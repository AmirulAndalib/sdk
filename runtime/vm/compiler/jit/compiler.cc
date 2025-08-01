// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "vm/compiler/jit/compiler.h"

#if !defined(DART_PRECOMPILED_RUNTIME)
#include "vm/code_patcher.h"
#include "vm/compiler/assembler/assembler.h"
#include "vm/compiler/assembler/disassembler.h"
#include "vm/compiler/backend/block_scheduler.h"
#include "vm/compiler/backend/branch_optimizer.h"
#include "vm/compiler/backend/constant_propagator.h"
#include "vm/compiler/backend/flow_graph.h"
#include "vm/compiler/backend/flow_graph_compiler.h"
#include "vm/compiler/backend/il_printer.h"
#include "vm/compiler/backend/inliner.h"
#include "vm/compiler/backend/linearscan.h"
#include "vm/compiler/backend/range_analysis.h"
#include "vm/compiler/backend/redundancy_elimination.h"
#include "vm/compiler/backend/type_propagator.h"
#include "vm/compiler/cha.h"
#include "vm/compiler/compiler_pass.h"
#include "vm/compiler/compiler_state.h"
#include "vm/compiler/ffi/callback.h"
#include "vm/compiler/frontend/flow_graph_builder.h"
#include "vm/compiler/frontend/kernel_to_il.h"
#include "vm/compiler/jit/jit_call_specializer.h"
#include "vm/dart_entry.h"
#include "vm/debugger.h"
#include "vm/deopt_instructions.h"
#include "vm/exceptions.h"
#include "vm/flags.h"
#include "vm/kernel.h"
#include "vm/longjump.h"
#include "vm/object.h"
#include "vm/object_store.h"
#include "vm/os.h"
#include "vm/parser.h"
#include "vm/regexp/regexp_assembler.h"
#include "vm/regexp/regexp_parser.h"
#include "vm/runtime_entry.h"
#include "vm/symbols.h"
#include "vm/tags.h"
#include "vm/timeline.h"
#include "vm/timer.h"
#endif

namespace dart {

DEFINE_FLAG(
    int,
    max_deoptimization_counter_threshold,
    16,
    "How many times we allow deoptimization before we disallow optimization.");
DEFINE_FLAG(charp,
            optimization_filter,
            nullptr,
            "Optimize only named function");
DEFINE_FLAG(bool, print_flow_graph, false, "Print the IR flow graph.");
DEFINE_FLAG(bool,
            print_flow_graph_optimized,
            false,
            "Print the IR flow graph when optimizing.");
DEFINE_FLAG(bool,
            print_ic_data_map,
            false,
            "Print the deopt-id to ICData map in optimizing compiler.");
DEFINE_FLAG(bool, print_code_source_map, false, "Print code source map.");
DEFINE_FLAG(bool,
            stress_test_background_compilation,
            false,
            "Keep background compiler running all the time");
DEFINE_FLAG(bool,
            stop_on_excessive_deoptimization,
            false,
            "Debugging: stops program if deoptimizing same function too often");
DEFINE_FLAG(bool, trace_compiler, false, "Trace compiler operations.");
DEFINE_FLAG(bool,
            trace_failed_optimization_attempts,
            false,
            "Traces all failed optimization attempts");
DEFINE_FLAG(bool,
            trace_optimizing_compiler,
            false,
            "Trace only optimizing compiler operations.");
DEFINE_FLAG(bool, trace_bailout, false, "Print bailout from ssa compiler.");

DECLARE_FLAG(bool, trace_failed_optimization_attempts);

static void PrecompilationModeHandler(bool value) {
  if (value) {
#if defined(TARGET_ARCH_IA32)
    FATAL("Precompilation not supported on IA32");
#endif

    FLAG_background_compilation = false;
    FLAG_enable_mirrors = false;
    FLAG_interpret_irregexp = true;
    FLAG_link_natives_lazily = true;
    FLAG_optimization_counter_threshold = -1;
    FLAG_polymorphic_with_deopt = false;
    FLAG_precompiled_mode = true;
    FLAG_reorder_basic_blocks = true;
    FLAG_use_field_guards = false;
    FLAG_use_cha_deopt = false;

#if !defined(PRODUCT) && !defined(DART_PRECOMPILED_RUNTIME)
    // Set flags affecting runtime accordingly for gen_snapshot.
    // These flags are constants with PRODUCT and DART_PRECOMPILED_RUNTIME.
    FLAG_deoptimize_alot = false;  // Used in some tests.
    FLAG_deoptimize_every = 0;     // Used in some tests.
    FLAG_use_osr = false;
#endif
  }
}

DEFINE_FLAG_HANDLER(PrecompilationModeHandler,
                    precompilation,
                    "Precompilation mode");

#ifndef DART_PRECOMPILED_RUNTIME

static FlowGraph* BuildIrregexpFunctionFlowGraph(
    Zone* zone,
    ParsedFunction* parsed_function,
    ZoneGrowableArray<const ICData*>* ic_data_array,
    intptr_t osr_id,
    bool optimized) {
  if (parsed_function->regexp_compile_data() == nullptr) {
    VMTagScope tagScope(parsed_function->thread(),
                        VMTag::kCompileParseRegExpTagId);
    RegExp& regexp = RegExp::Handle(parsed_function->function().regexp());

    const String& pattern = String::Handle(regexp.pattern());

    RegExpCompileData* compile_data = new (zone) RegExpCompileData();
    // Parsing failures are handled in the RegExp factory constructor.
    RegExpParser::ParseRegExp(pattern, regexp.flags(), compile_data);

    regexp.set_num_bracket_expressions(compile_data->capture_count);
    regexp.set_capture_name_map(compile_data->capture_name_map);
    if (compile_data->simple) {
      regexp.set_is_simple();
    } else {
      regexp.set_is_complex();
    }

    parsed_function->SetRegExpCompileData(compile_data);

    // Variables are allocated after compilation.
  }

  // Compile to the dart IR.
  RegExpEngine::CompilationResult result =
      RegExpEngine::CompileIR(parsed_function->regexp_compile_data(),
                              parsed_function, *ic_data_array, osr_id);
  if (result.error_message != nullptr) {
    Report::LongJump(LanguageError::Handle(
        LanguageError::New(String::Handle(String::New(result.error_message)))));
  }

  // Allocate variables now that we know the number of locals.
  parsed_function->AllocateIrregexpVariables(result.num_stack_locals);

  // When compiling for OSR, use a depth first search to find the OSR
  // entry and make graph entry jump to it instead of normal entry.
  // Catch entries are always considered reachable, even if they
  // become unreachable after OSR.
  if (osr_id != Compiler::kNoOSRDeoptId) {
    auto osr_result = result.graph_entry->FindOsrEntry(zone, result.num_blocks);
    // No try-catch in irregexps, so we can pass nullptr as flow_graph_builder.
    ASSERT(osr_result->try_entries_length() == 0);
    kernel::FlowGraphBuilder::RelinkToOsrEntry(/*builder=*/nullptr, osr_result);
  }
  PrologueInfo prologue_info(-1, -1);
  return new (zone)
      FlowGraph(*parsed_function, result.graph_entry, result.num_blocks,
                prologue_info, FlowGraph::CompilationModeFrom(optimized));
}

FlowGraph* Compiler::BuildFlowGraph(
    Zone* zone,
    ParsedFunction* parsed_function,
    ZoneGrowableArray<const ICData*>* ic_data_array,
    intptr_t osr_id,
    bool optimized) {
  if (parsed_function->function().IsIrregexpFunction()) {
    return BuildIrregexpFunctionFlowGraph(zone, parsed_function, ic_data_array,
                                          osr_id, optimized);
  }
  kernel::FlowGraphBuilder builder(parsed_function, ic_data_array,
                                   /* not building var desc */ nullptr,
                                   /* not inlining */ nullptr, optimized,
                                   osr_id);
  FlowGraph* graph = builder.BuildGraph();
  ASSERT(graph != nullptr);
  return graph;
}

bool Compiler::CanOptimizeFunction(Thread* thread, const Function& function) {
#if !defined(PRODUCT)
  if (thread->isolate_group()->debugger()->IsDebugging(thread, function)) {
    // We cannot set breakpoints and single step in optimized code,
    // so do not optimize the function. Bump usage counter down to avoid
    // repeatedly entering the runtime for an optimization attempt.
    function.SetUsageCounter(0);

    // If the optimization counter = 1, the unoptimized code will come back here
    // immediately, causing an infinite compilation loop. The compiler raises
    // the threshold for functions with breakpoints, so we drop the unoptimized
    // to force it to be recompiled.
    if (thread->isolate_group()->optimization_counter_threshold() < 2) {
      function.ClearCode();
    }
    return false;
  }
#endif
  if (function.deoptimization_counter() >=
      FLAG_max_deoptimization_counter_threshold) {
    if (FLAG_trace_failed_optimization_attempts ||
        FLAG_stop_on_excessive_deoptimization) {
      THR_Print("Too many deoptimizations: %s\n",
                function.ToFullyQualifiedCString());
      if (FLAG_stop_on_excessive_deoptimization) {
        FATAL("Stop on excessive deoptimization");
      }
    }
    // The function will not be optimized any longer. This situation can occur
    // mostly with small optimization counter thresholds.
    function.SetIsOptimizable(false);
    function.SetUsageCounter(INT32_MIN);
    return false;
  }
  if (FLAG_optimization_filter != nullptr) {
    // FLAG_optimization_filter is a comma-separated list of strings that are
    // matched against the fully-qualified function name.
    char* save_ptr;  // Needed for strtok_r.
    const char* function_name = function.ToFullyQualifiedCString();
    intptr_t len = strlen(FLAG_optimization_filter) + 1;  // Length with \0.
    char* filter = new char[len];
    strncpy(filter, FLAG_optimization_filter, len);  // strtok modifies arg 1.
    char* token = strtok_r(filter, ",", &save_ptr);
    bool found = false;
    while (token != nullptr) {
      if (strstr(function_name, token) != nullptr) {
        found = true;
        break;
      }
      token = strtok_r(nullptr, ",", &save_ptr);
    }
    delete[] filter;
    if (!found) {
      function.SetUsageCounter(INT32_MIN);
      return false;
    }
  }
  if (!function.IsOptimizable()) {
    // Huge methods (code size above --huge_method_cutoff_in_code_size) become
    // non-optimizable only after the code has been generated.
    if (FLAG_trace_failed_optimization_attempts) {
      THR_Print("Not optimizable: %s\n", function.ToFullyQualifiedCString());
    }
    function.SetUsageCounter(INT32_MIN);
    return false;
  }
  return true;
}

bool Compiler::IsBackgroundCompilation() {
  // For now: compilation in non mutator thread is the background compilation.
  return !Thread::Current()->IsDartMutatorThread();
}

class CompileParsedFunctionHelper : public ValueObject {
 public:
  CompileParsedFunctionHelper(ParsedFunction* parsed_function,
                              bool optimized,
                              intptr_t osr_id)
      : parsed_function_(parsed_function),
        optimized_(optimized),
        osr_id_(osr_id),
        thread_(Thread::Current()) {}

  CodePtr Compile();

 private:
  ParsedFunction* parsed_function() const { return parsed_function_; }
  bool optimized() const { return optimized_; }
  intptr_t osr_id() const { return osr_id_; }
  Thread* thread() const { return thread_; }
  IsolateGroup* isolate_group() const { return thread_->isolate_group(); }
  CodePtr FinalizeCompilation(compiler::Assembler* assembler,
                              FlowGraphCompiler* graph_compiler,
                              FlowGraph* flow_graph);

  ParsedFunction* parsed_function_;
  const bool optimized_;
  const intptr_t osr_id_;
  Thread* const thread_;

  DISALLOW_COPY_AND_ASSIGN(CompileParsedFunctionHelper);
};

CodePtr CompileParsedFunctionHelper::FinalizeCompilation(
    compiler::Assembler* assembler,
    FlowGraphCompiler* graph_compiler,
    FlowGraph* flow_graph) {
  ASSERT(!CompilerState::Current().is_aot());
  const Function& function = parsed_function()->function();

  // If another thread compiled and installed unoptmized code already,
  // skip installation.
  if (!optimized() && function.unoptimized_code() != Code::null()) {
    return function.unoptimized_code();
  }
  // If another thread compiled and installed optimized code for the
  // force-optimized function, skip installation.
  if (optimized() && function.ForceOptimize() && function.HasOptimizedCode()) {
    return function.CurrentCode();
  }
  Zone* const zone = thread()->zone();

  // CreateDeoptInfo uses the object pool and needs to be done before
  // FinalizeCode.
  Array& deopt_info_array = Array::Handle(zone, Object::empty_array().ptr());
  deopt_info_array = graph_compiler->CreateDeoptInfo(assembler);

  // Allocates instruction object. Since this occurs only at safepoint,
  // there can be no concurrent access to the instruction page.
  Code& code = Code::Handle(Code::FinalizeCode(
      graph_compiler, assembler, Code::PoolAttachment::kAttachPool, optimized(),
      /*stats=*/nullptr));
  code.set_is_optimized(optimized());
  code.set_owner(function);

  if (!function.IsOptimizable()) {
    // A function with huge unoptimized code can become non-optimizable
    // after generating unoptimized code.
    function.SetUsageCounter(INT32_MIN);
  }

  graph_compiler->FinalizePcDescriptors(code);
  code.set_deopt_info_array(deopt_info_array);

  graph_compiler->FinalizeStackMaps(code);
  graph_compiler->FinalizeVarDescriptors(code);
  graph_compiler->FinalizeExceptionHandlers(code);
  graph_compiler->FinalizeCatchEntryMovesMap(code);
  graph_compiler->FinalizeStaticCallTargetsTable(code);
  graph_compiler->FinalizeCodeSourceMap(code);

  if (function.ForceOptimize()) {
    ASSERT(optimized() && thread()->IsDartMutatorThread());
    code.set_is_force_optimized(true);
    function.AttachCode(code);
    function.SetWasCompiled(true);
  } else if (optimized()) {
    // We cannot execute generated code while installing code.
    ASSERT(Thread::Current()->OwnsGCSafepoint() ||
           (Thread::Current()->IsDartMutatorThread() &&
            IsolateGroup::Current()->ContainsOnlyOneIsolate()));
    // We are validating our CHA / field guard / ... assumptions. To prevent
    // another thread from concurrently changing them, we have to guarantee
    // mutual exclusion.
    DEBUG_ASSERT(
        IsolateGroup::Current()->program_lock()->IsCurrentThreadReader());

    const bool trace_compiler =
        FLAG_trace_compiler || FLAG_trace_optimizing_compiler;
    bool code_is_valid = true;
    if (flow_graph->parsed_function().guarded_fields()->Length() != 0) {
      const FieldSet* guarded_fields =
          flow_graph->parsed_function().guarded_fields();
      Field& original = Field::Handle();
      FieldSet::Iterator it = guarded_fields->GetIterator();
      while (const Field** field = it.Next()) {
        ASSERT(!(*field)->IsOriginal());
        original = (*field)->Original();
        if (!(*field)->IsConsistentWith(original)) {
          code_is_valid = false;
          if (trace_compiler) {
            THR_Print("--> FAIL: Field %s guarded state changed.",
                      (*field)->ToCString());
          }
          break;
        }
      }
    }

    if (!thread()->compiler_state().cha().IsConsistentWithCurrentHierarchy()) {
      code_is_valid = false;
      if (trace_compiler) {
        THR_Print("--> FAIL: Class hierarchy has new subclasses.");
      }
    }

    // Setting breakpoints at runtime could make a function non-optimizable.
    if (code_is_valid && Compiler::CanOptimizeFunction(thread(), function)) {
      if (osr_id() == Compiler::kNoOSRDeoptId) {
        function.InstallOptimizedCode(code);
      } else {
        // OSR is not compiled in background.
        ASSERT(!Compiler::IsBackgroundCompilation());
      }
      ASSERT(code.owner() == function.ptr());
    } else {
      code = Code::null();
    }
    if (function.usage_counter() < 0) {
      // Reset to 0 so that it can be recompiled if needed.
      if (code_is_valid) {
        function.SetUsageCounter(0);
      } else {
        // Trigger another optimization pass soon.
        function.SetUsageCounter(
            thread()->isolate_group()->optimization_counter_threshold() - 100);
      }
    }

    if (!code.IsNull()) {
      // The generated code was compiled under certain assumptions about
      // class hierarchy and field types. Register these dependencies
      // to ensure that the code will be deoptimized if they are violated.
      thread()->compiler_state().cha().RegisterDependencies(code);

      const FieldSet* guarded_fields =
          flow_graph->parsed_function().guarded_fields();
      Field& field = Field::Handle();
      FieldSet::Iterator it = guarded_fields->GetIterator();
      while (const Field** guarded_field = it.Next()) {
        field = (*guarded_field)->Original();
        field.RegisterDependentCode(code);
      }
    }
  } else {  // not optimized.
    function.SaveICDataMap(
        graph_compiler->deopt_id_to_ic_data(),
        Array::Handle(zone, graph_compiler->edge_counters_array()),
        flow_graph->coverage_array());
    function.set_unoptimized_code(code);
    function.AttachCode(code);
    function.SetWasCompiled(true);
    if (function.IsOptimizable() && (function.usage_counter() < 0)) {
      // While doing compilation in background, usage counter is set
      // to INT32_MIN. Reset counter so that function can be optimized further.
      function.SetUsageCounter(0);
    }
  }

  if (function.IsFfiCallbackTrampoline()) {
    compiler::ffi::SetFfiCallbackCode(thread(), function, code);
  }

  return code.ptr();
}

// Return null if bailed out.
CodePtr CompileParsedFunctionHelper::Compile() {
  ASSERT(!FLAG_precompiled_mode);
  const Function& function = parsed_function()->function();
  if (optimized() && !function.IsOptimizable()) {
    return Code::null();
  }
  Zone* const zone = thread()->zone();
  HANDLESCOPE(thread());
  EnterCompilerScope cs(thread());

  // We may reattempt compilation if the function needs to be assembled using
  // far branches on ARM. In the else branch of the setjmp call, done is set to
  // false, and use_far_branches is set to true if there is a longjmp from the
  // ARM assembler. In all other paths through this while loop, done is set to
  // true. use_far_branches is always false on ia32 and x64.
  volatile bool done = false;
  // volatile because the variable may be clobbered by a longjmp.
  volatile intptr_t far_branch_level = 0;

  Code* volatile result = &Code::ZoneHandle(zone);
  while (!done) {
    *result = Code::null();
    LongJumpScope jump(thread());
    if (DART_SETJMP(*jump.Set()) == 0) {
      FlowGraph* flow_graph = nullptr;
      ZoneGrowableArray<const ICData*>* ic_data_array = nullptr;

      CompilerState compiler_state(thread(), /*is_aot=*/false, optimized(),
                                   CompilerState::ShouldTrace(function));
      compiler_state.set_function(function);

      {
        // Extract type feedback before the graph is built, as the graph
        // builder uses it to attach it to nodes.
        ic_data_array = new (zone) ZoneGrowableArray<const ICData*>();

        // Clone ICData for background compilation so that it does not
        // change while compiling.
        const bool clone_ic_data = Compiler::IsBackgroundCompilation();
        function.RestoreICDataMap(ic_data_array, clone_ic_data);

        if (optimized()) {
          ASSERT(function.ic_data_array() != Array::null() ||
                 function.ForceOptimize());
        }

        if (FLAG_print_ic_data_map) {
          for (intptr_t i = 0; i < ic_data_array->length(); i++) {
            if ((*ic_data_array)[i] != nullptr) {
              THR_Print("%" Pd " ", i);
              FlowGraphPrinter::PrintICData(*(*ic_data_array)[i]);
            }
          }
        }

        TIMELINE_DURATION(thread(), CompilerVerbose, "BuildFlowGraph");
        flow_graph = Compiler::BuildFlowGraph(
            zone, parsed_function(), ic_data_array, osr_id(), optimized());
      }

      const bool print_flow_graph =
          (FLAG_print_flow_graph ||
           (optimized() && FLAG_print_flow_graph_optimized)) &&
          FlowGraphPrinter::ShouldPrint(function);

      if (print_flow_graph && !optimized()) {
        FlowGraphPrinter::PrintGraph("Unoptimized Compilation", flow_graph);
      }

      if (flow_graph->should_reorder_blocks()) {
        // Edge weights are indexed by blocks' preorder numbers. This means
        // we can't apply them to OSR graph because it does not have the same
        // structure as the original graph: it was mutated by RelinkToOsrEntry.
        if (osr_id() == Compiler::kNoOSRDeoptId) {
          TIMELINE_DURATION(thread(), CompilerVerbose,
                            "BlockScheduler::AssignEdgeWeights");
          BlockScheduler::AssignEdgeWeights(flow_graph);
        }
      }

      CompilerPassState pass_state(thread(), flow_graph);

      if (optimized()) {
        TIMELINE_DURATION(thread(), CompilerVerbose, "OptimizationPasses");

        JitCallSpecializer call_specializer(flow_graph);
        pass_state.call_specializer = &call_specializer;

        flow_graph = CompilerPass::RunPipeline(CompilerPass::kJIT, &pass_state);
      }

      compiler::ObjectPoolBuilder object_pool_builder;
      compiler::Assembler assembler(&object_pool_builder, far_branch_level);
      FlowGraphCompiler graph_compiler(&assembler, flow_graph,
                                       *parsed_function(), optimized(),
                                       ic_data_array);
      pass_state.graph_compiler = &graph_compiler;
      CompilerPass::GenerateCode(&pass_state);

      {
        TIMELINE_DURATION(thread(), CompilerVerbose, "FinalizeCompilation");

        auto install_code_fun = [&]() {
          *result =
              FinalizeCompilation(&assembler, &graph_compiler, flow_graph);
#if !defined(PRODUCT)
          // Isolate debuggers need to be notified of compiled function right
          // away as code is installed because there might be latent breakpoints
          // in compiled function, which have to be activated before functions
          // code is executed. Otherwise concurrently running isolates might
          // execute code before its patched and miss a need to pause at a
          // breakpoint.
          if (!result->IsNull()) {
            if (!function.HasOptimizedCode()) {
              thread()->isolate_group()->debugger()->NotifyCompilation(
                  function);
            }
          }
#endif
        };

        // Grab write program_lock outside of potential safepoint, that lock
        // can't be waited for inside the safepoint.
        // Initially read lock was added to guard direct_subclasses field
        // access.
        // Read lock was upgraded to write lock to guard dependent code updates.
        SafepointWriteRwLocker ml(thread(),
                                  thread()->isolate_group()->program_lock());
        // We have to ensure no mutators are running, because:
        //
        //   a) We allocate an instructions object, which might cause us to
        //      temporarily flip page protections (RX -> RW -> RX).
        //
        //   b) We have to ensure the code generated does not violate
        //      assumptions (e.g. CHA, field guards), the validation has to
        //      happen while mutator is stopped.
        //
        //   b) We update the [Function] object with a new [Code] which
        //      requires updating several pointers: We have to ensure all of
        //      those writes are observed atomically.
        //
        thread()->isolate_group()->RunWithStoppedMutators(install_code_fun);
      }
      if (!result->IsNull()) {
        // Must be called outside of safepoint.
        Code::NotifyCodeObservers(function, *result, optimized());

        if (FLAG_disassemble && FlowGraphPrinter::ShouldPrint(function)) {
          Disassembler::DisassembleCode(function, *result, optimized());
        } else if (FLAG_disassemble_optimized && optimized() &&
                   FlowGraphPrinter::ShouldPrint(function)) {
          Disassembler::DisassembleCode(function, *result, true);
        }
      }
      // Exit the loop and the function with the correct result value.
      done = true;
    } else {
      // We bailed out or we encountered an error.
      const Error& error = Error::Handle(thread()->StealStickyError());

      if (error.ptr() == Object::branch_offset_error().ptr()) {
        // Compilation failed due to an out of range branch offset in the
        // assembler. We try again (done = false) with far branches enabled.
        done = false;
        RELEASE_ASSERT(far_branch_level < 2);
        far_branch_level += 1;
      } else {
        // If the error isn't due to an out of range branch offset, we don't
        // try again (done = true).
        if (FLAG_trace_bailout) {
          THR_Print("%s\n", error.ToErrorCString());
        }
        if (!Compiler::IsBackgroundCompilation() && error.IsLanguageError() &&
            (LanguageError::Cast(error).kind() == Report::kBailout)) {
          // If is is not a background compilation, discard the error if it was
          // not a real error, but just a bailout. If we're it a background
          // compilation this will be dealt with in the caller.
        } else {
          // Otherwise, continue propagating unless we will try again.
          thread()->set_sticky_error(error);
        }
        done = true;
      }
    }
  }
  return result->ptr();
}

static ObjectPtr CompileFunctionHelper(const Function& function,
                                       bool optimized,
                                       intptr_t osr_id) {
  Thread* const thread = Thread::Current();
  NoActiveIsolateScope no_active_isolate(thread);

  ASSERT(!FLAG_precompiled_mode);
  ASSERT(!optimized || function.WasCompiled() || function.ForceOptimize());
  ASSERT(!function.is_declared_in_bytecode());
  LongJumpScope jump(thread);
  if (DART_SETJMP(*jump.Set()) == 0) {
    StackZone stack_zone(thread);
    Zone* const zone = stack_zone.GetZone();
    const bool trace_compiler =
        FLAG_trace_compiler || (FLAG_trace_optimizing_compiler && optimized);
    Timer per_compile_timer;
    per_compile_timer.Start();

    ParsedFunction* parsed_function = new (zone)
        ParsedFunction(thread, Function::ZoneHandle(zone, function.ptr()));
    if (trace_compiler) {
      const intptr_t token_size = function.SourceSize();
      THR_Print("Compiling %s%sfunction %s: '%s' @ token %s, size %" Pd "\n",
                (osr_id == Compiler::kNoOSRDeoptId ? "" : "osr "),
                (optimized ? "optimized " : ""),
                (Compiler::IsBackgroundCompilation() ? "(background)" : ""),
                function.ToFullyQualifiedCString(),
                function.token_pos().ToCString(), token_size);
    }

    CompileParsedFunctionHelper helper(parsed_function, optimized, osr_id);

    const Code& result = Code::Handle(helper.Compile());

    if (result.IsNull()) {
      const Error& error = Error::Handle(thread->StealStickyError());

      if (Compiler::IsBackgroundCompilation()) {
        // Try again later, background compilation may abort because of
        // state change during compilation.
        if (FLAG_trace_compiler) {
          THR_Print("Aborted background compilation: %s\n",
                    function.ToFullyQualifiedCString());
        }

        // We got an error during compilation.
        // If it was a bailout, then disable optimization.
        if (error.ptr() == Object::background_compilation_error().ptr()) {
          if (FLAG_trace_compiler) {
            THR_Print(
                "--> discarding background compilation for '%s' (will "
                "try to re-compile again later)\n",
                function.ToFullyQualifiedCString());
          }

          // Trigger another optimization pass soon.
          function.SetUsageCounter(
              thread->isolate_group()->optimization_counter_threshold() - 100);
          return Error::null();
        } else if (error.IsLanguageError() &&
                   LanguageError::Cast(error).kind() == Report::kBailout) {
          if (FLAG_trace_compiler) {
            THR_Print("--> disabling optimizations for '%s'\n",
                      function.ToFullyQualifiedCString());
          }
          function.SetIsOptimizable(false);
          return Error::null();
        } else {
          // The background compiler does not execute Dart code or handle
          // isolate messages.
          ASSERT(!error.IsUnwindError());
          return error.ptr();
        }
      }
      if (optimized) {
        if (error.IsLanguageError() &&
            LanguageError::Cast(error).kind() == Report::kBailout) {
          // Functions which cannot deoptimize should never bail out.
          ASSERT(!function.ForceOptimize());
          // Optimizer bailed out. Disable optimizations and never try again.
          if (trace_compiler) {
            THR_Print("--> disabling optimizations for '%s'\n",
                      function.ToFullyQualifiedCString());
          } else if (FLAG_trace_failed_optimization_attempts) {
            THR_Print("Cannot optimize: %s\n",
                      function.ToFullyQualifiedCString());
          }
          function.SetIsOptimizable(false);
          return Error::null();
        }
        return error.ptr();
      } else {
        ASSERT(!optimized);
        // The non-optimizing compiler can get an unhandled exception
        // due to OOM or Stack overflow errors, it should not however
        // bail out.
        ASSERT(error.IsUnhandledException() || error.IsUnwindError() ||
               (error.IsLanguageError() &&
                LanguageError::Cast(error).kind() != Report::kBailout));
        return error.ptr();
      }
      UNREACHABLE();
    }

    per_compile_timer.Stop();

    if (trace_compiler) {
      const auto& code = Code::Handle(function.CurrentCode());
      THR_Print("--> '%s' entry: %#" Px " size: %" Pd " time: %" Pd64 " us\n",
                function.ToFullyQualifiedCString(), code.PayloadStart(),
                code.Size(), per_compile_timer.TotalElapsedTime());
    }

    return result.ptr();
  } else {
    Thread* const thread = Thread::Current();
    StackZone stack_zone(thread);
    // We got an error during compilation or it is a bailout from background
    // compilation (e.g., during parsing with EnsureIsFinalized).
    const Error& error = Error::Handle(thread->StealStickyError());
    if (error.ptr() == Object::background_compilation_error().ptr()) {
      // Exit compilation, retry it later.
      if (FLAG_trace_bailout) {
        THR_Print("Aborted background compilation: %s\n",
                  function.ToFullyQualifiedCString());
      }
      return Object::null();
    }
    // Do not attempt to optimize functions that can cause errors.
    function.set_is_optimizable(false);
    return error.ptr();
  }
  UNREACHABLE();
  return Object::null();
}

ObjectPtr Compiler::CompileFunction(Thread* thread, const Function& function) {
#if defined(DART_PRECOMPILER) && !defined(TARGET_ARCH_IA32)
  RELEASE_ASSERT(!FLAG_precompiled_mode);
#endif

#if defined(DART_PRECOMPILED_RUNTIME)
  FATAL("Precompilation missed function %s (%s, %s)\n",
        function.ToLibNamePrefixedQualifiedCString(),
        function.token_pos().ToCString(),
        Function::KindToCString(function.kind()));
#endif  // defined(DART_PRECOMPILED_RUNTIME)

  VMTagScope tag_scope(thread, VMTag::kCompileUnoptimizedTagId);
  NoReloadScope no_reload_scope(thread);
#if defined(SUPPORT_TIMELINE)
  const char* event_name;
  if (IsBackgroundCompilation()) {
    event_name = "CompileFunctionUnoptimizedBackground";
  } else {
    event_name = "CompileFunction";
  }
  TIMELINE_FUNCTION_COMPILATION_DURATION(thread, event_name, function);
#endif  // defined(SUPPORT_TIMELINE)

  const bool optimized = function.ForceOptimize();
  return CompileFunctionHelper(function, optimized, kNoOSRDeoptId);
}

ErrorPtr Compiler::EnsureUnoptimizedCode(Thread* thread,
                                         const Function& function) {
  ASSERT(!function.ForceOptimize());
  if (function.unoptimized_code() != Object::null()) {
    return Error::null();
  }
  Code& original_code = Code::ZoneHandle(thread->zone());
  if (function.HasCode()) {
    original_code = function.CurrentCode();
  }
  const bool optimized = function.ForceOptimize();
  const Object& result =
      Object::Handle(CompileFunctionHelper(function, optimized, kNoOSRDeoptId));
  if (result.IsError()) {
    return Error::Cast(result).ptr();
  }
  // Since CompileFunctionHelper replaces the current code, re-attach the
  // the original code if the function was already compiled.
  if (!original_code.IsNull() && result.ptr() == function.CurrentCode() &&
      !original_code.IsDisabled()) {
    function.AttachCode(original_code);
  }
  ASSERT(function.unoptimized_code() != Object::null());
  ASSERT(function.unoptimized_code() == result.ptr());
  if (FLAG_trace_compiler) {
    THR_Print("Ensure unoptimized code for %s\n", function.ToCString());
  }
  return Error::null();
}

ObjectPtr Compiler::CompileOptimizedFunction(Thread* thread,
                                             const Function& function,
                                             intptr_t osr_id) {
  VMTagScope tag_scope(thread, VMTag::kCompileOptimizedTagId);
  NoReloadScope no_reload_scope(thread);

#if defined(SUPPORT_TIMELINE)
  const char* event_name;
  if (osr_id != kNoOSRDeoptId) {
    event_name = "CompileFunctionOptimizedOSR";
  } else if (IsBackgroundCompilation()) {
    event_name = "CompileFunctionOptimizedBackground";
  } else {
    event_name = "CompileFunctionOptimized";
  }
  TIMELINE_FUNCTION_COMPILATION_DURATION(thread, event_name, function);
#endif  // defined(SUPPORT_TIMELINE)

  return CompileFunctionHelper(function, /* optimized = */ true, osr_id);
}

void Compiler::ComputeLocalVarDescriptors(const Code& code) {
  ASSERT(!code.is_optimized());
  ASSERT(!FLAG_precompiled_mode);
  const Function& function = Function::Handle(code.function());
  // IsIrregexpFunction have eager var descriptors generation.
  ASSERT(!function.IsIrregexpFunction());
  // In background compilation, parser can produce 'errors": bailouts
  // if state changed while compiling in background.
  Thread* thread = Thread::Current();
  Zone* zone = thread->zone();
  CompilerState state(thread, /*is_aot=*/false, /*is_optimizing=*/false);
  LongJumpScope jump(thread);
  if (DART_SETJMP(*jump.Set()) == 0) {
    ParsedFunction* parsed_function =
        new ParsedFunction(thread, Function::ZoneHandle(zone, function.ptr()));
    ZoneGrowableArray<const ICData*>* ic_data_array =
        new ZoneGrowableArray<const ICData*>();
    ZoneGrowableArray<intptr_t>* context_level_array =
        new ZoneGrowableArray<intptr_t>();

    kernel::FlowGraphBuilder builder(
        parsed_function, ic_data_array, context_level_array,
        /* not inlining */ nullptr, false, Compiler::kNoOSRDeoptId);
    builder.BuildGraph();

    auto& var_descs = LocalVarDescriptors::Handle(zone);

    var_descs = parsed_function->scope()->GetVarDescriptors(
        function, context_level_array);

    ASSERT(!var_descs.IsNull());
    code.set_var_descriptors(var_descs);
  } else {
    // Only possible with background compilation.
    ASSERT(Compiler::IsBackgroundCompilation());
  }
}

ErrorPtr Compiler::CompileAllFunctions(const Class& cls) {
  Thread* thread = Thread::Current();
  Zone* zone = thread->zone();
  Object& result = Object::Handle(zone);
  // We don't expect functions() to change as the class was finalized.
  ASSERT(cls.is_finalized());
  Array& functions = Array::Handle(zone, cls.current_functions());
  Function& func = Function::Handle(zone);
  // Compile all the regular functions.
  for (int i = 0; i < functions.Length(); i++) {
    func ^= functions.At(i);
    ASSERT(!func.IsNull());
    if (!func.HasCode() && !func.is_abstract()) {
      result = CompileFunction(thread, func);
      if (result.IsError()) {
        return Error::Cast(result).ptr();
      }
      ASSERT(!result.IsNull());
    }
  }
  return Error::null();
}

void Compiler::AbortBackgroundCompilation(intptr_t deopt_id, const char* msg) {
  if (FLAG_trace_compiler) {
    THR_Print("ABORT background compilation: %s\n", msg);
  }
#if !defined(PRODUCT)
  TimelineStream* stream = Timeline::GetCompilerStream();
  ASSERT(stream != nullptr);
  TimelineEvent* event = stream->StartEvent();
  if (event != nullptr) {
    event->Instant("AbortBackgroundCompilation");
    event->SetNumArguments(1);
    event->CopyArgument(0, "reason", msg);
    event->Complete();
  }
#endif  // !defined(PRODUCT)
  ASSERT(Compiler::IsBackgroundCompilation());
  Thread::Current()->long_jump_base()->Jump(
      deopt_id, Object::background_compilation_error());
}

// C-heap allocated background compilation queue element.
class QueueElement {
 public:
  explicit QueueElement(const Function& function)
      : next_(nullptr), function_(function.ptr()) {}

  virtual ~QueueElement() {
    next_ = nullptr;
    function_ = Function::null();
  }

  FunctionPtr Function() const { return function_; }

  void set_next(QueueElement* elem) { next_ = elem; }
  QueueElement* next() const { return next_; }

  ObjectPtr function() const { return function_; }
  ObjectPtr* function_untag() {
    return reinterpret_cast<ObjectPtr*>(&function_);
  }

 private:
  QueueElement* next_;
  FunctionPtr function_;

  DISALLOW_COPY_AND_ASSIGN(QueueElement);
};

// Allocated in C-heap. Handles both input and output of background compilation.
// It implements a FIFO queue, using Peek, Add, Remove operations.
class BackgroundCompilationQueue {
 public:
  BackgroundCompilationQueue() : first_(nullptr), last_(nullptr) {}
  virtual ~BackgroundCompilationQueue() { Clear(); }

  void VisitObjectPointers(ObjectPointerVisitor* visitor) {
    ASSERT(visitor != nullptr);
    QueueElement* p = first_;
    while (p != nullptr) {
      visitor->VisitPointer(p->function_untag());
      p = p->next();
    }
  }

  bool IsEmpty() const { return first_ == nullptr; }

  void Add(QueueElement* value) {
    ASSERT(value != nullptr);
    ASSERT(value->next() == nullptr);
    if (first_ == nullptr) {
      first_ = value;
      ASSERT(last_ == nullptr);
    } else {
      ASSERT(last_ != nullptr);
      last_->set_next(value);
    }
    last_ = value;
    ASSERT(first_ != nullptr && last_ != nullptr);
  }

  QueueElement* Peek() const { return first_; }

  FunctionPtr PeekFunction() const {
    QueueElement* e = Peek();
    if (e == nullptr) {
      return Function::null();
    } else {
      return e->Function();
    }
  }

  QueueElement* Remove() {
    ASSERT(first_ != nullptr);
    QueueElement* result = first_;
    first_ = first_->next();
    if (first_ == nullptr) {
      last_ = nullptr;
    }
    return result;
  }

  bool ContainsObj(const Object& obj) const {
    QueueElement* p = first_;
    while (p != nullptr) {
      if (p->function() == obj.ptr()) {
        return true;
      }
      p = p->next();
    }
    return false;
  }

  void Clear() {
    while (!IsEmpty()) {
      QueueElement* e = Remove();
      delete e;
    }
    ASSERT((first_ == nullptr) && (last_ == nullptr));
  }

 private:
  QueueElement* first_;
  QueueElement* last_;

  DISALLOW_COPY_AND_ASSIGN(BackgroundCompilationQueue);
};

class BackgroundCompilerTask : public ThreadPool::Task {
 public:
  explicit BackgroundCompilerTask(BackgroundCompiler* background_compiler)
      : background_compiler_(background_compiler) {}
  virtual ~BackgroundCompilerTask() {}

 private:
  virtual void Run() { background_compiler_->Run(); }

  BackgroundCompiler* background_compiler_;

  DISALLOW_COPY_AND_ASSIGN(BackgroundCompilerTask);
};

BackgroundCompiler::BackgroundCompiler(IsolateGroup* isolate_group)
    : isolate_group_(isolate_group),
      monitor_(),
      function_queue_(new BackgroundCompilationQueue()),
      running_(false),
      done_(true),
      disabled_depth_(0) {}

// Fields all deleted in ::Stop; here clear them.
BackgroundCompiler::~BackgroundCompiler() {
  delete function_queue_;
}

void BackgroundCompiler::Run() {
  Thread::EnterIsolateGroupAsHelper(isolate_group_, Thread::kCompilerTask,
                                    /*bypass_safepoint=*/false);
  {
    Thread* thread = Thread::Current();
    StackZone stack_zone(thread);
    Zone* zone = stack_zone.GetZone();
    HANDLESCOPE(thread);
    Function& function = Function::Handle(zone);
    QueueElement* element = nullptr;
    {
      SafepointMonitorLocker ml(&monitor_);
      if (running_ && !function_queue()->IsEmpty()) {
        element = function_queue()->Remove();
        function ^= element->function();
      }
    }
    if (element != nullptr) {
      delete element;
      Compiler::CompileOptimizedFunction(thread, function,
                                         Compiler::kNoOSRDeoptId);

      // If an optimizable method is not optimized, put it back on
      // the background queue (unless it was passed to foreground).
      if ((!function.HasOptimizedCode() && function.IsOptimizable()) ||
          FLAG_stress_test_background_compilation) {
        if (Compiler::CanOptimizeFunction(thread, function)) {
          SafepointMonitorLocker ml(&monitor_);
          if (running_) {
            QueueElement* repeat_qelem = new QueueElement(function);
            function_queue()->Add(repeat_qelem);
          }
        }
      }
    }
  }
  Thread::ExitIsolateGroupAsHelper(/*bypass_safepoint=*/false);
  {
    MonitorLocker ml(&monitor_);
    if (running_ && !function_queue()->IsEmpty() &&
        Dart::thread_pool()->Run<BackgroundCompilerTask>(this)) {
      // Successfully scheduled a new task.
    } else {
      // Background compiler done. This notification must happen after the
      // thread leaves to group to avoid a shutdown race with the thread
      // registry.
      running_ = false;
      done_ = true;
      ml.NotifyAll();
    }
  }
}

bool BackgroundCompiler::EnqueueCompilation(const Function& function) {
  Thread* thread = Thread::Current();
  ASSERT(thread->IsDartMutatorThread());
  ASSERT(thread->CanAcquireSafepointLocks());

  SafepointMonitorLocker ml(&monitor_);
  if (disabled_depth_ > 0) return false;
  if (!running_ && done_) {
    running_ = true;
    done_ = false;
    // If we ever wanted to run the BG compiler on the
    // `IsolateGroup::mutator_pool()` we would need to ensure the BG compiler
    // stops when it's idle - otherwise the [MutatorThreadPool]-based idle
    // notification would not work anymore.
    if (!Dart::thread_pool()->Run<BackgroundCompilerTask>(this)) {
      running_ = false;
      done_ = true;
      return false;
    }
  }

  ASSERT(running_);
  if (function_queue()->ContainsObj(function)) {
    return true;
  }
  QueueElement* elem = new QueueElement(function);
  function_queue()->Add(elem);
  ml.NotifyAll();
  return true;
}

void BackgroundCompiler::VisitPointers(ObjectPointerVisitor* visitor) {
  function_queue_->VisitObjectPointers(visitor);
}

void BackgroundCompiler::Stop() {
  Thread* thread = Thread::Current();
  ASSERT(thread->isolate() == nullptr || !thread->BypassSafepoints());
  ASSERT(thread->CanAcquireSafepointLocks());

  SafepointMonitorLocker ml(&monitor_);
  StopLocked(thread, &ml);
}

void BackgroundCompiler::StopLocked(Thread* thread,
                                    SafepointMonitorLocker* locker) {
  running_ = false;
  function_queue_->Clear();
  while (!done_) {
    locker->Wait();
  }
}

void BackgroundCompiler::Enable() {
  Thread* thread = Thread::Current();
  ASSERT(!thread->BypassSafepoints());
  ASSERT(thread->CanAcquireSafepointLocks());

  SafepointMonitorLocker ml(&monitor_);
  disabled_depth_--;
  if (disabled_depth_ < 0) {
    FATAL("Mismatched number of calls to BackgroundCompiler::Enable/Disable.");
  }
}

void BackgroundCompiler::Disable() {
  Thread* thread = Thread::Current();
  ASSERT(!thread->BypassSafepoints());
  ASSERT(thread->CanAcquireSafepointLocks());

  SafepointMonitorLocker ml(&monitor_);
  disabled_depth_++;
  if (done_) return;
  StopLocked(thread, &ml);
}

#else  // DART_PRECOMPILED_RUNTIME

bool Compiler::IsBackgroundCompilation() {
  return false;
}

bool Compiler::CanOptimizeFunction(Thread* thread, const Function& function) {
  UNREACHABLE();
  return false;
}

ObjectPtr Compiler::CompileFunction(Thread* thread, const Function& function) {
  FATAL("Attempt to compile function %s", function.ToFullyQualifiedCString());
  return Error::null();
}

ErrorPtr Compiler::EnsureUnoptimizedCode(Thread* thread,
                                         const Function& function) {
  FATAL("Attempt to compile function %s", function.ToFullyQualifiedCString());
  return Error::null();
}

ObjectPtr Compiler::CompileOptimizedFunction(Thread* thread,
                                             const Function& function,
                                             intptr_t osr_id) {
  FATAL("Attempt to compile function %s", function.ToFullyQualifiedCString());
  return Error::null();
}

void Compiler::ComputeLocalVarDescriptors(const Code& code) {
  UNREACHABLE();
}

ErrorPtr Compiler::CompileAllFunctions(const Class& cls) {
  FATAL("Attempt to compile class %s", cls.ToCString());
  return Error::null();
}

void Compiler::AbortBackgroundCompilation(intptr_t deopt_id, const char* msg) {
  UNREACHABLE();
}

bool BackgroundCompiler::EnqueueCompilation(const Function& function) {
  UNREACHABLE();
  return false;
}

void BackgroundCompiler::VisitPointers(ObjectPointerVisitor* visitor) {
  UNREACHABLE();
}

void BackgroundCompiler::Stop() {
  UNREACHABLE();
}

void BackgroundCompiler::Enable() {
  // NOP
}

void BackgroundCompiler::Disable() {
  // NOP
}

#endif  // DART_PRECOMPILED_RUNTIME

}  // namespace dart
