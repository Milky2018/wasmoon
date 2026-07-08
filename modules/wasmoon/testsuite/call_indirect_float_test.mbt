///|
/// Tests for call_indirect with float parameters
/// These test cases expose a bug where float parameters assigned to callee-saved
/// FPRs (D8-D15) are not properly saved/restored across nested calls.

///|
test "call_indirect fac-f32 with recursion" {
  // This test fails because the float parameter (in D8) is not saved
  // across the recursive call, causing it to be overwritten.
  let source =
    #|(module
    #|  (type $over-f32 (func (param f32) (result f32)))
    #|
    #|  (func $fac-f32 (export "fac-f32") (type $over-f32)
    #|    (if (result f32) (f32.eq (local.get 0) (f32.const 0.0))
    #|      (then (f32.const 1.0))
    #|      (else
    #|        (f32.mul
    #|          (local.get 0)
    #|          (call_indirect (type $over-f32)
    #|            (f32.sub (local.get 0) (f32.const 1.0))
    #|            (i32.const 0)
    #|          )
    #|        )
    #|      )
    #|    )
    #|  )
    #|
    #|  (table funcref (elem $fac-f32))
    #|)
  // fac-f32(0.0) = 1.0 (base case, no recursion)
  let result0 = compare_jit_interp(source, "fac-f32", [F32(0.0)])
  inspect(result0, content="matched")
  // fac-f32(1.0) = 1.0 * fac-f32(0.0) = 1.0 * 1.0 = 1.0
  // This fails: returns 0.0 instead of 1.0
  // The bug: D8 (holding 1.0) is overwritten by recursive call
  let result1 = compare_jit_interp(source, "fac-f32", [F32(1.0)])
  inspect(result1, content="matched")
  // fac-f32(5.0) = 5.0 * 4.0 * 3.0 * 2.0 * 1.0 * 1.0 = 120.0
  let result5 = compare_jit_interp(source, "fac-f32", [F32(5.0)])
  inspect(result5, content="matched")
}

///|
test "call_indirect fac-f64 with recursion" {
  // Same issue with f64 parameters
  let source =
    #|(module
    #|  (type $over-f64 (func (param f64) (result f64)))
    #|
    #|  (func $fac-f64 (export "fac-f64") (type $over-f64)
    #|    (if (result f64) (f64.eq (local.get 0) (f64.const 0.0))
    #|      (then (f64.const 1.0))
    #|      (else
    #|        (f64.mul
    #|          (local.get 0)
    #|          (call_indirect (type $over-f64)
    #|            (f64.sub (local.get 0) (f64.const 1.0))
    #|            (i32.const 0)
    #|          )
    #|        )
    #|      )
    #|    )
    #|  )
    #|
    #|  (table funcref (elem $fac-f64))
    #|)
  let result0 = compare_jit_interp(source, "fac-f64", [F64(0.0)])
  inspect(result0, content="matched")
  let result1 = compare_jit_interp(source, "fac-f64", [F64(1.0)])
  inspect(result1, content="matched")
  let result5 = compare_jit_interp(source, "fac-f64", [F64(5.0)])
  inspect(result5, content="matched")
}

///|
test "direct call fac-f32 with recursion" {
  // Same bug happens with direct call, not just call_indirect
  let source =
    #|(module
    #|  (func $fac-f32 (export "fac-f32") (param f32) (result f32)
    #|    (if (result f32) (f32.eq (local.get 0) (f32.const 0.0))
    #|      (then (f32.const 1.0))
    #|      (else
    #|        (f32.mul
    #|          (local.get 0)
    #|          (call $fac-f32
    #|            (f32.sub (local.get 0) (f32.const 1.0))
    #|          )
    #|        )
    #|      )
    #|    )
    #|  )
    #|)
  let result0 = compare_jit_interp(source, "fac-f32", [F32(0.0)])
  inspect(result0, content="matched")
  let result1 = compare_jit_interp(source, "fac-f32", [F32(1.0)])
  inspect(result1, content="matched")
  let result5 = compare_jit_interp(source, "fac-f32", [F32(5.0)])
  inspect(result5, content="matched")
}
