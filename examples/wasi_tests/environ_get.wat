(module
  (import "wasi_snapshot_preview1" "environ_sizes_get"
    (func $environ_sizes_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "environ_get"
    (func $environ_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 320) "WASMOON_TEST=1\00")
  (data (i32.const 300) "environ_get: OK\n")
  (data (i32.const 200) "\2c\01\00\00")
  (data (i32.const 204) "\10\00\00\00")
  (func (export "_start")
    (local $errno i32)
    (local $i i32)
    (local $a i32)
    (local $b i32)
    ;; First get sizes
    (local.set $errno (call $environ_sizes_get (i32.const 0) (i32.const 4)))
    (if (i32.ne (local.get $errno) (i32.const 0)) (then unreachable))
    ;; This test is run with exactly one --env WASMOON_TEST=1
    (if (i32.ne (i32.load (i32.const 0)) (i32.const 1)) (then unreachable))
    (if (i32.ne (i32.load (i32.const 4)) (i32.const 15)) (then unreachable))
    ;; Then get environ (environ at 100, environ_buf at 150)
    (local.set $errno (call $environ_get (i32.const 100) (i32.const 150)))
    (if (i32.ne (local.get $errno) (i32.const 0)) (then unreachable))
    (if (i32.ne (i32.load (i32.const 100)) (i32.const 150)) (then unreachable))
    ;; Compare bytes in environ_buf with expected string at 320 (including NUL)
    (local.set $i (i32.const 0))
    (block $done
      (loop $loop
        (local.set $a (i32.load8_u (i32.add (i32.const 150) (local.get $i))))
        (local.set $b (i32.load8_u (i32.add (i32.const 320) (local.get $i))))
        (if (i32.ne (local.get $a) (local.get $b)) (then unreachable))
        (br_if $done (i32.eqz (local.get $a)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)))
    (drop (call $fd_write (i32.const 1) (i32.const 200) (i32.const 1) (i32.const 208)))))
