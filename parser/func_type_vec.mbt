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
  loop ([], 0) {
    (acc, i) =>
      if i >= count {
        acc
      } else {
        acc.push(reader())
        continue (acc, i + 1)
      }
  }
}
