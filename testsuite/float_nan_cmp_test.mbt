///|
/// Test for f32/f64 comparison with NaN
///
/// WebAssembly spec: Any comparison involving NaN returns false (0)
/// This is the "ordered" comparison semantics.
///
/// Bug: Our JIT uses signed condition codes (LT, LE, GT, GE) which don't
/// handle NaN correctly. When NaN is involved, AArch64 sets NZCV=0011:
///   - LT (N!=V): 0!=1 = true (wrong! should be 0)
///   - LE (Z=1|N!=V): N!=V is true (wrong! should be 0)
///   - GT (Z=0&N=V): 0&0 = false (correct)
///   - GE (N=V): 0=1 = false (correct)
///
/// Solution: Use MI for lt, LS for le (these check C and Z flags properly
/// for floating-point ordered comparisons)
test "f32.le with NaN - should return 0" {
  let source =
    #|(module
    #|  (func (export "f32.le") (param f32 f32) (result i32)
    #|    (f32.le (local.get 0) (local.get 1))
    #|  )
    #|)
  // f32.le(2.0, nan) should return 0
  let result = compare_jit_interp(source, "f32.le", [
    F32(2.0),
    F32(@float.not_a_number),
  ])
  inspect(result, content="matched")
}

///|
test "f32.lt with NaN - should return 0" {
  let source =
    #|(module
    #|  (func (export "f32.lt") (param f32 f32) (result i32)
    #|    (f32.lt (local.get 0) (local.get 1))
    #|  )
    #|)
  let result = compare_jit_interp(source, "f32.lt", [
    F32(2.0),
    F32(@float.not_a_number),
  ])
  inspect(result, content="matched")
}

///|
test "f32.gt with NaN - should return 0" {
  let source =
    #|(module
    #|  (func (export "f32.gt") (param f32 f32) (result i32)
    #|    (f32.gt (local.get 0) (local.get 1))
    #|  )
    #|)
  let result = compare_jit_interp(source, "f32.gt", [
    F32(2.0),
    F32(@float.not_a_number),
  ])
  inspect(result, content="matched")
}

///|
test "f32.ge with NaN - should return 0" {
  let source =
    #|(module
    #|  (func (export "f32.ge") (param f32 f32) (result i32)
    #|    (f32.ge (local.get 0) (local.get 1))
    #|  )
    #|)
  let result = compare_jit_interp(source, "f32.ge", [
    F32(2.0),
    F32(@float.not_a_number),
  ])
  inspect(result, content="matched")
}

///|
test "f64.le with NaN - should return 0" {
  let source =
    #|(module
    #|  (func (export "f64.le") (param f64 f64) (result i32)
    #|    (f64.le (local.get 0) (local.get 1))
    #|  )
    #|)
  let result = compare_jit_interp(source, "f64.le", [
    F64(2.0),
    F64(@double.not_a_number),
  ])
  inspect(result, content="matched")
}

///|
test "f64.lt with NaN - should return 0" {
  let source =
    #|(module
    #|  (func (export "f64.lt") (param f64 f64) (result i32)
    #|    (f64.lt (local.get 0) (local.get 1))
    #|  )
    #|)
  let result = compare_jit_interp(source, "f64.lt", [
    F64(2.0),
    F64(@double.not_a_number),
  ])
  inspect(result, content="matched")
}

///|
test "f64.gt with NaN - should return 0" {
  let source =
    #|(module
    #|  (func (export "f64.gt") (param f64 f64) (result i32)
    #|    (f64.gt (local.get 0) (local.get 1))
    #|  )
    #|)
  let result = compare_jit_interp(source, "f64.gt", [
    F64(2.0),
    F64(@double.not_a_number),
  ])
  inspect(result, content="matched")
}

///|
test "f64.ge with NaN - should return 0" {
  let source =
    #|(module
    #|  (func (export "f64.ge") (param f64 f64) (result i32)
    #|    (f64.ge (local.get 0) (local.get 1))
    #|  )
    #|)
  let result = compare_jit_interp(source, "f64.ge", [
    F64(2.0),
    F64(@double.not_a_number),
  ])
  inspect(result, content="matched")
}

///|
/// Test f32.ugt pattern from float_exprs.wast:
/// f32.ugt(x, y) = i32.eqz(f32.le(x, y))
/// When y is NaN, f32.le should return 0, so eqz(0) = 1
test "f32.ugt (unordered greater than)" {
  let source =
    #|(module
    #|  (func (export "f32.ugt") (param f32 f32) (result i32)
    #|    (i32.eqz (f32.le (local.get 0) (local.get 1)))
    #|  )
    #|)
  // f32.ugt(2.0, nan) = eqz(le(2.0, nan)) = eqz(0) = 1
  let result = compare_jit_interp(source, "f32.ugt", [
    F32(2.0),
    F32(@float.not_a_number),
  ])
  inspect(result, content="matched")
}

///|
/// Normal comparison tests (no NaN) - should still work
test "f32.le normal comparison" {
  let source =
    #|(module
    #|  (func (export "f32.le") (param f32 f32) (result i32)
    #|    (f32.le (local.get 0) (local.get 1))
    #|  )
    #|)
  // 2.0 <= 3.0 should be 1
  let result1 = compare_jit_interp(source, "f32.le", [F32(2.0), F32(3.0)])
  inspect(result1, content="matched")
  // 3.0 <= 2.0 should be 0
  let result2 = compare_jit_interp(source, "f32.le", [F32(3.0), F32(2.0)])
  inspect(result2, content="matched")
  // 2.0 <= 2.0 should be 1
  let result3 = compare_jit_interp(source, "f32.le", [F32(2.0), F32(2.0)])
  inspect(result3, content="matched")
}
