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
