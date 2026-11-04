///|
test "comparison branches preserve signedness and loop-carried values" {
  for width in [32, 64] {
    let source =
      $|(module
      $|(func (export "run") (param $left i\{width}) (param $right i\{width}) (result i\{width})
      $|  (local $i i32) (local $temporary i\{width})
      $|  (block $done (loop $again
      $|    (br_if $done (i32.ge_u (local.get $i) (i32.const 17)))
      $|    (if (i\{width}.lt_s (local.get $left) (local.get $right))
      $|      (then
      $|        (local.set $temporary (local.get $left))
      $|        (local.set $left (local.get $right))
      $|        (local.set $right (local.get $temporary)))
      $|      (else (local.set $right (i\{width}.add (local.get $right) (i\{width}.const 1)))))
      $|    (if (i\{width}.gt_u (local.get $left) (i\{width}.const 511))
      $|      (then (local.set $left (i\{width}.xor (local.get $left) (local.get $right))))
      $|      (else (local.set $left (i\{width}.add (local.get $left) (local.get $right)))))
      $|    (local.set $i (i32.add (local.get $i) (i32.const 1)))
      $|    (br $again)))
      $|  (i\{width}.sub (local.get $left) (local.get $right))))
    for opt_level in [0, 2] {
      let cases : Array[(Int64, Int64)] = [
        (0L, 1L),
        (-1L, 0L),
        (-2147483648L, 2147483647L),
        (-9223372036854775808L, 9223372036854775807L),
      ]
      for (left, right) in cases {
        let args : Array[@types.Value] = if width == 32 {
          [I32(left.to_int()), I32(right.to_int())]
        } else {
          [I64(left), I64(right)]
        }
        inspect(
          @testsuite.compare_jit_interp_with_opt_level(
            source, "run", args, opt_level,
          ),
          content="matched",
        )
      }
    }
  }
}
