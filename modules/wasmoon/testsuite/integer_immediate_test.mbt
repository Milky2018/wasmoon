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
