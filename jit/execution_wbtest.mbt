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
test "exec code allocation scales beyond 1024 blocks" {
  let blocks : Array[ExecCode] = []
  for _ in 0..<1100 {
    match ExecCode::new([0x00]) {
      Some(ec) => blocks.push(ec)
      None => fail("ExecCode allocation failed before 1100 blocks")
    }
  }
  let mut non_zero_ptrs = 0
  for block in blocks {
    if block.ptr() != 0L {
      non_zero_ptrs = non_zero_ptrs + 1
    }
  }
  inspect(blocks.length(), content="1100")
  inspect(non_zero_ptrs, content="1100")
}

///|
test "collect_gc_root_args filters non-gc values" {
  let args = [2L, 3L, 8L, 10L, 12L]
  let param_types = [
    @types.RefStruct(0),
    @types.RefStruct(1),
    @types.I64,
    @types.RefArray(2),
    @types.FuncRef,
  ]
  let roots = collect_gc_root_args(args, param_types)
  inspect(roots.length(), content="2")
  inspect(roots[0], content="2")
  inspect(roots[1], content="10")
}

///|
test "trap report: structured data available after jit trap" {
  let builder = @ir.IRBuilder::new("trap_div")
  let _vmctx = builder.add_param(@ir.Type::I64)
  let rhs = builder.add_param(@ir.Type::I32)
  builder.add_result(@ir.Type::I32)

  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let lhs = builder.iconst_i32(42)
  let result = builder.sdiv(lhs, rhs)
  builder.return_([result])

  let vcode_func = @lower.lower_function(builder.get_function())
  let allocated_func = @regalloc.allocate_registers_backtracking(vcode_func)
  let mc = @emit.emit_function(allocated_func)

  let jit_module = JITModule::from_single_function(
    mc.get_bytes(),
    "trap_div",
    [@types.ValueType::I32],
    [@types.ValueType::I32],
    4096L,
  )
  guard jit_module is Some(jm) else {
    fail("failed to create jit module")
    return
  }
  guard jm.get_func_by_name("trap_div") is Some(func) else {
    fail("function not found")
    return
  }

  let mut trapped = false
  (jm.call_with_context(func, [0L]) |> ignore) catch {
    JITTrap(msg) => {
      trapped = true
      inspect(msg.length() > 0, content="true")
    }
    JITExit(code) => fail("unexpected JITExit(\{code})")
  }
  inspect(trapped, content="true")

  let report = jm.get_last_trap_report()
  inspect(report is Some(_), content="true")
  if report is Some(r) {
    inspect(r.trap_kind == "integer divide by zero", content="true")
    inspect(r.wasm_frames.length() > 0, content="true")
    inspect(r.wasm_frames[0].func_name == "trap_div", content="true")
    inspect(r.wasm_func_idx is Some(0), content="true")
  }
}

///|
test "execute br_table with f32 locals (f32_br_2locals.wast)" {
  if @isa.ISA::current() is @isa.AMD64 {
    return
  }
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
      #|    br_cmp_imm.eq x1, #0, block1, block6
      #|block1:
      #|    d2 = ldf 10
      #|    jump block5
      #|block2:
      #|    d2 = ldf 10
      #|    jump block5
      #|block3:
      #|    d2 = ldf 10
      #|    jump block5
      #|block4:
      #|    d2 = ldf 0
      #|    jump block5
      #|block5(f2:float):
      #|    ret d2
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
  if @isa.ISA::current() is @isa.AMD64 {
    return
  }
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
      #|    v3:f32 = fconst 10
      #|    br_table v1, [block6, block7, block8], block5
      #|block1(v4:i32, v5:f32, v6:f32):
      #|    return v6
      #|block2(v7:i32, v8:f32, v9:f32):
      #|    v46:i32 = iconst 0
      #|    v47:i64 = load_mem_base mem=0 v0
      #|    v48:i64 = uextend v46
      #|    v49:i64 = iconst 0
      #|    v50:i64 = iadd v48, v49
      #|    v51:i64 = iadd v47, v50
      #|    v52:i64 = iconst 0
      #|    store_ptr.F32 v51, v8, v52
      #|    v53:i32 = iconst 0
      #|    v54:i64 = load_mem_base mem=0 v0
      #|    v55:i64 = uextend v53
      #|    v56:i64 = iconst 0
      #|    v57:i64 = iadd v55, v56
      #|    v58:i64 = iadd v54, v57
      #|    v59:i64 = iconst 0
      #|    v60:f32 = load_ptr.F32 v58, v59
      #|    jump block1(v7, v8, v60)
      #|block3(v10:i32, v11:f32, v12:f32):
      #|    v31:i32 = iconst 0
      #|    v32:i64 = load_mem_base mem=0 v0
      #|    v33:i64 = uextend v31
      #|    v34:i64 = iconst 0
      #|    v35:i64 = iadd v33, v34
      #|    v36:i64 = iadd v32, v35
      #|    v37:i64 = iconst 0
      #|    store_ptr.F32 v36, v11, v37
      #|    v38:i32 = iconst 0
      #|    v39:i64 = load_mem_base mem=0 v0
      #|    v40:i64 = uextend v38
      #|    v41:i64 = iconst 0
      #|    v42:i64 = iadd v40, v41
      #|    v43:i64 = iadd v39, v42
      #|    v44:i64 = iconst 0
      #|    v45:f32 = load_ptr.F32 v43, v44
      #|    jump block1(v10, v11, v45)
      #|block4(v13:i32, v14:f32, v15:f32):
      #|    v16:i32 = iconst 0
      #|    v17:i64 = load_mem_base mem=0 v0
      #|    v18:i64 = uextend v16
      #|    v19:i64 = iconst 0
      #|    v20:i64 = iadd v18, v19
      #|    v21:i64 = iadd v17, v20
      #|    v22:i64 = iconst 0
      #|    store_ptr.F32 v21, v14, v22
      #|    v23:i32 = iconst 0
      #|    v24:i64 = load_mem_base mem=0 v0
      #|    v25:i64 = uextend v23
      #|    v26:i64 = iconst 0
      #|    v27:i64 = iadd v25, v26
      #|    v28:i64 = iadd v24, v27
      #|    v29:i64 = iconst 0
      #|    v30:f32 = load_ptr.F32 v28, v29
      #|    jump block1(v13, v14, v30)
      #|block5:
      #|    jump block1(v1, v3, v2)
      #|block6:
      #|    jump block4(v1, v3, v2)
      #|block7:
      #|    jump block3(v1, v3, v2)
      #|block8:
      #|    jump block2(v1, v3, v2)
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
      #|    f14 = ldf 0
      #|    f15 = ldf 10
      #|    br_cmp_imm.eq v1, #0, block6, block9
      #|block1(v2:int, f3:float, f4:float):
      #|    ret f4
      #|block2(v5:int, f6:float, f7:float):
      #|    v23 = load_mem_base mem=0 x21
      #|    store_ptr.f32 +0 v23, f6
      #|    f35 = load_ptr.f32 +0 v23
      #|    jump block1 (v5, f6, f35)
      #|block3(v8:int, f9:float, f10:float):
      #|    v37 = load_mem_base mem=0 x21
      #|    store_ptr.f32 +0 v37, f9
      #|    f49 = load_ptr.f32 +0 v37
      #|    jump block1 (v8, f9, f49)
      #|block4(v11:int, f12:float, f13:float):
      #|    v51 = load_mem_base mem=0 x21
      #|    store_ptr.f32 +0 v51, f12
      #|    f63 = load_ptr.f32 +0 v51
      #|    jump block1 (v11, f12, f63)
      #|block5:
      #|    jump block1 (v1, f15, f14)
      #|block6:
      #|    jump block4 (v1, f15, f14)
      #|block7:
      #|    jump block3 (v1, f15, f14)
      #|block8:
      #|    jump block2 (v1, f15, f14)
      #|block9:
      #|    br_cmp_imm.eq v1, #1, block7, block10
      #|block10:
      #|    br_cmp_imm.eq v1, #2, block8, block5
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
      #|    br_cmp_imm.eq x1, #0, block6, block9
      #|block1(v2:int, f3:float, f4:float):
      #|    ret d3
      #|block2(v5:int, f6:float, f7:float):
      #|    x7 = load_mem_base mem=0 x21
      #|    store_ptr.f32 +0 x7, d2
      #|    d3 = load_ptr.f32 +0 x7
      #|    jump block1
      #|block3(v8:int, f9:float, f10:float):
      #|    x8 = load_mem_base mem=0 x21
      #|    store_ptr.f32 +0 x8, d2
      #|    d3 = load_ptr.f32 +0 x8
      #|    jump block1
      #|block4(v11:int, f12:float, f13:float):
      #|    x9 = load_mem_base mem=0 x21
      #|    store_ptr.f32 +0 x9, d2
      #|    d3 = load_ptr.f32 +0 x9
      #|    jump block1
      #|block5:
      #|    d2 = ldf 10
      #|    d3 = ldf 0
      #|    jump block1
      #|block6:
      #|    d2 = ldf 10
      #|    d6 = ldf 0
      #|    jump block4
      #|block7:
      #|    d2 = ldf 10
      #|    d5 = ldf 0
      #|    jump block3
      #|block8:
      #|    d2 = ldf 10
      #|    d4 = ldf 0
      #|    jump block2
      #|block9:
      #|    br_cmp_imm.eq x1, #1, block7, block10
      #|block10:
      #|    br_cmp_imm.eq x1, #2, block8, block5
      #|}
      #|
    ),
  )
  let mc = @emit.emit_function(allocated_func)
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: f50300aa  mov x21, x0
      #|block0:
      #|  0004: a1030034  cbz w1, block6
      #|block9:
      #|  0008: 3f040071  cmp w1, #1
      #|  000c: 40020054  b.eq block7
      #|block10:
      #|  0010: 3f080071  cmp w1, #2
      #|  0014: e0000054  b.eq block8
      #|block5:
      #|  0018: 100080d2  movz x16, #0, lsl #0
      #|  001c: 1024a8f2  movk x16, #16672, lsl #16
      #|  0020: 0202271e  fmov s2, w16
      #|  0024: 100080d2  movz x16, #0, lsl #0
      #|  0028: 0302271e  fmov s3, w16
      #|  002c: 1b000014  b block1
      #|block8:
      #|  0030: 100080d2  movz x16, #0, lsl #0
      #|  0034: 1024a8f2  movk x16, #16672, lsl #16
      #|  0038: 0202271e  fmov s2, w16
      #|  003c: 100080d2  movz x16, #0, lsl #0
      #|  0040: 0402271e  fmov s4, w16
      #|block2:
      #|  0044: a70640f9  ldr x7, [x21, #8]
      #|  0048: e20000bd  str s2, [x7, #0]
      #|  004c: e30040bd  ldr s3, [x7, #0]
      #|  0050: 12000014  b block1
      #|block7:
      #|  0054: 100080d2  movz x16, #0, lsl #0
      #|  0058: 1024a8f2  movk x16, #16672, lsl #16
      #|  005c: 0202271e  fmov s2, w16
      #|  0060: 100080d2  movz x16, #0, lsl #0
      #|  0064: 0502271e  fmov s5, w16
      #|block3:
      #|  0068: a80640f9  ldr x8, [x21, #8]
      #|  006c: 020100bd  str s2, [x8, #0]
      #|  0070: 030140bd  ldr s3, [x8, #0]
      #|  0074: 09000014  b block1
      #|block6:
      #|  0078: 100080d2  movz x16, #0, lsl #0
      #|  007c: 1024a8f2  movk x16, #16672, lsl #16
      #|  0080: 0202271e  fmov s2, w16
      #|  0084: 100080d2  movz x16, #0, lsl #0
      #|  0088: 0602271e  fmov s6, w16
      #|block4:
      #|  008c: a90640f9  ldr x9, [x21, #8]
      #|  0090: 220100bd  str s2, [x9, #0]
      #|  0094: 230140bd  ldr s3, [x9, #0]
      #|block1:
      #|  0098: 601ca34e  orr v0.16b, v3.16b, v3.16b
      #|  009c: c0035fd6  ret
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
