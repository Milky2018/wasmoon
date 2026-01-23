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
fn push_leb_u32(buf : Array[Int], n : Int) -> Unit {
  // All tests here only need single-byte u32 LEBs.
  if n < 0 || n >= 0x80 {
    abort("test helper only supports small leb_u32")
  }
  buf.push(n)
}

///|
fn push_utf8(buf : Array[Int], s : String) -> Unit {
  for i in 0..<s.length() {
    buf.push(s.code_unit_at(i).to_int())
  }
}

///|
fn make_component_with_single_import(name : String) -> Bytes {
  // component import section (id 10):
  // vec length 1
  // importname (plain): tag=0x00, len, bytes
  // externdesc: value (0x02), type (0x01), primvaltype u32 (0x79)
  let payload : Array[Int] = []
  push_leb_u32(payload, 1)
  payload.push(0x00)
  push_leb_u32(payload, name.length())
  push_utf8(payload, name)
  payload.push(0x02)
  payload.push(0x01)
  payload.push(0x79)
  make_component_binary([[0x0A, payload.length(), ..payload]])
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

///|
test "component validator: package-style import names validate" {
  let bytes = make_component_with_single_import("wasi:http/types@2.0.0")
  let parsed = try? @component.parse_component(bytes)
  guard parsed is Ok(c) else {
    inspect(parsed, content="Ok(_)") // helpful diff if parse fails
    return
  }
  let validated = try? validate_component(c)
  inspect(validated is Ok(_), content="true")
}

///|
test "component validator: import names starting with digit are rejected" {
  let bytes = make_component_with_single_import("1")
  let parsed = try? @component.parse_component(bytes)
  guard parsed is Ok(c) else {
    inspect(parsed, content="Ok(_)") // helpful diff if parse fails
    return
  }
  let validated = try? validate_component(c)
  let ok = match validated {
    Err(MissingCanonOption(_)) => false
    Err(InvalidKebabName(_)) => true
    _ => false
  }
  inspect(ok, content="true")
}
