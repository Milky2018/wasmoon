// Whitebox tests for WAT lexer

///|
test "read_number: positive integers" {
  let lexer = Lexer::new("123 456")
  inspect(lexer.read_number(), content="123")
}

///|
test "read_number: negative integers" {
  let lexer = Lexer::new("-123 456")
  inspect(lexer.read_number(), content="-123")
}

///|
test "read_number: hex integers" {
  let lexer = Lexer::new("0xff abc")
  inspect(lexer.read_number(), content="0xff")
}

///|
test "read_number: negative hex integers" {
  let lexer = Lexer::new("-0xff abc")
  inspect(lexer.read_number(), content="-0xff")
}

///|
test "read_number: hex float" {
  let lexer = Lexer::new("0x1.5p+3 abc")
  inspect(lexer.read_number(), content="0x1.5p+3")
}

///|
test "read_number: negative hex float" {
  let lexer = Lexer::new("-0x1.921fb6p+2 abc")
  inspect(lexer.read_number(), content="-0x1.921fb6p+2")
}

///|
test "read_number: inf without sign" {
  // "inf" without sign starts with 'i', which is not a digit or sign
  // So read_number will return empty string (it expects to start with digit or sign)
  // Actually, this case won't happen in practice because next_token
  // only calls read_number when it sees a digit, '-', or '+'
  let lexer = Lexer::new("inf abc")
  // The 'i' is not consumed, read_number returns what it can parse
  inspect(lexer.read_number(), content="inf")
}

///|
test "read_number: positive inf" {
  let lexer = Lexer::new("+inf abc")
  inspect(lexer.read_number(), content="+inf")
}

///|
test "read_number: negative inf" {
  let lexer = Lexer::new("-inf abc")
  inspect(lexer.read_number(), content="-inf")
}

///|
test "read_number: nan" {
  let lexer = Lexer::new("+nan abc")
  inspect(lexer.read_number(), content="+nan")
}

///|
test "read_number: negative nan" {
  let lexer = Lexer::new("-nan abc")
  inspect(lexer.read_number(), content="-nan")
}

///|
test "read_number: nan with payload" {
  let lexer = Lexer::new("-nan:0x200000 abc")
  inspect(lexer.read_number(), content="-nan:0x200000")
}

///|
test "read_number: positive nan with payload" {
  let lexer = Lexer::new("+nan:0x7fc00000 abc")
  inspect(lexer.read_number(), content="+nan:0x7fc00000")
}

///|
test "read_number: decimal float" {
  let lexer = Lexer::new("3.14159 abc")
  inspect(lexer.read_number(), content="3.14159")
}

///|
test "read_number: negative decimal float" {
  let lexer = Lexer::new("-2.71828 abc")
  inspect(lexer.read_number(), content="-2.71828")
}

///|
test "read_number: scientific notation" {
  let lexer = Lexer::new("1.5e+10 abc")
  inspect(lexer.read_number(), content="1.5e+10")
}

///|
test "read_number: negative zero hex float" {
  let lexer = Lexer::new("-0x0p+0 abc")
  inspect(lexer.read_number(), content="-0x0p+0")
}
