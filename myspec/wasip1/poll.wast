;; WASI Poll Tests
;; Tests poll_oneoff with REAL WASI implementation (not mock)
;;
;; Subscription structure (48 bytes):
;;   +0:  userdata (i64)
;;   +8:  type (u8): 0=clock, 1=fd_read, 2=fd_write
;;   +9:  padding (7 bytes)
;;   +16: union content (depends on type)
;;
;; Clock subscription (at +16):
;;   +16: clock_id (i32)
;;   +20: padding (4 bytes)
;;   +24: timeout (i64)
;;   +32: precision (i64)
;;   +40: flags (i16)
;;   +42: padding (6 bytes)
;;
;; FD subscription (at +16):
;;   +16: fd (i32)
;;
;; Event structure (32 bytes):
;;   +0:  userdata (i64)
;;   +8:  error (i16)
;;   +10: type (u8)
;;   +11: padding (5 bytes)
;;   +16: fd_readwrite data (16 bytes) - only for fd events

;; Test 1: poll_oneoff with clock subscription (immediate timeout=0)
(module
  (import "wasi_snapshot_preview1" "poll_oneoff" (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 2)

  (func (export "test") (result i32)
    ;; Setup clock subscription at address 0
    ;; userdata = 0x1234
    (i64.store (i32.const 0) (i64.const 0x1234))
    ;; type = 0 (clock)
    (i32.store8 (i32.const 8) (i32.const 0))
    ;; clock_id = 1 (monotonic) at +16
    (i32.store (i32.const 16) (i32.const 1))
    ;; timeout = 0 (immediate) at +24
    (i64.store (i32.const 24) (i64.const 0))
    ;; precision = 1000ns at +32
    (i64.store (i32.const 32) (i64.const 1000))
    ;; flags = 0 at +40
    (i32.store16 (i32.const 40) (i32.const 0))

    ;; Call poll_oneoff
    ;; subs=0, events=100, nsubscriptions=1, nevents_out=200
    (call $poll_oneoff (i32.const 0) (i32.const 100) (i32.const 1) (i32.const 200))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 2: poll_oneoff - verify nevents is written
(module
  (import "wasi_snapshot_preview1" "poll_oneoff" (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 2)

  (func (export "test") (result i32)
    ;; Setup clock subscription
    (i64.store (i32.const 0) (i64.const 0x1234))
    (i32.store8 (i32.const 8) (i32.const 0))
    (i32.store (i32.const 16) (i32.const 1))
    (i64.store (i32.const 24) (i64.const 0))
    (i64.store (i32.const 32) (i64.const 1000))
    (i32.store16 (i32.const 40) (i32.const 0))

    ;; Clear nevents location first
    (i32.store (i32.const 200) (i32.const 0))

    ;; Call poll_oneoff
    (drop (call $poll_oneoff (i32.const 0) (i32.const 100) (i32.const 1) (i32.const 200)))

    ;; Return nevents - should be 1
    (i32.load (i32.const 200))
  )
)
(assert_return (invoke "test") (i32.const 1))

;; Test 3: poll_oneoff - verify userdata is copied to event
(module
  (import "wasi_snapshot_preview1" "poll_oneoff" (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 2)

  (func (export "test") (result i64)
    ;; Setup clock subscription with specific userdata
    (i64.store (i32.const 0) (i64.const 0xDEADBEEF12345678))
    (i32.store8 (i32.const 8) (i32.const 0))
    (i32.store (i32.const 16) (i32.const 1))
    (i64.store (i32.const 24) (i64.const 0))
    (i64.store (i32.const 32) (i64.const 1000))
    (i32.store16 (i32.const 40) (i32.const 0))

    ;; Call poll_oneoff
    (drop (call $poll_oneoff (i32.const 0) (i32.const 100) (i32.const 1) (i32.const 200)))

    ;; Return userdata from event at +0
    (i64.load (i32.const 100))
  )
)
(assert_return (invoke "test") (i64.const 0xDEADBEEF12345678))

;; Test 4: poll_oneoff with zero subscriptions
(module
  (import "wasi_snapshot_preview1" "poll_oneoff" (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 2)

  (func (export "test") (result i32)
    ;; Initialize nevents to some value
    (i32.store (i32.const 200) (i32.const 99))

    ;; Call with 0 subscriptions
    (drop (call $poll_oneoff (i32.const 0) (i32.const 100) (i32.const 0) (i32.const 200)))

    ;; nevents should be 0
    (i32.load (i32.const 200))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 5: poll_oneoff with multiple clock subscriptions
(module
  (import "wasi_snapshot_preview1" "poll_oneoff" (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 3)

  (func (export "test") (result i32)
    ;; Setup first clock subscription at 0 (48 bytes)
    (i64.store (i32.const 0) (i64.const 0x1000))
    (i32.store8 (i32.const 8) (i32.const 0))
    (i32.store (i32.const 16) (i32.const 1))
    (i64.store (i32.const 24) (i64.const 0))
    (i64.store (i32.const 32) (i64.const 1000))
    (i32.store16 (i32.const 40) (i32.const 0))

    ;; Setup second clock subscription at 48 (48 bytes)
    (i64.store (i32.const 48) (i64.const 0x2000))
    (i32.store8 (i32.const 56) (i32.const 0))
    (i32.store (i32.const 64) (i32.const 1))
    (i64.store (i32.const 72) (i64.const 0))
    (i64.store (i32.const 80) (i64.const 1000))
    (i32.store16 (i32.const 88) (i32.const 0))

    ;; Call poll_oneoff with 2 subscriptions
    (drop (call $poll_oneoff (i32.const 0) (i32.const 200) (i32.const 2) (i32.const 400)))

    ;; Return nevents
    (i32.load (i32.const 400))
  )
)
(assert_return (invoke "test") (i32.const 2))

;; Test 6: poll_oneoff fd_write subscription on stdout (should be ready immediately)
(module
  (import "wasi_snapshot_preview1" "poll_oneoff" (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 2)

  (func (export "test") (result i32)
    ;; Setup fd_write subscription for stdout (fd=1)
    ;; userdata
    (i64.store (i32.const 0) (i64.const 0x5678))
    ;; type = 2 (fd_write)
    (i32.store8 (i32.const 8) (i32.const 2))
    ;; fd = 1 (stdout) at +16
    (i32.store (i32.const 16) (i32.const 1))

    ;; Call poll_oneoff
    (call $poll_oneoff (i32.const 0) (i32.const 100) (i32.const 1) (i32.const 200))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 7: poll_oneoff fd_read subscription on stdin
(module
  (import "wasi_snapshot_preview1" "poll_oneoff" (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 2)

  (func (export "test") (result i32)
    ;; Setup fd_read subscription for stdin (fd=0)
    ;; userdata
    (i64.store (i32.const 0) (i64.const 0x9ABC))
    ;; type = 1 (fd_read)
    (i32.store8 (i32.const 8) (i32.const 1))
    ;; fd = 0 (stdin) at +16
    (i32.store (i32.const 16) (i32.const 0))

    ;; Call poll_oneoff
    (call $poll_oneoff (i32.const 0) (i32.const 100) (i32.const 1) (i32.const 200))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 8: poll_oneoff with realtime clock (clock_id=0)
(module
  (import "wasi_snapshot_preview1" "poll_oneoff" (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 2)

  (func (export "test") (result i32)
    ;; Setup clock subscription with realtime clock
    (i64.store (i32.const 0) (i64.const 0xABCD))
    (i32.store8 (i32.const 8) (i32.const 0))
    ;; clock_id = 0 (realtime)
    (i32.store (i32.const 16) (i32.const 0))
    (i64.store (i32.const 24) (i64.const 0))
    (i64.store (i32.const 32) (i64.const 1000))
    (i32.store16 (i32.const 40) (i32.const 0))

    (call $poll_oneoff (i32.const 0) (i32.const 100) (i32.const 1) (i32.const 200))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 9: poll_oneoff - event type should match subscription type
(module
  (import "wasi_snapshot_preview1" "poll_oneoff" (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 2)

  (func (export "test") (result i32)
    ;; Setup clock subscription (type=0)
    (i64.store (i32.const 0) (i64.const 0x1234))
    (i32.store8 (i32.const 8) (i32.const 0))
    (i32.store (i32.const 16) (i32.const 1))
    (i64.store (i32.const 24) (i64.const 0))
    (i64.store (i32.const 32) (i64.const 1000))
    (i32.store16 (i32.const 40) (i32.const 0))

    (drop (call $poll_oneoff (i32.const 0) (i32.const 100) (i32.const 1) (i32.const 200)))

    ;; Event type is at offset +10 in event structure
    (i32.load8_u (i32.const 110))
  )
)
;; Type 0 = clock
(assert_return (invoke "test") (i32.const 0))

;; Test 10: poll_oneoff with invalid fd should still succeed
;; (the event will have an error code)
(module
  (import "wasi_snapshot_preview1" "poll_oneoff" (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 2)

  (func (export "test") (result i32)
    ;; Setup fd_read subscription for invalid fd=99
    (i64.store (i32.const 0) (i64.const 0xBAD))
    (i32.store8 (i32.const 8) (i32.const 1))
    (i32.store (i32.const 16) (i32.const 99))

    ;; poll_oneoff itself should succeed
    (call $poll_oneoff (i32.const 0) (i32.const 100) (i32.const 1) (i32.const 200))
  )
)
(assert_return (invoke "test") (i32.const 0))
