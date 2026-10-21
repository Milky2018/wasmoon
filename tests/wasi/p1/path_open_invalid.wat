(module
  (import "wasi_snapshot_preview1" "path_open"
    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 0) "test.txt")
  (data (i32.const 200) "path_open invalid: OK\n")
  (data (i32.const 100) "\c8\00\00\00")
  (data (i32.const 104) "\15\00\00\00")
  (func (export "_start")
    (local $errno i32)
    (local.set $errno (call $path_open
      (i32.const 999)  ;; invalid dir_fd
      (i32.const 0)    ;; dirflags
      (i32.const 0)    ;; path
      (i32.const 8)    ;; path_len
      (i32.const 0)    ;; oflags
      (i64.const 0)    ;; rights_base
      (i64.const 0)    ;; rights_inheriting
      (i32.const 0)    ;; fdflags
      (i32.const 50)))  ;; opened_fd
    (if (i32.ne (local.get $errno) (i32.const 8)) (then unreachable)) ;; EBADF
    (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))
