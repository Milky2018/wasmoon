///|
fn Parser::read_leb128_u32(self : Parser) -> Int32 raise ParserError {
  @binary.read_u32(self, Parser::read_byte, () => LEB128TooLarge)
}

///|
fn Parser::read_leb128_i32(self : Parser) -> Int32 raise ParserError {
  @binary.read_s32(self, Parser::read_byte, () => LEB128TooLarge)
}

///|
fn Parser::read_leb128_i64(self : Parser) -> Int64 raise ParserError {
  @binary.read_s64(self, Parser::read_byte, () => LEB128TooLarge)
}

///|
fn Parser::read_leb128_u64(self : Parser) -> Int64 raise ParserError {
  @binary.read_u64(self, Parser::read_byte, () => LEB128TooLarge)
}
