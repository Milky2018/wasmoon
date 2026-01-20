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
  // Build IR function: fn test(vmctx, selector) -> f32
  // ABI: X0=vmctx, X1+=user params
  let builder = @ir.IRBuilder::new("test")
  let _vmctx = builder.add_param(@ir.Type::I64)
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
  // br_table: targets = [case0, case1, case2], default = default_block
  builder.br_table(selector, [case0, case1, case2], default_block)

  // case0: jump exit with local1 (10.0)
  builder.switch_to_block(case0)
  builder.jump(exit, [local1])

  // case1: jump exit with local1 (10.0)
  builder.switch_to_block(case1)
  builder.jump(exit, [local1])

  // case2: jump exit with local1 (10.0)
  builder.switch_to_block(case2)
  builder.jump(exit, [local1])

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
  let allocated_func = @regalloc.allocate_registers_backtracking(vcode_func)

  // 3. Emit machine code
  let mc = @emit.emit_function(allocated_func)

  // Debug: print allocated VCode for the working test
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(v0:int, v1:int) -> float {
      #|block0:
      #|    d0 = ldf 10
      #|    d1 = ldf 0
      #|    br_cmp_imm.eq x1, #0, block1, block6
      #|block1:
      #|    jump block5
      #|block2:
      #|    jump block5
      #|block3:
      #|    jump block5
      #|block4:
      #|    d0 = mov d1
      #|    jump block5
      #|block5(f2:float):
      #|    ret d0
      #|block6:
      #|    br_cmp_imm.eq x1, #1, block2, block7
      #|block7:
      #|    br_cmp_imm.eq x1, #2, block3, block4
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
  let func_type = wasm_module.get_func_type(func_type_idx)

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
    @types.extract_func_types(wasm_module.types),
    wasm_module.funcs.mapi(fn(i, _) { wasm_module.funcs[i] }),
    0, // num_imports
    [], // import_func_type_indices
  )
  let ir_func = translator.translate(func_code.body)

  // ============ Phase 3: Verify IR structure ============
  // The function should have params, results, and multiple blocks
  inspect(ir_func.params.length(), content="2") // i32 param
  inspect(ir_func.results.length(), content="1") // f32 result
  // WASM nested blocks produce IR blocks. Memory 0 uses guard pages, so the IR
  // does not contain explicit bounds-check blocks for load/store.
  inspect(ir_func.blocks.length(), content="9")

  // Debug: print the IR to understand structure
  inspect(
    ir_func.print(),
    content=(
      #|function test(v0:i64, v1:i32) -> f32 {
      #|block0:
      #|    v2:f32 = fconst 0
      #|    v3:f32 = fconst 0
      #|    v4:f32 = fconst 10
      #|    br_table v1, [block5, block6, block7], block8
      #|block1(v5:i32, v6:f32, v7:f32):
      #|    return v7
      #|block2(v8:i32, v9:f32, v10:f32):
      #|    v47:i32 = iconst 0
      #|    v48:i64 = load_mem_base mem=0 v0
      #|    v49:i64 = uextend v47
      #|    v50:i64 = iconst 0
      #|    v51:i64 = iadd v49, v50
      #|    v52:i64 = iadd v48, v51
      #|    v53:i64 = iconst 0
      #|    store_ptr.F32 v52, v9, v53
      #|    v54:i32 = iconst 0
      #|    v55:i64 = load_mem_base mem=0 v0
      #|    v56:i64 = uextend v54
      #|    v57:i64 = iconst 0
      #|    v58:i64 = iadd v56, v57
      #|    v59:i64 = iadd v55, v58
      #|    v60:i64 = iconst 0
      #|    v61:f32 = load_ptr.F32 v59, v60
      #|    jump block1(v8, v9, v61)
      #|block3(v11:i32, v12:f32, v13:f32):
      #|    v32:i32 = iconst 0
      #|    v33:i64 = load_mem_base mem=0 v0
      #|    v34:i64 = uextend v32
      #|    v35:i64 = iconst 0
      #|    v36:i64 = iadd v34, v35
      #|    v37:i64 = iadd v33, v36
      #|    v38:i64 = iconst 0
      #|    store_ptr.F32 v37, v12, v38
      #|    v39:i32 = iconst 0
      #|    v40:i64 = load_mem_base mem=0 v0
      #|    v41:i64 = uextend v39
      #|    v42:i64 = iconst 0
      #|    v43:i64 = iadd v41, v42
      #|    v44:i64 = iadd v40, v43
      #|    v45:i64 = iconst 0
      #|    v46:f32 = load_ptr.F32 v44, v45
      #|    jump block1(v11, v12, v46)
      #|block4(v14:i32, v15:f32, v16:f32):
      #|    v17:i32 = iconst 0
      #|    v18:i64 = load_mem_base mem=0 v0
      #|    v19:i64 = uextend v17
      #|    v20:i64 = iconst 0
      #|    v21:i64 = iadd v19, v20
      #|    v22:i64 = iadd v18, v21
      #|    v23:i64 = iconst 0
      #|    store_ptr.F32 v22, v15, v23
      #|    v24:i32 = iconst 0
      #|    v25:i64 = load_mem_base mem=0 v0
      #|    v26:i64 = uextend v24
      #|    v27:i64 = iconst 0
      #|    v28:i64 = iadd v26, v27
      #|    v29:i64 = iadd v25, v28
      #|    v30:i64 = iconst 0
      #|    v31:f32 = load_ptr.F32 v29, v30
      #|    jump block1(v14, v15, v31)
      #|block5:
      #|    jump block4(v1, v4, v3)
      #|block6:
      #|    jump block3(v1, v4, v3)
      #|block7:
      #|    jump block2(v1, v4, v3)
      #|block8:
      #|    jump block1(v1, v4, v3)
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
      #|vcode test(v0:int, v1:int) -> float {
      #|block0:
      #|    f15 = ldf 0
      #|    f16 = ldf 10
      #|    br_cmp_imm.eq v1, #0, block5, block9
      #|block1(v2:int, f3:float, f4:float):
      #|    ret f4
      #|block2(v5:int, f6:float, f7:float):
      #|    v24 = load_mem_base mem=0 x21
      #|    store_ptr.f32 +0 v24, f6
      #|    f37 = load_ptr.f32 +0 v24
      #|    jump block1 (v5, f6, f37)
      #|block3(v8:int, f9:float, f10:float):
      #|    v39 = load_mem_base mem=0 x21
      #|    store_ptr.f32 +0 v39, f9
      #|    f52 = load_ptr.f32 +0 v39
      #|    jump block1 (v8, f9, f52)
      #|block4(v11:int, f12:float, f13:float):
      #|    v54 = load_mem_base mem=0 x21
      #|    store_ptr.f32 +0 v54, f12
      #|    f67 = load_ptr.f32 +0 v54
      #|    jump block1 (v11, f12, f67)
      #|block5:
      #|    jump block4 (v1, f16, f15)
      #|block6:
      #|    jump block3 (v1, f16, f15)
      #|block7:
      #|    jump block2 (v1, f16, f15)
      #|block8:
      #|    jump block1 (v1, f16, f15)
      #|block9:
      #|    br_cmp_imm.eq v1, #1, block6, block10
      #|block10:
      #|    br_cmp_imm.eq v1, #2, block7, block8
      #|}
      #|
    ),
  )
  let allocated_func = @regalloc.allocate_registers_backtracking(vcode_func)

  // Debug: print allocated VCode
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(v0:int, v1:int) -> float {
      #|block0:
      #|    d0 = ldf 0
      #|    d1 = ldf 10
      #|    br_cmp_imm.eq x1, #0, block5, block9
      #|block1(v2:int, f3:float, f4:float):
      #|    ret d0
      #|block2(v5:int, f6:float, f7:float):
      #|    x0 = load_mem_base mem=0 x21
      #|    store_ptr.f32 +0 x0, d1
      #|    d0 = load_ptr.f32 +0 x0
      #|    jump block1
      #|block3(v8:int, f9:float, f10:float):
      #|    x0 = load_mem_base mem=0 x21
      #|    store_ptr.f32 +0 x0, d1
      #|    d0 = load_ptr.f32 +0 x0
      #|    jump block1
      #|block4(v11:int, f12:float, f13:float):
      #|    x0 = load_mem_base mem=0 x21
      #|    store_ptr.f32 +0 x0, d1
      #|    d0 = load_ptr.f32 +0 x0
      #|    jump block1
      #|block5:
      #|    jump block4
      #|block6:
      #|    jump block3
      #|block7:
      #|    jump block2
      #|block8:
      #|    jump block1
      #|block9:
      #|    br_cmp_imm.eq x1, #1, block6, block10
      #|block10:
      #|    br_cmp_imm.eq x1, #2, block7, block8
      #|}
      #|
    ),
  )
  let mc = @emit.emit_function(allocated_func)
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: fd7bbfa9  stp x29, x30, [sp, #-16]!
      #|  0004: fd030091  add x29, sp, #0
      #|  0008: f40f1ff8  str x20, [sp, #-16]!
      #|  000c: f50300aa  mov x21, x0
      #|  0010: b40240f9  ldr x20, [x21, #0]
      #|block0:
      #|  0014: 100080d2  movz x16, #0, lsl #0
      #|  0018: 0002271e  fmov s0, w16
      #|  001c: 100080d2  movz x16, #0, lsl #0
      #|  0020: 1024a8f2  movk x16, #16672, lsl #16
      #|  0024: 0102271e  fmov s1, w16
      #|  0028: 3f000071  cmp w1, #0
      #|  002c: 20020054  b.eq block5
      #|  0030: 14000014  b block9
      #|block1:
      #|  0034: f40741f8  ldr x20, [sp], #16
      #|  0038: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  003c: c0035fd6  ret
      #|block2:
      #|  0040: 800240f9  ldr x0, [x20, #0]
      #|  0044: 010000bd  str s1, [x0, #0]
      #|  0048: 000040bd  ldr s0, [x0, #0]
      #|  004c: faffff17  b block1
      #|block3:
      #|  0050: 800240f9  ldr x0, [x20, #0]
      #|  0054: 010000bd  str s1, [x0, #0]
      #|  0058: 000040bd  ldr s0, [x0, #0]
      #|  005c: f6ffff17  b block1
      #|block4:
      #|  0060: 800240f9  ldr x0, [x20, #0]
      #|  0064: 010000bd  str s1, [x0, #0]
      #|  0068: 000040bd  ldr s0, [x0, #0]
      #|  006c: f2ffff17  b block1
      #|block5:
      #|  0070: fcffff17  b block4
      #|block6:
      #|  0074: f7ffff17  b block3
      #|block7:
      #|  0078: f2ffff17  b block2
      #|block8:
      #|  007c: eeffff17  b block1
      #|block9:
      #|  0080: 3f040071  cmp w1, #1
      #|  0084: 80ffff54  b.eq block6
      #|block10:
      #|  0088: 3f080071  cmp w1, #2
      #|  008c: 60ffff54  b.eq block7
      #|  0090: fbffff17  b block8
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
