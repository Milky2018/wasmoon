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
  let acc : Array[T] = []
  for _ in 0..<count {
    acc.push(reader())
  }
  acc
}
