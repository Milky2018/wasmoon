///|
test "embedding result futures use the canonical future table" {
  let runtime = HostRuntimeState()
  let table = runtime.resource_table()
  let types : Array[TypeDef?] = [
    Some(
      Variant([
        { label: "io", ty: None, refines: None, },
        { label: "other", ty: Some(TypeIdx(1)), refines: None, },
      ]),
    ),
    Some(Option(Prim(String))),
    Some(Result(None, Some(TypeIdx(0)))),
  ]
  let handle = runtime.new_host_unit_result_future(
    table,
    TypeIdx(2),
    types,
    error_case=0,
  ) catch {
    e => return fail("could not create host future: \{e}")
  }
  guard runtime.async_state.future_endpoints.get(handle_key(table.id, handle))
    is Some(endpoint) else {
    return fail("host future did not allocate a future endpoint")
  }
  debug_inspect(
    (
      runtime.stream_table.endpoints.get(handle_key(table.id, handle)),
      match runtime.async_state.host_future_values.get(endpoint.future_id) {
        Some(source) => poll_host_future_value(source)
        None => Pending
      },
    ),
    content="(None, Ready(Variant(1, Some(Variant(0, None)))))",
  )
}

///|
test "host call futures become first-class component futures" {
  let runtime = HostRuntimeState()
  let table = runtime.resource_table()
  let polled = Ref(false)
  let cancelled = Ref(false)
  let handle = runtime.new_host_call_future(
    table,
    Prim(U8),
    [],
    HostFuture(
      () => {
        if polled.val {
          Ready([U8(7)])
        } else {
          polled.val = true
          Pending
        }
      },
      () => cancelled.val = true,
    ),
  )
  guard runtime.async_state.future_endpoints.get(handle_key(table.id, handle))
    is Some(endpoint) &&
    runtime.async_state.host_future_values.get(endpoint.future_id)
    is Some(source) else {
    return fail("host call future did not allocate a future endpoint")
  }
  debug_inspect(
    [poll_host_future_value(source), poll_host_future_value(source)],
    content="[Pending, Ready(U8(7))]",
  )
  runtime.drop_host_readable_future(table, handle)
  debug_inspect(cancelled.val, content="true")
}

///|
test "dynamic host future sources are polled without blocking" {
  let ready = Ref(false)
  let source : HostFutureValue = {
    payload_ty: Prim(U8),
    types: [],
    value: Ref(None),
    pull: Some(fn() {
      if ready.val {
        Ready(U8(7))
      } else {
        ready.val = true
        Pending
      }
    }),
    cancel: None,
  }
  debug_inspect(
    [poll_host_future_value(source), poll_host_future_value(source)],
    content="[Pending, Ready(U8(7))]",
  )
}

///|
test "dynamic host stream sources are polled without blocking" {
  let ready = Ref(false)
  let source : HostValueStream = {
    payload_ty: Prim(U8),
    types: [],
    values: [],
    next: Ref(0),
    pull: Some(fn(_maximum) {
      if ready.val {
        Values([U8(7)])
      } else {
        ready.val = true
        Pending
      }
    }),
    cancel: None,
    closed: Ref(false),
  }
  debug_inspect(
    [poll_host_value_stream(source, 1), poll_host_value_stream(source, 1)],
    content="[Pending, Values([U8(7)])]",
  )
}

///|
test "dropping a dynamic host stream cancels its reactor source" {
  let runtime = HostRuntimeState()
  let table = runtime.resource_table()
  let events : Array[String] = []
  let readable = runtime.new_host_value_stream_source(
    table,
    Prim(U8),
    [],
    _maximum => Pending,
    () => events.push("cancelled"),
  ) catch {
    e => return fail("could not create dynamic host stream: \{e}")
  }
  runtime.drop_host_readable_stream(table, readable) catch {
    e => return fail("could not drop dynamic host stream: \{e}")
  }
  debug_inspect(events, content="[\"cancelled\"]")
}

///|
test "embedding reads dynamic streams with pending and EOF" {
  let runtime = HostRuntimeState()
  let table = runtime.resource_table()
  let step = Ref(0)
  let handle = runtime.new_host_value_stream_source(
    table,
    Prim(U8),
    [],
    _ => {
      step.val += 1
      match step.val {
        1 => Pending
        2 => Values([U8(65), U8(66)])
        _ => Closed
      }
    },
    () => (),
  )
  debug_inspect(runtime.read_host_byte_stream(table, handle), content="Pending")
  debug_inspect(
    runtime.read_host_byte_stream(table, handle),
    content="Data(<Bytes: [0x41, 0x42]>)",
  )
  debug_inspect(runtime.read_host_byte_stream(table, handle), content="Closed")
  runtime.drop_host_readable_stream(table, handle)
}

///|
test "embedding future reads are nonblocking and single use" {
  let runtime = HostRuntimeState()
  let table = runtime.resource_table()
  let ready = Ref(false)
  let handle = runtime.new_host_value_future_source(
    table,
    Prim(U8),
    [],
    () => {
      if ready.val {
        Ready(U8(42))
      } else {
        ready.val = true
        Pending
      }
    },
    () => (),
  )
  debug_inspect(
    runtime.read_host_value_future(table, handle),
    content="Pending",
  )
  debug_inspect(
    runtime.read_host_value_future(table, handle),
    content="Ready(U8(42))",
  )
  let repeated = try? runtime.read_host_value_future(table, handle)
  debug_inspect(
    repeated,
    content="Err(HostCallError(\"host future already read or busy\"))",
  )
  runtime.drop_host_readable_future(table, handle)
}

///|
test "embedding future read transfers owned resources from the producer table" {
  let runtime = HostRuntimeState()
  let source = runtime.resource_table()
  let target = ResourceTable()
  runtime.async_state.resource_tables.set(target.id, target)
  let resource = source.alloc({
    type_id: 71,
    rep: 99,
    dtor: None,
    host_dtor: None,
    kind: HostDefined,
    impl_component_id: source.id,
    own: true,
    borrow_scope: None,
    num_lends: [0],
  })
  let types : Array[TypeDef?] = [
    Some(ResourceType(71, 0x7f, None, HostDefined)),
    Some(Own(0)),
  ]
  let readable = runtime.new_host_value_future(
    source,
    TypeIdx(1),
    types,
    U32(resource),
  )
  let moved = transfer_future_readable_handle(
    runtime.async_state,
    source.id,
    target.id,
    readable,
  )
  guard runtime.read_host_value_future(target, moved) is Ready(U32(received)) else {
    return fail("expected owned resource")
  }
  inspect(source.get(resource) is None, content="true")
  inspect(target.get(received).unwrap().rep, content="99")
  runtime.drop_host_readable_future(target, moved)
  inspect(runtime.async_state.futures.length(), content="0")
}
