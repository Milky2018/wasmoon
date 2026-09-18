///|
fn append_control_test_u32(bytes : Array[Byte], value : Int) -> Unit {
  let mut remaining = value
  while remaining >= 128 {
    bytes.push(((remaining & 127) | 128).to_byte())
    remaining = remaining >> 7
  }
  bytes.push(remaining.to_byte())
}

///|
test "binary parser: deeply nested blocks use bounded host stack" {
  let depth = 2048
  let body : Array[Byte] = [0] // No locals.
  for _ in 0..<depth {
    body.push(0x02)
    body.push(0x40)
  }
  body.push(0x01) // nop
  for _ in 0..<=depth {
    body.push(0x0b)
  }
  let section : Array[Byte] = [1]
  append_control_test_u32(section, body.length())
  section.append(body)
  let bytes : Array[Byte] = [
    0, 0x61, 0x73, 0x6d, 1, 0, 0, 0, 1, 4, 1, 0x60, 0, 0, 3, 2, 1, 0, 10,
  ]
  append_control_test_u32(bytes, section.length())
  bytes.append(section)
  let module_ = @parser.parse_module(Bytes::from_array(bytes))
  let mut instructions = module_.codes[0].body
  for _ in 0..<depth {
    guard instructions[:] is [Block(Empty, inner)] else {
      fail("missing nested block")
    }
    instructions = inner
  }
  inspect(@debug.to_string(instructions), content="[Nop]")
}
