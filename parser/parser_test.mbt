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

///|
test "binary parse gc: ref.i31 opcode" {
  // (func (export "run") (result i32)
  //   i32.const 0
  //   ref.i31
  //   drop
  //   i32.const 7
  // )
  let type_section : FixedArray[Int] = [
    0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7f,
  ]
  let func_section : FixedArray[Int] = [0x03, 0x02, 0x01, 0x00]
  let export_section : FixedArray[Int] = [
    0x07, 0x07, 0x01, 0x03, 0x72, 0x75, 0x6e, 0x00, 0x00,
  ]
  let code_section : FixedArray[Int] = [
    0x0a, 0x0b, 0x01, 0x09, 0x00, 0x41, 0x00, 0xfb, 0x1c, 0x1a, 0x41, 0x07, 0x0b,
  ]
  guard parse_wasm([type_section, func_section, export_section, code_section])
    is Some(m) else {
    return
  }
  let body = m.codes[0].body
  let ok = match body {
    [I32Const(0), RefI31, Drop, I32Const(7)] => true
    _ => false
  }
  inspect(ok, content="true")
}

///|
test "binary parse gc: i31.get_u opcode" {
  // (func (export "run") (result i32)
  //   i32.const 5
  //   ref.i31
  //   i31.get_u
  // )
  let type_section : FixedArray[Int] = [
    0x01, 0x05, 0x01, 0x60, 0x00, 0x01, 0x7f,
  ]
  let func_section : FixedArray[Int] = [0x03, 0x02, 0x01, 0x00]
  let export_section : FixedArray[Int] = [
    0x07, 0x07, 0x01, 0x03, 0x72, 0x75, 0x6e, 0x00, 0x00,
  ]
  let code_section : FixedArray[Int] = [
    0x0a, 0x0a, 0x01, 0x08, 0x00, 0x41, 0x05, 0xfb, 0x1c, 0xfb, 0x1e, 0x0b,
  ]
  guard parse_wasm([type_section, func_section, export_section, code_section])
    is Some(m) else {
    return
  }
  let body = m.codes[0].body
  let ok = match body {
    [I32Const(5), RefI31, I31GetU] => true
    _ => false
  }
  inspect(ok, content="true")
}

///|
test "binary parse gc: rec group allows forward type refs" {
  // (module
  //   (rec
  //     (type (func (param (ref 1)) (result i32)))
  //     (type (struct (field (mut (ref null 0)))))
  //   )
  // )
  let type_section : FixedArray[Int] = [
    0x01, 0x0e, 0x01, 0x4e, 0x02, 0x60, 0x01, 0x64, 0x01, 0x01, 0x7f, 0x5f, 0x01,
    0x63, 0x00, 0x01,
  ]
  let m_opt = parse_wasm([type_section])
  inspect(m_opt is Some(_), content="true")
  guard m_opt is Some(m) else { return }
  let ok0 = match m.types[0].composite {
    Func(ft) =>
      ft.params == [@types.ValueType::RefStruct(1)] && ft.results == [I32]
    _ => false
  }
  inspect(ok0, content="true")
  let ok1 = match m.types[1].composite {
    Struct(st) =>
      st.fields.length() == 1 &&
      st.fields[0].storage_type ==
      @types.StorageType::Val(@types.ValueType::RefNullFuncTyped(0)) &&
      st.fields[0].mutable == true
    _ => false
  }
  inspect(ok1, content="true")
}
