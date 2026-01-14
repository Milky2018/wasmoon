///|
/// Regression tests for wide-arithmetic proposal

///|
test "wide-arithmetic: i64.mul_wide_u" {
  let source =
    #|(module
    #|  (func (export "test") (result i64 i64)
    #|    ;; (-1_u64) * 2 = 0x1FFFFFFFFFFFFFFE
    #|    ;; lo = 0xFFFFFFFFFFFFFFFE (-2), hi = 0x1
    #|    (i64.mul_wide_u (i64.const -1) (i64.const 2))
    #|  )
    #|)
  let interp = run_interp_only(source, "test", [])
  inspect(interp, content="Ok([I64(-2), I64(1)])")
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "wide-arithmetic: i64.mul_wide_s" {
  let source =
    #|(module
    #|  (func (export "test") (result i64 i64)
    #|    ;; (-1_s64) * 2 = -2 in 128-bit
    #|    ;; lo = -2, hi = -1
    #|    (i64.mul_wide_s (i64.const -1) (i64.const 2))
    #|  )
    #|)
  let interp = run_interp_only(source, "test", [])
  inspect(interp, content="Ok([I64(-2), I64(-1)])")
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}
