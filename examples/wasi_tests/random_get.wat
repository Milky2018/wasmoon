(module
  (import "wasi_snapshot_preview1" "random_get"
    (func $random_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  ;; Fill buffer with sentinel 0xAA
  (data (i32.const 0) "\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa\aa")
  (data (i32.const 200) "random_get: OK\n")
  (data (i32.const 100) "\c8\00\00\00")
  (data (i32.const 104) "\0f\00\00\00")
  (func (export "_start")
    (local $errno i32)
    (local $i i32)
    (local $diff i32)
    (local.set $errno (call $random_get (i32.const 0) (i32.const 32)))
    (if (i32.ne (local.get $errno) (i32.const 0)) (then unreachable))
    ;; Ensure at least one byte differs from 0xAA
    (local.set $i (i32.const 0))
    (local.set $diff (i32.const 0))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $i) (i32.const 32)))
        (if (i32.ne (i32.load8_u (local.get $i)) (i32.const 170))
          (then
            (local.set $diff (i32.const 1))
            (br $done)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)))
    (if (i32.eqz (local.get $diff)) (then unreachable))
    (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108))))))
