///|
test "memarg decoding preserves alignment exponents for validation" {
  for exponent in [31, 32, 33, 63] {
    let parser = Parser::Parser(
      Bytes::from_array([exponent.to_byte(), b'\x00']),
    )
    assert_eq(parser.read_memarg(), (0, exponent, 0L))
  }
  // Noncanonical but bounded unsigned LEB encodings are permitted.
  let extended = Parser::Parser(b"\x82\x00\x00")
  debug_inspect(extended.read_memarg(), content="(0, 2, 0)")
  let indexed = Parser::Parser(b"\x7f\x01\x00")
  debug_inspect(indexed.read_memarg(), content="(1, 63, 0)")
  let reserved = Parser::Parser(b"\x80\x01\x00")
  try reserved.read_memarg() catch {
    MalformedMemopFlags => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("reserved memarg flag bit was accepted")
  }
}
