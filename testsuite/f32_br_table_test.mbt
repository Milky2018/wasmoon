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
      #|function test(v0:i64, v1:i64, v2:i32) -> f32 {
      #|block0:
      #|    v3:f32 = fconst 0
      #|    v4:f32 = fconst 0
      #|    br_table v2, [block4, block5], block6
      #|block1(v5:i32, v6:f32, v7:f32):
      #|    return v6
      #|block2(v8:i32, v9:f32, v10:f32):
      #|    v15:f32 = fconst 3
      #|    jump block1(v8, v15, v10)
      #|block3(v11:i32, v12:f32, v13:f32):
      #|    v14:f32 = fconst 2
      #|    jump block1(v11, v14, v13)
      #|block4:
      #|    jump block3(v2, v3, v4)
      #|block5:
      #|    jump block2(v2, v3, v4)
      #|block6:
      #|    jump block1(v2, v3, v4)
      #|}
      #|
    ),
  )
  let vcode = @lower.lower_function(ir_func)
  inspect(
    vcode,
    content=(
      #|vcode test(v0:int, v1:int, v2:int) -> float {
      #|block0:
      #|    f12 = ldf 0
      #|    f13 = ldf 0
      #|    v15 = ldi 0
      #|    v14 = cmp32.eq v2, v15
      #|    branch v14, block4, block7
      #|block1(v3:int, f4:float, f5:float):
      #|    ret f4
      #|block2(v6:int, f7:float, f8:float):
      #|    f18 = ldf 3
      #|    jump block1 (v6, f18, f8)
      #|block3(v9:int, f10:float, f11:float):
      #|    f19 = ldf 2
      #|    jump block1 (v9, f19, f11)
      #|block4:
      #|    jump block3 (v2, f12, f13)
      #|block5:
      #|    jump block2 (v2, f12, f13)
      #|block6:
      #|    jump block1 (v2, f12, f13)
      #|block7:
      #|    v16 = ldi 1
      #|    v17 = cmp32.eq v2, v16
      #|    branch v17, block5, block6
      #|}
      #|
    ),
  )
  let allocated_func = @regalloc.allocate_registers_backtracking(vcode)
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(v0:int, v1:int, v2:int) -> float {
      #|block0:
      #|    d0 = ldf 0
      #|    d1 = ldf 0
      #|    x8 = ldi 0
      #|    x8 = cmp32.eq x2, x8
      #|    branch x8, block4, block7
      #|block1(v3:int, f4:float, f5:float):
      #|    ret d0
      #|block2(v6:int, f7:float, f8:float):
      #|    d0 = ldf 3
      #|    jump block1
      #|block3(v9:int, f10:float, f11:float):
      #|    d0 = ldf 2
      #|    jump block1
      #|block4:
      #|    jump block3
      #|block5:
      #|    jump block2
      #|block6:
      #|    jump block1
      #|block7:
      #|    x8 = ldi 1
      #|    x8 = cmp32.eq x2, x8
      #|    branch x8, block5, block6
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
