///|
// Test saturating truncation instructions
test "i32.trunc_sat_f32_s basic" {
  let source =
    #|(module
    #|  (func (export "trunc_sat") (param f32) (result i32)
    #|    (i32.trunc_sat_f32_s (local.get 0))
    #|  )
    #|)
  let result = compare_jit_interp(source, "trunc_sat", [@types.Value::F32(1.0)])
  inspect(result, content="matched")
}

///|
test "i32.trunc_sat_f32_s nan" {
  let source =
    #|(module
    #|  (func (export "trunc_sat") (param f32) (result i32)
    #|    (i32.trunc_sat_f32_s (local.get 0))
    #|  )
    #|)
  let nan = Float::reinterpret_from_int(0x7FC00000) // canonical NaN
  let result = compare_jit_interp(source, "trunc_sat", [@types.Value::F32(nan)])
  inspect(result, content="matched")
}

///|
test "i32.trunc_sat_f32_s overflow_positive" {
  let source =
    #|(module
    #|  (func (export "trunc_sat") (param f32) (result i32)
    #|    (i32.trunc_sat_f32_s (local.get 0))
    #|  )
    #|)
  let result = compare_jit_interp(source, "trunc_sat", [
    @types.Value::F32(2147483648.0),
  ])
  inspect(result, content="matched")
}

///|
test "i32.trunc_sat_f32_s overflow_negative" {
  let source =
    #|(module
    #|  (func (export "trunc_sat") (param f32) (result i32)
    #|    (i32.trunc_sat_f32_s (local.get 0))
    #|  )
    #|)
  let result = compare_jit_interp(source, "trunc_sat", [
    @types.Value::F32(-2147483904.0),
  ])
  inspect(result, content="matched")
}

///|
test "i32.trunc_sat_f32_u basic" {
  let source =
    #|(module
    #|  (func (export "trunc_sat") (param f32) (result i32)
    #|    (i32.trunc_sat_f32_u (local.get 0))
    #|  )
    #|)
  let result = compare_jit_interp(source, "trunc_sat", [@types.Value::F32(1.0)])
  inspect(result, content="matched")
}

///|
test "i32.trunc_sat_f32_u overflow" {
  let source =
    #|(module
    #|  (func (export "trunc_sat") (param f32) (result i32)
    #|    (i32.trunc_sat_f32_u (local.get 0))
    #|  )
    #|)
  let result = compare_jit_interp(source, "trunc_sat", [
    @types.Value::F32(4294967296.0),
  ])
  inspect(result, content="matched")
}

///|
test "i64.trunc_sat_f64_s basic" {
  let source =
    #|(module
    #|  (func (export "trunc_sat") (param f64) (result i64)
    #|    (i64.trunc_sat_f64_s (local.get 0))
    #|  )
    #|)
  let result = compare_jit_interp(source, "trunc_sat", [@types.Value::F64(1.0)])
  inspect(result, content="matched")
}

///|
test "i64.trunc_sat_f64_u basic" {
  let source =
    #|(module
    #|  (func (export "trunc_sat") (param f64) (result i64)
    #|    (i64.trunc_sat_f64_u (local.get 0))
    #|  )
    #|)
  let result = compare_jit_interp(source, "trunc_sat", [@types.Value::F64(1.0)])
  inspect(result, content="matched")
}
