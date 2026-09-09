///|
test "table64 bounds checks retain every index and length" {
  for
    operation in [
      "i64.const 4294967296 table.get 0 drop", "i64.const 4294967296 ref.null func table.set 0",
      "i64.const 4294967296 ref.null func i64.const 0 table.fill 0", "i64.const 0 ref.null func i64.const 4294967296 table.fill 0",
      "i64.const 4294967296 i64.const 0 i64.const 0 table.copy 0 0", "i64.const 0 i64.const 4294967296 i64.const 0 table.copy 0 0",
      "i64.const 0 i64.const 0 i64.const 4294967296 table.copy 0 0", "i64.const 4294967296 i32.const 0 i32.const 0 table.copy 0 1",
      "i32.const 0 i64.const 4294967296 i32.const 0 table.copy 1 0",
    ] {
    let source = "(module (table i64 1 funcref) (table 1 funcref) (func (export \"test\") \{operation}))"
    let result = compare_jit_interp(source, "test", [])
    inspect(
      compare_result_errors_contain(result, "out of bounds table access"),
      content="true",
    )
  }
}

///|
test "table64 indirect calls cannot alias a high index to zero" {
  for instruction in ["call_indirect", "return_call_indirect"] {
    let source = "(module (type $t (func (result i32))) (table i64 1 funcref) (func $target (type $t) i32.const 42) (elem (i64.const 0) func $target) (func (export \"test\") (param i64) (result i32) local.get 0 \{instruction} (type $t)))"
    inspect(
      compare_jit_interp(source, "test", [I64(0)]).to_string(),
      content="JIT: I32(42)\nInterpreter: I32(42)\nResult: MATCH",
    )
    let result = compare_jit_interp(source, "test", [I64(4294967296)])
    inspect(
      compare_result_errors_contain(result, "undefined element"),
      content="true",
    )
  }
}
