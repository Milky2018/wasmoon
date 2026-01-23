///|
test "wit component encode (minimal)" {
  let src =
    #|package local:demo;
    #|
    #|interface foo {
    #|  add: func(a: u32, b: u32) -> u32;
    #|}
    #|
    #|world demo {
    #|  export foo;
    #|}
  let root = @wit.parse_package(src) catch {
    e => {
      fail(e.to_string())
      panic()
    }
  }
  let res = @wit.resolve_package(root, []) catch {
    e => {
      fail(e.to_string())
      panic()
    }
  }
  let bytes = @wit.encode_wit_component_wasm(res) catch {
    e => {
      fail(e.to_string())
      panic()
    }
  }
  match @component.sniff_binary_kind(bytes) {
    Some(@component.BinaryKind::Component) => ()
    _ => fail("expected component binary kind")
  }
  let c = @component.parse_component(bytes) catch {
    e => {
      fail(e.to_string())
      panic()
    }
  }
  if c.exports.length() != 2 {
    fail("expected 2 type exports")
  }
  let wat = @wit.format_wit_component_wat(res) catch {
    e => {
      fail(e.to_string())
      panic()
    }
  }
  if !wat.has_prefix("(component") {
    fail("expected component WAT output")
  }
}
