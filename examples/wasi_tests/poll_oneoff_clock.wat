(module
  (import "wasi_snapshot_preview1" "poll_oneoff"
    (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  ;; Subscription struct at 0 (48 bytes)
  ;; userdata (8 bytes): 0x12345678
  (data (i32.const 0) "\78\56\34\12\00\00\00\00")
  ;; tag (1 byte): 0 = clock, then padding
  (data (i32.const 8) "\00\00\00\00")
  ;; clock_id (4 bytes): 1 = monotonic
  (data (i32.const 16) "\01\00\00\00")
  ;; padding
  (data (i32.const 20) "\00\00\00\00")
  ;; timeout (8 bytes): 1ms = 1000000ns
  (data (i32.const 24) "\40\42\0f\00\00\00\00\00")
  ;; precision (8 bytes)
  (data (i32.const 32) "\00\00\00\00\00\00\00\00")
  ;; flags (2 bytes): 0 = relative
  (data (i32.const 40) "\00\00")

  ;; Event output at 100 (32 bytes)
  ;; nevents output at 200

  ;; Success message
  (data (i32.const 300) "poll_oneoff: OK\n")
  (data (i32.const 400) "\2c\01\00\00")  ;; buf = 300
  (data (i32.const 404) "\0f\00\00\00")  ;; len = 15

  (func (export "_start")
    (if (i32.eqz (call $poll_oneoff
      (i32.const 0)    ;; in (subscriptions)
      (i32.const 100)  ;; out (events)
      (i32.const 1)    ;; nsubscriptions
      (i32.const 200))) ;; nevents out
      (then
        ;; Check that nevents == 1
        (if (i32.eq (i32.load (i32.const 200)) (i32.const 1))
          (then (drop (call $fd_write (i32.const 1) (i32.const 400) (i32.const 1) (i32.const 408)))))))))
