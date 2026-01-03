(module
  (import "wasi_snapshot_preview1" "fd_filestat_get"
    (func $fd_filestat_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "fd_filestat_get: OK\n")
  (data (i32.const 100) "\c8\00\00\00")
  (data (i32.const 104) "\13\00\00\00")
  (func (export "_start")
    (if (i32.eqz (call $fd_filestat_get (i32.const 1) (i32.const 0)))
      (then (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))))
