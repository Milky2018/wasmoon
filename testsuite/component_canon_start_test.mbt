///|
test "component: parse canon section (lower, no opts)" {
  let bytes : Array[Byte] = [
    // magic
    0x00, 0x61, 0x73, 0x6d,
    // version=u16(0x0d), layer=u16(0x01)
     0x0d, 0x00, 0x01, 0x00,
    // section 8 (canon), payload size=5
     0x08, 0x05,
    // vec length=1
     0x01,
    // lower: 0x01 0x00 f=0 opts=[]
     0x01, 0x00, 0x00, 0x00,
  ]
  let comp = @component.parse_component_binary(Bytes::from_array(bytes)) catch {
    e => return fail("parse component failed: \{e}")
  }
  let payload = match find_component_section_payload(comp, 8) {
    Some(p) => p
    None => return fail("missing canon section")
  }
  let canons = @component.parse_canon_section(payload) catch {
    e => return fail("parse canon section failed: \{e}")
  }
  inspect(canons.length(), content="1")
  inspect(canons[0], content="Lower(0, [])")
}

///|
test "component: parse start section (empty args, 0 results)" {
  let bytes : Array[Byte] = [
    0x00, 0x61, 0x73, 0x6d, 0x0d, 0x00, 0x01, 0x00,
    // section 9 (start), payload size=3
     0x09, 0x03,
    // f=0, arg*=[], r=0
     0x00, 0x00, 0x00,
  ]
  let comp = @component.parse_component_binary(Bytes::from_array(bytes)) catch {
    e => return fail("parse component failed: \{e}")
  }
  let payload = match find_component_section_payload(comp, 9) {
    Some(p) => p
    None => return fail("missing start section")
  }
  let start = @component.parse_start_section(payload) catch {
    e => return fail("parse start section failed: \{e}")
  }
  inspect(start, content="{func_idx: 0, args: [], results: 0}")
}

///|
test "component: parse_component collects canons + start" {
  let bytes : Array[Byte] = [
    0x00, 0x61, 0x73, 0x6d, 0x0d, 0x00, 0x01, 0x00, 0x08, 0x05, 0x01, 0x01, 0x00,
    0x00, 0x00, 0x09, 0x03, 0x00, 0x00, 0x00,
  ]
  let parsed = @component.parse_component(Bytes::from_array(bytes)) catch {
    e => return fail("parse failed: \{e}")
  }
  inspect(parsed.canons.length(), content="1")
  inspect(parsed.start, content="Some({func_idx: 0, args: [], results: 0})")
}
