// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
#include "vm/compiler/jit/jit_call_specializer.h"

#include "vm/bit_vector.h"
#include "vm/compiler/backend/branch_optimizer.h"
#include "vm/compiler/backend/flow_graph_compiler.h"
#include "vm/compiler/backend/il.h"
#include "vm/compiler/backend/il_printer.h"
#include "vm/compiler/backend/inliner.h"
#include "vm/compiler/backend/range_analysis.h"
#include "vm/compiler/cha.h"
#include "vm/compiler/frontend/flow_graph_builder.h"
#include "vm/compiler/jit/compiler.h"
#include "vm/cpu.h"
#include "vm/dart_entry.h"
#include "vm/exceptions.h"
#include "vm/hash_map.h"
#include "vm/object_store.h"
#include "vm/parser.h"
#include "vm/resolver.h"
#include "vm/scopes.h"
#include "vm/stack_frame.h"
#include "vm/symbols.h"

namespace dart {

// Quick access to the current zone.
#define Z (zone())

JitCallSpecializer::JitCallSpecializer(FlowGraph* flow_graph)
    : CallSpecializer(flow_graph,
                      CompilerState::Current().should_clone_fields()) {}

bool JitCallSpecializer::IsAllowedForInlining(intptr_t deopt_id) const {
  return true;
}

bool JitCallSpecializer::TryOptimizeStaticCallUsingStaticTypes(
    StaticCallInstr* call) {
  return false;
}

void JitCallSpecializer::ReplaceWithStaticCall(InstanceCallInstr* instr,
                                               const Function& target,
                                               intptr_t call_count) {
  StaticCallInstr* call =
      StaticCallInstr::FromCall(Z, instr, target, call_count);
  const CallTargets& targets = instr->Targets();
  if (targets.IsMonomorphic() && targets.MonomorphicExactness().IsExact()) {
    if (targets.MonomorphicExactness().IsTriviallyExact()) {
      flow_graph()->AddExactnessGuard(instr, targets.MonomorphicReceiverCid());
    }
    call->set_entry_kind(Code::EntryKind::kUnchecked);
  }
  instr->ReplaceWith(call, current_iterator());
}

// Tries to optimize instance call by replacing it with a faster instruction
// (e.g, binary op, field load, ..).
// TODO(dartbug.com/30635) Evaluate how much this can be shared with
// AotCallSpecializer.
void JitCallSpecializer::VisitInstanceCall(InstanceCallInstr* instr) {
  const CallTargets& targets = instr->Targets();
  if (targets.is_empty()) {
    return;  // No feedback.
  }

  const Token::Kind op_kind = instr->token_kind();

  // Type test is special as it always gets converted into inlined code.
  if (Token::IsTypeTestOperator(op_kind)) {
    ReplaceWithInstanceOf(instr);
    return;
  }

  if (op_kind == Token::kEQ && TryReplaceWithEqualityOp(instr, op_kind)) {
    return;
  }

  if (Token::IsRelationalOperator(op_kind) &&
      TryReplaceWithRelationalOp(instr, op_kind)) {
    return;
  }

  if (Token::IsBinaryOperator(op_kind) &&
      TryReplaceWithBinaryOp(instr, op_kind)) {
    return;
  }
  if (Token::IsUnaryOperator(op_kind) &&
      TryReplaceWithUnaryOp(instr, op_kind)) {
    return;
  }
  if ((op_kind == Token::kGET) && TryInlineInstanceGetter(instr)) {
    return;
  }
  if ((op_kind == Token::kSET) && TryInlineInstanceSetter(instr)) {
    return;
  }
  if (TryInlineInstanceMethod(instr)) {
    return;
  }

  bool has_one_target = targets.HasSingleTarget();
  if (has_one_target) {
    // Check if the single target is a polymorphic target, if it is,
    // we don't have one target.
    const Function& target = targets.FirstTarget();
    if (target.recognized_kind() == MethodRecognizer::kObjectRuntimeType) {
      has_one_target = PolymorphicInstanceCallInstr::ComputeRuntimeType(
                           targets) != Type::null();
    } else {
      has_one_target = !target.is_polymorphic_target() &&
                       !target.IsDynamicallyOverridden() &&
                       !target.is_declared_in_bytecode();
    }
  }

  if (has_one_target) {
    const Function& target = targets.FirstTarget();
    if (flow_graph()->CheckForInstanceCall(instr, target.kind()) ==
        FlowGraph::ToCheck::kNoCheck) {
      ReplaceWithStaticCall(instr, target, targets.AggregateCallCount());
      return;
    }
  }

  // If there is only one target we can make this into a deopting class check,
  // followed by a call instruction that does not check the class of the
  // receiver.  This enables a lot of optimizations because after the class
  // check we can probably inline the call and not worry about side effects.
  // However, this can fall down if new receiver classes arrive at this call
  // site after we generated optimized code.  This causes a deopt, and after a
  // few deopts we won't optimize this function any more at all.  Therefore for
  // very polymorphic sites we don't make this optimization, keeping it as a
  // regular checked PolymorphicInstanceCall, which falls back to the slow but
  // non-deopting megamorphic call stub when it sees new receiver classes.
  if (has_one_target && FLAG_polymorphic_with_deopt &&
      (!instr->ic_data()->HasDeoptReason(ICData::kDeoptCheckClass) ||
       targets.length() <= FLAG_max_polymorphic_checks)) {
    // Type propagation has not run yet, we cannot eliminate the check.
    AddReceiverCheck(instr);

    // Call can still deoptimize, do not detach environment from instr.
    const Function& target = targets.FirstTarget();
    ReplaceWithStaticCall(instr, target, targets.AggregateCallCount());
  } else {
    PolymorphicInstanceCallInstr* call =
        PolymorphicInstanceCallInstr::FromCall(Z, instr, targets,
                                               /* complete = */ false);
    instr->ReplaceWith(call, current_iterator());
  }
}

// Replace generic context allocation or cloning with a sequence of inlined
// allocation and explicit initializing stores.
// If context_value is not nullptr then newly allocated context is a populated
// with values copied from it, otherwise it is initialized with null.
void JitCallSpecializer::LowerContextAllocation(
    Definition* alloc,
    const ZoneGrowableArray<const Slot*>& context_variables,
    Value* context_value) {
  ASSERT(alloc->IsAllocateContext() || alloc->IsCloneContext());

  AllocateUninitializedContextInstr* replacement =
      new AllocateUninitializedContextInstr(
          alloc->source(), context_variables.length(), alloc->deopt_id());
  alloc->ReplaceWith(replacement, current_iterator());

  Instruction* cursor = replacement;

  Value* initial_value;
  if (context_value != nullptr) {
    LoadFieldInstr* load =
        new (Z) LoadFieldInstr(context_value->CopyWithType(Z),
                               Slot::Context_parent(), alloc->source());
    flow_graph()->InsertAfter(cursor, load, nullptr, FlowGraph::kValue);
    cursor = load;
    initial_value = new (Z) Value(load);
  } else {
    initial_value = new (Z) Value(flow_graph()->constant_null());
  }
  StoreFieldInstr* store = new (Z) StoreFieldInstr(
      Slot::Context_parent(), new (Z) Value(replacement), initial_value,
      kNoStoreBarrier, alloc->source(), StoreFieldInstr::Kind::kInitializing);
  flow_graph()->InsertAfter(cursor, store, nullptr, FlowGraph::kEffect);
  cursor = replacement;

  for (auto& slot : context_variables) {
    if (context_value != nullptr) {
      LoadFieldInstr* load = new (Z) LoadFieldInstr(
          context_value->CopyWithType(Z), *slot, alloc->source());
      flow_graph()->InsertAfter(cursor, load, nullptr, FlowGraph::kValue);
      cursor = load;
      initial_value = new (Z) Value(load);
    } else {
      initial_value = new (Z) Value(flow_graph()->constant_null());
    }

    store = new (Z) StoreFieldInstr(
        *slot, new (Z) Value(replacement), initial_value, kNoStoreBarrier,
        alloc->source(), StoreFieldInstr::Kind::kInitializing);
    flow_graph()->InsertAfter(cursor, store, nullptr, FlowGraph::kEffect);
    cursor = store;
  }
}

void JitCallSpecializer::VisitAllocateContext(AllocateContextInstr* instr) {
  LowerContextAllocation(instr, instr->context_slots(), nullptr);
}

void JitCallSpecializer::VisitCloneContext(CloneContextInstr* instr) {
  LowerContextAllocation(instr, instr->context_slots(), instr->context_value());
}

}  // namespace dart
