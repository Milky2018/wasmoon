///|
test "wide arithmetic: multiply returns low and high halves" {
  let source =
    #|(module
    #|  (func (export "test") (param i64 i64) (result i64 i64)
    #|    local.get 0 local.get 1 i64.mul_wide_u))
  let result = compare_jit_interp(source, "test", [I64(-1L), I64(-1L)])
  debug_inspect(result.interp_result, content="Ok([I64(1), I64(-2)])")
  debug_inspect(result.jit_result, content="Ok([I64(1), I64(-2)])")
}

///|
test "wide arithmetic: addition propagates unsigned carry" {
  let source =
    #|(module
    #|  (func (export "test") (param i64 i64 i64 i64) (result i64 i64)
    #|    local.get 0 local.get 1 local.get 2 local.get 3 i64.add128))
  let result = compare_jit_interp(source, "test", [
    I64(-1L),
    I64(7L),
    I64(1L),
    I64(9L),
  ])
  debug_inspect(result.interp_result, content="Ok([I64(0), I64(17)])")
  debug_inspect(result.jit_result, content="Ok([I64(0), I64(17)])")
}

///|
test "wide arithmetic: subtraction propagates unsigned borrow" {
  let source =
    #|(module
    #|  (func (export "test") (param i64 i64 i64 i64) (result i64 i64)
    #|    local.get 0 local.get 1 local.get 2 local.get 3 i64.sub128))
  let result = compare_jit_interp(source, "test", [
    I64(0L),
    I64(0L),
    I64(1L),
    I64(1L),
  ])
  debug_inspect(result.interp_result, content="Ok([I64(-1), I64(-2)])")
  debug_inspect(result.jit_result, content="Ok([I64(-1), I64(-2)])")
}

///|
test "wide arithmetic: conditional signed and unsigned products" {
  let source =
    #|(module
    #|  (func (export "test") (param i32 i64 i64) (result i64 i64)
    #|    local.get 0
    #|    if (result i64 i64)
    #|      local.get 1 local.get 2 i64.mul_wide_s
    #|    else
    #|      local.get 1 local.get 2 i64.mul_wide_u
    #|    end))
  let signed = compare_jit_interp(source, "test", [I32(1), I64(-1L), I64(-1L)])
  debug_inspect(signed.interp_result, content="Ok([I64(1), I64(0)])")
  debug_inspect(signed.jit_result, content="Ok([I64(1), I64(0)])")
  let unsigned = compare_jit_interp(source, "test", [I32(0), I64(-1L), I64(-1L)])
  debug_inspect(unsigned.interp_result, content="Ok([I64(1), I64(-2)])")
  debug_inspect(unsigned.jit_result, content="Ok([I64(1), I64(-2)])")
}
