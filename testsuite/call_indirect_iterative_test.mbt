///|
/// Regression test for call_indirect bug that shows up after many iterations
/// This mimics the aead_aegis128l pattern where the bug appears after 627 iterations

///|
test "call_indirect: iterative call with varying parameters" {
  let source =
    #|(module
    #|  ;; Same type as aead_aegis128l type 10: 10 int params
    #|  (type $t (func (param i32 i32 i32 i32 i64 i32 i64 i32 i32 i32) (result i32)))
    #|
    #|  ;; Simple function that returns sum of all params (mod 256 for simplicity)
    #|  (func $sum (export "sum") (type $t) (result i32)
    #|    (local.get 0)
    #|    (local.get 1) i32.add
    #|    (local.get 2) i32.add
    #|    (local.get 3) i32.add
    #|    (local.get 4) i32.wrap_i64
    #|    (local.get 5) i32.add
    #|    (local.get 6) i32.wrap_i64
    #|    (local.get 7) i32.add
    #|    (local.get 8) i32.add
    #|    (local.get 9) i32.add
    #|    (i32.const 255) i32.and
    #|  )
    #|
    #|  (table funcref (elem $sum))
    #|
    #|  ;; Loop 1000 times, calling call_indirect with different params each time
    #|  (func (export "test") (result i32)
    #|    (local $i i32)
    #|    (local $total i32)
    #|    (local $result i32)
    #|
    #|    (local.set $i (i32.const 0))
    #|    (local.set $total (i32.const 0))
    #|
    #|    (block $break (loop $top
    #|      ;; Call call_indirect with params based on iteration counter
    #|      (call_indirect (type $t)
    #|        (local.get $i)           ;; p0 = i
    #|        (i32.const 1)            ;; p1
    #|        (i32.const 2)            ;; p2
    #|        (i32.const 3)            ;; p3
    #|        (i64.const 5)            ;; p4
    #|        (i32.const 6)            ;; p5
    #|        (i64.const 7)            ;; p6
    #|        (i32.const 8)            ;; p7
    #|        (i32.const 9)            ;; p8
    #|        (i32.const 10)           ;; p9
    #|        (i32.const 0)
    #|      )
    #|      (local.set $result)
    #|      (local.set $total (local.get $total))
    #|
    #|      ;; Check if result matches expected
    #|      (local.get $result)
    #|      (local.get $i)
    #|      (i32.const 46)             ;; 1+2+3+5+6+7+8+9+10 = 51, + i should give i+51
    #|      i32.add
    #|      (i32.const 255) i32.and
    #|      i32.ne
    #|      br_if $break
    #|
    #|      ;; Increment and loop
    #|      (local.set $i (i32.add (local.get $i) (i32.const 1)))
    #|      (local.get $i)
    #|      (i32.const 1000)
    #|      i32.lt_u
    #|      br_if $top
    #|    ))
    #|
    #|    ;; Return 0 if all passed, 1 if failed
    #|    (local.get $i)
    #|    (i32.const 1000)
    #|    i32.eq
    #|  )
    #|)
  inspect(compare_jit_interp(source, "test", []), content="matched")
}

///|
test "call_indirect: type 11 (9 params, 3 stack args)" {
  let source =
    #|(module
    #|  ;; Same type as aead_aegis128l type 11: 9 int params
    #|  (type $t (func (param i32 i32 i32 i64 i32 i32 i64 i32 i32) (result i32)))
    #|
    #|  (func $sum (export "sum") (type $t) (result i32)
    #|    (local.get 0)
    #|    (local.get 1) i32.add
    #|    (local.get 2) i32.add
    #|    (local.get 3) i32.wrap_i64
    #|    (local.get 4) i32.add
    #|    (local.get 5) i32.add
    #|    (local.get 6) i32.wrap_i64
    #|    (local.get 7) i32.add
    #|    (local.get 8) i32.add
    #|    (i32.const 255) i32.and
    #|  )
    #|
    #|  (table funcref (elem $sum))
    #|
    #|  (func (export "test") (result i32)
    #|    (local $i i32)
    #|    (local.set $i (i32.const 0))
    #|
    #|    (block $break (loop $top
    #|      (call_indirect (type $t)
    #|        (local.get $i)
    #|        (i32.const 1)
    #|        (i32.const 2)
    #|        (i64.const 5)
    #|        (i32.const 6)
    #|        (i32.const 7)
    #|        (i64.const 9)
    #|        (i32.const 10)
    #|        (i32.const 11)
    #|        (i32.const 0)
    #|      )
    #|      drop
    #|
    #|      (local.set $i (i32.add (local.get $i) (i32.const 1)))
    #|      (local.get $i)
    #|      (i32.const 1000)
    #|      i32.lt_u
    #|      br_if $top
    #|    ))
    #|
    #|    (i32.const 1)
    #|  )
    #|)
  inspect(compare_jit_interp(source, "test", []), content="matched")
}
