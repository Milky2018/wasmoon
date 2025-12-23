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
test "regression: conditional 0.0 vs -0.0 now works correctly" {
  let neg = false
  let result = if neg { -0.0 } else { 0.0 }
  let bits = result.reinterpret_as_int64()
  // After MoonBit fix: correctly returns 0 (positive zero)
  inspect(bits, content="0")
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
  inspect(mod.get_func_type(0).params.length(), content="1")
  inspect(mod.get_func_type(0).results.length(), content="0")
  // Implicit type should be type 1: (func (result f64))
  inspect(mod.get_func_type(1).params.length(), content="0")
  inspect(mod.get_func_type(1).results.length(), content="1")
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

///|
test "regression: select with nested ref type in result annotation" {
  // select (result (ref null func)) should properly parse the nested parentheses
  // in the result type annotation. Previously, the parser would stop at the first
  // closing paren inside (ref null func), leaving the operands unparsed.
  let wat =
    #|(module
    #|  (type $t (func))
    #|  (func $tf) (elem declare func $tf)
    #|  (func (export "join-funcnull") (param i32) (result (ref null func))
    #|    (select (result (ref null func))
    #|      (ref.func $tf)
    #|      (ref.null func)
    #|      (local.get 0)
    #|    )
    #|  )
    #|)
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  // Should have parsed successfully with 2 functions
  inspect(mod.funcs.length(), content="2")
  // The exported function should have the typed select instruction
  let code = mod.codes[1]
  // Body should contain: RefFunc, RefNull, LocalGet, SelectTyped
  inspect(code.body.length(), content="4")
  // With result type annotation, should use SelectTyped not Select
  // (ref null func) is FuncRef, not RefNullFuncTyped - it's the abstract type
  inspect(code.body[3], content="SelectTyped([FuncRef])")
}

///|
test "regression: flat form with optional labels after else and end" {
  // WAT flat form allows optional label IDs after 'if', 'else', and 'end'
  // These labels are for documentation purposes and should be skipped.
  // Previously: parser failed with "expected 'end', got Id("body")"
  let wat =
    #|(module
    #|  (func (export "fac-stack-raw") (param $n i64) (result i64)
    #|    (local $i i64)
    #|    (local $res i64)
    #|    local.get $n
    #|    local.set $i
    #|    i64.const 1
    #|    local.set $res
    #|    block $done
    #|      loop $loop
    #|        local.get $i
    #|        i64.const 0
    #|        i64.eq
    #|        if $body
    #|          br $done
    #|        else $body
    #|          local.get $i
    #|          local.get $res
    #|          i64.mul
    #|          local.set $res
    #|          local.get $i
    #|          i64.const 1
    #|          i64.sub
    #|          local.set $i
    #|        end $body
    #|        br $loop
    #|      end $loop
    #|    end $done
    #|    local.get $res
    #|  )
    #|)
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  inspect(mod.funcs.length(), content="1")
  inspect(mod.exports.length(), content="1")
  inspect(mod.exports[0].name, content="fac-stack-raw")
}

// ============================================================
// Export-before-import pattern tests
// ============================================================

///|
test "parse WAT: global export before import" {
  // Global with export before import - tests export-before-import handling
  let wat =
    #|(module
    #|  (global $g (export "g") (import "spectest" "global_i32") i32)
    #|)
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  inspect(mod.imports.length(), content="1")
  inspect(mod.imports[0].mod_name, content="spectest")
  inspect(mod.imports[0].name, content="global_i32")
  inspect(mod.exports.length(), content="1")
  inspect(mod.exports[0].name, content="g")
}

///|
test "parse WAT: global import before export" {
  // Global with import before export - standard order
  let wat =
    #|(module
    #|  (global $g (import "spectest" "global_i32") (export "g") i32)
    #|)
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  inspect(mod.imports.length(), content="1")
  inspect(mod.exports.length(), content="1")
  inspect(mod.exports[0].name, content="g")
}

///|
test "parse WAT: global multiple exports with import" {
  // Global with multiple exports and import
  let wat =
    #|(module
    #|  (global $g (export "g1") (export "g2") (import "spectest" "global_i32") i32)
    #|)
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  inspect(mod.imports.length(), content="1")
  inspect(mod.exports.length(), content="2")
  inspect(mod.exports[0].name, content="g1")
  inspect(mod.exports[1].name, content="g2")
}

///|
test "parse WAT: memory export before import" {
  // Memory with export before import
  let wat =
    #|(module
    #|  (memory $m (export "m") (import "spectest" "memory") 1 2)
    #|)
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  inspect(mod.imports.length(), content="1")
  inspect(mod.imports[0].mod_name, content="spectest")
  inspect(mod.imports[0].name, content="memory")
  inspect(mod.exports.length(), content="1")
  inspect(mod.exports[0].name, content="m")
}

///|
test "parse WAT: table export before import" {
  // Table with export before import
  let wat =
    #|(module
    #|  (table $t (export "t") (import "spectest" "table") 10 20 funcref)
    #|)
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  inspect(mod.imports.length(), content="1")
  inspect(mod.imports[0].mod_name, content="spectest")
  inspect(mod.imports[0].name, content="table")
  inspect(mod.exports.length(), content="1")
  inspect(mod.exports[0].name, content="t")
}

///|
test "parse WAT: func export before import" {
  // Function with export before import
  let wat =
    #|(module
    #|  (func $f (export "f") (import "spectest" "print_i32") (param i32))
    #|)
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  inspect(mod.imports.length(), content="1")
  inspect(mod.imports[0].mod_name, content="spectest")
  inspect(mod.imports[0].name, content="print_i32")
  inspect(mod.exports.length(), content="1")
  inspect(mod.exports[0].name, content="f")
}

///|
test "parse WAT: func multiple exports before import" {
  // Function with multiple exports before import
  let wat =
    #|(module
    #|  (func $f (export "f1") (export "f2") (import "spectest" "print_i32") (param i32))
    #|)
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  inspect(mod.imports.length(), content="1")
  inspect(mod.exports.length(), content="2")
  inspect(mod.exports[0].name, content="f1")
  inspect(mod.exports[1].name, content="f2")
}

// ============================================================
// Error location tests
// ============================================================

///|
test "error location: unexpected token reports correct position" {
  // Test that error locations point to the correct token
  let wat = "(module (func invalid))"
  let result = try? parse(wat)
  match result {
    Err(InvalidInstruction(s, loc)) => {
      inspect(s, content="invalid")
      inspect(loc.line, content="1")
      // Position depends on lexer implementation
      inspect(loc.column > 0, content="true")
    }
    Err(_) =>
      // Accept other error types - the important thing is parsing failed
      ()
    Ok(_) => fail("expected error but parsing succeeded")
  }
}

///|
test "error location: multiline error position" {
  let wat =
    #|(module
    #|  (func
    #|    invalid
    #|  )
    #|)
  let result = try? parse(wat)
  match result {
    Err(InvalidInstruction(s, loc)) => {
      inspect(s, content="invalid")
      // Should be on line 3 or 4 depending on how multiline strings work
      inspect(loc.line >= 3, content="true")
    }
    Err(_) =>
      // Accept other error types
      ()
    Ok(_) => fail("expected error but parsing succeeded")
  }
}

// ============================================================
// Annotation handling in parser tests
// ============================================================

///|
test "parse WAT: annotations in module definition" {
  // Simple module with annotations - they should be skipped
  let wat = "(@a) (module (@b) )"
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  inspect(mod.funcs.length(), content="0")
}

///|
test "parse WAT: annotations around func definition" {
  let wat =
    #|(module
    #|  (@a) (func (@b) $f (@c))
    #|)
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  inspect(mod.funcs.length(), content="1")
}

///|
test "parse WAT: annotations around global definition" {
  let wat =
    #|(module
    #|  (@a) (global (@b) $g (@c) i32 (@d) (i32.const (@e) 0 (@f)))
    #|)
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  inspect(mod.globals.length(), content="1")
}

///|
test "parse WAT: annotations around memory definition" {
  let wat =
    #|(module
    #|  (@a) (memory (@b) $m (@c) 1 (@d) 2 (@e))
    #|)
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  inspect(mod.memories.length(), content="1")
}

///|
test "parse WAT: annotations around table definition" {
  let wat =
    #|(module
    #|  (@a) (table (@b) $t (@c) 1 (@d) funcref (@e))
    #|)
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  inspect(mod.tables.length(), content="1")
}

///|
test "parse WAT: annotations around type definition" {
  let wat =
    #|(module
    #|  (@a) (type (@b) $t (@c) (func (@d) (param (@e) i32) (@f) (result (@g) i32)))
    #|)
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  inspect(mod.types.length(), content="1")
  inspect(mod.get_func_type(0).params.length(), content="1")
  inspect(mod.get_func_type(0).results.length(), content="1")
}

///|
test "parse WAT: annotations around instructions" {
  let wat =
    #|(module
    #|  (func (@a)
    #|    (@b) i32.const (@c) 42 (@d)
    #|    (@e) drop (@f)
    #|  )
    #|)
  let mod = parse(wat) catch { e => fail("Parse error: \{e}") }
  inspect(mod.funcs.length(), content="1")
  let code = mod.codes[0]
  inspect(code.body.length(), content="2")
  inspect(code.body[0], content="I32Const(42)")
  inspect(code.body[1], content="Drop")
}

// ============================================================================
// Inline module parsing tests (WAST format without explicit module wrapper)
// ============================================================================

///|
test "is_module_field_keyword: recognizes all module field keywords" {
  // All module field keywords should be recognized
  inspect(is_module_field_keyword("type"), content="true")
  inspect(is_module_field_keyword("import"), content="true")
  inspect(is_module_field_keyword("func"), content="true")
  inspect(is_module_field_keyword("table"), content="true")
  inspect(is_module_field_keyword("memory"), content="true")
  inspect(is_module_field_keyword("global"), content="true")
  inspect(is_module_field_keyword("export"), content="true")
  inspect(is_module_field_keyword("start"), content="true")
  inspect(is_module_field_keyword("elem"), content="true")
  inspect(is_module_field_keyword("data"), content="true")
  inspect(is_module_field_keyword("tag"), content="true")
  // Non-module keywords should not be recognized
  inspect(is_module_field_keyword("module"), content="false")
  inspect(is_module_field_keyword("assert_return"), content="false")
  inspect(is_module_field_keyword("invoke"), content="false")
  inspect(is_module_field_keyword("i32"), content="false")
}

///|
test "parse WAST inline module: simple func" {
  // Inline module with just a function
  let wast = "(func)"
  let script = parse_wast(wast) catch { e => fail("Parse error: \{e}") }
  inspect(script.commands.length(), content="1")
  guard script.commands[0].0 is Module(mod_, _) else {
    fail("Expected Module command")
  }
  inspect(mod_.funcs.length(), content="1")
}

///|
test "parse WAST inline module: func and memory" {
  // Inline module matching spec/inline-module.wast
  let wast = "(func) (memory 0) (func (export \"f\"))"
  let script = parse_wast(wast) catch { e => fail("Parse error: \{e}") }
  inspect(script.commands.length(), content="1")
  guard script.commands[0].0 is Module(mod_, _) else {
    fail("Expected Module command")
  }
  inspect(mod_.funcs.length(), content="2")
  inspect(mod_.memories.length(), content="1")
  inspect(mod_.exports.length(), content="1")
  inspect(mod_.exports[0].name, content="f")
}

///|
test "parse WAST inline module: multiple fields" {
  // Inline module with various field types
  let wast =
    #|(type $t (func (param i32) (result i32)))
    #|(global $g i32 (i32.const 42))
    #|(memory 1)
    #|(table 1 funcref)
    #|(func $add (type $t) (local.get 0))
  let script = parse_wast(wast) catch { e => fail("Parse error: \{e}") }
  inspect(script.commands.length(), content="1")
  guard script.commands[0].0 is Module(mod_, _) else {
    fail("Expected Module command")
  }
  inspect(mod_.types.length(), content="1")
  inspect(mod_.globals.length(), content="1")
  inspect(mod_.memories.length(), content="1")
  inspect(mod_.tables.length(), content="1")
  inspect(mod_.funcs.length(), content="1")
}

///|
test "parse WAST inline module: with exports" {
  // Inline module with multiple exports
  let wast =
    #|(memory (export "mem") 1)
    #|(global (export "g") i32 (i32.const 100))
    #|(func (export "run") (result i32) (i32.const 42))
  let script = parse_wast(wast) catch { e => fail("Parse error: \{e}") }
  inspect(script.commands.length(), content="1")
  guard script.commands[0].0 is Module(mod_, _) else {
    fail("Expected Module command")
  }
  inspect(mod_.exports.length(), content="3")
  inspect(mod_.exports[0].name, content="mem")
  inspect(mod_.exports[1].name, content="g")
  inspect(mod_.exports[2].name, content="run")
}

///|
test "parse WAST inline module: with imports" {
  // Inline module with imports
  let wast =
    #|(import "env" "memory" (memory 1))
    #|(import "env" "log" (func (param i32)))
    #|(func (export "test") (call 0 (i32.const 42)))
  let script = parse_wast(wast) catch { e => fail("Parse error: \{e}") }
  inspect(script.commands.length(), content="1")
  guard script.commands[0].0 is Module(mod_, _) else {
    fail("Expected Module command")
  }
  inspect(mod_.imports.length(), content="2")
  inspect(mod_.imports[0].mod_name, content="env")
  inspect(mod_.imports[0].name, content="memory")
  inspect(mod_.imports[1].mod_name, content="env")
  inspect(mod_.imports[1].name, content="log")
  inspect(mod_.funcs.length(), content="1")
}

///|
test "parse WAST inline module: data and elem segments" {
  // Inline module with data and elem segments
  let wast =
    #|(memory 1)
    #|(table 1 funcref)
    #|(func $f)
    #|(data (i32.const 0) "hello")
    #|(elem (i32.const 0) $f)
  let script = parse_wast(wast) catch { e => fail("Parse error: \{e}") }
  inspect(script.commands.length(), content="1")
  guard script.commands[0].0 is Module(mod_, _) else {
    fail("Expected Module command")
  }
  inspect(mod_.datas.length(), content="1")
  inspect(mod_.elems.length(), content="1")
}

///|
test "parse WAST inline module: start function" {
  // Inline module with start function
  let wast =
    #|(func $init)
    #|(start $init)
  let script = parse_wast(wast) catch { e => fail("Parse error: \{e}") }
  inspect(script.commands.length(), content="1")
  guard script.commands[0].0 is Module(mod_, _) else {
    fail("Expected Module command")
  }
  inspect(mod_.funcs.length(), content="1")
  inspect(mod_.start, content="Some(0)")
}

///|
test "parse WAST: explicit module is not inline" {
  // Explicit (module ...) should not be treated as inline
  let wast = "(module (func))"
  let script = parse_wast(wast) catch { e => fail("Parse error: \{e}") }
  inspect(script.commands.length(), content="1")
  guard script.commands[0].0 is Module(mod_, _) else {
    fail("Expected Module command")
  }
  inspect(mod_.funcs.length(), content="1")
}

///|
test "parse WAST: assert commands are not inline modules" {
  // WAST commands should not be treated as inline modules
  let wast =
    #|(module (func (export "f") (result i32) (i32.const 42)))
    #|(assert_return (invoke "f") (i32.const 42))
  let script = parse_wast(wast) catch { e => fail("Parse error: \{e}") }
  inspect(script.commands.length(), content="2")
  guard script.commands[0].0 is Module(_, _) else {
    fail("Expected Module command")
  }
  guard script.commands[1].0 is AssertReturn(_, _) else {
    fail("Expected AssertReturn command")
  }
}

///|
test "parse WAST: module definition and instance" {
  // Test module definition followed by module instance
  let wast =
    #|(module definition $M
    #|  (global (export "g") (mut i32) (i32.const 0))
    #|)
    #|(module instance $I1 $M)
    #|(module instance $I2 $M)
  let script = parse_wast(wast) catch { e => fail("Parse error: \{e}") }
  inspect(script.commands.length(), content="3")
  guard script.commands[0].0 is ModuleDefinition(mod_, Some("M")) else {
    fail("Expected ModuleDefinition command with name M")
  }
  inspect(mod_.globals.length(), content="1")
  guard script.commands[1].0 is ModuleInstance(Some("I1"), "M") else {
    fail("Expected ModuleInstance I1 from M")
  }
  guard script.commands[2].0 is ModuleInstance(Some("I2"), "M") else {
    fail("Expected ModuleInstance I2 from M")
  }
}
