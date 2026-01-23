///|
fn parse_component(
  bytes : Array[Byte],
) -> Result[@component.ComponentBinary, String] {
  let parsed = @component.parse_component_binary(Bytes::from_array(bytes)) catch {
    e => return Err(e.to_string())
  }
  Ok(parsed)
}

///|
test "component: parse_component_binary parses header and section framing" {
  let bytes : Array[Byte] = [0x00, 0x61, 0x73, 0x6d, 0x0d, 0x00, 0x01, 0x00]
  let parsed = match parse_component(bytes) {
    Ok(v) => v
    Err(e) => return fail("parse failed: \{e}")
  }
  inspect(parsed.version, content="13")
  inspect(parsed.layer, content="1")
  inspect(parsed.sections.length(), content="0")
}

///|
test "component: parse_component_binary rejects core wasm modules" {
  let core : Array[Byte] = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]
  match parse_component(core) {
    Ok(_v) => return fail("expected an error, got Ok")
    Err(e) => inspect(e, content="input is not a component binary")
  }
}
