///|
fn build_component_with_core_module(core_bytes : Array[Byte]) -> Bytes {
  let header : Array[Byte] = [
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x01, 0x00, 0x01, 0x27,
  ]
  let bytes : Array[Byte] = []
  for b in header {
    bytes.push(b)
  }
  for b in core_bytes {
    bytes.push(b)
  }
  Bytes::from_array(bytes)
}

///|
test "component runtime: instantiate core module section" {
  let core_bytes : Array[Byte] = [
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, 0x01, 0x05, 0x01, 0x60, 0x00,
    0x01, 0x7f, 0x03, 0x02, 0x01, 0x00, 0x07, 0x0a, 0x01, 0x06, 0x61, 0x6e, 0x73,
    0x77, 0x65, 0x72, 0x00, 0x00, 0x0a, 0x06, 0x01, 0x04, 0x00, 0x41, 0x2a, 0x0b,
  ]
  let component_bytes = build_component_with_core_module(core_bytes)
  let component = @component.parse_component(component_bytes)
  let linker = @component.ComponentLinker::new()
  let instance = linker.instantiate("demo", component)
  let core_instance = match instance.get_core_module(0) {
    Some(inst) => inst
    None => return fail("missing core module")
  }
  let results = @executor.call_exported_func(
    linker.get_store(),
    core_instance,
    "answer",
    [],
  )
  inspect(results, content="[I32(42)]")
}

///|
test "component runtime: reject component imports" {
  let bytes = Bytes::from_array([
    0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x01, 0x00, 0x0a, 0x05, 0x01, 0x00, 0x00,
    0x01, 0x00,
  ])
  let component = @component.parse_component(bytes)
  let linker = @component.ComponentLinker::new()
  inspect(
    try? linker.instantiate("bad", component),
    content=(
      #|Err(UnsupportedComponent("imports"))
    ),
  )
}
