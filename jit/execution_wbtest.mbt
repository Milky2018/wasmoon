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
      #|    d1 = mov d0
      #|    jump block5
      #|block2:
      #|    d1 = mov d0
      #|    jump block5
      #|block3:
      #|    d1 = mov d0
      #|    jump block5
      #|block4:
      #|    d1 = mov d1
      #|    jump block5
      #|block5(f3:float):
      #|    ret d1
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
      #|    v52:i32 = iconst 0
      #|    v53:i64 = iconst 0
      #|    v54:i64 = load_ptr.I64 v0, v53
      #|    v55:i64 = uextend v52
      #|    v56:i64 = iconst 0
      #|    v57:i64 = iadd v55, v56
      #|    v58:i64 = iadd v54, v57
      #|    v59:i64 = iconst 0
      #|    store_ptr.F32 v58, v10, v59
      #|    v60:i32 = iconst 0
      #|    v61:i64 = iconst 0
      #|    v62:i64 = load_ptr.I64 v0, v61
      #|    v63:i64 = uextend v60
      #|    v64:i64 = iconst 0
      #|    v65:i64 = iadd v63, v64
      #|    v66:i64 = iadd v62, v65
      #|    v67:i64 = iconst 0
      #|    v68:f32 = load_ptr.F32 v66, v67
      #|    jump block1(v9, v10, v68)
      #|block3(v12:i32, v13:f32, v14:f32):
      #|    v35:i32 = iconst 0
      #|    v36:i64 = iconst 0
      #|    v37:i64 = load_ptr.I64 v0, v36
      #|    v38:i64 = uextend v35
      #|    v39:i64 = iconst 0
      #|    v40:i64 = iadd v38, v39
      #|    v41:i64 = iadd v37, v40
      #|    v42:i64 = iconst 0
      #|    store_ptr.F32 v41, v13, v42
      #|    v43:i32 = iconst 0
      #|    v44:i64 = iconst 0
      #|    v45:i64 = load_ptr.I64 v0, v44
      #|    v46:i64 = uextend v43
      #|    v47:i64 = iconst 0
      #|    v48:i64 = iadd v46, v47
      #|    v49:i64 = iadd v45, v48
      #|    v50:i64 = iconst 0
      #|    v51:f32 = load_ptr.F32 v49, v50
      #|    jump block1(v12, v13, v51)
      #|block4(v15:i32, v16:f32, v17:f32):
      #|    v18:i32 = iconst 0
      #|    v19:i64 = iconst 0
      #|    v20:i64 = load_ptr.I64 v0, v19
      #|    v21:i64 = uextend v18
      #|    v22:i64 = iconst 0
      #|    v23:i64 = iadd v21, v22
      #|    v24:i64 = iadd v20, v23
      #|    v25:i64 = iconst 0
      #|    store_ptr.F32 v24, v16, v25
      #|    v26:i32 = iconst 0
      #|    v27:i64 = iconst 0
      #|    v28:i64 = load_ptr.I64 v0, v27
      #|    v29:i64 = uextend v26
      #|    v30:i64 = iconst 0
      #|    v31:i64 = iadd v29, v30
      #|    v32:i64 = iadd v28, v31
      #|    v33:i64 = iconst 0
      #|    v34:f32 = load_ptr.F32 v32, v33
      #|    jump block1(v15, v16, v34)
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
      #|    v25 = ldi 0
      #|    v26 = load_ptr.i64 +0 v0
      #|    v27 = ldi 0
      #|    v28 = ldi 0
      #|    v29 = ldi 0
      #|    v30 = mov v26
      #|    v31 = ldi 0
      #|    store_ptr.f32 +0 v26, f7
      #|    v32 = ldi 0
      #|    v33 = ldi 0
      #|    v34 = load_ptr.i64 +0 v0
      #|    v35 = ldi 0
      #|    v36 = ldi 0
      #|    v37 = ldi 0
      #|    v38 = mov v34
      #|    v39 = ldi 0
      #|    f40 = load_ptr.f32 +0 v34
      #|    v3 = mov v6
      #|    f4 = mov f7
      #|    f5 = mov f40
      #|    jump block1
      #|block3(v9:int, f10:float, f11:float):
      #|    v41 = ldi 0
      #|    v42 = ldi 0
      #|    v43 = load_ptr.i64 +0 v0
      #|    v44 = ldi 0
      #|    v45 = ldi 0
      #|    v46 = ldi 0
      #|    v47 = mov v43
      #|    v48 = ldi 0
      #|    store_ptr.f32 +0 v43, f10
      #|    v49 = ldi 0
      #|    v50 = ldi 0
      #|    v51 = load_ptr.i64 +0 v0
      #|    v52 = ldi 0
      #|    v53 = ldi 0
      #|    v54 = ldi 0
      #|    v55 = mov v51
      #|    v56 = ldi 0
      #|    f57 = load_ptr.f32 +0 v51
      #|    v3 = mov v9
      #|    f4 = mov f10
      #|    f5 = mov f57
      #|    jump block1
      #|block4(v12:int, f13:float, f14:float):
      #|    v58 = ldi 0
      #|    v59 = ldi 0
      #|    v60 = load_ptr.i64 +0 v0
      #|    v61 = ldi 0
      #|    v62 = ldi 0
      #|    v63 = ldi 0
      #|    v64 = mov v60
      #|    v65 = ldi 0
      #|    store_ptr.f32 +0 v60, f13
      #|    v66 = ldi 0
      #|    v67 = ldi 0
      #|    v68 = load_ptr.i64 +0 v0
      #|    v69 = ldi 0
      #|    v70 = ldi 0
      #|    v71 = ldi 0
      #|    v72 = mov v68
      #|    v73 = ldi 0
      #|    f74 = load_ptr.f32 +0 v68
      #|    v3 = mov v12
      #|    f4 = mov f13
      #|    f5 = mov f74
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
  let allocated_func = @regalloc.allocate_registers_backtracking(vcode_func)

  // Debug: print allocated VCode
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(v0:int, v1:int, v2:int) -> float {
      #|block0:
      #|    d5 = ldf 0
      #|    d4 = ldf 10
      #|    x8 = ldi 0
      #|    x8 = cmp32.eq x2, x8
      #|    branch x8, block5, block9
      #|block1(v3:int, f4:float, f5:float):
      #|    ret d0
      #|block2(v6:int, f7:float, f8:float):
      #|    x10 = load_ptr.i64 +0 x0
      #|    store_ptr.f32 +0 x10, d2
      #|    x10 = load_ptr.i64 +0 x0
      #|    d3 = load_ptr.f32 +0 x10
      #|    x8 = mov x9
      #|    d1 = mov d2
      #|    d0 = mov d3
      #|    jump block1
      #|block3(v9:int, f10:float, f11:float):
      #|    x10 = load_ptr.i64 +0 x0
      #|    store_ptr.f32 +0 x10, d2
      #|    x10 = load_ptr.i64 +0 x0
      #|    d3 = load_ptr.f32 +0 x10
      #|    x8 = mov x9
      #|    d1 = mov d2
      #|    d0 = mov d3
      #|    jump block1
      #|block4(v12:int, f13:float, f14:float):
      #|    x9 = load_ptr.i64 +0 x0
      #|    store_ptr.f32 +0 x9, d4
      #|    x9 = load_ptr.i64 +0 x0
      #|    d2 = load_ptr.f32 +0 x9
      #|    x8 = mov x2
      #|    d1 = mov d4
      #|    d0 = mov d2
      #|    jump block1
      #|block5:
      #|    x2 = mov x2
      #|    d4 = mov d4
      #|    d5 = mov d5
      #|    jump block4
      #|block6:
      #|    x9 = mov x2
      #|    d2 = mov d4
      #|    d3 = mov d5
      #|    jump block3
      #|block7:
      #|    x9 = mov x2
      #|    d2 = mov d4
      #|    d3 = mov d5
      #|    jump block2
      #|block8:
      #|    x8 = mov x2
      #|    d1 = mov d4
      #|    d0 = mov d5
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
      #|block0:
      #|  0000: 100080d2  movz x16, #0, lsl #0
      #|  0004: 0502271e  fmov s5, w16
      #|  0008: 100080d2  movz x16, #0, lsl #0
      #|  000c: 1024a8f2  movk x16, #16672, lsl #16
      #|  0010: 0402271e  fmov s4, w16
      #|  0014: 080080d2  movz x8, #0, lsl #0
      #|  0018: 5f00086b  cmp w2, w8
      #|  001c: e8179f9a  cset x8, eq
      #|  0020: 680300b5  cbnz x8, block5
      #|  0024: 27000014  b block9
      #|block1:
      #|  0028: c0035fd6  ret
      #|block2:
      #|  002c: 0a0040f9  ldr x10, [x0, #0]
      #|  0030: 420100bd  str s2, [x10, #0]
      #|  0034: 0a0040f9  ldr x10, [x0, #0]
      #|  0038: 430140bd  ldr s3, [x10, #0]
      #|  003c: e80309aa  mov x8, x9
      #|  0040: 4140201e  fmov s1, s2
      #|  0044: 6040201e  fmov s0, s3
      #|  0048: f8ffff17  b block1
      #|block3:
      #|  004c: 0a0040f9  ldr x10, [x0, #0]
      #|  0050: 420100bd  str s2, [x10, #0]
      #|  0054: 0a0040f9  ldr x10, [x0, #0]
      #|  0058: 430140bd  ldr s3, [x10, #0]
      #|  005c: e80309aa  mov x8, x9
      #|  0060: 4140201e  fmov s1, s2
      #|  0064: 6040201e  fmov s0, s3
      #|  0068: f0ffff17  b block1
      #|block4:
      #|  006c: 090040f9  ldr x9, [x0, #0]
      #|  0070: 240100bd  str s4, [x9, #0]
      #|  0074: 090040f9  ldr x9, [x0, #0]
      #|  0078: 220140bd  ldr s2, [x9, #0]
      #|  007c: e80302aa  mov x8, x2
      #|  0080: 8140201e  fmov s1, s4
      #|  0084: 4040201e  fmov s0, s2
      #|  0088: e8ffff17  b block1
      #|block5:
      #|  008c: f8ffff17  b block4
      #|block6:
      #|  0090: e90302aa  mov x9, x2
      #|  0094: 8240201e  fmov s2, s4
      #|  0098: a340201e  fmov s3, s5
      #|  009c: ecffff17  b block3
      #|block7:
      #|  00a0: e90302aa  mov x9, x2
      #|  00a4: 8240201e  fmov s2, s4
      #|  00a8: a340201e  fmov s3, s5
      #|  00ac: e0ffff17  b block2
      #|block8:
      #|  00b0: e80302aa  mov x8, x2
      #|  00b4: 8140201e  fmov s1, s4
      #|  00b8: a040201e  fmov s0, s5
      #|  00bc: dbffff17  b block1
      #|block9:
      #|  00c0: 280080d2  movz x8, #1, lsl #0
      #|  00c4: 5f00086b  cmp w2, w8
      #|  00c8: e8179f9a  cset x8, eq
      #|  00cc: 28feffb5  cbnz x8, block6
      #|block10:
      #|  00d0: 480080d2  movz x8, #2, lsl #0
      #|  00d4: 5f00086b  cmp w2, w8
      #|  00d8: e8179f9a  cset x8, eq
      #|  00dc: 28feffb5  cbnz x8, block7
      #|  00e0: f4ffff17  b block8
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
