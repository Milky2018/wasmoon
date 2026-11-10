///|
test "component conformance JSON roundtrips control characters" {
  let text = "\u{0000}\u{0001}\u{0008}\u{000C}\t\r\n\"\\😀"
  let result = ScriptResult::ScriptResult()
  result.add_failed(text)
  assert_eq(
    @json.parse(component_test_json(false, None, text, text, Some(result))),
    @json.Json::object(
      Map([
        ("ok", @json.Json::boolean(false)),
        ("phase", @json.Json::string(text)),
        ("detail", @json.Json::string(text)),
        ("passed", @json.to_json(0)),
        ("failed", @json.to_json(1)),
        ("skipped", @json.to_json(0)),
        ("failures", @json.to_json([text])),
      ]),
    ),
  )
}

///|
test "component conformance JSON status fields remain stable" {
  let result = ScriptResult::ScriptResult()
  result.add_passed()
  result.add_failed("x")
  let json = component_test_json(
    false,
    Some(CompTestAssertFailed),
    "execute",
    "component-test has failing commands",
    Some(result),
  )
  inspect(json.contains("\"ok\":false"), content="true")
  inspect(json.contains("\"code\":\"COMP_TEST_ASSERT_FAILED\""), content="true")
  inspect(json.contains("\"passed\":1"), content="true")
  inspect(json.contains("\"failed\":1"), content="true")
}

///|
test "component conformance parses typed named composite values" {
  let types : Array[@component_types.TypeDef?] = [
    Some(Enum(["red", "green", "blue"])),
    Some(Flags(["a", "b", "c"])),
    Some(
      Variant([
        { label: "number", ty: Some(Prim(U32)), refines: None, },
        { label: "text", ty: Some(Prim(String)), refines: None, },
      ]),
    ),
    Some(
      Record([
        { label: "color", ty: TypeIdx(0), },
        { label: "features", ty: TypeIdx(1), },
        { label: "payload", ty: TypeIdx(2), },
      ]),
    ),
  ]
  let value : JsonValue = {
    type_: "record",
    value: None,
    label: None,
    labels: None,
    items: Some([
      {
        type_: "variant",
        value: Some("text"),
        label: Some("payload"),
        labels: None,
        items: Some([
          {
            type_: "str",
            value: Some("ok"),
            label: None,
            labels: None,
            items: None,
          },
        ]),
      },
      {
        type_: "flags",
        value: None,
        label: Some("features"),
        labels: Some(["a", "c"]),
        items: None,
      },
      {
        type_: "enum",
        value: Some("green"),
        label: Some("color"),
        labels: None,
        items: None,
      },
    ]),
  }
  debug_inspect(
    parse_typed_component_value(value, TypeIdx(3), types),
    content="([U32(1), U32(5), Variant(1, Some(String(\"ok\")))])",
  )
}
