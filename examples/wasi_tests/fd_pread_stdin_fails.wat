(module
  (import "wasi_snapshot_preview1" "fd_pread"
    (func $fd_pread (param i32 i32 i32 i64 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 0) "\64\00\00\00\40\00\00\00")  ;; iovec
  (data (i32.const 200) "fd_pread stdin: OK\n")
  (data (i32.const 100) "\c8\00\00\00")
  (data (i32.const 104) "\12\00\00\00")
  (func (export "_start")
    (local $errno i32)
    (local.set $errno (call $fd_pread (i32.const 0) (i32.const 0) (i32.const 1) (i64.const 0) (i32.const 8)))
    (if (i32.ne (local.get $errno) (i32.const 70)) (then unreachable))
    (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))
