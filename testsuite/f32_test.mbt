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
      #|function test(v0:f32) -> f32 {
      #|block0:
      #|    v1:f32 = fconst 15.5
      #|    v2:f32 = fadd v0, v1
      #|    return v2
      #|}
      #|
    ),
  )
  let vcode = @vcode.lower_function(ir_func)
  inspect(
    vcode,
    content=(
      #|vcode test(f0:float) -> float {
      #|block0:
      #|    f1 = ldf 15.5
      #|    f2 = fadd f0, f1
      #|    ret f2
      #|}
      #|
    ),
  )
  let allocated_func = @vcode.allocate_registers_aarch64(vcode)
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(f0:float) -> float {
      #|block0:
      #|    d1 = ldf 15.5
      #|    d2 = fadd d0, d1
      #|    ret d2
      #|}
      #|
    ),
  )
  let mc = @vcode.emit_function(allocated_func)
  let code_bytes = mc.get_bytes()
  let jit_module = @jit.JITModule::from_single_function(
    code_bytes,
    "test",
    1, // num_params
    [@types.ValueType::F32], // result_types
    4096L, // mem_size
  )
  guard jit_module is Some(jm) else { return }
  defer jm.free()
  let func = jm.get_func_by_name("test")
  guard func is Some(f) else { return }
  // Pass Float values (f32) since the WASM function takes f32 parameter
  // JITArg for Float reinterprets the f32 bit pattern and passes it correctly
  let result0 = jm.call_with_context(f, [
    (0.0 : Float).reinterpret_as_int().to_int64(),
  ])
  inspect(
    @types.Value::F32(Float::from_double(result0[0].reinterpret_as_double())),
    content="F32(15.5)",
  )
  let result1 = jm.call_with_context(f, [
    (1.0 : Float).reinterpret_as_int().to_int64(),
  ])
  inspect(
    @types.Value::F32(Float::from_double(result1[0].reinterpret_as_double())),
    content="F32(16.5)",
  )
  let result2 = jm.call_with_context(f, [
    (2.0 : Float).reinterpret_as_int().to_int64(),
  ])
  inspect(
    @types.Value::F32(Float::from_double(result2[0].reinterpret_as_double())),
    content="F32(17.5)",
  )
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
      #|function test(v0:f64) -> f64 {
      #|block0:
      #|    v1:f64 = fconst 15.5
      #|    v2:f64 = fadd v0, v1
      #|    return v2
      #|}
      #|
    ),
  )
  let vcode = @vcode.lower_function(ir_func)
  inspect(
    vcode,
    content=(
      #|vcode test(f0:double) -> double {
      #|block0:
      #|    f1 = ldf 15.5
      #|    f2 = fadd f0, f1
      #|    ret f2
      #|}
      #|
    ),
  )
  let allocated_func = @vcode.allocate_registers_aarch64(vcode)
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(f0:double) -> double {
      #|block0:
      #|    d1 = ldf 15.5
      #|    d2 = fadd d0, d1
      #|    ret d2
      #|}
      #|
    ),
  )
  let mc = @vcode.emit_function(allocated_func)
  let code_bytes = mc.get_bytes()
  let jit_module = @jit.JITModule::from_single_function(
    code_bytes,
    "test",
    1, // num_params
    [@types.ValueType::F64], // result_types
    4096L, // mem_size
  )
  guard jit_module is Some(jm) else { return }
  defer jm.free()
  let func = jm.get_func_by_name("test")
  guard func is Some(f) else { return }
  let result0 = jm.call_with_context(f, [0.0.reinterpret_as_int64()])
  inspect(
    @types.Value::F64(result0[0].reinterpret_as_double()),
    content="F64(15.5)",
  )
  let result1 = jm.call_with_context(f, [1.0.reinterpret_as_int64()])
  inspect(
    @types.Value::F64(result1[0].reinterpret_as_double()),
    content="F64(16.5)",
  )
  let result2 = jm.call_with_context(f, [2.0.reinterpret_as_int64()])
  inspect(
    @types.Value::F64(result2[0].reinterpret_as_double()),
    content="F64(17.5)",
  )
}
