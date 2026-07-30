///|
fn component_runtime_facade_fixture() -> Bytes raise @component_text.ComponentTextError {
  @component_text.parse_component_wat(
    (
      #|(component
      #|  (core module $m
      #|    (func (export "increment") (param i32) (result i32)
      #|      local.get 0
      #|      i32.const 1
      #|      i32.add))
      #|  (core instance $i (instantiate $m))
      #|  (func $increment (param "value" u32) (result u32)
      #|    (canon lift (core func $i "increment")))
      #|  (instance $math (export "increment" (func $increment)))
      #|  (export "increment" (func $increment))
      #|  (export "math" (instance $math))
      #|  (export "dep:math/math@1.0.0" (instance $math)))
      #|
    ),
  )
}

///|
fn component_runtime_trap_fixture() -> Bytes raise @component_text.ComponentTextError {
  @component_text.parse_component_wat(
    (
      #|(component
      #|  (core module $m
      #|    (func (export "trap")
      #|      unreachable))
      #|  (core instance $i (instantiate $m))
      #|  (func $trap
      #|    (canon lift (core func $i "trap")))
      #|  (export "trap" (func $trap)))
      #|
    ),
  )
}

///|
fn component_runtime_yield_fixture() -> Bytes raise @component_text.ComponentTextError {
  @component_text.parse_component_wat(
    (
      #|(component
      #|  (core module $m
      #|    (import "" "thread.yield" (func $thread.yield (result i32)))
      #|    (func (export "yield-once") (result i32)
      #|      (drop (call $thread.yield))
      #|      (i32.const 42)))
      #|  (canon thread.yield (core func $thread.yield))
      #|  (core instance $i (instantiate $m (with "" (instance
      #|    (export "thread.yield" (func $thread.yield))))))
      #|  (func $yield-once async (result u32)
      #|    (canon lift (core func $i "yield-once")))
      #|  (export "yield-once" (func $yield-once)))
      #|
    ),
  )
}

///|
fn component_runtime_yielding_background_timer_fixture() -> Bytes raise @component_text.ComponentTextError {
  @component_text.parse_component_wat(
    (
      #|(component
      #|  (import "wasi:clocks/monotonic-clock@0.3.0"
      #|    (instance $clock
      #|      (export "wait-for" (func async (param "how-long" u64)))))
      #|  (alias export $clock "wait-for" (func $wait-for))
      #|  (component $spinner
      #|    (core module $m
      #|      (import "" "task.return" (func $task.return))
      #|      (import "" "thread.yield" (func $thread.yield (result i32)))
      #|      (func (export "spin") (result i32)
      #|        (call $task.return)
      #|        (drop (call $thread.yield))
      #|        (i32.const 1))
      #|      (func (export "spin-cb") (param i32 i32 i32) (result i32)
      #|        (i32.const 1)))
      #|    (canon task.return (core func $task.return))
      #|    (canon thread.yield (core func $thread.yield))
      #|    (core instance $i (instantiate $m (with "" (instance
      #|      (export "task.return" (func $task.return))
      #|      (export "thread.yield" (func $thread.yield))))))
      #|    (func (export "spin") async (canon lift
      #|      (core func $i "spin")
      #|      async (callback (core func $i "spin-cb")))))
      #|  (instance $spinner-instance (instantiate $spinner))
      #|  (component $starter
      #|    (import "spin" (func $spin async))
      #|    (core func $spin-lowered (canon lower (func $spin)))
      #|    (core module $m
      #|      (import "" "spin" (func $spin))
      #|      (func (export "start-spinner") (call $spin)))
      #|    (core instance $i (instantiate $m (with "" (instance
      #|      (export "spin" (func $spin-lowered))))))
      #|    (func (export "start-spinner") async
      #|      (canon lift (core func $i "start-spinner") async)))
      #|  (instance $started (instantiate $starter
      #|    (with "spin" (func $spinner-instance "spin"))))
      #|  (alias export $started "start-spinner" (func $start-spinner))
      #|  (export "start-spinner" (func $start-spinner))
      #|  (export "wait-for" (func $wait-for)))
      #|
    ),
  )
}

///|
test "component runtime facade binds and invokes nested exports" {
  let runtime = @component.ComponentRuntime()
  defer runtime.close()
  let instance = runtime.instantiate(
    "fixture",
    component_runtime_facade_fixture(),
  )
  let function = instance.bind("math#increment")
  debug_inspect(
    function.type_(),
    content=(
      #|{
      #|  is_async: false,
      #|  params: [{ name: "value", ty: U32 }],
      #|  result: Some(U32),
      #|}
    ),
  )
  debug_inspect(
    function.call([U32(41U)]),
    content=(
      #|[U32(42)]
    ),
  )
}

///|
test "component calls resume a directly yielding guest" {
  let runtime = @component.ComponentRuntime(
    engine=@component.interpreter_component_engine(),
  )
  defer runtime.close()
  let blocking_call = runtime
    .instantiate("yield", component_runtime_yield_fixture())
    .bind("yield-once")
    .start([])
  debug_inspect(
    blocking_call.wait(),
    content=(
      #|[U32(42)]
    ),
  )
  let polled_call = runtime
    .instantiate("yield-poll", component_runtime_yield_fixture())
    .bind("yield-once")
    .start([])
  debug_inspect(
    (polled_call.poll(), polled_call.poll()),
    content=(
      #|(Pending, Ready([U32(42)]))
    ),
  )
  let native_runtime = @component.ComponentRuntime()
  defer native_runtime.close()
  debug_inspect(
    native_runtime
    .instantiate("native-yield", component_runtime_yield_fixture())
    .bind("yield-once")
    .start([])
    .wait(),
    content=(
      #|[U32(42)]
    ),
  )
}

///|
test "yielding background work cannot starve a WASI timer" {
  let ctx = @wasi_component.WasiComponentCtxBuilder().build()
  let runtime = @component.ComponentRuntime(
    engine=@component.interpreter_component_engine(),
  )
  defer runtime.close()
  runtime.install(@component.wasi_command_component_host(ctx))
  let instance = runtime.instantiate(
    "yielding-background-timer",
    component_runtime_yielding_background_timer_fixture(),
  )
  instance.bind("start-spinner").call([]) |> ignore
  let timer = instance.bind("wait-for").start([U64(0UL)])
  debug_inspect((timer.poll(), timer.poll()), content="(Pending, Ready([]))")
}

///|
test "component runtime rejects a second WASI readiness source" {
  let first_ctx = @wasi_component.WasiComponentCtxBuilder().build()
  let runtime = @component.ComponentRuntime(
    engine=@component.interpreter_component_engine(),
  )
  defer runtime.close()
  runtime.install(@component.wasi_command_component_host(first_ctx))
  let timer = runtime
    .instantiate(
      "first-wasi-host",
      component_runtime_yielding_background_timer_fixture(),
    )
    .bind("wait-for")
    .start([U64(0UL)])
  debug_inspect(timer.poll(), content="Pending")
  let second_ctx = @wasi_component.WasiComponentCtxBuilder().build()
  let install_error = try
    runtime.install(@component.wasi_command_component_host(second_ctx))
  catch {
    error => error
  } noraise {
    _ => fail("expected a second WASI readiness source to be rejected")
  }
  debug_inspect(
    (install_error, timer.poll()),
    content="(HostReadinessAlreadyInstalled, Ready([]))",
  )
}

///|
test "closing one interpreter session leaves its sibling operational" {
  let engine = @component.interpreter_component_engine()
  let first_runtime = @component.ComponentRuntime(engine~)
  let second_runtime = @component.ComponentRuntime(engine~)
  defer second_runtime.close()
  let first = first_runtime.instantiate(
    "first",
    component_runtime_facade_fixture(),
  )
  let second = second_runtime.instantiate(
    "second",
    component_runtime_facade_fixture(),
  )
  let first_result = first.bind("increment").call([U32(1U)])
  first_runtime.close()
  debug_inspect(
    (first_result, second.bind("increment").call([U32(40U)])),
    content=(
      #|([U32(2)], [U32(41)])
    ),
  )
}

///|
test "closing one native session leaves its sibling operational" {
  let engine = @component.native_component_engine(opt_level=0)
  let first_runtime = @component.ComponentRuntime(engine~)
  let second_runtime = @component.ComponentRuntime(engine~)
  defer second_runtime.close()
  let first = first_runtime.instantiate(
    "first-native",
    component_runtime_facade_fixture(),
  )
  let second = second_runtime.instantiate(
    "second-native",
    component_runtime_facade_fixture(),
  )
  let first_result = first.bind("increment").call([U32(2U)])
  first_runtime.close()
  debug_inspect(
    (first_result, second.bind("increment").call([U32(41U)])),
    content=(
      #|([U32(3)], [U32(42)])
    ),
  )
}

///|
test "WASI command hosts reject installer and context aliases" {
  let shared_installer_ctx = @wasi_component.WasiComponentCtxBuilder()
    .stdin(b"hello")
    .build()
  let shared_installer = @component.wasi_command_component_host(
    shared_installer_ctx,
  )
  let first_runtime = @component.ComponentRuntime(
    engine=@component.interpreter_component_engine(),
  )
  let second_runtime = @component.ComponentRuntime(
    engine=@component.interpreter_component_engine(),
  )
  defer first_runtime.close()
  defer second_runtime.close()
  first_runtime.install(shared_installer)
  let installer_alias_error = try
    second_runtime.install(shared_installer)
  catch {
    error => error
  } noraise {
    _ => fail("expected reused host installer to be rejected")
  }
  second_runtime.close()
  let stdin_component = @component_text.parse_component_wat(
    @fs.read_file_to_string(
      "testsuite/fixtures/wasi-command-async-stdin.component.wat",
    ),
  )
  let first_result = first_runtime
    .instantiate("first-wasi-owner", stdin_component)
    .bind("wasi:cli/run@0.3.0#run")
    .call([])

  let shared_ctx = @wasi_component.WasiComponentCtxBuilder()
    .stdin(b"hello")
    .build()
  let third_runtime = @component.ComponentRuntime(
    engine=@component.interpreter_component_engine(),
  )
  let fourth_runtime = @component.ComponentRuntime(
    engine=@component.interpreter_component_engine(),
  )
  defer third_runtime.close()
  defer fourth_runtime.close()
  third_runtime.install(@component.wasi_command_component_host(shared_ctx))
  let context_alias_error = try
    fourth_runtime.install(@component.wasi_command_component_host(shared_ctx))
  catch {
    error => error
  } noraise {
    _ => fail("expected aliased WASI context to be rejected")
  }
  fourth_runtime.close()
  let third_result = third_runtime
    .instantiate("third-wasi-owner", stdin_component)
    .bind("wasi:cli/run@0.3.0#run")
    .call([])
  debug_inspect(
    (installer_alias_error, first_result, context_alias_error, third_result),
    content=(
      #|(
      #|  HostInstallerAlreadyConsumed,
      #|  [ResultOk(None)],
      #|  HostContextAlreadyOwned,
      #|  [ResultOk(None)],
      #|)
    ),
  )
}

///|
test "component runtime native engine executes without interpreter fallback" {
  let events : Array[@component.NativeComponentExecutionEvent] = []
  let runtime = @component.ComponentRuntime(
    engine=@component.native_component_engine(opt_level=0, on_execution=fn(
      event,
    ) {
      events.push(event)
    }),
  )
  defer runtime.close()
  let result = runtime
    .instantiate("native", component_runtime_facade_fixture())
    .bind("increment")
    .call([U32(9U)])
  debug_inspect(
    (result, events),
    content=(
      #|([U32(10)], [RunToReturn])
    ),
  )
}

///|
test "native execution callback can close its runtime during suspension" {
  let close_runtime = Ref(fn() { () })
  let reenter_call = Ref(fn() { () })
  let events : Array[@component.NativeComponentExecutionEvent] = []
  let reentrant_errors : Array[@component.ComponentRuntimeError] = []
  let reentrant_returned = Ref(false)
  let runtime = @component.ComponentRuntime(
    engine=@component.native_component_engine(opt_level=0, on_execution=fn(
      event,
    ) {
      events.push(event)
      (close_runtime.val)()
      (reenter_call.val)()
    }),
  )
  let call = runtime
    .instantiate("native-close-on-suspend", component_runtime_yield_fixture())
    .bind("yield-once")
    .start([])
  close_runtime.val = fn() { runtime.close() }
  reenter_call.val = fn() {
    reenter_call.val = fn() { () }
    let error = try call.poll() catch {
      error => Some(error)
    } noraise {
      _ => None
    }
    match error {
      Some(error) => reentrant_errors.push(error)
      None => reentrant_returned.val = true
    }
  }
  let poll_error = try call.poll() catch {
    error => error
  } noraise {
    _ => fail("expected callback close to cancel the call")
  }
  let closed_error = try
    runtime.instantiate("closed", component_runtime_facade_fixture())
  catch {
    error => error
  } noraise {
    _ => fail("expected runtime to remain closed")
  }
  runtime.close()
  debug_inspect(
    (events, reentrant_errors, reentrant_returned.val, poll_error, closed_error),
    content="([Resumable], [Cancelled], false, Cancelled, RuntimeClosed)",
  )
}

///|
test "native execution callback rejects same-call reentry" {
  let reenter_call = Ref(fn() { () })
  let events : Array[@component.NativeComponentExecutionEvent] = []
  let reentrant_errors : Array[@component.ComponentRuntimeError] = []
  let reentrant_returned = Ref(false)
  let runtime = @component.ComponentRuntime(
    engine=@component.native_component_engine(opt_level=0, on_execution=fn(
      event,
    ) {
      events.push(event)
      (reenter_call.val)()
    }),
  )
  defer runtime.close()
  let call = runtime
    .instantiate("native-reentrant-call", component_runtime_yield_fixture())
    .bind("yield-once")
    .start([])
  reenter_call.val = fn() {
    reenter_call.val = fn() { () }
    let error = try call.poll() catch {
      error => Some(error)
    } noraise {
      _ => None
    }
    match error {
      Some(error) => reentrant_errors.push(error)
      None => reentrant_returned.val = true
    }
  }
  let outer = call.poll()
  call.cancel()
  debug_inspect(
    (events, reentrant_errors, reentrant_returned.val, outer),
    content="([Resumable], [CallAlreadyActive], false, Pending)",
  )
}

///|
test "native side-task callback close defers teardown until publication" {
  let armed = Ref(false)
  let close_runtime = Ref(fn() { () })
  let reenter_call = Ref(fn() { () })
  let events : Array[@component.NativeComponentExecutionEvent] = []
  let reentrant_errors : Array[@component.ComponentRuntimeError] = []
  let reentrant_returned = Ref(false)
  let runtime = @component.ComponentRuntime(
    engine=@component.native_component_engine(opt_level=0, on_execution=fn(
      event,
    ) {
      if armed.val {
        events.push(event)
        (reenter_call.val)()
        (close_runtime.val)()
      }
    }),
  )
  close_runtime.val = fn() { runtime.close() }
  let ctx = @wasi_component.WasiComponentCtxBuilder().build()
  runtime.install(@component.wasi_command_component_host(ctx))
  let instance = runtime.instantiate(
    "native-side-task-close",
    component_runtime_yielding_background_timer_fixture(),
  )
  instance.bind("start-spinner").call([]) |> ignore
  armed.val = true
  let timer = instance.bind("wait-for").start([U64(60_000_000_000UL)])
  reenter_call.val = fn() {
    reenter_call.val = fn() { () }
    let error = try timer.poll() catch {
      error => Some(error)
    } noraise {
      _ => None
    }
    match error {
      Some(error) => reentrant_errors.push(error)
      None => reentrant_returned.val = true
    }
  }
  debug_inspect(timer.poll(), content="Pending")
  let poll_errors : Array[@component.ComponentRuntimeError] = []
  let poll_returned = Ref(false)
  try timer.poll() catch {
    error => poll_errors.push(error)
  } noraise {
    _ => poll_returned.val = true
  }
  let closed_error = try
    runtime.instantiate(
      "closed-after-side-task",
      component_runtime_facade_fixture(),
    )
  catch {
    error => error
  } noraise {
    _ => fail("expected side-task callback close to remain terminal")
  }
  runtime.close()
  debug_inspect(
    (
      events,
      reentrant_errors,
      reentrant_returned.val,
      poll_errors,
      poll_returned.val,
      closed_error,
    ),
    content=(
      #|(
      #|  [Resumable],
      #|  [CallAlreadyActive],
      #|  false,
      #|  [Cancelled],
      #|  false,
      #|  RuntimeClosed,
      #|)
    ),
  )
}

///|
test "component calls expose stable completion and cancellation states" {
  let runtime = @component.ComponentRuntime(
    engine=@component.interpreter_component_engine(),
  )
  defer runtime.close()
  let function = runtime
    .instantiate("calls", component_runtime_facade_fixture())
    .bind("increment")
  let completed = function.start([U32(4U)])
  debug_inspect(
    (completed.poll(), completed.poll()),
    content=(
      #|(Ready([U32(5)]), Ready([U32(5)]))
    ),
  )
  completed.cancel()
  debug_inspect(
    completed.poll(),
    content=(
      #|Ready([U32(5)])
    ),
  )
  let cancelled = function.start([U32(8U)])
  cancelled.cancel()
  cancelled.cancel()
  inspect(
    try cancelled.poll() catch {
      error => error
    } noraise {
      _ => fail("expected cancelled call")
    },
    content=(
      #|Cancelled
    ),
  )
}

///|
async test "component calls expose an asynchronous join" {
  let runtime = @component.ComponentRuntime(
    engine=@component.interpreter_component_engine(),
  )
  defer runtime.close()
  let call = runtime
    .instantiate("async-join", component_runtime_facade_fixture())
    .bind("increment")
    .start([U32(6U)])
  debug_inspect(
    call.join(),
    content=(
      #|[U32(7)]
    ),
  )
}

///|
async test "component calls reject overlapping asynchronous joins" {
  let runtime = @component.ComponentRuntime(
    engine=@component.interpreter_component_engine(),
  )
  defer runtime.close()
  let ctx = @wasi_component.WasiComponentCtxBuilder().build()
  runtime.install(@component.wasi_command_component_host(ctx))
  let call = runtime
    .instantiate(
      "overlapping-join",
      component_runtime_yielding_background_timer_fixture(),
    )
    .bind("wait-for")
    .start([U64(60_000_000_000UL)])
  let outcomes = @async.with_task_group(group => {
    let first = group.spawn(no_wait=true, () => {
      try call.join() catch {
        error => Err(error)
      } noraise {
        values => Ok(values)
      }
    })
    let second = group.spawn(no_wait=true, () => {
      try call.join() catch {
        error => Err(error)
      } noraise {
        values => Ok(values)
      }
    })
    group.spawn_bg() <| () => { call.cancel() }
    (first.wait(), second.wait())
  })
  debug_inspect(outcomes, content="(Err(Cancelled), Err(CallAlreadyActive))")
}

///|
test "component call traps become stable errors before runtime teardown" {
  let runtime = @component.ComponentRuntime()
  defer runtime.close()
  let call = runtime
    .instantiate("trap", component_runtime_trap_fixture())
    .bind("trap")
    .start([])
  inspect(
    try call.wait() catch {
      error => error
    } noraise {
      _ => fail("expected component trap")
    },
    content=(
      #|InvocationFailed("CanonCallError(\"wasm trap: wasm `unreachable` instruction executed (core=trap::coreinst0 func_idx=0)\")")
    ),
  )
}

///|
test "component runtime close is terminal for retained aliases" {
  let runtime = @component.ComponentRuntime(
    engine=@component.interpreter_component_engine(),
  )
  let instance = runtime.instantiate(
    "lifecycle",
    component_runtime_facade_fixture(),
  )
  let function = instance.bind("increment")
  let call = function.start([U32(1U)])
  runtime.close()
  runtime.close()
  let instantiate_error = try
    runtime.instantiate("after-close", component_runtime_facade_fixture())
  catch {
    error => error
  } noraise {
    _ => fail("expected closed runtime")
  }
  let bind_error = try instance.bind("increment") catch {
    error => error
  } noraise {
    _ => fail("expected retained instance to be closed")
  }
  let start_error = try function.start([U32(2U)]) catch {
    error => error
  } noraise {
    _ => fail("expected retained function to be closed")
  }
  let call_error = try call.poll() catch {
    error => error
  } noraise {
    _ => fail("expected outstanding call to be cancelled")
  }
  inspect(
    (instantiate_error, bind_error, start_error, call_error),
    content=(
      #|(RuntimeClosed, RuntimeClosed, RuntimeClosed, Cancelled)
    ),
  )
}

///|
test "component runtime facade reports stable path and arity errors" {
  let runtime = @component.ComponentRuntime()
  defer runtime.close()
  let instance = runtime.instantiate(
    "fixture",
    component_runtime_facade_fixture(),
  )
  inspect(
    try instance.bind("math#missing") catch {
      error => error
    } noraise {
      _ => fail("expected unknown export")
    },
    content=(
      #|UnknownExport("math#missing")
    ),
  )
  let function = instance.bind("math#increment")
  inspect(
    try function.call([]) catch {
      error => error
    } noraise {
      _ => fail("expected argument count mismatch")
    },
    content=(
      #|ArgumentCountMismatch(expected=1, actual=0)
    ),
  )
}

///|
test "component runtime facade preserves WIT-shaped JSON values" {
  let ty = @component.ComponentValueType::Record([
    ComponentField("items", List(Option(U32))),
    ComponentField(
      "state",
      Variant([
        ComponentCase("ready", Some(String)),
        ComponentCase("closed", None),
      ]),
    ),
    ComponentField("permissions", Flags(["read", "write"])),
  ])
  let value = @component.parse_component_value_json(
    (
      #|{"items":[{"some":7},null],"state":{"case":"ready","value":"ok"},"permissions":["read"]}
    ),
    ty,
  )
  debug_inspect(
    value,
    content=(
      #|Record(
      #|  [
      #|    ("items", List([OptionSome(U32(7)), OptionNone])),
      #|    ("state", Variant("ready", Some(String("ok")))),
      #|    ("permissions", Flags(["read"])),
      #|  ],
      #|)
    ),
  )
  inspect(
    @component.component_value_to_json(value).stringify(),
    content=(
      #|{"items":[{"some":7},null],"state":{"case":"ready","value":"ok"},"permissions":["read"]}
    ),
  )
}

///|
test "component runtime facade rejects malformed JSON before invocation" {
  inspect(
    try
      @component.parse_component_value_json(
        "{\"wrong\":1}",
        Record([ComponentField("expected", U32)]),
      )
    catch {
      error => error
    } noraise {
      _ => fail("expected record validation failure")
    },
    content=(
      #|JsonValueError("missing record field 'expected'")
    ),
  )
}

///|
test "component JSON preserves non-finite floating-point values" {
  inspect(
    @component.component_values_to_json([
      F64(0.0 / 0.0),
      F64(1.0 / 0.0),
      F32(Float::from_double(-1.0 / 0.0)),
    ]).stringify(),
    content=(
      #|["nan","inf","-inf"]
    ),
  )
  debug_inspect(
    [
      @component.parse_component_value_json("\"nan\"", F64),
      @component.parse_component_value_json("\"inf\"", F32),
    ],
    content=(
      #|[F64(NaN), F32(Infinity)]
    ),
  )
}

///|
test "resolved WIT world binds and invokes a typed interface export" {
  let runtime = @component.ComponentRuntime()
  defer runtime.close()
  let instance = runtime.instantiate(
    "fixture",
    component_runtime_facade_fixture(),
  )
  let wit_package = @wit.parse_package(
    (
      #|package test:demo;
      #|
      #|interface math {
      #|  increment: func(value: u32) -> u32;
      #|}
      #|
      #|world demo {
      #|  export math;
      #|}
      #|
    ),
  )
  let bindings = @wit.resolve_package(wit_package, []).bind_world(
    "demo", instance,
  )
  debug_inspect(bindings.paths(), content="[\"math#increment\"]")
  debug_inspect(
    bindings.function("math#increment").call([U32(9U)]),
    content=(
      #|[U32(10)]
    ),
  )
}

///|
test "WIT binding rejects a mismatched export before invocation" {
  let runtime = @component.ComponentRuntime()
  defer runtime.close()
  let instance = runtime.instantiate(
    "fixture",
    component_runtime_facade_fixture(),
  )
  let wit_package = @wit.parse_package(
    (
      #|package test:demo;
      #|
      #|interface math {
      #|  increment: func(value: u32) -> string;
      #|}
      #|
      #|world demo {
      #|  export math;
      #|}
      #|
    ),
  )
  inspect(
    try
      @wit.resolve_package(wit_package, []).bind_world("demo", instance)
    catch {
      error => error
    } noraise {
      _ => fail("expected binding type mismatch")
    },
    content=(
      #|RuntimeBindingFailed("BindingTypeMismatch(\n  path=\"math#increment\",\n  expected={\n    is_async: false,\n    params: [{ name: \"value\", ty: U32 }],\n    result: Some(String),\n  },\n  actual={\n    is_async: false,\n    params: [{ name: \"value\", ty: U32 }],\n    result: Some(U32),\n  },\n)")
    ),
  )
}

///|
test "WIT binding covers direct and inline world exports" {
  let runtime = @component.ComponentRuntime()
  defer runtime.close()
  let instance = runtime.instantiate(
    "fixture",
    component_runtime_facade_fixture(),
  )
  let wit_package = @wit.parse_package(
    (
      #|package test:demo;
      #|
      #|world demo {
      #|  export increment: func(value: u32) -> u32;
      #|  export math: interface {
      #|    increment: func(value: u32) -> u32;
      #|  }
      #|}
      #|
    ),
  )
  let bindings = @wit.resolve_package(wit_package, []).bind_world(
    "demo", instance,
  )
  debug_inspect(bindings.paths(), content="[\"increment\", \"math#increment\"]")
}

///|
test "WIT binding resolves referenced dependency interfaces" {
  let runtime = @component.ComponentRuntime()
  defer runtime.close()
  let instance = runtime.instantiate(
    "fixture",
    component_runtime_facade_fixture(),
  )
  let root = @wit.parse_package(
    (
      #|package test:demo;
      #|
      #|world demo {
      #|  export dep:math/math@1.0.0;
      #|}
      #|
    ),
  )
  let dependency = @wit.parse_package(
    (
      #|package dep:math@1.0.0;
      #|
      #|interface math {
      #|  increment: func(value: u32) -> u32;
      #|}
      #|
    ),
  )
  let bindings = @wit.resolve_package(root, [dependency]).bind_world(
    "demo", instance,
  )
  debug_inspect(bindings.paths(), content="[\"dep:math/math@1.0.0#increment\"]")
}
