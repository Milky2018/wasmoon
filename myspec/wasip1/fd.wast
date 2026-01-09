;; WASI File Descriptor Tests
;; Tests fd_write, fd_read, fd_seek, fd_close, fd_fdstat_get, fd_filestat_get, etc.

;; Test 1: fd_write with single iovec to stdout
(module
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 100) "Hello")
  (data (i32.const 0) "\64\00\00\00")   ;; iov[0].buf = 100
  (data (i32.const 4) "\05\00\00\00")   ;; iov[0].len = 5

  (func (export "test") (result i32)
    (call $fd_write (i32.const 1) (i32.const 0) (i32.const 1) (i32.const 8))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 2: fd_write with multiple iovecs - tests iovec array parsing
(module
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "Hello ")
  (data (i32.const 210) "World!")
  ;; iovec array at 0
  (data (i32.const 0) "\c8\00\00\00")   ;; iov[0].buf = 200
  (data (i32.const 4) "\06\00\00\00")   ;; iov[0].len = 6
  (data (i32.const 8) "\d2\00\00\00")   ;; iov[1].buf = 210
  (data (i32.const 12) "\06\00\00\00")  ;; iov[1].len = 6

  (func (export "test") (result i32)
    (call $fd_write (i32.const 1) (i32.const 0) (i32.const 2) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 3: fd_write to stderr
(module
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 100) "Error")
  (data (i32.const 0) "\64\00\00\00")   ;; iov[0].buf = 100
  (data (i32.const 4) "\05\00\00\00")   ;; iov[0].len = 5

  (func (export "test") (result i32)
    (call $fd_write (i32.const 2) (i32.const 0) (i32.const 1) (i32.const 8))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 4: fd_write with invalid fd should return EBADF (8)
(module
  (import "wasi_snapshot_preview1" "fd_write" (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (call $fd_write (i32.const 99) (i32.const 0) (i32.const 1) (i32.const 8))
  )
)
(assert_return (invoke "test") (i32.const 8))

;; Test 5: fd_read from stdin
(module
  (import "wasi_snapshot_preview1" "fd_read" (func $fd_read (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 0) "\64\00\00\00")   ;; iov[0].buf = 100
  (data (i32.const 4) "\10\00\00\00")   ;; iov[0].len = 16

  (func (export "test") (result i32)
    (call $fd_read (i32.const 0) (i32.const 0) (i32.const 1) (i32.const 8))
  )
)
;; fd_read on stdin will return 0 (EOF) or actual bytes read
(assert_return (invoke "test") (i32.const 0))

;; Test 6: fd_read with invalid fd should return EBADF (8)
(module
  (import "wasi_snapshot_preview1" "fd_read" (func $fd_read (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (call $fd_read (i32.const 99) (i32.const 0) (i32.const 1) (i32.const 8))
  )
)
(assert_return (invoke "test") (i32.const 8))

;; Test 7: fd_close with invalid fd should return EBADF (8)
(module
  (import "wasi_snapshot_preview1" "fd_close" (func $fd_close (param i32) (result i32)))

  (func (export "test") (result i32)
    (call $fd_close (i32.const 99))
  )
)
(assert_return (invoke "test") (i32.const 8))

;; Test 8: fd_seek on stdout should return ESPIPE (70) - character devices can't seek
(module
  (import "wasi_snapshot_preview1" "fd_seek" (func $fd_seek (param i32 i64 i32 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (call $fd_seek (i32.const 1) (i64.const 0) (i32.const 0) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 70))

;; Test 9: fd_seek on invalid fd should return EBADF (8)
(module
  (import "wasi_snapshot_preview1" "fd_seek" (func $fd_seek (param i32 i64 i32 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (call $fd_seek (i32.const 99) (i64.const 0) (i32.const 0) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 8))

;; Test 10: fd_tell (fd_seek with whence=1 = CUR) - should return ESPIPE (70) on stdout
(module
  (import "wasi_snapshot_preview1" "fd_tell" (func $fd_tell (param i32 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (call $fd_tell (i32.const 1) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 70))

;; Test 11: fd_fdstat_get on stdout
(module
  (import "wasi_snapshot_preview1" "fd_fdstat_get" (func $fd_fdstat_get (param i32 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (call $fd_fdstat_get (i32.const 1) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 12: fd_fdstat_get with invalid fd should return EBADF (8)
(module
  (import "wasi_snapshot_preview1" "fd_fdstat_get" (func $fd_fdstat_get (param i32 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (call $fd_fdstat_get (i32.const 99) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 8))

;; Test 13: fd_filestat_get on stdout
(module
  (import "wasi_snapshot_preview1" "fd_filestat_get" (func $fd_filestat_get (param i32 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (call $fd_filestat_get (i32.const 1) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 14: fd_filestat_get with invalid fd should return EBADF (8)
(module
  (import "wasi_snapshot_preview1" "fd_filestat_get" (func $fd_filestat_get (param i32 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (call $fd_filestat_get (i32.const 99) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 8))

;; Test 15: fd_fdstat_set_flags - on macOS this may succeed
(module
  (import "wasi_snapshot_preview1" "fd_fdstat_set_flags" (func $fd_fdstat_set_flags (param i32 i32) (result i32)))

  (func (export "test") (result i32)
    (call $fd_fdstat_set_flags (i32.const 1) (i32.const 1))
  )
)
;; On macOS, fcntl(F_SETFL) on stdout succeeds for certain flags
(assert_return (invoke "test") (i32.const 0))

;; Test 16: fd_fdstat_set_flags with invalid fd should return EBADF (8)
(module
  (import "wasi_snapshot_preview1" "fd_fdstat_set_flags" (func $fd_fdstat_set_flags (param i32 i32) (result i32)))

  (func (export "test") (result i32)
    (call $fd_fdstat_set_flags (i32.const 99) (i32.const 1))
  )
)
(assert_return (invoke "test") (i32.const 8))

;; Test 17: fd_fdstat_set_rights
(module
  (import "wasi_snapshot_preview1" "fd_fdstat_set_rights" (func $fd_fdstat_set_rights (param i32 i64 i64) (result i32)))

  (func (export "test") (result i32)
    (call $fd_fdstat_set_rights (i32.const 1) (i64.const 1) (i64.const 1))
  )
)
;; Should succeed (0) or return ENOSYS (38) if not implemented
(assert_return (invoke "test") (i32.const 0))

;; Test 18: fd_prestat_get on invalid fd should return EBADF (8)
(module
  (import "wasi_snapshot_preview1" "fd_prestat_get" (func $fd_prestat_get (param i32 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (call $fd_prestat_get (i32.const 99) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 8))

;; Test 19: fd_pread with invalid fd should return EBADF (8)
(module
  (import "wasi_snapshot_preview1" "fd_pread" (func $fd_pread (param i32 i32 i32 i64 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (call $fd_pread (i32.const 99) (i32.const 0) (i32.const 1) (i64.const 0) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 8))

;; Test 20: fd_pwrite with invalid fd should return EBADF (8)
(module
  (import "wasi_snapshot_preview1" "fd_pwrite" (func $fd_pwrite (param i32 i32 i32 i64 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (call $fd_pwrite (i32.const 99) (i32.const 0) (i32.const 1) (i64.const 0) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 8))

;; Test 21: fd_sync with invalid fd should return EBADF (8)
(module
  (import "wasi_snapshot_preview1" "fd_sync" (func $fd_sync (param i32) (result i32)))

  (func (export "test") (result i32)
    (call $fd_sync (i32.const 99))
  )
)
(assert_return (invoke "test") (i32.const 8))

;; Test 22: fd_datasync with invalid fd should return EBADF (8)
(module
  (import "wasi_snapshot_preview1" "fd_datasync" (func $fd_datasync (param i32) (result i32)))

  (func (export "test") (result i32)
    (call $fd_datasync (i32.const 99))
  )
)
(assert_return (invoke "test") (i32.const 8))

;; Test 23: fd_advise
(module
  (import "wasi_snapshot_preview1" "fd_advise" (func $fd_advise (param i32 i64 i64 i32) (result i32)))

  (func (export "test") (result i32)
    (call $fd_advise (i32.const 99) (i64.const 0) (i64.const 100) (i32.const 0))
  )
)
;; Should return EBADF (8) or ENOSYS (38)
(assert_return (invoke "test") (i32.const 8))

;; Test 24: fd_allocate with invalid fd should return EBADF (8)
(module
  (import "wasi_snapshot_preview1" "fd_allocate" (func $fd_allocate (param i32 i64 i64) (result i32)))

  (func (export "test") (result i32)
    (call $fd_allocate (i32.const 99) (i64.const 0) (i64.const 100))
  )
)
(assert_return (invoke "test") (i32.const 8))

;; Test 25: fd_filestat_set_size with invalid fd should return EBADF (8)
(module
  (import "wasi_snapshot_preview1" "fd_filestat_set_size" (func $fd_filestat_set_size (param i32 i64) (result i32)))

  (func (export "test") (result i32)
    (call $fd_filestat_set_size (i32.const 99) (i64.const 100))
  )
)
(assert_return (invoke "test") (i32.const 8))

;; Test 26: fd_filestat_set_times with invalid fd should return EBADF (8)
(module
  (import "wasi_snapshot_preview1" "fd_filestat_set_times" (func $fd_filestat_set_times (param i32 i64 i64 i32) (result i32)))

  (func (export "test") (result i32)
    (call $fd_filestat_set_times (i32.const 99) (i64.const 0) (i64.const 0) (i32.const 0))
  )
)
(assert_return (invoke "test") (i32.const 8))

;; Test 27: fd_renumber to stdio fd returns EINVAL (28)
;; Renumbering to/from stdio fds (0-2) is not allowed
(module
  (import "wasi_snapshot_preview1" "fd_renumber" (func $fd_renumber (param i32 i32) (result i32)))

  (func (export "test") (result i32)
    (call $fd_renumber (i32.const 99) (i32.const 1))
  )
)
;; Returns EINVAL (28) because to_fd=1 is stdout (stdio)
(assert_return (invoke "test") (i32.const 28))

;; Test 28: sched_yield should always succeed
(module
  (import "wasi_snapshot_preview1" "sched_yield" (func $sched_yield (result i32)))

  (func (export "test") (result i32)
    (call $sched_yield)
  )
)
(assert_return (invoke "test") (i32.const 0))
