///|
test "table64 allocation overflow is checked before narrowing" {
  let source = "(module (table i64 0x2000000000000000 funcref) (func (export \"test\")))"
  let result = compare_jit_interp(source, "test", [])
  inspect(
    compare_result_errors_contain(
      result, "overflow calculating table allocation size",
    ),
    content="true",
  )
}

///|
test "table64 growth preserves allocation failure and limit failure distinctions" {
  for opt_level in [0, 2] {
    let result = compare_jit_interp_with_opt_level(
      "(module (table i64 0 funcref) (func (export \"test\") (result i64) ref.null func i64.const 0x2000000000000000 table.grow 0))",
      "test",
      [],
      opt_level,
    )
    inspect(
      compare_result_errors_contain(result, "failed to allocate"),
      content="true",
    )
    let result = compare_jit_interp_with_opt_level(
      "(module (table i64 0 4294967296 funcref) (func (export \"test\") (result i64 i64 i64) ref.null func i64.const 1 table.grow 0 ref.null func i64.const 0x2000000000000000 table.grow 0 table.size 0))",
      "test",
      [],
      opt_level,
    )
    inspect(
      result.to_string(),
      content="JIT: I64(0), I64(-1), I64(1)\nInterpreter: I64(0), I64(-1), I64(1)\nResult: MATCH",
    )
    let result = compare_jit_interp_with_opt_level(
      "(module (table i64 1 funcref) (func (export \"test\") (result i64 i64) ref.null func i64.const -1 table.grow 0 table.size 0))",
      "test",
      [],
      opt_level,
    )
    inspect(
      result.to_string(),
      content="JIT: I64(-1), I64(1)\nInterpreter: I64(-1), I64(1)\nResult: MATCH",
    )
  }
}
