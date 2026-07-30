///|
fn utf8_decode_error(bytes : Array[Byte]) -> ComponentRuntimeError? {
  try decode_utf8_runtime(Bytes::from_array(bytes)) catch {
    error => Some(error)
  } noraise {
    _ => None
  }
}

///|
test "canonical UTF-8 decoding distinguishes malformed and incomplete input" {
  debug_inspect(
    [
      utf8_decode_error([b'\xFF']),
      utf8_decode_error([b'\xC3']),
      utf8_decode_error([b'\xC3', b'\xB6']),
    ],
    content=(
      #|[
      #|  Some(CanonCallError("invalid utf-8")),
      #|  Some(CanonCallError("incomplete utf-8 byte sequence")),
      #|  None,
      #|]
    ),
  )
}

///|
test "latin1+utf16 tags only UTF-16 payloads" {
  let latin1 = encode_string_for_canon("é", Latin1Utf16)
  let utf16 = encode_string_for_canon("水", Latin1Utf16)
  debug_inspect(
    (latin1, utf16),
    content=(
      #|((<Bytes: [0xe9]>, 1, 2), (<Bytes: [0x34, 0x6c]>, -2147483647, 2))
    ),
  )
}
