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
  //   case0/1/2: jump exit with local1 (10.0)
  //   default: jump exit with local2_init (0.0)
  //   exit(local2_phi): return local2_phi
  // Note: Simplified to not use memory ops since br_table is the focus
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
      #|vcode test(v0:int, v1:int, v2:int) -> float {
      #|block0:
      #|    d0 = ldf 10
      #|    d1 = ldf 0
      #|    x8 = ldi 0
      #|    x8 = cmp32.eq x2, x8
      #|    branch x8, block1, block6
      #|block1:
      #|    jump block5
      #|block2:
      #|    jump block5
      #|block3:
      #|    jump block5
      #|block4:
      #|    d0 = mov d1
      #|    jump block5
      #|block5(f3:float):
      #|    ret d0
      #|block6:
      #|    x8 = ldi 1
      #|    x8 = cmp32.eq x2, x8
      #|    branch x8, block2, block7
      #|block7:
      #|    x8 = ldi 2
      #|    x8 = cmp32.eq x2, x8
      #|    branch x8, block3, block4
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
  inspect(ir_func.params.length(), content="3") // i32 param
  inspect(ir_func.results.length(), content="1") // f32 result
  // WASM nested blocks produce IR blocks. Memory 0 uses guard pages, so the IR
  // does not contain explicit bounds-check blocks for load/store.
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
      #|    v48:i32 = iconst 0
      #|    v49:i64 = load_mem_base mem=0 v0
      #|    v50:i64 = uextend v48
      #|    v51:i64 = iconst 0
      #|    v52:i64 = iadd v50, v51
      #|    v53:i64 = iadd v49, v52
      #|    v54:i64 = iconst 0
      #|    store_ptr.F32 v53, v10, v54
      #|    v55:i32 = iconst 0
      #|    v56:i64 = load_mem_base mem=0 v0
      #|    v57:i64 = uextend v55
      #|    v58:i64 = iconst 0
      #|    v59:i64 = iadd v57, v58
      #|    v60:i64 = iadd v56, v59
      #|    v61:i64 = iconst 0
      #|    v62:f32 = load_ptr.F32 v60, v61
      #|    jump block1(v9, v10, v62)
      #|block3(v12:i32, v13:f32, v14:f32):
      #|    v33:i32 = iconst 0
      #|    v34:i64 = load_mem_base mem=0 v0
      #|    v35:i64 = uextend v33
      #|    v36:i64 = iconst 0
      #|    v37:i64 = iadd v35, v36
      #|    v38:i64 = iadd v34, v37
      #|    v39:i64 = iconst 0
      #|    store_ptr.F32 v38, v13, v39
      #|    v40:i32 = iconst 0
      #|    v41:i64 = load_mem_base mem=0 v0
      #|    v42:i64 = uextend v40
      #|    v43:i64 = iconst 0
      #|    v44:i64 = iadd v42, v43
      #|    v45:i64 = iadd v41, v44
      #|    v46:i64 = iconst 0
      #|    v47:f32 = load_ptr.F32 v45, v46
      #|    jump block1(v12, v13, v47)
      #|block4(v15:i32, v16:f32, v17:f32):
      #|    v18:i32 = iconst 0
      #|    v19:i64 = load_mem_base mem=0 v0
      #|    v20:i64 = uextend v18
      #|    v21:i64 = iconst 0
      #|    v22:i64 = iadd v20, v21
      #|    v23:i64 = iadd v19, v22
      #|    v24:i64 = iconst 0
      #|    store_ptr.F32 v23, v16, v24
      #|    v25:i32 = iconst 0
      #|    v26:i64 = load_mem_base mem=0 v0
      #|    v27:i64 = uextend v25
      #|    v28:i64 = iconst 0
      #|    v29:i64 = iadd v27, v28
      #|    v30:i64 = iadd v26, v29
      #|    v31:i64 = iconst 0
      #|    v32:f32 = load_ptr.F32 v30, v31
      #|    jump block1(v15, v16, v32)
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
      #|    v25 = load_mem_base mem=0 v0
      #|    v26 = ldi 0
      #|    v27 = ldi 0
      #|    v28 = ldi 0
      #|    v29 = mov v25
      #|    v30 = ldi 0
      #|    store_ptr.f32 +0 v25, f7
      #|    v31 = ldi 0
      #|    v32 = load_mem_base mem=0 v0
      #|    v33 = ldi 0
      #|    v34 = ldi 0
      #|    v35 = ldi 0
      #|    v36 = mov v32
      #|    v37 = ldi 0
      #|    f38 = load_ptr.f32 +0 v32
      #|    jump block1 (v6, f7, f38)
      #|block3(v9:int, f10:float, f11:float):
      #|    v39 = ldi 0
      #|    v40 = load_mem_base mem=0 v0
      #|    v41 = ldi 0
      #|    v42 = ldi 0
      #|    v43 = ldi 0
      #|    v44 = mov v40
      #|    v45 = ldi 0
      #|    store_ptr.f32 +0 v40, f10
      #|    v46 = ldi 0
      #|    v47 = load_mem_base mem=0 v0
      #|    v48 = ldi 0
      #|    v49 = ldi 0
      #|    v50 = ldi 0
      #|    v51 = mov v47
      #|    v52 = ldi 0
      #|    f53 = load_ptr.f32 +0 v47
      #|    jump block1 (v9, f10, f53)
      #|block4(v12:int, f13:float, f14:float):
      #|    v54 = ldi 0
      #|    v55 = load_mem_base mem=0 v0
      #|    v56 = ldi 0
      #|    v57 = ldi 0
      #|    v58 = ldi 0
      #|    v59 = mov v55
      #|    v60 = ldi 0
      #|    store_ptr.f32 +0 v55, f13
      #|    v61 = ldi 0
      #|    v62 = load_mem_base mem=0 v0
      #|    v63 = ldi 0
      #|    v64 = ldi 0
      #|    v65 = ldi 0
      #|    v66 = mov v62
      #|    v67 = ldi 0
      #|    f68 = load_ptr.f32 +0 v62
      #|    jump block1 (v12, f13, f68)
      #|block5:
      #|    jump block4 (v2, f17, f16)
      #|block6:
      #|    jump block3 (v2, f17, f16)
      #|block7:
      #|    jump block2 (v2, f17, f16)
      #|block8:
      #|    jump block1 (v2, f17, f16)
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
  let allocated_func = @regalloc.allocate_registers_backtracking(vcode_func)

  // Debug: print allocated VCode
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(v0:int, v1:int, v2:int) -> float {
      #|block0:
      #|    d2 = ldf 0
      #|    d3 = ldf 10
      #|    x8 = ldi 0
      #|    x8 = cmp32.eq x2, x8
      #|    branch x8, block5, block9
      #|block1(v3:int, f4:float, f5:float):
      #|    ret d0
      #|block2(v6:int, f7:float, f8:float):
      #|    x9 = load_mem_base mem=0 x0
      #|    store_ptr.f32 +0 x9, d1
      #|    x9 = load_mem_base mem=0 x0
      #|    d0 = load_ptr.f32 +0 x9
      #|    jump block1
      #|block3(v9:int, f10:float, f11:float):
      #|    x9 = load_mem_base mem=0 x0
      #|    store_ptr.f32 +0 x9, d1
      #|    x9 = load_mem_base mem=0 x0
      #|    d0 = load_ptr.f32 +0 x9
      #|    jump block1
      #|block4(v12:int, f13:float, f14:float):
      #|    x9 = load_mem_base mem=0 x0
      #|    store_ptr.f32 +0 x9, d1
      #|    x9 = load_mem_base mem=0 x0
      #|    d0 = load_ptr.f32 +0 x9
      #|    jump block1
      #|block5:
      #|    x8 = mov x2
      #|    d1 = mov d3
      #|    jump block4
      #|block6:
      #|    x8 = mov x2
      #|    d1 = mov d3
      #|    d0 = mov d2
      #|    jump block3
      #|block7:
      #|    x8 = mov x2
      #|    d1 = mov d3
      #|    d0 = mov d2
      #|    jump block2
      #|block8:
      #|    x8 = mov x2
      #|    d1 = mov d3
      #|    d0 = mov d2
      #|    jump block1
      #|block9:
      #|    x8 = ldi 1
      #|    x8 = cmp32.eq x2, x8
      #|    branch x8, block6, block10
      #|block10:
      #|    x8 = ldi 2
      #|    x8 = cmp32.eq x2, x8
      #|    branch x8, block7, block8
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
      #|  0008: f353bfa9  stp x19, x20, [sp, #-16]!
      #|  000c: f30300aa  mov x19, x0
      #|  0010: 740240f9  ldr x20, [x19, #0]
      #|block0:
      #|  0014: 100080d2  movz x16, #0, lsl #0
      #|  0018: 0202271e  fmov s2, w16
      #|  001c: 100080d2  movz x16, #0, lsl #0
      #|  0020: 1024a8f2  movk x16, #16672, lsl #16
      #|  0024: 0302271e  fmov s3, w16
      #|  0028: 080080d2  movz x8, #0, lsl #0
      #|  002c: 5f00086b  cmp w2, w8
      #|  0030: e8179f9a  cset x8, eq
      #|  0034: c80200b5  cbnz x8, block5
      #|  0038: 24000014  b block9
      #|block1:
      #|  003c: 1840201e  fmov s24, s0
      #|  0040: 0043201e  fmov s0, s24
      #|  0044: f353c1a8  ldp x19, x20, [sp], #16
      #|  0048: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  004c: c0035fd6  ret
      #|block2:
      #|  0050: 890240f9  ldr x9, [x20, #0]
      #|  0054: 210100bd  str s1, [x9, #0]
      #|  0058: 890240f9  ldr x9, [x20, #0]
      #|  005c: 200140bd  ldr s0, [x9, #0]
      #|  0060: f7ffff17  b block1
      #|block3:
      #|  0064: 890240f9  ldr x9, [x20, #0]
      #|  0068: 210100bd  str s1, [x9, #0]
      #|  006c: 890240f9  ldr x9, [x20, #0]
      #|  0070: 200140bd  ldr s0, [x9, #0]
      #|  0074: f2ffff17  b block1
      #|block4:
      #|  0078: 890240f9  ldr x9, [x20, #0]
      #|  007c: 210100bd  str s1, [x9, #0]
      #|  0080: 890240f9  ldr x9, [x20, #0]
      #|  0084: 200140bd  ldr s0, [x9, #0]
      #|  0088: edffff17  b block1
      #|block5:
      #|  008c: e80302aa  mov x8, x2
      #|  0090: 6140201e  fmov s1, s3
      #|  0094: f9ffff17  b block4
      #|block6:
      #|  0098: e80302aa  mov x8, x2
      #|  009c: 6140201e  fmov s1, s3
      #|  00a0: 4040201e  fmov s0, s2
      #|  00a4: f0ffff17  b block3
      #|block7:
      #|  00a8: e80302aa  mov x8, x2
      #|  00ac: 6140201e  fmov s1, s3
      #|  00b0: 4040201e  fmov s0, s2
      #|  00b4: e7ffff17  b block2
      #|block8:
      #|  00b8: e80302aa  mov x8, x2
      #|  00bc: 6140201e  fmov s1, s3
      #|  00c0: 4040201e  fmov s0, s2
      #|  00c4: deffff17  b block1
      #|block9:
      #|  00c8: 280080d2  movz x8, #1, lsl #0
      #|  00cc: 5f00086b  cmp w2, w8
      #|  00d0: e8179f9a  cset x8, eq
      #|  00d4: 28feffb5  cbnz x8, block6
      #|block10:
      #|  00d8: 480080d2  movz x8, #2, lsl #0
      #|  00dc: 5f00086b  cmp w2, w8
      #|  00e0: e8179f9a  cset x8, eq
      #|  00e4: 28feffb5  cbnz x8, block7
      #|  00e8: f4ffff17  b block8
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
