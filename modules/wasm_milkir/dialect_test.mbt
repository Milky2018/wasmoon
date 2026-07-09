///|
test "Wasm extension descriptors validate immediate layout" {
  let desc = descriptor(MemoryGrow(0, Some(10)))
  inspect(desc.dialect, content="wasm")
  inspect(desc.opcode, content="memory_grow")
  inspect(desc.expected_immediate_count(), content="1..2")
  inspect(encode(MemoryGrow(0, None)).matches_descriptor(desc), content="true")
  inspect(
    encode(MemoryGrow(0, Some(10))).matches_descriptor(desc),
    content="true",
  )
}

///|
test "Wasm extension decode reports malformed immediates" {
  let ext = @milkir.ExtOp(
    "wasm",
    "memory_size",
    FixedArray::makei(0, fn(_) { 0 }),
  )
  debug_inspect(
    decode_error(ext),
    content=(
      #|Some("malformed Wasm MilkIR extension 'memory_size': expected 1 immediates, got 0")
    ),
  )
}

///|
test "Wasm extension decode reports unknown opcodes" {
  let ext = @milkir.ExtOp(
    "wasm",
    "memroy_size",
    FixedArray::makei(1, fn(_) { 0 }),
  )
  debug_inspect(
    decode_error(ext),
    content=(
      #|Some("unknown Wasm MilkIR extension opcode 'memroy_size'")
    ),
  )
}

///|
test "Wasm extension decode validates bool immediates" {
  let ext = @milkir.ExtOp(
    "wasm",
    "ref_test",
    FixedArray::makei(2, fn(i) { if i == 0 { 3 } else { 2 } }),
  )
  debug_inspect(
    decode_error(ext),
    content=(
      #|Some("malformed Wasm MilkIR extension 'ref_test': immediate 1 is a bool flag encoded as 0 or 1, got 2")
    ),
  )
}
