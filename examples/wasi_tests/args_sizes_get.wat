(module
  (import "wasi_snapshot_preview1" "args_sizes_get"
    (func $args_sizes_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "args_sizes_get: OK\n")
  (data (i32.const 100) "\c8\00\00\00")
  (data (i32.const 104) "\12\00\00\00")
  (func (export "_start")
    (local $errno i32)
    (local.set $errno (call $args_sizes_get (i32.const 0) (i32.const 4)))
    (if (i32.ne (local.get $errno) (i32.const 0)) (then unreachable))
    ;; wasmoon CLI sets argv[0] = module path (both JIT and interpreter)
    (if (i32.ne (i32.load (i32.const 0)) (i32.const 1)) (then unreachable))
    ;; argv_buf_size must be > 0 (at least "\0")
    (if (i32.eqz (i32.load (i32.const 4))) (then unreachable))
    (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))
