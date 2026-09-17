///|
test "fields retain repeated values, casing and order" {
  let fields = HttpFields::from_list(entries=[
    ("X-Test", b"one"),
    ("x-test", b"two"),
    ("Empty", b""),
  ]).unwrap()
  inspect(fields.get("X-TEST"), content="[b\"one\", b\"two\"]")
  inspect(fields.has("empty"), content="true")
  inspect(fields.get("absent"), content="[]")
  assert_eq(fields.copy_all(), [
    ("X-Test", b"one"),
    ("x-test", b"two"),
    ("Empty", b""),
  ])
}

///|
test "failed field mutations are atomic" {
  let fields = HttpFields::from_list(entries=[("x", b"original")]).unwrap()
  debug_inspect(
    fields.set("x", [b"valid", b"bad\r\ninjection"]),
    content="Err(InvalidSyntax)",
  )
  inspect(fields.get("x"), content="[b\"original\"]")
  debug_inspect(fields.append("Connection", b"close"), content="Err(Forbidden)")
  debug_inspect(
    fields.append("invalid name", b"value"),
    content="Err(InvalidSyntax)",
  )
  inspect(fields.copy_all().length(), content="1")
  let copy = fields.clone()
  copy.set("x", [b"copy"]).unwrap()
  inspect(fields.get("x"), content="[b\"original\"]")
}
