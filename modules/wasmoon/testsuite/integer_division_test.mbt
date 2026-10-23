///|
test "JIT: signed remainder handles the minimum value divided by minus one" {
  let source =
    #|(module
    #|  (func (export "i32_rem") (result i32)
    #|    (i32.rem_s (i32.const 0x80000000) (i32.const -1)))
    #|  (func (export "i64_rem") (result i64)
    #|    (i64.rem_s (i64.const 0x8000000000000000) (i64.const -1))))
  inspect(
    @testsuite.compare_jit_interp(source, "i32_rem", []),
    content="matched",
  )
  inspect(
    @testsuite.compare_jit_interp(source, "i64_rem", []),
    content="matched",
  )
}

///|
test "JIT: constant reciprocal division preserves signed rounding at both widths" {
  for width in ["i32", "i64"] {
    let constants = if width == "i32" {
      [
        "1", "2", "3", "7", "10", "31", "65537", "2147483647", "-2", "-7", "-2147483648",
      ]
    } else {
      [
        "1", "2", "3", "7", "10", "31", "4294967297", "9223372036854775807", "-2",
        "-7", "-9223372036854775808",
      ]
    }
    let inputs : Array[@types.Value] = if width == "i32" {
      [
        I32(0),
        I32(1),
        I32(-1),
        I32(7),
        I32(-17),
        I32(2147483647),
        I32(-2147483648),
        I32(-2147483647),
      ]
    } else {
      [
        I64(0L),
        I64(1L),
        I64(-1L),
        I64(7L),
        I64(-17L),
        I64(9223372036854775807L),
        I64(-9223372036854775808L),
        I64(-9223372036854775807L),
      ]
    }
    for constant in constants {
      let source =
        $|(module (func (export "test") (param $x \{width}) (result \{width} \{width} \{width} \{width})
        $| (\{width}.div_s (local.get $x) (\{width}.const \{constant}))
        $| (\{width}.div_u (local.get $x) (\{width}.const \{constant}))
        $| (\{width}.rem_s (local.get $x) (\{width}.const \{constant}))
        $| (\{width}.rem_u (local.get $x) (\{width}.const \{constant}))))
      for input in inputs {
        for level in [2, 3] {
          let result = @testsuite.compare_jit_interp_with_opt_level(
            source,
            "test",
            [input],
            level,
          )
          assert_true(
            result.matched(),
            msg="\{width} / \{constant} at O\{level}: \{result}",
          )
        }
      }
    }
  }
}

///|
test "JIT: constant legalization retains divide by zero and signed overflow traps" {
  for width in ["i32", "i64"] {
    for
      (divisor, expected) in [
        ("0", "integer divide by zero"),
        ("-1", "integer overflow"),
      ] {
      let source =
        $|(module (func (export "test") (param $x \{width}) (result \{width})
        $| (\{width}.div_s (local.get $x) (\{width}.const \{divisor}))))
      let value : @types.Value = if width == "i32" {
        I32(-2147483648)
      } else {
        I64(-9223372036854775808L)
      }
      for level in [2, 3] {
        let result = @testsuite.compare_jit_interp_with_opt_level(
          source,
          "test",
          [value],
          level,
        )
        assert_true(
          @testsuite.compare_result_errors_contain(result, expected),
          msg=result.to_string(),
        )
      }
    }
  }
}
