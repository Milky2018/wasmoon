///|
test "core type reader rejects negative spans without moving its cursor" {
  let reader = Reader(b"abc")
  reader.read_u8() |> ignore
  for count in [-1, -2147483648, 2147483647, 3] {
    try reader.read_bytes(count) catch {
      ComponentParseError(message) =>
        inspect(message, content="unexpected end of input")
      error => fail(error.to_string())
    } noraise {
      _ => fail("out-of-bounds span accepted")
    }
    inspect(reader.pos, content="1")
  }
  inspect(reader.read_bytes(2), content="b\"bc\"")
}
