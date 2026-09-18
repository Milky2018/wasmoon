///|
test "success parity rejects parse validation and export lookup failures" {
  for
    source in [
      "(module (func (export \"test\") i32.not))", "(module (func (export \"test\") (result i32) f64.const 0))",
      "(module (func (export \"other\")))",
    ] {
    let result = @testsuite.compare_jit_interp(source, "test", [])
    inspect(@testsuite.compare_result_is_match(result), content="false")
    inspect(result.matched(), content="false")
  }
}

///|
test "success parity rejects matching traps and trap checks require expected text" {
  let result = @testsuite.compare_jit_interp(
    "(module (func (export \"test\") unreachable))",
    "test",
    [],
  )
  inspect(result.matched(), content="false")
  inspect(
    @testsuite.compare_result_errors_contain(result, "unreachable"),
    content="true",
  )
  inspect(
    @testsuite.compare_result_errors_contain(result, "out of bounds"),
    content="false",
  )
}

///|
test "success parity accepts successful execution with explicit expected values" {
  let result = @testsuite.compare_jit_interp(
    "(module (func (export \"test\") (result i32) i32.const 42))",
    "test",
    [],
  )
  inspect(result, content="matched")
  inspect(
    result.to_string(),
    content="JIT: I32(42)\nInterpreter: I32(42)\nResult: MATCH",
  )
  inspect(
    @testsuite.compare_result_errors_contain(result, "unreachable"),
    content="false",
  )
}
