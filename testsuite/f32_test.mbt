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
      #|function test(v0:i64, v1:i64, v2:f32) -> f32 {
      #|block0:
      #|    v3:f32 = fconst 15.5
      #|    v4:f32 = fadd v2, v3
      #|    return v4
      #|}
      #|
    ),
  )
  let vcode = @lower.lower_function(ir_func)
  inspect(
    vcode,
    content=(
      #|vcode test(v0:int, v1:int, f2:float) -> float {
      #|block0:
      #|    f3 = ldf 15.5
      #|    f4 = fadd.s f2, f3
      #|    ret f4
      #|}
      #|
    ),
  )
  let allocated_func = @lower.allocate_registers_aarch64(vcode)
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(v0:int, v1:int, f2:float) -> float {
      #|block0:
      #|    d1 = ldf 15.5
      #|    d2 = fadd.s d0, d1
      #|    ret d2
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
      #|function test(v0:i64, v1:i64, v2:f64) -> f64 {
      #|block0:
      #|    v3:f64 = fconst 15.5
      #|    v4:f64 = fadd v2, v3
      #|    return v4
      #|}
      #|
    ),
  )
  let vcode = @lower.lower_function(ir_func)
  inspect(
    vcode,
    content=(
      #|vcode test(v0:int, v1:int, f2:double) -> double {
      #|block0:
      #|    f3 = ldf 15.5
      #|    f4 = fadd.d f2, f3
      #|    ret f4
      #|}
      #|
    ),
  )
  let allocated_func = @lower.allocate_registers_aarch64(vcode)
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(v0:int, v1:int, f2:double) -> double {
      #|block0:
      #|    d1 = ldf 15.5
      #|    d2 = fadd.d d0, d1
      #|    ret d2
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
      #|function test(v0:i64, v1:i64, v2:f32) -> f32 {
      #|block0:
      #|    v3:f32 = fconst 3.5
      #|    v4:f32 = fsub v2, v3
      #|    return v4
      #|}
      #|
    ),
  )
  let vcode = @lower.lower_function(ir_func)
  inspect(
    vcode,
    content=(
      #|vcode test(v0:int, v1:int, f2:float) -> float {
      #|block0:
      #|    f3 = ldf 3.5
      #|    f4 = fsub.s f2, f3
      #|    ret f4
      #|}
      #|
    ),
  )
  let allocated_func = @lower.allocate_registers_aarch64(vcode)
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(v0:int, v1:int, f2:float) -> float {
      #|block0:
      #|    d1 = ldf 3.5
      #|    d2 = fsub.s d0, d1
      #|    ret d2
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
      #|function test(v0:i64, v1:i64, v2:f32) -> f32 {
      #|block0:
      #|    v3:f32 = fconst 2.5
      #|    v4:f32 = fmul v2, v3
      #|    return v4
      #|}
      #|
    ),
  )
  let vcode = @lower.lower_function(ir_func)
  inspect(
    vcode,
    content=(
      #|vcode test(v0:int, v1:int, f2:float) -> float {
      #|block0:
      #|    f3 = ldf 2.5
      #|    f4 = fmul.s f2, f3
      #|    ret f4
      #|}
      #|
    ),
  )
  let allocated_func = @lower.allocate_registers_aarch64(vcode)
  inspect(
    allocated_func.print(),
    content=(
      #|vcode test(v0:int, v1:int, f2:float) -> float {
      #|block0:
      #|    d1 = ldf 2.5
      #|    d2 = fmul.s d0, d1
      #|    ret d2
      #|}
      #|
    ),
  )
  let mc = @emit.emit_function(allocated_func)
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: fd7bbfa9  stp x29, x30, [sp, #-16]!
      #|  0004: fd031faa  mov x29, x31
      #|  0008: f30f1ff8  str x19, [sp, #-16]!
      #|  000c: ff4300d1  sub sp, sp, #16
      #|  0010: f30300aa  mov x19, x0
      #|block0:
      #|  0014: 100080d2  movz x16, #0, lsl #0
      #|  0018: 1004a8f2  movk x16, #16416, lsl #16
      #|  001c: 0102271e  fmov s1, w16
      #|  0020: 0208211e  fmul s2, s0, s1
      #|  0024: 4040201e  fmov s0, s2
      #|  0028: ff430091  add sp, sp, #16
      #|  002c: f30741f8  ldr x19, [sp], #16
      #|  0030: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0034: c0035fd6  ret
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
