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
  emit_ret(mc, 30)

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
      #|  0014: 4d1bcf9a  sdiv x13, x14, x15
      #|  0018: 3014c29b  udiv x16, x17, x18
      #|  001c: 9302158a  and x19, x20, x21
      #|  0020: f60218aa  orr x22, x23, x24
      #|  0024: 59031bca  eor x25, x26, x27
      #|  0028: 2040c29a  lsl x0, x1, x2
      #|  002c: 0349c59a  lsr x3, x4, x5
      #|  0030: 6651c89a  asr x6, x7, x8
      #|  0034: 2018018b  add x0, x1, x2, lsl #3
      #|  0038: 036142cb  sub x3, x4, x5, lsr #4
      #|  003c: 6629848a  and x6, x7, x8, asr #5
      #|  0040: 497205aa  orr x9, x10, x11, lsl #6
      #|  0044: 2c3b47ca  eor x12, x13, x14, lsr #7
      #|  0048: 2018029b  madd x0, x1, x2, x3
      #|  004c: 24b9069b  msub x4, x5, x6, x7
      #|  0050: 28fa0a9b  mneg x8, x9, x10
      #|  0050: 28fa0a9b  msub x8, x9, x10, x31
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
      #|  00a0: 200000f9  str x0, [x1, #0]
      #|  00a4: 622000f9  str x2, [x3, #64]
      #|  00a8: a4280039  strb w4, [x5, #10]
      #|  00ac: e6280079  strh w6, [x7, #20]
      #|  00b0: 282900b9  str w8, [x9, #40]
      #|  00b4: fd7bbfa9  stp x29, x30, [sp, #-16]!
      #|  00b8: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  00bc: f35300a9  stp x19, x20, [sp, #0]
      #|  00c0: f55b41a9  ldp x21, x22, [sp, #16]
      #|  00c4: 2028621e  fadd d0, d1, d2
      #|  00c8: 0339651e  fsub d3, d4, d5
      #|  00cc: 6609681e  fmul d6, d7, d8
      #|  00d0: 491a6b1e  fdiv d9, d10, d11
      #|  00d4: 2040601e  fmov d0, d1
      #|  00d8: 6200679e  fmov d2, x3
      #|  00dc: a400669e  fmov x4, d5
      #|  00e0: e600271e  fmov s6, w7
      #|  00e4: 2801261e  fmov w8, s9
      #|  00e8: 6ac1221e  fcvt d10, s11
      #|  00ec: 200040bd  ldr s0, [x1, #0]
      #|  00f0: 620440fd  ldr d2, [x3, #8]
      #|  00f4: a41000bd  str s4, [x5, #16]
      #|  00f8: e60c00fd  str d6, [x7, #24]
      #|  00fc: 1f0001eb  cmp x0, x1
      #|  0100: 5f5001f1  cmp x2, #42
      #|  0104: 6020641e  fcmp d3, d4
      #|  0108: e5179f9a  cset x5, eq
      #|  010c: e6079f9a  cset x6, ne
      #|  0110: e7a79f9a  cset x7, lt
      #|  0114: e8b79f9a  cset x8, ge
      #|block0:
      #|  0118: 06000014  b block1
      #|  011c: a0000054  b.eq block2
      #|  0120: 81000054  b.ne block3
      #|  0124: 6b000054  b.lt block4
      #|  0128: 400000b4  cbz x0, block5
      #|  012c: 210000b5  cbnz x1, block6
      #|block6:
      #|  0130: faffff97  bl block0
      #|  0134: 00023fd6  blr x16
      #|  0138: c0035fd6  ret
      #|  013c: 1f2003d5  nop
      #|
    ),
  )
}
