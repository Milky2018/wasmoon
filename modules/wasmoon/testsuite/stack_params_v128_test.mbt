///|
test "v128 stack param (9th v128 arg)" {
  let source =
    #|(module
    #|  (func (export "test")
    #|    (param v128 v128 v128 v128 v128 v128 v128 v128 v128)
    #|    (result v128)
    #|    (local.get 8))
    #|)
  let v = @types.Value::V128(
    b"\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10",
  )
  let result = compare_jit_interp(source, "test", [v, v, v, v, v, v, v, v, v])
  inspect(result, content="matched")
}

///|
test "mixed overflow: f32 then v128 (16-byte alignment)" {
  let source =
    #|(module
    #|  (func (export "test")
    #|    (param f64 f64 f64 f64 f64 f64 f64 f64 f32 v128)
    #|    (result v128)
    #|    (local.get 9))
    #|)
  let v = @types.Value::V128(
    b"\x10\x0f\x0e\x0d\x0c\x0b\x0a\x09\x08\x07\x06\x05\x04\x03\x02\x01",
  )
  let result = compare_jit_interp(source, "test", [
    F64(1.0),
    F64(2.0),
    F64(3.0),
    F64(4.0),
    F64(5.0),
    F64(6.0),
    F64(7.0),
    F64(8.0),
    F32(3.5),
    v,
  ])
  inspect(result, content="matched")
}
