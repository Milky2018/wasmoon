(module
  (import "wasi_snapshot_preview1" "fd_filestat_set_size"
    (func $fd_filestat_set_size (param i32 i64) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "fd_filestat_set_size: OK\n")
  (data (i32.const 100) "\c8\00\00\00")
  (data (i32.const 104) "\18\00\00\00")
  (func (export "_start")
    (local $errno i32)
    ;; fd_filestat_set_size on stdin returns EINVAL
    (local.set $errno (call $fd_filestat_set_size (i32.const 0) (i64.const 100)))
    (if (i32.ne (local.get $errno) (i32.const 28)) (then unreachable))
    (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))
