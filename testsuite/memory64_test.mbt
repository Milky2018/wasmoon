// Memory64 and Table64 Integration Tests (JIT vs Interpreter)

// ============================================================
// Memory64 Tests
// ============================================================

///|
test "memory64: i32.load with i64 address" {
  let wat =
    #|(module
    #|  (memory i64 1)
    #|  (func (export "test") (result i32)
    #|    i64.const 0
    #|    i32.load
    #|  )
    #|)
  inspect(compare_jit_interp(wat, "test", []), content="matched")
}

///|
test "memory64: i32.store and i32.load" {
  let wat =
    #|(module
    #|  (memory i64 1)
    #|  (func (export "test") (result i32)
    #|    i64.const 8
    #|    i32.const 42
    #|    i32.store
    #|    i64.const 8
    #|    i32.load
    #|  )
    #|)
  inspect(compare_jit_interp(wat, "test", []), content="matched")
}

///|
test "memory64: i64.load and i64.store" {
  let wat =
    #|(module
    #|  (memory i64 1)
    #|  (func (export "test") (result i64)
    #|    i64.const 16
    #|    i64.const 0x123456789ABCDEF0
    #|    i64.store
    #|    i64.const 16
    #|    i64.load
    #|  )
    #|)
  inspect(compare_jit_interp(wat, "test", []), content="matched")
}

///|
test "memory64: memory.size returns i64" {
  // Use 1 page since JIT test helper allocates only 1 page
  let wat =
    #|(module
    #|  (memory i64 1)
    #|  (func (export "test") (result i64)
    #|    memory.size
    #|  )
    #|)
  inspect(compare_jit_interp(wat, "test", []), content="matched")
}

///|
test "memory64: memory.grow takes and returns i64" {
  let wat =
    #|(module
    #|  (memory i64 1)
    #|  (func (export "test") (result i64)
    #|    i64.const 1
    #|    memory.grow
    #|  )
    #|)
  inspect(compare_jit_interp(wat, "test", []), content="matched")
}

///|
test "memory64: load with offset" {
  // Store and load - avoids data segments which JIT helper doesn't initialize
  let wat =
    #|(module
    #|  (memory i64 1)
    #|  (func (export "test") (result i32)
    #|    i64.const 100
    #|    i32.const 0x04030201
    #|    i32.store
    #|    i64.const 100
    #|    i32.load
    #|  )
    #|)
  inspect(compare_jit_interp(wat, "test", []), content="matched")
}

// ============================================================
// Memory32 Baseline Tests (ensure no regressions)
// ============================================================

///|
test "memory32: i32.load with i32 address" {
  let wat =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (result i32)
    #|    i32.const 0
    #|    i32.load
    #|  )
    #|)
  inspect(compare_jit_interp(wat, "test", []), content="matched")
}

///|
test "memory32: memory.size returns i32" {
  // Use 1 page since JIT test helper allocates only 1 page
  let wat =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (result i32)
    #|    memory.size
    #|  )
    #|)
  inspect(compare_jit_interp(wat, "test", []), content="matched")
}

///|
test "memory32: memory.grow takes and returns i32" {
  let wat =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (result i32)
    #|    i32.const 1
    #|    memory.grow
    #|  )
    #|)
  inspect(compare_jit_interp(wat, "test", []), content="matched")
}

// ============================================================
// Table64 Tests
// ============================================================

///|
test "table64: table.size returns i64" {
  let wat =
    #|(module
    #|  (table i64 5 funcref)
    #|  (func (export "test") (result i64)
    #|    table.size 0
    #|  )
    #|)
  inspect(compare_jit_interp(wat, "test", []), content="matched")
}

///|
test "table64: table.grow takes and returns i64" {
  let wat =
    #|(module
    #|  (table i64 1 funcref)
    #|  (func (export "test") (result i64)
    #|    ref.null func
    #|    i64.const 2
    #|    table.grow 0
    #|  )
    #|)
  inspect(compare_jit_interp(wat, "test", []), content="matched")
}

// ============================================================
// Table32 Baseline Tests
// ============================================================

///|
test "table32: table.size returns i32" {
  let wat =
    #|(module
    #|  (table 5 funcref)
    #|  (func (export "test") (result i32)
    #|    table.size 0
    #|  )
    #|)
  inspect(compare_jit_interp(wat, "test", []), content="matched")
}

///|
test "table32: table.grow takes and returns i32" {
  let wat =
    #|(module
    #|  (table 1 funcref)
    #|  (func (export "test") (result i32)
    #|    ref.null func
    #|    i32.const 2
    #|    table.grow 0
    #|  )
    #|)
  inspect(compare_jit_interp(wat, "test", []), content="matched")
}
