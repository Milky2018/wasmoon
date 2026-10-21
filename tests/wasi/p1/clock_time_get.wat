;; Test realtime clock: verify it returns reasonable values
(module
  (import "wasi_snapshot_preview1" "clock_time_get"
    (func $clock_time_get (param i32 i64 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 1)

  ;; 2020-01-01 in seconds = 1577836800
  (data (i32.const 200) "clock_time_get: FAIL\nclock_time_get: OK\n")
  (data (i32.const 100) "\c8\00\00\00")  ;; buf = 200 (FAIL)
  (data (i32.const 104) "\15\00\00\00")  ;; len = 21
  (data (i32.const 108) "\dd\00\00\00")  ;; buf = 221 (OK)
  (data (i32.const 112) "\13\00\00\00")  ;; len = 19

  (func (export "_start")
    (local $timestamp_ns i64)
    (local $timestamp_s i64)

    ;; Get realtime clock (store at address 0)
    (drop (call $clock_time_get (i32.const 0) (i64.const 1000) (i32.const 0)))
    (local.set $timestamp_ns (i64.load (i32.const 0)))

    ;; Check: not zero
    (if (i64.eqz (local.get $timestamp_ns))
      (then
        (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 104)))
        (return)
      )
    )

    ;; Check: reasonable (>= 2020-01-01)
    (local.set $timestamp_s (i64.div_u (local.get $timestamp_ns) (i64.const 1000000000)))
    (if (i64.lt_u (local.get $timestamp_s) (i64.const 1577836800))
      (then
        (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 104)))
        (return)
      )
    )

    ;; All checks passed
    (drop (call $fd_write (i32.const 1) (i32.const 108) (i32.const 1) (i32.const 112)))
  )
)
