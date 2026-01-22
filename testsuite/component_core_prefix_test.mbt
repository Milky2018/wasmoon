///|
test "component: capture core-prefix section 1 (core module bytes)" {
  let bytes : Array[Byte] = [
    // component preamble
    0x00, 0x61, 0x73, 0x6d, 0x0d, 0x00, 0x01, 0x00,
    // section 1 (core module), size=8
     0x01, 0x08, 0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00,
  ]
  let comp = @component.parse_component(Bytes::from_array(bytes)) catch {
    e => return fail("parse failed: \{e}")
  }
  inspect(comp.core_modules.length(), content="1")
  inspect(comp.core_modules[0].length(), content="8")
  let m = comp.core_modules[0]
  inspect(m[0].to_int(), content="0")
  inspect(m[1].to_int(), content="97")
  inspect(m[2].to_int(), content="115")
  inspect(m[3].to_int(), content="109")
  inspect(m[4].to_int(), content="1")
}
