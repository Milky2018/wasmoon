// End-to-End Execution Tests for JIT Compiler
// These tests compile IR functions to machine code and actually execute them

// ============ f32_br_2locals.wast Reproduction ============
// This test reproduces the exact test pattern from spec/f32_br_2locals.wast
// and verifies the JIT-compiled code returns correct values:
//   (assert_return (invoke "test" (i32.const 0)) (f32.const 10.0))
//   (assert_return (invoke "test" (i32.const 1)) (f32.const 10.0))
//   (assert_return (invoke "test" (i32.const 2)) (f32.const 10.0))
//   (assert_return (invoke "test" (i32.const 3)) (f32.const 0.0))

///|
test "execute br_table with f32 locals (f32_br_2locals.wast)" {
  // Build IR function: fn test(callee_vmctx, caller_vmctx, selector) -> f32
  // v3 ABI: X0=callee_vmctx, X1=caller_vmctx, X2+=user params
  // Structure:
  //   entry: local1 = 10.0, local2_init = 0.0, br_table(selector)
  //   case0/1/2: store local1 to mem[0], load to local2, jump exit
  //   exit(local2_phi): return local2_phi
  let builder = @ir.IRBuilder::new("test")
  // v3 ABI: first two params are vmctx (unused in IR body but needed for ABI)
  let _callee_vmctx = builder.add_param(@ir.Type::I64)
  let _caller_vmctx = builder.add_param(@ir.Type::I64)
  let selector = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::F32)

  // Create all blocks
  let entry = builder.create_block()
  let case0 = builder.create_block()
  let case1 = builder.create_block()
  let case2 = builder.create_block()
  let default_block = builder.create_block() // for selector >= 3
  let exit = builder.create_block()

  // Add block parameter for exit (the merged local2 value)
  let local2_phi = builder.add_block_param(exit, @ir.Type::F32)

  // Entry block: set up locals and br_table
  builder.switch_to_block(entry)
  let local1 = builder.fconst_f32(10.0) // local1 = 10.0
  let local2_init = builder.fconst_f32(0.0) // local2 initial = 0.0
  let addr = builder.iconst_i32(0) // memory address for store/load
  // br_table: targets = [case0, case1, case2], default = default_block
  builder.br_table(selector, [case0, case1, case2], default_block)

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

  // default: jump exit with local2_init (0.0)
  builder.switch_to_block(default_block)
  builder.jump(exit, [local2_init])

  // exit: return local2_phi
  builder.switch_to_block(exit)
  builder.return_([local2_phi])

  // ============ Compilation Pipeline ============
  // 1. Lower IR to VCode
  let vcode_func = @lower.lower_function(builder.get_function())

  // 2. Register allocation
  let allocated_func = @lower.allocate_registers_aarch64(vcode_func)

  // 3. Emit machine code
  let mc = @emit.emit_function(allocated_func)

  // Debug: print allocated VCode for the working test
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(v0:int, v1:int, v2:int) -> float {
      #|block0:
      #|    d0 = ldf 10
      #|    d1 = ldf 0
      #|    x8 = ldi 0
      #|    x9 = ldi 0
      #|    x10 = cmp32.eq x2, x9
      #|    branch x10, block1, block6
      #|block1:
      #|    x9 = extend.u32_64 x8
      #|    x10 = add #4 x9
      #|    x11 = load_ptr.i64 +8 x19
      #|    trap_if_ugt #1 x10, x11
      #|    x9 = load.i64 +0 x19
      #|    x10 = add x9, x8
      #|    store.f32 +0 x10, d0
      #|    x9 = extend.u32_64 x8
      #|    x10 = add #4 x9
      #|    x11 = load_ptr.i64 +8 x19
      #|    trap_if_ugt #1 x10, x11
      #|    x9 = load.i64 +0 x19
      #|    x10 = add x9, x8
      #|    d0 = load.f32 +0 x10
      #|    d2 = mov d0
      #|    jump block5
      #|block2:
      #|    x9 = extend.u32_64 x8
      #|    x10 = add #4 x9
      #|    x11 = load_ptr.i64 +8 x19
      #|    trap_if_ugt #1 x10, x11
      #|    x9 = load.i64 +0 x19
      #|    x10 = add x9, x8
      #|    store.f32 +0 x10, d0
      #|    x9 = extend.u32_64 x8
      #|    x10 = add #4 x9
      #|    x11 = load_ptr.i64 +8 x19
      #|    trap_if_ugt #1 x10, x11
      #|    x9 = load.i64 +0 x19
      #|    x10 = add x9, x8
      #|    d1 = load.f32 +0 x10
      #|    d2 = mov d1
      #|    jump block5
      #|block3:
      #|    x9 = extend.u32_64 x8
      #|    x10 = add #4 x9
      #|    x11 = load_ptr.i64 +8 x19
      #|    trap_if_ugt #1 x10, x11
      #|    x9 = load.i64 +0 x19
      #|    x10 = add x9, x8
      #|    store.f32 +0 x10, d0
      #|    x9 = extend.u32_64 x8
      #|    x10 = add #4 x9
      #|    x11 = load_ptr.i64 +8 x19
      #|    trap_if_ugt #1 x10, x11
      #|    x9 = load.i64 +0 x19
      #|    x10 = add x9, x8
      #|    d1 = load.f32 +0 x10
      #|    d2 = mov d1
      #|    jump block5
      #|block4:
      #|    d2 = mov d1
      #|    jump block5
      #|block5(f3:float):
      #|    ret d2
      #|block6:
      #|    x9 = ldi 1
      #|    x10 = cmp32.eq x2, x9
      #|    branch x10, block2, block7
      #|block7:
      #|    x9 = ldi 2
      #|    x10 = cmp32.eq x2, x9
      #|    branch x10, block3, block4
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
    [@types.ValueType::I32], // param_types
    [@types.ValueType::F32], // result_types
    4096L, // mem_size
  )
  guard jit_module is Some(jm) else { return }
  let func = jm.get_func_by_name("test")
  guard func is Some(f) else { return }

  // ============ Execute and Verify ============
  // test(0) should return 10.0 (store 10 to mem[0], load back)
  let Single((result0_f32 : Float)) = jm.call_with_context_poly(f, Single(0))
  assert_eq(result0_f32, 10)

  // test(1) should return 10.0
  let Single((result1_f32 : Float)) = jm.call_with_context_poly(f, Single(1))
  assert_eq(result1_f32, 10)

  // test(2) should return 10.0
  let Single((result2_f32 : Float)) = jm.call_with_context_poly(f, Single(2))
  assert_eq(result2_f32, 10)

  // test(3) - default case: jumps to default_block which passes local2_init (0.0)
  let Single((result3_f32 : Float)) = jm.call_with_context_poly(f, Single(3))
  assert_eq(result3_f32, 0)
}

// ============ End-to-End WAST Source Test ============
// This test parses the actual f32_br_2locals.wast source, translates WASM → IR,
// compiles through the full JIT pipeline, and verifies the assert_return statements.

///|
test "end-to-end: f32_br_2locals.wast from source" {
  // The actual WAST source from spec/f32_br_2locals.wast
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
  inspect(ir_func.params.length(), content="3") // i32 param
  inspect(ir_func.results.length(), content="1") // f32 result
  // WASM nested blocks produce 9 IR blocks (vs 5 in manual construction)
  inspect(ir_func.blocks.length(), content="9")

  // Debug: print the IR to understand structure
  inspect(
    ir_func.print(),
    content=(
      #|function test(v0:i64, v1:i64, v2:i32) -> f32 {
      #|block0:
      #|    v3:f32 = fconst 0
      #|    v4:f32 = fconst 0
      #|    v5:f32 = fconst 10
      #|    br_table v2, [block5, block6, block7], block8
      #|block1(v6:i32, v7:f32, v8:f32):
      #|    return v8
      #|block2(v9:i32, v10:f32, v11:f32):
      #|    v24:i32 = iconst 0
      #|    store.f32 v24, v10 +0
      #|    v25:i32 = iconst 0
      #|    v26:f32 = load.f32 v25 +0
      #|    jump block1(v9, v10, v26)
      #|block3(v12:i32, v13:f32, v14:f32):
      #|    v21:i32 = iconst 0
      #|    store.f32 v21, v13 +0
      #|    v22:i32 = iconst 0
      #|    v23:f32 = load.f32 v22 +0
      #|    jump block1(v12, v13, v23)
      #|block4(v15:i32, v16:f32, v17:f32):
      #|    v18:i32 = iconst 0
      #|    store.f32 v18, v16 +0
      #|    v19:i32 = iconst 0
      #|    v20:f32 = load.f32 v19 +0
      #|    jump block1(v15, v16, v20)
      #|block5:
      #|    jump block4(v2, v5, v4)
      #|block6:
      #|    jump block3(v2, v5, v4)
      #|block7:
      #|    jump block2(v2, v5, v4)
      #|block8:
      #|    jump block1(v2, v5, v4)
      #|}
      #|
    ),
  )

  // ============ Phase 4: Lower IR → VCode → Machine Code ============
  let vcode_func = @lower.lower_function(ir_func)

  // Debug: print VCode to understand structure
  inspect(
    vcode_func.print(),
    content=(
      #|vcode test(v0:int, v1:int, v2:int) -> float {
      #|block0:
      #|    f15 = ldf 0
      #|    f16 = ldf 0
      #|    f17 = ldf 10
      #|    v19 = ldi 0
      #|    v18 = cmp32.eq v2, v19
      #|    branch v18, block5, block9
      #|block1(v3:int, f4:float, f5:float):
      #|    ret f5
      #|block2(v6:int, f7:float, f8:float):
      #|    v24 = ldi 0
      #|    v25 = extend.u32_64 v24
      #|    v26 = add #4 v25
      #|    v27 = load_ptr.i64 +8 x19
      #|    trap_if_ugt #1 v26, v27
      #|    v28 = load.i64 +0 x19
      #|    v29 = add v28, v24
      #|    store.f32 +0 v29, f7
      #|    v30 = ldi 0
      #|    v32 = extend.u32_64 v30
      #|    v33 = add #4 v32
      #|    v34 = load_ptr.i64 +8 x19
      #|    trap_if_ugt #1 v33, v34
      #|    v35 = load.i64 +0 x19
      #|    v36 = add v35, v30
      #|    f31 = load.f32 +0 v36
      #|    v3 = mov v6
      #|    f4 = mov f7
      #|    f5 = mov f31
      #|    jump block1
      #|block3(v9:int, f10:float, f11:float):
      #|    v37 = ldi 0
      #|    v38 = extend.u32_64 v37
      #|    v39 = add #4 v38
      #|    v40 = load_ptr.i64 +8 x19
      #|    trap_if_ugt #1 v39, v40
      #|    v41 = load.i64 +0 x19
      #|    v42 = add v41, v37
      #|    store.f32 +0 v42, f10
      #|    v43 = ldi 0
      #|    v45 = extend.u32_64 v43
      #|    v46 = add #4 v45
      #|    v47 = load_ptr.i64 +8 x19
      #|    trap_if_ugt #1 v46, v47
      #|    v48 = load.i64 +0 x19
      #|    v49 = add v48, v43
      #|    f44 = load.f32 +0 v49
      #|    v3 = mov v9
      #|    f4 = mov f10
      #|    f5 = mov f44
      #|    jump block1
      #|block4(v12:int, f13:float, f14:float):
      #|    v50 = ldi 0
      #|    v51 = extend.u32_64 v50
      #|    v52 = add #4 v51
      #|    v53 = load_ptr.i64 +8 x19
      #|    trap_if_ugt #1 v52, v53
      #|    v54 = load.i64 +0 x19
      #|    v55 = add v54, v50
      #|    store.f32 +0 v55, f13
      #|    v56 = ldi 0
      #|    v58 = extend.u32_64 v56
      #|    v59 = add #4 v58
      #|    v60 = load_ptr.i64 +8 x19
      #|    trap_if_ugt #1 v59, v60
      #|    v61 = load.i64 +0 x19
      #|    v62 = add v61, v56
      #|    f57 = load.f32 +0 v62
      #|    v3 = mov v12
      #|    f4 = mov f13
      #|    f5 = mov f57
      #|    jump block1
      #|block5:
      #|    v12 = mov v2
      #|    f13 = mov f17
      #|    f14 = mov f16
      #|    jump block4
      #|block6:
      #|    v9 = mov v2
      #|    f10 = mov f17
      #|    f11 = mov f16
      #|    jump block3
      #|block7:
      #|    v6 = mov v2
      #|    f7 = mov f17
      #|    f8 = mov f16
      #|    jump block2
      #|block8:
      #|    v3 = mov v2
      #|    f4 = mov f17
      #|    f5 = mov f16
      #|    jump block1
      #|block9:
      #|    v20 = ldi 1
      #|    v21 = cmp32.eq v2, v20
      #|    branch v21, block6, block10
      #|block10:
      #|    v22 = ldi 2
      #|    v23 = cmp32.eq v2, v22
      #|    branch v23, block7, block8
      #|}
      #|
    ),
  )
  let allocated_func = @lower.allocate_registers_aarch64(vcode_func)

  // Debug: print allocated VCode
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(v0:int, v1:int, v2:int) -> float {
      #|block0:
      #|    d0 = ldf 0
      #|    d1 = ldf 10
      #|    x8 = ldi 0
      #|    x9 = cmp32.eq x2, x8
      #|    branch x9, block5, block9
      #|block1(v3:int, f4:float, f5:float):
      #|    ret d3
      #|block2(v6:int, f7:float, f8:float):
      #|    x10 = ldi 0
      #|    x11 = extend.u32_64 x10
      #|    x12 = add #4 x11
      #|    x13 = load_ptr.i64 +8 x19
      #|    trap_if_ugt #1 x12, x13
      #|    x11 = load.i64 +0 x19
      #|    x12 = add x11, x10
      #|    store.f32 +0 x12, d4
      #|    x10 = ldi 0
      #|    x11 = extend.u32_64 x10
      #|    x12 = add #4 x11
      #|    x13 = load_ptr.i64 +8 x19
      #|    trap_if_ugt #1 x12, x13
      #|    x11 = load.i64 +0 x19
      #|    x12 = add x11, x10
      #|    d5 = load.f32 +0 x12
      #|    x8 = mov x9
      #|    d2 = mov d4
      #|    d3 = mov d5
      #|    jump block1
      #|block3(v9:int, f10:float, f11:float):
      #|    x10 = ldi 0
      #|    x11 = extend.u32_64 x10
      #|    x12 = add #4 x11
      #|    x13 = load_ptr.i64 +8 x19
      #|    trap_if_ugt #1 x12, x13
      #|    x11 = load.i64 +0 x19
      #|    x12 = add x11, x10
      #|    store.f32 +0 x12, d4
      #|    x10 = ldi 0
      #|    x11 = extend.u32_64 x10
      #|    x12 = add #4 x11
      #|    x13 = load_ptr.i64 +8 x19
      #|    trap_if_ugt #1 x12, x13
      #|    x11 = load.i64 +0 x19
      #|    x12 = add x11, x10
      #|    d5 = load.f32 +0 x12
      #|    x8 = mov x9
      #|    d2 = mov d4
      #|    d3 = mov d5
      #|    jump block1
      #|block4(v12:int, f13:float, f14:float):
      #|    x10 = ldi 0
      #|    x11 = extend.u32_64 x10
      #|    x12 = add #4 x11
      #|    x13 = load_ptr.i64 +8 x19
      #|    trap_if_ugt #1 x12, x13
      #|    x11 = load.i64 +0 x19
      #|    x12 = add x11, x10
      #|    store.f32 +0 x12, d4
      #|    x10 = ldi 0
      #|    x11 = extend.u32_64 x10
      #|    x12 = add #4 x11
      #|    x13 = load_ptr.i64 +8 x19
      #|    trap_if_ugt #1 x12, x13
      #|    x11 = load.i64 +0 x19
      #|    x12 = add x11, x10
      #|    d0 = load.f32 +0 x12
      #|    x8 = mov x9
      #|    d2 = mov d4
      #|    d3 = mov d0
      #|    jump block1
      #|block5:
      #|    x9 = mov x2
      #|    d4 = mov d1
      #|    d5 = mov d0
      #|    jump block4
      #|block6:
      #|    x9 = mov x2
      #|    d4 = mov d1
      #|    d5 = mov d0
      #|    jump block3
      #|block7:
      #|    x9 = mov x2
      #|    d4 = mov d1
      #|    d5 = mov d0
      #|    jump block2
      #|block8:
      #|    x8 = mov x2
      #|    d2 = mov d1
      #|    d3 = mov d0
      #|    jump block1
      #|block9:
      #|    x8 = ldi 1
      #|    x9 = cmp32.eq x2, x8
      #|    branch x9, block6, block10
      #|block10:
      #|    x8 = ldi 2
      #|    x9 = cmp32.eq x2, x8
      #|    branch x9, block7, block8
      #|}
      #|
    ),
  )
  let mc = @emit.emit_function(allocated_func)
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: fd7bbfa9  stp x29, x30, [sp, #-16]!
      #|  0004: fd031faa  mov x29, x31
      #|  0008: f30f1ff8  str x19, [sp, #-16]!
      #|  000c: ff4300d1  sub sp, sp, #16
      #|  0010: f30300aa  mov x19, x0
      #|block0:
      #|  0014: 100080d2  movz x16, #0, lsl #0
      #|  0018: 0002271e  fmov s0, w16
      #|  001c: 100080d2  movz x16, #0, lsl #0
      #|  0020: 1024a8f2  movk x16, #16672, lsl #16
      #|  0024: 0102271e  fmov s1, w16
      #|  0028: 080080d2  movz x8, #0, lsl #0
      #|  002c: 5f00086b  cmp w2, w8
      #|  0030: e9179f9a  cset x9, eq
      #|  0034: e90900b5  cbnz x9, block5
      #|  0038: 5e000014  b block9
      #|block1:
      #|  003c: 6040201e  fmov s0, s3
      #|  0040: ff430091  add sp, sp, #16
      #|  0044: f30741f8  ldr x19, [sp], #16
      #|  0048: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  004c: c0035fd6  ret
      #|block2:
      #|  0050: 0a0080d2  movz x10, #0, lsl #0
      #|  0054: eb030a2a  mov w11, w10
      #|  0058: 6c110091  add x12, x11, #4
      #|  005c: 6d0640f9  ldr x13, [x19, #8]
      #|  0060: 9f010deb  cmp x12, x13
      #|  0064: 49000054  b.ls .+8
      #|  0068: 200020d4  brk #1
      #|  006c: 6b0240f9  ldr x11, [x19, #0]
      #|  0070: 6c010a8b  add x12, x11, x10
      #|  0074: 840100bd  str s4, [x12, #0]
      #|  0078: 0a0080d2  movz x10, #0, lsl #0
      #|  007c: eb030a2a  mov w11, w10
      #|  0080: 6c110091  add x12, x11, #4
      #|  0084: 6d0640f9  ldr x13, [x19, #8]
      #|  0088: 9f010deb  cmp x12, x13
      #|  008c: 49000054  b.ls .+8
      #|  0090: 200020d4  brk #1
      #|  0094: 6b0240f9  ldr x11, [x19, #0]
      #|  0098: 6c010a8b  add x12, x11, x10
      #|  009c: 850140bd  ldr s5, [x12, #0]
      #|  00a0: e80309aa  mov x8, x9
      #|  00a4: 8240201e  fmov s2, s4
      #|  00a8: a340201e  fmov s3, s5
      #|  00ac: e4ffff17  b block1
      #|block3:
      #|  00b0: 0a0080d2  movz x10, #0, lsl #0
      #|  00b4: eb030a2a  mov w11, w10
      #|  00b8: 6c110091  add x12, x11, #4
      #|  00bc: 6d0640f9  ldr x13, [x19, #8]
      #|  00c0: 9f010deb  cmp x12, x13
      #|  00c4: 49000054  b.ls .+8
      #|  00c8: 200020d4  brk #1
      #|  00cc: 6b0240f9  ldr x11, [x19, #0]
      #|  00d0: 6c010a8b  add x12, x11, x10
      #|  00d4: 840100bd  str s4, [x12, #0]
      #|  00d8: 0a0080d2  movz x10, #0, lsl #0
      #|  00dc: eb030a2a  mov w11, w10
      #|  00e0: 6c110091  add x12, x11, #4
      #|  00e4: 6d0640f9  ldr x13, [x19, #8]
      #|  00e8: 9f010deb  cmp x12, x13
      #|  00ec: 49000054  b.ls .+8
      #|  00f0: 200020d4  brk #1
      #|  00f4: 6b0240f9  ldr x11, [x19, #0]
      #|  00f8: 6c010a8b  add x12, x11, x10
      #|  00fc: 850140bd  ldr s5, [x12, #0]
      #|  0100: e80309aa  mov x8, x9
      #|  0104: 8240201e  fmov s2, s4
      #|  0108: a340201e  fmov s3, s5
      #|  010c: ccffff17  b block1
      #|block4:
      #|  0110: 0a0080d2  movz x10, #0, lsl #0
      #|  0114: eb030a2a  mov w11, w10
      #|  0118: 6c110091  add x12, x11, #4
      #|  011c: 6d0640f9  ldr x13, [x19, #8]
      #|  0120: 9f010deb  cmp x12, x13
      #|  0124: 49000054  b.ls .+8
      #|  0128: 200020d4  brk #1
      #|  012c: 6b0240f9  ldr x11, [x19, #0]
      #|  0130: 6c010a8b  add x12, x11, x10
      #|  0134: 840100bd  str s4, [x12, #0]
      #|  0138: 0a0080d2  movz x10, #0, lsl #0
      #|  013c: eb030a2a  mov w11, w10
      #|  0140: 6c110091  add x12, x11, #4
      #|  0144: 6d0640f9  ldr x13, [x19, #8]
      #|  0148: 9f010deb  cmp x12, x13
      #|  014c: 49000054  b.ls .+8
      #|  0150: 200020d4  brk #1
      #|  0154: 6b0240f9  ldr x11, [x19, #0]
      #|  0158: 6c010a8b  add x12, x11, x10
      #|  015c: 800140bd  ldr s0, [x12, #0]
      #|  0160: e80309aa  mov x8, x9
      #|  0164: 8240201e  fmov s2, s4
      #|  0168: 0340201e  fmov s3, s0
      #|  016c: b4ffff17  b block1
      #|block5:
      #|  0170: e90302aa  mov x9, x2
      #|  0174: 2440201e  fmov s4, s1
      #|  0178: 0540201e  fmov s5, s0
      #|  017c: e5ffff17  b block4
      #|block6:
      #|  0180: e90302aa  mov x9, x2
      #|  0184: 2440201e  fmov s4, s1
      #|  0188: 0540201e  fmov s5, s0
      #|  018c: c9ffff17  b block3
      #|block7:
      #|  0190: e90302aa  mov x9, x2
      #|  0194: 2440201e  fmov s4, s1
      #|  0198: 0540201e  fmov s5, s0
      #|  019c: adffff17  b block2
      #|block8:
      #|  01a0: e80302aa  mov x8, x2
      #|  01a4: 2240201e  fmov s2, s1
      #|  01a8: 0340201e  fmov s3, s0
      #|  01ac: a4ffff17  b block1
      #|block9:
      #|  01b0: 280080d2  movz x8, #1, lsl #0
      #|  01b4: 5f00086b  cmp w2, w8
      #|  01b8: e9179f9a  cset x9, eq
      #|  01bc: 29feffb5  cbnz x9, block6
      #|  01c0: 01000014  b block10
      #|block10:
      #|  01c4: 480080d2  movz x8, #2, lsl #0
      #|  01c8: 5f00086b  cmp w2, w8
      #|  01cc: e9179f9a  cset x9, eq
      #|  01d0: 09feffb5  cbnz x9, block7
      #|  01d4: f3ffff17  b block8
      #|
    ),
  )

  // ============ Phase 5: Set up JIT execution ============
  let code_bytes = mc.get_bytes()
  let jit_module = JITModule::from_single_function(
    code_bytes,
    "test",
    [@types.ValueType::I32], // param_types
    [@types.ValueType::F32], // result_types
    4096L, // mem_size
  )
  guard jit_module is Some(jm) else { return }
  let func = jm.get_func_by_name("test")
  guard func is Some(f) else { return }

  // ============ Phase 6: Execute assert_return commands ============
  // Process each assert_return from the WAST script
  // Collect results: (input, expected, actual)
  let results : Array[(Int64, Float, Float)] = []
  for i in 1..<script.commands.length() {
    let (cmd, _) = script.commands[i]
    if cmd is @wast.WastCommand::AssertReturn(action, expected) &&
      action is @wast.WastAction::Invoke(_, func_name, args) {
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
  }

  // Show all test results: (input, expected, actual)
  // Expected: all 4 tests pass with correct values
  // Case 3 (default) returns 0.0 because local2 is never set when jumping directly to end
  inspect(results, content="[(0, 10, 10), (1, 10, 10), (2, 10, 10), (3, 0, 0)]")
  assert_eq(results[0], (0, 10, 10))
  assert_eq(results[1], (1, 10, 10))
  assert_eq(results[2], (2, 10, 10))
  assert_eq(results[3], (3, 0, 0))
}
