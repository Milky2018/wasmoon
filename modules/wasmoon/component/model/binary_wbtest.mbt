///|
fn parse_type_index_for_test(bytes : Array[Byte]) -> String {
  Reader::Reader(Bytes::from_array(bytes)).read_typeidx().to_string() catch {
    error => error.to_string()
  }
}

///|
test "component type indices use bounded unsigned LEB128" {
  debug_inspect(
    [
      parse_type_index_for_test([0x3F]),
      parse_type_index_for_test([0x40]),
      parse_type_index_for_test([0x7F]),
      parse_type_index_for_test([0x80, 0x01]),
      parse_type_index_for_test([0x80]),
      parse_type_index_for_test([0xFF, 0xFF, 0xFF, 0xFF, 0x1F]),
    ],
    content=(
      #|[
      #|  "63",
      #|  "64",
      #|  "127",
      #|  "128",
      #|  "unexpected end of input",
      #|  "leb128 value too large",
      #|]
    ),
  )
}
