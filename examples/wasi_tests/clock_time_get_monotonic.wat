(module
  (import "wasi_snapshot_preview1" "clock_time_get"
    (func $clock_time_get (param i32 i64 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "clock monotonic: OK\n")
  (data (i32.const 100) "\c8\00\00\00")
  (data (i32.const 104) "\13\00\00\00")
  (func (export "_start")
    ;; clock_id 1 = monotonic
    (if (i32.eqz (call $clock_time_get (i32.const 1) (i64.const 1000000) (i32.const 0)))
      (then (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))))
