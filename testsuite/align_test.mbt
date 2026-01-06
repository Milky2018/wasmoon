///|
/// Test for unaligned memory access (align.wast)
/// This test reproduces the bus error from align.wast
/// WASM allows specifying alignment hints smaller than natural alignment,
/// e.g., f32.store align=1 means "this address may not be 4-byte aligned"
test "f32 store/load with align=1" {
  // This is a minimal reproduction of the align.wast f32_align_switch function
  // It stores an f32 with align=1 hint, then loads it back
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (result f32)
    #|    (f32.store align=1 (i32.const 0) (f32.const 10.0))
    #|    (f32.load align=1 (i32.const 0))
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
    [], // param_types
    [@types.ValueType::F32], // result_types
    4096L, // mem_size
  )
  guard jit_module is Some(jm) else { return }
  let func = jm.get_func_by_name("test")
  guard func is Some(f) else { return }

  // This call may trigger Bus Error on AArch64 if the memory base
  // is not properly aligned for f32 access with align=1 hint
  let @jit.Single((result : Float)) = jm.call_with_context_poly(f, ())
  inspect(@types.Value::F32(result), content="F32(10)")
}

///|
/// Test f64 with align=1 - most likely to trigger bus error
/// since f64 requires 8-byte natural alignment
test "f64 store/load with align=1" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (result f64)
    #|    (f64.store align=1 (i32.const 0) (f64.const 10.0))
    #|    (f64.load align=1 (i32.const 0))
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
    [@types.ValueType::F64],
    4096L,
  )
  guard jit_module is Some(jm) else { return }
  let func = jm.get_func_by_name("test")
  guard func is Some(f) else { return }
  let @jit.Single((result : Double)) = jm.call_with_context_poly(f, ())
  inspect(result, content="10")
}

///|
/// Test i32 with align=1 at an unaligned address (offset 1)
/// This is more likely to actually trigger the bus error
test "i32 store/load at unaligned address" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (result i32)
    #|    (i32.store align=1 (i32.const 1) (i32.const 42))
    #|    (i32.load align=1 (i32.const 1))
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
    [@types.ValueType::I32],
    4096L,
  )
  guard jit_module is Some(jm) else { return }
  let func = jm.get_func_by_name("test")
  guard func is Some(f) else { return }
  let @jit.Single((result : Int)) = jm.call_with_context_poly(f, ())
  inspect(result, content="42")
}

///|
/// Test i64 at unaligned address (offset 3)
/// i64 requires 8-byte alignment, offset 3 is not aligned
test "i64 store/load at unaligned address" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (result i64)
    #|    (i64.store align=1 (i32.const 3) (i64.const 123456789))
    #|    (i64.load align=1 (i32.const 3))
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
    [@types.ValueType::I64],
    4096L,
  )
  guard jit_module is Some(jm) else { return }
  let func = jm.get_func_by_name("test")
  guard func is Some(f) else { return }
  let @jit.Single((result : Int64)) = jm.call_with_context_poly(f, ())
  inspect(result, content="123456789")
}

///|
/// Test f64 at unaligned address (offset 5)
/// f64 requires 8-byte alignment, offset 5 is definitely unaligned
test "f64 store/load at offset 5" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (result f64)
    #|    (f64.store align=1 (i32.const 5) (f64.const 3.14159))
    #|    (f64.load align=1 (i32.const 5))
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
    [@types.ValueType::F64],
    4096L,
  )
  guard jit_module is Some(jm) else { return }
  let func = jm.get_func_by_name("test")
  guard func is Some(f) else { return }
  let @jit.Single((result : Double)) = jm.call_with_context_poly(f, ())
  // Note: f64 has limited precision for comparison
  inspect(result, content="3.14159")
}
