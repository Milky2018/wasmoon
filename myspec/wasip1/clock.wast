;; WASI Clock Tests
;; Tests clock_time_get and clock_res_get

;; Mock WASI module that provides testable implementations
(module $wasi_snapshot_preview1
  (global $last_errno (mut i32) (i32.const 0))
  (global $monotonic_time (mut i64) (i64.const 1000000))
  (global $realtime_time (mut i64) (i64.const 2000000))

  (memory (export "memory") 1)

  ;; clock_time_get(clock_id, precision, result) -> errno
  (func (export "clock_time_get") (param i32 i64 i32) (result i32)
    (local $clock_id i32)
    (local.set $clock_id (local.get 0))

    ;; Check for valid clock_id
    ;; 0 = realtime, 1 = monotonic
    (if (i32.or (i32.lt_u (local.get $clock_id) (i32.const 0))
                (i32.gt_u (local.get $clock_id) (i32.const 1)))
      (then
        ;; ENOSYS = 38
        (global.set $last_errno (i32.const 38))
        (return (i32.const 38))
      )
    )

    ;; Return timestamp based on clock_id
    (if (i32.eq (local.get $clock_id) (i32.const 0))
      (then
        ;; realtime
        (i64.store (local.get 2) (global.get $realtime_time))
      )
      (else
        ;; monotonic - increment to simulate passing time
        (global.set $monotonic_time (i64.add (global.get $monotonic_time) (i64.const 1)))
        (i64.store (local.get 2) (global.get $monotonic_time))
      )
    )

    (global.set $last_errno (i32.const 0))
    (return (i32.const 0))
  )

  ;; clock_res_get(clock_id, result) -> errno
  (func (export "clock_res_get") (param i32 i32) (result i32)
    (local $clock_id i32)
    (local.set $clock_id (local.get 0))

    ;; Check for valid clock_id
    (if (i32.or (i32.lt_u (local.get $clock_id) (i32.const 0))
                (i32.gt_u (local.get $clock_id) (i32.const 1)))
      (then
        ;; ENOSYS = 38
        (global.set $last_errno (i32.const 38))
        (return (i32.const 38))
      )
    )

    ;; Return resolution (1ns = 1)
    (i64.store (local.get 1) (i64.const 1))
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

;; Test 1: clock_time_get with realtime clock (clock_id=0)
(module
  (import "wasi_snapshot_preview1" "clock_time_get" (func $clock_time_get (param i32 i64 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    ;; Get realtime with precision=1000ns
    (call $clock_time_get (i32.const 0) (i64.const 1000) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 2: clock_time_get with monotonic clock (clock_id=1)
(module
  (import "wasi_snapshot_preview1" "clock_time_get" (func $clock_time_get (param i32 i64 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    ;; Get monotonic time
    (call $clock_time_get (i32.const 1) (i64.const 1000) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 3: clock_time_get with invalid clock_id (should return ENOSYS=38)
(module
  (import "wasi_snapshot_preview1" "clock_time_get" (func $clock_time_get (param i32 i64 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    ;; Try invalid clock_id=3
    (call $clock_time_get (i32.const 3) (i64.const 1000) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 38))

;; Test 4: clock_res_get with realtime clock (clock_id=0)
(module
  (import "wasi_snapshot_preview1" "clock_res_get" (func $clock_res_get (param i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    ;; Get realtime resolution
    (call $clock_res_get (i32.const 0) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 5: clock_res_get with monotonic clock (clock_id=1)
(module
  (import "wasi_snapshot_preview1" "clock_res_get" (func $clock_res_get (param i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    ;; Get monotonic resolution
    (call $clock_res_get (i32.const 1) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 6: clock_res_get with invalid clock_id (should return ENOSYS=38)
(module
  (import "wasi_snapshot_preview1" "clock_res_get" (func $clock_res_get (param i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    ;; Try invalid clock_id=5
    (call $clock_res_get (i32.const 5) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 38))
