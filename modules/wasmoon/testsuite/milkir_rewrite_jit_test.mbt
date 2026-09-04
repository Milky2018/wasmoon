///|
test "JIT: comparison rewrites preserve signed-extension semantics" {
  let source =
    #|(module
    #|  (func (export "test") (param i32) (result i32)
    #|    local.get 0
    #|    i64.extend_i32_s
    #|    i64.const 0
    #|    i64.lt_s
    #|  )
    #|)
  for value in [-2147483648, -1, 0, 1, 2147483647] {
    assert_true(
      compare_result_is_match(compare_jit_interp(source, "test", [I32(value)])),
    )
  }
}

///|
test "JIT: comparison rewrites preserve zero-extension sign facts" {
  let source =
    #|(module
    #|  (func (export "test") (param i32) (result i32)
    #|    local.get 0
    #|    i64.extend_i32_u
    #|    i64.const 0
    #|    i64.lt_s
    #|  )
    #|)
  for value in [-2147483648, -1, 0, 1, 2147483647] {
    assert_true(
      compare_result_is_match(compare_jit_interp(source, "test", [I32(value)])),
    )
  }
}

///|
test "JIT: shift-mask rewrite preserves edge values" {
  let source =
    #|(module
    #|  (func (export "test") (param i32) (result i32)
    #|    local.get 0
    #|    i32.const 8
    #|    i32.shr_u
    #|    i32.const 8
    #|    i32.shl
    #|  )
    #|)
  for value in [-2147483648, -1, 0, 1, 2147483647] {
    assert_true(
      compare_result_is_match(compare_jit_interp(source, "test", [I32(value)])),
    )
  }
}

///|
test "JIT: opposite-rotation cancellation preserves masked amounts" {
  let source =
    #|(module
    #|  (func (export "test") (param i32 i32) (result i32)
    #|    local.get 0
    #|    local.get 1
    #|    i32.rotr
    #|    local.get 1
    #|    i32.rotl
    #|  )
    #|)
  for amount in [0, 1, 31, 32, 63, -1] {
    assert_true(
      compare_result_is_match(
        compare_jit_interp(source, "test", [I32(0x87654321), I32(amount)]),
      ),
    )
  }
}

///|
test "JIT: migrated modular arithmetic and comparisons preserve edge inputs" {
  let bodies = [
    "(i32.add (i32.and (local.get 0) (local.get 1)) (i32.xor (local.get 0) (local.get 1)))",
    "(i32.xor (i32.or (local.get 0) (local.get 1)) (i32.and (local.get 0) (local.get 1)))",
    "(i32.gt_u (i32.sub (local.get 0) (local.get 1)) (local.get 0))", "(i32.gt_s (select (local.get 0) (local.get 1) (i32.lt_s (local.get 0) (local.get 1))) (local.get 0))",
    "(i32.add (i32.shl (local.get 0) (i32.const 7)) (i32.shl (local.get 1) (i32.const 7)))",
    "(i32.wrap_i64 (i64.add (i64.extend_i32_u (local.get 0)) (i64.extend_i32_u (local.get 1))))",
  ]
  for body in bodies {
    let source = "(module (func (export \"test\") (param i32 i32) (result i32) \{body}))"
    for
      pair in [
        (-2147483648, -1),
        (-1, 1),
        (0, 0),
        (1, 2147483647),
        (2147483647, -2147483648),
      ] {
      assert_true(
        compare_result_is_match(
          compare_jit_interp(source, "test", [I32(pair.0), I32(pair.1)]),
        ),
      )
    }
  }
}

///|
test "JIT: narrow shifts retain wide count semantics" {
  for amount in [0, 31, 32, 63, 64, -1] {
    let source = "(module (func (export \"test\") (param i32) (result i32) (i32.wrap_i64 (i64.shl (i64.extend_i32_u (local.get 0)) (i64.const \{amount})))))"
    assert_true(
      compare_result_is_match(compare_jit_interp(source, "test", [I32(-1)])),
    )
  }
}

///|
test "JIT: float migration preserves signed zero and ties to even" {
  for
    expression in [
      "(f64.nearest (f64.const -0.5))", "(f64.nearest (f64.const 2.5))", "(f64.min (f64.const 0) (f64.const -0))",
      "(f64.max (f64.const -0) (f64.const 0))", "(f64.neg (f64.const nan:0x42))",
    ] {
    let source = "(module (func (export \"test\") (result i64) (i64.reinterpret_f64 \{expression})))"
    assert_true(compare_result_is_match(compare_jit_interp(source, "test", [])))
  }
}

///|
test "JIT: vector splat lifting preserves narrow lane wrapping" {
  for lane in ["i8x16", "i16x8", "i32x4"] {
    let source = "(module (func (export \"test\") (param i32 i32) (result i32) (i32x4.extract_lane 0 (\{lane}.add (\{lane}.splat (local.get 0)) (\{lane}.splat (local.get 1))))))"
    for pair in [(-1, 1), (255, 1), (65535, 1), (-2147483648, -1)] {
      assert_true(
        compare_result_is_match(
          compare_jit_interp(source, "test", [I32(pair.0), I32(pair.1)]),
        ),
      )
    }
  }
}
