// Regression test for i32.not codegen bug
// The bug: 64-bit MVN was used for i32.not, breaking the zero-extension invariant
// i32.not(0xFFFFFFFF) should be 0, but 64-bit MVN on 0x00000000FFFFFFFF gives 0xFFFFFFFF00000000

///|
test "JIT: i32.not basic" {
  // Test that i32.not(-1) = 0
  let source =
    #|(module
    #|  (func (export "test") (param i32) (result i32)
    #|    (i32.not (local.get 0))
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [I32(-1)])
  inspect(result, content="matched")
}

///|
test "JIT: i32.not with br_if" {
  // This is the critical test: i32.not + br_if was broken
  // i32.not(-1) = 0, so br_if should NOT branch
  let source =
    #|(module
    #|  (func (export "test") (result i32)
    #|    (block (result i32)
    #|      (i32.const 1)
    #|      (br_if 0 (i32.not (i32.const -1)))  ;; not(-1) = 0, should NOT branch
    #|      (drop)
    #|      (i32.const 42)
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "JIT: i32.not with br_if (should branch)" {
  // i32.not(0) = -1 (all 1s), so br_if SHOULD branch
  let source =
    #|(module
    #|  (func (export "test") (result i32)
    #|    (block (result i32)
    #|      (i32.const 1)
    #|      (br_if 0 (i32.not (i32.const 0)))  ;; not(0) = -1, should branch
    #|      (drop)
    #|      (i32.const 42)
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
test "JIT: i32.not preserves zero extension" {
  // Test that the result of i32.not is properly zero-extended
  // i32.sub(0, i32.not(x)) should work correctly
  let source =
    #|(module
    #|  (func (export "test") (param i32) (result i32)
    #|    ;; Returns -(not(x)) = -(-x-1) = x+1
    #|    (i32.sub (i32.const 0) (i32.not (local.get 0)))
    #|  )
    #|)
  // not(5) = -6, sub(0, -6) = 6
  let result = compare_jit_interp(source, "test", [I32(5)])
  inspect(result, content="matched")
}

///|
test "JIT: i32.not in loop condition" {
  // Loop until i32.not(counter) is zero (counter = -1)
  let source =
    #|(module
    #|  (func (export "test") (result i32)
    #|    (local $i i32)
    #|    (local.set $i (i32.const 0))
    #|    (block $exit
    #|      (loop $loop
    #|        ;; Decrement counter
    #|        (local.set $i (i32.sub (local.get $i) (i32.const 1)))
    #|        ;; Continue if not(-1) != 0 (i.e., if $i != -1)
    #|        ;; Since we start at 0 and decrement, first iteration has $i = -1
    #|        ;; not(-1) = 0, so we should exit immediately
    #|        (br_if $loop (i32.not (local.get $i)))
    #|      )
    #|    )
    #|    (local.get $i)
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}
