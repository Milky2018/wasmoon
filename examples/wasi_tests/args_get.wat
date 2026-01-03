;; Note: argv_buf needs enough space for long paths (macOS temp dirs can be 60+ chars)
;; Layout: argv at 100, argv_buf at 200, iovec at 400, message at 500
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
    ;; First get sizes
    (if (i32.eqz (call $args_sizes_get (i32.const 0) (i32.const 4)))
      (then
        ;; Then get args (argv at 100, argv_buf at 200 - room for long paths)
        (if (i32.eqz (call $args_get (i32.const 100) (i32.const 200)))
          (then (drop (call $fd_write (i32.const 1) (i32.const 400) (i32.const 1) (i32.const 408)))))))))
