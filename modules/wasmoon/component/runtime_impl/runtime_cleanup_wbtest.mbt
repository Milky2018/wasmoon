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
    { params: [], results: [] },
    fn(_arguments) { [] },
  )
  let result = try {
    linker.core_engine.invoke(
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
    { params: [], results: [] },
    fn(_arguments) { [] },
  )
  let outcome = linker.core_engine.invoke(
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
