///|
async test "dropping a response body interrupts a stalled network read" {
  @async.with_timeout(5000, async fn() {
    let peer_closed = Ref(false)
    let closed = @async.CondVar::Cond()
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
          first_byte: None,
        }
        assert_eq(ascii_text(input.line()), "GET / HTTP/1.1")
        let headers = input.fields()
        input.body(message_framing(headers, false, false), fn(_) {  }) |> ignore
        socket.write(b"HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n")
        assert_eq(socket.read_some(max_len=1), None)
        peer_closed.val = true
        closed.broadcast()
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
        host.runtime.drop_host_readable_stream(table, contents)
        host.runtime.drop_host_readable_future(table, trailers)
        host.wake.broadcast()
        @async.with_timeout(2000, async fn() {
          while !peer_closed.val {
            closed.wait()
          }
        })
      })
    })
  })
}
