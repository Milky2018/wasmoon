///|
/// Regression tests for `call_indirect` with integer stack (overflow) arguments.
///
/// Wasm v3 ABI for JIT:
/// - User integer args use X2-X7 (6 regs). Remaining int args spill to stack.
///
/// These tests validate:
/// - Correct outgoing stack arg stores by the caller
/// - Correct stack arg loads by the callee
/// - Correct ordering with mixed i32/i64 parameters

///|
test "call_indirect: mixed i32/i64 overflow stack args" {
  let source =
    #|(module
    #|  ;; 8 integer args => 6 in regs + 2 on stack
    #|  (type $t (func (param i32 i64 i32 i64 i32 i32 i64 i32) (result i64)))
    #|
    #|  ;; Pack each argument into one byte of the i64 result:
    #|  ;; byte0=p0, byte1=p1, ..., byte7=p7
    #|  (func $pack (export "pack") (type $t)
    #|    (local.get 0) i64.extend_i32_u
    #|    (local.get 1) (i64.const 8)  i64.shl i64.or
    #|    (local.get 2) i64.extend_i32_u (i64.const 16) i64.shl i64.or
    #|    (local.get 3) (i64.const 24) i64.shl i64.or
    #|    (local.get 4) i64.extend_i32_u (i64.const 32) i64.shl i64.or
    #|    (local.get 5) i64.extend_i32_u (i64.const 40) i64.shl i64.or
    #|    (local.get 6) (i64.const 48) i64.shl i64.or
    #|    (local.get 7) i64.extend_i32_u (i64.const 56) i64.shl i64.or
    #|  )
    #|
    #|  (table funcref (elem $pack))
    #|
    #|  (func (export "test") (result i64)
    #|    ;; expect 0x8007060504030201
    #|    (call_indirect (type $t)
    #|      (i32.const 1)
    #|      (i64.const 2)
    #|      (i32.const 3)
    #|      (i64.const 4)
    #|      (i32.const 5)
    #|      (i32.const 6)
    #|      (i64.const 7)
    #|      (i32.const 128)
    #|      (i32.const 0)
    #|    )
    #|  )
    #|)
  inspect(compare_jit_interp(source, "test", []), content="matched")
  inspect(
    compare_jit_interp(source, "pack", [
      I32(1),
      I64(2),
      I32(3),
      I64(4),
      I32(5),
      I32(6),
      I64(7),
      I32(128),
    ]),
    content="matched",
  )
}
