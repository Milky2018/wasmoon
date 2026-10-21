(module
  ;; Test that invalid rights are rejected
  ;; This should fail with EINVAL (28) on compliant WASI implementations

  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "path_open"
    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_prestat_get"
    (func $fd_prestat_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit"
    (func $proc_exit (param i32)))

  (memory (export "memory") 1)

  ;; Messages
  (data (i32.const 128) "Testing invalid rights validation...\n")
  (data (i32.const 168) "path_open with invalid rights: errno=")
  (data (i32.const 208) "\n")
  (data (i32.const 210) "PASS: Got expected EINVAL (28)\n")
  (data (i32.const 244) "FAIL: Expected EINVAL (28)\n")

  ;; Filename
  (data (i32.const 512) "test_invalid.txt")

  ;; Print helper
  (func $print (param $ptr i32) (param $len i32)
    (i32.store (i32.const 0) (local.get $ptr))
    (i32.store (i32.const 4) (local.get $len))
    (call $fd_write (i32.const 1) (i32.const 0) (i32.const 1) (i32.const 8))
    drop
  )

  ;; Print a number (0-99)
  (func $print_num (param $n i32)
    (local $tens i32)
    (local $ones i32)
    (local.set $tens (i32.div_u (local.get $n) (i32.const 10)))
    (local.set $ones (i32.rem_u (local.get $n) (i32.const 10)))
    (if (i32.gt_u (local.get $tens) (i32.const 0))
      (then
        (i32.store8 (i32.const 256) (i32.add (i32.const 48) (local.get $tens)))
        (call $print (i32.const 256) (i32.const 1))
      )
    )
    (i32.store8 (i32.const 256) (i32.add (i32.const 48) (local.get $ones)))
    (call $print (i32.const 256) (i32.const 1))
  )

  (func (export "_start")
    (local $errno i32)

    ;; Print header
    (call $print (i32.const 128) (i32.const 37))

    ;; First check that preopen exists
    (local.set $errno (call $fd_prestat_get (i32.const 3) (i32.const 32)))
    (if (i32.ne (local.get $errno) (i32.const 0))
      (then
        (call $print (i32.const 244) (i32.const 27))
        (call $proc_exit (i32.const 1))
      )
    )

    ;; Try path_open with INVALID rights (bit 30 set, which is not a valid right)
    ;; 0x40000000 = 1 << 30, which is outside the valid range (0-28)
    (call $print (i32.const 168) (i32.const 37))
    (local.set $errno
      (call $path_open
        (i32.const 3)           ;; dir_fd
        (i32.const 0)           ;; dirflags
        (i32.const 512)         ;; path ptr
        (i32.const 16)          ;; path_len
        (i32.const 1)           ;; oflags: CREATE
        (i64.const 0x40000000)  ;; INVALID rights_base (bit 30 set)
        (i64.const 0x1FFFFFFF)  ;; valid rights_inheriting
        (i32.const 0)           ;; fdflags
        (i32.const 16)          ;; opened_fd ptr
      )
    )
    (call $print_num (local.get $errno))
    (call $print (i32.const 208) (i32.const 1))

    ;; Check if we got EINVAL (28)
    (if (i32.eq (local.get $errno) (i32.const 28))
      (then
        (call $print (i32.const 210) (i32.const 31))
        (call $proc_exit (i32.const 0))
      )
      (else
        (call $print (i32.const 244) (i32.const 27))
        (call $proc_exit (i32.const 1))
      )
    )
  )
)
