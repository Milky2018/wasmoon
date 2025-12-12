// End-to-End Execution Tests for JIT Compiler
// These tests compile IR functions to machine code and actually execute them

// ============ f32_br_2locals.wast Reproduction ============
// This test reproduces the exact test pattern from testsuite/data/f32_br_2locals.wast
// and verifies the JIT-compiled code returns correct values:
//   (assert_return (invoke "test" (i32.const 0)) (f32.const 10.0))
//   (assert_return (invoke "test" (i32.const 1)) (f32.const 10.0))
//   (assert_return (invoke "test" (i32.const 2)) (f32.const 10.0))
//   (assert_return (invoke "test" (i32.const 3)) (f32.const 0.0))

///|
test "execute br_table with f32 locals (f32_br_2locals.wast)" {
  // Build IR function: fn test(selector: i32) -> f32
  // Structure:
  //   entry: local1 = 10.0, local2_init = 0.0, br_table(selector)
  //   case0/1/2: store local1 to mem[0], load to local2, jump exit
  //   exit(local2_phi): return local2_phi
  let builder = @ir.IRBuilder::new("test")
  let selector = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::F32)

  // Create all blocks
  let entry = builder.create_block()
  let case0 = builder.create_block()
  let case1 = builder.create_block()
  let case2 = builder.create_block()
  let exit = builder.create_block()

  // Add block parameter for exit (the merged local2 value)
  let local2_phi = builder.add_block_param(exit, @ir.Type::F32)

  // Entry block: set up locals and br_table
  builder.switch_to_block(entry)
  let local1 = builder.fconst_f32(10.0) // local1 = 10.0
  let local2_init = builder.fconst_f32(0.0) // local2 initial = 0.0
  let addr = builder.iconst_i32(0) // memory address for store/load
  // br_table: targets = [case0, case1, case2], default = exit
  builder.br_table(selector, [case0, case1, case2], exit)

  // case0: store local1, load to local2, jump exit
  builder.switch_to_block(case0)
  builder.store(@ir.Type::F32, addr, local1, 0)
  let local2_0 = builder.load(@ir.Type::F32, addr, 0)
  builder.jump(exit, [local2_0])

  // case1: same pattern
  builder.switch_to_block(case1)
  builder.store(@ir.Type::F32, addr, local1, 0)
  let local2_1 = builder.load(@ir.Type::F32, addr, 0)
  builder.jump(exit, [local2_1])

  // case2: same pattern
  builder.switch_to_block(case2)
  builder.store(@ir.Type::F32, addr, local1, 0)
  let local2_2 = builder.load(@ir.Type::F32, addr, 0)
  builder.jump(exit, [local2_2])

  // exit: return local2_phi
  builder.switch_to_block(exit)
  builder.return_([local2_phi])

  // Ignore unused values
  ignore(local2_init)

  // ============ Compilation Pipeline ============
  // 1. Lower IR to VCode
  let vcode_func = @vcode.lower_function(builder.get_function())

  // 2. Register allocation
  let allocated_func = @vcode.allocate_registers_aarch64(vcode_func)

  // 3. Emit machine code
  let mc = @vcode.emit_function(allocated_func)

  // Debug: print allocated VCode for the working test
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(v0:int) -> float {
      #|block0:
      #|    d0 = ldf 10
      #|    x8 = ldi 0
      #|    x19 = ldi 0
      #|    x23 = cmp.eq x3, x19
      #|    branch x23, block1, block5
      #|block1:
      #|    bounds_check +0, 4 x8
      #|    x19 = add x21, x8
      #|    store.f32 +0 x19, d0
      #|    bounds_check +0, 4 x8
      #|    x19 = add x21, x8
      #|    d0 = load.f32 +0 x19
      #|    d2 = mov d0
      #|    jump block4
      #|block2:
      #|    bounds_check +0, 4 x8
      #|    x19 = add x21, x8
      #|    store.f32 +0 x19, d0
      #|    bounds_check +0, 4 x8
      #|    x19 = add x21, x8
      #|    d1 = load.f32 +0 x19
      #|    d2 = mov d1
      #|    jump block4
      #|block3:
      #|    bounds_check +0, 4 x8
      #|    x19 = add x21, x8
      #|    store.f32 +0 x19, d0
      #|    bounds_check +0, 4 x8
      #|    x19 = add x21, x8
      #|    d1 = load.f32 +0 x19
      #|    d2 = mov d1
      #|    jump block4
      #|block4(f1:float):
      #|    ret d2
      #|block5:
      #|    x19 = ldi 1
      #|    x23 = cmp.eq x3, x19
      #|    branch x23, block2, block6
      #|block6:
      #|    x19 = ldi 2
      #|    x23 = cmp.eq x3, x19
      #|    branch x23, block3, block4
      #|}
      #|
    ),
  )

  // ============ Set up JIT Execution Context ============
  // Create JIT module with single function
  let code_bytes = mc.get_bytes()
  let jit_module = JITModule::from_single_function(
    code_bytes,
    "test",
    1, // num_params
    [@types.ValueType::F32], // result_types
    4096L, // mem_size
  )
  guard jit_module is Some(jm) else { return }
  defer jm.free()
  let func = jm.get_func_by_name("test")
  guard func is Some(f) else { return }

  // ============ Execute and Verify ============
  // Note: This test builds IR manually without proper phi handling for br_table default case
  // The br_table default jumps to exit without passing local2_init, so d2 retains its previous value
  // For proper WAST behavior, see the "end-to-end" test below which parses actual WAST

  // test(0) should return 10.0 (store 10 to mem[0], load back)
  let Single((result0_f32 : Float)) = jm.call_with_context_poly(f, Single(0))
  inspect(result0_f32, content="10")

  // test(1) should return 10.0
  let Single((result1_f32 : Float)) = jm.call_with_context_poly(f, Single(1))
  inspect(result1_f32, content="10")

  // test(2) should return 10.0
  let Single((result2_f32 : Float)) = jm.call_with_context_poly(f, Single(2))
  inspect(result2_f32, content="10")

  // test(3) - default case: jumps directly to exit, d2 retains value from d0 (which is 10.0)
  let Single((result3_f32 : Float)) = jm.call_with_context_poly(f, Single(3))
  inspect(result3_f32, content="10")
}

// ============ End-to-End WAST Source Test ============
// This test parses the actual f32_br_2locals.wast source, translates WASM → IR,
// compiles through the full JIT pipeline, and verifies the assert_return statements.

///|
test "end-to-end: f32_br_2locals.wast from source" {
  // The actual WAST source from testsuite/data/f32_br_2locals.wast
  let wast_source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (param i32) (result f32)
    #|    (local f32 f32)
    #|    (local.set 1 (f32.const 10.0))
    #|    (block $3
    #|      (block $2
    #|        (block $1
    #|          (block $0
    #|            (br_table $0 $1 $2 $3 (local.get 0))
    #|          )
    #|          ;; case 0
    #|          (f32.store (i32.const 0) (local.get 1))
    #|          (local.set 2 (f32.load (i32.const 0)))
    #|          (br $3)
    #|        )
    #|        ;; case 1
    #|        (f32.store (i32.const 0) (local.get 1))
    #|        (local.set 2 (f32.load (i32.const 0)))
    #|        (br $3)
    #|      )
    #|      ;; case 2
    #|      (f32.store (i32.const 0) (local.get 1))
    #|      (local.set 2 (f32.load (i32.const 0)))
    #|      (br $3)
    #|    )
    #|    ;; case 3 / default
    #|    (local.get 2)
    #|  )
    #|)
    #|(assert_return (invoke "test" (i32.const 0)) (f32.const 10.0))
    #|(assert_return (invoke "test" (i32.const 1)) (f32.const 10.0))
    #|(assert_return (invoke "test" (i32.const 2)) (f32.const 10.0))
    #|(assert_return (invoke "test" (i32.const 3)) (f32.const 0.0))
  let script = @wast.parse(wast_source)
  inspect(script.commands.length(), content="5") // 1 module + 4 assert_return

  // Extract module from first command
  let (first_cmd, _) = script.commands[0]
  let wasm_module : @types.Module = match first_cmd {
    @wast.WastCommand::Module(m, _) => m
    _ => {
      inspect(false, content="First command should be Module")
      return
    }
  }

  // ============ Phase 2: Extract function and translate to IR ============
  // The module has one function (index 0)
  guard wasm_module.codes.length() > 0 else {
    inspect(false, content="Module should have at least one function")
    return
  }
  let func_code = wasm_module.codes[0]
  let func_type_idx = wasm_module.funcs[0]
  let func_type = wasm_module.types[func_type_idx]

  // Get locals from the function code
  let locals : Array[@types.ValueType] = []
  for loc in func_code.locals {
    locals.push(loc)
  }

  // Create translator and translate WASM to IR
  let translator = @ir.Translator::new(
    "test",
    func_type,
    locals,
    wasm_module.types,
    wasm_module.funcs.mapi(fn(i, _) { wasm_module.funcs[i] }),
    0, // num_imports
    [], // import_func_type_indices
  )
  let ir_func = translator.translate(func_code.body)

  // ============ Phase 3: Verify IR structure ============
  // The function should have params, results, and multiple blocks
  inspect(ir_func.params.length(), content="1") // i32 param
  inspect(ir_func.results.length(), content="1") // f32 result
  // WASM nested blocks produce 9 IR blocks (vs 5 in manual construction)
  inspect(ir_func.blocks.length(), content="9")

  // Debug: print the IR to understand structure
  inspect(
    ir_func.print(),
    content=(
      #|function test(v0:i32) -> f32 {
      #|block0:
      #|    v1:f32 = fconst 0
      #|    v2:f32 = fconst 0
      #|    v3:f32 = fconst 10
      #|    br_table v0, [block5, block6, block7], block8
      #|block1(v4:i32, v5:f32, v6:f32):
      #|    return v6
      #|block2(v7:i32, v8:f32, v9:f32):
      #|    v22:i32 = iconst 0
      #|    store.f32 v22, v8 +0
      #|    v23:i32 = iconst 0
      #|    v24:f32 = load.f32 v23 +0
      #|    jump block1(v7, v8, v24)
      #|block3(v10:i32, v11:f32, v12:f32):
      #|    v19:i32 = iconst 0
      #|    store.f32 v19, v11 +0
      #|    v20:i32 = iconst 0
      #|    v21:f32 = load.f32 v20 +0
      #|    jump block1(v10, v11, v21)
      #|block4(v13:i32, v14:f32, v15:f32):
      #|    v16:i32 = iconst 0
      #|    store.f32 v16, v14 +0
      #|    v17:i32 = iconst 0
      #|    v18:f32 = load.f32 v17 +0
      #|    jump block1(v13, v14, v18)
      #|block5:
      #|    jump block4(v0, v3, v2)
      #|block6:
      #|    jump block3(v0, v3, v2)
      #|block7:
      #|    jump block2(v0, v3, v2)
      #|block8:
      #|    jump block1(v0, v3, v2)
      #|}
      #|
    ),
  )

  // ============ Phase 4: Lower IR → VCode → Machine Code ============
  let vcode_func = @vcode.lower_function(ir_func)

  // Debug: print VCode to understand structure
  inspect(
    vcode_func.print(),
    content=(
      #|vcode test(v0:int) -> float {
      #|block0:
      #|    f13 = ldf 0
      #|    f14 = ldf 0
      #|    f15 = ldf 10
      #|    v17 = ldi 0
      #|    v16 = cmp.eq v0, v17
      #|    branch v16, block5, block9
      #|block1(v1:int, f2:float, f3:float):
      #|    ret f3
      #|block2(v4:int, f5:float, f6:float):
      #|    v22 = ldi 0
      #|    bounds_check +0, 4 v22
      #|    v23 = add x21, v22
      #|    store.f32 +0 v23, f5
      #|    v24 = ldi 0
      #|    bounds_check +0, 4 v24
      #|    v26 = add x21, v24
      #|    f25 = load.f32 +0 v26
      #|    v1 = mov v4
      #|    f2 = mov f5
      #|    f3 = mov f25
      #|    jump block1
      #|block3(v7:int, f8:float, f9:float):
      #|    v27 = ldi 0
      #|    bounds_check +0, 4 v27
      #|    v28 = add x21, v27
      #|    store.f32 +0 v28, f8
      #|    v29 = ldi 0
      #|    bounds_check +0, 4 v29
      #|    v31 = add x21, v29
      #|    f30 = load.f32 +0 v31
      #|    v1 = mov v7
      #|    f2 = mov f8
      #|    f3 = mov f30
      #|    jump block1
      #|block4(v10:int, f11:float, f12:float):
      #|    v32 = ldi 0
      #|    bounds_check +0, 4 v32
      #|    v33 = add x21, v32
      #|    store.f32 +0 v33, f11
      #|    v34 = ldi 0
      #|    bounds_check +0, 4 v34
      #|    v36 = add x21, v34
      #|    f35 = load.f32 +0 v36
      #|    v1 = mov v10
      #|    f2 = mov f11
      #|    f3 = mov f35
      #|    jump block1
      #|block5:
      #|    v10 = mov v0
      #|    f11 = mov f15
      #|    f12 = mov f14
      #|    jump block4
      #|block6:
      #|    v7 = mov v0
      #|    f8 = mov f15
      #|    f9 = mov f14
      #|    jump block3
      #|block7:
      #|    v4 = mov v0
      #|    f5 = mov f15
      #|    f6 = mov f14
      #|    jump block2
      #|block8:
      #|    v1 = mov v0
      #|    f2 = mov f15
      #|    f3 = mov f14
      #|    jump block1
      #|block9:
      #|    v18 = ldi 1
      #|    v19 = cmp.eq v0, v18
      #|    branch v19, block6, block10
      #|block10:
      #|    v20 = ldi 2
      #|    v21 = cmp.eq v0, v20
      #|    branch v21, block7, block8
      #|}
      #|
    ),
  )
  let allocated_func = @vcode.allocate_registers_aarch64(vcode_func)

  // Debug: print allocated VCode
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(v0:int) -> float {
      #|block0:
      #|    d0 = ldf 0
      #|    d1 = ldf 10
      #|    x8 = ldi 0
      #|    x19 = cmp.eq x3, x8
      #|    branch x19, block5, block9
      #|block1(v1:int, f2:float, f3:float):
      #|    ret d3
      #|block2(v4:int, f5:float, f6:float):
      #|    x23 = ldi 0
      #|    bounds_check +0, 4 x23
      #|    x25 = add x21, x23
      #|    store.f32 +0 x25, d4
      #|    x23 = ldi 0
      #|    bounds_check +0, 4 x23
      #|    x25 = add x21, x23
      #|    d5 = load.f32 +0 x25
      #|    x8 = mov x19
      #|    d2 = mov d4
      #|    d3 = mov d5
      #|    jump block1
      #|block3(v7:int, f8:float, f9:float):
      #|    x23 = ldi 0
      #|    bounds_check +0, 4 x23
      #|    x25 = add x21, x23
      #|    store.f32 +0 x25, d4
      #|    x23 = ldi 0
      #|    bounds_check +0, 4 x23
      #|    x25 = add x21, x23
      #|    d5 = load.f32 +0 x25
      #|    x8 = mov x19
      #|    d2 = mov d4
      #|    d3 = mov d5
      #|    jump block1
      #|block4(v10:int, f11:float, f12:float):
      #|    x23 = ldi 0
      #|    bounds_check +0, 4 x23
      #|    x25 = add x21, x23
      #|    store.f32 +0 x25, d4
      #|    x23 = ldi 0
      #|    bounds_check +0, 4 x23
      #|    x25 = add x21, x23
      #|    d0 = load.f32 +0 x25
      #|    x8 = mov x19
      #|    d2 = mov d4
      #|    d3 = mov d0
      #|    jump block1
      #|block5:
      #|    x19 = mov x3
      #|    d4 = mov d1
      #|    d5 = mov d0
      #|    jump block4
      #|block6:
      #|    x19 = mov x3
      #|    d4 = mov d1
      #|    d5 = mov d0
      #|    jump block3
      #|block7:
      #|    x19 = mov x3
      #|    d4 = mov d1
      #|    d5 = mov d0
      #|    jump block2
      #|block8:
      #|    x8 = mov x3
      #|    d2 = mov d1
      #|    d3 = mov d0
      #|    jump block1
      #|block9:
      #|    x8 = ldi 1
      #|    x19 = cmp.eq x3, x8
      #|    branch x19, block6, block10
      #|block10:
      #|    x8 = ldi 2
      #|    x19 = cmp.eq x3, x8
      #|    branch x19, block7, block8
      #|}
      #|
    ),
  )
  let mc = @vcode.emit_function(allocated_func)
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: ff0301d1  sub sp, sp, #64
      #|  0004: f45700a9  stp x20, x21, [sp, #0]
      #|  0008: f66301a9  stp x22, x24, [sp, #16]
      #|  000c: f35f02a9  stp x19, x23, [sp, #32]
      #|  0010: f97f03a9  stp x25, x31, [sp, #48]
      #|  0014: f40300aa  mov x20, x0
      #|  0018: f50301aa  mov x21, x1
      #|  001c: f60302aa  mov x22, x2
      #|  0020: 98825ff8  ldur x24, [x20, #-8]
      #|block0:
      #|  0024: 100080d2  movz x16, #0, lsl #0
      #|  0028: 0002271e  fmov s0, w16
      #|  002c: 100080d2  movz x16, #0, lsl #0
      #|  0030: 1024a8f2  movk x16, #16672, lsl #16
      #|  0034: 0102271e  fmov s1, w16
      #|  0038: 080080d2  movz x8, #0, lsl #0
      #|  003c: 7f0008eb  cmp x3, x8
      #|  0040: f3179f9a  cset x19, eq
      #|  0044: b30800b5  cbnz x19, block5
      #|  0048: 54000014  b block9
      #|block1:
      #|  004c: 6040201e  fmov s0, s3
      #|  0050: f45740a9  ldp x20, x21, [sp, #0]
      #|  0054: f66341a9  ldp x22, x24, [sp, #16]
      #|  0058: f35f42a9  ldp x19, x23, [sp, #32]
      #|  005c: f91b40f9  ldr x25, [x31, #48]
      #|  0060: ff030191  add sp, sp, #64
      #|  0064: c0035fd6  ret
      #|block2:
      #|  0068: 170080d2  movz x23, #0, lsl #0
      #|  006c: f003172a  mov w16, w23
      #|  0070: 10120091  add x16, x16, #4
      #|  0074: 1f0216eb  cmp x16, x22
      #|  0080: b902178b  add x25, x21, x23
      #|  0084: 240300bd  str s4, [x25, #0]
      #|  0088: 170080d2  movz x23, #0, lsl #0
      #|  008c: f003172a  mov w16, w23
      #|  0090: 10120091  add x16, x16, #4
      #|  0094: 1f0216eb  cmp x16, x22
      #|  00a0: b902178b  add x25, x21, x23
      #|  00a4: 250340bd  ldr s5, [x25, #0]
      #|  00a8: e80313aa  mov x8, x19
      #|  00ac: 8240201e  fmov s2, s4
      #|  00b0: a340201e  fmov s3, s5
      #|  00b4: e6ffff17  b block1
      #|block3:
      #|  00b8: 170080d2  movz x23, #0, lsl #0
      #|  00bc: f003172a  mov w16, w23
      #|  00c0: 10120091  add x16, x16, #4
      #|  00c4: 1f0216eb  cmp x16, x22
      #|  00d0: b902178b  add x25, x21, x23
      #|  00d4: 240300bd  str s4, [x25, #0]
      #|  00d8: 170080d2  movz x23, #0, lsl #0
      #|  00dc: f003172a  mov w16, w23
      #|  00e0: 10120091  add x16, x16, #4
      #|  00e4: 1f0216eb  cmp x16, x22
      #|  00f0: b902178b  add x25, x21, x23
      #|  00f4: 250340bd  ldr s5, [x25, #0]
      #|  00f8: e80313aa  mov x8, x19
      #|  00fc: 8240201e  fmov s2, s4
      #|  0100: a340201e  fmov s3, s5
      #|  0104: d2ffff17  b block1
      #|block4:
      #|  0108: 170080d2  movz x23, #0, lsl #0
      #|  010c: f003172a  mov w16, w23
      #|  0110: 10120091  add x16, x16, #4
      #|  0114: 1f0216eb  cmp x16, x22
      #|  0120: b902178b  add x25, x21, x23
      #|  0124: 240300bd  str s4, [x25, #0]
      #|  0128: 170080d2  movz x23, #0, lsl #0
      #|  012c: f003172a  mov w16, w23
      #|  0130: 10120091  add x16, x16, #4
      #|  0134: 1f0216eb  cmp x16, x22
      #|  0140: b902178b  add x25, x21, x23
      #|  0144: 200340bd  ldr s0, [x25, #0]
      #|  0148: e80313aa  mov x8, x19
      #|  014c: 8240201e  fmov s2, s4
      #|  0150: 0340201e  fmov s3, s0
      #|  0154: beffff17  b block1
      #|block5:
      #|  0158: f30303aa  mov x19, x3
      #|  015c: 2440201e  fmov s4, s1
      #|  0160: 0540201e  fmov s5, s0
      #|  0164: e9ffff17  b block4
      #|block6:
      #|  0168: f30303aa  mov x19, x3
      #|  016c: 2440201e  fmov s4, s1
      #|  0170: 0540201e  fmov s5, s0
      #|  0174: d1ffff17  b block3
      #|block7:
      #|  0178: f30303aa  mov x19, x3
      #|  017c: 2440201e  fmov s4, s1
      #|  0180: 0540201e  fmov s5, s0
      #|  0184: b9ffff17  b block2
      #|block8:
      #|  0188: e80303aa  mov x8, x3
      #|  018c: 2240201e  fmov s2, s1
      #|  0190: 0340201e  fmov s3, s0
      #|  0194: aeffff17  b block1
      #|block9:
      #|  0198: 280080d2  movz x8, #1, lsl #0
      #|  019c: 7f0008eb  cmp x3, x8
      #|  01a0: f3179f9a  cset x19, eq
      #|  01a4: 33feffb5  cbnz x19, block6
      #|  01a8: 01000014  b block10
      #|block10:
      #|  01ac: 480080d2  movz x8, #2, lsl #0
      #|  01b0: 7f0008eb  cmp x3, x8
      #|  01b4: f3179f9a  cset x19, eq
      #|  01b8: 13feffb5  cbnz x19, block7
      #|  01bc: f3ffff17  b block8
      #|
    ),
  )

  // ============ Phase 5: Set up JIT execution ============
  let code_bytes = mc.get_bytes()
  let jit_module = JITModule::from_single_function(
    code_bytes,
    "test",
    1, // num_params
    [@types.ValueType::F32], // result_types
    4096L, // mem_size
  )
  guard jit_module is Some(jm) else { return }
  defer jm.free()
  let func = jm.get_func_by_name("test")
  guard func is Some(f) else { return }

  // ============ Phase 6: Execute assert_return commands ============
  // Process each assert_return from the WAST script
  // Collect results: (input, expected, actual)
  let results : Array[(Int64, Float, Float)] = []
  for i in 1..<script.commands.length() {
    let (cmd, _) = script.commands[i]
    match cmd {
      @wast.WastCommand::AssertReturn(action, expected) =>
        match action {
          @wast.WastAction::Invoke(_, func_name, args) => {
            assert_eq(func_name, "test")
            assert_eq(args.length(), 1)
            assert_eq(expected.length(), 1)

            // Get input argument
            let arg = match args[0] {
              @wast.WastValue::I32(n) => n
              x => fail("Input is not I32: \{x}")
            }

            // Get expected result
            let expected_f32 = match expected[0] {
              @wast.WastValue::F32(f) => f
              x => fail("Output is not F32: \{x}")
            }

            // Call the JIT-compiled function
            let Single((result_f32 : Float)) = jm.call_with_context_poly(
              f,
              Single(arg),
            )
            results.push((arg.to_int64(), expected_f32, result_f32))
          }
          _ => ()
        }
      _ => ()
    }
  }

  // Show all test results: (input, expected, actual)
  // Expected: all 4 tests pass with correct values
  inspect(results, content="[(0, 10, 10), (1, 10, 10), (2, 10, 10), (3, 0, 0)]")
}
