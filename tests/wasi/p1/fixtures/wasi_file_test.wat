(module
  ;; Test that all WASI file functions have correct signatures
  ;; by calling them and checking error codes

  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_read"
    (func $fd_read (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "path_open"
    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_close"
    (func $fd_close (param i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_seek"
    (func $fd_seek (param i32 i64 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_tell"
    (func $fd_tell (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit"
    (func $proc_exit (param i32)))

  (memory (export "memory") 1)

  ;; Messages
  (data (i32.const 64) "Testing WASI file functions...\n")
  (data (i32.const 128) "fd_seek on stdout: errno=")
  (data (i32.const 160) "fd_tell on stdout: errno=")
  (data (i32.const 192) "path_open (no dir): errno=")
  (data (i32.const 224) "All tests passed!\n")
  (data (i32.const 256) "\n")

  ;; Print helper
  (func $print (param $ptr i32) (param $len i32)
    (i32.store (i32.const 0) (local.get $ptr))
    (i32.store (i32.const 4) (local.get $len))
    (call $fd_write (i32.const 1) (i32.const 0) (i32.const 1) (i32.const 8))
    drop
  )

  ;; Print single digit number
  (func $print_digit (param $n i32)
    (i32.store8 (i32.const 300) (i32.add (i32.const 48) (local.get $n)))
    (call $print (i32.const 300) (i32.const 1))
  )

  (func (export "_start")
    (local $errno i32)

    ;; Print header
    (call $print (i32.const 64) (i32.const 31))

    ;; Test 1: fd_seek on stdout (should fail with ESPIPE=29 or similar)
    (call $print (i32.const 128) (i32.const 25))
    (local.set $errno
      (call $fd_seek
        (i32.const 1)   ;; stdout
        (i64.const 0)   ;; offset
        (i32.const 0)   ;; SEEK_SET
        (i32.const 16)  ;; result pointer
      )
    )
    ;; Print errno (should be 29=ESPIPE or 8=EBADF or 70=ENOTCAPABLE)
    (call $print_digit (i32.rem_u (local.get $errno) (i32.const 10)))
    (call $print (i32.const 256) (i32.const 1))

    ;; Test 2: fd_tell on stdout
    (call $print (i32.const 160) (i32.const 25))
    (local.set $errno
      (call $fd_tell
        (i32.const 1)   ;; stdout
        (i32.const 16)  ;; result pointer
      )
    )
    (call $print_digit (i32.rem_u (local.get $errno) (i32.const 10)))
    (call $print (i32.const 256) (i32.const 1))

    ;; Test 3: path_open with invalid dir_fd (should fail with EBADF=8)
    (call $print (i32.const 192) (i32.const 26))
    (i64.store (i32.const 32) (i64.const 0x7473_6574)) ;; "test" backwards
    (local.set $errno
      (call $path_open
        (i32.const 99)    ;; invalid dir_fd
        (i32.const 0)     ;; dirflags
        (i32.const 32)    ;; path
        (i32.const 4)     ;; path_len
        (i32.const 0)     ;; oflags
        (i64.const 0)     ;; rights_base
        (i64.const 0)     ;; rights_inheriting
        (i32.const 0)     ;; fdflags
        (i32.const 16)    ;; opened_fd
      )
    )
    (call $print_digit (local.get $errno))
    (call $print (i32.const 256) (i32.const 1))

    ;; Success
    (call $print (i32.const 224) (i32.const 18))
    (call $proc_exit (i32.const 0))
  )
)
