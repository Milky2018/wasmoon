///|
test "HTTP URI setters reject invalid syntax without changing the value" {
  let linker = @runtime_impl.ComponentLinker()
  defer linker.close()
  let host = HttpHost(linker)
  host.add_types()
  guard linker.get_import("wasi:http/types@0.3.0") is Some(Instance(types)) else {
    return fail("missing HTTP types")
  }
  let table = host.runtime.resource_table()
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
      Variant(0, None),
    ])
    is [Tuple([request, _])] else {
    return fail("missing request")
  }
  let paths : Array[@runtime_impl.ComponentValue] = [
    Variant(0, None),
    Variant(1, Some(String(""))),
    Variant(1, Some(String("/"))),
  ]
  for value in paths {
    assert_eq(
      types.call_exported_func("[method]request.set-path-with-query", [
        request, value,
      ]),
      [Variant(0, None)],
    )
    assert_eq(
      types.call_exported_func("[method]request.get-path-with-query", [request]),
      [value],
    )
  }
  // Resource syntax is independent of whether the HTTP transport can use it.
  for
    text in [
      "", "user@host", "user:pass%20@localhost:80", "host:65536", "host:", "[::1]:443",
    ] {
    let value : @runtime_impl.ComponentValue = Variant(1, Some(String(text)))
    assert_eq(
      types.call_exported_func("[method]request.set-authority", [request, value]),
      [Variant(0, None)],
    )
    assert_eq(
      types.call_exported_func("[method]request.get-authority", [request]),
      [value],
    )
  }
  for
    (name, valid, invalid) in [
      (
        "path-with-query",
        "/valid%2fpath?q=%ff/a?b",
        ["/<bad>/ok", "/%GG", "/%", "/a#fragment", "/a\\b", "/é"],
      ),
      (
        "authority",
        "[::1]:8080",
        ["<bad>", "bad%GG", "a/b", "a?b", "[::gg]", "host:abc", "host#fragment"],
      ),
      ("scheme", "custom+v1", ["1http", "ht<tp", "http:"]),
    ] {
    fn value(text : String) -> @runtime_impl.ComponentValue {
      let value : @runtime_impl.ComponentValue = if name == "scheme" {
        Variant(2, Some(String(text)))
      } else {
        String(text)
      }
      Variant(1, Some(value))
    }
    let setter = "[method]request.set-" + name
    let getter = "[method]request.get-" + name
    assert_eq(types.call_exported_func(setter, [request, value(valid)]), [
      Variant(0, None),
    ])
    for text in invalid {
      assert_eq(types.call_exported_func(setter, [request, value(text)]), [
        Variant(1, None),
      ])
      assert_eq(types.call_exported_func(getter, [request]), [value(valid)])
    }
  }
}

///|
test "HTTP transport rejects authorities that only satisfy URI syntax" {
  for authority in ["", "user@host", "user:pass%20@localhost:80", "host:65536"] {
    let rejected = try authority_host_port(authority, false) catch {
      HttpTransportError(19, _) => true
      _ => false
    } noraise {
      _ => false
    }
    assert_true(rejected)
  }
  assert_eq(authority_host_port("localhost:8080", false), ("localhost", 8080))
}
