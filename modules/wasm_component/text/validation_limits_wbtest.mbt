///|
test "component validation accepts nesting limit and rejects its successor" {
  for depth in [100, 101] {
    // Encode signed type references directly: the text encoder's unsigned
    // encoding above index 63 is tracked separately in ISS-621.
    let payload = ByteBuf::ByteBuf()
    payload.push_uleb_u32(depth)
    for index in 0..<depth {
      payload.push_u8(0x70) // list
      if index == 0 {
        payload.push_u8(0x79) // u32
      } else {
        payload.push_sleb_i32(index - 1)
      }
    }
    let section = payload.to_bytes()
    let binary = ByteBuf::ByteBuf()
    for byte in [0x00, 0x61, 0x73, 0x6d, 0x0d, 0x00, 0x01, 0x00, 0x07] {
      binary.push_u8(byte)
    }
    binary.push_uleb_u32(section.length())
    for byte in section {
      binary.push_u8(byte.to_int())
    }
    let component = @component.parse_component(binary.to_bytes())
    try @component_model.validate_component(component) catch {
      SectionParseError(7, _) => inspect(depth, content="101")
      error => fail("unexpected validation error: \{error}")
    } noraise {
      _ => inspect(depth, content="100")
    }
  }
}

///|
test "component validation accepts effective size limit and rejects its successor" {
  // The first tuple has effective size 100. Referencing it 999 times plus
  // 99 primitive fields makes the second tuple size 100000 including itself.
  let base_fields = Array::make(99, "u32").join(" ")
  let references = Array::make(999, "0").join(" ")
  for primitive_count in [99, 100] {
    let fields = Array::make(primitive_count, "u32").join(" ")
    let component = @component.parse_component(
      parse_component_wat(
        "(component (type (tuple \{base_fields})) (type (tuple \{references} \{fields})))",
      ),
    )
    try @component_model.validate_component(component) catch {
      SectionParseError(7, _) => inspect(primitive_count, content="100")
      error => fail("unexpected validation error: \{error}")
    } noraise {
      _ => inspect(primitive_count, content="99")
    }
  }
}
