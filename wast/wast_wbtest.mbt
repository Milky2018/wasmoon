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
test "parse_float32: nan with max payload preserves bits" {
  // -nan:0x7fffff should have all mantissa bits set (except quiet bit)
  // Expected bit pattern: 0xff800000 | 0x7fffff = 0xffffffff = -1 as i32
  let result = parse_float32("-nan:0x7fffff") catch {
    _ => fail("unexpected error")
  }
  inspect(result.reinterpret_as_int(), content="-1")
}

///|
test "parse_float32: positive nan with payload preserves bits" {
  // nan:0x200000 should produce 0x7f800000 | 0x200000 = 0x7fa00000 = 2141192192
  let result = parse_float32("nan:0x200000") catch {
    _ => fail("unexpected error")
  }
  inspect(result.reinterpret_as_int(), content="2141192192")
}

///|
test "parse_float32: negative nan with payload preserves bits" {
  // -nan:0x200000 should produce 0xff800000 | 0x200000 = 0xffa00000 = -6291456
  let result = parse_float32("-nan:0x200000") catch {
    _ => fail("unexpected error")
  }
  inspect(result.reinterpret_as_int(), content="-6291456")
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
test "parse_float64: nan with max payload preserves bits" {
  // -nan:0xfffffffffffff should have all mantissa bits set
  // Expected: 0xfff0000000000000 | 0xfffffffffffff = 0xffffffffffffffff = -1 as i64
  let result = parse_float64("-nan:0xfffffffffffff") catch {
    _ => fail("unexpected error")
  }
  inspect(result.reinterpret_as_int64(), content="-1")
}

///|
test "parse_float64: positive nan with payload preserves bits" {
  // nan:0x4000000000000 should produce 0x7ff0000000000000 | 0x4000000000000 = 9219994337134247936
  let result = parse_float64("nan:0x4000000000000") catch {
    _ => fail("unexpected error")
  }
  inspect(result.reinterpret_as_int64(), content="9219994337134247936")
}

///|
test "parse_float64: negative nan with payload preserves bits" {
  // -nan:0x4000000000000 should produce 0xfff0000000000000 | 0x4000000000000 = -3377699720527872
  let result = parse_float64("-nan:0x4000000000000") catch {
    _ => fail("unexpected error")
  }
  inspect(result.reinterpret_as_int64(), content="-3377699720527872")
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
  guard script.commands[0].0 is Module(_, _) else {
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
  if script.commands[1].0 is AssertReturn(Invoke(_, "add", args), expected) {
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
  if script.commands[1].0 is AssertTrap(Invoke(_, "div", _), msg) {
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
  guard script.commands[1].0 is Register("M1", None) else {
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
  if script.commands[1].0 is AssertReturn(_, expected) {
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
  if script.commands[1].0 is AssertReturn(_, expected) {
    if expected[0] is I32(n) {
      inspect(n, content="255")
    } else {
      fail("Expected I32 value")
    }
  } else {
    fail("Expected AssertReturn")
  }
}

// ============================================================
// Integer parsing tests for unsigned values
// ============================================================

///|
test "parse_int: unsigned i32 max (4294967295)" {
  // 4294967295 is u32::MAX, which should be interpreted as -1 in i32
  let result = parse_int("4294967295") catch { e => fail("Parse error: \{e}") }
  inspect(result, content="-1")
}

///|
test "parse_int: unsigned i32 boundary" {
  // 2147483648 is INT_MAX + 1, should be interpreted as INT_MIN
  let result = parse_int("2147483648") catch { e => fail("Parse error: \{e}") }
  inspect(result, content="-2147483648")
}

///|
test "parse_int64: unsigned i64 max (18446744073709551615)" {
  // 18446744073709551615 is u64::MAX, which should be interpreted as -1 in i64
  let result = parse_int64("18446744073709551615") catch {
    e => fail("Parse error: \{e}")
  }
  inspect(result, content="-1")
}

///|
test "parse_int64: unsigned i64 boundary" {
  // 9223372036854775808 is INT64_MAX + 1, should be INT64_MIN
  let result = parse_int64("9223372036854775808") catch {
    e => fail("Parse error: \{e}")
  }
  inspect(result, content="-9223372036854775808")
}

///|
test "parse_hex_int: with underscores" {
  let result = parse_hex_int("FFFF_FFFF") catch {
    e => fail("Parse error: \{e}")
  }
  inspect(result, content="-1")
}

///|
test "parse_hex_int64: with underscores" {
  let result = parse_hex_int64("FFFF_FFFF_FFFF_FFFF") catch {
    e => fail("Parse error: \{e}")
  }
  inspect(result, content="-1")
}

///|
test "parse_hex_int: simple hex" {
  let result = parse_hex_int("FF") catch { e => fail("Parse error: \{e}") }
  inspect(result, content="255")
}

///|
test "parse_hex_int64: simple hex" {
  let result = parse_hex_int64("1_0000_0000") catch {
    e => fail("Parse error: \{e}")
  }
  inspect(result, content="4294967296")
}

///|
test "collect_module_text reconstruction" {
  let wast_text =
    #|(module
    #|  (func $dummy)
    #|  (func $func (param i32 i32) (result i32) (local.get 0))
    #|  (type $check (func (param i32 i32) (result i32)))
    #|  (table funcref (elem $func))
    #|  (func (export "test") (result i32)
    #|    (call_indirect (type $check)
    #|      (i32.const 1) (i32.const 2) (i32.const 0)
    #|    )
    #|  )
    #|)
    #|(assert_return (invoke "test") (i32.const 1))
  let script = parse(wast_text)
  match script.commands[0].0 {
    Module(mod_, _) => {
      inspect(mod_.types.length(), content="4")
      inspect(mod_.funcs.length(), content="3")
      inspect(mod_.elems.length(), content="1")
      // Check elem init is correct (should be 1, func index of $func)
      inspect(mod_.elems[0].init[0], content="[RefFunc(1)]")
      // Check call_indirect type index (should be 2, index of $check)
      let test_func = mod_.codes[mod_.codes.length() - 1]
      inspect(
        test_func.body,
        content="[I32Const(1), I32Const(2), I32Const(0), CallIndirect(2, 0)]",
      )
    }
    _ => fail("expected module")
  }
}
