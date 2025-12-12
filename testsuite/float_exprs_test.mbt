///|
/// Tests for float_exprs.wast - floating point expression edge cases

///|
/// Test f32.no_fma - should not use fused multiply-add
/// Line 26-30: precision test for f32 mul+add
test "f32_no_fma" {
  let source =
    #|(module
    #|  (func (export "f32.no_fma") (param $x f32) (param $y f32) (param $z f32) (result f32)
    #|    (f32.add (f32.mul (local.get $x) (local.get $y)) (local.get $z)))
    #|)
  let result = compare_jit_interp(source, "f32.no_fma", [
    F32(0x1.a78402p+124),
    F32(0x1.cf8548p-23),
    F32(0x1.992adap+107),
  ])
  // Debug: print jit and interp results
  inspect(result, content="matched")
  // S register f32 operations now implemented
  inspect(result, content="matched")
}

///|
/// Test no_reassociate_mul - f32 multiplication chain
/// Line 360-364: f32.no_reassociate_mul
test "f32_no_reassociate_mul" {
  let source =
    #|(module
    #|  (func (export "f32.no_reassociate_mul") (param $x f32) (param $y f32) (param $z f32) (param $w f32) (result f32)
    #|    (f32.mul (f32.mul (f32.mul (local.get $x) (local.get $y)) (local.get $z)) (local.get $w)))
    #|)
  // Using first test case from line 360
  let result = compare_jit_interp(source, "f32.no_reassociate_mul", [
    F32(0x1.950ba8p-116),
    F32(0x1.efdacep-33),
    F32(-0x1.5f9bcp+102),
    F32(0x1.f04508p-56),
  ])
  // S register f32 operations now implemented
  inspect(result, content="matched")
}

///|
/// Test i32.no_fold_f32_s - trunc_s then convert_s should preserve value
/// Line 505-507: returns 0 instead of expected I32
test "i32_no_fold_f32_s" {
  let source =
    #|(module
    #|  (func (export "i32.no_fold_f32_s") (param $x i32) (result i32)
    #|    (i32.trunc_f32_s (f32.convert_i32_s (local.get $x))))
    #|)
  let result = compare_jit_interp(source, "i32.no_fold_f32_s", [I32(16777216)])
  inspect(result, content="matched")
}

///|
/// Test i32.no_fold_f32_u - trunc_u then convert_s
/// Line 509-511: returns 0 instead of expected I32
test "i32_no_fold_f32_u" {
  let source =
    #|(module
    #|  (func (export "i32.no_fold_f32_u") (param $x i32) (result i32)
    #|    (i32.trunc_f32_u (f32.convert_i32_s (local.get $x))))
    #|)
  let result = compare_jit_interp(source, "i32.no_fold_f32_u", [I32(16777216)])
  inspect(result, content="matched")
}

///|
/// Test i64.no_fold_f64_s - trunc_s then convert_s for i64
/// Line 513-515: returns 0 instead of expected I64
test "i64_no_fold_f64_s" {
  let source =
    #|(module
    #|  (func (export "i64.no_fold_f64_s") (param $x i64) (result i64)
    #|    (i64.trunc_f64_s (f64.convert_i64_s (local.get $x))))
    #|)
  let result = compare_jit_interp(source, "i64.no_fold_f64_s", [
    I64(9007199254740992L),
  ])
  inspect(result, content="matched")
}

///|
/// Test f32.i32.no_fold_trunc_s_convert_s - returns NaN instead of expected
/// Line 777-778: trunc then convert returns NaN
test "f32_i32_no_fold_trunc_s_convert_s" {
  let source =
    #|(module
    #|  (func (export "f32.i32.no_fold_trunc_s_convert_s") (param $x f32) (result f32)
    #|    (f32.convert_i32_s (i32.trunc_f32_s (local.get $x))))
    #|)
  let result = compare_jit_interp(source, "f32.i32.no_fold_trunc_s_convert_s", [
    F32(1.5),
  ])
  inspect(result, content="matched")
}

///|
/// Test f64.i32.no_fold_trunc_s_convert_s - returns NaN instead of expected
/// Line 786-787: trunc then convert returns NaN
test "f64_i32_no_fold_trunc_s_convert_s" {
  let source =
    #|(module
    #|  (func (export "f64.i32.no_fold_trunc_s_convert_s") (param $x f64) (result f64)
    #|    (f64.convert_i32_s (i32.trunc_f64_s (local.get $x))))
    #|)
  let result = compare_jit_interp(source, "f64.i32.no_fold_trunc_s_convert_s", [
    F64(1.5),
  ])
  inspect(result, content="matched")
}

///|
/// Test no_fold_demote_promote - demote then promote should not be identity
/// Line 624-628: precision differences
test "no_fold_demote_promote" {
  let source =
    #|(module
    #|  (func (export "no_fold_demote_promote") (param $x f64) (result f64)
    #|    (f64.promote_f32 (f32.demote_f64 (local.get $x))))
    #|)
  let result = compare_jit_interp(source, "no_fold_demote_promote", [
    F64(-1.7176275796615013e-40),
  ])
  inspect(result, content="matched")
}
