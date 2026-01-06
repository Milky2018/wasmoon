///|
/// Table Bulk Operations Tests
/// Tests for table.fill, table.copy, table.init, elem.drop
/// These tests run through the interpreter to verify correctness.

///|
test "table.init: basic initialization from element segment" {
  let source =
    #|(module
    #|  (table 3 funcref)
    #|  (elem funcref (ref.func $zero) (ref.func $one))
    #|
    #|  (func $zero (result i32) (i32.const 0))
    #|  (func $one (result i32) (i32.const 1))
    #|
    #|  (func (export "test") (result i32)
    #|    ;; Initialize table[0..2] from elem[0..2]
    #|    (table.init 0
    #|      (i32.const 0)   ;; dst in table
    #|      (i32.const 0)   ;; src in elem segment
    #|      (i32.const 2))  ;; size
    #|    ;; Call first function
    #|    (call_indirect (result i32) (i32.const 0))
    #|  )
    #|)
  let result = run_interp_only(source, "test", [])
  inspect(result, content="Ok([I32(0)])")
}

///|
test "table.init: verify second function" {
  let source =
    #|(module
    #|  (table 3 funcref)
    #|  (elem funcref (ref.func $zero) (ref.func $one))
    #|
    #|  (func $zero (result i32) (i32.const 0))
    #|  (func $one (result i32) (i32.const 1))
    #|
    #|  (func (export "test") (result i32)
    #|    (table.init 0
    #|      (i32.const 0)
    #|      (i32.const 0)
    #|      (i32.const 2))
    #|    ;; Call second function
    #|    (call_indirect (result i32) (i32.const 1))
    #|  )
    #|)
  let result = run_interp_only(source, "test", [])
  inspect(result, content="Ok([I32(1)])")
}

///|
test "table.copy: non-overlapping copy" {
  let source =
    #|(module
    #|  (table 10 funcref)
    #|  (elem (i32.const 0) $zero $one $two)
    #|  (func $zero (result i32) (i32.const 0))
    #|  (func $one (result i32) (i32.const 1))
    #|  (func $two (result i32) (i32.const 2))
    #|
    #|  (func (export "test") (result i32)
    #|    ;; Copy table[0..3] to table[3..6]
    #|    (table.copy
    #|      (i32.const 3)   ;; dst
    #|      (i32.const 0)   ;; src
    #|      (i32.const 3))  ;; size
    #|    ;; Call function at table[3] (should be $zero)
    #|    (call_indirect (result i32) (i32.const 3))
    #|  )
    #|)
  let result = run_interp_only(source, "test", [])
  inspect(result, content="Ok([I32(0)])")
}

///|
test "table.copy: verify copied function" {
  let source =
    #|(module
    #|  (table 10 funcref)
    #|  (elem (i32.const 0) $zero $one $two)
    #|  (func $zero (result i32) (i32.const 0))
    #|  (func $one (result i32) (i32.const 1))
    #|  (func $two (result i32) (i32.const 2))
    #|
    #|  (func (export "test") (result i32)
    #|    (table.copy
    #|      (i32.const 3)
    #|      (i32.const 0)
    #|      (i32.const 3))
    #|    ;; Call function at table[5] (should be $two)
    #|    (call_indirect (result i32) (i32.const 5))
    #|  )
    #|)
  let result = run_interp_only(source, "test", [])
  inspect(result, content="Ok([I32(2)])")
}

///|
test "table.fill: fill with null" {
  let source =
    #|(module
    #|  (table 5 funcref)
    #|  (elem (i32.const 0) $f)
    #|  (func $f (result i32) (i32.const 42))
    #|
    #|  (func (export "test") (result i32)
    #|    ;; Fill table[1..4] with null
    #|    (table.fill
    #|      (i32.const 1)
    #|      (ref.null func)
    #|      (i32.const 3))
    #|    ;; Table[0] should still work
    #|    (call_indirect (result i32) (i32.const 0))
    #|  )
    #|)
  let result = run_interp_only(source, "test", [])
  inspect(result, content="Ok([I32(42)])")
}

///|
test "elem.drop: dropped segment init with zero length succeeds" {
  let source =
    #|(module
    #|  (table 1 funcref)
    #|  (func $f)
    #|  (elem $e funcref (ref.func $f))
    #|
    #|  (func (export "test") (result i32)
    #|    ;; Drop the elem segment
    #|    (elem.drop $e)
    #|    ;; Init with zero length should still succeed
    #|    (table.init $e
    #|      (i32.const 0)
    #|      (i32.const 0)
    #|      (i32.const 0))
    #|    (i32.const 1)  ;; Return success indicator
    #|  )
    #|)
  let result = run_interp_only(source, "test", [])
  inspect(result, content="Ok([I32(1)])")
}

///|
test "elem.drop: can drop multiple times" {
  let source =
    #|(module
    #|  (table 1 funcref)
    #|  (func $f)
    #|  (elem $e funcref (ref.func $f))
    #|
    #|  (func (export "test") (result i32)
    #|    (elem.drop $e)
    #|    (elem.drop $e)
    #|    (elem.drop $e)
    #|    (i32.const 42)
    #|  )
    #|)
  let result = run_interp_only(source, "test", [])
  inspect(result, content="Ok([I32(42)])")
}
