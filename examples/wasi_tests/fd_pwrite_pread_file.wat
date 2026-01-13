;; Positive FS test: verify fd_pwrite/fd_pread offset semantics on a real file.
;; Runner must pass: --dir <tmpdir>::/sandbox
(module
  (import "wasi_snapshot_preview1" "path_open"
    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_pwrite"
    (func $fd_pwrite (param i32 i32 i32 i64 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_pread"
    (func $fd_pread (param i32 i32 i32 i64 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_tell"
    (func $fd_tell (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_close"
    (func $fd_close (param i32) (result i32)))

  (memory (export "memory") 1)

  (data (i32.const 0) "b.txt")
  (data (i32.const 100) "abcdef")
  (data (i32.const 120) "Z")
  (data (i32.const 140) "abZdef")
  (data (i32.const 300) "fd_pwrite/pread: OK\n")
  (data (i32.const 400) "\2c\01\00\00")  ;; iov.buf = 300
  (data (i32.const 404) "\14\00\00\00")  ;; iov.len = 20

  (func (export "_start")
    (local $errno i32)
    (local $fd i32)
    (local $i i32)

    ;; Open/create file relative to the first preopen dir (dir_fd=3).
    (local.set $errno (call $path_open
      (i32.const 3)    ;; dir_fd
      (i32.const 0)    ;; dirflags
      (i32.const 0)    ;; path
      (i32.const 5)    ;; path_len ("b.txt")
      (i32.const 9)    ;; oflags = CREAT|TRUNC
      (i64.const 0)    ;; rights_base
      (i64.const 0)    ;; rights_inheriting
      (i32.const 0)    ;; fdflags
      (i32.const 20))) ;; opened_fd out
    (if (i32.ne (local.get $errno) (i32.const 0)) (then unreachable))
    (local.set $fd (i32.load (i32.const 20)))

    ;; fd_write "abcdef" (6 bytes), cursor becomes 6.
    (i32.store (i32.const 64) (i32.const 100))
    (i32.store (i32.const 68) (i32.const 6))
    (local.set $errno (call $fd_write (local.get $fd) (i32.const 64) (i32.const 1) (i32.const 24)))
    (if (i32.ne (local.get $errno) (i32.const 0)) (then unreachable))
    (if (i32.ne (i32.load (i32.const 24)) (i32.const 6)) (then unreachable))

    ;; fd_tell should report 6.
    (local.set $errno (call $fd_tell (local.get $fd) (i32.const 32)))
    (if (i32.ne (local.get $errno) (i32.const 0)) (then unreachable))
    (if (i64.ne (i64.load (i32.const 32)) (i64.const 6)) (then unreachable))

    ;; fd_pwrite "Z" at offset 2, without moving cursor.
    (i32.store (i32.const 72) (i32.const 120))
    (i32.store (i32.const 76) (i32.const 1))
    (local.set $errno (call $fd_pwrite (local.get $fd) (i32.const 72) (i32.const 1) (i64.const 2) (i32.const 28)))
    (if (i32.ne (local.get $errno) (i32.const 0)) (then unreachable))
    (if (i32.ne (i32.load (i32.const 28)) (i32.const 1)) (then unreachable))

    ;; Cursor should still be 6.
    (local.set $errno (call $fd_tell (local.get $fd) (i32.const 32)))
    (if (i32.ne (local.get $errno) (i32.const 0)) (then unreachable))
    (if (i64.ne (i64.load (i32.const 32)) (i64.const 6)) (then unreachable))

    ;; fd_pread 6 bytes from offset 0 to 200.
    (i32.store (i32.const 80) (i32.const 200))
    (i32.store (i32.const 84) (i32.const 6))
    (local.set $errno (call $fd_pread (local.get $fd) (i32.const 80) (i32.const 1) (i64.const 0) (i32.const 36)))
    (if (i32.ne (local.get $errno) (i32.const 0)) (then unreachable))
    (if (i32.ne (i32.load (i32.const 36)) (i32.const 6)) (then unreachable))

    ;; Compare with expected "abZdef" at 140.
    (local.set $i (i32.const 0))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $i) (i32.const 6)))
        (if (i32.ne
          (i32.load8_u (i32.add (i32.const 200) (local.get $i)))
          (i32.load8_u (i32.add (i32.const 140) (local.get $i))))
          (then unreachable))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)))

    ;; Close file.
    (local.set $errno (call $fd_close (local.get $fd)))
    (if (i32.ne (local.get $errno) (i32.const 0)) (then unreachable))

    ;; Print OK.
    (drop (call $fd_write (i32.const 1) (i32.const 400) (i32.const 1) (i32.const 408)))
  )
)

