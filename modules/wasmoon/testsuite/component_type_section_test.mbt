///|

///|
test "component: parse type section (functype, empty params/results)" {
  let bytes : Array[Byte] = [
    // magic
    0x00, 0x61, 0x73, 0x6d,
    // version=u16(0x0d), layer=u16(0x01)
     0x0d, 0x00, 0x01, 0x00,
    // section 7 (type), payload size=5
     0x07, 0x05,
    // vec length=1
     0x01,
    // functype (sync) with empty params and empty results
     0x40, 0x00, 0x01, 0x00,
  ]
  let comp = @component.parse_component_binary(Bytes::from_array(bytes)) catch {
    e => return fail("parse component failed: \{e}")
  }
  let payload = match find_component_section_payload(comp, 7) {
    Some(p) => p
    None => return fail("missing type section")
  }
  let defs = @component.parse_type_section(payload) catch {
    e => return fail("parse type section failed: \{e}")
  }
  inspect(defs.length(), content="1")
  inspect(
    defs[0],
    content="FuncType({is_async: false, params: [], result: None})",
  )
}
