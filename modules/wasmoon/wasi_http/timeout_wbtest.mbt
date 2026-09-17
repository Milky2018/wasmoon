///|
async fn check_response_timeout(
  first_byte : Int64,
  between_bytes : Int64,
  reply : async (@socket.Tcp) -> Unit,
  expected : Bytes,
  fails : Bool,
) -> Unit {
  @async.with_timeout(5000, async fn() {
    let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
    defer server.close()
    @async.with_task_group(async fn(group) {
      group.spawn_bg(no_wait=true, async fn() {
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
        reply(socket)
      })
      let linker = @runtime_impl.ComponentLinker()
      defer linker.close()
      let host = HttpHost(linker)
      host.add_types()
      host.add_network_client(_ => true)
      host.run(async fn() {
        let table = host.runtime.resource_table()
        guard linker.get_import("wasi:http/types@0.3.0")
          is Some(Instance(types)) else {
          return fail("missing types")
        }
        let options = types.call_exported_func("[constructor]request-options", [])[0]
        for
          (name, duration) in [
            ("first-byte", first_byte),
            ("between-bytes", between_bytes),
          ] {
          assert_eq(
            types.call_exported_func(
              "[method]request-options.set-" + name + "-timeout",
              [options, Variant(1, Some(U64(duration)))],
            ),
            [Variant(0, None)],
          )
        }
        let headers = types.call_exported_func("[constructor]fields", [])[0]
        let trailers = host.runtime.new_host_value_future(
          table,
          host.future_payload(1),
          host.types,
          Variant(0, Some(Variant(0, None))),
        )
        guard types.call_exported_func("[static]request.new", [
            headers,
            Variant(0, None),
            U32(trailers),
            Variant(1, Some(options)),
          ])
          is [Tuple([request, _])] else {
          return fail("missing request")
        }
        assert_eq(
          types.call_exported_func("[method]request.set-authority", [
            request,
            Variant(1, Some(String(server.addr.to_string()))),
          ]),
          [Variant(0, None)],
        )
        guard linker.get_import("wasi:http/client@0.3.0")
          is Some(Instance(client)) else {
          return fail("missing client")
        }
        let response = host.invoke(client, "send", [request])
        if response is [Variant(1, Some(Variant(9, None)))] {
          assert_true(fails)
          assert_eq(expected, b"")
          return
        }
        guard response is [Variant(0, Some(response))] else {
          return fail("unexpected send result")
        }
        let receipt = host.runtime.new_host_value_future(
          table,
          host.future_payload(0),
          host.types,
          Variant(0, None),
        )
        guard types.call_exported_func("[static]response.consume-body", [
            response,
            U32(receipt),
          ])
          is [Tuple([U32(contents), U32(trailers)])] else {
          return fail("missing body")
        }
        host.wake.broadcast()
        let bytes : Array[Byte] = []
        while host.read_body(table, contents) is Some(chunk) {
          bytes.append(chunk.to_array())
        }
        assert_eq(Bytes::from_array(bytes), expected)
        assert_eq(
          host.read_future(table, trailers),
          if fails {
            http_error(9)
          } else {
            Variant(0, Some(Variant(0, None)))
          },
        )
      })
    })
  })
}

///|
async test "first body byte keeps its budget through headers and chunk framing" {
  check_response_timeout(
    1000000000L,
    10000000L,
    async fn(socket) {
      socket.write(
        b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n2;name=value\r\n",
      )
      @async.sleep(100)
      socket.write(b"hi\r\n0\r\n\r\n")
    },
    b"hi",
    false,
  )
}

///|
async test "long between-byte budget cannot extend the first body byte deadline" {
  check_response_timeout(
    30000000L,
    1000000000L,
    async fn(socket) {
      socket.write(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n")
      @async.sleep(200)
      socket.write(b"hi")
    },
    b"",
    true,
  )
}

///|
async test "between-byte timeout starts after the first body data" {
  check_response_timeout(
    1000000000L,
    30000000L,
    async fn(socket) {
      socket.write(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nh")
      @async.sleep(200)
      socket.write(b"i")
    },
    b"h",
    true,
  )
}

///|
async test "informational and partial headers do not restart the first-byte deadline" {
  check_response_timeout(
    80000000L,
    1000000000L,
    async fn(socket) {
      socket.write(
        b"HTTP/1.1 103 Early Hints\r\n\r\nHTTP/1.1 200 OK\r\nX-Slow: ",
      )
      for _ in 0..<6 {
        @async.sleep(30)
        socket.write(b"x")
      }
      socket.write(b"\r\nContent-Length: 2\r\n\r\nhi")
    },
    b"",
    true,
  )
}

///|
async test "empty response does not wait for a first body byte" {
  check_response_timeout(
    1000000000L,
    30000000L,
    async fn(socket) { socket.write(b"HTTP/1.1 204 No Content\r\n\r\n") },
    b"",
    false,
  )
}
