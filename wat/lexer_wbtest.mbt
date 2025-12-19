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

///|
test "read_number: nan without sign" {
  let lexer = Lexer::new("nan abc")
  inspect(lexer.read_number(), content="nan")
}

///|
test "read_number: nan with payload and underscores" {
  let lexer = Lexer::new("nan:0x7f_ffff abc")
  // Underscores are skipped in the payload
  inspect(lexer.read_number(), content="nan:0x7fffff")
}

///|
test "next_token: nan without sign is Number" {
  let lexer = Lexer::new("nan")
  let tok = lexer.next_token() catch { _ => fail("unexpected error") }
  inspect(tok.token, content="Number(\"nan\")")
}

///|
test "next_token: nan:payload without sign is Number" {
  let lexer = Lexer::new("nan:0x1")
  let tok = lexer.next_token() catch { _ => fail("unexpected error") }
  inspect(tok.token, content="Number(\"nan:0x1\")")
}

///|
test "next_token: inf without sign is Number" {
  let lexer = Lexer::new("inf")
  let tok = lexer.next_token() catch { _ => fail("unexpected error") }
  inspect(tok.token, content="Number(\"inf\")")
}

// ============================================================
// LocatedToken source position tests
// ============================================================

///|
test "LocatedToken: lparen position tracking" {
  let lexer = Lexer::new("(module)")
  let tok = lexer.next_token() catch { _ => fail("unexpected error") }
  inspect(tok.token, content="LParen")
  inspect(tok.span.start_line, content="1")
  inspect(tok.span.start_column, content="1")
  inspect(tok.span.end_line, content="1")
  inspect(tok.span.end_column, content="2")
  inspect(tok.raw, content="(")
}

///|
test "LocatedToken: keyword position tracking" {
  let lexer = Lexer::new("(module)")
  (lexer.next_token() catch { _ => fail("unexpected error") }) |> ignore
  let tok = lexer.next_token() catch { _ => fail("unexpected error") }
  inspect(tok.token, content="Keyword(\"module\")")
  inspect(tok.span.start_line, content="1")
  inspect(tok.span.start_column, content="2")
  inspect(tok.span.end_line, content="1")
  inspect(tok.span.end_column, content="8")
  inspect(tok.raw, content="module")
}

///|
test "LocatedToken: multiline position tracking" {
  let lexer = Lexer::new("(\n  module\n)")
  let lparen = lexer.next_token() catch { _ => fail("unexpected error") }
  inspect(lparen.span.start_line, content="1")
  inspect(lparen.span.start_column, content="1")
  let module_ = lexer.next_token() catch { _ => fail("unexpected error") }
  inspect(module_.span.start_line, content="2")
  inspect(module_.span.start_column, content="3")
  inspect(module_.span.end_line, content="2")
  inspect(module_.span.end_column, content="9")
  let rparen = lexer.next_token() catch { _ => fail("unexpected error") }
  inspect(rparen.span.start_line, content="3")
  inspect(rparen.span.start_column, content="1")
}

///|
test "LocatedToken: id position tracking" {
  let lexer = Lexer::new("$myname")
  let tok = lexer.next_token() catch { _ => fail("unexpected error") }
  inspect(tok.token, content="Id(\"myname\")")
  inspect(tok.span.start_column, content="1")
  inspect(tok.span.end_column, content="8")
  inspect(tok.raw, content="$myname")
}

///|
test "LocatedToken: string position tracking" {
  let lexer = Lexer::new("\"hello\"")
  let tok = lexer.next_token() catch { _ => fail("unexpected error") }
  inspect(tok.token, content="String_(\"hello\")")
  inspect(tok.span.start_column, content="1")
  inspect(tok.span.end_column, content="8")
  inspect(tok.raw, content="\"hello\"")
}

///|
test "LocatedToken: number position tracking" {
  let lexer = Lexer::new("12345")
  let tok = lexer.next_token() catch { _ => fail("unexpected error") }
  inspect(tok.token, content="Number(\"12345\")")
  inspect(tok.span.start_column, content="1")
  inspect(tok.span.end_column, content="6")
  inspect(tok.raw, content="12345")
}

///|
test "LocatedToken: to_loc conversion" {
  let lexer = Lexer::new("  keyword")
  let tok = lexer.next_token() catch { _ => fail("unexpected error") }
  let loc = tok.to_loc()
  inspect(loc.line, content="1")
  inspect(loc.column, content="3")
}

// ============================================================
// Annotation skipping tests
// ============================================================

///|
test "annotation: simple annotation skipped" {
  let lexer = Lexer::new("(@id) module")
  let tok = lexer.next_token() catch { _ => fail("unexpected error") }
  // The annotation should be skipped, next token is "module"
  inspect(tok.token, content="Keyword(\"module\")")
}

///|
test "annotation: annotation with content skipped" {
  let lexer = Lexer::new("(@custom \"some content\") func")
  let tok = lexer.next_token() catch { _ => fail("unexpected error") }
  inspect(tok.token, content="Keyword(\"func\")")
}

///|
test "annotation: nested annotations skipped" {
  let lexer = Lexer::new("(@outer (@inner)) keyword")
  let tok = lexer.next_token() catch { _ => fail("unexpected error") }
  inspect(tok.token, content="Keyword(\"keyword\")")
}

///|
test "annotation: multiple annotations skipped" {
  let lexer = Lexer::new("(@a) (@b) (@c) global")
  let tok = lexer.next_token() catch { _ => fail("unexpected error") }
  inspect(tok.token, content="Keyword(\"global\")")
}

///|
test "annotation: annotation after lparen" {
  let lexer = Lexer::new("((@a) module)")
  let lparen = lexer.next_token() catch { _ => fail("unexpected error") }
  inspect(lparen.token, content="LParen")
  let module_ = lexer.next_token() catch { _ => fail("unexpected error") }
  inspect(module_.token, content="Keyword(\"module\")")
}

///|
test "annotation: position after annotation" {
  let lexer = Lexer::new("(@a) module")
  let tok = lexer.next_token() catch { _ => fail("unexpected error") }
  // After skipping annotation, position should be correct
  inspect(tok.span.start_column, content="6") // "module" starts at column 6
}

///|
test "annotation: annotation with string id" {
  let lexer = Lexer::new("(@\"custom-id\") func")
  let tok = lexer.next_token() catch { _ => fail("unexpected error") }
  inspect(tok.token, content="Keyword(\"func\")")
}

///|
test "annotation: annotation spanning multiple lines" {
  let lexer = Lexer::new("(@a\n  content\n) module")
  let tok = lexer.next_token() catch { _ => fail("unexpected error") }
  inspect(tok.token, content="Keyword(\"module\")")
  inspect(tok.span.start_line, content="3")
}
