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
      #|    f2 = fadd.s f0, f1
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
      #|    d2 = fadd.s d0, d1
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
      #|    f2 = fadd.d f0, f1
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
      #|    d2 = fadd.d d0, d1
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
      #|    v1:f32 = fconst 3.5
      #|    v2:f32 = fsub v0, v1
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
      #|    f1 = ldf 3.5
      #|    f2 = fsub.s f0, f1
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
      #|    d1 = ldf 3.5
      #|    d2 = fsub.s d0, d1
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
  // 10.0 - 3.5 = 6.5
  let result0 = jm.call_with_context(f, [
    (10.0 : Float).reinterpret_as_int().to_int64(),
  ])
  inspect(
    @types.Value::F32(Float::from_double(result0[0].reinterpret_as_double())),
    content="F32(6.5)",
  )
  // 5.5 - 3.5 = 2.0
  let result1 = jm.call_with_context(f, [
    (5.5 : Float).reinterpret_as_int().to_int64(),
  ])
  inspect(
    @types.Value::F32(Float::from_double(result1[0].reinterpret_as_double())),
    content="F32(2)",
  )
  // 3.5 - 3.5 = 0.0
  let result2 = jm.call_with_context(f, [
    (3.5 : Float).reinterpret_as_int().to_int64(),
  ])
  inspect(
    @types.Value::F32(Float::from_double(result2[0].reinterpret_as_double())),
    content="F32(0)",
  )
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
      #|    v1:f32 = fconst 2.5
      #|    v2:f32 = fmul v0, v1
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
      #|    f1 = ldf 2.5
      #|    f2 = fmul.s f0, f1
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
      #|    d1 = ldf 2.5
      #|    d2 = fmul.s d0, d1
      #|    ret d2
      #|}
      #|
    ),
  )
  let mc = @vcode.emit_function(allocated_func)
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: ff8300d1  sub sp, sp, #32
      #|  0004: f45700a9  stp x20, x21, [sp, #0]
      #|  0008: f67f01a9  stp x22, x31, [sp, #16]
      #|  000c: f40300aa  mov x20, x0
      #|  0010: f50301aa  mov x21, x1
      #|  0014: f60302aa  mov x22, x2
      #|  0018: 7000271e  fmov s16, w3
      #|  001c: 00c2221e  fcvt d0, s16
      #|block0:
      #|  0020: 100080d2  movz x16, #0, lsl #0
      #|  0024: 1004a8f2  movk x16, #16416, lsl #16
      #|  0028: 1002271e  fmov s16, w16
      #|  002c: 01c2221e  fcvt d1, s16
      #|  0030: 1040621e  fcvt s16, d0
      #|  0034: 3140621e  fcvt s17, d1
      #|  0038: 100a311e  fmul s16, s16, s17
      #|  003c: 02c2221e  fcvt d2, s16
      #|  0040: 4040601e  fmov d0, d2
      #|  0044: f45740a9  ldp x20, x21, [sp, #0]
      #|  0048: f60b40f9  ldr x22, [x31, #16]
      #|  004c: ff830091  add sp, sp, #32
      #|  0050: c0035fd6  ret
      #|
    ),
  )
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
  // 4.0 * 2.5 = 10.0
  let result0 = jm.call_with_context(f, [
    (4.0 : Float).reinterpret_as_int().to_int64(),
  ])
  inspect(
    @types.Value::F32(Float::from_double(result0[0].reinterpret_as_double())),
    content="F32(10)",
  )
  // 3.0 * 2.5 = 7.5
  let result1 = jm.call_with_context(f, [
    (3.0 : Float).reinterpret_as_int().to_int64(),
  ])
  inspect(
    @types.Value::F32(Float::from_double(result1[0].reinterpret_as_double())),
    content="F32(7.5)",
  )
  // 0.0 * 2.5 = 0.0
  let result2 = jm.call_with_context(f, [
    (0.0 : Float).reinterpret_as_int().to_int64(),
  ])
  inspect(
    @types.Value::F32(Float::from_double(result2[0].reinterpret_as_double())),
    content="F32(0)",
  )
}
