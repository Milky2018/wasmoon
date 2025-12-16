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
  let func_type = ir.types[func_type_idx]

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
    ir.types,
    ir.funcs.mapi(fn(i, _) { ir.funcs[i] }),
    0, // num_imports
    [], // import_func_type_indices
  )
  let ir_func = translator.translate(func_code.body)
  inspect(
    ir_func.print(),
    content=(
      #|function test(v0:i32) -> f32 {
      #|block0:
      #|    v1:f32 = fconst 0
      #|    v2:f32 = fconst 0
      #|    br_table v0, [block4, block5], block6
      #|block1(v3:i32, v4:f32, v5:f32):
      #|    return v4
      #|block2(v6:i32, v7:f32, v8:f32):
      #|    v13:f32 = fconst 3
      #|    jump block1(v6, v13, v8)
      #|block3(v9:i32, v10:f32, v11:f32):
      #|    v12:f32 = fconst 2
      #|    jump block1(v9, v12, v11)
      #|block4:
      #|    jump block3(v0, v1, v2)
      #|block5:
      #|    jump block2(v0, v1, v2)
      #|block6:
      #|    jump block1(v0, v1, v2)
      #|}
      #|
    ),
  )
  let vcode = @lower.lower_function(ir_func)
  inspect(
    vcode,
    content=(
      #|vcode test(v0:int) -> float {
      #|block0:
      #|    f10 = ldf 0
      #|    f11 = ldf 0
      #|    v13 = ldi 0
      #|    v12 = cmp.eq v0, v13
      #|    branch v12, block4, block7
      #|block1(v1:int, f2:float, f3:float):
      #|    ret f2
      #|block2(v4:int, f5:float, f6:float):
      #|    f16 = ldf 3
      #|    v1 = mov v4
      #|    f2 = mov f16
      #|    f3 = mov f6
      #|    jump block1
      #|block3(v7:int, f8:float, f9:float):
      #|    f17 = ldf 2
      #|    v1 = mov v7
      #|    f2 = mov f17
      #|    f3 = mov f9
      #|    jump block1
      #|block4:
      #|    v7 = mov v0
      #|    f8 = mov f10
      #|    f9 = mov f11
      #|    jump block3
      #|block5:
      #|    v4 = mov v0
      #|    f5 = mov f10
      #|    f6 = mov f11
      #|    jump block2
      #|block6:
      #|    v1 = mov v0
      #|    f2 = mov f10
      #|    f3 = mov f11
      #|    jump block1
      #|block7:
      #|    v14 = ldi 1
      #|    v15 = cmp.eq v0, v14
      #|    branch v15, block5, block6
      #|}
      #|
    ),
  )
  let allocated_func = @lower.allocate_registers_aarch64(vcode)
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(v0:int) -> float {
      #|block0:
      #|    d0 = ldf 0
      #|    d1 = ldf 0
      #|    x8 = ldi 0
      #|    x9 = cmp.eq x0, x8
      #|    branch x9, block4, block7
      #|block1(v1:int, f2:float, f3:float):
      #|    ret d2
      #|block2(v4:int, f5:float, f6:float):
      #|    d6 = ldf 3
      #|    x8 = mov x9
      #|    d2 = mov d6
      #|    d3 = mov d5
      #|    jump block1
      #|block3(v7:int, f8:float, f9:float):
      #|    d0 = ldf 2
      #|    x8 = mov x9
      #|    d2 = mov d0
      #|    d3 = mov d5
      #|    jump block1
      #|block4:
      #|    x9 = mov x0
      #|    d4 = mov d0
      #|    d5 = mov d1
      #|    jump block3
      #|block5:
      #|    x9 = mov x0
      #|    d4 = mov d0
      #|    d5 = mov d1
      #|    jump block2
      #|block6:
      #|    x8 = mov x0
      #|    d2 = mov d0
      #|    d3 = mov d1
      #|    jump block1
      #|block7:
      #|    x8 = ldi 1
      #|    x9 = cmp.eq x0, x8
      #|    branch x9, block5, block6
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
  let func_type = ir.types[func_type_idx]

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
    ir.types,
    ir.funcs.mapi(fn(i, _) { ir.funcs[i] }),
    0, // num_imports
    [], // import_func_type_indices
  )
  let ir_func = translator.translate(func_code.body)
  let vcode = @lower.lower_function(ir_func)
  let allocated_func = @lower.allocate_registers_aarch64(vcode)
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
  inspect(result0, content="10")
  let @jit.Single((result1 : Float)) = jm.call_with_context_poly(
    f,
    @jit.Single(1L),
  )
  inspect(result1, content="10")
  let @jit.Single((result2 : Float)) = jm.call_with_context_poly(
    f,
    @jit.Single(2L),
  )
  inspect(result2, content="10")
  let @jit.Single((result3 : Float)) = jm.call_with_context_poly(
    f,
    @jit.Single(3L),
  )
  inspect(result3, content="0")
}
