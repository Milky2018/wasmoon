///|
test "component: parse instance + alias sections (minimal instantiate + outer alias)" {
  let bytes : Array[Byte] = [
    // magic
    0x00, 0x61, 0x73, 0x6d,
    // version=u16(0x0d), layer=u16(0x01)
     0x0d, 0x00, 0x01, 0x00,
    // section 5 (instance), payload size=4
     0x05, 0x04,
    // vec length=1
     0x01,
    // instanceexpr: instantiate componentidx=0, args=[]
     0x00, 0x00, 0x00,
    // section 6 (alias), payload size=5
     0x06, 0x05,
    // vec length=1
     0x01,
    // sort=func
     0x01,
    // aliastarget=outer ct=0 idx=0
     0x02, 0x00, 0x00,
  ]
  let comp = @component.parse_component_binary(Bytes::from_array(bytes)) catch {
    e => return fail("parse component failed: \{e}")
  }
  let inst_payload = match find_component_section_payload(comp, 5) {
    Some(p) => p
    None => return fail("missing instance section")
  }
  let alias_payload = match find_component_section_payload(comp, 6) {
    Some(p) => p
    None => return fail("missing alias section")
  }
  let instances = @component.parse_instance_section(inst_payload) catch {
    e => return fail("parse instance section failed: \{e}")
  }
  let aliases = @component.parse_alias_section(alias_payload) catch {
    e => return fail("parse alias section failed: \{e}")
  }
  inspect(instances.length(), content="1")
  inspect(instances[0].expr, content="Instantiate(0, [])")
  inspect(aliases.length(), content="1")
  inspect(aliases[0], content="{sort: Func, target: Outer(0, 0)}")
}

///|
test "component: parse_component collects instances + aliases" {
  let bytes : Array[Byte] = [
    0x00, 0x61, 0x73, 0x6d, 0x0d, 0x00, 0x01, 0x00, 0x05, 0x04, 0x01, 0x00, 0x00,
    0x00, 0x06, 0x05, 0x01, 0x01, 0x02, 0x00, 0x00,
  ]
  let parsed = @component.parse_component(Bytes::from_array(bytes)) catch {
    e => return fail("parse failed: \{e}")
  }
  inspect(parsed.instances.length(), content="1")
  inspect(parsed.aliases.length(), content="1")
}
