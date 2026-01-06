///|
/// Bulk Memory Operations Tests
/// Tests for memory.init, data.drop, memory.copy, memory.fill
/// These tests run through the interpreter to verify correctness.

///|
test "memory.init: basic copy from data segment" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (data "\aa\bb\cc\dd")
    #|
    #|  (func (export "test") (result i32)
    #|    ;; Initialize memory[0..2] from data[1..3] (bytes 0xbb, 0xcc)
    #|    (memory.init 0
    #|      (i32.const 0)   ;; dst in memory
    #|      (i32.const 1)   ;; src in data segment
    #|      (i32.const 2))  ;; size
    #|    ;; Return first byte copied
    #|    (i32.load8_u (i32.const 0))
    #|  )
    #|)
  let result = run_interp_only(source, "test", [])
  inspect(result, content="Ok([I32(187)])") // 0xbb = 187
}

///|
test "memory.init: verify second byte" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (data "\aa\bb\cc\dd")
    #|
    #|  (func (export "test") (result i32)
    #|    (memory.init 0
    #|      (i32.const 0)
    #|      (i32.const 1)
    #|      (i32.const 2))
    #|    (i32.load8_u (i32.const 1))
    #|  )
    #|)
  let result = run_interp_only(source, "test", [])
  inspect(result, content="Ok([I32(204)])") // 0xcc = 204
}

///|
test "memory.init: zero length is valid" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (data "\aa\bb\cc\dd")
    #|
    #|  (func (export "test") (result i32)
    #|    ;; First, write something to memory[100]
    #|    (i32.store8 (i32.const 100) (i32.const 42))
    #|    ;; Zero-length init should succeed and not change memory
    #|    (memory.init 0
    #|      (i32.const 100)
    #|      (i32.const 0)
    #|      (i32.const 0))
    #|    ;; Memory at 100 should still be 42
    #|    (i32.load8_u (i32.const 100))
    #|  )
    #|)
  let result = run_interp_only(source, "test", [])
  inspect(result, content="Ok([I32(42)])")
}

///|
test "data.drop: dropped segment init with zero length succeeds" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (data $d "x")
    #|
    #|  (func (export "test") (result i32)
    #|    ;; Drop the data segment
    #|    (data.drop $d)
    #|    ;; Init with zero length should still succeed
    #|    (memory.init $d
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
test "data.drop: can drop multiple times" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (data $d "hello")
    #|
    #|  (func (export "test") (result i32)
    #|    (data.drop $d)
    #|    (data.drop $d)
    #|    (data.drop $d)
    #|    (i32.const 42)
    #|  )
    #|)
  let result = run_interp_only(source, "test", [])
  inspect(result, content="Ok([I32(42)])")
}

// ============ JIT Comparison Tests ============

///|
test "JIT: memory.init basic copy" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (data "\aa\bb\cc\dd")
    #|
    #|  (func (export "test") (result i32)
    #|    (memory.init 0
    #|      (i32.const 0)
    #|      (i32.const 1)
    #|      (i32.const 2))
    #|    (i32.load8_u (i32.const 0))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "JIT: memory.init second byte" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (data "\aa\bb\cc\dd")
    #|
    #|  (func (export "test") (result i32)
    #|    (memory.init 0
    #|      (i32.const 0)
    #|      (i32.const 1)
    #|      (i32.const 2))
    #|    (i32.load8_u (i32.const 1))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "JIT: data.drop and init with zero length" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (data $d "x")
    #|
    #|  (func (export "test") (result i32)
    #|    (data.drop $d)
    #|    (memory.init $d
    #|      (i32.const 0)
    #|      (i32.const 0)
    #|      (i32.const 0))
    #|    (i32.const 1)
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}
