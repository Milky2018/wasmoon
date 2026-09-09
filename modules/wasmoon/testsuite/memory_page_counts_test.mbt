///|
test "single-byte memory64 pages retain size growth and declared maximum" {
  let source =
    #|(module
    #|  (memory i64 4294967296 4294967298 shared (pagesize 1))
    #|  (func (export "test") (result i64 i64 i64 i64)
    #|    memory.size
    #|    i64.const 1 memory.grow
    #|    memory.size
    #|    i64.const 2 memory.grow))
  for opt_level in [0, 2] {
    let result = compare_jit_interp_with_opt_level(
      source,
      "test",
      [],
      opt_level,
    )
    inspect(
      result.to_string(),
      content="JIT: I64(4294967296), I64(4294967296), I64(4294967297), I64(-1)\nInterpreter: I64(4294967296), I64(4294967296), I64(4294967297), I64(-1)\nResult: MATCH",
    )
  }
}

///|
test "single-byte memory32 caps growth below the failure sentinel" {
  let source =
    #|(module
    #|  (memory 4294967294 4294967295 shared (pagesize 1))
    #|  (func (export "test") (result i32 i32 i32 i32)
    #|    memory.size
    #|    i32.const 0 memory.grow
    #|    i32.const 1 memory.grow
    #|    memory.size))
  let result = compare_jit_interp(source, "test", [])
  inspect(
    result.to_string(),
    content="JIT: I32(-2), I32(-2), I32(-1), I32(-2)\nInterpreter: I32(-2), I32(-2), I32(-1), I32(-2)\nResult: MATCH",
  )
}
