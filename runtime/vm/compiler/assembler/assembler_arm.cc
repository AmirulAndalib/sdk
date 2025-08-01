// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "vm/globals.h"  // NOLINT
#if defined(TARGET_ARCH_ARM)

#define SHOULD_NOT_INCLUDE_RUNTIME

#include "vm/class_id.h"
#include "vm/compiler/assembler/assembler.h"
#include "vm/compiler/backend/locations.h"
#include "vm/cpu.h"
#include "vm/instructions.h"
#include "vm/tags.h"

// For use by LR related macros (e.g. CLOBBERS_LR).
#define __ this->

namespace dart {

DECLARE_FLAG(bool, check_code_pointer);
DECLARE_FLAG(bool, precompiled_mode);

namespace compiler {

Assembler::Assembler(ObjectPoolBuilder* object_pool_builder,
                     intptr_t far_branch_level)
    : AssemblerBase(object_pool_builder),
      use_far_branches_(far_branch_level != 0),
      constant_pool_allowed_(false) {
  generate_invoke_write_barrier_wrapper_ = [&](Condition cond, Register reg) {
    Call(
        Address(THR, target::Thread::write_barrier_wrappers_thread_offset(reg)),
        cond);
  };
  generate_invoke_array_write_barrier_ = [&](Condition cond) {
    Call(Address(THR, target::Thread::array_write_barrier_entry_point_offset()),
         cond);
  };
}

uint32_t Address::encoding3() const {
  if (kind_ == Immediate) {
    uint32_t offset = encoding_ & kOffset12Mask;
    ASSERT(offset < 256);
    return (encoding_ & ~kOffset12Mask) | B22 | ((offset & 0xf0) << 4) |
           (offset & 0xf);
  }
  ASSERT(kind_ == IndexRegister);
  return encoding_;
}

uint32_t Address::vencoding() const {
  ASSERT(kind_ == Immediate);
  uint32_t offset = encoding_ & kOffset12Mask;
  ASSERT(offset < (1 << 10));           // In the range 0 to +1020.
  ASSERT(Utils::IsAligned(offset, 4));  // Multiple of 4.
  int mode = encoding_ & ((8 | 4 | 1) << 21);
  ASSERT((mode == Offset) || (mode == NegOffset));
  uint32_t vencoding = (encoding_ & (0xf << kRnShift)) | (offset >> 2);
  if (mode == Offset) {
    vencoding |= 1 << 23;
  }
  return vencoding;
}

void Assembler::Emit(int32_t value) {
  AssemblerBuffer::EnsureCapacity ensured(&buffer_);
  buffer_.Emit<int32_t>(value);
}

void Assembler::EmitType01(Condition cond,
                           int type,
                           Opcode opcode,
                           int set_cc,
                           Register rn,
                           Register rd,
                           Operand o) {
  ASSERT(rd != kNoRegister);
  ASSERT(cond != kNoCondition);
  int32_t encoding =
      static_cast<int32_t>(cond) << kConditionShift | type << kTypeShift |
      static_cast<int32_t>(opcode) << kOpcodeShift | set_cc << kSShift |
      ArmEncode::Rn(rn) | ArmEncode::Rd(rd) | o.encoding();
  Emit(encoding);
}

void Assembler::EmitType5(Condition cond, int32_t offset, bool link) {
  ASSERT(cond != kNoCondition);
  int32_t encoding = static_cast<int32_t>(cond) << kConditionShift |
                     5 << kTypeShift | (link ? 1 : 0) << kLinkShift;
  BailoutIfInvalidBranchOffset(offset);
  Emit(Assembler::EncodeBranchOffset(offset, encoding));
}

void Assembler::EmitMemOp(Condition cond,
                          bool load,
                          bool byte,
                          Register rd,
                          Address ad) {
  ASSERT(rd != kNoRegister);
  ASSERT(cond != kNoCondition);
  // Unpredictable, illegal on some microarchitectures.
  ASSERT(!ad.has_writeback() || (ad.rn() != rd));

  int32_t encoding = (static_cast<int32_t>(cond) << kConditionShift) | B26 |
                     (ad.kind() == Address::Immediate ? 0 : B25) |
                     (load ? L : 0) | (byte ? B : 0) | ArmEncode::Rd(rd) |
                     ad.encoding();
  Emit(encoding);
}

void Assembler::EmitMemOpAddressMode3(Condition cond,
                                      int32_t mode,
                                      Register rd,
                                      Address ad) {
  ASSERT(rd != kNoRegister);
  ASSERT(cond != kNoCondition);
  // Unpredictable, illegal on some microarchitectures.
  ASSERT(!ad.has_writeback() || (ad.rn() != rd));

  int32_t encoding = (static_cast<int32_t>(cond) << kConditionShift) | mode |
                     ArmEncode::Rd(rd) | ad.encoding3();
  Emit(encoding);
}

void Assembler::EmitMultiMemOp(Condition cond,
                               BlockAddressMode am,
                               bool load,
                               Register base,
                               RegList regs) {
  ASSERT(base != kNoRegister);
  ASSERT(cond != kNoCondition);
  // Unpredictable, illegal on some microarchitectures.
  ASSERT(!Address::has_writeback(am) || !(regs & (1 << base)));
  int32_t encoding = (static_cast<int32_t>(cond) << kConditionShift) | B27 |
                     am | (load ? L : 0) | ArmEncode::Rn(base) | regs;
  Emit(encoding);
}

void Assembler::EmitShiftImmediate(Condition cond,
                                   Shift opcode,
                                   Register rd,
                                   Register rm,
                                   Operand o) {
  ASSERT(cond != kNoCondition);
  ASSERT(o.type() == 1);
  int32_t encoding = static_cast<int32_t>(cond) << kConditionShift |
                     static_cast<int32_t>(MOV) << kOpcodeShift |
                     ArmEncode::Rd(rd) | o.encoding() << kShiftImmShift |
                     static_cast<int32_t>(opcode) << kShiftShift |
                     static_cast<int32_t>(rm);
  Emit(encoding);
}

void Assembler::EmitShiftRegister(Condition cond,
                                  Shift opcode,
                                  Register rd,
                                  Register rm,
                                  Operand o) {
  ASSERT(cond != kNoCondition);
  ASSERT(o.type() == 0);
  int32_t encoding = static_cast<int32_t>(cond) << kConditionShift |
                     static_cast<int32_t>(MOV) << kOpcodeShift |
                     ArmEncode::Rd(rd) | o.encoding() << kShiftRegisterShift |
                     static_cast<int32_t>(opcode) << kShiftShift | B4 |
                     static_cast<int32_t>(rm);
  Emit(encoding);
}

void Assembler::and_(Register rd, Register rn, Operand o, Condition cond) {
  EmitType01(cond, o.type(), AND, 0, rn, rd, o);
}

void Assembler::ands(Register rd, Register rn, Operand o, Condition cond) {
  EmitType01(cond, o.type(), AND, 1, rn, rd, o);
}

void Assembler::eor(Register rd, Register rn, Operand o, Condition cond) {
  EmitType01(cond, o.type(), EOR, 0, rn, rd, o);
}

void Assembler::sub(Register rd, Register rn, Operand o, Condition cond) {
  EmitType01(cond, o.type(), SUB, 0, rn, rd, o);
}

void Assembler::rsb(Register rd, Register rn, Operand o, Condition cond) {
  EmitType01(cond, o.type(), RSB, 0, rn, rd, o);
}

void Assembler::rsbs(Register rd, Register rn, Operand o, Condition cond) {
  EmitType01(cond, o.type(), RSB, 1, rn, rd, o);
}

void Assembler::add(Register rd, Register rn, Operand o, Condition cond) {
  EmitType01(cond, o.type(), ADD, 0, rn, rd, o);
}

void Assembler::adds(Register rd, Register rn, Operand o, Condition cond) {
  EmitType01(cond, o.type(), ADD, 1, rn, rd, o);
}

void Assembler::subs(Register rd, Register rn, Operand o, Condition cond) {
  EmitType01(cond, o.type(), SUB, 1, rn, rd, o);
}

void Assembler::adc(Register rd, Register rn, Operand o, Condition cond) {
  EmitType01(cond, o.type(), ADC, 0, rn, rd, o);
}

void Assembler::adcs(Register rd, Register rn, Operand o, Condition cond) {
  EmitType01(cond, o.type(), ADC, 1, rn, rd, o);
}

void Assembler::sbc(Register rd, Register rn, Operand o, Condition cond) {
  EmitType01(cond, o.type(), SBC, 0, rn, rd, o);
}

void Assembler::sbcs(Register rd, Register rn, Operand o, Condition cond) {
  EmitType01(cond, o.type(), SBC, 1, rn, rd, o);
}

void Assembler::rsc(Register rd, Register rn, Operand o, Condition cond) {
  EmitType01(cond, o.type(), RSC, 0, rn, rd, o);
}

void Assembler::tst(Register rn, Operand o, Condition cond) {
  EmitType01(cond, o.type(), TST, 1, rn, R0, o);
}

void Assembler::teq(Register rn, Operand o, Condition cond) {
  EmitType01(cond, o.type(), TEQ, 1, rn, R0, o);
}

void Assembler::cmp(Register rn, Operand o, Condition cond) {
  EmitType01(cond, o.type(), CMP, 1, rn, R0, o);
}

void Assembler::cmn(Register rn, Operand o, Condition cond) {
  EmitType01(cond, o.type(), CMN, 1, rn, R0, o);
}

void Assembler::orr(Register rd, Register rn, Operand o, Condition cond) {
  EmitType01(cond, o.type(), ORR, 0, rn, rd, o);
}

void Assembler::orrs(Register rd, Register rn, Operand o, Condition cond) {
  EmitType01(cond, o.type(), ORR, 1, rn, rd, o);
}

void Assembler::mov(Register rd, Operand o, Condition cond) {
  EmitType01(cond, o.type(), MOV, 0, R0, rd, o);
}

void Assembler::movs(Register rd, Operand o, Condition cond) {
  EmitType01(cond, o.type(), MOV, 1, R0, rd, o);
}

void Assembler::bic(Register rd, Register rn, Operand o, Condition cond) {
  EmitType01(cond, o.type(), BIC, 0, rn, rd, o);
}

void Assembler::bics(Register rd, Register rn, Operand o, Condition cond) {
  EmitType01(cond, o.type(), BIC, 1, rn, rd, o);
}

void Assembler::mvn_(Register rd, Operand o, Condition cond) {
  EmitType01(cond, o.type(), MVN, 0, R0, rd, o);
}

void Assembler::mvns(Register rd, Operand o, Condition cond) {
  EmitType01(cond, o.type(), MVN, 1, R0, rd, o);
}

void Assembler::clz(Register rd, Register rm, Condition cond) {
  ASSERT(rd != kNoRegister);
  ASSERT(rm != kNoRegister);
  ASSERT(cond != kNoCondition);
  ASSERT(rd != PC);
  ASSERT(rm != PC);
  int32_t encoding = (static_cast<int32_t>(cond) << kConditionShift) | B24 |
                     B22 | B21 | (0xf << 16) | ArmEncode::Rd(rd) | (0xf << 8) |
                     B4 | static_cast<int32_t>(rm);
  Emit(encoding);
}

void Assembler::rbit(Register rd, Register rm, Condition cond) {
  ASSERT(rd != kNoRegister);
  ASSERT(rm != kNoRegister);
  ASSERT(cond != kNoCondition);
  ASSERT(rd != PC);
  ASSERT(rm != PC);
  int32_t encoding = (static_cast<int32_t>(cond) << kConditionShift) | B26 |
                     B25 | B23 | B22 | B21 | B20 | (0xf << 16) |
                     ArmEncode::Rd(rd) | (0xf << 8) | B5 | B4 |
                     static_cast<int32_t>(rm);
  Emit(encoding);
}

void Assembler::movw(Register rd, uint16_t imm16, Condition cond) {
  ASSERT(cond != kNoCondition);
  int32_t encoding = static_cast<int32_t>(cond) << kConditionShift | B25 | B24 |
                     ((imm16 >> 12) << 16) | ArmEncode::Rd(rd) |
                     (imm16 & 0xfff);
  Emit(encoding);
}

void Assembler::movt(Register rd, uint16_t imm16, Condition cond) {
  ASSERT(cond != kNoCondition);
  int32_t encoding = static_cast<int32_t>(cond) << kConditionShift | B25 | B24 |
                     B22 | ((imm16 >> 12) << 16) | ArmEncode::Rd(rd) |
                     (imm16 & 0xfff);
  Emit(encoding);
}

void Assembler::EmitMulOp(Condition cond,
                          int32_t opcode,
                          Register rd,
                          Register rn,
                          Register rm,
                          Register rs) {
  ASSERT(rd != kNoRegister);
  ASSERT(rn != kNoRegister);
  ASSERT(rm != kNoRegister);
  ASSERT(rs != kNoRegister);
  ASSERT(cond != kNoCondition);
  int32_t encoding = opcode | (static_cast<int32_t>(cond) << kConditionShift) |
                     ArmEncode::Rn(rn) | ArmEncode::Rd(rd) | ArmEncode::Rs(rs) |
                     B7 | B4 | ArmEncode::Rm(rm);
  Emit(encoding);
}

void Assembler::mul(Register rd, Register rn, Register rm, Condition cond) {
  // Assembler registers rd, rn, rm are encoded as rn, rm, rs.
  EmitMulOp(cond, 0, R0, rd, rn, rm);
}

// Like mul, but sets condition flags.
void Assembler::muls(Register rd, Register rn, Register rm, Condition cond) {
  EmitMulOp(cond, B20, R0, rd, rn, rm);
}

void Assembler::mla(Register rd,
                    Register rn,
                    Register rm,
                    Register ra,
                    Condition cond) {
  // rd <- ra + rn * rm.
  // Assembler registers rd, rn, rm, ra are encoded as rn, rm, rs, rd.
  EmitMulOp(cond, B21, ra, rd, rn, rm);
}

void Assembler::mls(Register rd,
                    Register rn,
                    Register rm,
                    Register ra,
                    Condition cond) {
  // rd <- ra - rn * rm.
  // Assembler registers rd, rn, rm, ra are encoded as rn, rm, rs, rd.
  EmitMulOp(cond, B22 | B21, ra, rd, rn, rm);
}

void Assembler::smull(Register rd_lo,
                      Register rd_hi,
                      Register rn,
                      Register rm,
                      Condition cond) {
  // Assembler registers rd_lo, rd_hi, rn, rm are encoded as rd, rn, rm, rs.
  EmitMulOp(cond, B23 | B22, rd_lo, rd_hi, rn, rm);
}

void Assembler::umull(Register rd_lo,
                      Register rd_hi,
                      Register rn,
                      Register rm,
                      Condition cond) {
  // Assembler registers rd_lo, rd_hi, rn, rm are encoded as rd, rn, rm, rs.
  EmitMulOp(cond, B23, rd_lo, rd_hi, rn, rm);
}

void Assembler::umlal(Register rd_lo,
                      Register rd_hi,
                      Register rn,
                      Register rm,
                      Condition cond) {
  // Assembler registers rd_lo, rd_hi, rn, rm are encoded as rd, rn, rm, rs.
  EmitMulOp(cond, B23 | B21, rd_lo, rd_hi, rn, rm);
}

void Assembler::umaal(Register rd_lo,
                      Register rd_hi,
                      Register rn,
                      Register rm) {
  ASSERT(rd_lo != IP);
  ASSERT(rd_hi != IP);
  ASSERT(rn != IP);
  ASSERT(rm != IP);
  // Assembler registers rd_lo, rd_hi, rn, rm are encoded as rd, rn, rm, rs.
  EmitMulOp(AL, B22, rd_lo, rd_hi, rn, rm);
}

void Assembler::EmitDivOp(Condition cond,
                          int32_t opcode,
                          Register rd,
                          Register rn,
                          Register rm) {
  ASSERT(TargetCPUFeatures::integer_division_supported());
  ASSERT(rd != kNoRegister);
  ASSERT(rn != kNoRegister);
  ASSERT(rm != kNoRegister);
  ASSERT(cond != kNoCondition);
  int32_t encoding = opcode | (static_cast<int32_t>(cond) << kConditionShift) |
                     (static_cast<int32_t>(rn) << kDivRnShift) |
                     (static_cast<int32_t>(rd) << kDivRdShift) | B26 | B25 |
                     B24 | B20 | B15 | B14 | B13 | B12 | B4 |
                     (static_cast<int32_t>(rm) << kDivRmShift);
  Emit(encoding);
}

void Assembler::sdiv(Register rd, Register rn, Register rm, Condition cond) {
  EmitDivOp(cond, 0, rd, rn, rm);
}

void Assembler::udiv(Register rd, Register rn, Register rm, Condition cond) {
  EmitDivOp(cond, B21, rd, rn, rm);
}

void Assembler::ldr(Register rd, Address ad, Condition cond) {
  EmitMemOp(cond, true, false, rd, ad);
}

void Assembler::str(Register rd, Address ad, Condition cond) {
  EmitMemOp(cond, false, false, rd, ad);
}

void Assembler::ldrb(Register rd, Address ad, Condition cond) {
  EmitMemOp(cond, true, true, rd, ad);
}

void Assembler::strb(Register rd, Address ad, Condition cond) {
  EmitMemOp(cond, false, true, rd, ad);
}

void Assembler::ldrh(Register rd, Address ad, Condition cond) {
  EmitMemOpAddressMode3(cond, L | B7 | H | B4, rd, ad);
}

void Assembler::strh(Register rd, Address ad, Condition cond) {
  EmitMemOpAddressMode3(cond, B7 | H | B4, rd, ad);
}

void Assembler::ldrsb(Register rd, Address ad, Condition cond) {
  EmitMemOpAddressMode3(cond, L | B7 | B6 | B4, rd, ad);
}

void Assembler::ldrsh(Register rd, Address ad, Condition cond) {
  EmitMemOpAddressMode3(cond, L | B7 | B6 | H | B4, rd, ad);
}

void Assembler::ldrd(Register rd,
                     Register rd2,
                     Register rn,
                     int32_t offset,
                     Condition cond) {
  ASSERT((rd % 2) == 0);
  ASSERT(rd2 == rd + 1);
  EmitMemOpAddressMode3(cond, B7 | B6 | B4, rd, Address(rn, offset));
}

void Assembler::strd(Register rd,
                     Register rd2,
                     Register rn,
                     int32_t offset,
                     Condition cond) {
  ASSERT((rd % 2) == 0);
  ASSERT(rd2 == rd + 1);
  EmitMemOpAddressMode3(cond, B7 | B6 | B5 | B4, rd, Address(rn, offset));
}

void Assembler::ldm(BlockAddressMode am,
                    Register base,
                    RegList regs,
                    Condition cond) {
  ASSERT(regs != 0);
  EmitMultiMemOp(cond, am, true, base, regs);
}

void Assembler::stm(BlockAddressMode am,
                    Register base,
                    RegList regs,
                    Condition cond) {
  ASSERT(regs != 0);
  EmitMultiMemOp(cond, am, false, base, regs);
}

void Assembler::ldrex(Register rt, Register rn, Condition cond) {
  ASSERT(rn != kNoRegister);
  ASSERT(rt != kNoRegister);
  ASSERT(rn != R15);
  ASSERT(rt != R15);
  ASSERT(cond != kNoCondition);
  int32_t encoding = (static_cast<int32_t>(cond) << kConditionShift) | B24 |
                     B23 | L | (static_cast<int32_t>(rn) << kLdrExRnShift) |
                     (static_cast<int32_t>(rt) << kLdrExRtShift) | B11 | B10 |
                     B9 | B8 | B7 | B4 | B3 | B2 | B1 | B0;
  Emit(encoding);
}

void Assembler::strex(Register rd, Register rt, Register rn, Condition cond) {
  ASSERT(rn != kNoRegister);
  ASSERT(rd != kNoRegister);
  ASSERT(rt != kNoRegister);
  ASSERT(rn != R15);
  ASSERT(rd != R15);
  ASSERT(rt != R15);
  ASSERT(rd != kNoRegister);
  ASSERT(rt != kNoRegister);
  ASSERT(cond != kNoCondition);
  ASSERT(rd != rn);
  ASSERT(rd != rt);
  int32_t encoding = (static_cast<int32_t>(cond) << kConditionShift) | B24 |
                     B23 | (static_cast<int32_t>(rn) << kStrExRnShift) |
                     (static_cast<int32_t>(rd) << kStrExRdShift) | B11 | B10 |
                     B9 | B8 | B7 | B4 |
                     (static_cast<int32_t>(rt) << kStrExRtShift);
  Emit(encoding);
}

void Assembler::dmb() {
  // Emit a `dmb ish` instruction.
  Emit(kDataMemoryBarrier);
}

static int32_t BitFieldExtractEncoding(bool sign_extend,
                                       Register rd,
                                       Register rn,
                                       int32_t lsb,
                                       int32_t width,
                                       Condition cond) {
  ASSERT(rn != kNoRegister && rn != PC);
  ASSERT(rd != kNoRegister && rd != PC);
  ASSERT(cond != kNoCondition);
  ASSERT(Utils::IsUint(kBitFieldExtractLSBBits, lsb));
  ASSERT(width >= 1);
  ASSERT(lsb + width <= kBitsPerInt32);
  const int32_t widthm1 = width - 1;
  ASSERT(Utils::IsUint(kBitFieldExtractWidthBits, widthm1));
  return (static_cast<int32_t>(cond) << kConditionShift) | B26 | B25 | B24 |
         B23 | (sign_extend ? 0 : B22) | B21 |
         (widthm1 << kBitFieldExtractWidthShift) |
         (static_cast<int32_t>(rd) << kRdShift) |
         (lsb << kBitFieldExtractLSBShift) | B6 | B4 |
         (static_cast<int32_t>(rn) << kBitFieldExtractRnShift);
}

void Assembler::sbfx(Register rd,
                     Register rn,
                     int32_t lsb,
                     int32_t width,
                     Condition cond) {
  const bool sign_extend = true;
  Emit(BitFieldExtractEncoding(sign_extend, rd, rn, lsb, width, cond));
}

void Assembler::ubfx(Register rd,
                     Register rn,
                     int32_t lsb,
                     int32_t width,
                     Condition cond) {
  const bool sign_extend = false;
  Emit(BitFieldExtractEncoding(sign_extend, rd, rn, lsb, width, cond));
}

void Assembler::EnterFullSafepoint(Register addr, Register state) {
  // We generate the same number of instructions whether or not the slow-path is
  // forced. This simplifies GenerateJitCallbackTrampolines.
  Label slow_path, done, retry;
  if (FLAG_use_slow_path) {
    b(&slow_path);
  }

  LoadImmediate(addr, target::Thread::safepoint_state_offset());
  add(addr, THR, Operand(addr));
  Bind(&retry);
  ldrex(state, addr);
  cmp(state, Operand(target::Thread::native_safepoint_state_unacquired()));
  b(&slow_path, NE);

  mov(state, Operand(target::Thread::native_safepoint_state_acquired()));
  strex(TMP, state, addr);
  cmp(TMP, Operand(0));  // 0 means strex was successful.
  b(&done, EQ);

  if (!FLAG_use_slow_path) {
    b(&retry);
  }

  Bind(&slow_path);
  ldr(TMP, Address(THR, target::Thread::enter_safepoint_stub_offset()));
  ldr(TMP, FieldAddress(TMP, target::Code::entry_point_offset()));
  blx(TMP);

  Bind(&done);
}

void Assembler::TransitionGeneratedToNative(Register destination_address,
                                            Register exit_frame_fp,
                                            Register exit_through_ffi,
                                            Register tmp1,
                                            bool enter_safepoint) {
  // Save exit frame information to enable stack walking.
  StoreToOffset(exit_frame_fp, THR,
                target::Thread::top_exit_frame_info_offset());

  StoreToOffset(exit_through_ffi, THR,
                target::Thread::exit_through_ffi_offset());
  Register tmp2 = exit_through_ffi;

  VerifyInGenerated(tmp1);
  // Mark that the thread is executing native code.
  StoreToOffset(destination_address, THR, target::Thread::vm_tag_offset());
  LoadImmediate(tmp1, target::Thread::native_execution_state());
  StoreToOffset(tmp1, THR, target::Thread::execution_state_offset());

  if (enter_safepoint) {
    EnterFullSafepoint(tmp1, tmp2);
  }
}

void Assembler::ExitFullSafepoint(Register tmp1, Register tmp2) {
  Register addr = tmp1;
  Register state = tmp2;

  // We generate the same number of instructions whether or not the slow-path is
  // forced, for consistency with EnterFullSafepoint.
  Label slow_path, done, retry;
  if (FLAG_use_slow_path) {
    b(&slow_path);
  }

  LoadImmediate(addr, target::Thread::safepoint_state_offset());
  add(addr, THR, Operand(addr));
  Bind(&retry);
  ldrex(state, addr);
  cmp(state, Operand(target::Thread::native_safepoint_state_acquired()));
  b(&slow_path, NE);

  mov(state, Operand(target::Thread::native_safepoint_state_unacquired()));
  strex(TMP, state, addr);
  cmp(TMP, Operand(0));  // 0 means strex was successful.
  b(&done, EQ);

  if (!FLAG_use_slow_path) {
    b(&retry);
  }

  Bind(&slow_path);
  ldr(TMP, Address(THR, target::Thread::exit_safepoint_stub_offset()));
  ldr(TMP, FieldAddress(TMP, target::Code::entry_point_offset()));
  blx(TMP);

  Bind(&done);
}

void Assembler::TransitionNativeToGenerated(Register addr,
                                            Register state,
                                            bool exit_safepoint,
                                            bool set_tag) {
  if (exit_safepoint) {
    ExitFullSafepoint(addr, state);
  } else {
#if defined(DEBUG)
    // Ensure we've already left the safepoint.
    ASSERT(target::Thread::native_safepoint_state_acquired() != 0);
    LoadImmediate(state, target::Thread::native_safepoint_state_acquired());
    ldr(TMP, Address(THR, target::Thread::safepoint_state_offset()));
    ands(TMP, TMP, Operand(state));
    Label ok;
    b(&ok, ZERO);
    Breakpoint();
    Bind(&ok);
#endif
  }

  VerifyNotInGenerated(TMP);
  // Mark that the thread is executing Dart code.
  if (set_tag) {
    LoadImmediate(state, target::Thread::vm_tag_dart_id());
    StoreToOffset(state, THR, target::Thread::vm_tag_offset());
  }
  LoadImmediate(state, target::Thread::generated_execution_state());
  StoreToOffset(state, THR, target::Thread::execution_state_offset());

  // Reset exit frame information in Isolate's mutator thread structure.
  LoadImmediate(state, 0);
  StoreToOffset(state, THR, target::Thread::top_exit_frame_info_offset());
  StoreToOffset(state, THR, target::Thread::exit_through_ffi_offset());
}

void Assembler::VerifyInGenerated(Register scratch) {
#if defined(DEBUG)
  // Verify the thread is in generated.
  Comment("VerifyInGenerated");
  ldr(scratch, Address(THR, target::Thread::execution_state_offset()));
  Label ok;
  CompareImmediate(scratch, target::Thread::generated_execution_state());
  BranchIf(EQUAL, &ok, Assembler::kNearJump);
  Breakpoint();
  Bind(&ok);
#endif
}

void Assembler::VerifyNotInGenerated(Register scratch) {
#if defined(DEBUG)
  // Verify the thread is in native or VM.
  Comment("VerifyNotInGenerated");
  ldr(scratch, Address(THR, target::Thread::execution_state_offset()));
  CompareImmediate(scratch, target::Thread::generated_execution_state());
  Label ok;
  BranchIf(NOT_EQUAL, &ok, Assembler::kNearJump);
  Breakpoint();
  Bind(&ok);
#endif
}

void Assembler::clrex() {
  int32_t encoding = (kSpecialCondition << kConditionShift) | B26 | B24 | B22 |
                     B21 | B20 | (0xff << 12) | B4 | 0xf;
  Emit(encoding);
}

void Assembler::nop(Condition cond) {
  ASSERT(cond != kNoCondition);
  int32_t encoding = (static_cast<int32_t>(cond) << kConditionShift) | B25 |
                     B24 | B21 | (0xf << 12);
  Emit(encoding);
}

void Assembler::vmovsr(SRegister sn, Register rt, Condition cond) {
  ASSERT(sn != kNoSRegister);
  ASSERT(rt != kNoRegister);
  ASSERT(rt != SP);
  ASSERT(rt != PC);
  ASSERT(cond != kNoCondition);
  int32_t encoding = (static_cast<int32_t>(cond) << kConditionShift) | B27 |
                     B26 | B25 | ((static_cast<int32_t>(sn) >> 1) * B16) |
                     (static_cast<int32_t>(rt) * B12) | B11 | B9 |
                     ((static_cast<int32_t>(sn) & 1) * B7) | B4;
  Emit(encoding);
}

void Assembler::vmovrs(Register rt, SRegister sn, Condition cond) {
  ASSERT(sn != kNoSRegister);
  ASSERT(rt != kNoRegister);
  ASSERT(rt != SP);
  ASSERT(rt != PC);
  ASSERT(cond != kNoCondition);
  int32_t encoding = (static_cast<int32_t>(cond) << kConditionShift) | B27 |
                     B26 | B25 | B20 | ((static_cast<int32_t>(sn) >> 1) * B16) |
                     (static_cast<int32_t>(rt) * B12) | B11 | B9 |
                     ((static_cast<int32_t>(sn) & 1) * B7) | B4;
  Emit(encoding);
}

void Assembler::vmovsrr(SRegister sm,
                        Register rt,
                        Register rt2,
                        Condition cond) {
  ASSERT(sm != kNoSRegister);
  ASSERT(sm != S31);
  ASSERT(rt != kNoRegister);
  ASSERT(rt != SP);
  ASSERT(rt != PC);
  ASSERT(rt2 != kNoRegister);
  ASSERT(rt2 != SP);
  ASSERT(rt2 != PC);
  ASSERT(cond != kNoCondition);
  int32_t encoding = (static_cast<int32_t>(cond) << kConditionShift) | B27 |
                     B26 | B22 | (static_cast<int32_t>(rt2) * B16) |
                     (static_cast<int32_t>(rt) * B12) | B11 | B9 |
                     ((static_cast<int32_t>(sm) & 1) * B5) | B4 |
                     (static_cast<int32_t>(sm) >> 1);
  Emit(encoding);
}

void Assembler::vmovrrs(Register rt,
                        Register rt2,
                        SRegister sm,
                        Condition cond) {
  ASSERT(sm != kNoSRegister);
  ASSERT(sm != S31);
  ASSERT(rt != kNoRegister);
  ASSERT(rt != SP);
  ASSERT(rt != PC);
  ASSERT(rt2 != kNoRegister);
  ASSERT(rt2 != SP);
  ASSERT(rt2 != PC);
  ASSERT(rt != rt2);
  ASSERT(cond != kNoCondition);
  int32_t encoding = (static_cast<int32_t>(cond) << kConditionShift) | B27 |
                     B26 | B22 | B20 | (static_cast<int32_t>(rt2) * B16) |
                     (static_cast<int32_t>(rt) * B12) | B11 | B9 |
                     ((static_cast<int32_t>(sm) & 1) * B5) | B4 |
                     (static_cast<int32_t>(sm) >> 1);
  Emit(encoding);
}

void Assembler::vmovdr(DRegister dn, int i, Register rt, Condition cond) {
  ASSERT((i == 0) || (i == 1));
  ASSERT(rt != kNoRegister);
  ASSERT(rt != SP);
  ASSERT(rt != PC);
  ASSERT(dn != kNoDRegister);
  ASSERT(cond != kNoCondition);
  int32_t encoding = (static_cast<int32_t>(cond) << kConditionShift) | B27 |
                     B26 | B25 | (i * B21) | (static_cast<int32_t>(rt) * B12) |
                     B11 | B9 | B8 | ((static_cast<int32_t>(dn) >> 4) * B7) |
                     ((static_cast<int32_t>(dn) & 0xf) * B16) | B4;
  Emit(encoding);
}

void Assembler::vmovdrr(DRegister dm,
                        Register rt,
                        Register rt2,
                        Condition cond) {
  ASSERT(dm != kNoDRegister);
  ASSERT(rt != kNoRegister);
  ASSERT(rt != SP);
  ASSERT(rt != PC);
  ASSERT(rt2 != kNoRegister);
  ASSERT(rt2 != SP);
  ASSERT(rt2 != PC);
  ASSERT(cond != kNoCondition);
  int32_t encoding = (static_cast<int32_t>(cond) << kConditionShift) | B27 |
                     B26 | B22 | (static_cast<int32_t>(rt2) * B16) |
                     (static_cast<int32_t>(rt) * B12) | B11 | B9 | B8 |
                     ((static_cast<int32_t>(dm) >> 4) * B5) | B4 |
                     (static_cast<int32_t>(dm) & 0xf);
  Emit(encoding);
}

void Assembler::vmovrrd(Register rt,
                        Register rt2,
                        DRegister dm,
                        Condition cond) {
  ASSERT(dm != kNoDRegister);
  ASSERT(rt != kNoRegister);
  ASSERT(rt != SP);
  ASSERT(rt != PC);
  ASSERT(rt2 != kNoRegister);
  ASSERT(rt2 != SP);
  ASSERT(rt2 != PC);
  ASSERT(rt != rt2);
  ASSERT(cond != kNoCondition);
  int32_t encoding = (static_cast<int32_t>(cond) << kConditionShift) | B27 |
                     B26 | B22 | B20 | (static_cast<int32_t>(rt2) * B16) |
                     (static_cast<int32_t>(rt) * B12) | B11 | B9 | B8 |
                     ((static_cast<int32_t>(dm) >> 4) * B5) | B4 |
                     (static_cast<int32_t>(dm) & 0xf);
  Emit(encoding);
}

void Assembler::vldrs(SRegister sd, Address ad, Condition cond) {
  ASSERT(sd != kNoSRegister);
  ASSERT(cond != kNoCondition);
  int32_t encoding = (static_cast<int32_t>(cond) << kConditionShift) | B27 |
                     B26 | B24 | B20 | ((static_cast<int32_t>(sd) & 1) * B22) |
                     ((static_cast<int32_t>(sd) >> 1) * B12) | B11 | B9 |
                     ad.vencoding();
  Emit(encoding);
}

void Assembler::vstrs(SRegister sd, Address ad, Condition cond) {
  ASSERT(static_cast<Register>(ad.encoding_ & (0xf << kRnShift)) != PC);
  ASSERT(sd != kNoSRegister);
  ASSERT(cond != kNoCondition);
  int32_t encoding = (static_cast<int32_t>(cond) << kConditionShift) | B27 |
                     B26 | B24 | ((static_cast<int32_t>(sd) & 1) * B22) |
                     ((static_cast<int32_t>(sd) >> 1) * B12) | B11 | B9 |
                     ad.vencoding();
  Emit(encoding);
}

void Assembler::vldrd(DRegister dd, Address ad, Condition cond) {
  ASSERT(dd != kNoDRegister);
  ASSERT(cond != kNoCondition);
  int32_t encoding = (static_cast<int32_t>(cond) << kConditionShift) | B27 |
                     B26 | B24 | B20 | ((static_cast<int32_t>(dd) >> 4) * B22) |
                     ((static_cast<int32_t>(dd) & 0xf) * B12) | B11 | B9 | B8 |
                     ad.vencoding();
  Emit(encoding);
}

void Assembler::vstrd(DRegister dd, Address ad, Condition cond) {
  ASSERT(static_cast<Register>(ad.encoding_ & (0xf << kRnShift)) != PC);
  ASSERT(dd != kNoDRegister);
  ASSERT(cond != kNoCondition);
  int32_t encoding = (static_cast<int32_t>(cond) << kConditionShift) | B27 |
                     B26 | B24 | ((static_cast<int32_t>(dd) >> 4) * B22) |
                     ((static_cast<int32_t>(dd) & 0xf) * B12) | B11 | B9 | B8 |
                     ad.vencoding();
  Emit(encoding);
}

void Assembler::EmitMultiVSMemOp(Condition cond,
                                 BlockAddressMode am,
                                 bool load,
                                 Register base,
                                 SRegister start,
                                 uint32_t count) {
  ASSERT(base != kNoRegister);
  ASSERT(cond != kNoCondition);
  ASSERT(start != kNoSRegister);
  ASSERT(static_cast<int32_t>(start) + count <= kNumberOfSRegisters);

  int32_t encoding = (static_cast<int32_t>(cond) << kConditionShift) | B27 |
                     B26 | B11 | B9 | am | (load ? L : 0) |
                     ArmEncode::Rn(base) |
                     ((static_cast<int32_t>(start) & 0x1) != 0 ? D : 0) |
                     ((static_cast<int32_t>(start) >> 1) << 12) | count;
  Emit(encoding);
}

void Assembler::EmitMultiVDMemOp(Condition cond,
                                 BlockAddressMode am,
                                 bool load,
                                 Register base,
                                 DRegister start,
                                 int32_t count) {
  ASSERT(base != kNoRegister);
  ASSERT(cond != kNoCondition);
  ASSERT(start != kNoDRegister);
  ASSERT(static_cast<int32_t>(start) + count <= kNumberOfDRegisters);
  const int notArmv5te = 0;

  int32_t encoding =
      (static_cast<int32_t>(cond) << kConditionShift) | B27 | B26 | B11 | B9 |
      B8 | am | (load ? L : 0) | ArmEncode::Rn(base) |
      ((static_cast<int32_t>(start) & 0x10) != 0 ? D : 0) |
      ((static_cast<int32_t>(start) & 0xf) << 12) | (count << 1) | notArmv5te;
  Emit(encoding);
}

void Assembler::vldms(BlockAddressMode am,
                      Register base,
                      SRegister first,
                      SRegister last,
                      Condition cond) {
  ASSERT((am == IA) || (am == IA_W) || (am == DB_W));
  ASSERT(last > first);
  EmitMultiVSMemOp(cond, am, true, base, first, last - first + 1);
}

void Assembler::vstms(BlockAddressMode am,
                      Register base,
                      SRegister first,
                      SRegister last,
                      Condition cond) {
  ASSERT((am == IA) || (am == IA_W) || (am == DB_W));
  ASSERT(last > first);
  EmitMultiVSMemOp(cond, am, false, base, first, last - first + 1);
}

void Assembler::vldmd(BlockAddressMode am,
                      Register base,
                      DRegister first,
                      intptr_t count,
                      Condition cond) {
  ASSERT((am == IA) || (am == IA_W) || (am == DB_W));
  ASSERT(count <= 16);
  ASSERT(first + count <= kNumberOfDRegisters);
  EmitMultiVDMemOp(cond, am, true, base, first, count);
}

void Assembler::vstmd(BlockAddressMode am,
                      Register base,
                      DRegister first,
                      intptr_t count,
                      Condition cond) {
  ASSERT((am == IA) || (am == IA_W) || (am == DB_W));
  ASSERT(count <= 16);
  ASSERT(first + count <= kNumberOfDRegisters);
  EmitMultiVDMemOp(cond, am, false, base, first, count);
}

void Assembler::EmitVFPsss(Condition cond,
                           int32_t opcode,
                           SRegister sd,
                           SRegister sn,
                           SRegister sm) {
  ASSERT(sd != kNoSRegister);
  ASSERT(sn != kNoSRegister);
  ASSERT(sm != kNoSRegister);
  ASSERT(cond != kNoCondition);
  int32_t encoding =
      (static_cast<int32_t>(cond) << kConditionShift) | B27 | B26 | B25 | B11 |
      B9 | opcode | ((static_cast<int32_t>(sd) & 1) * B22) |
      ((static_cast<int32_t>(sn) >> 1) * B16) |
      ((static_cast<int32_t>(sd) >> 1) * B12) |
      ((static_cast<int32_t>(sn) & 1) * B7) |
      ((static_cast<int32_t>(sm) & 1) * B5) | (static_cast<int32_t>(sm) >> 1);
  Emit(encoding);
}

void Assembler::EmitVFPddd(Condition cond,
                           int32_t opcode,
                           DRegister dd,
                           DRegister dn,
                           DRegister dm) {
  ASSERT(dd != kNoDRegister);
  ASSERT(dn != kNoDRegister);
  ASSERT(dm != kNoDRegister);
  ASSERT(cond != kNoCondition);
  int32_t encoding =
      (static_cast<int32_t>(cond) << kConditionShift) | B27 | B26 | B25 | B11 |
      B9 | B8 | opcode | ((static_cast<int32_t>(dd) >> 4) * B22) |
      ((static_cast<int32_t>(dn) & 0xf) * B16) |
      ((static_cast<int32_t>(dd) & 0xf) * B12) |
      ((static_cast<int32_t>(dn) >> 4) * B7) |
      ((static_cast<int32_t>(dm) >> 4) * B5) | (static_cast<int32_t>(dm) & 0xf);
  Emit(encoding);
}

void Assembler::vmovs(SRegister sd, SRegister sm, Condition cond) {
  EmitVFPsss(cond, B23 | B21 | B20 | B6, sd, S0, sm);
}

void Assembler::vmovd(DRegister dd, DRegister dm, Condition cond) {
  EmitVFPddd(cond, B23 | B21 | B20 | B6, dd, D0, dm);
}

bool Assembler::vmovs(SRegister sd, float s_imm, Condition cond) {
  uint32_t imm32 = bit_cast<uint32_t, float>(s_imm);
  if (((imm32 & ((1 << 19) - 1)) == 0) &&
      ((((imm32 >> 25) & ((1 << 6) - 1)) == (1 << 5)) ||
       (((imm32 >> 25) & ((1 << 6) - 1)) == ((1 << 5) - 1)))) {
    uint8_t imm8 = ((imm32 >> 31) << 7) | (((imm32 >> 29) & 1) << 6) |
                   ((imm32 >> 19) & ((1 << 6) - 1));
    EmitVFPsss(cond, B23 | B21 | B20 | ((imm8 >> 4) * B16) | (imm8 & 0xf), sd,
               S0, S0);
    return true;
  }
  return false;
}

bool Assembler::vmovd(DRegister dd, double d_imm, Condition cond) {
  uint64_t imm64 = bit_cast<uint64_t, double>(d_imm);
  if (((imm64 & ((1LL << 48) - 1)) == 0) &&
      ((((imm64 >> 54) & ((1 << 9) - 1)) == (1 << 8)) ||
       (((imm64 >> 54) & ((1 << 9) - 1)) == ((1 << 8) - 1)))) {
    uint8_t imm8 = ((imm64 >> 63) << 7) | (((imm64 >> 61) & 1) << 6) |
                   ((imm64 >> 48) & ((1 << 6) - 1));
    EmitVFPddd(cond, B23 | B21 | B20 | ((imm8 >> 4) * B16) | B8 | (imm8 & 0xf),
               dd, D0, D0);
    return true;
  }
  return false;
}

void Assembler::vadds(SRegister sd,
                      SRegister sn,
                      SRegister sm,
                      Condition cond) {
  EmitVFPsss(cond, B21 | B20, sd, sn, sm);
}

void Assembler::vaddd(DRegister dd,
                      DRegister dn,
                      DRegister dm,
                      Condition cond) {
  EmitVFPddd(cond, B21 | B20, dd, dn, dm);
}

void Assembler::vsubs(SRegister sd,
                      SRegister sn,
                      SRegister sm,
                      Condition cond) {
  EmitVFPsss(cond, B21 | B20 | B6, sd, sn, sm);
}

void Assembler::vsubd(DRegister dd,
                      DRegister dn,
                      DRegister dm,
                      Condition cond) {
  EmitVFPddd(cond, B21 | B20 | B6, dd, dn, dm);
}

void Assembler::vmuls(SRegister sd,
                      SRegister sn,
                      SRegister sm,
                      Condition cond) {
  EmitVFPsss(cond, B21, sd, sn, sm);
}

void Assembler::vmuld(DRegister dd,
                      DRegister dn,
                      DRegister dm,
                      Condition cond) {
  EmitVFPddd(cond, B21, dd, dn, dm);
}

void Assembler::vmlas(SRegister sd,
                      SRegister sn,
                      SRegister sm,
                      Condition cond) {
  EmitVFPsss(cond, 0, sd, sn, sm);
}

void Assembler::vmlad(DRegister dd,
                      DRegister dn,
                      DRegister dm,
                      Condition cond) {
  EmitVFPddd(cond, 0, dd, dn, dm);
}

void Assembler::vmlss(SRegister sd,
                      SRegister sn,
                      SRegister sm,
                      Condition cond) {
  EmitVFPsss(cond, B6, sd, sn, sm);
}

void Assembler::vmlsd(DRegister dd,
                      DRegister dn,
                      DRegister dm,
                      Condition cond) {
  EmitVFPddd(cond, B6, dd, dn, dm);
}

void Assembler::vdivs(SRegister sd,
                      SRegister sn,
                      SRegister sm,
                      Condition cond) {
  EmitVFPsss(cond, B23, sd, sn, sm);
}

void Assembler::vdivd(DRegister dd,
                      DRegister dn,
                      DRegister dm,
                      Condition cond) {
  EmitVFPddd(cond, B23, dd, dn, dm);
}

void Assembler::vabss(SRegister sd, SRegister sm, Condition cond) {
  EmitVFPsss(cond, B23 | B21 | B20 | B7 | B6, sd, S0, sm);
}

void Assembler::vabsd(DRegister dd, DRegister dm, Condition cond) {
  EmitVFPddd(cond, B23 | B21 | B20 | B7 | B6, dd, D0, dm);
}

void Assembler::vnegs(SRegister sd, SRegister sm, Condition cond) {
  EmitVFPsss(cond, B23 | B21 | B20 | B16 | B6, sd, S0, sm);
}

void Assembler::vnegd(DRegister dd, DRegister dm, Condition cond) {
  EmitVFPddd(cond, B23 | B21 | B20 | B16 | B6, dd, D0, dm);
}

void Assembler::vsqrts(SRegister sd, SRegister sm, Condition cond) {
  EmitVFPsss(cond, B23 | B21 | B20 | B16 | B7 | B6, sd, S0, sm);
}

void Assembler::vsqrtd(DRegister dd, DRegister dm, Condition cond) {
  EmitVFPddd(cond, B23 | B21 | B20 | B16 | B7 | B6, dd, D0, dm);
}

void Assembler::EmitVFPsd(Condition cond,
                          int32_t opcode,
                          SRegister sd,
                          DRegister dm) {
  ASSERT(sd != kNoSRegister);
  ASSERT(dm != kNoDRegister);
  ASSERT(cond != kNoCondition);
  int32_t encoding =
      (static_cast<int32_t>(cond) << kConditionShift) | B27 | B26 | B25 | B11 |
      B9 | opcode | ((static_cast<int32_t>(sd) & 1) * B22) |
      ((static_cast<int32_t>(sd) >> 1) * B12) |
      ((static_cast<int32_t>(dm) >> 4) * B5) | (static_cast<int32_t>(dm) & 0xf);
  Emit(encoding);
}

void Assembler::EmitVFPds(Condition cond,
                          int32_t opcode,
                          DRegister dd,
                          SRegister sm) {
  ASSERT(dd != kNoDRegister);
  ASSERT(sm != kNoSRegister);
  ASSERT(cond != kNoCondition);
  int32_t encoding =
      (static_cast<int32_t>(cond) << kConditionShift) | B27 | B26 | B25 | B11 |
      B9 | opcode | ((static_cast<int32_t>(dd) >> 4) * B22) |
      ((static_cast<int32_t>(dd) & 0xf) * B12) |
      ((static_cast<int32_t>(sm) & 1) * B5) | (static_cast<int32_t>(sm) >> 1);
  Emit(encoding);
}

void Assembler::vcvtsd(SRegister sd, DRegister dm, Condition cond) {
  EmitVFPsd(cond, B23 | B21 | B20 | B18 | B17 | B16 | B8 | B7 | B6, sd, dm);
}

void Assembler::vcvtds(DRegister dd, SRegister sm, Condition cond) {
  EmitVFPds(cond, B23 | B21 | B20 | B18 | B17 | B16 | B7 | B6, dd, sm);
}

void Assembler::vcvtis(SRegister sd, SRegister sm, Condition cond) {
  EmitVFPsss(cond, B23 | B21 | B20 | B19 | B18 | B16 | B7 | B6, sd, S0, sm);
}

void Assembler::vcvtid(SRegister sd, DRegister dm, Condition cond) {
  EmitVFPsd(cond, B23 | B21 | B20 | B19 | B18 | B16 | B8 | B7 | B6, sd, dm);
}

void Assembler::vcvtsi(SRegister sd, SRegister sm, Condition cond) {
  EmitVFPsss(cond, B23 | B21 | B20 | B19 | B7 | B6, sd, S0, sm);
}

void Assembler::vcvtdi(DRegister dd, SRegister sm, Condition cond) {
  EmitVFPds(cond, B23 | B21 | B20 | B19 | B8 | B7 | B6, dd, sm);
}

void Assembler::vcvtus(SRegister sd, SRegister sm, Condition cond) {
  EmitVFPsss(cond, B23 | B21 | B20 | B19 | B18 | B7 | B6, sd, S0, sm);
}

void Assembler::vcvtud(SRegister sd, DRegister dm, Condition cond) {
  EmitVFPsd(cond, B23 | B21 | B20 | B19 | B18 | B8 | B7 | B6, sd, dm);
}

void Assembler::vcvtsu(SRegister sd, SRegister sm, Condition cond) {
  EmitVFPsss(cond, B23 | B21 | B20 | B19 | B6, sd, S0, sm);
}

void Assembler::vcvtdu(DRegister dd, SRegister sm, Condition cond) {
  EmitVFPds(cond, B23 | B21 | B20 | B19 | B8 | B6, dd, sm);
}

void Assembler::vcmps(SRegister sd, SRegister sm, Condition cond) {
  EmitVFPsss(cond, B23 | B21 | B20 | B18 | B6, sd, S0, sm);
}

void Assembler::vcmpd(DRegister dd, DRegister dm, Condition cond) {
  EmitVFPddd(cond, B23 | B21 | B20 | B18 | B6, dd, D0, dm);
}

void Assembler::vcmpsz(SRegister sd, Condition cond) {
  EmitVFPsss(cond, B23 | B21 | B20 | B18 | B16 | B6, sd, S0, S0);
}

void Assembler::vcmpdz(DRegister dd, Condition cond) {
  EmitVFPddd(cond, B23 | B21 | B20 | B18 | B16 | B6, dd, D0, D0);
}

void Assembler::vmrs(Register rd, Condition cond) {
  ASSERT(cond != kNoCondition);
  int32_t encoding = (static_cast<int32_t>(cond) << kConditionShift) | B27 |
                     B26 | B25 | B23 | B22 | B21 | B20 | B16 |
                     (static_cast<int32_t>(rd) * B12) | B11 | B9 | B4;
  Emit(encoding);
}

void Assembler::vmstat(Condition cond) {
  vmrs(APSR, cond);
}

static inline int ShiftOfOperandSize(OperandSize size) {
  switch (size) {
    case kByte:
    case kUnsignedByte:
      return 0;
    case kTwoBytes:
    case kUnsignedTwoBytes:
      return 1;
    case kFourBytes:
    case kUnsignedFourBytes:
      return 2;
    case kWordPair:
      return 3;
    case kSWord:
    case kDWord:
      return 0;
    default:
      UNREACHABLE();
      break;
  }

  UNREACHABLE();
  return -1;
}

void Assembler::EmitSIMDqqq(int32_t opcode,
                            OperandSize size,
                            QRegister qd,
                            QRegister qn,
                            QRegister qm) {
  ASSERT(TargetCPUFeatures::neon_supported());
  int sz = ShiftOfOperandSize(size);
  int32_t encoding =
      (static_cast<int32_t>(kSpecialCondition) << kConditionShift) | B25 | B6 |
      opcode | ((sz & 0x3) * B20) |
      ((static_cast<int32_t>(qd * 2) >> 4) * B22) |
      ((static_cast<int32_t>(qn * 2) & 0xf) * B16) |
      ((static_cast<int32_t>(qd * 2) & 0xf) * B12) |
      ((static_cast<int32_t>(qn * 2) >> 4) * B7) |
      ((static_cast<int32_t>(qm * 2) >> 4) * B5) |
      (static_cast<int32_t>(qm * 2) & 0xf);
  Emit(encoding);
}

void Assembler::EmitSIMDddd(int32_t opcode,
                            OperandSize size,
                            DRegister dd,
                            DRegister dn,
                            DRegister dm) {
  ASSERT(TargetCPUFeatures::neon_supported());
  int sz = ShiftOfOperandSize(size);
  int32_t encoding =
      (static_cast<int32_t>(kSpecialCondition) << kConditionShift) | B25 |
      opcode | ((sz & 0x3) * B20) | ((static_cast<int32_t>(dd) >> 4) * B22) |
      ((static_cast<int32_t>(dn) & 0xf) * B16) |
      ((static_cast<int32_t>(dd) & 0xf) * B12) |
      ((static_cast<int32_t>(dn) >> 4) * B7) |
      ((static_cast<int32_t>(dm) >> 4) * B5) | (static_cast<int32_t>(dm) & 0xf);
  Emit(encoding);
}

void Assembler::vmovq(QRegister qd, QRegister qm) {
  EmitSIMDqqq(B21 | B8 | B4, kByte, qd, qm, qm);
}

void Assembler::vaddqi(OperandSize sz,
                       QRegister qd,
                       QRegister qn,
                       QRegister qm) {
  EmitSIMDqqq(B11, sz, qd, qn, qm);
}

void Assembler::vaddqs(QRegister qd, QRegister qn, QRegister qm) {
  EmitSIMDqqq(B11 | B10 | B8, kSWord, qd, qn, qm);
}

void Assembler::vsubqi(OperandSize sz,
                       QRegister qd,
                       QRegister qn,
                       QRegister qm) {
  EmitSIMDqqq(B24 | B11, sz, qd, qn, qm);
}

void Assembler::vsubqs(QRegister qd, QRegister qn, QRegister qm) {
  EmitSIMDqqq(B21 | B11 | B10 | B8, kSWord, qd, qn, qm);
}

void Assembler::vmulqi(OperandSize sz,
                       QRegister qd,
                       QRegister qn,
                       QRegister qm) {
  EmitSIMDqqq(B11 | B8 | B4, sz, qd, qn, qm);
}

void Assembler::vmulqs(QRegister qd, QRegister qn, QRegister qm) {
  EmitSIMDqqq(B24 | B11 | B10 | B8 | B4, kSWord, qd, qn, qm);
}

void Assembler::vshlqi(OperandSize sz,
                       QRegister qd,
                       QRegister qm,
                       QRegister qn) {
  EmitSIMDqqq(B25 | B10, sz, qd, qn, qm);
}

void Assembler::vshlqu(OperandSize sz,
                       QRegister qd,
                       QRegister qm,
                       QRegister qn) {
  EmitSIMDqqq(B25 | B24 | B10, sz, qd, qn, qm);
}

void Assembler::veorq(QRegister qd, QRegister qn, QRegister qm) {
  EmitSIMDqqq(B24 | B8 | B4, kByte, qd, qn, qm);
}

void Assembler::vorrq(QRegister qd, QRegister qn, QRegister qm) {
  EmitSIMDqqq(B21 | B8 | B4, kByte, qd, qn, qm);
}

void Assembler::vornq(QRegister qd, QRegister qn, QRegister qm) {
  EmitSIMDqqq(B21 | B20 | B8 | B4, kByte, qd, qn, qm);
}

void Assembler::vandq(QRegister qd, QRegister qn, QRegister qm) {
  EmitSIMDqqq(B8 | B4, kByte, qd, qn, qm);
}

void Assembler::vmvnq(QRegister qd, QRegister qm) {
  EmitSIMDqqq(B25 | B24 | B23 | B10 | B8 | B7, kWordPair, qd, Q0, qm);
}

void Assembler::vminqs(QRegister qd, QRegister qn, QRegister qm) {
  EmitSIMDqqq(B21 | B11 | B10 | B9 | B8, kSWord, qd, qn, qm);
}

void Assembler::vmaxqs(QRegister qd, QRegister qn, QRegister qm) {
  EmitSIMDqqq(B11 | B10 | B9 | B8, kSWord, qd, qn, qm);
}

void Assembler::vabsqs(QRegister qd, QRegister qm) {
  EmitSIMDqqq(B24 | B23 | B21 | B20 | B19 | B16 | B10 | B9 | B8, kSWord, qd, Q0,
              qm);
}

void Assembler::vnegqs(QRegister qd, QRegister qm) {
  EmitSIMDqqq(B24 | B23 | B21 | B20 | B19 | B16 | B10 | B9 | B8 | B7, kSWord,
              qd, Q0, qm);
}

void Assembler::vrecpeqs(QRegister qd, QRegister qm) {
  EmitSIMDqqq(B24 | B23 | B21 | B20 | B19 | B17 | B16 | B10 | B8, kSWord, qd,
              Q0, qm);
}

void Assembler::vrecpsqs(QRegister qd, QRegister qn, QRegister qm) {
  EmitSIMDqqq(B11 | B10 | B9 | B8 | B4, kSWord, qd, qn, qm);
}

void Assembler::vrsqrteqs(QRegister qd, QRegister qm) {
  EmitSIMDqqq(B24 | B23 | B21 | B20 | B19 | B17 | B16 | B10 | B8 | B7, kSWord,
              qd, Q0, qm);
}

void Assembler::vrsqrtsqs(QRegister qd, QRegister qn, QRegister qm) {
  EmitSIMDqqq(B21 | B11 | B10 | B9 | B8 | B4, kSWord, qd, qn, qm);
}

void Assembler::vdup(OperandSize sz, QRegister qd, DRegister dm, int idx) {
  ASSERT((sz != kDWord) && (sz != kSWord) && (sz != kWordPair));
  int code = 0;

  switch (sz) {
    case kByte:
    case kUnsignedByte: {
      ASSERT((idx >= 0) && (idx < 8));
      code = 1 | (idx << 1);
      break;
    }
    case kTwoBytes:
    case kUnsignedTwoBytes: {
      ASSERT((idx >= 0) && (idx < 4));
      code = 2 | (idx << 2);
      break;
    }
    case kFourBytes:
    case kUnsignedFourBytes: {
      ASSERT((idx >= 0) && (idx < 2));
      code = 4 | (idx << 3);
      break;
    }
    default: {
      break;
    }
  }

  EmitSIMDddd(B24 | B23 | B11 | B10 | B6, kWordPair,
              static_cast<DRegister>(qd * 2),
              static_cast<DRegister>(code & 0xf), dm);
}

void Assembler::vtbl(DRegister dd, DRegister dn, int len, DRegister dm) {
  ASSERT((len >= 1) && (len <= 4));
  EmitSIMDddd(B24 | B23 | B11 | ((len - 1) * B8), kWordPair, dd, dn, dm);
}

void Assembler::vzipqw(QRegister qd, QRegister qm) {
  EmitSIMDqqq(B24 | B23 | B21 | B20 | B19 | B17 | B8 | B7, kByte, qd, Q0, qm);
}

void Assembler::vceqqi(OperandSize sz,
                       QRegister qd,
                       QRegister qn,
                       QRegister qm) {
  EmitSIMDqqq(B24 | B11 | B4, sz, qd, qn, qm);
}

void Assembler::vceqqs(QRegister qd, QRegister qn, QRegister qm) {
  EmitSIMDqqq(B11 | B10 | B9, kSWord, qd, qn, qm);
}

void Assembler::vcgeqi(OperandSize sz,
                       QRegister qd,
                       QRegister qn,
                       QRegister qm) {
  EmitSIMDqqq(B9 | B8 | B4, sz, qd, qn, qm);
}

void Assembler::vcugeqi(OperandSize sz,
                        QRegister qd,
                        QRegister qn,
                        QRegister qm) {
  EmitSIMDqqq(B24 | B9 | B8 | B4, sz, qd, qn, qm);
}

void Assembler::vcgeqs(QRegister qd, QRegister qn, QRegister qm) {
  EmitSIMDqqq(B24 | B11 | B10 | B9, kSWord, qd, qn, qm);
}

void Assembler::vcgtqi(OperandSize sz,
                       QRegister qd,
                       QRegister qn,
                       QRegister qm) {
  EmitSIMDqqq(B9 | B8, sz, qd, qn, qm);
}

void Assembler::vcugtqi(OperandSize sz,
                        QRegister qd,
                        QRegister qn,
                        QRegister qm) {
  EmitSIMDqqq(B24 | B9 | B8, sz, qd, qn, qm);
}

void Assembler::vcgtqs(QRegister qd, QRegister qn, QRegister qm) {
  EmitSIMDqqq(B24 | B21 | B11 | B10 | B9, kSWord, qd, qn, qm);
}

void Assembler::bkpt(uint16_t imm16) {
  Emit(BkptEncoding(imm16));
}

void Assembler::b(Label* label, Condition cond) {
  EmitBranch(cond, label, false);
}

void Assembler::bl(Label* label, Condition cond) {
  EmitBranch(cond, label, true);
}

void Assembler::bx(Register rm, Condition cond) {
  ASSERT(rm != kNoRegister);
  ASSERT(cond != kNoCondition);
  int32_t encoding = (static_cast<int32_t>(cond) << kConditionShift) | B24 |
                     B21 | (0xfff << 8) | B4 | ArmEncode::Rm(rm);
  Emit(encoding);
}

void Assembler::blx(Register rm, Condition cond) {
  ASSERT(rm != kNoRegister);
  ASSERT(cond != kNoCondition);
  int32_t encoding = (static_cast<int32_t>(cond) << kConditionShift) | B24 |
                     B21 | (0xfff << 8) | B5 | B4 | ArmEncode::Rm(rm);
  Emit(encoding);
}

void Assembler::MarkExceptionHandler(Label* label) {
  EmitType01(AL, 1, TST, 1, PC, R0, Operand(0));
  Label l;
  b(&l);
  EmitBranch(AL, label, false);
  Bind(&l);
}

void Assembler::Drop(intptr_t stack_elements) {
  ASSERT(stack_elements >= 0);
  if (stack_elements > 0) {
    AddImmediate(SP, stack_elements * target::kWordSize);
  }
}

// Uses a code sequence that can easily be decoded.
void Assembler::LoadWordFromPoolIndex(Register rd,
                                      intptr_t index,
                                      Register pp,
                                      Condition cond) {
  ASSERT((pp != PP) || constant_pool_allowed());
  ASSERT(rd != pp);
  // PP is tagged on ARM.
  const int32_t offset =
      target::ObjectPool::element_offset(index) - kHeapObjectTag;
  int32_t offset_mask = 0;
  if (Address::CanHoldLoadOffset(kFourBytes, offset, &offset_mask)) {
    ldr(rd, Address(pp, offset), cond);
  } else {
    int32_t offset_hi = offset & ~offset_mask;  // signed
    uint32_t offset_lo = offset & offset_mask;  // unsigned
    // Inline a simplified version of AddImmediate(rd, pp, offset_hi).
    Operand o;
    if (Operand::CanHold(offset_hi, &o)) {
      add(rd, pp, o, cond);
    } else {
      LoadImmediate(rd, offset_hi, cond);
      add(rd, pp, Operand(rd), cond);
    }
    ldr(rd, Address(rd, offset_lo), cond);
  }
}

void Assembler::StoreWordToPoolIndex(Register value,
                                     intptr_t index,
                                     Register pp,
                                     Condition cond) {
  ASSERT((pp != PP) || constant_pool_allowed());
  ASSERT(value != pp);
  // PP is tagged on ARM.
  const int32_t offset =
      target::ObjectPool::element_offset(index) - kHeapObjectTag;
  int32_t offset_mask = 0;
  if (Address::CanHoldLoadOffset(kFourBytes, offset, &offset_mask)) {
    str(value, Address(pp, offset), cond);
  } else {
    int32_t offset_hi = offset & ~offset_mask;  // signed
    uint32_t offset_lo = offset & offset_mask;  // unsigned
    // Inline a simplified version of AddImmediate(rd, pp, offset_hi).
    Operand o;
    if (Operand::CanHold(offset_hi, &o)) {
      add(TMP, pp, o, cond);
    } else {
      LoadImmediate(TMP, offset_hi, cond);
      add(TMP, pp, Operand(TMP), cond);
    }
    str(value, Address(TMP, offset_lo), cond);
  }
}

void Assembler::CheckCodePointer() {
#ifdef DEBUG
  if (!FLAG_check_code_pointer) {
    return;
  }
  Comment("CheckCodePointer");
  Label cid_ok, instructions_ok;
  Push(R0);
  Push(IP);
  CompareClassId(CODE_REG, kCodeCid, R0);
  b(&cid_ok, EQ);
  bkpt(0);
  Bind(&cid_ok);

  const intptr_t offset = CodeSize() + Instr::kPCReadOffset +
                          target::Instructions::HeaderSize() - kHeapObjectTag;
  mov(R0, Operand(PC));
  AddImmediate(R0, -offset);
  ldr(IP, FieldAddress(CODE_REG, target::Code::instructions_offset()));
  cmp(R0, Operand(IP));
  b(&instructions_ok, EQ);
  bkpt(1);
  Bind(&instructions_ok);
  Pop(IP);
  Pop(R0);
#endif
}

void Assembler::RestoreCodePointer() {
  ldr(CODE_REG,
      Address(FP, target::frame_layout.code_from_fp * target::kWordSize));
  CheckCodePointer();
}

void Assembler::LoadPoolPointer(Register reg) {
  // Load new pool pointer.
  CheckCodePointer();
  ldr(reg, FieldAddress(CODE_REG, target::Code::object_pool_offset()));
  set_constant_pool_allowed(reg == PP);
}

void Assembler::SetupGlobalPoolAndDispatchTable() {
  ASSERT(FLAG_precompiled_mode);
  ldr(PP, Address(THR, target::Thread::global_object_pool_offset()));
  ldr(DISPATCH_TABLE_REG,
      Address(THR, target::Thread::dispatch_table_array_offset()));
}

void Assembler::LoadIsolate(Register rd) {
  ldr(rd, Address(THR, target::Thread::isolate_offset()));
}

void Assembler::LoadIsolateGroup(Register rd) {
  ldr(rd, Address(THR, target::Thread::isolate_group_offset()));
}

bool Assembler::CanLoadFromObjectPool(const Object& object) const {
  ASSERT(IsOriginalObject(object));
  if (!constant_pool_allowed()) {
    return false;
  }

  DEBUG_ASSERT(IsNotTemporaryScopedHandle(object));
  ASSERT(IsInOldSpace(object));
  return true;
}

void Assembler::LoadObjectHelper(
    Register rd,
    const Object& object,
    Condition cond,
    bool is_unique,
    Register pp,
    ObjectPoolBuilderEntry::SnapshotBehavior snapshot_behavior) {
  ASSERT(IsOriginalObject(object));
  // `is_unique == true` effectively means object has to be patchable.
  if (!is_unique) {
    intptr_t offset = 0;
    if (target::CanLoadFromThread(object, &offset)) {
      // Load common VM constants from the thread. This works also in places
      // where no constant pool is set up (e.g. intrinsic code).
      ldr(rd, Address(THR, offset), cond);
      return;
    }
    if (target::IsSmi(object)) {
      // Relocation doesn't apply to Smis.
      LoadImmediate(rd, target::ToRawSmi(object), cond);
      return;
    }
  }
  RELEASE_ASSERT(CanLoadFromObjectPool(object));
  // Make sure that class CallPattern is able to decode this load from the
  // object pool.
  const auto index =
      is_unique
          ? object_pool_builder().AddObject(
                object, ObjectPoolBuilderEntry::kPatchable, snapshot_behavior)
          : object_pool_builder().FindObject(
                object, ObjectPoolBuilderEntry::kNotPatchable,
                snapshot_behavior);
  LoadWordFromPoolIndex(rd, index, pp, cond);
}

void Assembler::LoadObject(Register rd, const Object& object, Condition cond) {
  LoadObjectHelper(rd, object, cond, /* is_unique = */ false, PP);
}

void Assembler::LoadUniqueObject(
    Register rd,
    const Object& object,
    Condition cond,
    ObjectPoolBuilderEntry::SnapshotBehavior snapshot_behavior) {
  LoadObjectHelper(rd, object, cond, /* is_unique = */ true, PP,
                   snapshot_behavior);
}

void Assembler::LoadNativeEntry(Register rd,
                                const ExternalLabel* label,
                                ObjectPoolBuilderEntry::Patchability patchable,
                                Condition cond) {
  const intptr_t index =
      object_pool_builder().FindNativeFunction(label, patchable);
  LoadWordFromPoolIndex(rd, index, PP, cond);
}

void Assembler::PushObject(const Object& object) {
  ASSERT(IsOriginalObject(object));
  LoadObject(IP, object);
  Push(IP);
}

void Assembler::CompareObject(Register rn, const Object& object) {
  ASSERT(IsOriginalObject(object));
  ASSERT(rn != IP);
  if (target::IsSmi(object)) {
    CompareImmediate(rn, target::ToRawSmi(object));
  } else {
    LoadObject(IP, object);
    cmp(rn, Operand(IP));
  }
}

Register UseRegister(Register reg, RegList* used) {
  ASSERT(reg != THR);
  ASSERT(reg != SP);
  ASSERT(reg != FP);
  ASSERT(reg != PC);
  ASSERT((*used & (1 << reg)) == 0);
  *used |= (1 << reg);
  return reg;
}

Register AllocateRegister(RegList* used) {
  const RegList free = ~*used;
  return (free == 0)
             ? kNoRegister
             : UseRegister(
                   static_cast<Register>(Utils::CountTrailingZerosWord(free)),
                   used);
}

void Assembler::StoreBarrier(Register object,
                             Register value,
                             CanBeSmi can_be_smi,
                             Register scratch) {
  // x.slot = x. Barrier should have be removed at the IL level.
  ASSERT(object != value);
  ASSERT(object != LINK_REGISTER);
  ASSERT(value != LINK_REGISTER);
  ASSERT(object != scratch);
  ASSERT(value != scratch);
  ASSERT(scratch != kNoRegister);

  // In parallel, test whether
  //  - object is old and not remembered and value is new, or
  //  - object is old and value is old and not marked and concurrent marking is
  //    in progress
  // If so, call the WriteBarrier stub, which will either add object to the
  // store buffer (case 1) or add value to the marking stack (case 2).
  // Compare UntaggedObject::StorePointer.
  Label done;
  if (can_be_smi == kValueCanBeSmi) {
    BranchIfSmi(value, &done, kNearJump);
  } else {
#if defined(DEBUG)
    Label passed_check;
    BranchIfNotSmi(value, &passed_check, kNearJump);
    Breakpoint();
    Bind(&passed_check);
#endif
  }
  const bool preserve_lr = lr_state().LRContainsReturnAddress();
  if (preserve_lr) {
    SPILLS_LR_TO_FRAME(Push(LR));
  }
  CLOBBERS_LR({
    ldrb(scratch, FieldAddress(object, target::Object::tags_offset()));
    ldrb(LR, FieldAddress(value, target::Object::tags_offset()));
    and_(scratch, LR,
         Operand(scratch, LSR, target::UntaggedObject::kBarrierOverlapShift));
    ldr(LR, Address(THR, target::Thread::write_barrier_mask_offset()));
    tst(scratch, Operand(LR));
  });
  if (value != kWriteBarrierValueReg) {
    // Unlikely. Only non-graph intrinsics.
    // TODO(rmacnak): Shuffle registers in intrinsics.
    Label restore_and_done;
    b(&restore_and_done, ZERO);
    Register objectForCall = object;
    if (object != kWriteBarrierValueReg) {
      Push(kWriteBarrierValueReg);
    } else {
      COMPILE_ASSERT(R2 != kWriteBarrierValueReg);
      COMPILE_ASSERT(R3 != kWriteBarrierValueReg);
      objectForCall = (value == R2) ? R3 : R2;
      PushList((1 << kWriteBarrierValueReg) | (1 << objectForCall));
      mov(objectForCall, Operand(object));
    }
    mov(kWriteBarrierValueReg, Operand(value));
    generate_invoke_write_barrier_wrapper_(AL, objectForCall);

    if (object != kWriteBarrierValueReg) {
      Pop(kWriteBarrierValueReg);
    } else {
      PopList((1 << kWriteBarrierValueReg) | (1 << objectForCall));
    }
    Bind(&restore_and_done);
  } else {
    generate_invoke_write_barrier_wrapper_(NE, object);
  }
  if (preserve_lr) {
    RESTORES_LR_FROM_FRAME(Pop(LR));
  }
  Bind(&done);
}

void Assembler::ArrayStoreBarrier(Register object,
                                  Register slot,
                                  Register value,
                                  CanBeSmi can_be_smi,
                                  Register scratch) {
  ASSERT(object != LINK_REGISTER);
  ASSERT(value != LINK_REGISTER);
  ASSERT(slot != LINK_REGISTER);
  ASSERT(object != scratch);
  ASSERT(value != scratch);
  ASSERT(slot != scratch);
  ASSERT(scratch != kNoRegister);

  // In parallel, test whether
  //  - object is old and not remembered and value is new, or
  //  - object is old and value is old and not marked and concurrent marking is
  //    in progress
  // If so, call the WriteBarrier stub, which will either add object to the
  // store buffer (case 1) or add value to the marking stack (case 2).
  // Compare UntaggedObject::StorePointer.
  Label done;
  if (can_be_smi == kValueCanBeSmi) {
    BranchIfSmi(value, &done, kNearJump);
  } else {
#if defined(DEBUG)
    Label passed_check;
    BranchIfNotSmi(value, &passed_check, kNearJump);
    Breakpoint();
    Bind(&passed_check);
#endif
  }
  const bool preserve_lr = lr_state().LRContainsReturnAddress();
  if (preserve_lr) {
    SPILLS_LR_TO_FRAME(Push(LR));
  }

  CLOBBERS_LR({
    ldrb(scratch, FieldAddress(object, target::Object::tags_offset()));
    ldrb(LR, FieldAddress(value, target::Object::tags_offset()));
    and_(scratch, LR,
         Operand(scratch, LSR, target::UntaggedObject::kBarrierOverlapShift));
    ldr(LR, Address(THR, target::Thread::write_barrier_mask_offset()));
    tst(scratch, Operand(LR));
  });

  if ((object != kWriteBarrierObjectReg) || (value != kWriteBarrierValueReg) ||
      (slot != kWriteBarrierSlotReg)) {
    // Spill and shuffle unimplemented. Currently StoreIntoArray is only used
    // from StoreIndexInstr, which gets these exact registers from the register
    // allocator.
    UNIMPLEMENTED();
  }
  generate_invoke_array_write_barrier_(NE);
  if (preserve_lr) {
    RESTORES_LR_FROM_FRAME(Pop(LR));
  }
  Bind(&done);
}

void Assembler::StoreObjectIntoObjectNoBarrier(Register object,
                                               const Address& dest,
                                               const Object& value,
                                               MemoryOrder memory_order,
                                               OperandSize size) {
  ASSERT_EQUAL(size, kFourBytes);
  ASSERT_EQUAL(dest.mode(), Address::Mode::Offset);
  ASSERT_EQUAL(dest.kind(), Address::OffsetKind::Immediate);
  int32_t ignored = 0;
  Register scratch = TMP;
  if (!Address::CanHoldStoreOffset(size, dest.offset(), &ignored)) {
    // As there is no TMP2 on ARM7, Store uses TMP when the instruction cannot
    // contain the offset, so we need to use a different scratch register
    // for loading the object.
    scratch = dest.base() == R9 ? R8 : R9;
    Push(scratch);
  }
  ASSERT(IsOriginalObject(value));
  DEBUG_ASSERT(IsNotTemporaryScopedHandle(value));
  // No store buffer update.
  LoadObject(scratch, value);
  if (memory_order == kRelease) {
    StoreRelease(scratch, dest);
  } else {
    Store(scratch, dest);
  }
  if (scratch != TMP) {
    Pop(scratch);
  }
}

void Assembler::VerifyStoreNeedsNoWriteBarrier(Register object,
                                               Register value) {
  // We can't assert the incremental barrier is not needed here, only the
  // generational barrier. We sometimes omit the write barrier when 'value' is
  // a constant, but we don't eagerly mark 'value' and instead assume it is also
  // reachable via a constant pool, so it doesn't matter if it is not traced via
  // 'object'.
  Label done;
  BranchIfSmi(value, &done, kNearJump);
  ldrb(TMP, FieldAddress(value, target::Object::tags_offset()));
  tst(TMP, Operand(1 << target::UntaggedObject::kNewOrEvacuationCandidateBit));
  b(&done, ZERO);
  ldrb(TMP, FieldAddress(object, target::Object::tags_offset()));
  tst(TMP, Operand(1 << target::UntaggedObject::kOldAndNotRememberedBit));
  b(&done, ZERO);
  Stop("Write barrier is required");
  Bind(&done);
}

void Assembler::StoreInternalPointer(Register object,
                                     const Address& dest,
                                     Register value) {
  str(value, dest);
}

void Assembler::InitializeFieldsNoBarrier(Register object,
                                          Register begin,
                                          Register end,
                                          Register value_even,
                                          Register value_odd) {
  ASSERT(value_odd == value_even + 1);
  Label init_loop;
  Bind(&init_loop);
  AddImmediate(begin, 2 * target::kWordSize);
  cmp(begin, Operand(end));
  strd(value_even, value_odd, begin, -2 * target::kWordSize, LS);
  b(&init_loop, CC);
  str(value_even, Address(begin, -2 * target::kWordSize), HI);
}

void Assembler::InitializeFieldsNoBarrierUnrolled(Register object,
                                                  Register base,
                                                  intptr_t begin_offset,
                                                  intptr_t end_offset,
                                                  Register value_even,
                                                  Register value_odd) {
  ASSERT(value_odd == value_even + 1);
  intptr_t current_offset = begin_offset;
  while (current_offset + target::kWordSize < end_offset) {
    strd(value_even, value_odd, base, current_offset);
    current_offset += 2 * target::kWordSize;
  }
  while (current_offset < end_offset) {
    str(value_even, Address(base, current_offset));
    current_offset += target::kWordSize;
  }
}

void Assembler::StoreIntoSmiField(const Address& dest, Register value) {
#if defined(DEBUG)
  Label done;
  tst(value, Operand(kHeapObjectTag));
  b(&done, EQ);
  Stop("New value must be Smi.");
  Bind(&done);
#endif  // defined(DEBUG)
  Store(value, dest);
}

void Assembler::ExtractClassIdFromTags(Register result,
                                       Register tags,
                                       Condition cond) {
  ASSERT(target::UntaggedObject::kClassIdTagPos == 12);
  ASSERT(target::UntaggedObject::kClassIdTagSize == 20);
  ubfx(result, tags, target::UntaggedObject::kClassIdTagPos,
       target::UntaggedObject::kClassIdTagSize, cond);
}

void Assembler::ExtractInstanceSizeFromTags(Register result, Register tags) {
  ASSERT(target::UntaggedObject::kSizeTagPos == 8);
  ASSERT(target::UntaggedObject::kSizeTagSize == 4);
  Lsr(result, tags,
      Operand(target::UntaggedObject::kSizeTagPos -
              target::ObjectAlignment::kObjectAlignmentLog2),
      AL);
  AndImmediate(result, result,
               (Utils::NBitMask(target::UntaggedObject::kSizeTagSize)
                << target::ObjectAlignment::kObjectAlignmentLog2));
}

void Assembler::LoadClassId(Register result, Register object, Condition cond) {
  ldr(result, FieldAddress(object, target::Object::tags_offset()), cond);
  ExtractClassIdFromTags(result, result, cond);
}

void Assembler::LoadClassById(Register result, Register class_id) {
  ASSERT(result != class_id);

  const intptr_t table_offset =
      target::IsolateGroup::cached_class_table_table_offset();

  LoadIsolateGroup(result);
  LoadFromOffset(result, result, table_offset);
  ldr(result, Address(result, class_id, LSL, target::kWordSizeLog2));
}

void Assembler::CompareClassId(Register object,
                               intptr_t class_id,
                               Register scratch) {
  LoadClassId(scratch, object);
  CompareImmediate(scratch, class_id);
}

void Assembler::LoadClassIdMayBeSmi(Register result, Register object) {
  tst(object, Operand(kSmiTagMask));
  LoadClassId(result, object, NE);
  LoadImmediate(result, kSmiCid, EQ);
}

void Assembler::LoadTaggedClassIdMayBeSmi(Register result, Register object) {
  LoadClassIdMayBeSmi(result, object);
  SmiTag(result);
}

void Assembler::EnsureHasClassIdInDEBUG(intptr_t cid,
                                        Register src,
                                        Register scratch,
                                        bool can_be_null) {
#if defined(DEBUG)
  Comment("Check that object in register has cid %" Pd "", cid);
  Label matches;
  LoadClassIdMayBeSmi(scratch, src);
  CompareImmediate(scratch, cid);
  BranchIf(EQUAL, &matches, Assembler::kNearJump);
  if (can_be_null) {
    CompareImmediate(scratch, kNullCid);
    BranchIf(EQUAL, &matches, Assembler::kNearJump);
  }
  Breakpoint();
  Bind(&matches);
#endif
}

void Assembler::BailoutIfInvalidBranchOffset(int32_t offset) {
  if (!CanEncodeBranchDistance(offset)) {
    ASSERT(!use_far_branches());
    BailoutWithBranchOffsetError();
  }
}

int32_t Assembler::EncodeBranchOffset(int32_t offset, int32_t inst) {
  // The offset is off by 8 due to the way the ARM CPUs read PC.
  offset -= Instr::kPCReadOffset;

  // Properly preserve only the bits supported in the instruction.
  offset >>= 2;
  offset &= kBranchOffsetMask;
  return (inst & ~kBranchOffsetMask) | offset;
}

int Assembler::DecodeBranchOffset(int32_t inst) {
  // Sign-extend, left-shift by 2, then add 8.
  return ((((inst & kBranchOffsetMask) << 8) >> 6) + Instr::kPCReadOffset);
}

static int32_t DecodeARMv7LoadImmediate(int32_t movt, int32_t movw) {
  int32_t offset = 0;
  offset |= (movt & 0xf0000) << 12;
  offset |= (movt & 0xfff) << 16;
  offset |= (movw & 0xf0000) >> 4;
  offset |= movw & 0xfff;
  return offset;
}

class PatchFarBranch : public AssemblerFixup {
 public:
  PatchFarBranch() {}

  void Process(const MemoryRegion& region, intptr_t position) {
    ProcessARMv7(region, position);
  }

 private:
  void ProcessARMv7(const MemoryRegion& region, intptr_t position) {
    const int32_t movw = region.Load<int32_t>(position);
    const int32_t movt = region.Load<int32_t>(position + Instr::kInstrSize);
    const int32_t bx = region.Load<int32_t>(position + 2 * Instr::kInstrSize);

    if (((movt & 0xfff0f000) == 0xe340c000) &&  // movt IP, high
        ((movw & 0xfff0f000) == 0xe300c000)) {  // movw IP, low
      const int32_t offset = DecodeARMv7LoadImmediate(movt, movw);
      const int32_t dest = region.start() + offset;
      const uint16_t dest_high = Utils::High16Bits(dest);
      const uint16_t dest_low = Utils::Low16Bits(dest);
      const int32_t patched_movt =
          0xe340c000 | ((dest_high >> 12) << 16) | (dest_high & 0xfff);
      const int32_t patched_movw =
          0xe300c000 | ((dest_low >> 12) << 16) | (dest_low & 0xfff);

      region.Store<int32_t>(position, patched_movw);
      region.Store<int32_t>(position + Instr::kInstrSize, patched_movt);
      return;
    }

    // If the offset loading instructions aren't there, we must have replaced
    // the far branch with a near one, and so these instructions
    // should be NOPs.
    ASSERT((movt == Instr::kNopInstruction) && (bx == Instr::kNopInstruction));
  }

  virtual bool IsPointerOffset() const { return false; }
};

void Assembler::EmitFarBranch(Condition cond, int32_t offset, bool link) {
  buffer_.EmitFixup(new PatchFarBranch());
  LoadPatchableImmediate(IP, offset);
  if (link) {
    blx(IP, cond);
  } else {
    bx(IP, cond);
  }
}

void Assembler::EmitBranch(Condition cond, Label* label, bool link) {
  if (label->IsBound()) {
    const int32_t dest = label->Position() - buffer_.Size();
    if (use_far_branches() && !CanEncodeBranchDistance(dest)) {
      EmitFarBranch(cond, label->Position(), link);
    } else {
      EmitType5(cond, dest, link);
    }
    label->UpdateLRState(lr_state());
  } else {
    const intptr_t position = buffer_.Size();
    if (use_far_branches()) {
      const int32_t dest = label->position_;
      EmitFarBranch(cond, dest, link);
    } else {
      // Use the offset field of the branch instruction for linking the sites.
      EmitType5(cond, label->position_, link);
    }
    label->LinkTo(position, lr_state());
  }
}

void Assembler::BindARMv7(Label* label) {
  ASSERT(!label->IsBound());
  intptr_t bound_pc = buffer_.Size();
  while (label->IsLinked()) {
    const int32_t position = label->Position();
    int32_t dest = bound_pc - position;
    if (use_far_branches() && !CanEncodeBranchDistance(dest)) {
      // Far branches are enabled and we can't encode the branch offset.

      // Grab instructions that load the offset.
      const int32_t movw =
          buffer_.Load<int32_t>(position + 0 * Instr::kInstrSize);
      const int32_t movt =
          buffer_.Load<int32_t>(position + 1 * Instr::kInstrSize);

      // Change from relative to the branch to relative to the assembler
      // buffer.
      dest = buffer_.Size();
      const uint16_t dest_high = Utils::High16Bits(dest);
      const uint16_t dest_low = Utils::Low16Bits(dest);
      const int32_t patched_movt =
          0xe340c000 | ((dest_high >> 12) << 16) | (dest_high & 0xfff);
      const int32_t patched_movw =
          0xe300c000 | ((dest_low >> 12) << 16) | (dest_low & 0xfff);

      // Rewrite the instructions.
      buffer_.Store<int32_t>(position + 0 * Instr::kInstrSize, patched_movw);
      buffer_.Store<int32_t>(position + 1 * Instr::kInstrSize, patched_movt);
      label->position_ = DecodeARMv7LoadImmediate(movt, movw);
    } else if (use_far_branches() && CanEncodeBranchDistance(dest)) {
      // Far branches are enabled, but we can encode the branch offset.

      // Grab instructions that load the offset, and the branch.
      const int32_t movw =
          buffer_.Load<int32_t>(position + 0 * Instr::kInstrSize);
      const int32_t movt =
          buffer_.Load<int32_t>(position + 1 * Instr::kInstrSize);
      const int32_t branch =
          buffer_.Load<int32_t>(position + 2 * Instr::kInstrSize);

      // Grab the branch condition, and encode the link bit.
      const int32_t cond = branch & 0xf0000000;
      const int32_t link = (branch & 0x20) << 19;

      // Encode the branch and the offset.
      const int32_t new_branch = cond | link | 0x0a000000;
      const int32_t encoded = EncodeBranchOffset(dest, new_branch);

      // Write the encoded branch instruction followed by two nops.
      buffer_.Store<int32_t>(position + 0 * Instr::kInstrSize, encoded);
      buffer_.Store<int32_t>(position + 1 * Instr::kInstrSize,
                             Instr::kNopInstruction);
      buffer_.Store<int32_t>(position + 2 * Instr::kInstrSize,
                             Instr::kNopInstruction);

      label->position_ = DecodeARMv7LoadImmediate(movt, movw);
    } else {
      BailoutIfInvalidBranchOffset(dest);
      int32_t next = buffer_.Load<int32_t>(position);
      int32_t encoded = Assembler::EncodeBranchOffset(dest, next);
      buffer_.Store<int32_t>(position, encoded);
      label->position_ = Assembler::DecodeBranchOffset(next);
    }
  }
  label->BindTo(bound_pc, lr_state());
}

void Assembler::Bind(Label* label) {
  BindARMv7(label);
}

OperandSize Address::OperandSizeFor(intptr_t cid) {
  auto const rep = RepresentationUtils::RepresentationOfArrayElement(cid);
  switch (rep) {
    case kUnboxedInt64:
      return kDWord;
    case kUnboxedFloat:
      return kSWord;
    case kUnboxedDouble:
      return kDWord;
    case kUnboxedInt32x4:
    case kUnboxedFloat32x4:
    case kUnboxedFloat64x2:
      return kRegList;
    default:
      return RepresentationUtils::OperandSize(rep);
  }
}

bool Address::CanHoldLoadOffset(OperandSize size,
                                int32_t offset,
                                int32_t* offset_mask) {
  switch (size) {
    case kByte:
    case kTwoBytes:
    case kUnsignedTwoBytes:
    case kWordPair: {
      *offset_mask = 0xff;
      return Utils::MagnitudeIsUint(8, offset);  // Addressing mode 3.
    }
    case kUnsignedByte:
    case kFourBytes:
    case kUnsignedFourBytes: {
      *offset_mask = 0xfff;
      return Utils::MagnitudeIsUint(12, offset);  // Addressing mode 2.
    }
    case kSWord:
    case kDWord: {
      *offset_mask = 0x3fc;  // Multiple of 4.
      // VFP addressing mode.
      return (Utils::MagnitudeIsUint(10, offset) &&
              Utils::IsAligned(offset, 4));
    }
    case kRegList: {
      *offset_mask = 0x0;
      return offset == 0;
    }
    default: {
      UNREACHABLE();
      return false;
    }
  }
}

bool Address::CanHoldStoreOffset(OperandSize size,
                                 int32_t offset,
                                 int32_t* offset_mask) {
  switch (size) {
    case kTwoBytes:
    case kUnsignedTwoBytes:
    case kWordPair: {
      *offset_mask = 0xff;
      return Utils::MagnitudeIsUint(8, offset);  // Addressing mode 3.
    }
    case kByte:
    case kUnsignedByte:
    case kFourBytes:
    case kUnsignedFourBytes: {
      *offset_mask = 0xfff;
      return Utils::MagnitudeIsUint(12, offset);  // Addressing mode 2.
    }
    case kSWord:
    case kDWord: {
      *offset_mask = 0x3fc;  // Multiple of 4.
      // VFP addressing mode.
      return (Utils::MagnitudeIsUint(10, offset) &&
              Utils::IsAligned(offset, 4));
    }
    case kRegList: {
      *offset_mask = 0x0;
      return offset == 0;
    }
    default: {
      UNREACHABLE();
      return false;
    }
  }
}

bool Address::CanHoldImmediateOffset(bool is_load,
                                     intptr_t cid,
                                     int64_t offset) {
  int32_t offset_mask = 0;
  if (is_load) {
    return CanHoldLoadOffset(OperandSizeFor(cid), offset, &offset_mask);
  } else {
    return CanHoldStoreOffset(OperandSizeFor(cid), offset, &offset_mask);
  }
}

void Assembler::Push(Register rd, Condition cond) {
  str(rd, Address(SP, -target::kWordSize, Address::PreIndex), cond);
}

void Assembler::Pop(Register rd, Condition cond) {
  ldr(rd, Address(SP, target::kWordSize, Address::PostIndex), cond);
}

void Assembler::PushList(RegList regs, Condition cond) {
  stm(DB_W, SP, regs, cond);
}

void Assembler::PopList(RegList regs, Condition cond) {
  ldm(IA_W, SP, regs, cond);
}

void Assembler::PushQuad(FpuRegister reg, Condition cond) {
  DRegister dreg = EvenDRegisterOf(reg);
  vstmd(DB_W, SP, dreg, 2, cond);  // 2 D registers per Q register.
}

void Assembler::PopQuad(FpuRegister reg, Condition cond) {
  DRegister dreg = EvenDRegisterOf(reg);
  vldmd(IA_W, SP, dreg, 2, cond);  // 2 D registers per Q register.
}

void Assembler::PushRegisters(const RegisterSet& regs) {
  const intptr_t fpu_regs_count = regs.FpuRegisterCount();
  if (fpu_regs_count > 0) {
    AddImmediate(SP, -(fpu_regs_count * kFpuRegisterSize));
    // Store fpu registers with the lowest register number at the lowest
    // address.
    intptr_t offset = 0;
    mov(TMP, Operand(SP));
    for (intptr_t i = 0; i < kNumberOfFpuRegisters; ++i) {
      QRegister fpu_reg = static_cast<QRegister>(i);
      if (regs.ContainsFpuRegister(fpu_reg)) {
        DRegister d = EvenDRegisterOf(fpu_reg);
        ASSERT(d + 1 == OddDRegisterOf(fpu_reg));
        vstmd(IA_W, IP, d, 2);
        offset += kFpuRegisterSize;
      }
    }
    ASSERT(offset == (fpu_regs_count * kFpuRegisterSize));
  }

  // The order in which the registers are pushed must match the order
  // in which the registers are encoded in the safe point's stack map.
  // NOTE: This matches the order of ARM's multi-register push.
  RegList reg_list = 0;
  for (intptr_t i = kNumberOfCpuRegisters - 1; i >= 0; --i) {
    Register reg = static_cast<Register>(i);
    if (regs.ContainsRegister(reg)) {
      reg_list |= (1 << reg);
    }
  }
  if (reg_list != 0) {
    PushList(reg_list);
  }
}

void Assembler::PopRegisters(const RegisterSet& regs) {
  RegList reg_list = 0;
  for (intptr_t i = kNumberOfCpuRegisters - 1; i >= 0; --i) {
    Register reg = static_cast<Register>(i);
    if (regs.ContainsRegister(reg)) {
      reg_list |= (1 << reg);
    }
  }
  if (reg_list != 0) {
    PopList(reg_list);
  }

  const intptr_t fpu_regs_count = regs.FpuRegisterCount();
  if (fpu_regs_count > 0) {
    // Fpu registers have the lowest register number at the lowest address.
    intptr_t offset = 0;
    for (intptr_t i = 0; i < kNumberOfFpuRegisters; ++i) {
      QRegister fpu_reg = static_cast<QRegister>(i);
      if (regs.ContainsFpuRegister(fpu_reg)) {
        DRegister d = EvenDRegisterOf(fpu_reg);
        ASSERT(d + 1 == OddDRegisterOf(fpu_reg));
        vldmd(IA_W, SP, d, 2);
        offset += kFpuRegisterSize;
      }
    }
    ASSERT(offset == (fpu_regs_count * kFpuRegisterSize));
  }
}

void Assembler::PushRegistersInOrder(std::initializer_list<Register> regs) {
  // Collect the longest descending sequences of registers and
  // push them with a single STMDB instruction.
  RegList pending_regs = 0;
  Register lowest_pending_reg = kNumberOfCpuRegisters;
  intptr_t num_pending_regs = 0;
  for (Register reg : regs) {
    if (reg >= lowest_pending_reg) {
      ASSERT(pending_regs != 0);
      if (num_pending_regs > 1) {
        PushList(pending_regs);
      } else {
        Push(lowest_pending_reg);
      }
      pending_regs = 0;
      num_pending_regs = 0;
    }
    pending_regs |= (1 << reg);
    lowest_pending_reg = reg;
    ++num_pending_regs;
  }
  if (pending_regs != 0) {
    if (num_pending_regs > 1) {
      PushList(pending_regs);
    } else {
      Push(lowest_pending_reg);
    }
  }
}

void Assembler::PushNativeCalleeSavedRegisters() {
  // Save new context and C++ ABI callee-saved registers.
  PushList(kAbiPreservedCpuRegs);

  const DRegister firstd = EvenDRegisterOf(kAbiFirstPreservedFpuReg);
  ASSERT(2 * kAbiPreservedFpuRegCount < 16);
  // Save FPU registers. 2 D registers per Q register.
  vstmd(DB_W, SP, firstd, 2 * kAbiPreservedFpuRegCount);
}

void Assembler::PopNativeCalleeSavedRegisters() {
  const DRegister firstd = EvenDRegisterOf(kAbiFirstPreservedFpuReg);
  // Restore C++ ABI callee-saved registers.
  // Restore FPU registers. 2 D registers per Q register.
  vldmd(IA_W, SP, firstd, 2 * kAbiPreservedFpuRegCount);
  // Restore CPU registers.
  PopList(kAbiPreservedCpuRegs);
}

void Assembler::ExtendValue(Register rd,
                            Register rm,
                            OperandSize sz,
                            Condition cond) {
  switch (sz) {
    case kUnsignedFourBytes:
    case kFourBytes:
      if (rd == rm) return;
      return mov(rd, Operand(rm), cond);
    case kUnsignedTwoBytes:
      return ubfx(rd, rm, 0, kBitsPerInt16, cond);
    case kTwoBytes:
      return sbfx(rd, rm, 0, kBitsPerInt16, cond);
    case kUnsignedByte:
      return ubfx(rd, rm, 0, kBitsPerInt8, cond);
    case kByte:
      return sbfx(rd, rm, 0, kBitsPerInt8, cond);
    default:
      UNIMPLEMENTED();
      break;
  }
}

void Assembler::Lsl(Register rd,
                    Register rm,
                    const Operand& shift_imm,
                    Condition cond) {
  ASSERT(shift_imm.type() == 1);
  ASSERT(shift_imm.encoding() != 0);  // Do not use Lsl if no shift is wanted.
  mov(rd, Operand(rm, LSL, shift_imm.encoding()), cond);
}

void Assembler::Lsl(Register rd, Register rm, Register rs, Condition cond) {
  mov(rd, Operand(rm, LSL, rs), cond);
}

void Assembler::Lsr(Register rd,
                    Register rm,
                    const Operand& shift_imm,
                    Condition cond) {
  ASSERT(shift_imm.type() == 1);
  uint32_t shift = shift_imm.encoding();
  ASSERT(shift != 0);  // Do not use Lsr if no shift is wanted.
  if (shift == 32) {
    shift = 0;  // Comply to UAL syntax.
  }
  mov(rd, Operand(rm, LSR, shift), cond);
}

void Assembler::Lsr(Register rd, Register rm, Register rs, Condition cond) {
  mov(rd, Operand(rm, LSR, rs), cond);
}

void Assembler::Asr(Register rd,
                    Register rm,
                    const Operand& shift_imm,
                    Condition cond) {
  ASSERT(shift_imm.type() == 1);
  uint32_t shift = shift_imm.encoding();
  ASSERT(shift != 0);  // Do not use Asr if no shift is wanted.
  if (shift == 32) {
    shift = 0;  // Comply to UAL syntax.
  }
  mov(rd, Operand(rm, ASR, shift), cond);
}

void Assembler::Asrs(Register rd,
                     Register rm,
                     const Operand& shift_imm,
                     Condition cond) {
  ASSERT(shift_imm.type() == 1);
  uint32_t shift = shift_imm.encoding();
  ASSERT(shift != 0);  // Do not use Asr if no shift is wanted.
  if (shift == 32) {
    shift = 0;  // Comply to UAL syntax.
  }
  movs(rd, Operand(rm, ASR, shift), cond);
}

void Assembler::Asr(Register rd, Register rm, Register rs, Condition cond) {
  mov(rd, Operand(rm, ASR, rs), cond);
}

void Assembler::Ror(Register rd,
                    Register rm,
                    const Operand& shift_imm,
                    Condition cond) {
  ASSERT(shift_imm.type() == 1);
  ASSERT(shift_imm.encoding() != 0);  // Use Rrx instruction.
  mov(rd, Operand(rm, ROR, shift_imm.encoding()), cond);
}

void Assembler::Ror(Register rd, Register rm, Register rs, Condition cond) {
  mov(rd, Operand(rm, ROR, rs), cond);
}

void Assembler::Rrx(Register rd, Register rm, Condition cond) {
  mov(rd, Operand(rm, ROR, 0), cond);
}

void Assembler::SignFill(Register rd, Register rm, Condition cond) {
  Asr(rd, rm, Operand(31), cond);
}

void Assembler::Vreciprocalqs(QRegister qd, QRegister qm) {
  ASSERT(qm != QTMP);
  ASSERT(qd != QTMP);

  // Reciprocal estimate.
  vrecpeqs(qd, qm);
  // 2 Newton-Raphson steps.
  vrecpsqs(QTMP, qm, qd);
  vmulqs(qd, qd, QTMP);
  vrecpsqs(QTMP, qm, qd);
  vmulqs(qd, qd, QTMP);
}

void Assembler::VreciprocalSqrtqs(QRegister qd, QRegister qm) {
  ASSERT(qm != QTMP);
  ASSERT(qd != QTMP);

  // Reciprocal square root estimate.
  vrsqrteqs(qd, qm);
  // 2 Newton-Raphson steps. xn+1 = xn * (3 - Q1*xn^2) / 2.
  // First step.
  vmulqs(QTMP, qd, qd);       // QTMP <- xn^2
  vrsqrtsqs(QTMP, qm, QTMP);  // QTMP <- (3 - Q1*QTMP) / 2.
  vmulqs(qd, qd, QTMP);       // xn+1 <- xn * QTMP
  // Second step.
  vmulqs(QTMP, qd, qd);
  vrsqrtsqs(QTMP, qm, QTMP);
  vmulqs(qd, qd, QTMP);
}

void Assembler::Vsqrtqs(QRegister qd, QRegister qm, QRegister temp) {
  ASSERT(temp != QTMP);
  ASSERT(qm != QTMP);
  ASSERT(qd != QTMP);

  if (temp != kNoQRegister) {
    vmovq(temp, qm);
    qm = temp;
  }

  VreciprocalSqrtqs(qd, qm);
  vmovq(qm, qd);
  Vreciprocalqs(qd, qm);
}

void Assembler::Vdivqs(QRegister qd, QRegister qn, QRegister qm) {
  ASSERT(qd != QTMP);
  ASSERT(qn != QTMP);
  ASSERT(qm != QTMP);

  Vreciprocalqs(qd, qm);
  vmulqs(qd, qn, qd);
}

void Assembler::Branch(const Address& address, Condition cond) {
  ldr(PC, address, cond);
}

void Assembler::BranchLink(intptr_t target_code_pool_index,
                           CodeEntryKind entry_kind) {
  CLOBBERS_LR({
    // Avoid clobbering CODE_REG when invoking code in precompiled mode.
    // We don't actually use CODE_REG in the callee and caller might
    // be using CODE_REG for a live value (e.g. a value that is alive
    // across invocation of a shared stub like the one we use for
    // allocating Mint boxes).
    const Register code_reg = FLAG_precompiled_mode ? LR : CODE_REG;
    LoadWordFromPoolIndex(code_reg, target_code_pool_index, PP, AL);
    Call(FieldAddress(code_reg, target::Code::entry_point_offset(entry_kind)));
  });
}

void Assembler::BranchLink(
    const Code& target,
    ObjectPoolBuilderEntry::Patchability patchable,
    CodeEntryKind entry_kind,
    ObjectPoolBuilderEntry::SnapshotBehavior snapshot_behavior) {
  // Make sure that class CallPattern is able to patch the label referred
  // to by this code sequence.
  // For added code robustness, use 'blx lr' in a patchable sequence and
  // use 'blx ip' in a non-patchable sequence (see other BranchLink flavors).
  const intptr_t index = object_pool_builder().FindObject(
      ToObject(target), patchable, snapshot_behavior);
  BranchLink(index, entry_kind);
}

void Assembler::BranchLinkPatchable(
    const Code& target,
    CodeEntryKind entry_kind,
    ObjectPoolBuilderEntry::SnapshotBehavior snapshot_behavior) {
  BranchLink(target, ObjectPoolBuilderEntry::kPatchable, entry_kind,
             snapshot_behavior);
}

void Assembler::BranchLinkWithEquivalence(const Code& target,
                                          const Object& equivalence,
                                          CodeEntryKind entry_kind) {
  // Make sure that class CallPattern is able to patch the label referred
  // to by this code sequence.
  // For added code robustness, use 'blx lr' in a patchable sequence and
  // use 'blx ip' in a non-patchable sequence (see other BranchLink flavors).
  const intptr_t index =
      object_pool_builder().FindObject(ToObject(target), equivalence);
  BranchLink(index, entry_kind);
}

void Assembler::BranchLink(const ExternalLabel* label) {
  CLOBBERS_LR({
    LoadImmediate(LR, label->address());  // Target address is never patched.
    blx(LR);  // Use blx instruction so that the return branch prediction works.
  });
}

void Assembler::BranchLinkOffset(Register base, int32_t offset) {
  ASSERT(base != PC);
  ASSERT(base != IP);
  LoadFromOffset(IP, base, offset);
  blx(IP);  // Use blx instruction so that the return branch prediction works.
}

void Assembler::LoadPatchableImmediate(Register rd,
                                       int32_t value,
                                       Condition cond) {
  const uint16_t value_low = Utils::Low16Bits(value);
  const uint16_t value_high = Utils::High16Bits(value);
  movw(rd, value_low, cond);
  movt(rd, value_high, cond);
}

void Assembler::LoadDecodableImmediate(Register rd,
                                       int32_t value,
                                       Condition cond) {
  movw(rd, Utils::Low16Bits(value), cond);
  const uint16_t value_high = Utils::High16Bits(value);
  if (value_high != 0) {
    movt(rd, value_high, cond);
  }
}

void Assembler::LoadImmediate(Register rd, Immediate value, Condition cond) {
  LoadImmediate(rd, value.value(), cond);
}

void Assembler::LoadImmediate(Register rd, int32_t value, Condition cond) {
  Operand o;
  if (Operand::CanHold(value, &o)) {
    mov(rd, o, cond);
  } else if (Operand::CanHold(~value, &o)) {
    mvn_(rd, o, cond);
  } else {
    LoadDecodableImmediate(rd, value, cond);
  }
}

void Assembler::LoadSImmediate(SRegister sd, float value, Condition cond) {
  if (!vmovs(sd, value, cond)) {
    const DRegister dd = static_cast<DRegister>(sd >> 1);
    const int index = sd & 1;
    LoadImmediate(IP, bit_cast<int32_t, float>(value), cond);
    vmovdr(dd, index, IP, cond);
  }
}

void Assembler::LoadDImmediate(DRegister dd,
                               double value,
                               Register scratch,
                               Condition cond) {
  ASSERT(scratch != PC);
  ASSERT(scratch != IP);
  if (vmovd(dd, value, cond)) return;

  int64_t imm64 = bit_cast<int64_t, double>(value);
  if (constant_pool_allowed()) {
    intptr_t index = object_pool_builder().FindImmediate64(imm64);
    intptr_t offset =
        target::ObjectPool::element_offset(index) - kHeapObjectTag;
    LoadDFromOffset(dd, PP, offset, cond);
  } else {
    // A scratch register and IP are needed to load an arbitrary double.
    ASSERT(scratch != kNoRegister);
    int64_t imm64 = bit_cast<int64_t, double>(value);
    LoadImmediate(IP, Utils::Low32Bits(imm64), cond);
    LoadImmediate(scratch, Utils::High32Bits(imm64), cond);
    vmovdrr(dd, IP, scratch, cond);
  }
}

void Assembler::LoadQImmediate(QRegister qd, simd128_value_t value) {
  ASSERT(constant_pool_allowed());
  intptr_t index = object_pool_builder().FindImmediate128(value);
  intptr_t offset = target::ObjectPool::element_offset(index) - kHeapObjectTag;
  LoadMultipleDFromOffset(EvenDRegisterOf(qd), 2, PP, offset);
}

Address Assembler::PrepareLargeLoadOffset(const Address& address,
                                          OperandSize size,
                                          Condition cond) {
  ASSERT(size != kWordPair);
  if (address.kind() != Address::Immediate) {
    return address;
  }
  int32_t offset = address.offset();
  int32_t offset_mask = 0;
  if (Address::CanHoldLoadOffset(size, offset, &offset_mask)) {
    return address;
  }
  auto mode = address.mode();
  // If the retrieved offset is negative, then the U bit was flipped during
  // encoding, so re-flip it.
  if (offset < 0) {
    mode = static_cast<Address::Mode>(mode ^ U);
  }
  // If writing back post-indexing, we can't separate the instruction into
  // two parts and the offset must fit.
  ASSERT((mode | U) != Address::PostIndex);
  // If we're writing back pre-indexing, we must add directly to the base,
  // otherwise we use TMP.
  Register base = address.base();
  ASSERT(base != TMP || address.has_writeback());
  Register temp = address.has_writeback() ? base : TMP;
  AddImmediate(temp, base, offset & ~offset_mask, cond);
  base = temp;
  offset = offset & offset_mask;
  return Address(base, offset, mode);
}

Address Assembler::PrepareLargeStoreOffset(const Address& address,
                                           OperandSize size,
                                           Condition cond) {
  ASSERT(size != kWordPair);
  if (address.kind() != Address::Immediate) {
    return address;
  }
  int32_t offset = address.offset();
  int32_t offset_mask = 0;
  if (Address::CanHoldStoreOffset(size, offset, &offset_mask)) {
    return address;
  }
  auto mode = address.mode();
  // If the retrieved offset is negative, then the U bit was flipped during
  // encoding, so re-flip it.
  if (offset < 0) {
    mode = static_cast<Address::Mode>(mode ^ U);
  }
  // If writing back post-indexing, we can't separate the instruction into
  // two parts and the offset must fit.
  ASSERT((mode | U) != Address::PostIndex);
  // If we're writing back pre-indexing, we must add directly to the base,
  // otherwise we use TMP.
  Register base = address.base();
  ASSERT(base != TMP || address.has_writeback());
  Register temp = address.has_writeback() ? base : TMP;
  AddImmediate(temp, base, offset & ~offset_mask, cond);
  base = temp;
  offset = offset & offset_mask;
  return Address(base, offset, mode);
}

void Assembler::Load(Register reg,
                     const Address& address,
                     OperandSize size,
                     Condition cond) {
  const Address& addr = PrepareLargeLoadOffset(address, size, cond);
  switch (size) {
    case kByte:
      ldrsb(reg, addr, cond);
      break;
    case kUnsignedByte:
      ldrb(reg, addr, cond);
      break;
    case kTwoBytes:
      ldrsh(reg, addr, cond);
      break;
    case kUnsignedTwoBytes:
      ldrh(reg, addr, cond);
      break;
    case kUnsignedFourBytes:
    case kFourBytes:
      ldr(reg, addr, cond);
      break;
    default:
      UNREACHABLE();
  }
}

void Assembler::LoadFromStack(Register dst, intptr_t depth) {
  ASSERT(depth >= 0);
  LoadFromOffset(dst, SPREG, depth * target::kWordSize);
}

void Assembler::StoreToStack(Register src, intptr_t depth) {
  ASSERT(depth >= 0);
  StoreToOffset(src, SPREG, depth * target::kWordSize);
}

void Assembler::CompareToStack(Register src, intptr_t depth) {
  LoadFromStack(TMP, depth);
  CompareRegisters(src, TMP);
}

void Assembler::Store(Register reg,
                      const Address& address,
                      OperandSize size,
                      Condition cond) {
  const Address& addr = PrepareLargeStoreOffset(address, size, cond);
  switch (size) {
    case kUnsignedByte:
    case kByte:
      strb(reg, addr, cond);
      break;
    case kUnsignedTwoBytes:
    case kTwoBytes:
      strh(reg, addr, cond);
      break;
    case kUnsignedFourBytes:
    case kFourBytes:
      str(reg, addr, cond);
      break;
    default:
      UNREACHABLE();
  }
}

void Assembler::LoadSFromOffset(SRegister reg,
                                Register base,
                                int32_t offset,
                                Condition cond) {
  vldrs(reg, PrepareLargeLoadOffset(Address(base, offset), kSWord, cond), cond);
}

void Assembler::StoreSToOffset(SRegister reg,
                               Register base,
                               int32_t offset,
                               Condition cond) {
  vstrs(reg, PrepareLargeStoreOffset(Address(base, offset), kSWord, cond),
        cond);
}

void Assembler::LoadDFromOffset(DRegister reg,
                                Register base,
                                int32_t offset,
                                Condition cond) {
  vldrd(reg, PrepareLargeLoadOffset(Address(base, offset), kDWord, cond), cond);
}

void Assembler::StoreDToOffset(DRegister reg,
                               Register base,
                               int32_t offset,
                               Condition cond) {
  vstrd(reg, PrepareLargeStoreOffset(Address(base, offset), kDWord, cond),
        cond);
}

void Assembler::LoadMultipleDFromOffset(DRegister first,
                                        intptr_t count,
                                        Register base,
                                        int32_t offset) {
  ASSERT(base != IP);
  AddImmediate(IP, base, offset);
  vldmd(IA, IP, first, count);
}

void Assembler::StoreMultipleDToOffset(DRegister first,
                                       intptr_t count,
                                       Register base,
                                       int32_t offset) {
  ASSERT(base != IP);
  AddImmediate(IP, base, offset);
  vstmd(IA, IP, first, count);
}

void Assembler::AddImmediate(Register rd,
                             Register rn,
                             int32_t value,
                             Condition cond) {
  if (value == 0) {
    if (rd != rn) {
      mov(rd, Operand(rn), cond);
    }
    return;
  }
  // We prefer to select the shorter code sequence rather than selecting add for
  // positive values and sub for negatives ones, which would slightly improve
  // the readability of generated code for some constants.
  Operand o;
  if (Operand::CanHold(value, &o)) {
    add(rd, rn, o, cond);
  } else if (Operand::CanHold(-value, &o)) {
    sub(rd, rn, o, cond);
  } else {
    ASSERT(rn != IP);
    if (Operand::CanHold(~value, &o)) {
      mvn_(IP, o, cond);
      add(rd, rn, Operand(IP), cond);
    } else if (Operand::CanHold(~(-value), &o)) {
      mvn_(IP, o, cond);
      sub(rd, rn, Operand(IP), cond);
    } else if (value > 0) {
      LoadDecodableImmediate(IP, value, cond);
      add(rd, rn, Operand(IP), cond);
    } else {
      LoadDecodableImmediate(IP, -value, cond);
      sub(rd, rn, Operand(IP), cond);
    }
  }
}

void Assembler::AddImmediateSetFlags(Register rd,
                                     Register rn,
                                     int32_t value,
                                     Condition cond) {
  Operand o;
  if (Operand::CanHold(value, &o)) {
    // Handles value == kMinInt32.
    adds(rd, rn, o, cond);
  } else if (Operand::CanHold(-value, &o)) {
    ASSERT(value != kMinInt32);  // Would cause erroneous overflow detection.
    subs(rd, rn, o, cond);
  } else {
    ASSERT(rn != IP);
    if (Operand::CanHold(~value, &o)) {
      mvn_(IP, o, cond);
      adds(rd, rn, Operand(IP), cond);
    } else if (Operand::CanHold(~(-value), &o)) {
      ASSERT(value != kMinInt32);  // Would cause erroneous overflow detection.
      mvn_(IP, o, cond);
      subs(rd, rn, Operand(IP), cond);
    } else {
      LoadDecodableImmediate(IP, value, cond);
      adds(rd, rn, Operand(IP), cond);
    }
  }
}

void Assembler::SubImmediate(Register rd,
                             Register rn,
                             int32_t value,
                             Condition cond) {
  AddImmediate(rd, rn, -value, cond);
}

void Assembler::SubImmediateSetFlags(Register rd,
                                     Register rn,
                                     int32_t value,
                                     Condition cond) {
  Operand o;
  if (Operand::CanHold(value, &o)) {
    // Handles value == kMinInt32.
    subs(rd, rn, o, cond);
  } else if (Operand::CanHold(-value, &o)) {
    ASSERT(value != kMinInt32);  // Would cause erroneous overflow detection.
    adds(rd, rn, o, cond);
  } else {
    ASSERT(rn != IP);
    if (Operand::CanHold(~value, &o)) {
      mvn_(IP, o, cond);
      subs(rd, rn, Operand(IP), cond);
    } else if (Operand::CanHold(~(-value), &o)) {
      ASSERT(value != kMinInt32);  // Would cause erroneous overflow detection.
      mvn_(IP, o, cond);
      adds(rd, rn, Operand(IP), cond);
    } else {
      LoadDecodableImmediate(IP, value, cond);
      subs(rd, rn, Operand(IP), cond);
    }
  }
}

void Assembler::AndImmediate(Register rd,
                             Register rs,
                             int32_t imm,
                             OperandSize sz,
                             Condition cond) {
  ASSERT(sz == kFourBytes || sz == kUnsignedFourBytes);
  Operand o;
  // Avoid generating a load + and_ pair for all bits set, since
  // Operand::CanHold returns false for that case. This also allows the
  // instruction to be a no-op if rd == rs.
  if (imm == -1) {
    MoveRegister(rd, rs);
  } else if (Operand::CanHold(imm, &o)) {
    and_(rd, rs, Operand(o), cond);
  } else {
    LoadImmediate(TMP, imm, cond);
    and_(rd, rs, Operand(TMP), cond);
  }
}

void Assembler::AndImmediateSetFlags(Register rd,
                                     Register rs,
                                     int32_t imm,
                                     Condition cond) {
  Operand o;
  if (Operand::CanHold(imm, &o)) {
    ands(rd, rs, Operand(o), cond);
  } else {
    LoadImmediate(TMP, imm, cond);
    ands(rd, rs, Operand(TMP), cond);
  }
}

void Assembler::OrImmediate(Register rd,
                            Register rs,
                            int32_t imm,
                            Condition cond) {
  Operand o;
  if (Operand::CanHold(imm, &o)) {
    orr(rd, rs, Operand(o), cond);
  } else {
    LoadImmediate(TMP, imm, cond);
    orr(rd, rs, Operand(TMP), cond);
  }
}

void Assembler::XorImmediate(Register rd,
                             Register rs,
                             int32_t imm,
                             Condition cond) {
  Operand o;
  if (Operand::CanHold(imm, &o)) {
    eor(rd, rs, Operand(o), cond);
  } else {
    LoadImmediate(TMP, imm, cond);
    eor(rd, rs, Operand(TMP), cond);
  }
}

void Assembler::CompareImmediate(Register rn, int32_t value, Condition cond) {
  Operand o;
  if (Operand::CanHold(value, &o)) {
    cmp(rn, o, cond);
  } else {
    ASSERT(rn != IP);
    LoadImmediate(IP, value, cond);
    cmp(rn, Operand(IP), cond);
  }
}

void Assembler::TestImmediate(Register rn, int32_t imm, Condition cond) {
  Operand o;
  if (Operand::CanHold(imm, &o)) {
    tst(rn, o, cond);
  } else {
    LoadImmediate(IP, imm);
    tst(rn, Operand(IP), cond);
  }
}

void Assembler::IntegerDivide(Register result,
                              Register left,
                              Register right,
                              DRegister tmpl,
                              DRegister tmpr) {
  ASSERT(tmpl != tmpr);
  if (TargetCPUFeatures::integer_division_supported()) {
    sdiv(result, left, right);
  } else {
    SRegister stmpl = EvenSRegisterOf(tmpl);
    SRegister stmpr = EvenSRegisterOf(tmpr);
    vmovsr(stmpl, left);
    vcvtdi(tmpl, stmpl);  // left is in tmpl.
    vmovsr(stmpr, right);
    vcvtdi(tmpr, stmpr);  // right is in tmpr.
    vdivd(tmpr, tmpl, tmpr);
    vcvtid(stmpr, tmpr);
    vmovrs(result, stmpr);
  }
}

static int NumRegsBelowFP(RegList regs) {
  int count = 0;
  for (int i = 0; i < FP; i++) {
    if ((regs & (1 << i)) != 0) {
      count++;
    }
  }
  return count;
}

void Assembler::ArithmeticShiftRightImmediate(Register dst,
                                              Register src,
                                              int32_t shift,
                                              OperandSize sz) {
  ASSERT(sz == kFourBytes);
  ASSERT((shift >= 0) && (shift < OperandSizeInBits(sz)));
  if (shift != 0) {
    Asr(dst, src, Operand(shift));
  } else {
    MoveRegister(dst, src);
  }
}

void Assembler::CompareWords(Register reg1,
                             Register reg2,
                             intptr_t offset,
                             Register count,
                             Register temp,
                             Label* equals) {
  Label loop;

  AddImmediate(reg1, offset - kHeapObjectTag);
  AddImmediate(reg2, offset - kHeapObjectTag);

  COMPILE_ASSERT(target::kWordSize == 4);
  Bind(&loop);
  BranchIfZero(count, equals, Assembler::kNearJump);
  AddImmediate(count, -1);
  ldr(temp, Address(reg1, 4, Address::PostIndex));
  ldr(TMP, Address(reg2, 4, Address::PostIndex));
  cmp(temp, Operand(TMP));
  BranchIf(EQUAL, &loop, Assembler::kNearJump);
}

void Assembler::EnterFrame(RegList regs, intptr_t frame_size) {
  if (prologue_offset_ == -1) {
    prologue_offset_ = CodeSize();
  }
  PushList(regs);
  if ((regs & (1 << FP)) != 0) {
    // Set FP to the saved previous FP.
    add(FP, SP, Operand(4 * NumRegsBelowFP(regs)));
  }
  if (frame_size != 0) {
    AddImmediate(SP, -frame_size);
  }
}

void Assembler::LeaveFrame(RegList regs, bool allow_pop_pc) {
  ASSERT(allow_pop_pc || (regs & (1 << PC)) == 0);  // Must not pop PC.
  if ((regs & (1 << FP)) != 0) {
    // Use FP to set SP.
    sub(SP, FP, Operand(4 * NumRegsBelowFP(regs)));
  }
  PopList(regs);
}

void Assembler::Ret(Condition cond /* = AL */) {
  READS_RETURN_ADDRESS_FROM_LR(bx(LR, cond));
}

void Assembler::SetReturnAddress(Register value) {
  RESTORES_RETURN_ADDRESS_FROM_REGISTER_TO_LR(MoveRegister(LR, value));
}

void Assembler::ReserveAlignedFrameSpace(intptr_t frame_space) {
  // Reserve space for arguments and align frame before entering
  // the C++ world.
  AddImmediate(SP, -frame_space);
  if (OS::ActivationFrameAlignment() > 1) {
    bic(SP, SP, Operand(OS::ActivationFrameAlignment() - 1));
  }
}

void Assembler::EmitEntryFrameVerification(Register scratch) {
#if defined(DEBUG)
  Label done;
  ASSERT(!constant_pool_allowed());
  LoadImmediate(scratch, target::frame_layout.exit_link_slot_from_entry_fp *
                             target::kWordSize);
  add(scratch, scratch, Operand(FPREG));
  cmp(scratch, Operand(SPREG));
  b(&done, EQ);

  Breakpoint();

  Bind(&done);
#endif
}

void Assembler::CallRuntime(const RuntimeEntry& entry,
                            intptr_t argument_count) {
  ASSERT(!entry.is_leaf());
  // Argument count is not checked here, but in the runtime entry for a more
  // informative error message.
  LoadFromOffset(R9, THR, entry.OffsetFromThread());
  LoadImmediate(R4, argument_count);
  ldr(IP, Address(THR, target::Thread::call_to_runtime_entry_point_offset()));
  blx(IP);
}

// For use by LR related macros (e.g. CLOBBERS_LR).
#undef __
#define __ assembler_->

#if defined(VFPv3_D32)
static const RegisterSet kVolatileFpuRegisters(0, 0xFF0F);  // Q0-Q3, Q8-Q15
#else
static const RegisterSet kVolatileFpuRegisters(0, 0x000F);  // Q0-Q3
#endif

LeafRuntimeScope::LeafRuntimeScope(Assembler* assembler,
                                   intptr_t frame_size,
                                   bool preserve_registers)
    : assembler_(assembler), preserve_registers_(preserve_registers) {
  __ Comment("EnterCallRuntimeFrame");
  if (preserve_registers) {
    // Preserve volatile CPU registers and PP.
    SPILLS_LR_TO_FRAME(__ EnterFrame(
        kDartVolatileCpuRegs | (1 << PP) | (1 << FP) | (1 << LR), 0));
    COMPILE_ASSERT((kDartVolatileCpuRegs & (1 << PP)) == 0);

    __ PushRegisters(kVolatileFpuRegisters);
  } else {
    SPILLS_LR_TO_FRAME(__ EnterFrame((1 << FP) | (1 << LR), 0));
    // These registers must always be preserved.
    COMPILE_ASSERT(IsCalleeSavedRegister(THR));
    COMPILE_ASSERT(IsCalleeSavedRegister(PP));
    COMPILE_ASSERT(IsCalleeSavedRegister(CODE_REG));
  }

  __ ReserveAlignedFrameSpace(frame_size);
}

void LeafRuntimeScope::Call(const RuntimeEntry& entry,
                            intptr_t argument_count) {
  ASSERT(argument_count == entry.argument_count());
  __ LoadFromOffset(TMP, THR, entry.OffsetFromThread());
  __ str(TMP,
         compiler::Address(THR, compiler::target::Thread::vm_tag_offset()));
  __ blx(TMP);
  __ LoadImmediate(TMP, VMTag::kDartTagId);
  __ str(TMP,
         compiler::Address(THR, compiler::target::Thread::vm_tag_offset()));
}

LeafRuntimeScope::~LeafRuntimeScope() {
  if (preserve_registers_) {
    // SP might have been modified to reserve space for arguments
    // and ensure proper alignment of the stack frame.
    // We need to restore it before restoring registers.
    const intptr_t kPushedFpuRegisterSize =
        kVolatileFpuRegisters.FpuRegisterCount() * kFpuRegisterSize;

    COMPILE_ASSERT(PP < FP);
    COMPILE_ASSERT((kDartVolatileCpuRegs & (1 << PP)) == 0);
    // kVolatileCpuRegCount +1 for PP, -1 because even though LR is volatile,
    // it is pushed ahead of FP.
    const intptr_t kPushedRegistersSize =
        kDartVolatileCpuRegCount * target::kWordSize + kPushedFpuRegisterSize;
    __ AddImmediate(SP, FP, -kPushedRegistersSize);

    __ PopRegisters(kVolatileFpuRegisters);

    // Restore volatile CPU registers.
    RESTORES_LR_FROM_FRAME(__ LeaveFrame(kDartVolatileCpuRegs | (1 << PP) |
                                         (1 << FP) | (1 << LR)));
  } else {
    RESTORES_LR_FROM_FRAME(__ LeaveFrame((1 << FP) | (1 << LR)));
  }
}

// For use by LR related macros (e.g. CLOBBERS_LR).
#undef __
#define __ this->

void Assembler::EnterDartFrame(intptr_t frame_size, bool load_pool_pointer) {
  ASSERT(!constant_pool_allowed());

  // Registers are pushed in descending order: R5 | R6 | R7/R11 | R14.
  COMPILE_ASSERT(PP < CODE_REG);
  COMPILE_ASSERT(CODE_REG < FP);
  COMPILE_ASSERT(FP < LINK_REGISTER.code);

  if (!FLAG_precompiled_mode) {
    SPILLS_LR_TO_FRAME(
        EnterFrame((1 << PP) | (1 << CODE_REG) | (1 << FP) | (1 << LR), 0));

    // Setup pool pointer for this dart function.
    if (load_pool_pointer) LoadPoolPointer();
  } else {
    SPILLS_LR_TO_FRAME(EnterFrame((1 << FP) | (1 << LR), 0));
  }
  set_constant_pool_allowed(true);

  // Reserve space for locals.
  AddImmediate(SP, -frame_size);
}

// On entry to a function compiled for OSR, the caller's frame pointer, the
// stack locals, and any copied parameters are already in place.  The frame
// pointer is already set up.  The PC marker is not correct for the
// optimized function and there may be extra space for spill slots to
// allocate. We must also set up the pool pointer for the function.
void Assembler::EnterOsrFrame(intptr_t extra_size) {
  ASSERT(!constant_pool_allowed());
  Comment("EnterOsrFrame");
  RestoreCodePointer();
  LoadPoolPointer();

  AddImmediate(SP, -extra_size);
}

void Assembler::LeaveDartFrame() {
  if (!FLAG_precompiled_mode) {
    ldr(PP, Address(FP, target::frame_layout.saved_caller_pp_from_fp *
                            target::kWordSize));
  }
  set_constant_pool_allowed(false);

  // This will implicitly drop saved PP, PC marker due to restoring SP from FP
  // first.
  RESTORES_LR_FROM_FRAME(LeaveFrame((1 << FP) | (1 << LR)));
}

void Assembler::LeaveDartFrameAndReturn() {
  if (!FLAG_precompiled_mode) {
    ldr(PP, Address(FP, target::frame_layout.saved_caller_pp_from_fp *
                            target::kWordSize));
  }
  set_constant_pool_allowed(false);

  // This will implicitly drop saved PP, PC marker due to restoring SP from FP
  // first.
  LeaveFrame((1 << FP) | (1 << PC), /*allow_pop_pc=*/true);
}

void Assembler::EnterStubFrame() {
  EnterDartFrame(0);
}

void Assembler::LeaveStubFrame() {
  LeaveDartFrame();
}

void Assembler::EnterCFrame(intptr_t frame_space) {
  // Already saved.
  COMPILE_ASSERT(IsCalleeSavedRegister(THR));
  COMPILE_ASSERT(IsCalleeSavedRegister(PP));

  EnterFrame(1 << FP, 0);
  ReserveAlignedFrameSpace(frame_space);
}

void Assembler::LeaveCFrame() {
  LeaveFrame(1 << FP);
}

// R0 receiver, R9 ICData entries array
// Preserve R4 (ARGS_DESC_REG), not required today, but maybe later.
void Assembler::MonomorphicCheckedEntryJIT() {
  has_monomorphic_entry_ = true;
#if defined(TESTING) || defined(DEBUG)
  bool saved_use_far_branches = use_far_branches();
  set_use_far_branches(false);
#endif
  intptr_t start = CodeSize();

  Comment("MonomorphicCheckedEntry");
  ASSERT_EQUAL(CodeSize() - start,
               target::Instructions::kMonomorphicEntryOffsetJIT);

  const intptr_t cid_offset = target::Array::element_offset(0);
  const intptr_t count_offset = target::Array::element_offset(1);

  // Sadly this cannot use ldm because ldm takes no offset.
  ldr(R1, FieldAddress(R9, cid_offset));
  ldr(R2, FieldAddress(R9, count_offset));
  LoadClassIdMayBeSmi(IP, R0);
  add(R2, R2, Operand(target::ToRawSmi(1)));
  cmp(R1, Operand(IP, LSL, 1));
  Branch(Address(THR, target::Thread::switchable_call_miss_entry_offset()), NE);
  str(R2, FieldAddress(R9, count_offset));
  LoadImmediate(R4, 0);  // GC-safe for OptimizeInvokedFunction.

  // Fall through to unchecked entry.
  ASSERT_EQUAL(CodeSize() - start,
               target::Instructions::kPolymorphicEntryOffsetJIT);

#if defined(TESTING) || defined(DEBUG)
  set_use_far_branches(saved_use_far_branches);
#endif
}

// R0 receiver, R9 guarded cid as Smi.
// Preserve R4 (ARGS_DESC_REG), not required today, but maybe later.
void Assembler::MonomorphicCheckedEntryAOT() {
  has_monomorphic_entry_ = true;
#if defined(TESTING) || defined(DEBUG)
  bool saved_use_far_branches = use_far_branches();
  set_use_far_branches(false);
#endif
  intptr_t start = CodeSize();

  Comment("MonomorphicCheckedEntry");
  ASSERT_EQUAL(CodeSize() - start,
               target::Instructions::kMonomorphicEntryOffsetAOT);

  LoadClassId(IP, R0);
  cmp(R9, Operand(IP, LSL, 1));
  Branch(Address(THR, target::Thread::switchable_call_miss_entry_offset()), NE);

  // Fall through to unchecked entry.
  ASSERT_EQUAL(CodeSize() - start,
               target::Instructions::kPolymorphicEntryOffsetAOT);

#if defined(TESTING) || defined(DEBUG)
  set_use_far_branches(saved_use_far_branches);
#endif
}

void Assembler::BranchOnMonomorphicCheckedEntryJIT(Label* label) {
  has_monomorphic_entry_ = true;
  while (CodeSize() < target::Instructions::kMonomorphicEntryOffsetJIT) {
    bkpt(0);
  }
  b(label);
  while (CodeSize() < target::Instructions::kPolymorphicEntryOffsetJIT) {
    bkpt(0);
  }
}

void Assembler::CombineHashes(Register hash, Register other) {
  // hash += other_hash
  add(hash, hash, Operand(other));
  // hash += hash << 10
  add(hash, hash, Operand(hash, LSL, 10));
  // hash ^= hash >> 6
  eor(hash, hash, Operand(hash, LSR, 6));
}

void Assembler::FinalizeHashForSize(intptr_t bit_size,
                                    Register hash,
                                    Register scratch) {
  ASSERT(bit_size > 0);  // Can't avoid returning 0 if there are no hash bits!
  // While any 32-bit hash value fits in X bits, where X > 32, the caller may
  // reasonably expect that the returned values fill the entire bit space.
  ASSERT(bit_size <= kBitsPerInt32);
  // hash += hash << 3;
  add(hash, hash, Operand(hash, LSL, 3));
  // hash ^= hash >> 11;  // Logical shift, unsigned hash.
  eor(hash, hash, Operand(hash, LSR, 11));
  // hash += hash << 15;
  adds(hash, hash, Operand(hash, LSL, 15));
  if (bit_size < kBitsPerInt32) {
    // Size to fit.
    AndImmediateSetFlags(hash, hash, Utils::NBitMask(bit_size), NOT_ZERO);
  }
  // return (hash == 0) ? 1 : hash;
  LoadImmediate(hash, 1, ZERO);
}

#ifndef PRODUCT
void Assembler::MaybeTraceAllocation(Register stats_addr_reg, Label* trace) {
  ASSERT(stats_addr_reg != kNoRegister);
  ASSERT(stats_addr_reg != TMP);
  ldrb(TMP, Address(stats_addr_reg, 0));
  cmp(TMP, Operand(0));
  b(trace, NE);
}

void Assembler::MaybeTraceAllocation(intptr_t cid,
                                     Label* trace,
                                     Register temp_reg,
                                     JumpDistance distance) {
  LoadAllocationTracingStateAddress(temp_reg, cid);
  MaybeTraceAllocation(temp_reg, trace);
}

void Assembler::MaybeTraceAllocation(Register cid,
                                     Label* trace,
                                     Register temp_reg,
                                     JumpDistance distance) {
  LoadAllocationTracingStateAddress(temp_reg, cid);
  MaybeTraceAllocation(temp_reg, trace);
}

void Assembler::LoadAllocationTracingStateAddress(Register dest, Register cid) {
  ASSERT(dest != kNoRegister);
  ASSERT(dest != TMP);

  LoadIsolateGroup(dest);
  ldr(dest, Address(dest, target::IsolateGroup::class_table_offset()));
  ldr(dest,
      Address(dest,
              target::ClassTable::allocation_tracing_state_table_offset()));
  AddScaled(dest, dest, cid, TIMES_1,
            target::ClassTable::AllocationTracingStateSlotOffsetFor(0));
}

void Assembler::LoadAllocationTracingStateAddress(Register dest, intptr_t cid) {
  ASSERT(dest != kNoRegister);
  ASSERT(dest != TMP);
  ASSERT(cid > 0);

  LoadIsolateGroup(dest);
  ldr(dest, Address(dest, target::IsolateGroup::class_table_offset()));
  ldr(dest,
      Address(dest,
              target::ClassTable::allocation_tracing_state_table_offset()));
  AddImmediate(dest,
               target::ClassTable::AllocationTracingStateSlotOffsetFor(cid));
}
#endif  // !PRODUCT

void Assembler::TryAllocateObject(intptr_t cid,
                                  intptr_t instance_size,
                                  Label* failure,
                                  JumpDistance distance,
                                  Register instance_reg,
                                  Register temp_reg) {
  ASSERT(failure != nullptr);
  ASSERT(instance_reg != kNoRegister);
  ASSERT(instance_reg != temp_reg);
  ASSERT(instance_reg != IP);
  ASSERT(temp_reg != kNoRegister);
  ASSERT(temp_reg != IP);
  ASSERT(instance_size != 0);
  ASSERT(Utils::IsAligned(instance_size,
                          target::ObjectAlignment::kObjectAlignment));
  if (FLAG_inline_alloc &&
      target::Heap::IsAllocatableInNewSpace(instance_size)) {
    ldr(instance_reg, Address(THR, target::Thread::top_offset()));
    // TODO(koda): Protect against unsigned overflow here.
    AddImmediate(instance_reg, instance_size);
    // instance_reg: potential top (next object start).
    ldr(IP, Address(THR, target::Thread::end_offset()));
    cmp(IP, Operand(instance_reg));
    // fail if heap end unsigned less than or equal to new heap top.
    b(failure, LS);
    CheckAllocationCanary(instance_reg, temp_reg);

    // If this allocation is traced, program will jump to failure path
    // (i.e. the allocation stub) which will allocate the object and trace the
    // allocation call site.
    NOT_IN_PRODUCT(LoadAllocationTracingStateAddress(temp_reg, cid));
    NOT_IN_PRODUCT(MaybeTraceAllocation(temp_reg, failure));

    // Successfully allocated the object, now update top to point to
    // next object start and store the class in the class field of object.
    str(instance_reg, Address(THR, target::Thread::top_offset()));
    // Move instance_reg back to the start of the object and tag it.
    AddImmediate(instance_reg, -instance_size + kHeapObjectTag);

    const uword tags = target::MakeTagWordForNewSpaceObject(cid, instance_size);
    LoadImmediate(temp_reg, tags);
    InitializeHeader(temp_reg, instance_reg);
  } else {
    b(failure);
  }
}

void Assembler::TryAllocateArray(intptr_t cid,
                                 intptr_t instance_size,
                                 Label* failure,
                                 Register instance,
                                 Register end_address,
                                 Register temp1,
                                 Register temp2) {
  if (FLAG_inline_alloc &&
      target::Heap::IsAllocatableInNewSpace(instance_size)) {
    NOT_IN_PRODUCT(LoadAllocationTracingStateAddress(temp1, cid));
    // Potential new object start.
    ldr(instance, Address(THR, target::Thread::top_offset()));
    AddImmediateSetFlags(end_address, instance, instance_size);
    b(failure, CS);  // Branch if unsigned overflow.

    // Check if the allocation fits into the remaining space.
    // instance: potential new object start.
    // end_address: potential next object start.
    ldr(temp2, Address(THR, target::Thread::end_offset()));
    cmp(end_address, Operand(temp2));
    b(failure, CS);
    CheckAllocationCanary(instance, temp2);

    // If this allocation is traced, program will jump to failure path
    // (i.e. the allocation stub) which will allocate the object and trace the
    // allocation call site.
    NOT_IN_PRODUCT(MaybeTraceAllocation(temp1, failure));

    // Successfully allocated the object(s), now update top to point to
    // next object start and initialize the object.
    str(end_address, Address(THR, target::Thread::top_offset()));
    add(instance, instance, Operand(kHeapObjectTag));

    // Initialize the tags.
    // instance: new object start as a tagged pointer.
    const uword tags = target::MakeTagWordForNewSpaceObject(cid, instance_size);
    LoadImmediate(temp2, tags);
    InitializeHeader(temp2, instance);
  } else {
    b(failure);
  }
}

void Assembler::CopyMemoryWords(Register src,
                                Register dst,
                                Register size,
                                Register temp) {
  Label loop, done;
  __ cmp(size, Operand(0));
  __ b(&done, EQUAL);
  __ Bind(&loop);
  __ ldr(temp, Address(src, target::kWordSize, Address::PostIndex));
  __ str(temp, Address(dst, target::kWordSize, Address::PostIndex));
  __ subs(size, size, Operand(target::kWordSize));
  __ b(&loop, NOT_ZERO);
  __ Bind(&done);
}

void Assembler::GenerateUnRelocatedPcRelativeCall(Condition cond,
                                                  intptr_t offset_into_target) {
  // Emit "blr.cond <offset>".
  EmitType5(cond, 0x686868, /*link=*/true);

  PcRelativeCallPattern pattern(buffer_.contents() + buffer_.Size() -
                                PcRelativeCallPattern::kLengthInBytes);
  pattern.set_distance(offset_into_target);
}

void Assembler::GenerateUnRelocatedPcRelativeTailCall(
    Condition cond,
    intptr_t offset_into_target) {
  // Emit "b <offset>".
  EmitType5(cond, 0x686868, /*link=*/false);

  PcRelativeTailCallPattern pattern(buffer_.contents() + buffer_.Size() -
                                    PcRelativeTailCallPattern::kLengthInBytes);
  pattern.set_distance(offset_into_target);
}

bool Assembler::AddressCanHoldConstantIndex(const Object& constant,
                                            bool is_load,
                                            bool is_external,
                                            intptr_t cid,
                                            intptr_t index_scale,
                                            bool* needs_base) {
  ASSERT(needs_base != nullptr);
  auto const rep = RepresentationUtils::RepresentationOfArrayElement(cid);
  if ((rep == kUnboxedInt32x4) || (rep == kUnboxedFloat32x4) ||
      (rep == kUnboxedFloat64x2)) {
    // We are using vldmd/vstmd which do not support offset.
    return false;
  }

  if (!IsSafeSmi(constant)) return false;
  const int64_t index = target::SmiValue(constant);
  const intptr_t offset_base =
      (is_external ? 0
                   : (target::Instance::DataOffsetFor(cid) - kHeapObjectTag));
  const int64_t offset = index * index_scale + offset_base;
  if (!Utils::IsInt(32, offset)) return false;
  if (Address::CanHoldImmediateOffset(is_load, cid, offset)) {
    *needs_base = false;
    return true;
  }
  if (Address::CanHoldImmediateOffset(is_load, cid, offset - offset_base)) {
    *needs_base = true;
    return true;
  }

  return false;
}

Address Assembler::ElementAddressForIntIndex(bool is_load,
                                             bool is_external,
                                             intptr_t cid,
                                             intptr_t index_scale,
                                             Register array,
                                             intptr_t index,
                                             Register temp) {
  const int64_t offset_base =
      (is_external ? 0
                   : (target::Instance::DataOffsetFor(cid) - kHeapObjectTag));
  const int64_t offset =
      offset_base + static_cast<int64_t>(index) * index_scale;
  ASSERT(Utils::IsInt(32, offset));

  if (Address::CanHoldImmediateOffset(is_load, cid, offset)) {
    return Address(array, static_cast<int32_t>(offset));
  } else {
    ASSERT(Address::CanHoldImmediateOffset(is_load, cid, offset - offset_base));
    AddImmediate(temp, array, static_cast<int32_t>(offset_base));
    return Address(temp, static_cast<int32_t>(offset - offset_base));
  }
}

void Assembler::LoadElementAddressForIntIndex(Register address,
                                              bool is_load,
                                              bool is_external,
                                              intptr_t cid,
                                              intptr_t index_scale,
                                              Register array,
                                              intptr_t index) {
  const int64_t offset_base =
      (is_external ? 0
                   : (target::Instance::DataOffsetFor(cid) - kHeapObjectTag));
  const int64_t offset =
      offset_base + static_cast<int64_t>(index) * index_scale;
  ASSERT(Utils::IsInt(32, offset));
  AddImmediate(address, array, offset);
}

Address Assembler::ElementAddressForRegIndex(bool is_load,
                                             bool is_external,
                                             intptr_t cid,
                                             intptr_t index_scale,
                                             bool index_unboxed,
                                             Register array,
                                             Register index) {
  // If unboxed, index is expected smi-tagged, (i.e, LSL 1) for all arrays.
  const intptr_t boxing_shift = index_unboxed ? 0 : -kSmiTagShift;
  const intptr_t shift = Utils::ShiftForPowerOfTwo(index_scale) + boxing_shift;
  int32_t offset =
      is_external ? 0 : (target::Instance::DataOffsetFor(cid) - kHeapObjectTag);
  const OperandSize size = Address::OperandSizeFor(cid);
  ASSERT(array != IP);
  ASSERT(index != IP);
  const Register base = is_load ? IP : index;
  if ((offset != 0) || (is_load && (size == kByte || size == kUnsignedByte)) ||
      (size == kTwoBytes) || (size == kUnsignedTwoBytes) || (size == kSWord) ||
      (size == kDWord) || (size == kRegList)) {
    if (shift < 0) {
      ASSERT(shift == -1);
      add(base, array, Operand(index, ASR, 1));
    } else {
      add(base, array, Operand(index, LSL, shift));
    }
  } else {
    if (shift < 0) {
      ASSERT(shift == -1);
      return Address(array, index, ASR, 1);
    } else {
      return Address(array, index, LSL, shift);
    }
  }
  int32_t offset_mask = 0;
  if ((is_load && !Address::CanHoldLoadOffset(size, offset, &offset_mask)) ||
      (!is_load && !Address::CanHoldStoreOffset(size, offset, &offset_mask))) {
    AddImmediate(base, offset & ~offset_mask);
    offset = offset & offset_mask;
  }
  return Address(base, offset);
}

void Assembler::LoadElementAddressForRegIndex(Register address,
                                              bool is_load,
                                              bool is_external,
                                              intptr_t cid,
                                              intptr_t index_scale,
                                              bool index_unboxed,
                                              Register array,
                                              Register index) {
  // If unboxed, index is expected smi-tagged, (i.e, LSL 1) for all arrays.
  const intptr_t boxing_shift = index_unboxed ? 0 : -kSmiTagShift;
  const intptr_t shift = Utils::ShiftForPowerOfTwo(index_scale) + boxing_shift;
  int32_t offset =
      is_external ? 0 : (target::Instance::DataOffsetFor(cid) - kHeapObjectTag);
  if (shift < 0) {
    ASSERT(shift == -1);
    add(address, array, Operand(index, ASR, 1));
  } else {
    add(address, array, Operand(index, LSL, shift));
  }
  if (offset != 0) {
    AddImmediate(address, offset);
  }
}

void Assembler::LoadStaticFieldAddress(Register address,
                                       Register field,
                                       Register scratch,
                                       bool is_shared) {
  LoadFieldFromOffset(scratch, field,
                      target::Field::host_offset_or_field_id_offset());
  const intptr_t field_table_offset =
      is_shared ? compiler::target::Thread::shared_field_table_values_offset()
                : compiler::target::Thread::field_table_values_offset();
  LoadMemoryValue(address, THR, static_cast<int32_t>(field_table_offset));
  add(address, address,
      Operand(scratch, LSL, target::kWordSizeLog2 - kSmiTagShift));
}

void Assembler::LoadFieldAddressForRegOffset(Register address,
                                             Register instance,
                                             Register offset_in_words_as_smi) {
  add(address, instance,
      Operand(offset_in_words_as_smi, LSL,
              target::kWordSizeLog2 - kSmiTagShift));
  AddImmediate(address, -kHeapObjectTag);
}

void Assembler::LoadHalfWordUnaligned(Register dst,
                                      Register addr,
                                      Register tmp) {
  ASSERT(dst != addr);
  ldrb(dst, Address(addr, 0));
  ldrsb(tmp, Address(addr, 1));
  orr(dst, dst, Operand(tmp, LSL, 8));
}

void Assembler::LoadHalfWordUnsignedUnaligned(Register dst,
                                              Register addr,
                                              Register tmp) {
  ASSERT(dst != addr);
  ldrb(dst, Address(addr, 0));
  ldrb(tmp, Address(addr, 1));
  orr(dst, dst, Operand(tmp, LSL, 8));
}

void Assembler::StoreHalfWordUnaligned(Register src,
                                       Register addr,
                                       Register tmp) {
  strb(src, Address(addr, 0));
  Lsr(tmp, src, Operand(8));
  strb(tmp, Address(addr, 1));
}

void Assembler::LoadWordUnaligned(Register dst, Register addr, Register tmp) {
  ASSERT(dst != addr);
  ldrb(dst, Address(addr, 0));
  ldrb(tmp, Address(addr, 1));
  orr(dst, dst, Operand(tmp, LSL, 8));
  ldrb(tmp, Address(addr, 2));
  orr(dst, dst, Operand(tmp, LSL, 16));
  ldrb(tmp, Address(addr, 3));
  orr(dst, dst, Operand(tmp, LSL, 24));
}

void Assembler::StoreWordUnaligned(Register src, Register addr, Register tmp) {
  strb(src, Address(addr, 0));
  Lsr(tmp, src, Operand(8));
  strb(tmp, Address(addr, 1));
  Lsr(tmp, src, Operand(16));
  strb(tmp, Address(addr, 2));
  Lsr(tmp, src, Operand(24));
  strb(tmp, Address(addr, 3));
}

void Assembler::RangeCheck(Register value,
                           Register temp,
                           intptr_t low,
                           intptr_t high,
                           RangeCheckCondition condition,
                           Label* target) {
  auto cc = condition == kIfInRange ? LS : HI;
  Register to_check = temp != kNoRegister ? temp : value;
  AddImmediate(to_check, value, -low);
  CompareImmediate(to_check, high - low);
  b(target, cc);
}

}  // namespace compiler
}  // namespace dart

#endif  // defined(TARGET_ARCH_ARM)
