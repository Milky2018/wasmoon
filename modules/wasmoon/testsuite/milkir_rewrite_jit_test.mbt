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
