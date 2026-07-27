///|
test "embedding result futures use the canonical future table" {
  let runtime = HostRuntimeState()
  let table = runtime.resource_table()
  let types : Array[TypeDef?] = [
    Some(Enum(["io"])),
    Some(Result(None, Some(TypeIdx(0)))),
  ]
  let handle = runtime.new_host_unit_result_future(table, TypeIdx(1), types) catch {
    e => return fail("could not create host future: \{e}")
  }
  guard runtime.async_state.future_endpoints.get(handle_key(table.id, handle))
    is Some(endpoint) else {
    return fail("host future did not allocate a future endpoint")
  }
  debug_inspect(
    (
      runtime.stream_table.endpoints.get(handle_key(table.id, handle)),
      runtime.async_state.host_future_values.get(endpoint.future_id),
    ),
    content="(None, Some(HostFutureValue))",
  )
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
