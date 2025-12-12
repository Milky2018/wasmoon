///|
/// Stress tests for register allocation
/// These tests are designed to trigger spills and verify correct handling
/// of register aliasing (especially S/D register aliasing on AArch64)

///|
/// Test: Multiple f32/f64 returns with internal call
/// This was the original failing case - f32 and f64 spilled to same scratch register
test "regalloc: f32 f64 multi-return spill" {
  let source =
    #|  (module
    #|    (func $swap (param f32 f64) (result f64 f32)
    #|      (local.get 1) (local.get 0))
    #|    (func (export "test") (result f64 f32)
    #|      (call $swap (f32.const 1) (f64.const 2))))
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test: 3 float returns (exceeds 2-register return ABI)
test "regalloc: 3 float returns" {
  let source =
    #|  (module
    #|    (func (export "test") (result f32 f64 f32)
    #|      (f32.const 1) (f64.const 2) (f32.const 3)))
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test: 4 float returns with mixed types
test "regalloc: 4 mixed float returns" {
  let source =
    #|  (module
    #|    (func (export "test") (result f32 f64 f64 f32)
    #|      (f32.const 1) (f64.const 2) (f64.const 3) (f32.const 4)))
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test: Call that returns multiple values which are then returned
/// Forces spill of call results
test "regalloc: forwarding multi-value call results" {
  let source =
    #|  (module
    #|    (func $producer (result f64 f32 f64)
    #|      (f64.const 1) (f32.const 2) (f64.const 3))
    #|    (func (export "test") (result f64 f32 f64)
    #|      (call $producer)))
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test: Multiple calls with results that must be combined
/// Creates register pressure across call boundaries
test "regalloc: combining results from multiple calls" {
  let source =
    #|  (module
    #|    (func $get_f32 (result f32) (f32.const 1.5))
    #|    (func $get_f64 (result f64) (f64.const 2.5))
    #|    (func (export "test") (result f64 f32)
    #|      (call $get_f64)
    #|      (call $get_f32)))
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test: High register pressure with many locals
/// Forces spilling of intermediate values
test "regalloc: many float locals" {
  let source =
    #|  (module
    #|    (func (export "test") (result f64)
    #|      (local f64 f64 f64 f64 f64 f64 f64 f64 f64 f64)
    #|      (local.set 0 (f64.const 1))
    #|      (local.set 1 (f64.const 2))
    #|      (local.set 2 (f64.const 3))
    #|      (local.set 3 (f64.const 4))
    #|      (local.set 4 (f64.const 5))
    #|      (local.set 5 (f64.const 6))
    #|      (local.set 6 (f64.const 7))
    #|      (local.set 7 (f64.const 8))
    #|      (local.set 8 (f64.const 9))
    #|      (local.set 9 (f64.const 10))
    #|      (f64.add (local.get 0) (f64.add (local.get 1) (f64.add (local.get 2)
    #|        (f64.add (local.get 3) (f64.add (local.get 4) (f64.add (local.get 5)
    #|          (f64.add (local.get 6) (f64.add (local.get 7) (f64.add (local.get 8)
    #|            (local.get 9))))))))))))
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test: Mixed int and float locals with high pressure
test "regalloc: mixed int float pressure" {
  let source =
    #|  (module
    #|    (func (export "test") (param i32 f32 i64 f64) (result f64 i64 f32 i32)
    #|      (local.get 3) (local.get 2) (local.get 1) (local.get 0)))
  let result = compare_jit_interp(source, "test", [
    I32(1),
    F32(2.0),
    I64(3),
    F64(4.0),
  ])
  inspect(result, content="matched")
}

///|
/// Test: Call with many arguments (exceeds register args)
test "regalloc: many call arguments" {
  let source =
    #|  (module
    #|    (func $sum8 (param f64 f64 f64 f64 f64 f64 f64 f64) (result f64)
    #|      (f64.add (local.get 0) (f64.add (local.get 1) (f64.add (local.get 2)
    #|        (f64.add (local.get 3) (f64.add (local.get 4) (f64.add (local.get 5)
    #|          (f64.add (local.get 6) (local.get 7)))))))))
    #|    (func (export "test") (result f64)
    #|      (call $sum8
    #|        (f64.const 1) (f64.const 2) (f64.const 3) (f64.const 4)
    #|        (f64.const 5) (f64.const 6) (f64.const 7) (f64.const 8))))
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test: Nested calls with float values live across calls
test "regalloc: values live across nested calls" {
  let source =
    #|  (module
    #|    (func $id_f32 (param f32) (result f32) (local.get 0))
    #|    (func $id_f64 (param f64) (result f64) (local.get 0))
    #|    (func (export "test") (result f64 f32)
    #|      (call $id_f64 (f64.const 2.0))
    #|      (call $id_f32 (f32.const 1.0))))
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test: f32 value that survives across a call (must use callee-saved FPR)
test "regalloc: f32 live across call" {
  let source =
    #|  (module
    #|    (func $consume (param f64) (result f64) (local.get 0))
    #|    (func (export "test") (result f32)
    #|      (local f32)
    #|      (local.set 0 (f32.const 42.0))
    #|      (drop (call $consume (f64.const 3.14)))
    #|      (local.get 0)))
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test: Multiple spilled values used in arithmetic
test "regalloc: spilled values in expression" {
  let source =
    #|  (module
    #|    (func $get_vals (result f32 f64 f32 f64)
    #|      (f32.const 1) (f64.const 2) (f32.const 3) (f64.const 4))
    #|    (func (export "test") (result f64)
    #|      (local f32 f64 f32 f64)
    #|      (call $get_vals)
    #|      (local.set 3)
    #|      (local.set 2)
    #|      (local.set 1)
    #|      (local.set 0)
    #|      (f64.add
    #|        (f64.promote_f32 (local.get 0))
    #|        (f64.add (local.get 1)
    #|          (f64.add (f64.promote_f32 (local.get 2))
    #|            (local.get 3))))))
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}
