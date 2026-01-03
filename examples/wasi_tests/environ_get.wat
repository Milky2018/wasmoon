(module
  (import "wasi_snapshot_preview1" "environ_sizes_get"
    (func $environ_sizes_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "environ_get"
    (func $environ_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 300) "environ_get: OK\n")
  (data (i32.const 200) "\2c\01\00\00")
  (data (i32.const 204) "\10\00\00\00")
  (func (export "_start")
    ;; First get sizes
    (if (i32.eqz (call $environ_sizes_get (i32.const 0) (i32.const 4)))
      (then
        ;; Then get environ (environ at 100, environ_buf at 150)
        (if (i32.eqz (call $environ_get (i32.const 100) (i32.const 150)))
          (then (drop (call $fd_write (i32.const 1) (i32.const 200) (i32.const 1) (i32.const 208)))))))))
