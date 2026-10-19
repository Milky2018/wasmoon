(module
  (import "wasi_snapshot_preview1" "clock_time_get" (func $clock (param i32 i64 i32) (result i32)))
  (memory (export "memory") 1)
  (tag $e (param i64))
  (func (export "run") (param $n i32) (result i64 i64) (local $i i32)
    (if (i32.le_s (local.get $n) (i32.const 0)) (then unreachable))
    (if (call $clock (i32.const 3) (i64.const 0) (i32.const 16)) (then unreachable))
    (if (call $clock (i32.const 1) (i64.const 0) (i32.const 0)) (then unreachable))
    (loop $again
      (block $caught (result exnref)
        (try_table (catch_all_ref $caught) (throw $e (i64.const 42)))
        unreachable)
      drop
      local.get $i i32.const 1 i32.add local.tee $i
      local.get $n i32.lt_u br_if $again)
    (if (call $clock (i32.const 1) (i64.const 0) (i32.const 8)) (then unreachable))
    (if (call $clock (i32.const 3) (i64.const 0) (i32.const 24)) (then unreachable))
    (if (i32.ne (local.get $i) (local.get $n)) (then unreachable))
    (i64.sub (i64.load (i32.const 8)) (i64.load (i32.const 0)))
    (i64.sub (i64.load (i32.const 24)) (i64.load (i32.const 16)))))
