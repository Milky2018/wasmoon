///|
test "HTTP fields are callable through the generated component interface" {
  let linker = @runtime_impl.ComponentLinker()
  defer linker.close()
  let host = HttpHost(linker)
  host.add_types()
  guard linker.get_import("wasi:http/types@0.3.0") is Some(Instance(types)) else {
    return fail("HTTP types missing")
  }
  guard types.call_exported_func("[constructor]fields", []) is [handle] else {
    return fail("fields constructor failed")
  }
  assert_eq(
    types.call_exported_func("[method]fields.append", [
      handle,
      String("X-A"),
      List([U8(65)]),
    ]),
    [Variant(0, None)],
  )
  assert_eq(
    types.call_exported_func("[method]fields.append", [
      handle,
      String("x-a"),
      List([U8(66)]),
    ]),
    [Variant(0, None)],
  )
  assert_eq(
    types.call_exported_func("[method]fields.get-and-delete", [
      handle,
      String("X-A"),
    ]),
    [Variant(0, Some(List([List([U8(65)]), List([U8(66)])])))],
  )
  assert_eq(
    types.call_exported_func("[method]fields.has", [handle, String("x-a")]),
    [Bool(false)],
  )
}

///|
test "HTTP request options clone independently" {
  let linker = @runtime_impl.ComponentLinker()
  defer linker.close()
  let host = HttpHost(linker)
  host.add_types()
  guard linker.get_import("wasi:http/types@0.3.0") is Some(Instance(types)) else {
    return fail("HTTP types missing")
  }
  let options = types.call_exported_func("[constructor]request-options", [])[0]
  assert_eq(
    types.call_exported_func("[method]request-options.set-connect-timeout", [
      options,
      Variant(1, Some(U64(123L))),
    ]),
    [Variant(0, None)],
  )
  let copy = types.call_exported_func("[method]request-options.clone", [options])[0]
  types.call_exported_func("[method]request-options.set-connect-timeout", [
    copy,
    Variant(0, None),
  ])
  |> ignore
  assert_eq(
    types.call_exported_func("[method]request-options.get-connect-timeout", [
      options,
    ]),
    [Variant(1, Some(U64(123L)))],
  )
  assert_eq(
    types.call_exported_func("[method]request-options.get-connect-timeout", [
      copy,
    ]),
    [Variant(0, None)],
  )
}
