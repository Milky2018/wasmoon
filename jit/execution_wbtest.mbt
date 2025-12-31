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
  let allocated_func = @regalloc.allocate_registers_aarch64(vcode_func)

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
      #|    x9 = cmp32.eq x2, x8
      #|    branch x9, block1, block6
      #|block1:
      #|    d2 = mov d0
      #|    jump block5
      #|block2:
      #|    d2 = mov d0
      #|    jump block5
      #|block3:
      #|    d2 = mov d0
      #|    jump block5
      #|block4:
      #|    d2 = mov d1
      #|    jump block5
      #|block5(f3:float):
      #|    ret d2
      #|block6:
      #|    x8 = ldi 1
      #|    x9 = cmp32.eq x2, x8
      #|    branch x9, block2, block7
      #|block7:
      #|    x8 = ldi 2
      #|    x9 = cmp32.eq x2, x8
      #|    branch x9, block3, block4
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
  // WASM nested blocks produce 9 IR blocks (vs 5 in manual construction)
  inspect(ir_func.blocks.length(), content="21")

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
      #|    v72:i32 = iconst 0
      #|    v73:i64 = iconst 0
      #|    v74:i64 = load_ptr.I64 v0, v73
      #|    v75:i64 = iconst 8
      #|    v76:i64 = load_ptr.I64 v0, v75
      #|    v77:i64 = uextend v72
      #|    v78:i64 = iconst 0
      #|    v79:i64 = iadd v77, v78
      #|    v80:i64 = iconst 4
      #|    v81:i64 = iadd v79, v80
      #|    v82:i32 = icmp.ule v81, v76
      #|    brnz v82, block18, block17
      #|block3(v12:i32, v13:f32, v14:f32):
      #|    v45:i32 = iconst 0
      #|    v46:i64 = iconst 0
      #|    v47:i64 = load_ptr.I64 v0, v46
      #|    v48:i64 = iconst 8
      #|    v49:i64 = load_ptr.I64 v0, v48
      #|    v50:i64 = uextend v45
      #|    v51:i64 = iconst 0
      #|    v52:i64 = iadd v50, v51
      #|    v53:i64 = iconst 4
      #|    v54:i64 = iadd v52, v53
      #|    v55:i32 = icmp.ule v54, v49
      #|    brnz v55, block14, block13
      #|block4(v15:i32, v16:f32, v17:f32):
      #|    v18:i32 = iconst 0
      #|    v19:i64 = iconst 0
      #|    v20:i64 = load_ptr.I64 v0, v19
      #|    v21:i64 = iconst 8
      #|    v22:i64 = load_ptr.I64 v0, v21
      #|    v23:i64 = uextend v18
      #|    v24:i64 = iconst 0
      #|    v25:i64 = iadd v23, v24
      #|    v26:i64 = iconst 4
      #|    v27:i64 = iadd v25, v26
      #|    v28:i32 = icmp.ule v27, v22
      #|    brnz v28, block10, block9
      #|block5:
      #|    jump block4(v2, v5, v4)
      #|block6:
      #|    jump block3(v2, v5, v4)
      #|block7:
      #|    jump block2(v2, v5, v4)
      #|block8:
      #|    jump block1(v2, v5, v4)
      #|block9:
      #|    trap "memory out of bounds"
      #|block10:
      #|    v29:i64 = iadd v20, v25
      #|    v30:i64 = iconst 0
      #|    store_ptr.F32 v29, v16, v30
      #|    v31:i32 = iconst 0
      #|    v32:i64 = iconst 0
      #|    v33:i64 = load_ptr.I64 v0, v32
      #|    v34:i64 = iconst 8
      #|    v35:i64 = load_ptr.I64 v0, v34
      #|    v36:i64 = uextend v31
      #|    v37:i64 = iconst 0
      #|    v38:i64 = iadd v36, v37
      #|    v39:i64 = iconst 4
      #|    v40:i64 = iadd v38, v39
      #|    v41:i32 = icmp.ule v40, v35
      #|    brnz v41, block12, block11
      #|block11:
      #|    trap "memory out of bounds"
      #|block12:
      #|    v42:i64 = iadd v33, v38
      #|    v43:i64 = iconst 0
      #|    v44:f32 = load_ptr.F32 v42, v43
      #|    jump block1(v15, v16, v44)
      #|block13:
      #|    trap "memory out of bounds"
      #|block14:
      #|    v56:i64 = iadd v47, v52
      #|    v57:i64 = iconst 0
      #|    store_ptr.F32 v56, v13, v57
      #|    v58:i32 = iconst 0
      #|    v59:i64 = iconst 0
      #|    v60:i64 = load_ptr.I64 v0, v59
      #|    v61:i64 = iconst 8
      #|    v62:i64 = load_ptr.I64 v0, v61
      #|    v63:i64 = uextend v58
      #|    v64:i64 = iconst 0
      #|    v65:i64 = iadd v63, v64
      #|    v66:i64 = iconst 4
      #|    v67:i64 = iadd v65, v66
      #|    v68:i32 = icmp.ule v67, v62
      #|    brnz v68, block16, block15
      #|block15:
      #|    trap "memory out of bounds"
      #|block16:
      #|    v69:i64 = iadd v60, v65
      #|    v70:i64 = iconst 0
      #|    v71:f32 = load_ptr.F32 v69, v70
      #|    jump block1(v12, v13, v71)
      #|block17:
      #|    trap "memory out of bounds"
      #|block18:
      #|    v83:i64 = iadd v74, v79
      #|    v84:i64 = iconst 0
      #|    store_ptr.F32 v83, v10, v84
      #|    v85:i32 = iconst 0
      #|    v86:i64 = iconst 0
      #|    v87:i64 = load_ptr.I64 v0, v86
      #|    v88:i64 = iconst 8
      #|    v89:i64 = load_ptr.I64 v0, v88
      #|    v90:i64 = uextend v85
      #|    v91:i64 = iconst 0
      #|    v92:i64 = iadd v90, v91
      #|    v93:i64 = iconst 4
      #|    v94:i64 = iadd v92, v93
      #|    v95:i32 = icmp.ule v94, v89
      #|    brnz v95, block20, block19
      #|block19:
      #|    trap "memory out of bounds"
      #|block20:
      #|    v96:i64 = iadd v87, v92
      #|    v97:i64 = iconst 0
      #|    v98:f32 = load_ptr.F32 v96, v97
      #|    jump block1(v9, v10, v98)
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
      #|    branch v18, block5, block21
      #|block1(v3:int, f4:float, f5:float):
      #|    ret f5
      #|block2(v6:int, f7:float, f8:float):
      #|    v24 = ldi 0
      #|    v25 = ldi 0
      #|    v26 = load_ptr.i64 +0 v0
      #|    v27 = ldi 8
      #|    v28 = load_ptr.i64 +8 v0
      #|    v29 = extend.u32_64 v24
      #|    v30 = ldi 0
      #|    v31 = mov v29
      #|    v32 = ldi 4
      #|    v33 = add #4 v31
      #|    v34 = cmp.ule v33, v28
      #|    br_cmp.ls v33, v28, block18, block17
      #|block3(v9:int, f10:float, f11:float):
      #|    v35 = ldi 0
      #|    v36 = ldi 0
      #|    v37 = load_ptr.i64 +0 v0
      #|    v38 = ldi 8
      #|    v39 = load_ptr.i64 +8 v0
      #|    v40 = extend.u32_64 v35
      #|    v41 = ldi 0
      #|    v42 = mov v40
      #|    v43 = ldi 4
      #|    v44 = add #4 v42
      #|    v45 = cmp.ule v44, v39
      #|    br_cmp.ls v44, v39, block14, block13
      #|block4(v12:int, f13:float, f14:float):
      #|    v46 = ldi 0
      #|    v47 = ldi 0
      #|    v48 = load_ptr.i64 +0 v0
      #|    v49 = ldi 8
      #|    v50 = load_ptr.i64 +8 v0
      #|    v51 = extend.u32_64 v46
      #|    v52 = ldi 0
      #|    v53 = mov v51
      #|    v54 = ldi 4
      #|    v55 = add #4 v53
      #|    v56 = cmp.ule v55, v50
      #|    br_cmp.ls v55, v50, block10, block9
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
      #|    trap "memory out of bounds"
      #|block10:
      #|    v57 = add v48, v53
      #|    v58 = ldi 0
      #|    store_ptr.f32 +0 v57, f13
      #|    v59 = ldi 0
      #|    v60 = ldi 0
      #|    v61 = load_ptr.i64 +0 v0
      #|    v62 = ldi 8
      #|    v63 = load_ptr.i64 +8 v0
      #|    v64 = extend.u32_64 v59
      #|    v65 = ldi 0
      #|    v66 = mov v64
      #|    v67 = ldi 4
      #|    v68 = add #4 v66
      #|    v69 = cmp.ule v68, v63
      #|    br_cmp.ls v68, v63, block12, block11
      #|block11:
      #|    trap "memory out of bounds"
      #|block12:
      #|    v70 = add v61, v66
      #|    v71 = ldi 0
      #|    f72 = load_ptr.f32 +0 v70
      #|    v3 = mov v12
      #|    f4 = mov f13
      #|    f5 = mov f72
      #|    jump block1
      #|block13:
      #|    trap "memory out of bounds"
      #|block14:
      #|    v73 = add v37, v42
      #|    v74 = ldi 0
      #|    store_ptr.f32 +0 v73, f10
      #|    v75 = ldi 0
      #|    v76 = ldi 0
      #|    v77 = load_ptr.i64 +0 v0
      #|    v78 = ldi 8
      #|    v79 = load_ptr.i64 +8 v0
      #|    v80 = extend.u32_64 v75
      #|    v81 = ldi 0
      #|    v82 = mov v80
      #|    v83 = ldi 4
      #|    v84 = add #4 v82
      #|    v85 = cmp.ule v84, v79
      #|    br_cmp.ls v84, v79, block16, block15
      #|block15:
      #|    trap "memory out of bounds"
      #|block16:
      #|    v86 = add v77, v82
      #|    v87 = ldi 0
      #|    f88 = load_ptr.f32 +0 v86
      #|    v3 = mov v9
      #|    f4 = mov f10
      #|    f5 = mov f88
      #|    jump block1
      #|block17:
      #|    trap "memory out of bounds"
      #|block18:
      #|    v89 = add v26, v31
      #|    v90 = ldi 0
      #|    store_ptr.f32 +0 v89, f7
      #|    v91 = ldi 0
      #|    v92 = ldi 0
      #|    v93 = load_ptr.i64 +0 v0
      #|    v94 = ldi 8
      #|    v95 = load_ptr.i64 +8 v0
      #|    v96 = extend.u32_64 v91
      #|    v97 = ldi 0
      #|    v98 = mov v96
      #|    v99 = ldi 4
      #|    v100 = add #4 v98
      #|    v101 = cmp.ule v100, v95
      #|    br_cmp.ls v100, v95, block20, block19
      #|block19:
      #|    trap "memory out of bounds"
      #|block20:
      #|    v102 = add v93, v98
      #|    v103 = ldi 0
      #|    f104 = load_ptr.f32 +0 v102
      #|    v3 = mov v6
      #|    f4 = mov f7
      #|    f5 = mov f104
      #|    jump block1
      #|block21:
      #|    v20 = ldi 1
      #|    v21 = cmp32.eq v2, v20
      #|    branch v21, block6, block22
      #|block22:
      #|    v22 = ldi 2
      #|    v23 = cmp32.eq v2, v22
      #|    branch v23, block7, block8
      #|}
      #|
    ),
  )
  let allocated_func = @regalloc.allocate_registers_aarch64(vcode_func)

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
      #|    branch x9, block5, block21
      #|block1(v3:int, f4:float, f5:float):
      #|    ret d3
      #|block2(v6:int, f7:float, f8:float):
      #|    x10 = ldi 0
      #|    x11 = load_ptr.i64 +0 x0
      #|    x12 = load_ptr.i64 +8 x0
      #|    x13 = extend.u32_64 x10
      #|    x14 = mov x13
      #|    x10 = add #4 x14
      #|    br_cmp.ls x10, x12, block18, block17
      #|block3(v9:int, f10:float, f11:float):
      #|    x10 = ldi 0
      #|    x11 = load_ptr.i64 +0 x0
      #|    x12 = load_ptr.i64 +8 x0
      #|    x13 = extend.u32_64 x10
      #|    x14 = mov x13
      #|    x10 = add #4 x14
      #|    br_cmp.ls x10, x12, block14, block13
      #|block4(v12:int, f13:float, f14:float):
      #|    x10 = ldi 0
      #|    x11 = load_ptr.i64 +0 x0
      #|    x12 = load_ptr.i64 +8 x0
      #|    x13 = extend.u32_64 x10
      #|    x14 = mov x13
      #|    x10 = add #4 x14
      #|    br_cmp.ls x10, x12, block10, block9
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
      #|    trap "memory out of bounds"
      #|block10:
      #|    x10 = add x11, x14
      #|    store_ptr.f32 +0 x10, d4
      #|    x11 = ldi 0
      #|    x10 = load_ptr.i64 +0 x0
      #|    x12 = load_ptr.i64 +8 x0
      #|    x13 = extend.u32_64 x11
      #|    x14 = mov x13
      #|    x11 = add #4 x14
      #|    br_cmp.ls x11, x12, block12, block11
      #|block11:
      #|    trap "memory out of bounds"
      #|block12:
      #|    x11 = add x10, x14
      #|    d0 = load_ptr.f32 +0 x11
      #|    x8 = mov x9
      #|    d2 = mov d4
      #|    d3 = mov d0
      #|    jump block1
      #|block13:
      #|    trap "memory out of bounds"
      #|block14:
      #|    x10 = add x11, x14
      #|    store_ptr.f32 +0 x10, d4
      #|    x11 = ldi 0
      #|    x10 = load_ptr.i64 +0 x0
      #|    x12 = load_ptr.i64 +8 x0
      #|    x13 = extend.u32_64 x11
      #|    x14 = mov x13
      #|    x11 = add #4 x14
      #|    br_cmp.ls x11, x12, block16, block15
      #|block15:
      #|    trap "memory out of bounds"
      #|block16:
      #|    x11 = add x10, x14
      #|    d5 = load_ptr.f32 +0 x11
      #|    x8 = mov x9
      #|    d2 = mov d4
      #|    d3 = mov d5
      #|    jump block1
      #|block17:
      #|    trap "memory out of bounds"
      #|block18:
      #|    x10 = add x11, x14
      #|    store_ptr.f32 +0 x10, d4
      #|    x11 = ldi 0
      #|    x10 = load_ptr.i64 +0 x0
      #|    x12 = load_ptr.i64 +8 x0
      #|    x13 = extend.u32_64 x11
      #|    x14 = mov x13
      #|    x11 = add #4 x14
      #|    br_cmp.ls x11, x12, block20, block19
      #|block19:
      #|    trap "memory out of bounds"
      #|block20:
      #|    x11 = add x10, x14
      #|    d5 = load_ptr.f32 +0 x11
      #|    x8 = mov x9
      #|    d2 = mov d4
      #|    d3 = mov d5
      #|    jump block1
      #|block21:
      #|    x8 = ldi 1
      #|    x9 = cmp32.eq x2, x8
      #|    branch x9, block6, block22
      #|block22:
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
      #|  0000: ff4300d1  sub sp, sp, #16
      #|block0:
      #|  0004: 100080d2  movz x16, #0, lsl #0
      #|  0008: 0002271e  fmov s0, w16
      #|  000c: 100080d2  movz x16, #0, lsl #0
      #|  0010: 1024a8f2  movk x16, #16672, lsl #16
      #|  0014: 0102271e  fmov s1, w16
      #|  0018: 080080d2  movz x8, #0, lsl #0
      #|  001c: 5f00086b  cmp w2, w8
      #|  0020: e9179f9a  cset x9, eq
      #|  0024: 090400b5  cbnz x9, block5
      #|  0028: 65000014  b block21
      #|block1:
      #|  002c: 6040201e  fmov s0, s3
      #|  0030: ff430091  add sp, sp, #16
      #|  0034: c0035fd6  ret
      #|block2:
      #|  0038: 0a0080d2  movz x10, #0, lsl #0
      #|  003c: 0b0040f9  ldr x11, [x0, #0]
      #|  0040: 0c0440f9  ldr x12, [x0, #8]
      #|  0044: ed030a2a  mov w13, w10
      #|  0048: ee030daa  mov x14, x13
      #|  004c: ca110091  add x10, x14, #4
      #|  0050: 5f010ceb  cmp x10, x12
      #|  0054: 29090054  b.ls block18
      #|  0058: 47000014  b block17
      #|block3:
      #|  005c: 0a0080d2  movz x10, #0, lsl #0
      #|  0060: 0b0040f9  ldr x11, [x0, #0]
      #|  0064: 0c0440f9  ldr x12, [x0, #8]
      #|  0068: ed030a2a  mov w13, w10
      #|  006c: ee030daa  mov x14, x13
      #|  0070: ca110091  add x10, x14, #4
      #|  0074: 5f010ceb  cmp x10, x12
      #|  0078: c9050054  b.ls block14
      #|  007c: 2c000014  b block13
      #|block4:
      #|  0080: 0a0080d2  movz x10, #0, lsl #0
      #|  0084: 0b0040f9  ldr x11, [x0, #0]
      #|  0088: 0c0440f9  ldr x12, [x0, #8]
      #|  008c: ed030a2a  mov w13, w10
      #|  0090: ee030daa  mov x14, x13
      #|  0094: ca110091  add x10, x14, #4
      #|  0098: 5f010ceb  cmp x10, x12
      #|  009c: 69020054  b.ls block10
      #|  00a0: 11000014  b block9
      #|block5:
      #|  00a4: e90302aa  mov x9, x2
      #|  00a8: 2440201e  fmov s4, s1
      #|  00ac: 0540201e  fmov s5, s0
      #|  00b0: f4ffff17  b block4
      #|block6:
      #|  00b4: e90302aa  mov x9, x2
      #|  00b8: 2440201e  fmov s4, s1
      #|  00bc: 0540201e  fmov s5, s0
      #|  00c0: e7ffff17  b block3
      #|block7:
      #|  00c4: e90302aa  mov x9, x2
      #|  00c8: 2440201e  fmov s4, s1
      #|  00cc: 0540201e  fmov s5, s0
      #|  00d0: daffff17  b block2
      #|block8:
      #|  00d4: e80302aa  mov x8, x2
      #|  00d8: 2240201e  fmov s2, s1
      #|  00dc: 0340201e  fmov s3, s0
      #|  00e0: d3ffff17  b block1
      #|block10:
      #|  00e8: 6a010e8b  add x10, x11, x14
      #|  00ec: 440100bd  str s4, [x10, #0]
      #|  00f0: 0b0080d2  movz x11, #0, lsl #0
      #|  00f4: 0a0040f9  ldr x10, [x0, #0]
      #|  00f8: 0c0440f9  ldr x12, [x0, #8]
      #|  00fc: ed030b2a  mov w13, w11
      #|  0100: ee030daa  mov x14, x13
      #|  0104: cb110091  add x11, x14, #4
      #|  0108: 7f010ceb  cmp x11, x12
      #|  010c: 49000054  b.ls block12
      #|block12:
      #|  0114: 4b010e8b  add x11, x10, x14
      #|  0118: 600140bd  ldr s0, [x11, #0]
      #|  011c: e80309aa  mov x8, x9
      #|  0120: 8240201e  fmov s2, s4
      #|  0124: 0340201e  fmov s3, s0
      #|  0128: c1ffff17  b block1
      #|block14:
      #|  0130: 6a010e8b  add x10, x11, x14
      #|  0134: 440100bd  str s4, [x10, #0]
      #|  0138: 0b0080d2  movz x11, #0, lsl #0
      #|  013c: 0a0040f9  ldr x10, [x0, #0]
      #|  0140: 0c0440f9  ldr x12, [x0, #8]
      #|  0144: ed030b2a  mov w13, w11
      #|  0148: ee030daa  mov x14, x13
      #|  014c: cb110091  add x11, x14, #4
      #|  0150: 7f010ceb  cmp x11, x12
      #|  0154: 49000054  b.ls block16
      #|block16:
      #|  015c: 4b010e8b  add x11, x10, x14
      #|  0160: 650140bd  ldr s5, [x11, #0]
      #|  0164: e80309aa  mov x8, x9
      #|  0168: 8240201e  fmov s2, s4
      #|  016c: a340201e  fmov s3, s5
      #|  0170: afffff17  b block1
      #|block18:
      #|  0178: 6a010e8b  add x10, x11, x14
      #|  017c: 440100bd  str s4, [x10, #0]
      #|  0180: 0b0080d2  movz x11, #0, lsl #0
      #|  0184: 0a0040f9  ldr x10, [x0, #0]
      #|  0188: 0c0440f9  ldr x12, [x0, #8]
      #|  018c: ed030b2a  mov w13, w11
      #|  0190: ee030daa  mov x14, x13
      #|  0194: cb110091  add x11, x14, #4
      #|  0198: 7f010ceb  cmp x11, x12
      #|  019c: 49000054  b.ls block20
      #|block20:
      #|  01a4: 4b010e8b  add x11, x10, x14
      #|  01a8: 650140bd  ldr s5, [x11, #0]
      #|  01ac: e80309aa  mov x8, x9
      #|  01b0: 8240201e  fmov s2, s4
      #|  01b4: a340201e  fmov s3, s5
      #|  01b8: 9dffff17  b block1
      #|block21:
      #|  01bc: 280080d2  movz x8, #1, lsl #0
      #|  01c0: 5f00086b  cmp w2, w8
      #|  01c4: e9179f9a  cset x9, eq
      #|  01c8: 69f7ffb5  cbnz x9, block6
      #|block22:
      #|  01cc: 480080d2  movz x8, #2, lsl #0
      #|  01d0: 5f00086b  cmp w2, w8
      #|  01d4: e9179f9a  cset x9, eq
      #|  01d8: 69f7ffb5  cbnz x9, block7
      #|  01dc: beffff17  b block8
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
