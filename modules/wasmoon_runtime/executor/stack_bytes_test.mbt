///|
fn byte_limited_instance(
  module_ : @types.Module,
  bytes : Int64,
) -> (@runtime.Store, @runtime.ModuleInstance) raise {
  let store = @runtime.Store(
    interpreter_limits=@runtime.InterpreterLimits::new(
      max_stack_bytes=Some(bytes),
    ),
  )
  let instance = @executor.instantiate_module_with_imports(
    store,
    module_,
    Imports(store),
  )
  (store, instance)
}

///|
test "tail replacement and guest exception unwinding return byte reservations" {
  let store = @runtime.Store(
    interpreter_limits=@runtime.InterpreterLimits::new(
      max_frames=1,
      max_stack_bytes=Some(384L),
    ),
  )
  defer store.close()
  let tail = @executor.instantiate_module_with_imports(
    store,
    @types.Module::simple(
      [I32],
      [I32],
      [
        LocalGet(0),
        I32Eqz,
        If(Value(I32), [I32Const(42)], [
          LocalGet(0),
          I32Const(1),
          I32Sub,
          ReturnCall(0),
        ]),
      ],
      "tail",
    ),
    Imports(store),
  )
  assert_eq(@executor.call_exported_func(store, tail, "tail", [I32(10000)]), [
    I32(42),
  ])
  let module_ = @wat.parse(
    (
      #|(module (tag $e) (func (export "run") (param i32) (result i32)
      #| (loop $again
      #|  (block $caught (try_table (catch_all $caught) throw $e))
      #|  local.get 0 i32.const 1 i32.sub local.tee 0 br_if $again)
      #| i32.const 42))
    ),
  )
  let (store, instance) = byte_limited_instance(module_, 480L)
  defer store.close()
  assert_eq(@executor.call_exported_func(store, instance, "run", [I32(1000)]), [
    I32(42),
  ])
}

///|
test "stack byte admission includes frame metadata and locals independently of depth" {
  for locals in [0, 8] {
    let module_ = deep_call_module()
    module_.codes[0] = {
      ..module_.codes[0],
      locals: ReadOnlyArray::from_array(Array::make(locals, I64)),
    }
    let (store, instance) = byte_limited_instance(module_, 1024L)
    defer store.close()
    if locals == 0 {
      assert_eq(
        @executor.call_exported_func(store, instance, "count", [I32(2)]),
        [I32(2)],
      )
    } else {
      try
        @executor.call_exported_func(store, instance, "count", [I32(2)])
      catch {
        InterpreterStackBytesExceeded => ()
        error => fail(error.to_string())
      } noraise {
        _ => fail("locals escaped the byte budget")
      }
    }
    assert_eq(
      @executor.call_exported_func(store, instance, "count", [I32(0)]),
      [I32(0)],
    )
  }
  for bytes in [0L, -1L] {
    try @runtime.InterpreterLimits::new(max_stack_bytes=Some(bytes)) catch {
      TypeMismatch => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("invalid byte limit accepted")
    }
  }
}

///|
test "shallow operand and control stacks meet exact accounted byte boundaries" {
  let operands : Array[@types.Instruction] = Array::make(30, I32Const(42))
  for _ in 0..<30 {
    operands.push(Drop)
  }
  let mut control : @types.Instruction = Nop
  for _ in 0..<10 {
    control = Block(Empty, [control])
  }
  for body in [ReadOnlyArray::from_array(operands), [control]] {
    for bytes in [1119L, 1120L] {
      let (store, instance) = byte_limited_instance(
        @types.Module::simple([], [], body, "run"),
        bytes,
      )
      defer store.close()
      let failed = try {
        @executor.call_exported_func(store, instance, "run", []) |> ignore
        false
      } catch {
        InterpreterStackBytesExceeded => true
        error => fail(error.to_string())
      }
      assert_eq(failed, bytes == 1119L)
    }
  }
}

///|
test "cooperative and host suspension retain the stack byte reservation" {
  let body : Array[@types.Instruction] = Array::make(30, Nop)
  body.push(I32Const(42))
  for bytes in [191L, 192L] {
    let (store, instance) = byte_limited_instance(
      @types.Module::simple([], [I32], ReadOnlyArray::from_array(body), "run"),
      bytes,
    )
    defer store.close()
    let mut outcome = @executor.call_func_by_index_resumable(
      store,
      instance,
      0,
      [],
      _ => None,
      cooperative=true,
      cooperative_quantum=3,
    )
    let mut failed = false
    let mut pauses = 0
    while outcome is Suspended(CooperativeYield, continuation) {
      pauses += 1
      outcome = continuation.continue_execution() catch {
        InterpreterStackBytesExceeded => {
          failed = true
          break
        }
        error => fail(error.to_string())
      }
    }
    assert_eq(pauses, 10)
    assert_eq(failed, bytes == 191L)
    if !failed {
      guard outcome is Returned(values) else { fail("unexpected suspension") }
      assert_eq(values, [I32(42)])
    }
  }
  let store = @runtime.Store(
    interpreter_limits=@runtime.InterpreterLimits::new(
      max_stack_bytes=Some(192L),
    ),
  )
  defer store.close()
  let ready = Ref(false)
  let host = store.alloc_host_func(
    fn(_) raise @runtime.RuntimeError {
      if !ready.val {
        raise Unreachable
      }
      []
    },
    func_type={ params: [], results: [], },
    type_idx=0,
  )
  let module_ = @wat.parse(
    "(module (import \"h\" \"pause\" (func)) (func (export \"run\") (result i32) call 0 call 0 i32.const 42))",
  )
  let imports = @runtime.Imports::Imports(store)
  imports.add_func("h", "pause", host)
  let instance = @executor.instantiate_module_with_imports(
    store, module_, imports,
  )
  let mut outcome = @executor.call_func_by_index_resumable(
    store,
    instance,
    1,
    [],
    _ => Some(1L),
  )
  for _ in 0..<5 {
    guard outcome is Suspended(HostCall(1L), continuation) else {
      fail("missing host pause")
    }
    outcome = continuation.continue_execution()
  }
  ready.val = true
  guard outcome is Suspended(_, continuation) else {
    fail("missing final host pause")
  }
  guard continuation.continue_execution() is Returned(values) else {
    fail("unexpected suspension")
  }
  assert_eq(values, [I32(42)])
}

///|
test "host reentry has its own byte budget and count limits remain independent" {
  let store = @runtime.Store(
    interpreter_limits=@runtime.InterpreterLimits::new(
      max_stack_bytes=Some(192L),
      max_frames=1,
    ),
  )
  defer store.close()
  let leaf = @executor.instantiate_module_with_imports(
    store,
    @types.Module::simple([], [I32], [I32Const(42)], "leaf"),
    Imports(store),
  )
  let host = store.alloc_host_func(
    fn(_) raise @runtime.RuntimeError {
      @executor.call_func_by_index(store, leaf, 0, [])
    },
    func_type={ params: [], results: [I32], },
    type_idx=0,
  )
  let imports = @runtime.Imports::Imports(store)
  imports.add_func("h", "leaf", host)
  let instance = @executor.instantiate_module_with_imports(
    store,
    @wat.parse(
      "(module (import \"h\" \"leaf\" (func (result i32))) (func (export \"run\") (result i32) call 0))",
    ),
    imports,
  )
  assert_eq(@executor.call_exported_func(store, instance, "run", []), [I32(42)])
  let (count_store, count_instance) = limited_count(
    @runtime.InterpreterLimits::new(
      max_frames=1,
      max_stack_bytes=Some(1000000L),
    ),
  )
  defer count_store.close()
  try
    @executor.call_exported_func(count_store, count_instance, "count", [I32(1)])
  catch {
    CallStackExhausted => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("byte budget disabled the frame limit")
  }
}
