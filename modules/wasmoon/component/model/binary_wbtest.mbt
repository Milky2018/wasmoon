///|
fn parse_type_index_for_test(bytes : Array[Byte]) -> String {
  Reader::Reader(Bytes::from_array(bytes)).read_typeidx().to_string() catch {
    error => error.to_string()
  }
}

///|
fn parse_component_for_test(bytes : Bytes) -> String {
  try {
    let component = parse_component_binary(bytes)
    "version=\{component.version} layer=\{component.layer} sections=\{component.sections.length()}"
  } catch {
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

///|
test "component binary preamble requires version 0x0d and layer 1" {
  let official = Bytes::from_array([
    0x00, 0x61, 0x73, 0x6D, 0x0D, 0x00, 0x01, 0x00,
  ])
  let obsolete = Bytes::from_array([
    0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x01, 0x00,
  ])
  debug_inspect(
    (
      sniff_binary_kind(official),
      parse_component_for_test(official),
      sniff_binary_kind(obsolete),
      parse_component_for_test(obsolete),
    ),
    content=(
      #|(
      #|  Some(Component),
      #|  "version=13 layer=1 sections=0",
      #|  Some(UnknownPreamble(1, 1)),
      #|  "unsupported component preamble: version=1 layer=1",
      #|)
    ),
  )
}
