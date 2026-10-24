// ============================================================
// Parser State
// ============================================================

///|
struct Parser {
  data : Bytes
  mut pos : Int32
  mut instruction_sources : Array[@types.InstructionSource]?
  mut has_data_count : Bool // true if data count section was seen
  types : Array[@types.SubType]
  max_depth : Int32
  remaining_work : Ref[Int64]
  admit_work : ((Int64) -> Bool)?
}

///|
pub impl Debug for Parser with fn to_repr(self) {
  Repr::record({
    "position": Repr(self.pos),
    "input_bytes": Repr(self.data.length()),
  })
}

///|
/// Create a new parser from bytes
pub fn Parser::Parser(data : Bytes) -> Parser {
  {
    data,
    pos: 0,
    instruction_sources: None,
    has_data_count: false,
    types: [],
    max_depth: 0x7FFF_FFFF,
    remaining_work: Ref(0x7FFF_FFFF_FFFF_FFFFL),
    admit_work: None,
  }
}

///|
/// Work includes bytes visited (including type pre-scans) and expanded vector
/// entries. Admission runs before expansion; nesting counts expression frames.
pub(all) struct ParseLimits {
  max_input_bytes : Int64
  max_work : Int64
  max_depth : Int32
} derive(Debug)

///|
pub extend ParseLimits with Debug::{to_repr}

///|
fn Parser::charge(self : Parser, amount : Int64) -> Unit raise ParserError {
  guard amount >= 0L && amount <= self.remaining_work.val else {
    raise WorkLimitExceeded
  }
  if self.admit_work is Some(admit) && !admit(amount) {
    raise WorkLimitExceeded
  }
  self.remaining_work.val -= amount
}

///|
/// Check if at end of input
fn Parser::is_eof(self : Parser) -> Bool {
  self.pos >= self.data.length()
}

///|
/// Peek at the next byte without consuming
fn Parser::peek_byte(self : Parser) -> Int32 raise ParserError {
  if self.is_eof() {
    raise UnexpectedEndOfInput
  }
  self.data[self.pos].to_int()
}

///|
/// Consume and return the next byte
fn Parser::read_byte(self : Parser) -> Int32 raise ParserError {
  if self.is_eof() {
    raise UnexpectedEndOfInput
  }
  let byte = self.data[self.pos].to_int()
  self.charge(1L)
  self.pos += 1
  byte
}

///|
/// Skip n bytes
fn Parser::skip(self : Parser, n : Int32) -> Unit raise ParserError {
  if n < 0 || n > self.data.length() - self.pos {
    raise UnexpectedEndOfInput
  }
  self.charge(n.to_int64())
  self.pos += n
}

///|
/// Read n bytes
fn Parser::read_bytes(self : Parser, n : Int32) -> Bytes raise ParserError {
  if n < 0 || n > self.data.length() - self.pos {
    raise UnexpectedEndOfInput
  }
  self.charge(n.to_int64())
  let bytes : Array[Byte] = []
  for i in 0..<n {
    bytes.push(self.data[self.pos + i])
  }
  self.pos += n
  Bytes::from_array(bytes)
}
