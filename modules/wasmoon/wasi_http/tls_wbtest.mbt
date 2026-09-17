///|
fn test_key(name : String) -> String raise {
  for
    directory in [
      "modules/wasmoon/wasi_http/test_keys", "wasi_http/test_keys", "test_keys",
    ] {
    let path = directory + "/" + name
    if @fs.path_exists(path) {
      return path
    }
  }
  fail("missing HTTP test credential")
}

///|
#cfg(not(platform="windows"))
// The upstream server helper is intentionally test-only; production uses its client API.
#warnings("-alert_internal")
async fn test_tls_server(socket : @socket.Tcp) -> @tls.Tls {
  @tls.Tls::server_from_pair(
    socket,
    socket,
    private_key_file=test_key("key.pem"),
    private_key_type=PEM,
    certificate_file=test_key("cert.pem"),
    certificate_type=PEM,
  )
}

///|
#cfg(platform="windows")
// The upstream server helper is intentionally test-only; production uses its client API.
#warnings("-alert_internal")
async fn test_tls_server(socket : @socket.Tcp) -> @tls.Tls {
  @tls.Tls::server_from_pair(socket, socket, pfx_file=test_key("cert.pfx"))
}

///|
async test "HTTPS verifies custom trust roots and rejects untrusted certificates" {
  @async.with_timeout(10000, async fn() {
    for trusted in [true, false] {
      let server = @socket.TcpServer(@socket.Addr::resolve("localhost", port=0))
      defer server.close()
      @async.with_task_group(async fn(group) {
        group.spawn_bg(async fn() {
          let (socket, _) = server.accept()
          defer socket.close()
          try {
            let tls = test_tls_server(socket)
            defer tls.close()
            let input = HttpInput::{
              reader: tls,
              buffer: b"",
              offset: 0,
              timeout: Some(3000),
              body_deadline: None,
            }
            input.line() |> ignore
            let headers = input.fields()
            input.body(message_framing(headers, false, false), fn(_) {  })
            |> ignore
            tls.write("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
          } catch {
            error => if trusted { raise error }
          }
        })
        let linker = @runtime_impl.ComponentLinker()
        defer linker.close()
        let host = HttpHost(linker)
        host.add_types()
        host.add_network_client(
          _ => true,
          trust=if trusted {
            CustomPemFile(test_key("cert.pem"))
          } else {
            SystemRoot
          },
        )
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
            return fail("missing request")
          }
          let (_, port) = authority_host_port(server.addr.to_string(), true)
          message.attributes.set(
            "authority",
            Variant(1, Some(String("localhost:\{port}"))),
          )
          message.attributes.set("scheme", Variant(1, Some(Variant(1, None))))
          guard linker.get_import("wasi:http/client@0.3.0")
            is Some(Instance(client)) else {
            return fail("missing client")
          }
          let result = host.invoke(client, "send", [request])
          if trusted {
            guard result is [Variant(0, Some(_))] else {
              fail("trusted HTTPS failed: \{repr(result)}")
            }
          } else {
            guard result is [Variant(1, Some(Variant(12, _)))] else {
              fail("untrusted HTTPS was accepted: \{repr(result)}")
            }
          }
        })
      })
    }
  })
}
