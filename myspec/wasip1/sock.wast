;; WASI Socket Tests
;; Tests sock_accept, sock_send, sock_recv, sock_shutdown

;; Mock WASI module that provides testable implementations
(module $wasi_snapshot_preview1
  (global $last_errno (mut i32) (i32.const 0))

  (memory (export "memory") 2)

  ;; sock_accept(fd, flags, result_fd) -> errno
  (func (export "sock_accept") (param i32 i32 i32) (result i32)
    (local $fd i32)
    (local.set $fd (local.get 0))

    ;; Only fd 3 is valid (a socket fd)
    (if (i32.ne (local.get $fd) (i32.const 3))
      (then
        (global.set $last_errno (i32.const 8))
        (return (i32.const 8))
      )
    )

    ;; Return success with a fake fd
    (i32.store (local.get 2) (i32.const 10))
    (global.set $last_errno (i32.const 0))
    (return (i32.const 0))
  )

  ;; sock_send(fd, si_data, si_data_len, si_flags, so_datalen) -> errno
  (func (export "sock_send") (param i32 i32 i32 i32 i32) (result i32)
    (local $fd i32)
    (local.set $fd (local.get 0))

    ;; Only fd 3 is valid
    (if (i32.ne (local.get $fd) (i32.const 3))
      (then
        (global.set $last_errno (i32.const 8))
        (return (i32.const 8))
      )
    )

    ;; Return bytes sent (assume all data sent)
    (i32.store (local.get 4) (local.get 2))
    (global.set $last_errno (i32.const 0))
    (return (i32.const 0))
  )

  ;; sock_recv(fd, ri_data, ri_data_len, ri_flags, ro_datalen, ro_flags) -> errno
  (func (export "sock_recv") (param i32 i32 i32 i32 i32 i32) (result i32)
    (local $fd i32)
    (local.set $fd (local.get 0))

    ;; Only fd 3 is valid
    (if (i32.ne (local.get $fd) (i32.const 3))
      (then
        (global.set $last_errno (i32.const 8))
        (return (i32.const 8))
      )
    )

    ;; Return bytes received (simulate receiving 0 bytes = EOF)
    (i32.store (local.get 4) (i32.const 0))
    (i32.store (local.get 5) (i32.const 0))  ;; ro_flags
    (global.set $last_errno (i32.const 0))
    (return (i32.const 0))
  )

  ;; sock_shutdown(fd, how) -> errno
  (func (export "sock_shutdown") (param i32 i32) (result i32)
    (local $fd i32)
    (local.set $fd (local.get 0))

    ;; Only fd 3 is valid
    (if (i32.ne (local.get $fd) (i32.const 3))
      (then
        (global.set $last_errno (i32.const 8))
        (return (i32.const 8))
      )
    )

    (global.set $last_errno (i32.const 0))
    (return (i32.const 0))
  )

  ;; Helper to get last errno
  (func (export "get_last_errno") (result i32)
    (global.get $last_errno)
  )
)

;; Register the WASI module so subsequent modules can import from it
(register "wasi_snapshot_preview1" $wasi_snapshot_preview1)

;; Test 1: sock_accept with valid fd
(module
  (import "wasi_snapshot_preview1" "sock_accept" (func $sock_accept (param i32 i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    (call $sock_accept (i32.const 3) (i32.const 0) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 2: sock_accept with invalid fd (should return EBADF=8)
(module
  (import "wasi_snapshot_preview1" "sock_accept" (func $sock_accept (param i32 i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    (call $sock_accept (i32.const 99) (i32.const 0) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 8))

;; Test 3: sock_send with valid fd
(module
  (import "wasi_snapshot_preview1" "sock_send" (func $sock_send (param i32 i32 i32 i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    (call $sock_send (i32.const 3) (i32.const 100) (i32.const 1) (i32.const 0) (i32.const 104))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 4: sock_send with invalid fd (should return EBADF=8)
(module
  (import "wasi_snapshot_preview1" "sock_send" (func $sock_send (param i32 i32 i32 i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    (call $sock_send (i32.const 99) (i32.const 100) (i32.const 1) (i32.const 0) (i32.const 104))
  )
)
(assert_return (invoke "test") (i32.const 8))

;; Test 5: sock_recv with valid fd
(module
  (import "wasi_snapshot_preview1" "sock_recv" (func $sock_recv (param i32 i32 i32 i32 i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    (call $sock_recv (i32.const 3) (i32.const 100) (i32.const 1) (i32.const 0) (i32.const 104) (i32.const 108))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 6: sock_recv with invalid fd (should return EBADF=8)
(module
  (import "wasi_snapshot_preview1" "sock_recv" (func $sock_recv (param i32 i32 i32 i32 i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    (call $sock_recv (i32.const 99) (i32.const 100) (i32.const 1) (i32.const 0) (i32.const 104) (i32.const 108))
  )
)
(assert_return (invoke "test") (i32.const 8))

;; Test 7: sock_shutdown with valid fd
(module
  (import "wasi_snapshot_preview1" "sock_shutdown" (func $sock_shutdown (param i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    (call $sock_shutdown (i32.const 3) (i32.const 0))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 8: sock_shutdown with invalid fd (should return EBADF=8)
(module
  (import "wasi_snapshot_preview1" "sock_shutdown" (func $sock_shutdown (param i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    (call $sock_shutdown (i32.const 99) (i32.const 0))
  )
)
(assert_return (invoke "test") (i32.const 8))
