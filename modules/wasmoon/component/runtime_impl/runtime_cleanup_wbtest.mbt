///|
test "host stream lifecycle returns live tables to baseline" {
  let runtime = HostRuntimeState()
  let table = runtime.resource_table()
  for i in 0..<512 {
    let handle = runtime.new_host_byte_stream(
      table,
      Bytes::from_array([i.to_byte()]),
    )
    runtime.drop_host_readable_stream(table, handle)
  }
  debug_inspect(
    (
      runtime.stream_table.endpoints.length(),
      runtime.stream_table.streams.length(),
      runtime.stream_table.host_values.length(),
      runtime.async_state.waitable_to_set.length(),
      runtime.async_state.waitable_events.length(),
    ),
    content="(0, 0, 0, 0, 0)",
  )
}

///|
test "host future lifecycle returns live tables to baseline" {
  let runtime = HostRuntimeState()
  let table = runtime.resource_table()
  let cancellations = Ref(0)
  for i in 0..<512 {
    let handle = runtime.new_host_value_future_source(
      table,
      Prim(U32),
      [],
      () => Ready(U32(i)),
      () => cancellations.val = cancellations.val + 1,
    )
    runtime.drop_host_readable_future(table, handle)
  }
  debug_inspect(
    (
      runtime.async_state.future_endpoints.length(),
      runtime.async_state.futures.length(),
      runtime.async_state.host_future_values.length(),
      runtime.async_state.waitable_to_set.length(),
      runtime.async_state.waitable_events.length(),
      cancellations.val,
    ),
    content="(0, 0, 0, 0, 0, 512)",
  )
}

///|
test "resource table recycles freed handles without retaining entries" {
  let table = ResourceTable()
  let destructor_calls = Ref(0)
  let entry : ResourceHandle = {
    type_id: 1,
    rep: 7,
    dtor: None,
    host_dtor: Some(
      HostResourceDestructor(rep => {
        if rep != 7 {
          destructor_calls.val = -100
        } else {
          destructor_calls.val = destructor_calls.val + 1
        }
      }),
    ),
    kind: HostDefined,
    impl_component_id: table.id,
    own: true,
    borrow_scope: None,
    num_lends: [0],
  }
  let first = table.alloc(entry)
  match table.free(first) {
    Some(removed) =>
      match removed.host_dtor {
        Some(dtor) => dtor.destroy(removed.rep)
        None => ()
      }
    None => ()
  }
  table.free(first) |> ignore
  let second = table.alloc(entry)
  table.free(second) |> ignore
  debug_inspect(
    (
      first,
      second,
      table.entries.val.length(),
      table.free_handles.val,
      table.next_handle.val,
      destructor_calls.val,
    ),
    content="(1, 1, 0, [1], 2, 1)",
  )
}

///|
test "task metadata cleanup returns all ownership maps to baseline" {
  let async_state = AsyncState(StreamTable())
  for i in 0..<512 {
    let task_id = alloc_task_id(async_state)
    init_task_meta(async_state, task_id, i, 0L)
    async_state.task_borrows.set(task_id, 1)
    async_state.task_borrow_scopes.set(task_id, [[task_id]])
    remove_task_meta(async_state, task_id)
  }
  debug_inspect(
    (
      async_state.task_instance.length(),
      async_state.task_caller.length(),
      async_state.task_borrows.length(),
      async_state.task_borrow_scopes.length(),
    ),
    content="(0, 0, 0, 0)",
  )
}

///|
test "linker close cannot overtake in-flight continuation ownership" {
  let events : Array[String] = []
  let close_linker = Ref(fn() { () })
  let engine = CoreExecutionEngine(
    fn(_store, _module, _instance) { () },
    fn(_store, _instance, _function_index, _arguments, _request) {
      (close_linker.val)()
      Suspended(
        Yield,
        CoreContinuation(fn() { Returned([]) }, fn() {
          events.push("continuation")
        }),
      )
    },
    close=fn() { events.push("engine") },
  )
  let linker = ComponentLinker::with_core_execution_engine(engine)
  close_linker.val = fn() { linker.close() }
  let core_func = alloc_host_core_func(
    linker.get_store(),
    { params: [], results: [], },
    fn(_arguments) { [] },
  )
  let result = try {
    linker
    .core_engine()
    .invoke(
      linker.get_store(),
      core_func.instance,
      0,
      [],
      CoreExecutionRequest(CallbackStep, PreferNative, Resumable),
    )
    |> ignore
    "published"
  } catch {
    Cancelled => "cancelled"
    error => "unexpected: \{error}"
  } noraise {
    result => result
  }
  debug_inspect(
    (result, events),
    content="(\"cancelled\", [\"continuation\", \"engine\"])",
  )
}

///|
test "published continuation lease delays linker teardown" {
  let events : Array[String] = []
  let engine = CoreExecutionEngine(
    fn(_store, _module, _instance) { () },
    fn(_store, _instance, _function_index, _arguments, _request) {
      Suspended(
        Yield,
        CoreContinuation(fn() { Returned([]) }, fn() {
          events.push("continuation")
        }),
      )
    },
    close=fn() { events.push("engine") },
  )
  let linker = ComponentLinker::with_core_execution_engine(engine)
  let core_func = alloc_host_core_func(
    linker.get_store(),
    { params: [], results: [], },
    fn(_arguments) { [] },
  )
  let outcome = linker
    .core_engine()
    .invoke(
      linker.get_store(),
      core_func.instance,
      0,
      [],
      CoreExecutionRequest(CallbackStep, PreferNative, Resumable),
    )
  guard outcome is Suspended(_, continuation) else {
    return fail("expected a suspended managed execution")
  }
  linker.close()
  debug_inspect(events, content="[]")
  continuation.cancel()
  debug_inspect(events, content="[\"continuation\", \"engine\"]")
}

///|
/// Terminal close must drop the linker's reference to its execution engine.
///
/// The engine can reach embedder-supplied closures and native session state.
/// An embedder callback that refers back to its own linker — closing it from
/// inside an engine callback, for example — would otherwise leave a reference
/// cycle that survives close, which reference counting never reclaims.
/// LeakSanitizer caught exactly that shape as an all-indirect leak.
test "terminal close releases the linker's core execution engine" {
  let events : Array[String] = []
  let engine = CoreExecutionEngine(
    fn(_store, _module, _instance) { () },
    fn(_store, _instance, _function_index, _arguments, _request) {
      Returned([])
    },
    close=fn() { events.push("engine") },
  )
  let linker = ComponentLinker::with_core_execution_engine(engine)
  debug_inspect(linker.core_engine_slot.val is Some(_), content="true")
  linker.close()
  // Engine closed exactly once, and no longer retained by the linker.
  debug_inspect(
    (events, linker.core_engine_slot.val is None),
    content="([\"engine\"], true)",
  )
  // Repeated close stays terminal and does not close the engine again.
  linker.close()
  debug_inspect(events, content="[\"engine\"]")
}

///|
test "failed component instantiation withdraws core linker registrations" {
  let provider_bytes = @component_text.parse_component_wat(
    (
      #|(component
      #|  (core module $provider
      #|    (func (export "f") (result i32) (i32.const 7)))
      #|  (core instance $provider (instantiate $provider)))
      #|
    ),
  )
  let provider = @component.parse_component(provider_bytes)
  let provider_validated = @component_validator.validate_component_for_instantiation_with_config(
    provider,
    ComponentValidationConfig(false),
  )
  let bytes = @component_text.parse_component_wat(
    (
      #|(component
      #|  (core module $ok
      #|    (table 1 funcref)
      #|    (memory 1)
      #|    (global i32 (i32.const 1))
      #|    (func (export "f") (result i32) (i32.const 1)))
      #|  (core instance $registered (instantiate $ok))
      #|  (core module $boom (func $start unreachable) (start $start))
      #|  (core instance $trapped (instantiate $boom)))
      #|
    ),
  )
  let component = @component.parse_component(bytes)
  let validated = @component_validator.validate_component_for_instantiation_with_config(
    component,
    ComponentValidationConfig(false),
  )
  let linker = ComponentLinker::ComponentLinker()
  linker.instantiate("provider", provider_validated) |> ignore
  for root_name in ["first", "second"] {
    try linker.instantiate(root_name, validated) catch {
      _ => ()
    } noraise {
      _ => fail("expected core start to trap")
    }
    debug_inspect(
      linker.core_linker.get_module("\{root_name}::coreinst0") is None,
      content="true",
    )
    debug_inspect(
      linker.core_linker.get_module("provider::coreinst0") is Some(_),
      content="true",
    )
  }
  linker.close()
}
