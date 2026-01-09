;; WASI Clock Tests
;; Tests clock_time_get and clock_res_get with REAL WASI implementation

;; Test 1: clock_time_get with realtime clock (clock_id=0) - verify success
(module
  (import "wasi_snapshot_preview1" "clock_time_get" (func $clock_time_get (param i32 i64 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    ;; Get realtime with precision=1000ns, store result at offset 100
    (call $clock_time_get (i32.const 0) (i64.const 1000) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 2: clock_time_get realtime - verify timestamp is non-zero
(module
  (import "wasi_snapshot_preview1" "clock_time_get" (func $clock_time_get (param i32 i64 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i64)
    ;; Get realtime, store at offset 100
    (drop (call $clock_time_get (i32.const 0) (i64.const 1000) (i32.const 100)))
    ;; Return the timestamp (should be non-zero for realtime clock)
    (i64.load (i32.const 100))
  )

  ;; Check that timestamp is greater than 0 (realtime since epoch)
  (func (export "is_positive") (result i32)
    (drop (call $clock_time_get (i32.const 0) (i64.const 1000) (i32.const 100)))
    (i64.gt_s (i64.load (i32.const 100)) (i64.const 0))
  )
)
(assert_return (invoke "is_positive") (i32.const 1))

;; Test 3: clock_time_get with monotonic clock (clock_id=1)
(module
  (import "wasi_snapshot_preview1" "clock_time_get" (func $clock_time_get (param i32 i64 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    ;; Get monotonic time
    (call $clock_time_get (i32.const 1) (i64.const 1000) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 4: clock_time_get monotonic - two calls should be non-decreasing
(module
  (import "wasi_snapshot_preview1" "clock_time_get" (func $clock_time_get (param i32 i64 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    ;; Get first monotonic time at offset 100
    (drop (call $clock_time_get (i32.const 1) (i64.const 1) (i32.const 100)))
    ;; Get second monotonic time at offset 200
    (drop (call $clock_time_get (i32.const 1) (i64.const 1) (i32.const 200)))
    ;; Second should be >= first (monotonic property)
    (i64.ge_u (i64.load (i32.const 200)) (i64.load (i32.const 100)))
  )
)
(assert_return (invoke "test") (i32.const 1))

;; Test 5: clock_time_get with process CPU time clock (clock_id=2)
(module
  (import "wasi_snapshot_preview1" "clock_time_get" (func $clock_time_get (param i32 i64 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    ;; ProcessCPUTimeId = 2
    (call $clock_time_get (i32.const 2) (i64.const 1000) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 6: clock_time_get with thread CPU time clock (clock_id=3)
(module
  (import "wasi_snapshot_preview1" "clock_time_get" (func $clock_time_get (param i32 i64 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    ;; ThreadCPUTimeId = 3
    (call $clock_time_get (i32.const 3) (i64.const 1000) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 7: clock_time_get with invalid clock_id (should return EINVAL=28)
(module
  (import "wasi_snapshot_preview1" "clock_time_get" (func $clock_time_get (param i32 i64 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    ;; Invalid clock_id=4
    (call $clock_time_get (i32.const 4) (i64.const 1000) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 28))

;; Test 8: clock_time_get with invalid clock_id=99
(module
  (import "wasi_snapshot_preview1" "clock_time_get" (func $clock_time_get (param i32 i64 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (call $clock_time_get (i32.const 99) (i64.const 1000) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 28))

;; Test 9: clock_time_get with precision=0 (should still work)
(module
  (import "wasi_snapshot_preview1" "clock_time_get" (func $clock_time_get (param i32 i64 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (call $clock_time_get (i32.const 0) (i64.const 0) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 10: clock_time_get with very high precision (1ns)
(module
  (import "wasi_snapshot_preview1" "clock_time_get" (func $clock_time_get (param i32 i64 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (call $clock_time_get (i32.const 1) (i64.const 1) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 11: clock_res_get with realtime clock (clock_id=0)
(module
  (import "wasi_snapshot_preview1" "clock_res_get" (func $clock_res_get (param i32 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (call $clock_res_get (i32.const 0) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 12: clock_res_get - resolution should be positive
(module
  (import "wasi_snapshot_preview1" "clock_res_get" (func $clock_res_get (param i32 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (drop (call $clock_res_get (i32.const 0) (i32.const 100)))
    ;; Resolution should be > 0
    (i64.gt_s (i64.load (i32.const 100)) (i64.const 0))
  )
)
(assert_return (invoke "test") (i32.const 1))

;; Test 13: clock_res_get with monotonic clock (clock_id=1)
(module
  (import "wasi_snapshot_preview1" "clock_res_get" (func $clock_res_get (param i32 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (call $clock_res_get (i32.const 1) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 14: clock_res_get with process CPU time clock (clock_id=2)
(module
  (import "wasi_snapshot_preview1" "clock_res_get" (func $clock_res_get (param i32 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (call $clock_res_get (i32.const 2) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 15: clock_res_get with thread CPU time clock (clock_id=3)
(module
  (import "wasi_snapshot_preview1" "clock_res_get" (func $clock_res_get (param i32 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (call $clock_res_get (i32.const 3) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 16: clock_res_get with invalid clock_id (should return EINVAL=28)
(module
  (import "wasi_snapshot_preview1" "clock_res_get" (func $clock_res_get (param i32 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (call $clock_res_get (i32.const 4) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 28))
