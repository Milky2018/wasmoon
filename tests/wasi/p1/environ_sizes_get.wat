(module
  (import "wasi_snapshot_preview1" "environ_sizes_get"
    (func $environ_sizes_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "environ_sizes_get: OK\n")
  (data (i32.const 100) "\c8\00\00\00")
  (data (i32.const 104) "\15\00\00\00")
  (func (export "_start")
    (local $errno i32)
    (local.set $errno (call $environ_sizes_get (i32.const 0) (i32.const 4)))
    (if (i32.ne (local.get $errno) (i32.const 0)) (then unreachable))
    ;; This test is run with exactly one --env WASMOON_TEST=1
    (if (i32.ne (i32.load (i32.const 0)) (i32.const 1)) (then unreachable))
    ;; "WASMOON_TEST=1" length 14 + NUL = 15
    (if (i32.ne (i32.load (i32.const 4)) (i32.const 15)) (then unreachable))
    (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))
