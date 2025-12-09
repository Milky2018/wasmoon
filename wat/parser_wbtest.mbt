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
test "parse_u32: hex overflow 0x1_0000_0000 raises error" {
  // 0x1_0000_0000 = 4294967296, exceeds u32 max
  let result = try? parse_u32("0x1_0000_0000")
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

///|
test "parse WAT: forward reference global export" {
  // Export references a global defined later
  let wat = "(module (export \"a\" (global $g)) (global $g i32 (i32.const 0)))"
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  inspect(mod.exports.length(), content="1")
  inspect(mod.exports[0].name, content="a")
  inspect(mod.exports[0].desc is @types.ExportDesc::Global(_), content="true")
}

///|
test "parse WAT: forward reference global inline export" {
  // Inline export with global name before definition
  let wat = "(module (global $a (export \"a\") i32 (i32.const 0)))"
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  inspect(mod.exports.length(), content="1")
  inspect(mod.exports[0].name, content="a")
  inspect(mod.globals.length(), content="1")
}

///|
test "parse WAT: forward reference func" {
  // Export references a function defined later
  let wat = "(module (export \"f\" (func $f)) (func $f))"
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  inspect(mod.exports.length(), content="1")
  inspect(mod.exports[0].name, content="f")
  inspect(mod.exports[0].desc is @types.ExportDesc::Func(_), content="true")
}

///|
test "parse WAT: forward reference memory" {
  // Export references a memory defined later
  let wat = "(module (export \"m\" (memory $m)) (memory $m 1))"
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  inspect(mod.exports.length(), content="1")
  inspect(mod.exports[0].name, content="m")
  inspect(mod.exports[0].desc is @types.ExportDesc::Memory(_), content="true")
}

///|
test "parse WAT: forward reference table" {
  // Export references a table defined later
  let wat = "(module (export \"t\" (table $t)) (table $t 1 funcref))"
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  inspect(mod.exports.length(), content="1")
  inspect(mod.exports[0].name, content="t")
  inspect(mod.exports[0].desc is @types.ExportDesc::Table(_), content="true")
}

// ============================================================
// Regression tests for float_literals.wast failures
// ============================================================

///|
test "debug: MoonBit 0.0 bit pattern" {
  // Verify MoonBit's 0.0 and -0.0 bit patterns
  let pos_zero : Double = 0.0
  let neg_zero : Double = -0.0
  inspect(pos_zero.reinterpret_as_int64(), content="0")
  inspect(neg_zero.reinterpret_as_int64(), content="-9223372036854775808")
}

///|
// NOTE: This test documents a MoonBit compiler bug where
// `if neg { -0.0 } else { 0.0 }` returns -0.0 even when neg=false.
// Keep this test to track when the bug is fixed.
test "moonbit-bug: conditional 0.0 vs -0.0 returns wrong value" {
  let neg = false
  let result = if neg { -0.0 } else { 0.0 }
  let bits = result.reinterpret_as_int64()
  // BUG: Should be 0, but MoonBit returns -9223372036854775808 (negative zero)
  inspect(bits, content="-9223372036854775808")
}

///|
test "regression: f64.zero - hex float 0x0.0p0 should be positive zero" {
  // f64.zero: 0x0.0p0 should return bit pattern 0x0000000000000000 (positive zero)
  // NOT 0x8000000000000000 (negative zero)
  let result = parse_float64("0x0.0p0") catch { e => fail("Parse error: \{e}") }
  let bits = result.reinterpret_as_int64()
  inspect(bits, content="0") // Should be 0, not -9223372036854775808
}

///|
test "regression: f64.positive_zero - hex float +0x0.0p0 with explicit plus" {
  // +0x0.0p0 should also be positive zero
  let result = parse_float64("+0x0.0p0") catch {
    e => fail("Parse error: \{e}")
  }
  let bits = result.reinterpret_as_int64()
  inspect(bits, content="0") // Should be 0, not -9223372036854775808
}

///|
test "regression: f32.large_int - 80-bit hex integer" {
  // 0x1_0000_0000_0000_0000_0000 is 2^80
  // As f32, this should be 0x67800000 (1736441856)
  let result = parse_float32("0x1_0000_0000_0000_0000_0000") catch {
    e => fail("Parse error: \{e}")
  }
  let bits = result.reinterpret_as_int()
  inspect(bits, content="1736441856") // 0x67800000
}

///|
test "regression: f32_dec.min_positive - smallest positive f32" {
  // 1.4013e-45 is the smallest positive subnormal f32
  // Should have bit pattern 0x00000001 (1)
  // f32 subnormal: value = mantissa * 2^(-149) where mantissa is in [0, 2^23-1]
  // For bit pattern 1: value = 1 * 2^(-149) ≈ 1.4012984643e-45
  let result = parse_float32("1.4013e-45") catch {
    e => fail("Parse error: \{e}")
  }
  let bits = result.reinterpret_as_int()
  inspect(bits, content="1") // Should be 1, not 0
}

///|
test "debug: f32 subnormal boundary values" {
  // 2^(-149) ≈ 1.4012984643e-45 is the smallest positive f32
  // 1.4e-45 is slightly less than 2^(-149), but close enough to round to 1
  let r1 = parse_float32("1.4e-45") catch { e => fail("Parse error: \{e}") }
  inspect(r1.reinterpret_as_int(), content="1")

  // 1.5e-45 should definitely round to 1
  let r2 = parse_float32("1.5e-45") catch { e => fail("Parse error: \{e}") }
  inspect(r2.reinterpret_as_int(), content="1")
}

///|
test "debug: strconv parse_double for subnormal" {
  // What does MoonBit's strconv return for 1.4013e-45?
  let d = @strconv.parse_double("1.4013e-45") catch { _ => fail("parse error") }
  // Convert double to float (may lose precision)
  let f = Float::from_double(d)
  inspect(f.reinterpret_as_int(), content="1")
}

///|
test "debug: strconv for max subnormal" {
  let d = @strconv.parse_double("1.1754942e-38") catch {
    _ => fail("parse error")
  }
  let f = Float::from_double(d)
  inspect(f.reinterpret_as_int(), content="8388607")
}

///|
test "regression: f32_dec.max_subnormal - largest subnormal f32" {
  // 1.1754942e-38 is close to the largest subnormal f32
  // max_subnormal = 8388607 * 2^(-149) ≈ 1.1754942106924411e-38
  // 8388606 * 2^(-149) ≈ 1.1754940705955805e-38
  // midpoint ≈ 1.1754941406440108e-38
  // 1.1754942e-38 > midpoint, so should round up to 8388607
  let result = parse_float32("1.1754942e-38") catch {
    e => fail("Parse error: \{e}")
  }
  let bits = result.reinterpret_as_int()
  inspect(bits, content="8388607") // 0x007fffff
}

///|
test "debug: max subnormal with more precision" {
  // Use exact value that should definitely be 8388607
  let r1 = parse_float32("1.17549421e-38") catch {
    e => fail("Parse error: \{e}")
  }
  inspect(r1.reinterpret_as_int(), content="8388607")

  // Use exact value for 8388606
  let r2 = parse_float32("1.17549407e-38") catch {
    e => fail("Parse error: \{e}")
  }
  inspect(r2.reinterpret_as_int(), content="8388606")
}

// ============================================================
// Regression tests for func.wast and func_ptrs.wast bugs
// ============================================================

///|
test "regression: local index with explicit type reference" {
  // When a function uses (type $sig) instead of inline params,
  // local $var should be indexed correctly (param_count + local_index)
  // Previously: used inline_params.length() which was 0 when type was used
  let wat =
    #|(module
    #|  (type $sig (func (param i32) (result i32)))
    #|  (func (type $sig) (local $var i32)
    #|    local.get $var  ;; should get local at index 1 (param 0, local 1)
    #|  )
    #|)
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  // Function should have type index 0
  inspect(mod.funcs[0], content="0")
  // Body should have LocalGet(1) - the local $var
  let code = mod.codes[0]
  inspect(code.locals.length(), content="1")
  inspect(code.body[0], content="LocalGet(1)")
}

///|
test "regression: explicit type definitions parsed before functions" {
  // Type $t is defined AFTER functions $f, $g, $h that use matching signatures.
  // Previously: parser created implicit types during function parsing,
  // so the type indices didn't match correctly.
  // Now: explicit type definitions are parsed first.
  let wat =
    #|(module
    #|  (func $f (result f64) (f64.const 0))  ;; adds implicit type ()
    #|  (func $g (param i32))                 ;; reuses explicit type $t
    #|  (func $h (result f64) (f64.const 1))  ;; reuses implicit type from $f
    #|  (type $t (func (param i32)))
    #|)
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  // Should have 2 types: (param i32) and (result f64)
  inspect(mod.types.length(), content="2")
  // $t should be type 0: (func (param i32))
  inspect(mod.types[0].params.length(), content="1")
  inspect(mod.types[0].results.length(), content="0")
  // Implicit type should be type 1: (func (result f64))
  inspect(mod.types[1].params.length(), content="0")
  inspect(mod.types[1].results.length(), content="1")
  // $g should use type 0 (same as explicit $t)
  inspect(mod.funcs[1], content="0")
}

///|
test "regression: ref type local parsing" {
  // (ref $t) should be parsed as RefFuncTyped (non-nullable typed function reference)
  let wat =
    #|(module
    #|  (type $t (func))
    #|  (func $test (local $x (ref $t)))
    #|)
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  let code = mod.codes[0]
  inspect(code.locals.length(), content="1")
  inspect(code.locals[0], content="RefFuncTyped(0)")
}
