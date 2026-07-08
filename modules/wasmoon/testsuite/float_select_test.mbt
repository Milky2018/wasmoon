///|
/// Test for float select with NaN
///
/// WebAssembly select semantics: select(val1, val2, cond)
/// If cond != 0, return val1, else return val2
///
/// Bug fixed: emit_cmp_imm had incorrect Rn encoding, causing
/// wrong flag settings for select condition check.
test "f64 select with cond=0 should return false_val" {
  let source =
    #|(module
    #|  (func (export "test") (result f64)
    #|    (select (f64.const 1.0) (f64.const 2.0) (i32.const 0)))
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "f64 select with cond=1 should return true_val" {
  let source =
    #|(module
    #|  (func (export "test") (result f64)
    #|    (select (f64.const 1.0) (f64.const 2.0) (i32.const 1)))
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "f64.no_fold_lt_select with NaN - should return NaN (false_val)" {
  let source =
    #|(module
    #|  (func (export "test") (param f64 f64) (result f64)
    #|    (select (local.get 0) (local.get 1) (f64.lt (local.get 0) (local.get 1))))
    #|)
  // 0.0 < nan = false, so select returns false_val (nan)
  let result = compare_jit_interp(source, "test", [
    F64(0.0),
    F64(@double.not_a_number),
  ])
  inspect(result, content="matched")
}

///|
test "f64.no_fold_lt_select with NaN reversed - should return 0 (false_val)" {
  let source =
    #|(module
    #|  (func (export "test") (param f64 f64) (result f64)
    #|    (select (local.get 0) (local.get 1) (f64.lt (local.get 0) (local.get 1))))
    #|)
  // nan < 0.0 = false, so select returns false_val (0.0)
  let result = compare_jit_interp(source, "test", [
    F64(@double.not_a_number),
    F64(0.0),
  ])
  inspect(result, content="matched")
}

///|
test "i32 select with cond=0 should return false_val" {
  let source =
    #|(module
    #|  (func (export "test") (result i32)
    #|    (select (i32.const 1) (i32.const 2) (i32.const 0)))
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "i32 select with cond=1 should return true_val" {
  let source =
    #|(module
    #|  (func (export "test") (result i32)
    #|    (select (i32.const 1) (i32.const 2) (i32.const 1)))
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "f32 select with NaN" {
  let source =
    #|(module
    #|  (func (export "test") (param f32 f32) (result f32)
    #|    (select (local.get 0) (local.get 1) (f32.lt (local.get 0) (local.get 1))))
    #|)
  // 0.0 < nan = false, so select returns false_val (nan)
  let result = compare_jit_interp(source, "test", [
    F32(0.0),
    F32(@float.not_a_number),
  ])
  inspect(result, content="matched")
}
