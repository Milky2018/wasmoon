///|
test "f32 identity multiple values" {
  let source =
    #|(module
    #|  (func (export "id") (param f32) (result f32)
    #|    (local.get 0))
    #|)
  // Test with multiple values to ensure it's not a fluke
  let r1 = compare_jit_interp(source, "id", [F32(1.0)])
  let r2 = compare_jit_interp(source, "id", [F32(2.0)])
  let r3 = compare_jit_interp(source, "id", [F32(123.456)])
  inspect(r1, content="matched")
  inspect(r2, content="matched")
  inspect(r3, content="matched")
}

///|
test "f32 add with prints" {
  let source =
    #|(module
    #|  (func (export "add") (param f32) (param f32) (result f32)
    #|    (f32.add (local.get 0) (local.get 1)))
    #|)
  // Test with very simple values
  let a = (1.0 : Float)
  let b = (2.0 : Float)
  let a_bits = a.reinterpret_as_int()
  let b_bits = b.reinterpret_as_int()
  inspect(a_bits, content="1065353216") // Should be 0x3F800000 = 1065353216
  inspect(b_bits, content="1073741824") // Should be 0x40000000 = 1073741824
  let result = compare_jit_interp(source, "add", [F32(a), F32(b)])
  inspect(result, content="matched")
}

///|
// Test for 8 f64 parameters - parameters 4-7 fail
test "f64 8 params - get param 0" {
  let source =
    #|(module
    #|  (func (export "get_p0") (param f64) (param f64) (param f64) (param f64) (param f64) (param f64) (param f64) (param f64) (result f64)
    #|    (local.get 0))
    #|)
  let result = compare_jit_interp(source, "get_p0", [
    F64(1.0),
    F64(2.0),
    F64(3.0),
    F64(4.0),
    F64(5.0),
    F64(6.0),
    F64(7.0),
    F64(8.0),
  ])
  inspect(result, content="matched")
}

///|
test "f64 8 params - get param 4" {
  let source =
    #|(module
    #|  (func (export "get_p4") (param f64) (param f64) (param f64) (param f64) (param f64) (param f64) (param f64) (param f64) (result f64)
    #|    (local.get 4))
    #|)
  let result = compare_jit_interp(source, "get_p4", [
    F64(1.0),
    F64(2.0),
    F64(3.0),
    F64(4.0),
    F64(5.0),
    F64(6.0),
    F64(7.0),
    F64(8.0),
  ])
  inspect(result, content="matched")
}

///|
test "f64 8 params - get param 7" {
  let source =
    #|(module
    #|  (func (export "get_p7") (param f64) (param f64) (param f64) (param f64) (param f64) (param f64) (param f64) (param f64) (result f64)
    #|    (local.get 7))
    #|)
  let result = compare_jit_interp(source, "get_p7", [
    F64(1.0),
    F64(2.0),
    F64(3.0),
    F64(4.0),
    F64(5.0),
    F64(6.0),
    F64(7.0),
    F64(8.0),
  ])
  inspect(result, content="matched")
}

///|
// Test for f32.nonarithmetic_nan_bitpattern - fneg should flip sign bit without changing payload
test "f32 nonarithmetic nan bitpattern" {
  let source =
    #|(module
    #|  (func (export "f32.nonarithmetic_nan_bitpattern") (param i32) (result i32)
    #|    (i32.reinterpret_f32 (f32.neg (f32.reinterpret_i32 (local.get 0)))))
    #|)
  // 0x7f803210 is a signaling NaN, negation should give 0xff803210
  let result = compare_jit_interp(source, "f32.nonarithmetic_nan_bitpattern", [
    I32(0x7f803210),
  ])
  inspect(result, content="matched")
}

///|
// Test for dot_product_example with 8 f64 parameters
test "dot product example" {
  let source =
    #|(module
    #|  (func (export "dot_product_example")
    #|        (param f64) (param f64) (param f64) (param f64)
    #|        (param f64) (param f64) (param f64) (param f64)
    #|        (result f64)
    #|    (f64.add (f64.add (f64.add
    #|      (f64.mul (local.get 0) (local.get 4))
    #|      (f64.mul (local.get 1) (local.get 5)))
    #|      (f64.mul (local.get 2) (local.get 6)))
    #|      (f64.mul (local.get 3) (local.get 7)))
    #|  )
    #|)
  let result = compare_jit_interp(source, "dot_product_example", [
    F64(3.2e7),
    F64(1.0),
    F64(-1.0),
    F64(8.0e7),
    F64(4.0e7),
    F64(1.0),
    F64(-1.0),
    F64(-1.6e7),
  ])
  inspect(result, content="matched")
}

///|
// Test for >8 parameters - args 8+ go on stack
test "i64 9 params - get param 8 (stack arg)" {
  let source =
    #|(module
    #|  (func (export "get_p8")
    #|        (param i64) (param i64) (param i64) (param i64)
    #|        (param i64) (param i64) (param i64) (param i64)
    #|        (param i64)
    #|        (result i64)
    #|    (local.get 8))
    #|)
  let result = compare_jit_interp(source, "get_p8", [
    I64(1L),
    I64(2L),
    I64(3L),
    I64(4L),
    I64(5L),
    I64(6L),
    I64(7L),
    I64(8L),
    I64(9L),
  ])
  inspect(result, content="matched")
}

///|
test "i64 10 params - sum all" {
  let source =
    #|(module
    #|  (func (export "sum10")
    #|        (param i64) (param i64) (param i64) (param i64)
    #|        (param i64) (param i64) (param i64) (param i64)
    #|        (param i64) (param i64)
    #|        (result i64)
    #|    (i64.add
    #|      (i64.add
    #|        (i64.add
    #|          (i64.add
    #|            (i64.add
    #|              (i64.add
    #|                (i64.add
    #|                  (i64.add
    #|                    (i64.add
    #|                      (local.get 0)
    #|                      (local.get 1))
    #|                    (local.get 2))
    #|                  (local.get 3))
    #|                (local.get 4))
    #|              (local.get 5))
    #|            (local.get 6))
    #|          (local.get 7))
    #|        (local.get 8))
    #|      (local.get 9)))
    #|)
  // 1+2+3+4+5+6+7+8+9+10 = 55
  let result = compare_jit_interp(source, "sum10", [
    I64(1L),
    I64(2L),
    I64(3L),
    I64(4L),
    I64(5L),
    I64(6L),
    I64(7L),
    I64(8L),
    I64(9L),
    I64(10L),
  ])
  inspect(result, content="matched")
}

///|
test "f64 9 params - get param 8 (stack arg)" {
  let source =
    #|(module
    #|  (func (export "get_p8")
    #|        (param f64) (param f64) (param f64) (param f64)
    #|        (param f64) (param f64) (param f64) (param f64)
    #|        (param f64)
    #|        (result f64)
    #|    (local.get 8))
    #|)
  let result = compare_jit_interp(source, "get_p8", [
    F64(1.0),
    F64(2.0),
    F64(3.0),
    F64(4.0),
    F64(5.0),
    F64(6.0),
    F64(7.0),
    F64(8.0),
    F64(9.0),
  ])
  inspect(result, content="matched")
}

///|
test "i64 16 params - sum all" {
  let source =
    #|(module
    #|  (func (export "sum16")
    #|        (param i64) (param i64) (param i64) (param i64)
    #|        (param i64) (param i64) (param i64) (param i64)
    #|        (param i64) (param i64) (param i64) (param i64)
    #|        (param i64) (param i64) (param i64) (param i64)
    #|        (result i64)
    #|    (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add
    #|      (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add
    #|        (i64.add (local.get 0) (local.get 1))
    #|        (local.get 2)) (local.get 3)) (local.get 4)) (local.get 5))
    #|        (local.get 6)) (local.get 7)) (local.get 8)) (local.get 9))
    #|        (local.get 10)) (local.get 11)) (local.get 12)) (local.get 13))
    #|        (local.get 14)) (local.get 15)))
    #|)
  // 1+2+3+...+16 = 136
  let result = compare_jit_interp(source, "sum16", [
    I64(1L),
    I64(2L),
    I64(3L),
    I64(4L),
    I64(5L),
    I64(6L),
    I64(7L),
    I64(8L),
    I64(9L),
    I64(10L),
    I64(11L),
    I64(12L),
    I64(13L),
    I64(14L),
    I64(15L),
    I64(16L),
  ])
  inspect(result, content="matched")
}
