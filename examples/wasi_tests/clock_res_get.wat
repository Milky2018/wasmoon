(module
  (import "wasi_snapshot_preview1" "clock_res_get"
    (func $clock_res_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "clock_res_get: OK\n")
  (data (i32.const 100) "\c8\00\00\00")
  (data (i32.const 104) "\11\00\00\00")
  (func (export "_start")
    (if (i32.eqz (call $clock_res_get (i32.const 0) (i32.const 0)))
      (then (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))))
