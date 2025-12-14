///|
/// Comprehensive test for disassembly output
/// Tests that all emit functions produce correct annotated output
test "comprehensive disasm test" {
  // Test a complex WASM function that uses many instructions
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (param i64 i64) (result i64)
    #|    (local i64)
    #|    ;; Add params
    #|    (local.set 2 (i64.add (local.get 0) (local.get 1)))
    #|    ;; Multiply
    #|    (local.set 2 (i64.mul (local.get 2) (local.get 0)))
    #|    ;; Subtract
    #|    (local.set 2 (i64.sub (local.get 2) (local.get 1)))
    #|    ;; Bitwise operations
    #|    (local.set 2 (i64.and (local.get 2) (i64.const 255)))
    #|    (local.set 2 (i64.or (local.get 2) (i64.const 256)))
    #|    (local.set 2 (i64.xor (local.get 2) (i64.const 128)))
    #|    ;; Shifts
    #|    (local.set 2 (i64.shl (local.get 2) (i64.const 2)))
    #|    (local.set 2 (i64.shr_s (local.get 2) (i64.const 1)))
    #|    ;; Return
    #|    (local.get 2)
    #|  )
    #|)
  let ir = @wat.parse(source)
  let func_code = ir.codes[0]
  let func_type_idx = ir.funcs[0]
  let func_type = ir.types[func_type_idx]
  let locals : Array[@types.ValueType] = []
  for loc in func_code.locals {
    locals.push(loc)
  }
  let translator = @ir.Translator::new(
    "test",
    func_type,
    locals,
    ir.types,
    ir.funcs.mapi(fn(i, _) { ir.funcs[i] }),
    0,
    [],
  )
  let ir_func = translator.translate(func_code.body)
  let vcode = lower_function(ir_func)
  let allocated = allocate_registers_aarch64(vcode)
  let mc = emit_function(allocated)
  let disasm = mc.dump_disasm()
  // Check that disasm is not empty
  assert_true(disasm.length() > 0)
  // Check for key instructions that should be present
  assert_true(disasm.contains("sub sp"))
  assert_true(disasm.contains("stp x"))
  assert_true(disasm.contains("mov x"))
  assert_true(disasm.contains("add x"))
  assert_true(disasm.contains("mul x"))
  assert_true(disasm.contains("sub x"))
  assert_true(disasm.contains("and x"))
  assert_true(disasm.contains("orr x"))
  assert_true(disasm.contains("eor x"))
  assert_true(disasm.contains("lsl x"))
  assert_true(disasm.contains("asr x"))
  assert_true(disasm.contains("ldp x"))
  assert_true(disasm.contains("add sp"))
  assert_true(disasm.contains("ret"))
}

///|
/// Test float operations disassembly
test "float operations disasm" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (param f64 f64) (result f64)
    #|    (local f64)
    #|    (local.set 2 (f64.add (local.get 0) (local.get 1)))
    #|    (local.set 2 (f64.sub (local.get 2) (local.get 1)))
    #|    (local.set 2 (f64.mul (local.get 2) (local.get 0)))
    #|    (local.set 2 (f64.div (local.get 2) (local.get 1)))
    #|    (local.get 2)
    #|  )
    #|)
  let ir = @wat.parse(source)
  let func_code = ir.codes[0]
  let func_type_idx = ir.funcs[0]
  let func_type = ir.types[func_type_idx]
  let locals : Array[@types.ValueType] = []
  for loc in func_code.locals {
    locals.push(loc)
  }
  let translator = @ir.Translator::new(
    "test",
    func_type,
    locals,
    ir.types,
    ir.funcs.mapi(fn(i, _) { ir.funcs[i] }),
    0,
    [],
  )
  let ir_func = translator.translate(func_code.body)
  let vcode = lower_function(ir_func)
  let allocated = allocate_registers_aarch64(vcode)
  let mc = emit_function(allocated)
  let disasm = mc.dump_disasm()
  // Check for float instructions
  assert_true(disasm.contains("fadd d"))
  assert_true(disasm.contains("fsub d"))
  assert_true(disasm.contains("fmul d"))
  assert_true(disasm.contains("fdiv d"))
  assert_true(disasm.contains("fmov d"))
}

///|
/// Test memory operations disassembly
test "memory operations disasm" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (param i32) (result i64)
    #|    ;; Load various sizes
    #|    (i64.load (local.get 0))
    #|  )
    #|)
  let ir = @wat.parse(source)
  let func_code = ir.codes[0]
  let func_type_idx = ir.funcs[0]
  let func_type = ir.types[func_type_idx]
  let locals : Array[@types.ValueType] = []
  for loc in func_code.locals {
    locals.push(loc)
  }
  let translator = @ir.Translator::new(
    "test",
    func_type,
    locals,
    ir.types,
    ir.funcs.mapi(fn(i, _) { ir.funcs[i] }),
    0,
    [],
  )
  let ir_func = translator.translate(func_code.body)
  let vcode = lower_function(ir_func)
  let allocated = allocate_registers_aarch64(vcode)
  let mc = emit_function(allocated)
  let disasm = mc.dump_disasm()
  // Check for load instruction
  assert_true(disasm.contains("ldr x"))
}

///|
/// Test branch/control flow disassembly
test "branch operations disasm" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (param i32) (result i32)
    #|    (if (result i32) (local.get 0)
    #|      (then (i32.const 1))
    #|      (else (i32.const 0))
    #|    )
    #|  )
    #|)
  let ir = @wat.parse(source)
  let func_code = ir.codes[0]
  let func_type_idx = ir.funcs[0]
  let func_type = ir.types[func_type_idx]
  let locals : Array[@types.ValueType] = []
  for loc in func_code.locals {
    locals.push(loc)
  }
  let translator = @ir.Translator::new(
    "test",
    func_type,
    locals,
    ir.types,
    ir.funcs.mapi(fn(i, _) { ir.funcs[i] }),
    0,
    [],
  )
  let ir_func = translator.translate(func_code.body)
  let vcode = lower_function(ir_func)
  let allocated = allocate_registers_aarch64(vcode)
  let mc = emit_function(allocated)
  let disasm = mc.dump_disasm()
  // Check for branch instructions
  assert_true(
    disasm.contains("cbnz x") ||
    disasm.contains("cbz x") ||
    disasm.contains("b block"),
  )
}

///|
/// Test comparison operations disassembly
test "comparison operations disasm" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (param i64 i64) (result i32)
    #|    (i64.lt_s (local.get 0) (local.get 1))
    #|  )
    #|)
  let ir = @wat.parse(source)
  let func_code = ir.codes[0]
  let func_type_idx = ir.funcs[0]
  let func_type = ir.types[func_type_idx]
  let locals : Array[@types.ValueType] = []
  for loc in func_code.locals {
    locals.push(loc)
  }
  let translator = @ir.Translator::new(
    "test",
    func_type,
    locals,
    ir.types,
    ir.funcs.mapi(fn(i, _) { ir.funcs[i] }),
    0,
    [],
  )
  let ir_func = translator.translate(func_code.body)
  let vcode = lower_function(ir_func)
  let allocated = allocate_registers_aarch64(vcode)
  let mc = emit_function(allocated)
  let disasm = mc.dump_disasm()
  // Check for comparison and set instructions
  assert_true(disasm.contains("cmp x"))
  assert_true(disasm.contains("cset x"))
}

///|
/// Direct test of all emit functions - no compilation, just raw instruction emission
test "all emit functions disasm" {
  let mc = MachineCode::new()

  // Integer arithmetic
  emit_add_reg(mc, 0, 1, 2)
  emit_add_imm(mc, 3, 4, 100)
  emit_sub_reg(mc, 5, 6, 7)
  emit_sub_imm(mc, 8, 9, 200)
  emit_mul(mc, 10, 11, 12)
  emit_sdiv(mc, 13, 14, 15)
  emit_udiv(mc, 16, 17, 18)

  // Logical operations
  emit_and_reg(mc, 19, 20, 21)
  emit_orr_reg(mc, 22, 23, 24)
  emit_eor_reg(mc, 25, 26, 27)

  // Shifts
  emit_lsl_reg(mc, 0, 1, 2)
  emit_lsr_reg(mc, 3, 4, 5)
  emit_asr_reg(mc, 6, 7, 8)

  // Shifted operand variants
  emit_add_shifted(mc, 0, 1, 2, Lsl, 3)
  emit_sub_shifted(mc, 3, 4, 5, Lsr, 4)
  emit_and_shifted(mc, 6, 7, 8, Asr, 5)
  emit_orr_shifted(mc, 9, 10, 11, Lsl, 6)
  emit_eor_shifted(mc, 12, 13, 14, Lsr, 7)

  // Multiply-accumulate
  emit_madd(mc, 0, 1, 2, 3)
  emit_msub(mc, 4, 5, 6, 7)
  emit_mneg(mc, 8, 9, 10)

  // Move instructions
  emit_mov_reg(mc, 0, 1)
  emit_mov_reg32(mc, 2, 3)
  emit_movz(mc, 4, 0x1234, 0)
  emit_movz(mc, 5, 0xABCD, 16)
  emit_movk(mc, 6, 0x5678, 32)

  // Load immediate
  emit_load_imm64(mc, 7, 0x123456789ABCDEF0L)

  // Integer loads
  emit_ldr_imm(mc, 0, 1, 0)
  emit_ldr_imm(mc, 2, 3, 64)
  emit_ldrb_imm(mc, 4, 5, 10)
  emit_ldrh_imm(mc, 6, 7, 20)
  emit_ldr_w_imm(mc, 8, 9, 40)

  // Sign-extending loads
  emit_ldrsb_x_imm(mc, 10, 11, 5)
  emit_ldrsb_w_imm(mc, 12, 13, 6)
  emit_ldrsh_x_imm(mc, 14, 15, 8)
  emit_ldrsh_w_imm(mc, 16, 17, 10)
  emit_ldrsw_imm(mc, 18, 19, 16)

  // Sign/Zero Extension Instructions
  emit_sxtb_x(mc, 0, 1) // Sign extend byte to 64-bit
  emit_sxth_x(mc, 2, 3) // Sign extend halfword to 64-bit
  emit_sxtw(mc, 4, 5) // Sign extend word to 64-bit
  emit_sxtb_w(mc, 6, 7) // Sign extend byte to 32-bit
  emit_sxth_w(mc, 8, 9) // Sign extend halfword to 32-bit
  emit_uxtb_x(mc, 10, 11) // Zero extend byte to 64-bit
  emit_uxth_x(mc, 12, 13) // Zero extend halfword to 64-bit
  emit_uxtb_w(mc, 14, 15) // Zero extend byte to 32-bit
  emit_uxth_w(mc, 16, 17) // Zero extend halfword to 32-bit

  // Integer stores
  emit_str_imm(mc, 0, 1, 0)
  emit_str_imm(mc, 2, 3, 64)
  emit_strb_imm(mc, 4, 5, 10)
  emit_strh_imm(mc, 6, 7, 20)
  emit_str_w_imm(mc, 8, 9, 40)

  // Stack pair operations
  emit_stp_pre(mc, 29, 30, 31, -16)
  emit_ldp_post(mc, 29, 30, 31, 16)
  emit_stp_offset(mc, 19, 20, 31, 0)
  emit_ldp_offset(mc, 21, 22, 31, 16)

  // Floating-point arithmetic
  emit_fadd_d(mc, 0, 1, 2)
  emit_fsub_d(mc, 3, 4, 5)
  emit_fmul_d(mc, 6, 7, 8)
  emit_fdiv_d(mc, 9, 10, 11)

  // Floating-point moves
  emit_fmov_d(mc, 0, 1)
  emit_fmov_x_to_d(mc, 2, 3)
  emit_fmov_d_to_x(mc, 4, 5)
  emit_fmov_w_to_s(mc, 6, 7)
  emit_fmov_s_to_w(mc, 8, 9)
  emit_fcvt_d_s(mc, 10, 11)

  // Floating-point loads/stores
  emit_ldr_s_imm(mc, 0, 1, 0)
  emit_ldr_d_imm(mc, 2, 3, 8)
  emit_str_s_imm(mc, 4, 5, 16)
  emit_str_d_imm(mc, 6, 7, 24)

  // Comparison
  emit_cmp_reg(mc, 0, 1)
  emit_cmp_imm(mc, 2, 42)
  emit_fcmp_d(mc, 3, 4)
  emit_cset(mc, 5, CondCode::EQ.to_int())
  emit_cset(mc, 6, CondCode::NE.to_int())
  emit_cset(mc, 7, CondCode::LT.to_int())
  emit_cset(mc, 8, CondCode::GE.to_int())

  // Branches
  mc.define_label(0)
  emit_b(mc, 1)
  emit_b_cond(mc, CondCode::EQ.to_int(), 2)
  emit_b_cond(mc, CondCode::NE.to_int(), 3)
  emit_b_cond(mc, CondCode::LT.to_int(), 4)
  emit_cbz(mc, 0, 5)
  emit_cbnz(mc, 1, 6)
  mc.define_label(1)
  mc.define_label(2)
  mc.define_label(3)
  mc.define_label(4)
  mc.define_label(5)
  mc.define_label(6)

  // Call and return
  emit_bl(mc, 0)
  emit_blr(mc, 16)
  emit_br(mc, 17) // Branch register (indirect jump)
  emit_ret(mc, 30)

  // ADR (PC-relative address)
  emit_adr(mc, 18, 8) // ADR x18, .+8

  // NOP
  emit_nop(mc)
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
      #|  0050: 28fd0a9b  msub x8, x9, x10, x31
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
      #|  00e0: f35300a9  stp x19, x20, [sp, #0]
      #|  00e4: f55b41a9  ldp x21, x22, [sp, #16]
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
test "emit_str_imm" {
  let mc = MachineCode::new()
  emit_ldr_imm(mc, 0, 1, 8) // LDR X0, [X1, #8]
  emit_str_imm(mc, 2, 3, 16) // STR X2, [X3, #16]
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
  emit_ldr_reg_scaled(mc, 0, 1, 2, 3)
  // LDR X3, [X4, X5, LSL #0] - no scaling
  emit_ldr_reg_scaled(mc, 3, 4, 5, 0)
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
  emit_str_reg_scaled(mc, 0, 1, 2, 3)
  // STR X3, [X4, X5, LSL #0] - no scaling
  emit_str_reg_scaled(mc, 3, 4, 5, 0)
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
  emit_b_cond_offset(mc, 0, 8)
  // B.NE +12 (skip 3 instructions)
  emit_b_cond_offset(mc, 1, 12)
  // B.LT +4 (skip 1 instruction)
  emit_b_cond_offset(mc, 11, 4)
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
  emit_brk(mc, 0)
  // BRK #2 (type mismatch trap)
  emit_brk(mc, 2)
  // BRK #1 (general trap)
  emit_brk(mc, 1)
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
  emit_cmp_imm(mc, actual_type_reg, expected_type)
  emit_b_cond_offset(mc, 0, 8) // B.EQ +8
  emit_brk(mc, 2)
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
  emit_load_imm64(mc, 17, expected_type.to_int64())
  emit_cmp_reg(mc, actual_type_reg, 17)
  emit_b_cond_offset(mc, 0, 8) // B.EQ +8
  emit_brk(mc, 2)
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
  emit_cmp_imm(mc, 9, 7905) // Will compare against 3809, not 7905!
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
