///|
test "JIT: arithmetic immediates preserve width, operand order and shared constants" {
  for
    (width, constants) in [
      (
        "i32",
        ["-1", "-64", "-4095", "-4096", "-4097", "-16773120", "-2147483648"],
      ),
      (
        "i64",
        [
          "-1", "-64", "-4095", "-4096", "-4097", "-16773120", "-9223372036854775808",
        ],
      ),
    ] {
    for constant in constants {
      let source =
        $|(module
        $|  (func (export "test") (param $x \{width})
        $|    (result \{width} \{width} \{width} \{width} \{width})
        $|    (local $c \{width})
        $|    (local.set $c (\{width}.const \{constant}))
        $|    (\{width}.add (local.get $x) (local.get $c))
        $|    (\{width}.add (local.get $c) (local.get $x))
        $|    (\{width}.sub (local.get $x) (local.get $c))
        $|    (\{width}.sub (local.get $c) (local.get $x))
        $|    (local.get $c)))
      let inputs : Array[@types.Value] = if width == "i32" {
        [I32(0), I32(-1), I32(2147483647), I32(-2147483648)]
      } else {
        [
          I64(0L),
          I64(-1L),
          I64(9223372036854775807L),
          I64(-9223372036854775808L),
        ]
      }
      for input in inputs {
        inspect(
          @testsuite.compare_jit_interp(source, "test", [input]),
          content="matched",
        )
      }
    }
  }
}

///|
test "JIT: materialized integer constants preserve all bits" {
  for
    (width, constants) in [
      (
        "i32",
        [
          "0", "-1", "-64", "0x00ff00ff", "0x80000000", "0x12345678", "0xffff1234",
          "0x1234ffff",
        ],
      ),
      (
        "i64",
        [
          "0", "-1", "-64", "0x00ff00ff00ff00ff", "0x8000000000000000", "0x123456789abcdef0",
          "0xffff1234ffff5678", "0x1234ffffffffffff", "0xffffffff1234ffff", "0x00000000ffffffff",
        ],
      ),
    ] {
    for constant in constants {
      let source =
        $|(module (func (export "test") (result \{width})
        $|  (\{width}.const \{constant})))
      inspect(
        @testsuite.compare_jit_interp(source, "test", []),
        content="matched",
      )
    }
  }
}

///|
test "JIT: immediate comparisons preserve signedness and both operand orders" {
  for width in ["i32", "i64"] {
    for constant in ["0", "42", "4095", "4096", "16773120", "4097", "-1"] {
      let comparisons : Array[String] = []
      for
        operation in [
          "eq", "ne", "lt_s", "le_s", "gt_s", "ge_s", "lt_u", "le_u", "gt_u", "ge_u",
        ] {
        comparisons.push(
          "(\{width}.\{operation} (local.get $x) (\{width}.const \{constant}))",
        )
        comparisons.push(
          "(\{width}.\{operation} (\{width}.const \{constant}) (local.get $x))",
        )
      }
      let results = Array::make(20, "i32").join(" ")
      let body = comparisons.join("\n")
      let source = "(module (func (export \"test\") (param $x \{width}) (result \{results}) \{body}))"
      let inputs : Array[@types.Value] = if width == "i32" {
        [
          I32(0),
          I32(-1),
          I32(41),
          I32(42),
          I32(43),
          I32(-2147483648),
          I32(2147483647),
        ]
      } else {
        [
          I64(0L),
          I64(-1L),
          I64(41L),
          I64(42L),
          I64(43L),
          I64(-9223372036854775808L),
          I64(9223372036854775807L),
        ]
      }
      for input in inputs {
        inspect(
          @testsuite.compare_jit_interp(source, "test", [input]),
          content="matched",
        )
      }
    }
  }
}
