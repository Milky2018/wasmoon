(module
  (import "wasi_snapshot_preview1" "clock_time_get"
    (func $clock_time_get (param i32 i64 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "clock_time_get: OK\n")
  (data (i32.const 100) "\c8\00\00\00")  ;; buf = 200
  (data (i32.const 104) "\12\00\00\00")  ;; len = 18
  (func (export "_start")
    (if (i32.eqz (call $clock_time_get (i32.const 0) (i64.const 1000000) (i32.const 0)))
      (then (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))))
