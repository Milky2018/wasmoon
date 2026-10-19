(module
  (import "spectest" "print_char" (func $boundary (param i32)))
  (memory (export "memory") 1)
  (tag $e)
  (func (export "run") (param $n i32) (result i32) (local $i i32) (local $saved exnref)
    (loop $populate
      (block $caught (result exnref)
        (try_table (catch_all_ref $caught) (throw $e)) unreachable)
      local.set $saved
      local.get $i i32.const 1 i32.add local.tee $i
      i32.const 4096 i32.lt_u br_if $populate)
    (local.set $i (i32.const 0))
    (if (i32.le_s (local.get $n) (i32.const 0)) (then unreachable))
    (call $boundary (i32.const 1))
    (loop $again
      (block $handled
        (try_table (catch_all $handled) (throw_ref (local.get $saved))))
      local.get $i i32.const 1 i32.add local.tee $i
      local.get $n i32.lt_u br_if $again)
    (call $boundary (i32.const 2))
    (if (i32.ne (local.get $i) (local.get $n)) (then unreachable))
    (local.get $i)))
(assert_return (invoke "run" (i32.const 2000000)) (i32.const 2000000))
