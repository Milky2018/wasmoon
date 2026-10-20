///|
test "standalone WAT string decoding preserves bytes and Unicode escapes" {
  for spelling in ["\"é\"", "\"\\c3\\a9\"", "\"\\u{e9}\""] {
    assert_eq(@wat.parse_string_literal(spelling), b"\xc3\xa9")
  }
  assert_eq(@wat.parse_string_literal("\"💩\\ff\""), b"\xf0\x9f\x92\xa9\xff")
  assert_eq(
    @wat.parse_string_literal("\"\\n\\t\\r\\\\\\\"\\'\""),
    b"\n\t\r\\\"'",
  )
  for
    spelling in [
      "", "word", "\"a\" \"b\"", "\"\\q\"", "\"\\u{d800}\"", "\"unterminated",
    ] {
    try @wat.parse_string_literal(spelling) catch {
      _ => ()
    } noraise {
      _ => fail("malformed string literal was accepted")
    }
  }
}
