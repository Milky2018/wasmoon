// Tests for WAST parser

// ============================================================
// Lexer tests for read_number
// ============================================================

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
test "read_number: positive nan" {
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
test "read_number: negative zero hex float" {
  let lexer = Lexer::new("-0x0p+0 abc")
  inspect(lexer.read_number(), content="-0x0p+0")
}

// ============================================================
// Float parsing tests
// ============================================================

///|
test "parse_float32: positive infinity" {
  let result = parse_float32("inf") catch { _ => fail("unexpected error") }
  inspect(result.is_pos_inf(), content="true")
}

///|
test "parse_float32: negative infinity" {
  let result = parse_float32("-inf") catch { _ => fail("unexpected error") }
  inspect(result.is_neg_inf(), content="true")
}

///|
test "parse_float32: nan" {
  let result = parse_float32("nan") catch { _ => fail("unexpected error") }
  inspect(result.is_nan(), content="true")
}

///|
test "parse_float32: negative nan" {
  let result = parse_float32("-nan") catch { _ => fail("unexpected error") }
  inspect(result.is_nan(), content="true")
}

///|
test "parse_float32: nan with payload" {
  let result = parse_float32("-nan:0x200000") catch {
    _ => fail("unexpected error")
  }
  inspect(result.is_nan(), content="true")
}

///|
test "parse_float32: hex float zero" {
  let result = parse_float32("0x0p+0") catch { _ => fail("unexpected error") }
  inspect(result, content="0")
}

///|
test "parse_float32: hex float 1.0" {
  let result = parse_float32("0x1p+0") catch { _ => fail("unexpected error") }
  inspect(result, content="1")
}

///|
test "parse_float32: hex float with fraction" {
  // 0x1.8 * 2^0 = 1.5
  let result = parse_float32("0x1.8p+0") catch { _ => fail("unexpected error") }
  inspect(result, content="1.5")
}

///|
test "parse_float64: positive infinity" {
  let result = parse_float64("inf") catch { _ => fail("unexpected error") }
  inspect(result.is_pos_inf(), content="true")
}

///|
test "parse_float64: negative infinity" {
  let result = parse_float64("-inf") catch { _ => fail("unexpected error") }
  inspect(result.is_neg_inf(), content="true")
}

///|
test "parse_float64: nan with payload" {
  let result = parse_float64("-nan:0x8000000000000") catch {
    _ => fail("unexpected error")
  }
  inspect(result.is_nan(), content="true")
}

///|
test "parse_float64: hex float" {
  let result = parse_float64("0x1.921fb54442d18p+1") catch {
    _ => fail("unexpected error")
  }
  // This is approximately pi
  inspect(result > 3.14 && result < 3.15, content="true")
}

// ============================================================
// WAST command parsing tests
// ============================================================

///|
test "parse simple module" {
  let input =
    #|(module
    #|  (func (export "add") (param i32 i32) (result i32)
    #|    local.get 0
    #|    local.get 1
    #|    i32.add)
    #|)
  let script = parse(input) catch { e => fail("Parse error: \{e}") }
  inspect(script.commands.length(), content="1")
  guard script.commands[0] is Module(_, _) else {
    fail("Expected Module command")
  }
}

///|
test "parse assert_return" {
  let input =
    #|(module
    #|  (func (export "add") (param i32 i32) (result i32)
    #|    local.get 0
    #|    local.get 1
    #|    i32.add)
    #|)
    #|(assert_return (invoke "add" (i32.const 1) (i32.const 2)) (i32.const 3))
  let script = parse(input) catch { e => fail("Parse error: \{e}") }
  inspect(script.commands.length(), content="2")
  if script.commands[1] is AssertReturn(Invoke(_, "add", args), expected) {
    inspect(args.length(), content="2")
    inspect(expected.length(), content="1")
  } else {
    fail("Expected AssertReturn command")
  }
}

///|
test "parse assert_trap" {
  let input =
    #|(module
    #|  (func (export "div") (param i32 i32) (result i32)
    #|    local.get 0
    #|    local.get 1
    #|    i32.div_s)
    #|)
    #|(assert_trap (invoke "div" (i32.const 1) (i32.const 0)) "integer divide by zero")
  let script = parse(input) catch { e => fail("Parse error: \{e}") }
  inspect(script.commands.length(), content="2")
  if script.commands[1] is AssertTrap(Invoke(_, "div", _), msg) {
    inspect(msg, content="integer divide by zero")
  } else {
    fail("Expected AssertTrap command")
  }
}

///|
test "parse register command" {
  let input =
    #|(module)
    #|(register "M1")
  let script = parse(input) catch { e => fail("Parse error: \{e}") }
  inspect(script.commands.length(), content="2")
  guard script.commands[1] is Register("M1", None) else {
    fail("Expected Register command")
  }
}

///|
test "parse i32 const values" {
  let input =
    #|(module
    #|  (func (export "f") (result i32) i32.const 42)
    #|)
    #|(assert_return (invoke "f") (i32.const 42))
  let script = parse(input) catch { e => fail("Parse error: \{e}") }
  if script.commands[1] is AssertReturn(_, expected) {
    if expected[0] is I32(n) {
      inspect(n, content="42")
    } else {
      fail("Expected I32 value")
    }
  } else {
    fail("Expected AssertReturn")
  }
}

///|
test "parse hex numbers" {
  let input =
    #|(module
    #|  (func (export "f") (result i32) i32.const 0)
    #|)
    #|(assert_return (invoke "f") (i32.const 0xff))
  let script = parse(input) catch { e => fail("Parse error: \{e}") }
  if script.commands[1] is AssertReturn(_, expected) {
    if expected[0] is I32(n) {
      inspect(n, content="255")
    } else {
      fail("Expected I32 value")
    }
  } else {
    fail("Expected AssertReturn")
  }
}
