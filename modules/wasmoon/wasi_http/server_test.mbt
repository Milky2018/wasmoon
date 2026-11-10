///|
async test "HTTP server reports request errors and closes cancelled connections" {
  for cancel in [false, true] {
    @async.with_timeout(5000, async fn() {
      let listener = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
      defer listener.close()
      let linker = @runtime_impl.ComponentLinker()
      defer linker.close()
      let component = @component_validator.validate_component_for_instantiation(
        @component.parse_component(b"\x00asm\x0d\x00\x01\x00"),
      )
      let instance = linker.instantiate("empty-service", component)
      let host = @wasi_http.HttpHost(linker)
      let ready = Ref(false)
      let wake = @async.CondVar::Cond()
      let failure : Ref[String?] = Ref(None)
      @async.with_task_group(async fn(group) {
        let serving = group.spawn(async fn() {
          let (socket, _) = listener.accept()
          defer socket.close()
          host.run(async fn() {
            ready.val = true
            wake.broadcast()
            host.serve_connection(socket, instance)
          }) catch {
            error => failure.val = Some(error.to_string())
          }
        })
        let client = @socket.Tcp::connect(listener.addr)
        defer client.close()
        client.write(if cancel { b"GET / HT" } else { b"INVALID\r\n\r\n" })
        while !ready.val {
          wake.wait()
        }
        if cancel {
          serving.cancel()
        }
        let response : Array[Byte] = []
        while client.read_some() is Some(bytes) {
          response.append(bytes.to_array())
        }
        if cancel {
          assert_true(response.is_empty())
          assert_eq(failure.val, None)
        } else {
          assert_eq(
            Bytes::from_array(response),
            b"HTTP/1.1 400 Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
          )
          assert_true(
            failure.val is Some(message) &&
            message.contains("HttpTransportError"),
            msg="Unexpected request error: \{Repr(failure.val)}",
          )
        }
      })
    })
  }
}
