///|
test "fields retain repeated values, casing and order" {
  let fields = @wasi_http.HttpFields::from_list(entries=[
    ("X-Test", b"one"),
    ("x-test", b"two"),
    ("Empty", b""),
  ]).unwrap()
  assert_eq(fields.get("X-TEST"), [b"one", b"two"])
  inspect(fields.has("empty"), content="true")
  debug_inspect(fields.get("absent"), content="[]")
  assert_eq(fields.copy_all(), [
    ("X-Test", b"one"),
    ("x-test", b"two"),
    ("Empty", b""),
  ])
}

///|
test "failed field mutations are atomic" {
  let fields = @wasi_http.HttpFields::from_list(entries=[("x", b"original")]).unwrap()
  debug_inspect(
    fields.set("x", [b"valid", b"bad\r\ninjection"]),
    content="Err(InvalidSyntax)",
  )
  assert_eq(fields.get("x"), [b"original"])
  debug_inspect(fields.append("Connection", b"close"), content="Err(Forbidden)")
  debug_inspect(
    fields.append("invalid name", b"value"),
    content="Err(InvalidSyntax)",
  )
  inspect(fields.copy_all().length(), content="1")
  let copy = fields.clone()
  copy.set("x", [b"copy"]).unwrap()
  assert_eq(fields.get("x"), [b"original"])
}

///|
test "deleting a header validates the name without mutating the collection" {
  let fields = @wasi_http.HttpFields::from_list(entries=[("X-Test", b"kept")]).unwrap()
  debug_inspect(fields.delete("invalid name"), content="Err(InvalidSyntax)")
  debug_inspect(fields.delete("Connection"), content="Err(Forbidden)")
  assert_eq(fields.copy_all(), [("X-Test", b"kept")])
}

///|
test "transport-owned headers cannot be installed through fields" {
  for name in ["http2-settings", "HTTP2-Settings", "host", "Host"] {
    let fields = @wasi_http.HttpFields::from_list().unwrap()
    assert_eq(fields.append(name, b"value"), Err(Forbidden))
    assert_eq(fields.set(name, [b"value"]), Err(Forbidden))
    assert_eq(fields.copy_all(), [])
    assert_true(
      @wasi_http.HttpFields::from_list(entries=[(name, b"value")])
      is Err(Forbidden),
    )
  }
}
