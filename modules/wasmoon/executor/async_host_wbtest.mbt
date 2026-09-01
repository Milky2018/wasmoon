///|
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
async test "async host function suspends wasm without blocking the host task" {
  let events : Array[String] = []
  let linker = @runtime.Linker::Linker()
  linker.add_async_host_func(
    "host",
    "double",
    async fn(args) {
      events.push("host started")
      @async.sleep(10)
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
    group.spawn_bg() <| () => {
      @async.sleep(1)
      events.push("other task ran")
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
