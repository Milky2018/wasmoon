///|
// Inventory from the pinned HTTP middleware world, including base imports.
test "HTTP host registers every pinned middleware function and type" {
  let linker = @runtime_impl.ComponentLinker()
  let ctx = @wasi_component.WasiComponentCtxBuilder().build()
  defer ctx.close()
  defer linker.close()
  let host = HttpHost(linker)
  host.add_types()
  host.add_service_base(ctx)
  host.add_network_client(_ => false)
  host.add_handler((_, _) => raise HostCallError("unused audit handler"))
  let expected : Array[(String, Array[String], Array[String])] = [
    ("wasi:clocks/types@0.3.0", [], ["duration"]),
    (
      "wasi:http/types@0.3.0",
      [
        "[constructor]fields", "[static]fields.from-list", "[method]fields.get",
        "[method]fields.has", "[method]fields.set", "[method]fields.delete", "[method]fields.get-and-delete",
        "[method]fields.append", "[method]fields.copy-all", "[method]fields.clone",
        "[static]request.new", "[method]request.get-method", "[method]request.set-method",
        "[method]request.get-path-with-query", "[method]request.set-path-with-query",
        "[method]request.get-scheme", "[method]request.set-scheme", "[method]request.get-authority",
        "[method]request.set-authority", "[method]request.get-options", "[method]request.get-headers",
        "[static]request.consume-body", "[constructor]request-options", "[method]request-options.get-connect-timeout",
        "[method]request-options.set-connect-timeout", "[method]request-options.get-first-byte-timeout",
        "[method]request-options.set-first-byte-timeout", "[method]request-options.get-between-bytes-timeout",
        "[method]request-options.set-between-bytes-timeout", "[method]request-options.clone",
        "[static]response.new", "[method]response.get-status-code", "[method]response.set-status-code",
        "[method]response.get-headers", "[static]response.consume-body",
      ],
      [
        "duration", "method", "scheme", "DNS-error-payload", "TLS-alert-received-payload",
        "field-size-payload", "error-code", "header-error", "request-options-error",
        "field-name", "field-value", "fields", "headers", "trailers", "request",
        "request-options", "status-code", "response",
      ],
    ),
    (
      "wasi:http/handler@0.3.0",
      ["handle"],
      ["request", "response", "error-code"],
    ),
    ("wasi:cli/types@0.3.0", [], ["error-code"]),
    ("wasi:cli/stdout@0.3.0", ["write-via-stream"], ["error-code"]),
    ("wasi:cli/stderr@0.3.0", ["write-via-stream"], ["error-code"]),
    ("wasi:cli/stdin@0.3.0", ["read-via-stream"], ["error-code"]),
    ("wasi:http/client@0.3.0", ["send"], ["request", "response", "error-code"]),
    (
      "wasi:clocks/monotonic-clock@0.3.0",
      ["now", "get-resolution", "wait-until", "wait-for"],
      ["duration", "mark"],
    ),
    (
      "wasi:clocks/system-clock@0.3.0",
      ["now", "get-resolution"],
      ["duration", "instant"],
    ),
    ("wasi:random/random@0.3.0", ["get-random-bytes", "get-random-u64"], []),
    (
      "wasi:random/insecure@0.3.0",
      ["get-insecure-random-bytes", "get-insecure-random-u64"],
      [],
    ),
    ("wasi:random/insecure-seed@0.3.0", ["get-insecure-seed"], []),
  ]
  let missing : Array[String] = []
  for (name, functions, types) in expected {
    // clocks/types is synthesized from its primitive type equality at linking.
    if name == "wasi:clocks/types@0.3.0" {
      continue
    }
    guard linker.get_import(name) is Some(Instance(instance)) else {
      missing.push("interface: \{name}")
      continue
    }
    for name in functions {
      guard instance.get_export(name) is Some(Func(_)) else {
        missing.push("function: \{name}")
        continue
      }
    }
    for name in types {
      guard instance.get_export(name) is Some(Type(_)) else {
        missing.push("type: \{name}")
        continue
      }
    }
  }
  assert_eq(missing, [])
}
