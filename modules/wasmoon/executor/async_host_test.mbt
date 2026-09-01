///|
/// Build the public-API fixture shared by async host-call tests.
fn async_host_test_module() -> @types.Module {
  let func_type : @types.FuncType = { params: [I32], results: [I32], }
  {
    ..@types.Module::empty(),
    types: [@types.SubType::from_func(func_type)],
    type_rec_groups: [0],
    imports: [{ mod_name: "host", name: "double", desc: Func(0), }],
    funcs: [0],
    codes: [{ locals: [], body: [LocalGet(0), Call(0), I32Const(1), I32Add], }],
    exports: [{ name: "run", desc: Func(1), }],
  }
}

///|
fn async_host_gc_test_module() -> @types.Module {
  let host_type : @types.FuncType = { params: [], results: [], }
  let run_type : @types.FuncType = { params: [], results: [I32], }
  let struct_type : @types.StructType = {
    fields: [{ storage_type: Val(I32), mutable: false, }],
  }
  {
    ..@types.Module::empty(),
    types: [
      @types.SubType::from_func(host_type),
      @types.SubType::simple(Struct(struct_type)),
      @types.SubType::from_func(run_type),
    ],
    type_rec_groups: [0, 1, 2],
    imports: [{ mod_name: "host", name: "collect", desc: Func(0), }],
    funcs: [2],
    codes: [
      {
        locals: [RefNullStruct(1)],
        body: [
          I32Const(42),
          StructNew(1),
          LocalSet(0),
          Call(0),
          LocalGet(0),
          StructGet(1, 0),
        ],
      },
    ],
    exports: [{ name: "run", desc: Func(1), }],
  }
}

///|
fn async_host_start_test_module() -> @types.Module {
  let func_type : @types.FuncType = { params: [], results: [], }
  {
    ..@types.Module::empty(),
    types: [@types.SubType::from_func(func_type)],
    type_rec_groups: [0],
    imports: [{ mod_name: "host", name: "start", desc: Func(0), }],
    funcs: [0],
    codes: [{ locals: [], body: [Call(0)], }],
    start: Some(1),
  }
}

///|
fn async_host_gc_cancel_test_module() -> @types.Module {
  let host_type : @types.FuncType = { params: [], results: [], }
  let run_type : @types.FuncType = { params: [RefNullStruct(1)], results: [], }
  let struct_type : @types.StructType = {
    fields: [{ storage_type: Val(I32), mutable: false, }],
  }
  {
    ..@types.Module::empty(),
    types: [
      @types.SubType::from_func(host_type),
      @types.SubType::simple(Struct(struct_type)),
      @types.SubType::from_func(run_type),
    ],
    type_rec_groups: [0, 1, 2],
    imports: [{ mod_name: "host", name: "wait", desc: Func(0), }],
    funcs: [2],
    codes: [{ locals: [], body: [Call(0)], }],
    exports: [{ name: "run", desc: Func(1), }],
  }
}

///|
fn async_host_twice_test_module() -> @types.Module {
  let func_type : @types.FuncType = { params: [I32], results: [I32], }
  {
    ..@types.Module::empty(),
    types: [@types.SubType::from_func(func_type)],
    type_rec_groups: [0],
    imports: [{ mod_name: "host", name: "increment", desc: Func(0), }],
    funcs: [0],
    codes: [{ locals: [], body: [LocalGet(0), Call(0), Call(0)], }],
    exports: [{ name: "run", desc: Func(1), }],
  }
}

///|
fn async_host_argument_root_test_module() -> @types.Module {
  let struct_type : @types.StructType = {
    fields: [{ storage_type: Val(I32), mutable: false, }],
  }
  let host_type : @types.FuncType = {
    params: [RefNullStruct(0)],
    results: [I32],
  }
  let run_type : @types.FuncType = { params: [], results: [I32], }
  {
    ..@types.Module::empty(),
    types: [
      @types.SubType::simple(Struct(struct_type)),
      @types.SubType::from_func(host_type),
      @types.SubType::from_func(run_type),
    ],
    type_rec_groups: [0, 1, 2],
    imports: [{ mod_name: "host", name: "read", desc: Func(1), }],
    funcs: [2],
    codes: [{ locals: [], body: [I32Const(42), StructNew(0), Call(0)], }],
    exports: [{ name: "run", desc: Func(1), }],
  }
}

///|
fn async_host_throw_after_wait_test_module() -> @types.Module {
  let func_type : @types.FuncType = { params: [I32], results: [I32], }
  let tag_type : @types.FuncType = { params: [I32], results: [], }
  {
    ..@types.Module::empty(),
    types: [
      @types.SubType::from_func(func_type),
      @types.SubType::from_func(tag_type),
    ],
    type_rec_groups: [0, 1],
    imports: [{ mod_name: "host", name: "double", desc: Func(0), }],
    funcs: [0],
    codes: [{ locals: [], body: [LocalGet(0), Call(0), Throw(0)], }],
    tags: [{ type_idx: 1, }],
    exports: [{ name: "run", desc: Func(1), }],
  }
}

///|
async test "async host function suspends wasm without blocking the host task" {
  let events : Array[String] = []
  let host_started = @async.Semaphore(1, initial_value=0)
  let host_may_finish = @async.Semaphore(1, initial_value=0)
  let linker = @runtime.Linker::Linker()
  defer linker.close()
  linker.add_async_host_func(
    "host",
    "double",
    async fn(args) {
      events.push("host started")
      host_started.release()
      host_may_finish.acquire()
      events.push("host ready")
      match args[0] {
        I32(value) => [I32(value * 2)]
        _ => raise @runtime.TypeMismatch
      }
    },
    func_type={ params: [I32], results: [I32], },
  )
  let instance = instantiate_with_linker(
    linker,
    "guest",
    async_host_test_module(),
  )
  let result = @async.with_task_group(group => {
    let call = group.spawn(no_wait=true, () => {
      call_exported_func_async(linker.get_store(), instance, "run", [I32(20)])
    })
    host_started.acquire()
    group.spawn_bg() <| () => {
      events.push("other task ran")
      host_may_finish.release()
    }
    call.wait()
  })
  debug_inspect(result, content="[I32(41)]")
  debug_inspect(
    events,
    content="[\"host started\", \"other task ran\", \"host ready\"]",
  )
}

///|
test "sync wasm call rejects an async host function" {
  let linker = @runtime.Linker::Linker()
  defer linker.close()
  linker.add_async_host_func(
    "host",
    "double",
    async fn(args) {
      @async.sleep(0)
      args
    },
    func_type={ params: [I32], results: [I32], },
  )
  let instance = instantiate_with_linker(
    linker,
    "guest",
    async_host_test_module(),
  )
  let error = try
    call_exported_func(linker.get_store(), instance, "run", [I32(20)])
  catch {
    error => error
  } noraise {
    _ => fail("expected the synchronous call to fail")
  }
  inspect(error, content="async host function requires an async wasm call")
}

///|
async test "async host function preserves its runtime error" {
  let linker = @runtime.Linker::Linker()
  defer linker.close()
  linker.add_async_host_func(
    "host",
    "double",
    async fn(_args) {
      @async.sleep(1)
      raise @runtime.DivisionByZero
    },
    func_type={ params: [I32], results: [I32], },
  )
  let instance = instantiate_with_linker(
    linker,
    "guest",
    async_host_test_module(),
  )
  let error = try
    call_exported_func_async(linker.get_store(), instance, "run", [I32(20)])
  catch {
    error => error
  } noraise {
    _ => fail("expected the host function to fail")
  }
  inspect(error, content="integer divide by zero")
}

///|
async test "parked interpreter continuation keeps frame GC roots alive" {
  let store = @runtime.Store::with_c_heap()
  let linker = @runtime.Linker::with_store(store)
  defer linker.close()
  linker.add_async_host_func_with_caller(
    "host",
    "collect",
    async fn(caller, _args) {
      @async.sleep(0)
      caller.store().collect_garbage() |> ignore
      []
    },
    func_type={ params: [], results: [], },
  )
  let instance = instantiate_with_linker(
    linker,
    "guest",
    async_host_gc_test_module(),
  )
  let result = call_exported_func_async(store, instance, "run", [])
  debug_inspect(result, content="[I32(42)]")
}

///|
async test "parked async host-call arguments remain GC roots" {
  let store = @runtime.Store::with_c_heap()
  let linker = @runtime.Linker::with_store(store)
  defer linker.close()
  linker.add_async_host_func_with_caller(
    "host",
    "read",
    async fn(caller, args) {
      @async.sleep(0)
      caller.store().collect_garbage() |> ignore
      match args[0] {
        StructRef(reference) => [caller.store().struct_get(reference, 0)]
        _ => raise @runtime.TypeMismatch
      }
    },
    func_type={ params: [RefNullStruct(0)], results: [I32], },
  )
  let instance = instantiate_with_linker(
    linker,
    "guest",
    async_host_argument_root_test_module(),
  )
  let result = call_exported_func_async(store, instance, "run", [])
  debug_inspect(result, content="[I32(42)]")
}

///|
async test "resumable async calls preserve wasm exceptions after suspension" {
  let linker = @runtime.Linker::Linker()
  defer linker.close()
  linker.add_async_host_func(
    "host",
    "double",
    async fn(args) {
      @async.sleep(1)
      match args[0] {
        I32(value) => [I32(value * 2)]
        _ => raise @runtime.TypeMismatch
      }
    },
    func_type={ params: [I32], results: [I32], },
  )
  let store = linker.get_store()
  let instance = instantiate_with_linker(
    linker,
    "guest",
    async_host_throw_after_wait_test_module(),
  )
  @runtime.with_async_host_call_driver(async fn(driver) {
    guard call_func_by_index_resumable_async_with_exception(
        store,
        instance,
        1,
        [I32(21)],
        driver,
      )
      is ResumableSuspended(continuation) else {
      fail("expected the imported call to suspend")
    }
    driver.wait_pending()
    guard continuation.continue_execution_with_exception()
      is ResumableThrown(tag_addr, values) else {
      fail("expected the resumed call to throw")
    }
    inspect(tag_addr == instance.tag_addrs[0], content="true")
    debug_inspect(values, content="[I32(42)]")
  })
}

///|
test "synchronous instantiation rejects an async start function" {
  let linker = @runtime.Linker::Linker()
  defer linker.close()
  linker.add_async_host_func(
    "host",
    "start",
    async fn(_args) {
      @async.sleep(0)
      []
    },
    func_type={ params: [], results: [], },
  )
  let error = try
    instantiate_with_linker(linker, "guest", async_host_start_test_module())
  catch {
    error => error
  } noraise {
    _ => fail("expected synchronous instantiation to reject async start")
  }
  inspect(error, content="async host function requires an async wasm call")
}

///|
async test "asynchronous instantiation runs an async start exactly once" {
  let calls = [0]
  let linker = @runtime.Linker::Linker()
  defer linker.close()
  linker.add_async_host_func(
    "host",
    "start",
    async fn(_args) {
      calls[0] = calls[0] + 1
      @async.sleep(1)
      []
    },
    func_type={ params: [], results: [], },
  )
  instantiate_with_linker_async(linker, "guest", async_host_start_test_module())
  |> ignore
  inspect(calls[0], content="1")
}

///|
async test "cancelling an interpreter continuation releases its GC roots" {
  let store = @runtime.Store::with_c_heap()
  let linker = @runtime.Linker::with_store(store)
  defer linker.close()
  linker.add_async_host_func(
    "host",
    "wait",
    async fn(_args) {
      @async.sleep(1000)
      []
    },
    func_type={ params: [], results: [], },
  )
  let instance = instantiate_with_linker(
    linker,
    "guest",
    async_host_gc_cancel_test_module(),
  )
  let rooted = store.alloc_struct(1, [I32(42)])
  @async.with_task_group(group => {
    let call = group.spawn(no_wait=true, allow_failure=true, () => {
      call_exported_func_async(store, instance, "run", [StructRef(rooted)])
    })
    @async.sleep(1)
    call.cancel()
    try call.wait() catch {
      _ => ()
    } noraise {
      _ => fail("expected the asynchronous call to be cancelled")
    }
  })
  inspect(store.collect_garbage(), content="1")
  inspect(store.is_gc_valid(rooted), content="false")
}

///|
async test "failed async host call releases interpreter GC roots" {
  let store = @runtime.Store::with_c_heap()
  let linker = @runtime.Linker::with_store(store)
  defer linker.close()
  linker.add_async_host_func(
    "host",
    "wait",
    async fn(_args) {
      @async.sleep(1)
      raise @runtime.DivisionByZero
    },
    func_type={ params: [], results: [], },
  )
  let instance = instantiate_with_linker(
    linker,
    "guest",
    async_host_gc_cancel_test_module(),
  )
  let rooted = store.alloc_struct(1, [I32(42)])
  let error = try
    call_exported_func_async(store, instance, "run", [StructRef(rooted)])
  catch {
    error => error
  } noraise {
    _ => fail("expected the asynchronous host function to fail")
  }
  inspect(error, content="integer divide by zero")
  inspect(store.collect_garbage(), content="1")
  inspect(store.is_gc_valid(rooted), content="false")
}

///|
async test "one interpreter invocation can await multiple host calls" {
  let linker = @runtime.Linker::Linker()
  defer linker.close()
  linker.add_async_host_func(
    "host",
    "increment",
    async fn(args) {
      @async.sleep(1)
      match args[0] {
        I32(value) => [I32(value + 1)]
        _ => raise @runtime.TypeMismatch
      }
    },
    func_type={ params: [I32], results: [I32], },
  )
  let instance = instantiate_with_linker(
    linker,
    "guest",
    async_host_twice_test_module(),
  )
  let result = call_exported_func_async(linker.get_store(), instance, "run", [
    I32(10),
  ])
  debug_inspect(result, content="[I32(12)]")
}

///|
test "synchronous linker instantiation executes start exactly once" {
  let calls = [0]
  let linker = @runtime.Linker::Linker()
  defer linker.close()
  linker.add_host_func(
    "host",
    "start",
    fn(_args) {
      calls[0] = calls[0] + 1
      []
    },
    func_type={ params: [], results: [], },
  )
  instantiate_with_linker(linker, "guest", async_host_start_test_module())
  |> ignore
  inspect(calls[0], content="1")
}
