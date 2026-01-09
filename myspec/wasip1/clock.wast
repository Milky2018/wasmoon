;; WASI Clock Tests
;; Tests clock_time_get and clock_res_get

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

;; Test 3: clock_time_get with process CPU time clock (clock_id=2)
(module
  (import "wasi_snapshot_preview1" "clock_time_get" (func $clock_time_get (param i32 i64 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    ;; ProcessCPUTimeId = 2 (supported in real WASI)
    (call $clock_time_get (i32.const 2) (i64.const 1000) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 4: clock_time_get with thread CPU time clock (clock_id=3)
(module
  (import "wasi_snapshot_preview1" "clock_time_get" (func $clock_time_get (param i32 i64 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    ;; ThreadCPUTimeId = 3 (supported in real WASI)
    (call $clock_time_get (i32.const 3) (i64.const 1000) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 5: clock_time_get with invalid clock_id (should return EINVAL=28)
(module
  (import "wasi_snapshot_preview1" "clock_time_get" (func $clock_time_get (param i32 i64 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    ;; Try invalid clock_id=4 (beyond the defined clock IDs)
    (call $clock_time_get (i32.const 4) (i64.const 1000) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 28))

;; Test 6: clock_res_get with realtime clock (clock_id=0)
(module
  (import "wasi_snapshot_preview1" "clock_res_get" (func $clock_res_get (param i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    ;; Get realtime resolution
    (call $clock_res_get (i32.const 0) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 7: clock_res_get with monotonic clock (clock_id=1)
(module
  (import "wasi_snapshot_preview1" "clock_res_get" (func $clock_res_get (param i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    ;; Get monotonic resolution
    (call $clock_res_get (i32.const 1) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 8: clock_res_get with thread CPU time clock (clock_id=3)
(module
  (import "wasi_snapshot_preview1" "clock_res_get" (func $clock_res_get (param i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    ;; ThreadCPUTimeId = 3 (supported in real WASI)
    (call $clock_res_get (i32.const 3) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 0))
