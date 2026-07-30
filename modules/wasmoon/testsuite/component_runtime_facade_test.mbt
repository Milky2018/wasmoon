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
fn component_runtime_async_import_fixture() -> Bytes raise @component_text.ComponentTextError {
  @component_text.parse_component_wat(
    (
      #|(component
      #|  (import "host"
      #|    (instance $host
      #|      (export "wait" (func async (result u32)))))
      #|  (alias export $host "wait" (func $wait))
      #|  (export "wait" (func $wait)))
      #|
    ),
  )
}

///|
fn component_runtime_async_host(
  ready : Ref[Bool],
  cancellations : Ref[Int],
) -> @component_host.ComponentHostInstaller {
  @component_host.ComponentHostInstaller::from_linker_installer(fn(
    linker,
  ) raise @runtime_impl.ComponentRuntimeError {
    let host_runtime = linker.host_runtime_state()
    let builder = linker.host_instance_builder("host", host_runtime)
    builder.add_async_func(
      "wait",
      { is_async: true, params: [], result: Some(Prim(U32)) },
      fn(_args, _table) {
        HostFuture(
          fn() { if ready.val { Ready([U32(17)]) } else { Pending } },
          fn() { cancellations.val = cancellations.val + 1 },
        )
      },
    )
    linker.add_import("host", Instance(builder.finish()))
  })
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
test "component engines open independent interpreter sessions" {
  let engine = @component.interpreter_component_engine()
  let first_runtime = @component.ComponentRuntime(engine~)
  defer first_runtime.close()
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
  debug_inspect(
    (
      first.bind("increment").call([U32(1U)]),
      second.bind("increment").call([U32(40U)]),
    ),
    content=(
      #|([U32(2)], [U32(41)])
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
async test "component async join and runtime close share one call lifecycle" {
  let ready = Ref(false)
  let cancellations = Ref(0)
  let runtime = @component.ComponentRuntime(
    engine=@component.interpreter_component_engine(),
  )
  runtime.install(component_runtime_async_host(ready, cancellations))
  let function = runtime
    .instantiate("async-host", component_runtime_async_import_fixture())
    .bind("wait")
  let joined = function.start([])
  let progress = []
  let result = @async.with_task_group(group => {
    let task = group.spawn(no_wait=true, () => joined.join())
    group.spawn_bg() <| () => {
      progress.push("other process ran")
      ready.val = true
    }
    task.wait()
  })
  ready.val = false
  let cancelled = function.start([])
  debug_inspect(cancelled.poll(), content="Pending")
  runtime.close()
  let cancelled_error = try cancelled.poll() catch {
    error => error
  } noraise {
    _ => fail("expected runtime close to cancel the call")
  }
  inspect(
    (result, progress, cancellations.val, cancelled_error),
    content=(
      #|([U32(17)], [other process ran], 1, Cancelled)
    ),
  )
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
