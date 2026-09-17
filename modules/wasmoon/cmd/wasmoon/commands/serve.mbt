///|
/// Serve an HTTP 0.3 service with a fresh component instance per connection.
pub async fn serve_http(
  file : String,
  middleware : Array[String],
  address : String,
  network : String,
  use_jit : Bool,
) -> Int {
  try {
    let component = load_http_service(file)
    let layers = middleware.map(path => load_http_service(path))
    let server = @socket.TcpServer(
      @socket.Addr::parse(address),
      reuse_addr=true,
    )
    defer server.close()
    @logger.info("Serving \{file} on http://\{server.addr}")
    server.run_forever(
      async fn(socket, _) {
        defer socket.close()
        let linker = if use_jit {
          @runtime_impl.ComponentLinker::with_core_execution_engine(
            @component_native.open_native_component_session(opt_level=0),
          )
        } else {
          ComponentLinker()
        }
        defer linker.close()
        let ctx = @wasi_component.WasiComponentCtxBuilder()
          .inherit_stdout()
          .inherit_stderr()
          .build()
        defer ctx.close()
        let host = @wasi_http.HttpHost(linker)
        host.add_types()
        host.add_service_base(ctx)
        host.add_network_client(_ => network != "deny", allow_address=fn(addr) {
          network == "all" ||
          (
            network == "loopback" &&
            (
              addr.to_string().has_prefix("127.") ||
              addr.to_string().has_prefix("[::1]:")
            )
          )
        })
        host.run(async fn() {
          let mut instance = linker.instantiate("http-service", component)
          for index = layers.length() - 1; index >= 0; index = index - 1 {
            host.add_downstream(instance)
            instance = linker.instantiate(
              "http-middleware-\{index}",
              layers[index],
            )
          }
          host.serve_connection(socket, instance)
        }) catch {
          error => @logger.error("HTTP connection failed: \{error}")
        }
      },
      max_connections=256,
      allow_failure=true,
    )
    0
  } catch {
    error => {
      @logger.error("HTTP server failed: \{error}")
      1
    }
  }
}

///|
fn load_http_service(
  path : String,
) -> @component_model.ValidatedComponent raise {
  let parsed = @component_types.parse_component(@fs.read_file_to_bytes(path))
  let validated = @component_model.validate_component_for_instantiation(parsed)
  if !parsed.exports.any(export_ => {
      (
        export_.name is Plain(b"wasi:http/handler@0.3.0") ||
        export_.name is WithVersion(b"wasi:http/handler", b"0.3.0")
      ) &&
      export_.sortidx.sort is Instance
    }) {
    raise @runtime_impl.HostCallError(
      "HTTP service must export wasi:http/handler@0.3.0: " + path,
    )
  }
  validated
}
