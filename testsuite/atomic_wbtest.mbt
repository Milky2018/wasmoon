// Tests for atomic (0xFE) instructions

///|
fn exported_func_index(mod_ : @types.Module, name : String) -> Int {
  for exp in mod_.exports {
    if exp.name == name {
      match exp.desc {
        Func(idx) => return idx
        _ => ()
      }
    }
  }
  abort("Function '\{name}' not found")
}

///|
test "atomics: i32.atomic.store + i32.atomic.load (interp & jit)" {
  let bytes : Array[Byte] = [
    // Magic \0asm
    0x00, 0x61, 0x73, 0x6d,
    // Version 1
     0x01, 0x00, 0x00, 0x00,

    // Type section
     0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7f,

    // Function section
     0x03, 0x02, 0x01, 0x00,

    // Memory section: min=1, max=1
     0x05, 0x04, 0x01, 0x01, 0x01, 0x01,

    // Export section: (export "run" (func 0))
     0x07, 0x07, 0x01, 0x03, 0x72, 0x75, 0x6e, 0x00, 0x00,

    // Code section
     0x0a, 0x12, 0x01,
    // func body size
     0x10,
    // locals
     0x00,
    // i32.const 0
     0x41, 0x00,
    // i32.const 42
     0x41, 0x2a,
    // i32.atomic.store (0xFE 0x17) memarg(flags=2, offset=0)
     0xfe, 0x17, 0x02, 0x00,
    // i32.const 0
     0x41, 0x00,
    // i32.atomic.load (0xFE 0x10) memarg(flags=2, offset=0)
     0xfe, 0x10, 0x02, 0x00,
    // end
     0x0b,
  ]
  let mod_ = @parser.parse_module(Bytes::from_array(bytes))
  @validator.validate_module(mod_)
  let (store, instance) = @executor.instantiate_module(mod_)
  let interp = @executor.call_exported_func(store, instance, "run", [])
  inspect(interp[0], content="I32(42)")
  let func_idx = exported_func_index(mod_, "run")
  let type_idx = mod_.funcs[func_idx]
  let func_type = mod_.get_func_type(type_idx)
  let jit = run_jit(
    mod_,
    "run",
    func_idx,
    [],
    func_type.params,
    func_type.results,
  )
  let jit_vals = match jit {
    Ok(v) => v
    Err(e) => return fail("JIT error: \{e}")
  }
  inspect(jit_vals[0], content="I32(42)")
}

///|
test "atomics: i32.atomic.rmw.add returns old value (interp & jit)" {
  let bytes : Array[Byte] = [
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,

    // Type section: () -> i32
     0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7f,
    // Function section
     0x03, 0x02, 0x01, 0x00,
    // Memory section: min=1, max=1
     0x05, 0x04, 0x01, 0x01, 0x01, 0x01,
    // Export section
     0x07, 0x07, 0x01, 0x03, 0x72, 0x75, 0x6e, 0x00, 0x00,

    // Code section
     0x0a, 0x14, 0x01,
    // body size
     0x12, 0x00,
    // i32.const 0
     0x41, 0x00,
    // i32.const 7
     0x41, 0x07,
    // i32.atomic.store
     0xfe, 0x17, 0x02, 0x00,
    // i32.const 0
     0x41, 0x00,
    // i32.const 5
     0x41, 0x05,
    // i32.atomic.rmw.add
     0xfe, 0x1e, 0x02, 0x00, 0x0b,
  ]
  let mod_ = @parser.parse_module(Bytes::from_array(bytes))
  @validator.validate_module(mod_)
  let (store, instance) = @executor.instantiate_module(mod_)
  let interp = @executor.call_exported_func(store, instance, "run", [])
  inspect(interp[0], content="I32(7)")
  let func_idx = exported_func_index(mod_, "run")
  let type_idx = mod_.funcs[func_idx]
  let func_type = mod_.get_func_type(type_idx)
  let jit = run_jit(
    mod_,
    "run",
    func_idx,
    [],
    func_type.params,
    func_type.results,
  )
  let jit_vals = match jit {
    Ok(v) => v
    Err(e) => return fail("JIT error: \{e}")
  }
  inspect(jit_vals[0], content="I32(7)")
}

///|
test "atomics: i32.atomic.rmw.cmpxchg updates memory (interp & jit)" {
  let bytes : Array[Byte] = [
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,

    // Type section: () -> i32
     0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7f,
    // Function section
     0x03, 0x02, 0x01, 0x00,
    // Memory section: min=1, max=1
     0x05, 0x04, 0x01, 0x01, 0x01, 0x01,
    // Export section
     0x07, 0x07, 0x01, 0x03, 0x72, 0x75, 0x6e, 0x00, 0x00,

    // Code section
     0x0a, 0x1d, 0x01,
    // body size
     0x1b, 0x00,
    // i32.const 0
     0x41, 0x00,
    // i32.const 9
     0x41, 0x09,
    // i32.atomic.store
     0xfe, 0x17, 0x02, 0x00,
    // i32.const 0
     0x41, 0x00,
    // i32.const 9
     0x41, 0x09,
    // i32.const 11
     0x41, 0x0b,
    // i32.atomic.rmw.cmpxchg
     0xfe, 0x48, 0x02, 0x00,
    // drop old value
     0x1a,
    // i32.const 0
     0x41, 0x00,
    // i32.atomic.load
     0xfe, 0x10, 0x02, 0x00, 0x0b,
  ]
  let mod_ = @parser.parse_module(Bytes::from_array(bytes))
  @validator.validate_module(mod_)
  let (store, instance) = @executor.instantiate_module(mod_)
  let interp = @executor.call_exported_func(store, instance, "run", [])
  inspect(interp[0], content="I32(11)")
  let func_idx = exported_func_index(mod_, "run")
  let type_idx = mod_.funcs[func_idx]
  let func_type = mod_.get_func_type(type_idx)
  let jit = run_jit(
    mod_,
    "run",
    func_idx,
    [],
    func_type.params,
    func_type.results,
  )
  let jit_vals = match jit {
    Ok(v) => v
    Err(e) => return fail("JIT error: \{e}")
  }
  inspect(jit_vals[0], content="I32(11)")
}
