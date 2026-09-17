///|
async test "network client preserves duplicate fields, bytes and chunked trailers" {
  @async.with_timeout(5000, async fn() {
    let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    @async.with_task_group(async fn(group) {
      group.spawn_bg(async fn() {
        let (socket, _) = server.accept()
        defer socket.close()
        let input = HttpInput::{
          reader: socket,
          buffer: b"",
          offset: 0,
          timeout: Some(2000),
          between_timeout: Some(2000),
        }
        assert_eq(ascii_text(input.line()), "GET / HTTP/1.1")
        let headers = input.fields()
        input.body(message_framing(headers, false, false), async fn(_) {  })
        |> ignore
        socket.write(
          b"HTTP/1.1 200 OK\r\nX-Repeat: one\r\nx-repeat: two\r\nX-Raw: \xff\r\nTransfer-Encoding: chunked\r\n\r\n2\r\nhi\r\n0\r\nX-Trailer: done\r\n\r\n",
        )
      })
      let linker = @runtime_impl.ComponentLinker()
      defer linker.close()
      let host = HttpHost(linker)
      host.add_types()
      host.add_network_client(_ => true)
      host.run(async fn() {
        let table = host.runtime.resource_table()
        let headers = host.allocate(
          table,
          "fields",
          Fields(HttpFields::from_list().unwrap()),
        )
        let trailers = host.runtime.new_host_value_future(
          table,
          host.future_payload(1),
          host.types,
          Variant(0, Some(Variant(0, None))),
        )
        guard host.new_message(
            false,
            [headers, Variant(0, None), U32(trailers), Variant(0, None)],
            table,
          )
          is Tuple([request, _]) else {
          return fail("missing request")
        }
        guard host.get(table, request, "request") is Message(message) else {
          return fail("missing message")
        }
        message.attributes.set(
          "authority",
          Variant(1, Some(String(server.addr.to_string()))),
        )
        guard linker.get_import("wasi:http/client@0.3.0")
          is Some(Instance(client)) else {
          return fail("missing client")
        }
        guard host.invoke(client, "send", [request])
          is [Variant(0, Some(response))] else {
          return fail("network send failed")
        }
        guard host.take(table, response, "response") is Message(message) else {
          return fail("missing response")
        }
        assert_eq(message.headers.get("x-repeat"), [b"one", b"two"])
        assert_eq(message.headers.get("x-raw"), [b"\xff"])
        let receipt = host.runtime.new_host_value_future(
          table,
          host.future_payload(0),
          host.types,
          Variant(0, None),
        )
        guard host.consume_body(message, receipt, table)
          is Tuple([U32(contents), U32(trailers)]) else {
          return fail("missing body")
        }
        host.wake.broadcast()
        let received : Array[Byte] = []
        while host.read_body(table, contents) is Some(bytes) {
          received.append(bytes.to_array())
        }
        assert_eq(Bytes::from_array(received), b"hi")
        guard host.read_future(table, trailers)
          is Variant(0, Some(Variant(1, Some(handle)))) &&
          host.take(table, handle, "fields") is Fields(fields) else {
          return fail("missing trailers")
        }
        assert_eq(fields.get("x-trailer"), [b"done"])
      })
    })
  })
}
