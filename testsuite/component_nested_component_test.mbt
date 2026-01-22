///|
test "component: parse nested component section (4)" {
  // outer: section 4 payload is the inner component bytes
  let outer : Array[Byte] = [
    0x00, 0x61, 0x73, 0x6d, 0x0d, 0x00, 0x01, 0x00,
    // section 4, size=8, payload=inner
     0x04, 0x08, 0x00, 0x61, 0x73, 0x6d, 0x0d, 0x00, 0x01, 0x00,
  ]
  let parsed = @component.parse_component(Bytes::from_array(outer)) catch {
    e => return fail("parse failed: \{e}")
  }
  inspect(parsed.components.length(), content="1")
  inspect(parsed.components[0].binary.version, content="13")
  inspect(parsed.components[0].binary.layer, content="1")
}
