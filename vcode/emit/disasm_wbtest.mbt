///|
/// Direct test of all emit functions - no compilation, just raw instruction emission
test "all emit functions disasm" {
  let mc = MachineCode::new()

  // Integer arithmetic
  mc.emit_add_reg(0, 1, 2)
  mc.emit_add_imm(3, 4, 100)
  mc.emit_sub_reg(5, 6, 7)
  mc.emit_sub_imm(8, 9, 200)
  mc.emit_mul(10, 11, 12)
  mc.emit_sdiv(13, 14, 15)
  mc.emit_udiv(16, 17, 18)

  // Logical operations
  mc.emit_and_reg(19, 20, 21)
  mc.emit_orr_reg(22, 23, 24)
  mc.emit_eor_reg(25, 26, 27)

  // Shifts
  mc.emit_lsl_reg(0, 1, 2)
  mc.emit_lsr_reg(3, 4, 5)
  mc.emit_asr_reg(6, 7, 8)

  // Shifted operand variants
  mc.emit_add_shifted(0, 1, 2, Lsl, 3)
  mc.emit_sub_shifted(3, 4, 5, Lsr, 4)
  mc.emit_and_shifted(6, 7, 8, Asr, 5)
  mc.emit_orr_shifted(9, 10, 11, Lsl, 6)
  mc.emit_eor_shifted(12, 13, 14, Lsr, 7)

  // Multiply-accumulate
  mc.emit_madd(0, 1, 2, 3)
  mc.emit_msub(4, 5, 6, 7)
  mc.emit_mneg(8, 9, 10)

  // Move instructions
  mc.emit_mov_reg(0, 1)
  mc.emit_mov_reg32(2, 3)
  mc.emit_movz(4, 0x1234, 0)
  mc.emit_movz(5, 0xABCD, 16)
  mc.emit_movk(6, 0x5678, 32)

  // Load immediate
  mc.emit_load_imm64(7, 0x123456789ABCDEF0L)

  // Integer loads
  mc.emit_ldr_imm(0, 1, 0)
  mc.emit_ldr_imm(2, 3, 64)
  mc.emit_ldrb_imm(4, 5, 10)
  mc.emit_ldrh_imm(6, 7, 20)
  mc.emit_ldr_w_imm(8, 9, 40)

  // Sign-extending loads
  mc.emit_ldrsb_x_imm(10, 11, 5)
  mc.emit_ldrsb_w_imm(12, 13, 6)
  mc.emit_ldrsh_x_imm(14, 15, 8)
  mc.emit_ldrsh_w_imm(16, 17, 10)
  mc.emit_ldrsw_imm(18, 19, 16)

  // Sign/Zero Extension Instructions
  mc.emit_sxtb_x(0, 1) // Sign extend byte to 64-bit
  mc.emit_sxth_x(2, 3) // Sign extend halfword to 64-bit
  mc.emit_sxtw(4, 5) // Sign extend word to 64-bit
  mc.emit_sxtb_w(6, 7) // Sign extend byte to 32-bit
  mc.emit_sxth_w(8, 9) // Sign extend halfword to 32-bit
  mc.emit_uxtb_x(10, 11) // Zero extend byte to 64-bit
  mc.emit_uxth_x(12, 13) // Zero extend halfword to 64-bit
  mc.emit_uxtb_w(14, 15) // Zero extend byte to 32-bit
  mc.emit_uxth_w(16, 17) // Zero extend halfword to 32-bit

  // Integer stores
  mc.emit_str_imm(0, 1, 0)
  mc.emit_str_imm(2, 3, 64)
  mc.emit_strb_imm(4, 5, 10)
  mc.emit_strh_imm(6, 7, 20)
  mc.emit_str_w_imm(8, 9, 40)

  // Stack pair operations
  mc.emit_stp_pre(29, 30, 31, -16)
  mc.emit_ldp_post(29, 30, 31, 16)
  mc.emit_stp_pre(19, 20, 31, 0)
  mc.emit_ldp_post(21, 22, 31, 16)

  // Floating-point arithmetic
  mc.emit_fadd_d(0, 1, 2)
  mc.emit_fsub_d(3, 4, 5)
  mc.emit_fmul_d(6, 7, 8)
  mc.emit_fdiv_d(9, 10, 11)

  // Floating-point moves
  mc.emit_fmov_d(0, 1)
  mc.emit_fmov_x_to_d(2, 3)
  mc.emit_fmov_d_to_x(4, 5)
  mc.emit_fmov_w_to_s(6, 7)
  mc.emit_fmov_s_to_w(8, 9)
  mc.emit_fcvt_d_s(10, 11)

  // Floating-point loads/stores
  mc.emit_ldr_s_imm(0, 1, 0)
  mc.emit_ldr_d_imm(2, 3, 8)
  mc.emit_str_s_imm(4, 5, 16)
  mc.emit_str_d_imm(6, 7, 24)

  // Comparison
  mc.emit_cmp_reg(0, 1)
  mc.emit_cmp_imm(2, 42)
  mc.emit_fcmp_d(3, 4)
  mc.emit_cset(5, CondCode::EQ.to_int())
  mc.emit_cset(6, CondCode::NE.to_int())
  mc.emit_cset(7, CondCode::LT.to_int())
  mc.emit_cset(8, CondCode::GE.to_int())

  // Branches
  mc.define_label(0)
  mc.emit_b(1)
  mc.emit_b_cond(CondCode::EQ.to_int(), 2)
  mc.emit_b_cond(CondCode::NE.to_int(), 3)
  mc.emit_b_cond(CondCode::LT.to_int(), 4)
  mc.emit_cbz(0, 5)
  mc.emit_cbnz(1, 6)
  mc.define_label(1)
  mc.define_label(2)
  mc.define_label(3)
  mc.define_label(4)
  mc.define_label(5)
  mc.define_label(6)

  // Call and return
  mc.emit_bl(0)
  mc.emit_blr(16)
  mc.emit_br(17) // Branch register (indirect jump)
  mc.emit_ret(30)

  // ADR (PC-relative address)
  mc.emit_adr(18, 8) // ADR x18, .+8

  // NOP
  mc.emit_nop()
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: 2000028b  add x0, x1, x2
      #|  0004: 83900191  add x3, x4, #100
      #|  0008: c50007cb  sub x5, x6, x7
      #|  000c: 282103d1  sub x8, x9, #200
      #|  0010: 6a7d0c9b  mul x10, x11, x12
      #|  0014: cd0dcf9a  sdiv x13, x14, x15
      #|  0018: 300ad29a  udiv x16, x17, x18
      #|  001c: 9302158a  and x19, x20, x21
      #|  0020: f60218aa  orr x22, x23, x24
      #|  0024: 59031bca  eor x25, x26, x27
      #|  0028: 2020c29a  lsl x0, x1, x2
      #|  002c: 8324c59a  lsr x3, x4, x5
      #|  0030: e628c89a  asr x6, x7, x8
      #|  0034: 200c028b  add x0, x1, x2, lsl #3
      #|  0038: 831045cb  sub x3, x4, x5, lsr #4
      #|  003c: e614888a  and x6, x7, x8, asr #5
      #|  0040: 49190baa  orr x9, x10, x11, lsl #6
      #|  0044: ac1d4eca  eor x12, x13, x14, lsr #7
      #|  0048: 200c029b  madd x0, x1, x2, x3
      #|  004c: a49c069b  msub x4, x5, x6, x7
      #|  0050: 28fd0a9b  mneg x8, x9, x10
      #|  0054: e00301aa  mov x0, x1
      #|  0058: e203032a  mov w2, w3
      #|  005c: 844682d2  movz x4, #4660, lsl #0
      #|  0060: a579b5d2  movz x5, #43981, lsl #16
      #|  0064: 06cfcaf2  movk x6, #22136, lsl #32
      #|  0068: 07de9bd2  movz x7, #57072, lsl #0
      #|  006c: 8757b3f2  movk x7, #39612, lsl #16
      #|  0070: 07cfcaf2  movk x7, #22136, lsl #32
      #|  0074: 8746e2f2  movk x7, #4660, lsl #48
      #|  0078: 200040f9  ldr x0, [x1, #0]
      #|  007c: 622040f9  ldr x2, [x3, #64]
      #|  0080: a4284039  ldrb w4, [x5, #10]
      #|  0084: e6284079  ldrh w6, [x7, #20]
      #|  0088: 282940b9  ldr w8, [x9, #40]
      #|  008c: 6a158039  ldrsb x10, [x11, #5]
      #|  0090: ac19c039  ldrsb w12, [x13, #6]
      #|  0094: ee118079  ldrsh x14, [x15, #8]
      #|  0098: 3016c079  ldrsh w16, [x17, #10]
      #|  009c: 721280b9  ldrsw x18, [x19, #16]
      #|  00a0: 201c4093  sxtb x0, w1
      #|  00a4: 623c4093  sxth x2, w3
      #|  00a8: a47c4093  sxtw x4, w5
      #|  00ac: e61c0013  sxtb w6, w7
      #|  00b0: 283d0013  sxth w8, w9
      #|  00b4: 6a1d0053  uxtb x10, w11
      #|  00b8: ac3d0053  uxth x12, w13
      #|  00bc: ee1d0053  uxtb w14, w15
      #|  00c0: 303e0053  uxth w16, w17
      #|  00c4: 200000f9  str x0, [x1, #0]
      #|  00c8: 622000f9  str x2, [x3, #64]
      #|  00cc: a4280039  strb w4, [x5, #10]
      #|  00d0: e6280079  strh w6, [x7, #20]
      #|  00d4: 282900b9  str w8, [x9, #40]
      #|  00d8: fd7bbfa9  stp x29, x30, [sp, #-16]!
      #|  00dc: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  00e0: f35380a9  stp x19, x20, [sp, #0]!
      #|  00e4: f55bc1a8  ldp x21, x22, [sp], #16
      #|  00e8: 2028621e  fadd d0, d1, d2
      #|  00ec: 8338651e  fsub d3, d4, d5
      #|  00f0: e608681e  fmul d6, d7, d8
      #|  00f4: 49196b1e  fdiv d9, d10, d11
      #|  00f8: 2040601e  fmov d0, d1
      #|  00fc: 6200679e  fmov d2, x3
      #|  0100: a400669e  fmov x4, d5
      #|  0104: e600271e  fmov s6, w7
      #|  0108: 2801261e  fmov w8, s9
      #|  010c: 6ac1221e  fcvt d10, s11
      #|  0110: 200040bd  ldr s0, [x1, #0]
      #|  0114: 620440fd  ldr d2, [x3, #8]
      #|  0118: a41000bd  str s4, [x5, #16]
      #|  011c: e60c00fd  str d6, [x7, #24]
      #|  0120: 1f0001eb  cmp x0, x1
      #|  0124: 5fa800f1  cmp x2, #42
      #|  0128: 6020641e  fcmp d3, d4
      #|  012c: e5179f9a  cset x5, eq
      #|  0130: e6079f9a  cset x6, ne
      #|  0134: e7a79f9a  cset x7, lt
      #|  0138: e8b79f9a  cset x8, ge
      #|block0:
      #|  013c: 06000014  b block1
      #|  0140: a0000054  b.eq block2
      #|  0144: 81000054  b.ne block3
      #|  0148: 6b000054  b.lt block4
      #|  014c: 400000b4  cbz x0, block5
      #|  0150: 210000b5  cbnz x1, block6
      #|block1:
      #|block2:
      #|block3:
      #|block4:
      #|block5:
      #|block6:
      #|  0154: faffff97  bl block0
      #|  0158: 00023fd6  blr x16
      #|  015c: 20021fd6  br x17
      #|  0160: c0035fd6  ret
      #|  0164: 52000010  adr x18, .+8
      #|  0168: 1f2003d5  nop
      #|
    ),
  )
}

///|
test "emit add.uxtw disasm" {
  let mc = MachineCode::new()
  mc.emit_add_uxtw(8, 10, 8, 0)
  mc.emit_add_uxtw(8, 10, 8, 2)
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: 4841288b  add x8, x10, w8, uxtw
      #|  0004: 4849288b  add x8, x10, w8, uxtw #2
      #|
    ),
  )
}

///|
test "emit load_imm64 -1 uses movn" {
  let mc = MachineCode::new()
  mc.emit_load_imm64(11, -1L)
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: 0b008092  movn x11, #0, lsl #0
      #|
    ),
  )
}

///|
test "emit_str_imm" {
  let mc = MachineCode::new()
  mc.emit_ldr_imm(0, 1, 8) // LDR X0, [X1, #8]
  mc.emit_str_imm(2, 3, 16) // STR X2, [X3, #16]
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: 200440f9  ldr x0, [x1, #8]
      #|  0004: 620800f9  str x2, [x3, #16]
      #|
    ),
  )
}

///|
test "emit_ldr_reg_scaled" {
  let mc = MachineCode::new()
  // LDR X0, [X1, X2, LSL #3] - scaled by 8 (for 64-bit elements)
  mc.emit_ldr_reg_scaled(0, 1, 2, 3)
  // LDR X3, [X4, X5, LSL #0] - no scaling
  mc.emit_ldr_reg_scaled(3, 4, 5, 0)
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: 207862f8  ldr x0, [x1, x2, lsl #3]
      #|  0004: 836865f8  ldr x3, [x4, x5, lsl #0]
      #|
    ),
  )
}

///|
test "emit_str_reg_scaled" {
  let mc = MachineCode::new()
  // STR X0, [X1, X2, LSL #3] - scaled by 8 (for 64-bit elements)
  mc.emit_str_reg_scaled(0, 1, 2, 3)
  // STR X3, [X4, X5, LSL #0] - no scaling
  mc.emit_str_reg_scaled(3, 4, 5, 0)
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: 207822f8  str x0, [x1, x2, lsl #3]
      #|  0004: 836825f8  str x3, [x4, x5, lsl #0]
      #|
    ),
  )
}

///|
test "emit_b_cond_offset" {
  let mc = MachineCode::new()
  // B.EQ +8 (skip 2 instructions)
  mc.emit_b_cond_offset(0, 8)
  // B.NE +12 (skip 3 instructions)
  mc.emit_b_cond_offset(1, 12)
  // B.LT +4 (skip 1 instruction)
  mc.emit_b_cond_offset(11, 4)
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: 40000054  b.eq .+8
      #|  0004: 61000054  b.ne .+12
      #|  0008: 2b000054  b.lt .+4
      #|
    ),
  )
}

///|
test "emit_brk" {
  let mc = MachineCode::new()
  // BRK #0
  mc.emit_brk(0)
  // BRK #2 (type mismatch trap)
  mc.emit_brk(2)
  // BRK #1 (general trap)
  mc.emit_brk(1)
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: 000020d4  brk #0
      #|  0004: 400020d4  brk #2
      #|  0008: 200020d4  brk #1
      #|
    ),
  )
}

///|
/// Test type check with small immediate (<=4095) - uses CMP immediate
test "type_check_small_immediate" {
  let mc = MachineCode::new()
  // Simulate TypeCheckIndirect with expected_type = 100 (small, fits in 12 bits)
  let expected_type = 100
  let actual_type_reg = 9 // x9
  // This path should use CMP immediate
  mc.emit_cmp_imm(actual_type_reg, expected_type)
  mc.emit_b_cond_offset(0, 8) // B.EQ +8
  mc.emit_brk(2)
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: 3f9101f1  cmp x9, #100
      #|  0004: 40000054  b.eq .+8
      #|  0008: 400020d4  brk #2
      #|
    ),
  )
}

///|
/// Test type check with large immediate (>4095) - uses load + CMP register
test "type_check_large_immediate" {
  let mc = MachineCode::new()
  // Simulate TypeCheckIndirect with expected_type = 7905 (0x1EE1, > 4095)
  let expected_type = 7905
  let actual_type_reg = 9 // x9
  // This path should load into x17 first, then use CMP register
  mc.emit_load_imm64(17, expected_type.to_int64())
  mc.emit_cmp_reg(actual_type_reg, 17)
  mc.emit_b_cond_offset(0, 8) // B.EQ +8
  mc.emit_brk(2)
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: 31dc83d2  movz x17, #7905, lsl #0
      #|  0004: 3f0111eb  cmp x9, x17
      #|  0008: 40000054  b.eq .+8
      #|  000c: 400020d4  brk #2
      #|
    ),
  )
}

///|
/// Test that CMP immediate truncates values > 4095 (this is the bug we fixed)
/// This test documents the limitation of emit_cmp_imm
test "cmp_imm_truncates_large_values" {
  let mc = MachineCode::new()
  // 7905 = 0x1EE1, masked to 12 bits = 0xEE1 = 3809
  // This shows the WRONG behavior if we use CMP immediate for large values
  mc.emit_cmp_imm(9, 7905) // Will compare against 3809, not 7905!
  mc.resolve_fixups()
  // Note: The annotation says 7905 but the actual immediate is 3809 (0xEE1)
  // This is why we must use load+cmp_reg for values > 4095
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: 3f853bf1  cmp x9, #7905
      #|
    ),
  )
  // Verify the actual encoded immediate by checking the instruction bytes
  // Bits [21:10] contain imm12. Let's decode 0xf13b853f:
  // The instruction encodes imm12 = 0xEE1 = 3809, not 7905
  let inst = mc.bytes[0] |
    (mc.bytes[1] << 8) |
    (mc.bytes[2] << 16) |
    (mc.bytes[3] << 24)
  let encoded_imm12 = (inst >> 10) & 0xFFF
  inspect(encoded_imm12, content="3809") // This proves truncation happened!
}

///|
/// Test Standard pre-indexed stores for prologue
test "emit_str_pre - GPR pre-indexed store" {
  let mc = MachineCode::new()
  // STR X19, [SP, #-16]! - single GPR push
  mc.emit_str_pre(19, 31, -16)
  // STR X20, [SP, #-8]!
  mc.emit_str_pre(20, 31, -8)
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: f30f1ff8  str x19, [sp, #-16]!
      #|  0004: f48f1ff8  str x20, [sp, #-8]!
      #|
    ),
  )
}

///|
/// Test Standard pre-indexed stores for FPR pairs
test "emit_stp_d_pre - FPR pair pre-indexed store" {
  let mc = MachineCode::new()
  // STP D8, D9, [SP, #-16]! - FPR pair push
  mc.emit_stp_d_pre(8, 9, 31, -16)
  // STP D10, D11, [SP, #-32]!
  mc.emit_stp_d_pre(10, 11, 31, -32)
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: e827bf6d  stp d8, d9, [sp, #-16]!
      #|  0004: ea2fbe6d  stp d10, d11, [sp, #-32]!
      #|
    ),
  )
}

///|
/// Test Standard pre-indexed store for single FPR
test "emit_str_d_pre - FPR pre-indexed store" {
  let mc = MachineCode::new()
  // STR D8, [SP, #-16]! - single FPR push
  mc.emit_str_d_pre(8, 31, -16)
  // STR D15, [SP, #-8]!
  mc.emit_str_d_pre(15, 31, -8)
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: e80f1ffc  str d8, [sp, #-16]!
      #|  0004: ef8f1ffc  str d15, [sp, #-8]!
      #|
    ),
  )
}

///|
/// Test Standard post-indexed loads for epilogue
test "emit_ldr_post - GPR post-indexed load" {
  let mc = MachineCode::new()
  // LDR X19, [SP], #16 - single GPR pop
  mc.emit_ldr_post(19, 31, 16)
  // LDR X20, [SP], #8
  mc.emit_ldr_post(20, 31, 8)
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: f30741f8  ldr x19, [sp], #16
      #|  0004: f48740f8  ldr x20, [sp], #8
      #|
    ),
  )
}

///|
/// Test Standard post-indexed loads for FPR pairs
test "emit_ldp_d_post - FPR pair post-indexed load" {
  let mc = MachineCode::new()
  // LDP D8, D9, [SP], #16 - FPR pair pop
  mc.emit_ldp_d_post(8, 9, 31, 16)
  // LDP D10, D11, [SP], #32
  mc.emit_ldp_d_post(10, 11, 31, 32)
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: e827c16c  ldp d8, d9, [sp], #16
      #|  0004: ea2fc26c  ldp d10, d11, [sp], #32
      #|
    ),
  )
}

///|
/// Test Standard post-indexed load for single FPR
test "emit_ldr_d_post - FPR post-indexed load" {
  let mc = MachineCode::new()
  // LDR D8, [SP], #16 - single FPR pop
  mc.emit_ldr_d_post(8, 31, 16)
  // LDR D15, [SP], #8
  mc.emit_ldr_d_post(15, 31, 8)
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: e80741fc  ldr d8, [sp], #16
      #|  0004: ef8740fc  ldr d15, [sp], #8
      #|
    ),
  )
}

///|
/// Test offset-based STP/LDP for GPRs (not pre/post indexed)
test "emit_stp_ldp_offset - GPR pairs with offset" {
  let mc = MachineCode::new()
  // STP X19, X20, [SP, #0]
  mc.emit_stp_offset(19, 20, 31, 0)
  // STP X21, X22, [SP, #16]
  mc.emit_stp_offset(21, 22, 31, 16)
  // LDP X19, X20, [SP, #0]
  mc.emit_ldp_offset(19, 20, 31, 0)
  // LDP X21, X22, [SP, #16]
  mc.emit_ldp_offset(21, 22, 31, 16)
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: f35300a9  stp x19, x20, [sp, #0]
      #|  0004: f55b01a9  stp x21, x22, [sp, #16]
      #|  0008: f35340a9  ldp x19, x20, [sp, #0]
      #|  000c: f55b41a9  ldp x21, x22, [sp, #16]
      #|
    ),
  )
}

///|
/// Test offset-based STP/LDP for FPRs (D registers)
test "emit_stp_ldp_d_offset - FPR pairs with offset" {
  let mc = MachineCode::new()
  // STP D8, D9, [SP, #0]
  mc.emit_stp_d_offset(8, 9, 31, 0)
  // STP D10, D11, [SP, #16]
  mc.emit_stp_d_offset(10, 11, 31, 16)
  // LDP D8, D9, [SP, #0]
  mc.emit_ldp_d_offset(8, 9, 31, 0)
  // LDP D10, D11, [SP, #16]
  mc.emit_ldp_d_offset(10, 11, 31, 16)
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: e827006d  stp d8, d9, [sp, #0]
      #|  0004: ea2f016d  stp d10, d11, [sp, #16]
      #|  0008: e827406d  ldp d8, d9, [sp, #0]
      #|  000c: ea2f416d  ldp d10, d11, [sp, #16]
      #|
    ),
  )
}

///|
/// Test complete Standard prologue sequence
test "standard_prologue_sequence" {
  let mc = MachineCode::new()
  // Step 1: Save FP/LR with fixed -16 pre-indexed
  mc.emit_stp_pre(29, 30, 31, -16)
  // MOV X29, SP (set frame pointer)
  mc.emit_mov_reg(29, 31)
  // Step 2: Save GPRs with pre-indexed pushes
  mc.emit_stp_pre(19, 20, 31, -16)
  mc.emit_str_pre(21, 31, -16) // Single GPR
  // Step 3: Save FPRs with pre-indexed pushes
  mc.emit_stp_d_pre(8, 9, 31, -16)
  mc.emit_str_d_pre(10, 31, -16) // Single FPR
  // Step 4: Allocate remaining stack (spill + outgoing)
  mc.emit_sub_imm(31, 31, 64)
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: fd7bbfa9  stp x29, x30, [sp, #-16]!
      #|  0004: fd031faa  mov x29, x31
      #|  0008: f353bfa9  stp x19, x20, [sp, #-16]!
      #|  000c: f50f1ff8  str x21, [sp, #-16]!
      #|  0010: e827bf6d  stp d8, d9, [sp, #-16]!
      #|  0014: ea0f1ffc  str d10, [sp, #-16]!
      #|  0018: ff0301d1  sub sp, sp, #64
      #|
    ),
  )
}

///|
/// Test complete Standard epilogue sequence
test "standard_epilogue_sequence" {
  let mc = MachineCode::new()
  // Step 1: Deallocate remaining stack
  mc.emit_add_imm(31, 31, 64)
  // Step 2: Restore FPRs with post-indexed pops (reverse order)
  mc.emit_ldr_d_post(10, 31, 16) // Single FPR first
  mc.emit_ldp_d_post(8, 9, 31, 16)
  // Step 3: Restore GPRs with post-indexed pops (reverse order)
  mc.emit_ldr_post(21, 31, 16) // Single GPR first
  mc.emit_ldp_post(19, 20, 31, 16)
  // Step 4: Restore FP/LR with post-indexed pop
  mc.emit_ldp_post(29, 30, 31, 16)
  // Return
  mc.emit_ret(30)
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: ff030191  add sp, sp, #64
      #|  0004: ea0741fc  ldr d10, [sp], #16
      #|  0008: e827c16c  ldp d8, d9, [sp], #16
      #|  000c: f50741f8  ldr x21, [sp], #16
      #|  0010: f353c1a8  ldp x19, x20, [sp], #16
      #|  0014: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0018: c0035fd6  ret
      #|
    ),
  )
}

///|
/// Test 32-bit instruction variants for i32 operations
test "32-bit instruction variants" {
  let mc = MachineCode::new()

  // 32-bit arithmetic
  mc.emit_sdiv32(0, 1, 2) // SDIV W0, W1, W2
  mc.emit_udiv32(3, 4, 5) // UDIV W3, W4, W5
  mc.emit_sub_reg32(6, 7, 8) // SUB W6, W7, W8
  mc.emit_add_reg32(0, 1, 2) // ADD W0, W1, W2
  mc.emit_add_imm32(3, 4, 100) // ADD W3, W4, #100
  mc.emit_mul32(5, 6, 7) // MUL W5, W6, W7

  // 32-bit shifts
  mc.emit_lsl_reg32(9, 10, 11) // LSL W9, W10, W11
  mc.emit_lsr_reg32(12, 13, 14) // LSR W12, W13, W14
  mc.emit_asr_reg32(15, 16, 17) // ASR W15, W16, W17
  mc.emit_ror_reg32(18, 19, 20) // ROR W18, W19, W20

  // 32-bit bit manipulation
  mc.emit_clz32(21, 22) // CLZ W21, W22
  mc.emit_rbit32(23, 24) // RBIT W23, W24

  // 32-bit comparison
  mc.emit_cmp_reg32(25, 26) // CMP W25, W26
  mc.emit_cmp_imm32(27, 42) // CMP W27, #42

  // 32-bit move
  mc.emit_mov_reg32(28, 29) // MOV W28, W29
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: 200cc21a  sdiv w0, w1, w2
      #|  0004: 8308c51a  udiv w3, w4, w5
      #|  0008: e600084b  sub w6, w7, w8
      #|  000c: 2000020b  add w0, w1, w2
      #|  0010: 83900111  add w3, w4, #100
      #|  0014: c57c071b  mul w5, w6, w7
      #|  0018: 4921cb1a  lsl w9, w10, w11
      #|  001c: ac25ce1a  lsr w12, w13, w14
      #|  0020: 0f2ad11a  asr w15, w16, w17
      #|  0024: 722ed41a  ror w18, w19, w20
      #|  0028: d512c05a  clz w21, w22
      #|  002c: 1703c05a  rbit w23, w24
      #|  0030: 3f031a6b  cmp w25, w26
      #|  0034: 7fab0071  cmp w27, #42
      #|  0038: fc031d2a  mov w28, w29
      #|
    ),
  )
}

///|
/// Test CBNZ with immediate offset (for TrapIfZero)
test "cbnz_offset instruction" {
  let mc = MachineCode::new()
  // CBNZ X0, +8 (64-bit)
  CbnzOffset(0, true, 8).emit(mc)
  // CBNZ W1, +8 (32-bit)
  CbnzOffset(1, false, 8).emit(mc)
  // BRK #4
  mc.emit_brk(4)
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: 400000b5  cbnz x0, .+8
      #|  0004: 41000035  cbnz w1, .+8
      #|  0008: 800020d4  brk #4
      #|
    ),
  )
}

///|
/// Test ADDS with zero register (for checking rhs == -1)
test "adds_imm_zr instruction" {
  let mc = MachineCode::new()
  // ADDS XZR, X0, #1 (64-bit) - check if X0 == -1
  AddsImmZr(0, 1, true).emit(mc)
  // ADDS WZR, W1, #1 (32-bit) - check if W1 == -1
  AddsImmZr(1, 1, false).emit(mc)
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: 1f0400b1  adds xzr, x0, #1
      #|  0004: 3f040031  adds wzr, w1, #1
      #|
    ),
  )
}

///|
/// Test CCMP (conditional compare immediate)
test "ccmp_imm instruction" {
  let mc = MachineCode::new()
  // CCMP X0, #1, #0, EQ (64-bit) - if Z set, compare X0-1
  CCmpImm(0, 1, 0, 0, true).emit(mc)
  // CCMP W1, #1, #0, EQ (32-bit) - if Z set, compare W1-1
  CCmpImm(1, 1, 0, 0, false).emit(mc)
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: 000841fa  ccmp x0, #1, #0, eq
      #|  0004: 2008417a  ccmp w1, #1, #0, eq
      #|
    ),
  )
}

///|
/// Test div overflow trap sequence (INT_MIN / -1)
test "div_overflow_trap_sequence" {
  let mc = MachineCode::new()
  // Full sequence for checking INT_MIN / -1 (64-bit):
  // 1. ADDS XZR, X1, #1 - check if divisor == -1
  AddsImmZr(1, 1, true).emit(mc)
  // 2. CCMP X0, #1, #0, EQ - if divisor == -1, check if dividend-1 overflows
  CCmpImm(0, 1, 0, 0, true).emit(mc)
  // 3. B.VC +8 - skip trap if no overflow
  mc.emit_b_cond_offset(7, 8) // VC = condition 7
  // 4. BRK #4 - trap on overflow
  mc.emit_brk(4)
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: 3f0400b1  adds xzr, x1, #1
      #|  0004: 000841fa  ccmp x0, #1, #0, eq
      #|  0008: 47000054  b.vc .+8
      #|  000c: 800020d4  brk #4
      #|
    ),
  )
}
