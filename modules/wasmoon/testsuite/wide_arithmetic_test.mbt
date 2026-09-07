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
  debug_inspect(interp, content="Ok([I64(-2), I64(1)])")
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
  debug_inspect(interp, content="Ok([I64(-2), I64(-1)])")
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "wide arithmetic: binary encoding preserves every opcode" {
  let source =
    #|(module (func (result i64 i64)
    #|  unreachable i64.add128 i64.sub128 i64.mul_wide_s i64.mul_wide_u))
  let module_ = @wat.parse(source)
  @validator.validate_module(module_)
  let bytes = Bytes::from_array(@encoder.encode(module_).map(n => n.to_byte()))
  let decoded = @parser.parse_module(bytes)
  @validator.validate_module(decoded)
  debug_inspect(
    decoded.codes[0].body,
    content="[Unreachable, I64Add128, I64Sub128, I64MulWideS, I64MulWideU]",
  )
}
