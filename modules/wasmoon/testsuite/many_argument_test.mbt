///|
// Test for many function parameters with indirect call
// This tests that stack parameters work correctly when passed through multiple function calls

///|
test "i64 64 params - indirect call via test function" {
  let source =
    #|(module
    #|  ;; Inner function that takes 64 i64 parameters and sums them
    #|  (func $sum64
    #|        (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64)
    #|        (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64)
    #|        (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64)
    #|        (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64)
    #|        (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64)
    #|        (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64)
    #|        (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64)
    #|        (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64) (param i64)
    #|        (result i64)
    #|    (local $sum i64)
    #|    (local.set $sum (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add
    #|      (local.get 0) (local.get 1)) (local.get 2)) (local.get 3)) (local.get 4)) (local.get 5)) (local.get 6)) (local.get 7)))
    #|    (local.set $sum (i64.add (local.get $sum) (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add
    #|      (local.get 8) (local.get 9)) (local.get 10)) (local.get 11)) (local.get 12)) (local.get 13)) (local.get 14)) (local.get 15))))
    #|    (local.set $sum (i64.add (local.get $sum) (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add
    #|      (local.get 16) (local.get 17)) (local.get 18)) (local.get 19)) (local.get 20)) (local.get 21)) (local.get 22)) (local.get 23))))
    #|    (local.set $sum (i64.add (local.get $sum) (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add
    #|      (local.get 24) (local.get 25)) (local.get 26)) (local.get 27)) (local.get 28)) (local.get 29)) (local.get 30)) (local.get 31))))
    #|    (local.set $sum (i64.add (local.get $sum) (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add
    #|      (local.get 32) (local.get 33)) (local.get 34)) (local.get 35)) (local.get 36)) (local.get 37)) (local.get 38)) (local.get 39))))
    #|    (local.set $sum (i64.add (local.get $sum) (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add
    #|      (local.get 40) (local.get 41)) (local.get 42)) (local.get 43)) (local.get 44)) (local.get 45)) (local.get 46)) (local.get 47))))
    #|    (local.set $sum (i64.add (local.get $sum) (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add
    #|      (local.get 48) (local.get 49)) (local.get 50)) (local.get 51)) (local.get 52)) (local.get 53)) (local.get 54)) (local.get 55))))
    #|    (local.set $sum (i64.add (local.get $sum) (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add (i64.add
    #|      (local.get 56) (local.get 57)) (local.get 58)) (local.get 59)) (local.get 60)) (local.get 61)) (local.get 62)) (local.get 63))))
    #|    (local.get $sum))
    #|
    #|  ;; Test function that calls sum64 with constants 1-64
    #|  ;; Expected result: 1+2+...+64 = 64*65/2 = 2080
    #|  (func (export "test") (result i64)
    #|    (call $sum64
    #|      (i64.const 1) (i64.const 2) (i64.const 3) (i64.const 4)
    #|      (i64.const 5) (i64.const 6) (i64.const 7) (i64.const 8)
    #|      (i64.const 9) (i64.const 10) (i64.const 11) (i64.const 12)
    #|      (i64.const 13) (i64.const 14) (i64.const 15) (i64.const 16)
    #|      (i64.const 17) (i64.const 18) (i64.const 19) (i64.const 20)
    #|      (i64.const 21) (i64.const 22) (i64.const 23) (i64.const 24)
    #|      (i64.const 25) (i64.const 26) (i64.const 27) (i64.const 28)
    #|      (i64.const 29) (i64.const 30) (i64.const 31) (i64.const 32)
    #|      (i64.const 33) (i64.const 34) (i64.const 35) (i64.const 36)
    #|      (i64.const 37) (i64.const 38) (i64.const 39) (i64.const 40)
    #|      (i64.const 41) (i64.const 42) (i64.const 43) (i64.const 44)
    #|      (i64.const 45) (i64.const 46) (i64.const 47) (i64.const 48)
    #|      (i64.const 49) (i64.const 50) (i64.const 51) (i64.const 52)
    #|      (i64.const 53) (i64.const 54) (i64.const 55) (i64.const 56)
    #|      (i64.const 57) (i64.const 58) (i64.const 59) (i64.const 60)
    #|      (i64.const 61) (i64.const 62) (i64.const 63) (i64.const 64)))
    #|)
  // Call "test" function with no arguments - it internally calls sum64 with 64 args
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
// Test with parameters passed through - the test function receives params and forwards them
test "i64 16 params - forward through test function" {
  let source =
    #|(module
    #|  ;; Inner function that takes 16 i64 parameters and sums them
    #|  (func $sum16
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
    #|
    #|  ;; Test function that receives 16 params and forwards them to sum16
    #|  (func (export "test")
    #|        (param i64) (param i64) (param i64) (param i64)
    #|        (param i64) (param i64) (param i64) (param i64)
    #|        (param i64) (param i64) (param i64) (param i64)
    #|        (param i64) (param i64) (param i64) (param i64)
    #|        (result i64)
    #|    (call $sum16
    #|      (local.get 0) (local.get 1) (local.get 2) (local.get 3)
    #|      (local.get 4) (local.get 5) (local.get 6) (local.get 7)
    #|      (local.get 8) (local.get 9) (local.get 10) (local.get 11)
    #|      (local.get 12) (local.get 13) (local.get 14) (local.get 15)))
    #|)
  // 1+2+...+16 = 136
  let result = compare_jit_interp(source, "test", [
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

///|
// Test with mixed types - f64 params passed through
test "f64 10 params - forward through test function" {
  let source =
    #|(module
    #|  ;; Inner function that takes 10 f64 parameters and sums them
    #|  (func $sum10
    #|        (param f64) (param f64) (param f64) (param f64) (param f64)
    #|        (param f64) (param f64) (param f64) (param f64) (param f64)
    #|        (result f64)
    #|    (f64.add (f64.add (f64.add (f64.add (f64.add (f64.add (f64.add (f64.add (f64.add
    #|      (local.get 0) (local.get 1)) (local.get 2)) (local.get 3)) (local.get 4))
    #|      (local.get 5)) (local.get 6)) (local.get 7)) (local.get 8)) (local.get 9)))
    #|
    #|  ;; Test function that receives 10 f64 params and forwards them
    #|  (func (export "test")
    #|        (param f64) (param f64) (param f64) (param f64) (param f64)
    #|        (param f64) (param f64) (param f64) (param f64) (param f64)
    #|        (result f64)
    #|    (call $sum10
    #|      (local.get 0) (local.get 1) (local.get 2) (local.get 3) (local.get 4)
    #|      (local.get 5) (local.get 6) (local.get 7) (local.get 8) (local.get 9)))
    #|)
  // 1.0+2.0+...+10.0 = 55.0
  let result = compare_jit_interp(source, "test", [
    F64(1.0),
    F64(2.0),
    F64(3.0),
    F64(4.0),
    F64(5.0),
    F64(6.0),
    F64(7.0),
    F64(8.0),
    F64(9.0),
    F64(10.0),
  ])
  inspect(result, content="matched")
}
