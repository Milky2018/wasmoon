///|
/// Regression tests for AArch64 shifted-operand instruction selection on i32.
///
/// The lowering currently matches patterns like:
///   i32.add(x, i32.shl(y, const)) -> AddShifted(..., const)
/// and emits AArch64 "shifted register" forms.
///
/// For i32, the shift amount is masked by WebAssembly semantics (amount & 31).
/// If the pattern uses the constant directly (e.g. 32), the JIT can miscompile.
/// Additionally, using 64-bit forms can leave non-zero upper 32 bits, which can
/// break i32-as-boolean conditions when the JIT uses 64-bit CBZ/CBNZ.

///|
test "JIT: i32.add + i32.shl with shift=32 (must mask to 0)" {
  let source =
    #|(module
    #|  (func (export "test") (result i32)
    #|    ;; (1 << (32 & 31)) == 1
    #|    (i32.add (i32.const 10) (i32.shl (i32.const 1) (i32.const 32)))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "JIT: i32.and + i32.shl with shift=32 (must mask to 0)" {
  let source =
    #|(module
    #|  (func (export "test") (result i32)
    #|    ;; (1 << (32 & 31)) == 1; (0xFF & 1) == 1
    #|    (i32.and (i32.const 255) (i32.shl (i32.const 1) (i32.const 32)))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "JIT: i32 boolean via br_if must use low 32 bits" {
  let source =
    #|(module
    #|  (func (export "test") (result i32)
    #|    (block (result i32)
    #|      (i32.const 1)
    #|      ;; 0x80000000 + (1 << 31) wraps to 0 in i32.
    #|      ;; If the JIT computes it in 64-bit and tests the full 64-bit value,
    #|      ;; it may branch incorrectly (upper bits non-zero).
    #|      (br_if 0 (i32.add (i32.const 0x80000000) (i32.shl (i32.const 1) (i32.const 31))))
    #|      (drop)
    #|      (i32.const 42)
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}
