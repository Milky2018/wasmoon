// ============================================================
// Parser Tests
// ============================================================

///|
test "LEB128 u32 decoding - single byte" {
  let parser = Parser::new(b"\x7F") // 127
  inspect(parser.read_leb128_u32(), content="127")
}

///|
test "LEB128 u32 decoding - multi byte" {
  let parser = Parser::new(b"\xE5\x8E\x26") // 624485
  inspect(parser.read_leb128_u32(), content="624485")
}

///|
test "LEB128 i32 decoding - negative" {
  let parser = Parser::new(b"\x7E") // -2
  inspect(parser.read_leb128_i32(), content="-2")
}

///|
test "LEB128 i64 decoding" {
  let parser = Parser::new(b"\x80\x80\x80\x80\x80\x01") // 2^32
  inspect(parser.read_leb128_i64(), content="34359738368")
}

///|
test "LEB128 u32 - too long (6 bytes)" {
  // 6 bytes encoding value 3: \x83\x80\x80\x80\x80\x00
  let parser = Parser::new(b"\x83\x80\x80\x80\x80\x00")
  inspect(
    try? parser.read_leb128_u32(),
    content="Err(LEB128 encoded integer is too large)",
  )
}

///|
test "LEB128 u32 - 5th byte with unused bits set" {
  // Value 3 with 5th byte having bit 4 set: \x83\x80\x80\x80\x10
  let parser = Parser::new(b"\x83\x80\x80\x80\x10")
  inspect(
    try? parser.read_leb128_u32(),
    content="Err(LEB128 encoded integer is too large)",
  )
}

///|
test "LEB128 u32 - valid 5 byte encoding" {
  // Maximum u32 (0xFFFFFFFF): \xFF\xFF\xFF\xFF\x0F
  let parser = Parser::new(b"\xFF\xFF\xFF\xFF\x0F")
  inspect(parser.read_leb128_u32(), content="-1") // -1 as signed = 0xFFFFFFFF
}

///|
test "LEB128 i32 - unused bits not sign-extended (positive)" {
  // i32.const 0 with 5th byte = 0x70 (bits 4-6 should be 0 for positive)
  let parser = Parser::new(b"\x80\x80\x80\x80\x70")
  inspect(
    try? parser.read_leb128_i32(),
    content="Err(LEB128 encoded integer is too large)",
  )
}

///|
test "LEB128 i32 - unused bits not sign-extended (negative)" {
  // i32.const -1 with 5th byte = 0x0F (bits 4-6 should be 1 for negative)
  let parser = Parser::new(b"\xFF\xFF\xFF\xFF\x0F")
  inspect(
    try? parser.read_leb128_i32(),
    content="Err(LEB128 encoded integer is too large)",
  )
}

///|
test "LEB128 i32 - valid positive 5 byte" {
  // Maximum positive i32 (0x7FFFFFFF): bits 4-6 = 0 in 5th byte
  let parser = Parser::new(b"\xFF\xFF\xFF\xFF\x07")
  inspect(parser.read_leb128_i32(), content="2147483647")
}

///|
test "LEB128 i32 - valid negative 5 byte" {
  // -1 with proper sign extension: bits 4-6 = 1 in 5th byte
  let parser = Parser::new(b"\xFF\xFF\xFF\xFF\x7F")
  inspect(parser.read_leb128_i32(), content="-1")
}

///|
test "LEB128 i64 - unused bits not sign-extended" {
  // i64.const 0 with 10th byte = 0x7E (bits 1-6 should be 0 for positive)
  let parser = Parser::new(b"\x80\x80\x80\x80\x80\x80\x80\x80\x80\x7E")
  inspect(
    try? parser.read_leb128_i64(),
    content="Err(LEB128 encoded integer is too large)",
  )
}

///|
test "LEB128 i64 - valid maximum positive" {
  // Maximum positive i64: 0x7FFFFFFFFFFFFFFF
  let parser = Parser::new(b"\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\xFF\x00")
  inspect(parser.read_leb128_i64(), content="9223372036854775807")
}

///|
test "value type parsing" {
  let parser = Parser::new(b"\x7F\x7E\x7D\x7C")
  inspect(parser.read_value_type(), content="I32")
  inspect(parser.read_value_type(), content="I64")
  inspect(parser.read_value_type(), content="F32")
  inspect(parser.read_value_type(), content="F64")
}

///|
test "peek_byte does not consume" {
  let parser = Parser::new(b"\x42")
  let first = parser.peek_byte()
  let second = parser.peek_byte()
  let consumed = parser.read_byte()
  inspect((first, second, consumed), content="(66, 66, 66)")
}

///|
test "f32 parsing - 1.0" {
  // IEEE 754: 1.0f = 0x3F800000, little-endian: 00 00 80 3F
  let parser = Parser::new(b"\x00\x00\x80\x3F")
  inspect(parser.read_f32(), content="1")
}

///|
test "f64 parsing - 1.0" {
  // IEEE 754: 1.0 = 0x3FF0000000000000, little-endian: 00 00 00 00 00 00 F0 3F
  let parser = Parser::new(b"\x00\x00\x00\x00\x00\x00\xF0\x3F")
  inspect(parser.read_f64(), content="1")
}

// ============================================================
// Custom Section Validation Tests (custom.wast regression)
// ============================================================

///|
test "custom section - empty section should fail" {
  // custom.wast line 76: \00asm \01\00\00\00 \00\00
  // section_id=0, section_size=0, but custom section must have a name
  let bytes = b"\x00asm\x01\x00\x00\x00\x00\x00"
  inspect(try? parse_module(bytes), content="Err(unexpected end)")
}

///|
test "custom section - length out of bounds" {
  // custom.wast line 84: section claims 0x26=38 bytes but only 36 available
  // \00asm \01\00\00\00 \00\26\10 "a custom section" "this is the payload"
  let bytes = b"\x00asm\x01\x00\x00\x00\x00\x26\x10a custom sectionthis is the payload"
  inspect(try? parse_module(bytes), content="Err(length out of bounds)")
}

///|
test "custom section - concatenated modules" {
  // custom.wast line 114: two wasm modules concatenated
  // \00asm\01\00\00\00 \00asm\01\00\00\00
  let bytes = b"\x00asm\x01\x00\x00\x00\x00asm\x01\x00\x00\x00"
  inspect(try? parse_module(bytes), content="Err(length out of bounds)")
}
