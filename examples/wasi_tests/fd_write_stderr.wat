(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 100) "Hello stderr!\n")
  (data (i32.const 0) "\64\00\00\00")  ;; buf = 100
  (data (i32.const 4) "\0e\00\00\00")  ;; len = 14
  (func (export "_start")
    (drop (call $fd_write (i32.const 2) (i32.const 0) (i32.const 1) (i32.const 8)))))
