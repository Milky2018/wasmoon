///|
test "A critical bug (fixed) as in data/f32_br_2locals_simp" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (param i32) (result f32)
    #|    (local f32 f32)
    #|    (block $2
    #|      (block $1
    #|        (block $0
    #|          (br_table $0 $1 $2 (local.get 0))
    #|        )
    #|        ;; case 0
    #|        (local.set 1 (f32.const 2.0))
    #|        (br $2)
    #|      )
    #|      ;; case 1
    #|      (local.set 1 (f32.const 3.0))
    #|      (br $2)
    #|    )
    #|    ;; case 2 / default
    #|    (local.get 1)
    #|  )
    #|)
  let ir = @wat.parse(source)
  let func_code = ir.codes[0]
  let func_type_idx = ir.funcs[0]
  let func_type = ir.get_func_type(func_type_idx)

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
    @types.extract_func_types(ir.types),
    ir.funcs.mapi(fn(i, _) { ir.funcs[i] }),
    0, // num_imports
    [], // import_func_type_indices
  )
  let ir_func = translator.translate(func_code.body)
  inspect(
    ir_func.print(),
    content=(
      #|function test(v0:i64, v1:i32) -> f32 {
      #|block0:
      #|    v2:f32 = fconst 0
      #|    v3:f32 = fconst 0
      #|    br_table v1, [block4, block5], block6
      #|block1(v4:i32, v5:f32, v6:f32):
      #|    return v5
      #|block2(v7:i32, v8:f32, v9:f32):
      #|    v14:f32 = fconst 3
      #|    jump block1(v7, v14, v9)
      #|block3(v10:i32, v11:f32, v12:f32):
      #|    v13:f32 = fconst 2
      #|    jump block1(v10, v13, v12)
      #|block4:
      #|    jump block3(v1, v2, v3)
      #|block5:
      #|    jump block2(v1, v2, v3)
      #|block6:
      #|    jump block1(v1, v2, v3)
      #|}
      #|
    ),
  )
  let vcode = @lower.lower_function(ir_func)
  inspect(
    vcode,
    content=(
      #|vcode test(v0:int, v1:int) -> float {
      #|block0:
      #|    f11 = ldf 0
      #|    f12 = ldf 0
      #|    br_cmp_imm.eq v1, #0, block4, block7
      #|block1(v2:int, f3:float, f4:float):
      #|    ret f3
      #|block2(v5:int, f6:float, f7:float):
      #|    f17 = ldf 3
      #|    jump block1 (v5, f17, f7)
      #|block3(v8:int, f9:float, f10:float):
      #|    f18 = ldf 2
      #|    jump block1 (v8, f18, f10)
      #|block4:
      #|    jump block3 (v1, f11, f12)
      #|block5:
      #|    jump block2 (v1, f11, f12)
      #|block6:
      #|    jump block1 (v1, f11, f12)
      #|block7:
      #|    br_cmp_imm.eq v1, #1, block5, block6
      #|}
      #|
    ),
  )
  let allocated_func = @regalloc.allocate_registers_backtracking(vcode)
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(v0:int, v1:int) -> float {
      #|block0:
      #|    d0 = ldf 0
      #|    d1 = ldf 0
      #|    br_cmp_imm.eq x1, #0, block4, block7
      #|block1(v2:int, f3:float, f4:float):
      #|    ret d0
      #|block2(v5:int, f6:float, f7:float):
      #|    d0 = ldf 3
      #|    jump block1
      #|block3(v8:int, f9:float, f10:float):
      #|    d0 = ldf 2
      #|    jump block1
      #|block4:
      #|    jump block3
      #|block5:
      #|    jump block2
      #|block6:
      #|    jump block1
      #|block7:
      #|    br_cmp_imm.eq x1, #1, block5, block6
      #|}
      #|
    ),
  )
  let mc = @emit.emit_function(allocated_func)
  let code_bytes = mc.get_bytes()
  let jit_module = @jit.JITModule::from_single_function(
    code_bytes,
    "test",
    [@types.ValueType::I32], // param_types
    [@types.ValueType::F32], // result_types
    4096L, // mem_size
  )
  guard jit_module is Some(jm) else { return }
  let func = jm.get_func_by_name("test")
  guard func is Some(f) else { return }
  let @jit.Single((result0 : Float)) = jm.call_with_context_poly(
    f,
    @jit.Single(0L),
  )
  inspect(result0, content="2")
  assert_eq(result0, 2)
  let @jit.Single((result1 : Float)) = jm.call_with_context_poly(
    f,
    @jit.Single(1L),
  )
  inspect(result1, content="3")
  assert_eq(result1, 3)
  let @jit.Single((result2 : Float)) = jm.call_with_context_poly(
    f,
    @jit.Single(2L),
  )
  inspect(result2, content="0")
  assert_eq(result2, 0)
}

///|
test "A critical bug as in data/f32_br_2locals" {
  let source =
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
  let ir = @wat.parse(source)
  let func_code = ir.codes[0]
  let func_type_idx = ir.funcs[0]
  let func_type = ir.get_func_type(func_type_idx)

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
    @types.extract_func_types(ir.types),
    ir.funcs.mapi(fn(i, _) { ir.funcs[i] }),
    0, // num_imports
    [], // import_func_type_indices
  )
  let ir_func = translator.translate(func_code.body)
  let vcode = @lower.lower_function(ir_func)
  let allocated_func = @regalloc.allocate_registers_backtracking(vcode)
  let mc = @emit.emit_function(allocated_func)
  let code_bytes = mc.get_bytes()
  let jit_module = @jit.JITModule::from_single_function(
    code_bytes,
    "test",
    [@types.ValueType::I32], // param_types
    [@types.ValueType::F32], // result_types
    4096L, // mem_size
  )
  guard jit_module is Some(jm) else { return }
  let func = jm.get_func_by_name("test")
  guard func is Some(f) else { return }
  let @jit.Single((result0 : Float)) = jm.call_with_context_poly(
    f,
    @jit.Single(0L),
  )
  assert_eq(result0, 10)
  let @jit.Single((result1 : Float)) = jm.call_with_context_poly(
    f,
    @jit.Single(1L),
  )
  assert_eq(result1, 10)
  let @jit.Single((result2 : Float)) = jm.call_with_context_poly(
    f,
    @jit.Single(2L),
  )
  assert_eq(result2, 10)
  let @jit.Single((result3 : Float)) = jm.call_with_context_poly(
    f,
    @jit.Single(3L),
  )
  assert_eq(result3, 0)
}
