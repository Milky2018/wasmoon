///|
/// Regression tests for component-model canonical option validation.

///|
fn bytes_of(ints : Array[Int]) -> Bytes {
  Bytes::from_array(ints.map(fn(x) { x.to_byte() }))
}

///|
fn make_component_binary(sections : Array[Array[Int]]) -> Bytes {
  let ints : Array[Int] = [
    0x00, 0x61, 0x73, 0x6D, // \0asm
     0x01, 0x00, // version u16 (0x0001)
     0x01, 0x00,
  ] // layer u16 (0x0001 = component)
  for s in sections {
    for b in s {
      ints.push(b)
    }
  }
  bytes_of(ints)
}

///|
test "component validator: canon lift string result doesn't require realloc" {
  // Component with:
  // - type[0] = (func (result string))
  // - canon[0] = lift core func 0 with only (memory 0)
  let type_payload = [0x01, 0x40, 0x00, 0x00, 0x73]
  let canon_payload = [0x01, 0x00, 0x00, 0x00, 0x01, 0x03, 0x00, 0x00]
  let component_bin = make_component_binary([
    [0x07, type_payload.length(), ..type_payload],
    [0x08, canon_payload.length(), ..canon_payload],
  ])
  let parsed = try? @component.parse_component(component_bin)
  guard parsed is Ok(c) else {
    inspect(parsed, content="Ok(_)") // helpful diff if parse fails
    return
  }
  let validated = try? validate_component(c)
  inspect(validated is Ok(_), content="true")
}

///|
test "component validator: canon lift string param requires realloc" {
  // Component with:
  // - type[0] = (func (param string))
  // - canon[0] = lift core func 0 with only (memory 0)
  let type_payload = [0x01, 0x40, 0x01, 0x00, 0x73, 0x01, 0x00]
  let canon_payload = [0x01, 0x00, 0x00, 0x00, 0x01, 0x03, 0x00, 0x00]
  let component_bin = make_component_binary([
    [0x07, type_payload.length(), ..type_payload],
    [0x08, canon_payload.length(), ..canon_payload],
  ])
  let parsed = try? @component.parse_component(component_bin)
  guard parsed is Ok(c) else {
    inspect(parsed, content="Ok(_)") // helpful diff if parse fails
    return
  }
  let validated = try? validate_component(c)
  let ok = match validated {
    Err(MissingCanonOption(opt)) => opt == "realloc"
    _ => false
  }
  inspect(ok, content="true")
}
