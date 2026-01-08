;; Layout: argc/argv_buf_size at 0/4, argv at 100, argv_buf at 200, iovec at 400, message at 500
(module
  (import "wasi_snapshot_preview1" "args_sizes_get"
    (func $args_sizes_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "args_get"
    (func $args_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 500) "args_get: OK\n")
  (data (i32.const 400) "\f4\01\00\00")
  (data (i32.const 404) "\0d\00\00\00")
  (func (export "_start")
    (local $errno i32)
    (local $argc i32)
    (local $bufsz i32)
    (local $i i32)
    (local $max i32)
    ;; First get sizes
    (local.set $errno (call $args_sizes_get (i32.const 0) (i32.const 4)))
    (if (i32.ne (local.get $errno) (i32.const 0)) (then unreachable))
    (local.set $argc (i32.load (i32.const 0)))
    (local.set $bufsz (i32.load (i32.const 4)))
    ;; wasmoon CLI sets argv[0] = module path
    (if (i32.ne (local.get $argc) (i32.const 1)) (then unreachable))
    (if (i32.eqz (local.get $bufsz)) (then unreachable))
    (local.set $max (i32.sub (local.get $bufsz) (i32.const 1)))
    ;; Then get args (argv at 100, argv_buf at 200)
    (local.set $errno (call $args_get (i32.const 100) (i32.const 200)))
    (if (i32.ne (local.get $errno) (i32.const 0)) (then unreachable))
    ;; argv[0] should point at argv_buf
    (if (i32.ne (i32.load (i32.const 100)) (i32.const 200)) (then unreachable))
    ;; Ensure argv[0] is NUL-terminated exactly at argv_buf_size-1
    (local.set $i (i32.const 0))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $i) (local.get $max)))
        (br_if $done (i32.eqz (i32.load8_u (i32.add (i32.const 200) (local.get $i)))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)))
    (if (i32.ne (local.get $i) (local.get $max)) (then unreachable))
    (if (i32.ne (i32.load8_u (i32.add (i32.const 200) (local.get $i))) (i32.const 0)) (then unreachable))
    (drop (call $fd_write (i32.const 1) (i32.const 400) (i32.const 1) (i32.const 408))))))
