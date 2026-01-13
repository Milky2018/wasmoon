(module
  (import "wasi_snapshot_preview1" "sched_yield"
    (func $sched_yield (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "sched_yield: OK\n")
  (data (i32.const 100) "\c8\00\00\00")
  (data (i32.const 104) "\0f\00\00\00")
  (func (export "_start")
    (local $errno i32)
    (local.set $errno (call $sched_yield))
    (if (i32.ne (local.get $errno) (i32.const 0)) (then unreachable))
    (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))
