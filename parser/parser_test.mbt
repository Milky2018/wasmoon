// Binary Parser Tests for Memory64 and Table64

// Helper to construct WASM binary from bytes
///|
fn make_wasm_module(sections : Array[FixedArray[Int]]) -> Bytes {
  let bytes : Array[Int] = []
  // Magic number and version
  bytes.push(0x00)
  bytes.push(0x61)
  bytes.push(0x73)
  bytes.push(0x6D) // \0asm
  bytes.push(0x01)
  bytes.push(0x00)
  bytes.push(0x00)
  bytes.push(0x00) // version 1
  for section in sections {
    for b in section {
      bytes.push(b)
    }
  }
  Bytes::from_array(bytes.map(fn(x) { x.to_byte() }))
}

// Helper to parse and get module

///|
fn parse_wasm(sections : Array[FixedArray[Int]]) -> @types.Module? {
  let data = make_wasm_module(sections)
  let result = try? @parser.parse_module(data)
  match result {
    Ok(m) => Some(m)
    Err(_) => None
  }
}

// ============================================================
// Memory64 Binary Parser Tests
// ============================================================

///|
test "binary parse memory32 - flag 0x00" {
  let mem_section : FixedArray[Int] = [0x05, 0x03, 0x01, 0x00, 0x01]
  guard parse_wasm([mem_section]) is Some(m) else { return }
  inspect(m.memories.length(), content="1")
  inspect(m.memories[0].limits.min, content="1")
  inspect(m.memories[0].limits.max, content="None")
  inspect(m.memories[0].is_memory64, content="false")
}

///|
test "binary parse memory32 - flag 0x01" {
  let mem_section : FixedArray[Int] = [0x05, 0x04, 0x01, 0x01, 0x01, 0x04]
  guard parse_wasm([mem_section]) is Some(m) else { return }
  inspect(m.memories[0].limits.min, content="1")
  inspect(m.memories[0].limits.max, content="Some(4)")
  inspect(m.memories[0].is_memory64, content="false")
}

///|
test "binary parse memory64 - flag 0x04" {
  let mem_section : FixedArray[Int] = [0x05, 0x03, 0x01, 0x04, 0x02]
  guard parse_wasm([mem_section]) is Some(m) else { return }
  inspect(m.memories.length(), content="1")
  inspect(m.memories[0].limits.min, content="2")
  inspect(m.memories[0].limits.max, content="None")
  inspect(m.memories[0].is_memory64, content="true")
}

///|
test "binary parse memory64 - flag 0x05" {
  let mem_section : FixedArray[Int] = [0x05, 0x04, 0x01, 0x05, 0x01, 0x0A]
  guard parse_wasm([mem_section]) is Some(m) else { return }
  inspect(m.memories[0].limits.min, content="1")
  inspect(m.memories[0].limits.max, content="Some(10)")
  inspect(m.memories[0].is_memory64, content="true")
}

// ============================================================
// Table64 Binary Parser Tests
// ============================================================

///|
test "binary parse table32 - flag 0x00" {
  let table_section : FixedArray[Int] = [0x04, 0x04, 0x01, 0x70, 0x00, 0x01]
  guard parse_wasm([table_section]) is Some(m) else { return }
  inspect(m.tables.length(), content="1")
  inspect(m.tables[0].type_.limits.min, content="1")
  inspect(m.tables[0].type_.limits.max, content="None")
  inspect(m.tables[0].type_.is_table64, content="false")
}

///|
test "binary parse table32 - flag 0x01" {
  let table_section : FixedArray[Int] = [
    0x04, 0x05, 0x01, 0x70, 0x01, 0x01, 0x0A,
  ]
  guard parse_wasm([table_section]) is Some(m) else { return }
  inspect(m.tables[0].type_.limits.min, content="1")
  inspect(m.tables[0].type_.limits.max, content="Some(10)")
  inspect(m.tables[0].type_.is_table64, content="false")
}

///|
test "binary parse table64 - flag 0x04" {
  let table_section : FixedArray[Int] = [0x04, 0x04, 0x01, 0x70, 0x04, 0x02]
  guard parse_wasm([table_section]) is Some(m) else { return }
  inspect(m.tables.length(), content="1")
  inspect(m.tables[0].type_.limits.min, content="2")
  inspect(m.tables[0].type_.limits.max, content="None")
  inspect(m.tables[0].type_.is_table64, content="true")
}

///|
test "binary parse table64 - flag 0x05" {
  let table_section : FixedArray[Int] = [
    0x04, 0x05, 0x01, 0x70, 0x05, 0x01, 0x0A,
  ]
  guard parse_wasm([table_section]) is Some(m) else { return }
  inspect(m.tables[0].type_.limits.min, content="1")
  inspect(m.tables[0].type_.limits.max, content="Some(10)")
  inspect(m.tables[0].type_.is_table64, content="true")
}

// ============================================================
// Error Tests for Invalid Flags
// ============================================================

///|
test "binary parse memory - invalid flag 0x08 rejected" {
  let mem_section : FixedArray[Int] = [0x05, 0x03, 0x01, 0x08, 0x01]
  inspect(parse_wasm([mem_section]) is None, content="true")
}

///|
test "binary parse table - invalid flag 0x08 rejected" {
  let table_section : FixedArray[Int] = [0x04, 0x04, 0x01, 0x70, 0x08, 0x01]
  inspect(parse_wasm([table_section]) is None, content="true")
}

///|
test "binary parse table - shared flag 0x03 rejected for tables" {
  let table_section : FixedArray[Int] = [
    0x04, 0x05, 0x01, 0x70, 0x03, 0x01, 0x04,
  ]
  inspect(parse_wasm([table_section]) is None, content="true")
}

// ============================================================
// Multi-memory and Multi-table Tests
// ============================================================

///|
test "binary parse multi-memory with mixed 32/64" {
  let mem_section : FixedArray[Int] = [0x05, 0x05, 0x02, 0x00, 0x01, 0x04, 0x02]
  guard parse_wasm([mem_section]) is Some(m) else { return }
  inspect(m.memories.length(), content="2")
  inspect(m.memories[0].is_memory64, content="false")
  inspect(m.memories[0].limits.min, content="1")
  inspect(m.memories[1].is_memory64, content="true")
  inspect(m.memories[1].limits.min, content="2")
}

///|
test "binary parse multi-table with mixed 32/64" {
  let table_section : FixedArray[Int] = [
    0x04, 0x08, 0x02, 0x70, 0x00, 0x01, 0x70, 0x04, 0x02,
  ]
  guard parse_wasm([table_section]) is Some(m) else { return }
  inspect(m.tables.length(), content="2")
  inspect(m.tables[0].type_.is_table64, content="false")
  inspect(m.tables[0].type_.limits.min, content="1")
  inspect(m.tables[1].type_.is_table64, content="true")
  inspect(m.tables[1].type_.limits.min, content="2")
}
