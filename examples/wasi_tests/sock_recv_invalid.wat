(module
  (import "wasi_snapshot_preview1" "sock_recv"
    (func $sock_recv (param i32 i32 i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 0) "\64\00\00\00\40\00\00\00")  ;; iovec
  (data (i32.const 200) "sock_recv invalid: OK\n")
  (data (i32.const 100) "\c8\00\00\00")
  (data (i32.const 104) "\15\00\00\00")
  (func (export "_start")
    (local $errno i32)
    (local.set $errno (call $sock_recv (i32.const 999) (i32.const 0) (i32.const 1) (i32.const 0) (i32.const 50) (i32.const 52)))
    (if (i32.ne (local.get $errno) (i32.const 8)) (then unreachable))
    (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))
