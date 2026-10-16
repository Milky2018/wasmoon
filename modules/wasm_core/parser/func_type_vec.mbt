// ============================================================
// Function Type Parsing
// ============================================================

///|
/// Read a vector of items using a reader function
fn[T] Parser::read_vec(
  self : Parser,
  reader : () -> T raise ParserError,
) -> Array[T] raise ParserError {
  let count = self.read_u32()
  self.charge(count.reinterpret_as_uint().to_int64())
  let acc : Array[T] = []
  for _ in 0..<count {
    acc.push(reader())
  }
  acc
}
