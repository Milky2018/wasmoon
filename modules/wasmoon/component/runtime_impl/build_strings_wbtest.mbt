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
