(module
  (import "wasi_snapshot_preview1" "sock_shutdown"
    (func $sock_shutdown (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "sock_shutdown invalid: OK\n")
  (data (i32.const 100) "\c8\00\00\00")
  (data (i32.const 104) "\19\00\00\00")
  (func (export "_start")
    (local $errno i32)
    (local.set $errno (call $sock_shutdown (i32.const 999) (i32.const 0)))
    (if (i32.ne (local.get $errno) (i32.const 8)) (then unreachable))
    (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))
