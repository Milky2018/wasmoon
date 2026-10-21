;; Test monotonic clock: verify it increases
(module
  (import "wasi_snapshot_preview1" "clock_time_get"
    (func $clock_time_get (param i32 i64 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 1)

  (data (i32.const 200) "clock monotonic: FAIL\nclock monotonic: OK\n")
  (data (i32.const 100) "\c8\00\00\00")  ;; buf = 200 (FAIL)
  (data (i32.const 104) "\16\00\00\00")  ;; len = 22
  (data (i32.const 108) "\de\00\00\00")  ;; buf = 222 (OK)
  (data (i32.const 112) "\14\00\00\00")  ;; len = 20

  (func (export "_start")
    (local $t1 i64)
    (local $t2 i64)

    ;; Get T1
    (drop (call $clock_time_get (i32.const 1) (i64.const 1000) (i32.const 0)))
    (local.set $t1 (i64.load (i32.const 0)))

    ;; Check: not zero
    (if (i64.eqz (local.get $t1))
      (then
        (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 104)))
        (return)
      )
    )

    ;; Get T2
    (drop (call $clock_time_get (i32.const 1) (i64.const 1000) (i32.const 8)))
    (local.set $t2 (i64.load (i32.const 8)))

    ;; Check: T2 >= T1 (monotonic)
    (if (i64.lt_u (local.get $t2) (local.get $t1))
      (then
        (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 104)))
        (return)
      )
    )

    ;; All checks passed
    (drop (call $fd_write (i32.const 1) (i32.const 108) (i32.const 1) (i32.const 112)))
  )
)
