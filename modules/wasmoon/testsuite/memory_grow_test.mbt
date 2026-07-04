///|
test "memory.grow: basic grow returns old size" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (result i32)
    #|    (memory.grow (i32.const 1))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "memory.grow: grow by 0 returns current size" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (result i32)
    #|    (memory.grow (i32.const 0))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "memory.grow: grow with dynamic delta" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (param i32) (result i32)
    #|    (memory.grow (local.get 0))
    #|  )
    #|)
  // grow by 0 returns current size (1)
  let result = compare_jit_interp(source, "test", [I32(0)])
  inspect(result, content="matched")
}

///|
test "memory.grow: fails when exceeding max limit" {
  let source =
    #|(module
    #|  (memory 1 2)  ;; min=1 page, max=2 pages
    #|  (func (export "test") (result i32)
    #|    ;; Try to grow by 2 pages - should fail because 1+2=3 > max(2)
    #|    (memory.grow (i32.const 2))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  // Both JIT and interpreter should return -1 (failure)
  inspect(result, content="matched")
}

///|
test "memory.grow: succeeds when within max limit" {
  let source =
    #|(module
    #|  (memory 1 3)  ;; min=1 page, max=3 pages
    #|  (func (export "test") (result i32)
    #|    ;; Grow by 1 page - should succeed because 1+1=2 <= max(3)
    #|    (memory.grow (i32.const 1))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  // Both should return 1 (old size before grow)
  inspect(result, content="matched")
}

///|
test "memory.size: returns initial size" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (result i32)
    #|    (memory.size)
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "memory: store and load i32" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (result i32)
    #|    (i32.store (i32.const 100) (i32.const 12345))
    #|    (i32.load (i32.const 100))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "memory: store and load at different offsets" {
  let source =
    #|(module
    #|  (memory 1)
    #|  (func (export "test") (result i32)
    #|    (i32.store (i32.const 0) (i32.const 111))
    #|    (i32.store (i32.const 4) (i32.const 222))
    #|    (i32.store (i32.const 8) (i32.const 333))
    #|    ;; Sum all values
    #|    (i32.add
    #|      (i32.add
    #|        (i32.load (i32.const 0))
    #|        (i32.load (i32.const 4)))
    #|      (i32.load (i32.const 8)))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}
