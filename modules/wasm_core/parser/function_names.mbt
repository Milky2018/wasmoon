///|
// Decode optional debug metadata inside bounded sub-readers. Resource admission
// shares the enclosing parser budget; malformed metadata is ignored by its caller.
fn Parser::read_function_names(
  self : Parser,
  payload : Bytes,
) -> Map[Int32, String] raise ParserError {
  let reader = { ..self, data: payload, pos: 0, }
  let names : Map[Int32, String] = Map([])
  while !reader.is_eof() {
    let id = reader.read_byte()
    let size = reader.read_u32()
    let bytes = reader.read_bytes(size)
    if id == 1 {
      let subsection = { ..reader, data: bytes, pos: 0, }
      let count = subsection.read_u32()
      for _ in 0..<count {
        let index = subsection.read_u32()
        let name = subsection.read_string()
        names.set(index, name)
      }
      guard subsection.is_eof() else { raise SectionSizeMismatch }
    }
  }
  names
}
