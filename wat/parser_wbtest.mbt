// Whitebox tests for WAT parser float parsing

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
test "parse_float32: positive nan" {
  let result = parse_float32("+nan") catch { _ => fail("unexpected error") }
  inspect(result.is_nan(), content="true")
}

///|
test "parse_float32: negative nan" {
  let result = parse_float32("-nan") catch { _ => fail("unexpected error") }
  inspect(result.is_nan(), content="true")
}

///|
test "parse_float32: nan with payload" {
  let result = parse_float32("nan:0x200000") catch {
    _ => fail("unexpected error")
  }
  inspect(result.is_nan(), content="true")
}

///|
test "parse_float32: negative nan with payload" {
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
test "parse_float32: negative hex float zero" {
  let result = parse_float32("-0x0p+0") catch { _ => fail("unexpected error") }
  // -0.0 == 0.0 in comparison, but it's negative zero
  inspect(result == (0.0 : Float), content="true")
}

///|
test "parse_float32: hex float 1.0" {
  let result = parse_float32("0x1p+0") catch { _ => fail("unexpected error") }
  inspect(result, content="1")
}

///|
test "parse_float32: hex float 8.0" {
  // 0x1.0 * 2^3 = 8.0
  let result = parse_float32("0x1p+3") catch { _ => fail("unexpected error") }
  inspect(result, content="8")
}

///|
test "parse_float32: hex float with fraction" {
  // 0x1.8 * 2^0 = 1.5
  let result = parse_float32("0x1.8p+0") catch { _ => fail("unexpected error") }
  inspect(result, content="1.5")
}

///|
test "parse_float32: negative hex float" {
  let result = parse_float32("-0x1.8p+0") catch {
    _ => fail("unexpected error")
  }
  inspect(result, content="-1.5")
}

///|
test "parse_float32: decimal float" {
  let result = parse_float32("3.14") catch { _ => fail("unexpected error") }
  // Float precision, check approximate
  inspect(result > (3.13 : Float) && result < (3.15 : Float), content="true")
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
test "parse_float64: nan" {
  let result = parse_float64("nan") catch { _ => fail("unexpected error") }
  inspect(result.is_nan(), content="true")
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

///|
test "parse_float64: negative hex float" {
  let result = parse_float64("-0x1p+10") catch { _ => fail("unexpected error") }
  inspect(result, content="-1024")
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
test "parse_hex_u32: with underscores" {
  let result = parse_hex_u32("FFFF_FFFF") catch {
    e => fail("Parse error: \{e}")
  }
  inspect(result, content="-1") // -1 when interpreted as signed
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
test "parse_u32: overflow raises error" {
  // Values exceeding u32 max should raise error
  let result = try? parse_u32("0xFFFF_FFFF_FFFF_FFFF")
  inspect(result is Err(_), content="true")
}

///|
test "parse_hex_u32: overflow raises error" {
  let result = try? parse_hex_u32("FFFF_FFFF_FFFF_FFFF")
  inspect(result is Err(_), content="true")
}

///|
test "parse_u32: max valid value" {
  let result = parse_u32("0xFFFF_FFFF") catch { e => fail("Parse error: \{e}") }
  inspect(result, content="-1") // 0xFFFFFFFF as signed int
}

///|
test "parse_u32: decimal overflow raises error" {
  // 4294967296 is u32::MAX + 1
  let result = try? parse_u32("4294967296")
  inspect(result is Err(_), content="true")
}

///|
test "parse WAT: multiple inline exports on func" {
  // Test: (module (func (export "a") (export "b") (export "c")))
  let wat = "(module (func (export \"a\") (export \"b\") (export \"c\")))"
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  inspect(mod.exports.length(), content="3")
  inspect(mod.exports[0].name, content="a")
  inspect(mod.exports[1].name, content="b")
  inspect(mod.exports[2].name, content="c")
}
