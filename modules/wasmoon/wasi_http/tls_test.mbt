// Keep TLS credential setup in the blackbox executable: synchronous backend
// initialization must not share an event loop with the whitebox HTTP timers.

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
            if trusted &&
              @env.get_env_var("WASMOON_TEST_BLOCKING_TLS_SETUP") == Some("1") {
              // CI proves that blocking credential setup cannot starve the
              // whitebox HTTP tests. Delay only the first setup, not its budget.
              let stop = @async.now() + 3200L
              while @async.now() < stop {
                ()
              }
            }
            let tls = test_tls_server(socket)
            defer tls.close()
            @async.with_timeout(3000, async fn() {
              guard tls.read_until("\r\n\r\n") is Some(headers) else {
                return fail("missing HTTPS request headers")
              }
              assert_true(headers.has_prefix("GET / HTTP/1.1\r\n"))
              assert_true(headers.contains("Transfer-Encoding: chunked"))
              // Consume the complete empty request before closing the peer.
              assert_eq(tls.read_until("\r\n\r\n"), Some("0"))
              tls.write("HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
            })
          } catch {
            error => if trusted { raise error }
          }
        })
        let linker = @runtime_impl.ComponentLinker()
        defer linker.close()
        let host = @wasi_http.HttpHost(linker)
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
          guard linker.get_import("wasi:http/types@0.3.0")
            is Some(Instance(types)) else {
            return fail("missing HTTP types")
          }
          guard types.get_export("[static]request.new")
            is Some(Func(Host(signature, type_space, _))) &&
            signature.params[2].ty is TypeIdx(index) &&
            type_space[index] is Some(Future(Some(payload))) else {
            return fail("missing request trailer type")
          }
          let headers = types.call_exported_func("[constructor]fields", [])[0]
          let trailers = linker
            .host_runtime_state()
            .new_host_value_future(
              types.resource_table,
              payload,
              type_space,
              Variant(0, Some(Variant(0, None))),
            )
          guard types.call_exported_func("[static]request.new", [
              headers,
              Variant(0, None),
              U32(trailers),
              Variant(0, None),
            ])
            is [Tuple([request, _])] else {
            return fail("missing request")
          }
          assert_eq(
            types.call_exported_func("[method]request.set-authority", [
              request,
              Variant(1, Some(String("localhost:\{server.addr.port()}"))),
            ]),
            [Variant(0, None)],
          )
          assert_eq(
            types.call_exported_func("[method]request.set-scheme", [
              request,
              Variant(1, Some(Variant(1, None))),
            ]),
            [Variant(0, None)],
          )
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
