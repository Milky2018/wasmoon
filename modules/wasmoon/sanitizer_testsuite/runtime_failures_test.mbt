///|
test "valid capacity denial is catchable and leaves the process usable" {
  let oversized = @wat.parse("(module (memory i64 281474976710656))")
  @validator.validate_module(oversized)
  let denied = try {
    let (store, _) = @executor.instantiate_module_with_init(oversized)
    store.close()
    false
  } catch {
    MemoryMinimumExceedsLimits(_) => true
    _ => false
  }
  inspect(denied, content="true")
  let valid = @wat.parse(
    "(module (func (export \"run\") (result i32) i32.const 42))",
  )
  @validator.validate_module(valid)
  let (store, instance) = @executor.instantiate_module_with_init(valid)
  defer store.close()
  debug_inspect(
    @executor.call_exported_func(store, instance, "run", []),
    content="[I32(42)]",
  )
}

///|
test "both instantiation entry points preserve table capacity failures" {
  let module_ = @wat.parse("(module (table i64 2147483648 funcref))")
  @validator.validate_module(module_)
  for initialized in [false, true] {
    let denied = try {
      let (store, _) = if initialized {
        @executor.instantiate_module_with_init(module_)
      } else {
        @executor.instantiate_module(module_)
      }
      store.close()
      false
    } catch {
      TableAllocationFailed => true
      _ => false
    }
    inspect(denied, content="true")
  }
}

///|
test "memory and table constructors reject invalid host arguments without aborting" {
  for page_size in [-1, 31] {
    let rejected = try {
      @runtime.Memory::Memory(0, None, page_size_log2=page_size) |> ignore
      false
    } catch {
      InvalidMemoryType(_) => true
      _ => false
    }
    inspect(rejected, content="true")
  }
  let shared_rejected = try {
    @runtime.Memory::Memory(0, None, is_shared=true) |> ignore
    false
  } catch {
    InvalidMemoryType(_) => true
    _ => false
  }
  inspect(shared_rejected, content="true")
  let memory_rejected = try {
    @runtime.Memory::Memory(2, Some(1)) |> ignore
    false
  } catch {
    InvalidMemoryType(_) => true
    _ => false
  }
  inspect(memory_rejected, content="true")
  let table_rejected = try {
    @runtime.Table::Table(FuncRef, 2, Some(1)) |> ignore
    false
  } catch {
    InvalidTableType(_) => true
    _ => false
  }
  inspect(table_rejected, content="true")
  let store = @runtime.Store::Store()
  defer store.close()
  let missing = try {
    store.get_memory(0) |> ignore
    false
  } catch {
    UndefinedElement => true
    _ => false
  }
  inspect(missing, content="true")
  let memory = @runtime.Memory::Memory(0, Some(1))
  let address = store.alloc_mem(memory)
  inspect(store.get_memory(address).byte_len(), content="0")
}

///|
test "growth denial preserves existing memory and table contents" {
  let store = @runtime.Store::Store()
  defer store.close()
  let memory = @runtime.Memory::Memory(1, Some(2))
  store.alloc_mem(memory) |> ignore
  memory.store_byte(0, b'Q')
  inspect(memory.grow(2), content="-1")
  inspect(memory.load_byte(0).to_int(), content="81")
  inspect(memory.grow(1), content="1")
  inspect(memory.load_byte(0).to_int(), content="81")
  let table = @runtime.Table::Table(FuncRef, 1, Some(2))
  table.set(0, FuncRef(17))
  inspect(table.grow(2, Null), content="-1")
  debug_inspect(table.get(0), content="FuncRef(17)")
  inspect(table.grow(1, Null), content="1")
  debug_inspect(table.get(0), content="FuncRef(17)")
}

///|
test "native GC allocation denial preserves existing roots and permits reuse" {
  let store = lifecycle_store(true)
  defer store.close()
  let existing = store.alloc_struct(0, [I32(37)])
  let lease = store.pin_gc_roots([StructRef(existing)])
  defer lease.release()
  @wasmoon_jit.gc_debug_set_fail_alloc(1)
  defer @wasmoon_jit.gc_debug_set_fail_alloc(0)
  let failed = try {
    store.alloc_struct(0, [I32(99)]) |> ignore
    false
  } catch {
    OutOfMemory => true
    _ => false
  }
  inspect(failed, content="true")
  @wasmoon_jit.gc_debug_set_fail_alloc(0)
  let next = store.alloc_struct(0, [I32(42)])
  debug_inspect(store.struct_get(existing, 0), content="I32(37)")
  debug_inspect(store.struct_get(next, 0), content="I32(42)")
}

///|
test "host failures stay distinct from guest traps and subsequent calls succeed" {
  let source =
    #|(module
    #|  (import "host" "value" (func $host (result i32)))
    #|  (func (export "run") (result i32) call $host)
    #|  (func (export "trap") unreachable))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  for native in [false, true] {
    let store = if native { @runtime.Store::with_c_heap() } else { Store() }
    let linker = @runtime.Linker::with_store(store)
    defer linker.close()
    let reject = Ref(true)
    linker.add_host_func(
      "host",
      "value",
      fn(_) raise @runtime.RuntimeError {
        if reject.val {
          raise OutOfMemory
        }
        [I32(42)]
      },
      func_type={ params: [], results: [I32], },
    )
    let instance = @executor.instantiate_with_linker(linker, "guest", module_)
    if native {
      let context = build_gc_root_context(module_, instance, store)
      defer context.jit_module.close()
      context.install_hostcall_dispatcher(store, instance)
      let failed = try {
        context.call_core_func(store, instance, 1, []) |> ignore
        false
      } catch {
        HostInvocation(error) => error is OutOfMemory
        _ => false
      }
      inspect(failed, content="true")
      let trapped = try {
        context.call_core_func(store, instance, 2, []) |> ignore
        false
      } catch {
        Trap(_) => true
        _ => false
      }
      inspect(trapped, content="true")
      reject.val = false
      debug_inspect(
        context.call_core_func(store, instance, 1, []),
        content="[I32(42)]",
      )
    } else {
      let failure = @executor.call_exported_func_with_options(
        store,
        instance,
        "run",
        [],
      )
      let host_error = match failure {
        Err(error) =>
          error.runtime_error is Some(OutOfMemory) &&
          error.kind is HostInvocation
        _ => false
      }
      inspect(host_error, content="true")
      let trap = @executor.call_exported_func_with_options(
        store,
        instance,
        "trap",
        [],
      )
      let guest_trap = match trap {
        Err(error) =>
          error.runtime_error is Some(Unreachable) && error.kind is Trap
        _ => false
      }
      inspect(guest_trap, content="true")
      reject.val = false
      debug_inspect(
        @executor.call_exported_func(store, instance, "run", []),
        content="[I32(42)]",
      )
    }
  }
}

///|
extern "c" fn runtime_fail_native_allocation(attempt : Int32) -> Unit = "wasmoon_native_fail_allocation_for_tests"

///|
test "component runtime preparation denial is typed and releases partial owners" {
  for attempt in 1..<=6 {
    runtime_fail_native_allocation(attempt)
    let denied = try {
      let runtime = @component.ComponentRuntime::ComponentRuntime()
      runtime.close()
      false
    } catch {
      ResourceExhausted(_) => true
      _ => false
    }
    runtime_fail_native_allocation(0)
    inspect(denied, content="true")
    let runtime = @component.ComponentRuntime::ComponentRuntime()
    defer runtime.close()
    let instance = runtime.instantiate(
      "recovered",
      component_runtime_facade_fixture(),
    )
    debug_inspect(
      instance.bind("increment").call([U32(41U)]),
      content="[U32(42)]",
    )
  }
}

///|
test "native memory allocation and growth denial leave the Store reusable" {
  let store = @runtime.Store::Store()
  defer store.close()
  runtime_fail_native_allocation(1)
  defer runtime_fail_native_allocation(0)
  let denied = try {
    @runtime.Memory::Memory(1, Some(2), is_memory64=true) |> ignore
    false
  } catch {
    OutOfMemory => true
    _ => false
  }
  inspect(denied, content="true")
  let memory = @runtime.Memory::Memory(1, Some(2), is_memory64=true)
  inspect(store.alloc_mem(memory), content="0")
  memory.store_byte(0, b'Q')
  runtime_fail_native_allocation(1)
  inspect(memory.grow(1), content="-1")
  inspect(memory.byte_len(), content="65536")
  inspect(memory.load_byte(0).to_int(), content="81")
  inspect(memory.grow(1), content="1")
  inspect(memory.byte_len(), content="131072")
}

///|
test "native table allocation denial does not publish a Store address" {
  let store = @runtime.Store::Store()
  defer store.close()
  let table = @runtime.Table::Table(FuncRef, 1, None)
  runtime_fail_native_allocation(1)
  defer runtime_fail_native_allocation(0)
  let denied = try {
    store.alloc_table(table) |> ignore
    false
  } catch {
    TableAllocationFailed => true
    _ => false
  }
  inspect(denied, content="true")
  inspect(store.counts().tables, content="0")
  inspect(store.alloc_table(table), content="0")
}

///|
test "failed capacity instantiation rolls back explicit transactions and permits reuse" {
  let invalid = @wat.parse(
    "(module (func) (memory 1) (memory i64 281474976710656))",
  )
  let valid = @wat.parse(
    "(module (func (export \"run\") (result i32) i32.const 42))",
  )
  @validator.validate_module(invalid)
  @validator.validate_module(valid)
  for native in [false, true] {
    let store = if native { @runtime.Store::with_c_heap() } else { Store() }
    let linker = @runtime.Linker::with_store(store)
    defer linker.close()
    for _ in 0..<20 {
      let transaction = @runtime.InstantiationTransaction::new()
      linker.register_rollback(transaction.registrar())
      let denied = try {
        @executor.instantiate_with_linker(linker, "failed", invalid) |> ignore
        false
      } catch {
        MemoryMinimumExceedsLimits(_) => true
        _ => false
      }
      transaction.rollback()
      inspect(denied, content="true")
      debug_inspect(
        (store.counts().funcs, store.counts().mems, store.counts().instances),
        content="(0, 0, 0)",
      )
    }
    let instance = @executor.instantiate_with_linker(linker, "valid", valid)
    debug_inspect(
      @executor.call_exported_func(store, instance, "run", []),
      content="[I32(42)]",
    )
  }
}

///|
test "native heap activation rejects live interpreter objects without losing them" {
  let store = lifecycle_store(false)
  defer store.close()
  let object = store.alloc_struct(0, [I32(37)])
  let denied = try {
    store.enable_c_heap()
    false
  } catch {
    HeapRepresentationInUse => true
    _ => false
  }
  inspect(denied, content="true")
  inspect(store.native_heap() is None, content="true")
  debug_inspect(store.struct_get(object, 0), content="I32(37)")
  inspect(store.collect_garbage(), content="1")
  store.enable_c_heap()
  let next = store.alloc_struct(0, [I32(42)])
  debug_inspect(store.struct_get(next, 0), content="I32(42)")
}

///|
test "native exception delivery returns through MoonBit cleanup before unwinding guest code" {
  let source =
    #|(module
    #|  (import "host" "callback" (func $callback))
    #|  (tag $e (param i32))
    #|  (func (export "run") (result i32)
    #|    (block $caught (result i32)
    #|      (try_table (catch $e $caught) (call $callback))
    #|      i32.const 0)))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  let store = @runtime.Store::with_c_heap()
  let linker = @runtime.Linker::with_store(store)
  defer linker.close()
  linker.add_host_func("host", "callback", fn(_) { [] })
  let instance = @executor.instantiate_with_linker(linker, "guest", module_)
  let context = build_gc_root_context(module_, instance, store)
  defer context.jit_module.close()
  let cleaned = Ref(false)
  context.jit_module.set_hostcall_callback(fn() {
    defer {
      cleaned.val = true
    }
    context.jit_module.throw_exception_values(0, [37L]) catch {
      _ => return HostcallTrap(9)
    }
    HostcallCompleted
  })
  debug_inspect(
    context.call_core_func(store, instance, 1, []),
    content="[I32(37)]",
  )
  inspect(cleaned.val, content="true")
}

///|
test "staged exception allocation denial runs cleanup and permits the next call" {
  let source =
    #|(module (import "host" "callback" (func $callback)) (tag $e (param i32))
    #|  (func (export "run") (result i32)
    #|    (block $caught (result i32)
    #|      (try_table (catch $e $caught) (call $callback)) i32.const 0)))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  let store = @runtime.Store::with_c_heap()
  let linker = @runtime.Linker::with_store(store)
  defer linker.close()
  linker.add_host_func("host", "callback", fn(_) { [] })
  let instance = @executor.instantiate_with_linker(linker, "guest", module_)
  let context = build_gc_root_context(module_, instance, store)
  defer context.jit_module.close()
  let outside = try {
    context.jit_module.throw_exception_values(0, [1L])
    false
  } catch {
    InvalidBinding(_) => true
    _ => false
  }
  inspect(outside, content="true")
  let deny = Ref(true)
  let cleaned = Ref(false)
  context.jit_module.set_hostcall_callback(fn() {
    defer {
      cleaned.val = true
    }
    if deny.val {
      runtime_fail_native_allocation(1)
    }
    context.jit_module.throw_exception_values(0, [37L]) catch {
      ExceptionPayloadAllocationFailed => return HostcallTrap(9)
      _ => return HostcallTrap(8)
    }
    HostcallCompleted
  })
  let failed = try {
    context.call_core_func(store, instance, 1, []) |> ignore
    false
  } catch {
    Trap(message) => message.contains("out of memory")
    _ => false
  }
  inspect(failed, content="true")
  inspect(cleaned.val, content="true")
  deny.val = false
  cleaned.val = false
  debug_inspect(
    context.call_core_func(store, instance, 1, []),
    content="[I32(37)]",
  )
  inspect(cleaned.val, content="true")
}

///|
test "a host callback may clear its registration before returning host exit" {
  let module_ = @wat.parse(
    "(module (import \"host\" \"callback\" (func $callback)) (func (export \"run\") (result i32) call $callback i32.const 42))",
  )
  @validator.validate_module(module_)
  let store = @runtime.Store::with_c_heap()
  let linker = @runtime.Linker::with_store(store)
  defer linker.close()
  linker.add_host_func("host", "callback", fn(_) { [] })
  let instance = @executor.instantiate_with_linker(linker, "guest", module_)
  let context = build_gc_root_context(module_, instance, store)
  defer context.jit_module.close()
  let cleaned = Ref(false)
  context.jit_module.set_hostcall_callback(fn() {
    defer {
      cleaned.val = true
    }
    context.jit_module.clear_hostcall_callback()
    HostcallExit(23)
  })
  let exited = try {
    context.call_core_func(store, instance, 1, []) |> ignore
    false
  } catch {
    Exit(23) => true
    _ => false
  }
  inspect(exited, content="true")
  inspect(cleaned.val, content="true")
  context.install_hostcall_dispatcher(store, instance)
  debug_inspect(
    context.call_core_func(store, instance, 1, []),
    content="[I32(42)]",
  )
}

///|
test "an imported exception preserves a Store tag absent from the caller module" {
  let callee = @wat.parse(
    "(module (tag (export \"e\") (param i32)) (func (export \"throw\") i32.const 37 throw 0))",
  )
  let caller_source =
    #|(module (import "callee" "throw" (func $throw)) (tag $unrelated)
    #|  (func (export "run") (result exnref)
    #|    (block $caught (result exnref)
    #|      (try_table (catch_all_ref $caught) (call $throw)) ref.null exn)))
  let caller = @wat.parse(caller_source)
  @validator.validate_module(callee)
  @validator.validate_module(caller)
  let store = @runtime.Store::with_c_heap()
  let linker = @runtime.Linker::with_store(store)
  defer linker.close()
  let callee_instance = @executor.instantiate_with_linker(
    linker, "callee", callee,
  )
  let instance = @executor.instantiate_with_linker(linker, "caller", caller)
  let context = build_gc_root_context(caller, instance, store)
  defer context.jit_module.close()
  context.install_hostcall_dispatcher(store, instance)
  guard context.call_core_func(store, instance, 1, []) is [ExnRef(index)] else {
    fail("expected an exception snapshot")
  }
  let exception = store.get_exn(index)
  assert_eq(exception.tag_addr, callee_instance.tag_addrs[0])
  debug_inspect(exception.values, content="[I32(37)]")
}

///|
test "component native preparation denial rolls back and preserves its resource category" {
  let bytes = component_runtime_facade_fixture()
  let mut rejected = 0
  for attempt in 1..<=24 {
    let runtime = @component.ComponentRuntime::ComponentRuntime()
    defer runtime.close()
    runtime_fail_native_allocation(attempt)
    let result = try {
      runtime.instantiate("first", bytes) |> ignore
      None
    } catch {
      error => Some(error)
    }
    runtime_fail_native_allocation(0)
    if result is Some(error) {
      rejected += 1
      guard error is ResourceExhausted(_) else {
        fail("native resource failure lost its category: \{error}")
      }
    }
    let instance = runtime.instantiate("recovered", bytes)
    debug_inspect(
      instance.bind("increment").call([U32(41U)]),
      content="[U32(42)]",
    )
  }
  assert_true(rejected >= 4)
}

///|
test "closed JIT module preparation returns errors instead of reporting no-op success" {
  let module_ = @jit.JITModule::JITModule()
  module_.close()
  let operations : Array[() -> Unit raise @wasmoon_jit.NativeSetupError] = [
    () => module_.set_memory_pointers([]),
    () => module_.init_shared_tables([], []),
    () => module_.setup_segments([], []),
  ]
  for operation in operations {
    let rejected = try {
      operation()
      false
    } catch {
      InvalidBinding(_) => true
      _ => false
    }
    inspect(rejected, content="true")
  }
  let rejected = try {
    module_.gc_begin_frame(0L)
    false
  } catch {
    JITTrap(message) => message == "missing JIT context"
    _ => false
  }
  inspect(rejected, content="true")
  module_.close()
}
