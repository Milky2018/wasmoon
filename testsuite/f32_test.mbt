///|
test "f32 add" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (param f32) (result f32)
    #|    (local.get 0)
    #|    (f32.const 15.5)
    #|    (f32.add)
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
      #|function test(v0:i64, v1:f32) -> f32 {
      #|block0:
      #|    v2:f32 = fconst 15.5
      #|    v3:f32 = fadd v1, v2
      #|    return v3
      #|}
      #|
    ),
  )
  let vcode = @lower.lower_function(ir_func)
  inspect(
    vcode,
    content=(
      #|vcode test(v0:int, f1:float) -> float {
      #|block0:
      #|    f2 = ldf 15.5
      #|    f3 = fadd.s f1, f2
      #|    ret f3
      #|}
      #|
    ),
  )
  let allocated_func = @regalloc.allocate_registers_backtracking(vcode)
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(v0:int, f1:float) -> float {
      #|block0:
      #|    d1 = ldf 15.5
      #|    d0 = fadd.s d0, d1
      #|    ret d0
      #|}
      #|
    ),
  )
  let mc = @emit.emit_function(allocated_func)
  let code_bytes = mc.get_bytes()
  let jit_module = @jit.JITModule::from_single_function(
    code_bytes,
    "test",
    [@types.ValueType::F32], // param_types
    [@types.ValueType::F32], // result_types
    4096L, // mem_size
  )
  guard jit_module is Some(jm) else { return }
  let func = jm.get_func_by_name("test")
  guard func is Some(f) else { return }
  // Pass Float values (f32) since the WASM function takes f32 parameter
  // JITArg for Float reinterprets the f32 bit pattern and passes it correctly
  let @jit.Single((result0 : Float)) = jm.call_with_context_poly(
    f,
    @jit.Single((0.0 : Float)),
  )
  inspect(result0, content="15.5")
  let @jit.Single((result1 : Float)) = jm.call_with_context_poly(
    f,
    @jit.Single((1.0 : Float)),
  )
  inspect(result1, content="16.5")
  let @jit.Single((result2 : Float)) = jm.call_with_context_poly(
    f,
    @jit.Single((2.0 : Float)),
  )
  inspect(result2, content="17.5")
}

///|
test "f64 add" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (param f64) (result f64)
    #|    (local.get 0)
    #|    (f64.const 15.5)
    #|    (f64.add)
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
      #|function test(v0:i64, v1:f64) -> f64 {
      #|block0:
      #|    v2:f64 = fconst 15.5
      #|    v3:f64 = fadd v1, v2
      #|    return v3
      #|}
      #|
    ),
  )
  let vcode = @lower.lower_function(ir_func)
  inspect(
    vcode,
    content=(
      #|vcode test(v0:int, f1:double) -> double {
      #|block0:
      #|    f2 = ldf 15.5
      #|    f3 = fadd.d f1, f2
      #|    ret f3
      #|}
      #|
    ),
  )
  let allocated_func = @regalloc.allocate_registers_backtracking(vcode)
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(v0:int, f1:double) -> double {
      #|block0:
      #|    d1 = ldf 15.5
      #|    d0 = fadd.d d0, d1
      #|    ret d0
      #|}
      #|
    ),
  )
  let mc = @emit.emit_function(allocated_func)
  let code_bytes = mc.get_bytes()
  let jit_module = @jit.JITModule::from_single_function(
    code_bytes,
    "test",
    [@types.ValueType::F64], // param_types
    [@types.ValueType::F64], // result_types
    4096L, // mem_size
  )
  guard jit_module is Some(jm) else { return }
  let func = jm.get_func_by_name("test")
  guard func is Some(f) else { return }
  let @jit.Single((result0 : Double)) = jm.call_with_context_poly(
    f,
    @jit.Single(0.0),
  )
  inspect(result0, content="15.5")
  let @jit.Single((result1 : Double)) = jm.call_with_context_poly(
    f,
    @jit.Single(1.0),
  )
  inspect(result1, content="16.5")
  let @jit.Single((result2 : Double)) = jm.call_with_context_poly(
    f,
    @jit.Single(2.0),
  )
  inspect(result2, content="17.5")
}

///|
test "f32 sub" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (param f32) (result f32)
    #|    (local.get 0)
    #|    (f32.const 3.5)
    #|    (f32.sub)
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
      #|function test(v0:i64, v1:f32) -> f32 {
      #|block0:
      #|    v2:f32 = fconst 3.5
      #|    v3:f32 = fsub v1, v2
      #|    return v3
      #|}
      #|
    ),
  )
  let vcode = @lower.lower_function(ir_func)
  inspect(
    vcode,
    content=(
      #|vcode test(v0:int, f1:float) -> float {
      #|block0:
      #|    f2 = ldf 3.5
      #|    f3 = fsub.s f1, f2
      #|    ret f3
      #|}
      #|
    ),
  )
  let allocated_func = @regalloc.allocate_registers_backtracking(vcode)
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(v0:int, f1:float) -> float {
      #|block0:
      #|    d1 = ldf 3.5
      #|    d0 = fsub.s d0, d1
      #|    ret d0
      #|}
      #|
    ),
  )
  let mc = @emit.emit_function(allocated_func)
  let code_bytes = mc.get_bytes()
  let jit_module = @jit.JITModule::from_single_function(
    code_bytes,
    "test",
    [@types.ValueType::F32], // param_types
    [@types.ValueType::F32], // result_types
    4096L, // mem_size
  )
  guard jit_module is Some(jm) else { return }
  let func = jm.get_func_by_name("test")
  guard func is Some(f) else { return }
  // 10.0 - 3.5 = 6.5
  let @jit.Single((result0 : Float)) = jm.call_with_context_poly(
    f,
    @jit.Single((10.0 : Float)),
  )
  inspect(result0, content="6.5")
  // 5.5 - 3.5 = 2.0
  let @jit.Single((result1 : Float)) = jm.call_with_context_poly(
    f,
    @jit.Single((5.5 : Float)),
  )
  inspect(result1, content="2")
  // 3.5 - 3.5 = 0.0
  let @jit.Single((result2 : Float)) = jm.call_with_context_poly(
    f,
    @jit.Single((3.5 : Float)),
  )
  inspect(result2, content="0")
}

///|
test "f32 mul" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (param f32) (result f32)
    #|    (local.get 0)
    #|    (f32.const 2.5)
    #|    (f32.mul)
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
      #|function test(v0:i64, v1:f32) -> f32 {
      #|block0:
      #|    v2:f32 = fconst 2.5
      #|    v3:f32 = fmul v1, v2
      #|    return v3
      #|}
      #|
    ),
  )
  let vcode = @lower.lower_function(ir_func)
  inspect(
    vcode,
    content=(
      #|vcode test(v0:int, f1:float) -> float {
      #|block0:
      #|    f2 = ldf 2.5
      #|    f3 = fmul.s f1, f2
      #|    ret f3
      #|}
      #|
    ),
  )
  let allocated_func = @regalloc.allocate_registers_backtracking(vcode)
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(v0:int, f1:float) -> float {
      #|block0:
      #|    d1 = ldf 2.5
      #|    d0 = fmul.s d0, d1
      #|    ret d0
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
      #|  0004: 1004a8f2  movk x16, #16416, lsl #16
      #|  0008: 0102271e  fmov s1, w16
      #|  000c: 0008211e  fmul s0, s0, s1
      #|  0010: c0035fd6  ret
      #|
    ),
  )
  let code_bytes = mc.get_bytes()
  let jit_module = @jit.JITModule::from_single_function(
    code_bytes,
    "test",
    [@types.ValueType::F32], // param_types
    [@types.ValueType::F32], // result_types
    4096L, // mem_size
  )
  guard jit_module is Some(jm) else { return }
  let func = jm.get_func_by_name("test")
  guard func is Some(f) else { return }
  // 4.0 * 2.5 = 10.0
  let @jit.Single((result0 : Float)) = jm.call_with_context_poly(
    f,
    @jit.Single((4.0 : Float)),
  )
  inspect(result0, content="10")
  assert_eq(result0, 10)
  // 3.0 * 2.5 = 7.5
  let @jit.Single((result1 : Float)) = jm.call_with_context_poly(
    f,
    @jit.Single((3.0 : Float)),
  )
  inspect(result1, content="7.5")
  assert_eq(result1, 7.5)
  // 0.0 * 2.5 = 0.0
  let @jit.Single((result2 : Float)) = jm.call_with_context_poly(
    f,
    @jit.Single((0.0 : Float)),
  )
  inspect(result2, content="0")
  assert_eq(result2, 0)
}
