///|
fn deep_call_module() -> @types.Module {
  @types.Module::simple(
    [I32],
    [I32],
    [
      LocalGet(0),
      I32Eqz,
      If(Value(I32), [I32Const(0)], [
        LocalGet(0),
        I32Const(1),
        I32Sub,
        Call(0),
        I32Const(1),
        I32Add,
      ]),
    ],
    "count",
  )
}

///|
test "explicit stack: ten thousand ordinary calls" {
  let (store, instance) = @executor.instantiate_module(deep_call_module())
  defer store.close()
  let values = @executor.call_exported_func(store, instance, "count", [
    I32(10000),
  ])
  assert_true(values[0] is I32(10000))
}

///|
fn limited_count(
  limits : @runtime.InterpreterLimits,
) -> (@runtime.Store, @runtime.ModuleInstance) raise {
  let store = @runtime.Store::Store(interpreter_limits=limits)
  let instance = @executor.instantiate_module_with_imports(
    store,
    deep_call_module(),
    Imports(),
  )
  (store, instance)
}

///|
test "explicit stack: exact frame budget and recovery" {
  let (store, instance) = limited_count(
    @runtime.InterpreterLimits::new(max_frames=8),
  )
  defer store.close()
  assert_true(
    @executor.call_exported_func(store, instance, "count", [I32(7)])[0]
    is I32(7),
  )
  let failure = try
    @executor.call_exported_func(store, instance, "count", [I32(8)])
  catch {
    CallStackExhausted => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(failure)
  assert_true(
    @executor.call_exported_func(store, instance, "count", [I32(7)])[0]
    is I32(7),
  )
}

///|
test "explicit stack: locals and operands share the value budget" {
  let (store, instance) = limited_count(
    @runtime.InterpreterLimits::new(max_values=8),
  )
  defer store.close()
  let failure = try
    @executor.call_exported_func(store, instance, "count", [I32(20)])
  catch {
    StackOverflow => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(failure)
  assert_true(
    @executor.call_exported_func(store, instance, "count", [I32(2)])[0]
    is I32(2),
  )
}

///|
test "explicit stack: tail calls replace the frame within a one-frame budget" {
  let mod = @types.Module::simple(
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
  )
  let store = @runtime.Store::Store(
    interpreter_limits=@runtime.InterpreterLimits::new(max_frames=1),
  )
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    mod,
    Imports(),
  )
  assert_true(
    @executor.call_exported_func(store, instance, "tail", [I32(100000)])[0]
    is I32(42),
  )
}

///|
test "explicit stack: cooperative resumption across deep calls" {
  let (store, instance) = limited_count(@runtime.InterpreterLimits::default())
  defer store.close()
  let mut outcome = @executor.call_func_by_index_resumable(
    store,
    instance,
    0,
    [I32(10000)],
    fn(_) { None },
    cooperative=true,
  )
  let mut pauses = 0
  while true {
    match outcome {
      Returned(values) => {
        assert_true(values[0] is I32(10000))
        break
      }
      Suspended(CooperativeYield, continuation) => {
        pauses += 1
        outcome = continuation.continue_execution()
      }
      _ => fail("unexpected host suspension")
    }
  }
  assert_true(pauses > 20)
}

///|
fn deep_host_module() -> @types.Module {
  {
    ..@types.Module::empty(),
    types: [@types.SubType::func([I32], [I32]), @types.SubType::func([], [I32])],
    type_rec_groups: [0, 1],
    imports: [{ mod_name: "host", name: "leaf", desc: Func(1), }],
    funcs: [0],
    codes: [
      {
        locals: [],
        body: [
          LocalGet(0),
          I32Eqz,
          If(Value(I32), [Call(0)], [
            LocalGet(0),
            I32Const(1),
            I32Sub,
            Call(1),
            I32Const(1),
            I32Add,
          ]),
        ],
      },
    ],
    exports: [{ name: "count", desc: Func(1), }],
  }
}

///|
test "explicit stack: deep host suspension and single-use resume" {
  let ready = Ref(false)
  let store = @runtime.Store::Store()
  defer store.close()
  let host = store.alloc_host_func_with_caller(
    fn(_, _) raise @runtime.RuntimeError {
      if !ready.val {
        raise Unreachable
      }
      [I32(5)]
    },
    func_type={ params: [], results: [I32], },
    type_idx=1,
  )
  let imports = @runtime.Imports::Imports()
  imports.add_func("host", "leaf", host)
  let instance = @executor.instantiate_module_with_imports(
    store,
    deep_host_module(),
    imports,
  )
  let outcome = @executor.call_func_by_index_resumable(
    store,
    instance,
    1,
    [I32(10000)],
    fn(_) { Some(7L) },
  )
  guard outcome is Suspended(HostCall(7L), continuation) else {
    fail("expected suspension")
  }
  ready.val = true
  guard continuation.continue_execution() is Returned(values) else {
    fail("expected return")
  }
  assert_true(values[0] is I32(10005))
  let reused = try continuation.continue_execution() catch {
    _ => true
  } noraise {
    _ => false
  }
  assert_true(reused)
}

///|
test "explicit stack: host reentry is bounded and recovers" {
  let instance_ref : Ref[@runtime.ModuleInstance?] = Ref(None)
  let reenter = Ref(true)
  let store = @runtime.Store::Store(
    interpreter_limits=@runtime.InterpreterLimits::new(max_reentry_depth=4),
  )
  defer store.close()
  let host = store.alloc_host_func_with_caller(
    fn(_, _) raise @runtime.RuntimeError {
      if reenter.val {
        @executor.call_exported_func(
          store,
          instance_ref.val.unwrap(),
          "count",
          [I32(0)],
        )
      } else {
        [I32(9)]
      }
    },
    func_type={ params: [], results: [I32], },
    type_idx=1,
  )
  let imports = @runtime.Imports::Imports()
  imports.add_func("host", "leaf", host)
  let instance = @executor.instantiate_module_with_imports(
    store,
    deep_host_module(),
    imports,
  )
  instance_ref.val = Some(instance)
  let failure = try
    @executor.call_exported_func(store, instance, "count", [I32(0)])
  catch {
    CallStackExhausted => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(failure)
  reenter.val = false
  assert_true(
    @executor.call_exported_func(store, instance, "count", [I32(0)])[0]
    is I32(9),
  )
  instance_ref.val = None
}

///|
test "explicit stack: deep structured control and control budget" {
  let mut body : Array[@types.Instruction] = [I32Const(42)]
  for _ in 0..<2000 {
    body = [Block(Value(I32), body)]
  }
  let mod = @types.Module::simple([], [I32], body, "nested")
  let (store, instance) = @executor.instantiate_module(mod)
  defer store.close()
  assert_true(
    @executor.call_exported_func(store, instance, "nested", [])[0] is I32(42),
  )
  let limited = @runtime.Store::Store(
    interpreter_limits=@runtime.InterpreterLimits::new(max_controls=128),
  )
  defer limited.close()
  let instance = @executor.instantiate_module_with_imports(
    limited,
    mod,
    Imports(),
  )
  let exhausted = try
    @executor.call_exported_func(limited, instance, "nested", [])
  catch {
    StackOverflow => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(exhausted)
}

///|
test "explicit stack: exception unwinds ten thousand guest calls" {
  let mod : @types.Module = {
    ..@types.Module::empty(),
    types: [@types.SubType::func([I32], [I32]), @types.SubType::func([I32], [])],
    type_rec_groups: [0, 1],
    tags: [{ type_idx: 1, }],
    funcs: [0, 0],
    codes: [
      {
        locals: [],
        body: [
          LocalGet(0),
          I32Eqz,
          If(Value(I32), [I32Const(42), Throw(0)], [
            LocalGet(0),
            I32Const(1),
            I32Sub,
            Call(0),
            I32Const(1),
            I32Add,
          ]),
        ],
      },
      {
        locals: [],
        body: [
          Block(Value(I32), [
            TryTable(Empty, [Catch(0, 0)], [LocalGet(0), Call(0), Drop]),
            I32Const(-1),
          ]),
        ],
      },
    ],
    exports: [{ name: "catch", desc: Func(1), }],
  }
  let (store, instance) = @executor.instantiate_module(mod)
  defer store.close()
  assert_true(
    @executor.call_exported_func(store, instance, "catch", [I32(10000)])[0]
    is I32(42),
  )
}

///|
test "explicit stack: deep frame roots survive host collection" {
  let mod : @types.Module = {
    ..@types.Module::empty(),
    types: [
      @types.SubType::simple(
        Struct({ fields: [{ storage_type: Val(I32), mutable: false, }], }),
      ),
      @types.SubType::func([], []),
      @types.SubType::func([I32, RefNullStruct(0)], [I32]),
      @types.SubType::func([], [I32]),
    ],
    type_rec_groups: [0, 1, 2, 3],
    imports: [{ mod_name: "host", name: "collect", desc: Func(1), }],
    funcs: [2, 3],
    codes: [
      {
        locals: [],
        body: [
          LocalGet(0),
          I32Eqz,
          If(Value(I32), [Call(0), I32Const(0)], [
            LocalGet(0),
            I32Const(1),
            I32Sub,
            LocalGet(1),
            Call(1),
          ]),
          LocalGet(1),
          StructGet(0, 0),
          I32Add,
        ],
      },
      {
        locals: [],
        body: [I32Const(2000), I32Const(1), StructNew(0), Call(1)],
      },
    ],
    exports: [{ name: "run", desc: Func(2), }],
  }
  let store = @runtime.Store::Store()
  defer store.close()
  let host = store.alloc_host_func_with_caller(
    fn(_, _) {
      store.collect_garbage() |> ignore
      []
    },
    func_type={ params: [], results: [], },
    type_idx=1,
  )
  let imports = @runtime.Imports::Imports()
  imports.add_func("host", "collect", host)
  let instance = @executor.instantiate_module_with_imports(store, mod, imports)
  assert_true(
    @executor.call_exported_func(store, instance, "run", [])[0] is I32(2001),
  )
}

///|
async test "explicit stack: asynchronous host resumes deep guest frames" {
  let started = @async.Semaphore(1, initial_value=0)
  let finish = @async.Semaphore(1, initial_value=0)
  let linker = @runtime.Linker::Linker()
  defer linker.close()
  linker.add_async_host_func(
    "host",
    "leaf",
    async fn(_) {
      started.release()
      finish.acquire()
      [I32(5)]
    },
    func_type={ params: [], results: [I32], },
  )
  let instance = @executor.instantiate_with_linker(
    linker,
    "deep",
    deep_host_module(),
  )
  let values = @async.with_task_group(group => {
    let task = group.spawn(no_wait=true, () => {
      @executor.call_exported_func_async(
        linker.get_store(),
        instance,
        "count",
        [I32(10000)],
      )
    })
    started.acquire()
    finish.release()
    task.wait()
  })
  assert_true(values[0] is I32(10005))
}

///|
test "explicit stack: runaway ordinary recursion traps" {
  let mod = @types.Module::simple([], [], [Call(0)], "run")
  let (store, instance) = @executor.instantiate_module(mod)
  defer store.close()
  let exhausted = try
    @executor.call_exported_func(store, instance, "run", [])
  catch {
    CallStackExhausted => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(exhausted)
}

///|
test "explicit stack: frame storage exhaustion preserves call-stack classification" {
  let mod : @types.Module = {
    ..@types.Module::simple([], [], [], "run"),
    codes: [{ locals: Array::make(32, I64), body: [], }],
  }
  let store = @runtime.Store::Store(
    interpreter_limits=@runtime.InterpreterLimits::new(max_values=16),
  )
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    mod,
    Imports(),
  )
  let exhausted = try
    @executor.call_exported_func(store, instance, "run", [])
  catch {
    CallStackExhausted => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(exhausted)
}

///|
test "explicit stack: nested guest continuation boundaries are bounded" {
  let mod : @types.Module = {
    ..@types.Module::empty(),
    types: [@types.SubType::func([], []), @types.SubType::simple(Cont(0))],
    type_rec_groups: [0, 1],
    funcs: [0],
    codes: [{ locals: [], body: [RefFunc(0), ContNew(1), Resume(1, [])], }],
    exports: [{ name: "run", desc: Func(0), }],
  }
  let store = @runtime.Store::Store(
    interpreter_limits=@runtime.InterpreterLimits::new(max_reentry_depth=4),
  )
  defer store.close()
  let instance = @executor.instantiate_module_with_imports(
    store,
    mod,
    Imports(),
  )
  let exhausted = try
    @executor.call_exported_func(store, instance, "run", [])
  catch {
    CallStackExhausted => true
    _ => false
  } noraise {
    _ => false
  }
  assert_true(exhausted)
}
