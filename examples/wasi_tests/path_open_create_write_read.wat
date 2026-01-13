;; Positive FS test: create a file in a preopened dir, write, seek, read back.
;; Runner must pass: --dir <tmpdir>::/sandbox
(module
  (import "wasi_snapshot_preview1" "path_open"
    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_read"
    (func $fd_read (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_seek"
    (func $fd_seek (param i32 i64 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_close"
    (func $fd_close (param i32) (result i32)))

  (memory (export "memory") 1)

  (data (i32.const 0) "a.txt")
  (data (i32.const 100) "hello")
  (data (i32.const 120) "hello")
  (data (i32.const 300) "path_open create/read: OK\n")
  (data (i32.const 400) "\2c\01\00\00")  ;; iov.buf = 300
  (data (i32.const 404) "\1a\00\00\00")  ;; iov.len = 26

  (func (export "_start")
    (local $errno i32)
    (local $fd i32)
    (local $i i32)
    ;; Open/create file relative to the first preopen dir (dir_fd=3).
    (local.set $errno (call $path_open
      (i32.const 3)    ;; dir_fd
      (i32.const 0)    ;; dirflags
      (i32.const 0)    ;; path
      (i32.const 5)    ;; path_len ("a.txt")
      (i32.const 9)    ;; oflags = CREAT|TRUNC
      (i64.const 0)    ;; rights_base
      (i64.const 0)    ;; rights_inheriting
      (i32.const 0)    ;; fdflags
      (i32.const 20))) ;; opened_fd out
    (if (i32.ne (local.get $errno) (i32.const 0)) (then unreachable))
    (local.set $fd (i32.load (i32.const 20)))

    ;; Write "hello" via fd_write.
    ;; iovec at 64: { buf=100, len=5 }
    (i32.store (i32.const 64) (i32.const 100))
    (i32.store (i32.const 68) (i32.const 5))
    (local.set $errno (call $fd_write (local.get $fd) (i32.const 64) (i32.const 1) (i32.const 24)))
    (if (i32.ne (local.get $errno) (i32.const 0)) (then unreachable))
    (if (i32.ne (i32.load (i32.const 24)) (i32.const 5)) (then unreachable))

    ;; Seek back to start.
    (local.set $errno (call $fd_seek (local.get $fd) (i64.const 0) (i32.const 0) (i32.const 32)))
    (if (i32.ne (local.get $errno) (i32.const 0)) (then unreachable))
    (if (i64.ne (i64.load (i32.const 32)) (i64.const 0)) (then unreachable))

    ;; Read 5 bytes to 140.
    (i32.store (i32.const 72) (i32.const 140))
    (i32.store (i32.const 76) (i32.const 5))
    (local.set $errno (call $fd_read (local.get $fd) (i32.const 72) (i32.const 1) (i32.const 28)))
    (if (i32.ne (local.get $errno) (i32.const 0)) (then unreachable))
    (if (i32.ne (i32.load (i32.const 28)) (i32.const 5)) (then unreachable))

    ;; Compare read bytes with expected "hello" at 120.
    (local.set $i (i32.const 0))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $i) (i32.const 5)))
        (if (i32.ne
          (i32.load8_u (i32.add (i32.const 140) (local.get $i)))
          (i32.load8_u (i32.add (i32.const 120) (local.get $i))))
          (then unreachable))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)))

    ;; Close file (best-effort).
    (local.set $errno (call $fd_close (local.get $fd)))
    (if (i32.ne (local.get $errno) (i32.const 0)) (then unreachable))

    ;; Print OK.
    (drop (call $fd_write (i32.const 1) (i32.const 400) (i32.const 1) (i32.const 408)))
  )
)

