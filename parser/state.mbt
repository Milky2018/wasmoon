// ============================================================
// Parser State
// ============================================================

///|
struct Parser {
  data : Bytes
  mut pos : Int
  mut has_data_count : Bool // true if data count section was seen
  types : Array[@types.SubType]
} derive(Show)

///|
/// Create a new parser from bytes
pub fn Parser::new(data : Bytes) -> Parser {
  { data, pos: 0, has_data_count: false, types: [] }
}

///|
/// Check if at end of input
fn Parser::is_eof(self : Parser) -> Bool {
  self.pos >= self.data.length()
}

///|
/// Peek at the next byte without consuming
fn Parser::peek_byte(self : Parser) -> Int raise ParserError {
  if self.is_eof() {
    raise UnexpectedEndOfInput
  }
  self.data[self.pos].to_int()
}

///|
/// Consume and return the next byte
fn Parser::read_byte(self : Parser) -> Int raise ParserError {
  if self.is_eof() {
    raise UnexpectedEndOfInput
  }
  let byte = self.data[self.pos].to_int()
  self.pos += 1
  byte
}

///|
/// Skip n bytes
fn Parser::skip(self : Parser, n : Int) -> Unit raise ParserError {
  if self.pos + n > self.data.length() {
    raise UnexpectedEndOfInput
  }
  self.pos += n
}

///|
/// Read n bytes
fn Parser::read_bytes(self : Parser, n : Int) -> Bytes raise ParserError {
  if self.pos + n > self.data.length() {
    raise UnexpectedEndOfInput
  }
  let bytes = loop ([], 0) {
    (acc, i) =>
      if i >= n {
        acc
      } else {
        acc.push(self.data[self.pos + i])
        continue (acc, i + 1)
      }
  }
  self.pos += n
  Bytes::from_array(bytes)
}
