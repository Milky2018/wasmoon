///|
test "component: parse_component collects types/imports/exports" {
  let bytes : Array[Byte] = [
    0x00, 0x61, 0x73, 0x6d,
    // version=u16(0x0d), layer=u16(0x01)
     0x0d, 0x00, 0x01, 0x00,
    // section 7 (type), payload size=5
     0x07, 0x05, 0x01, 0x40, 0x00, 0x01, 0x00,
    // section 10 (import), payload size=5
     0x0a, 0x05, 0x01, 0x00, 0x00, 0x01, 0x00,
    // section 11 (export), payload size=6
     0x0b, 0x06, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00,
  ]
  let comp = @component.parse_component(Bytes::from_array(bytes)) catch {
    e => return fail("parse failed: \{e}")
  }
  inspect(comp.binary.version, content="13")
  inspect(comp.binary.layer, content="1")
  inspect(comp.types.length(), content="1")
  inspect(comp.imports.length(), content="1")
  inspect(comp.exports.length(), content="1")
}
