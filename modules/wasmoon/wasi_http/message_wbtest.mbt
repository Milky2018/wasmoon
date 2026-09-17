///|
test "response body completion waits for EOF and consumer receipt" {
  let linker = @runtime_impl.ComponentLinker()
  defer linker.close()
  let host = HttpHost(linker)
  host.add_types()
  guard linker.get_import("wasi:http/types@0.3.0") is Some(Instance(types)) else {
    return fail("missing HTTP types")
  }
  let table = host.runtime.resource_table()
  let headers = types.call_exported_func("[constructor]fields", [])[0]
  let body = host.runtime.new_host_byte_stream(table, b"stream")
  let trailers = host.runtime.new_host_value_future(
    table,
    host.future_payload(1),
    host.types,
    Variant(0, Some(Variant(0, None))),
  )
  guard types.call_exported_func("[static]response.new", [
      headers,
      Variant(1, Some(U32(body))),
      U32(trailers),
    ])
    is [Tuple([response, U32(completion)])] else {
    return fail("response construction failed")
  }
  let frozen = types.call_exported_func("[method]response.get-headers", [
      response,
    ])[0]
  assert_eq(
    types.call_exported_func("[method]fields.append", [
      frozen,
      String("x"),
      List([]),
    ]),
    [Variant(1, Some(Variant(2, None)))],
  )
  let receipt_value = Ref(None)
  let receipt = host.runtime.new_host_value_future_source(
    table,
    host.future_payload(0),
    host.types,
    () => {
      match receipt_value.val {
        Some(value) => Ready(value)
        None => Pending
      }
    },
    () => (),
  )
  guard types.call_exported_func("[static]response.consume-body", [
      response,
      U32(receipt),
    ])
    is [Tuple([U32(contents), U32(trailers)])] else {
    return fail("consume body failed")
  }
  host.poll() |> ignore
  debug_inspect(
    host.runtime.read_host_value_future(table, trailers),
    content="Pending",
  )
  guard host.runtime.read_host_byte_stream(table, contents) is Data(bytes) else {
    return fail("missing body bytes")
  }
  assert_eq(bytes, b"stream")
  host.poll() |> ignore
  debug_inspect(
    host.runtime.read_host_value_future(table, trailers),
    content="Pending",
  )
  debug_inspect(
    host.runtime.read_host_byte_stream(table, contents),
    content="Closed",
  )
  guard host.runtime.read_host_value_future(table, trailers)
    is Ready(Variant(0, Some(Variant(0, None)))) else {
    return fail("missing trailers result")
  }
  debug_inspect(
    host.runtime.read_host_value_future(table, completion),
    content="Pending",
  )
  receipt_value.val = Some(Variant(0, None))
  host.poll() |> ignore
  guard host.runtime.read_host_value_future(table, completion)
    is Ready(Variant(0, None)) else {
    return fail("transmission did not complete")
  }
  inspect(host.bodies.length(), content="0")
}

///|
test "dropping trailers releases an undelivered fields resource" {
  let linker = @runtime_impl.ComponentLinker()
  defer linker.close()
  let host = HttpHost(linker)
  host.add_types()
  let table = host.runtime.resource_table()
  let fields = host.allocate(
    table,
    "fields",
    Fields(HttpFields::from_list(entries=[("x-end", b"value")]).unwrap()),
  )
  let trailers = host.runtime.new_host_value_future(
    table,
    host.future_payload(1),
    host.types,
    Variant(0, Some(Variant(1, Some(fields)))),
  )
  let headers = host.allocate(
    table,
    "fields",
    Fields(HttpFields::from_list().unwrap()),
  )
  guard host.new_message(
      true,
      [headers, Variant(0, None), U32(trailers)],
      table,
    )
    is Tuple([response, _]) else {
    return fail("missing response")
  }
  guard host.take(table, response, "response") is Message(message) else {
    return fail("missing response")
  }
  let receipt = host.runtime.new_host_value_future(
    table,
    host.future_payload(0),
    host.types,
    Variant(0, None),
  )
  guard host.consume_body(message, receipt, table)
    is Tuple([U32(stream), U32(trailers)]) else {
    return fail("missing body")
  }
  host.poll() |> ignore
  assert_eq(host.resources.length(), 1)
  host.runtime.drop_host_readable_future(table, trailers)
  host.runtime.drop_host_readable_stream(table, stream)
  host.poll() |> ignore
  assert_eq(host.resources.length(), 0)
  assert_eq(host.bodies.length(), 0)
}

///|
test "cancelling a body drops its producer and completes the transmission" {
  let linker = @runtime_impl.ComponentLinker()
  defer linker.close()
  let host = HttpHost(linker)
  host.add_types()
  let table = host.runtime.resource_table()
  let cancelled = Ref(false)
  let source = host.runtime.new_host_value_stream_source(
    table,
    Prim(U8),
    [],
    _ => Pending,
    () => cancelled.val = true,
  )
  let trailers = host.runtime.new_host_value_future_source(
    table,
    host.future_payload(1),
    host.types,
    () => Pending,
    () => (),
  )
  let headers = host.allocate(
    table,
    "fields",
    Fields(HttpFields::from_list().unwrap()),
  )
  guard host.new_message(
      true,
      [headers, Variant(1, Some(U32(source))), U32(trailers)],
      table,
    )
    is Tuple([response, U32(completion)]) else {
    return fail("missing response")
  }
  guard host.take(table, response, "response") is Message(message) else {
    return fail("missing response")
  }
  let receipt = host.runtime.new_host_value_future_source(
    table,
    host.future_payload(0),
    host.types,
    () => Pending,
    () => (),
  )
  guard host.consume_body(message, receipt, table) is Tuple([U32(stream), _]) else {
    return fail("missing stream")
  }
  host.runtime.drop_host_readable_stream(table, stream)
  host.poll() |> ignore
  assert_true(cancelled.val)
  guard host.runtime.read_host_value_future(table, completion)
    is Ready(Variant(1, _)) else {
    fail("cancelled transmission did not fail")
  }
}
