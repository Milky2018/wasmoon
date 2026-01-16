///|
test "multi return: 3 integers" {
  let source =
    #|(module
    #|  (func (export "test") (param i32) (result i32 i32 i32)
    #|    (local.get 0)
    #|    (local.get 0)
    #|    (i32.const 1)
    #|    (i32.add)
    #|    (local.get 0)
    #|    (i32.const 2)
    #|    (i32.add)
    #|  )
    #|)
  let ir = @wat.parse(source)
  let func_code = ir.codes[0]
  let func_type_idx = ir.funcs[0]
  let func_type = ir.get_func_type(func_type_idx)
  let locals : Array[@types.ValueType] = []
  for loc in func_code.locals {
    locals.push(loc)
  }
  let translator = @ir.Translator::new(
    "test",
    func_type,
    locals,
    @types.extract_func_types(ir.types),
    ir.funcs.mapi(fn(i, _) { ir.funcs[i] }),
    0,
    [],
  )
  let ir_func = translator.translate(func_code.body)
  let vcode = @lower.lower_function(ir_func)
  let allocated_func = @regalloc.allocate_registers_backtracking(vcode)
  let mc = @emit.emit_function(allocated_func)
  let code_bytes = mc.get_bytes()
  let jit_module = @jit.JITModule::from_single_function(
    code_bytes,
    "test",
    [@types.ValueType::I32],
    [@types.ValueType::I32, @types.ValueType::I32, @types.ValueType::I32],
    4096L,
  )
  guard jit_module is Some(jm) else { return }
  let func = jm.get_func_by_name("test")
  guard func is Some(f) else { return }
  let (r0, r1, r2) : (Int, Int, Int) = jm.call_with_context_poly(
    f,
    @jit.Single(10),
  )
  inspect(r0, content="10")
  inspect(r1, content="11")
  inspect(r2, content="12")
}

///|
test "multi return: 4 integers" {
  let source =
    #|(module
    #|  (func (export "test") (param i32) (result i32 i32 i32 i32)
    #|    (local.get 0)
    #|    (local.get 0)
    #|    (i32.const 10)
    #|    (i32.add)
    #|    (local.get 0)
    #|    (i32.const 20)
    #|    (i32.add)
    #|    (local.get 0)
    #|    (i32.const 30)
    #|    (i32.add)
    #|  )
    #|)
  let ir = @wat.parse(source)
  let func_code = ir.codes[0]
  let func_type_idx = ir.funcs[0]
  let func_type = ir.get_func_type(func_type_idx)
  let locals : Array[@types.ValueType] = []
  for loc in func_code.locals {
    locals.push(loc)
  }
  let translator = @ir.Translator::new(
    "test",
    func_type,
    locals,
    @types.extract_func_types(ir.types),
    ir.funcs.mapi(fn(i, _) { ir.funcs[i] }),
    0,
    [],
  )
  let ir_func = translator.translate(func_code.body)
  let vcode = @lower.lower_function(ir_func)
  let allocated_func = @regalloc.allocate_registers_backtracking(vcode)
  let mc = @emit.emit_function(allocated_func)
  let code_bytes = mc.get_bytes()
  let jit_module = @jit.JITModule::from_single_function(
    code_bytes,
    "test",
    [@types.ValueType::I32],
    [
      @types.ValueType::I32,
      @types.ValueType::I32,
      @types.ValueType::I32,
      @types.ValueType::I32,
    ],
    4096L,
  )
  guard jit_module is Some(jm) else { return }
  let func = jm.get_func_by_name("test")
  guard func is Some(f) else { return }
  let (r0, r1, r2, r3) : (Int, Int, Int, Int) = jm.call_with_context_poly(
    f,
    @jit.Single(100),
  )
  inspect(r0, content="100")
  inspect(r1, content="110")
  inspect(r2, content="120")
  inspect(r3, content="130")
}

///|
test "multi return: 3 floats" {
  let source =
    #|(module
    #|  (func (export "test") (result f64 f64 f64)
    #|    (f64.const 1.5)
    #|    (f64.const 2.5)
    #|    (f64.const 3.5)
    #|  )
    #|)
  let ir = @wat.parse(source)
  let func_code = ir.codes[0]
  let func_type_idx = ir.funcs[0]
  let func_type = ir.get_func_type(func_type_idx)
  let locals : Array[@types.ValueType] = []
  for loc in func_code.locals {
    locals.push(loc)
  }
  let translator = @ir.Translator::new(
    "test",
    func_type,
    locals,
    @types.extract_func_types(ir.types),
    ir.funcs.mapi(fn(i, _) { ir.funcs[i] }),
    0,
    [],
  )
  let ir_func = translator.translate(func_code.body)
  let vcode = @lower.lower_function(ir_func)
  let allocated_func = @regalloc.allocate_registers_backtracking(vcode)
  let mc = @emit.emit_function(allocated_func)
  let code_bytes = mc.get_bytes()
  let jit_module = @jit.JITModule::from_single_function(
    code_bytes,
    "test",
    [],
    [@types.ValueType::F64, @types.ValueType::F64, @types.ValueType::F64],
    4096L,
  )
  guard jit_module is Some(jm) else { return }
  let func = jm.get_func_by_name("test")
  guard func is Some(f) else { return }
  let (r0, r1, r2) : (Double, Double, Double) = jm.call_with_context_poly(f, ())
  inspect(r0, content="1.5")
  inspect(r1, content="2.5")
  inspect(r2, content="3.5")
}

///|
test "multi return: mixed int and float" {
  let source =
    #|(module
    #|  (func (export "test") (param i32) (result i32 i32 i32 f64)
    #|    (local.get 0)
    #|    (local.get 0)
    #|    (i32.const 10)
    #|    (i32.add)
    #|    (local.get 0)
    #|    (i32.const 20)
    #|    (i32.add)
    #|    (f64.const 3.14)
    #|  )
    #|)
  let ir = @wat.parse(source)
  let func_code = ir.codes[0]
  let func_type_idx = ir.funcs[0]
  let func_type = ir.get_func_type(func_type_idx)
  let locals : Array[@types.ValueType] = []
  for loc in func_code.locals {
    locals.push(loc)
  }
  let translator = @ir.Translator::new(
    "test",
    func_type,
    locals,
    @types.extract_func_types(ir.types),
    ir.funcs.mapi(fn(i, _) { ir.funcs[i] }),
    0,
    [],
  )
  let ir_func = translator.translate(func_code.body)
  let vcode = @lower.lower_function(ir_func)
  let allocated_func = @regalloc.allocate_registers_backtracking(vcode)
  let mc = @emit.emit_function(allocated_func)
  let code_bytes = mc.get_bytes()
  let jit_module = @jit.JITModule::from_single_function(
    code_bytes,
    "test",
    [@types.ValueType::I32],
    [
      @types.ValueType::I32,
      @types.ValueType::I32,
      @types.ValueType::I32,
      @types.ValueType::F64,
    ],
    4096L,
  )
  guard jit_module is Some(jm) else { return }
  let func = jm.get_func_by_name("test")
  guard func is Some(f) else { return }
  let (r0, r1, r2, r3) : (Int, Int, Int, Double) = jm.call_with_context_poly(
    f,
    @jit.Single(5),
  )
  inspect(r0, content="5")
  inspect(r1, content="15")
  inspect(r2, content="25")
  inspect(r3, content="3.14")
}

///|
test "multi return: 2 integers (no extra buffer)" {
  let source =
    #|(module
    #|  (func (export "test") (result i32 i32)
    #|    (i32.const 42)
    #|    (i32.const 99)
    #|  )
    #|)
  let ir = @wat.parse(source)
  let func_code = ir.codes[0]
  let func_type_idx = ir.funcs[0]
  let func_type = ir.get_func_type(func_type_idx)
  let locals : Array[@types.ValueType] = []
  for loc in func_code.locals {
    locals.push(loc)
  }
  let translator = @ir.Translator::new(
    "test",
    func_type,
    locals,
    @types.extract_func_types(ir.types),
    ir.funcs.mapi(fn(i, _) { ir.funcs[i] }),
    0,
    [],
  )
  let ir_func = translator.translate(func_code.body)
  let vcode = @lower.lower_function(ir_func)
  let allocated_func = @regalloc.allocate_registers_backtracking(vcode)
  let mc = @emit.emit_function(allocated_func)
  let code_bytes = mc.get_bytes()
  let jit_module = @jit.JITModule::from_single_function(
    code_bytes,
    "test",
    [],
    [@types.ValueType::I32, @types.ValueType::I32],
    4096L,
  )
  guard jit_module is Some(jm) else { return }
  let func = jm.get_func_by_name("test")
  guard func is Some(f) else { return }
  let (r0, r1) : (Int, Int) = jm.call_with_context_poly(f, ())
  inspect(r0, content="42")
  inspect(r1, content="99")
}
