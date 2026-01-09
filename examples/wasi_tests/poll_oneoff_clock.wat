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

  ;; Event output at 96 (32 bytes, 8-byte aligned)
  ;; nevents output at 200 (initialized to sentinel)
  (data (i32.const 200) "\ff\ff\ff\ff")

  ;; Success message
  (data (i32.const 300) "poll_oneoff: OK\n")
  (data (i32.const 400) "\2c\01\00\00")  ;; buf = 300
  (data (i32.const 404) "\0f\00\00\00")  ;; len = 15

  (func (export "_start")
    (local $errno i32)
    (local $out i32)
    (local.set $out (i32.const 96))
    (local.set $errno (call $poll_oneoff
      (i32.const 0)          ;; in (subscriptions)
      (local.get $out)       ;; out (events)
      (i32.const 1)          ;; nsubscriptions
      (i32.const 200)))      ;; nevents out
    (if (i32.ne (local.get $errno) (i32.const 0)) (then unreachable))
    ;; Check nevents == 1
    (if (i32.ne (i32.load (i32.const 200)) (i32.const 1)) (then unreachable))
    ;; event.userdata == 0x12345678
    (if (i64.ne (i64.load (local.get $out)) (i64.const 305419896)) (then unreachable))
    ;; event.error == 0
    (if (i32.ne (i32.load8_u (i32.add (local.get $out) (i32.const 8))) (i32.const 0)) (then unreachable))
    (if (i32.ne (i32.load8_u (i32.add (local.get $out) (i32.const 9))) (i32.const 0)) (then unreachable))
    ;; event.type == clock (0)
    (if (i32.ne (i32.load8_u (i32.add (local.get $out) (i32.const 10))) (i32.const 0)) (then unreachable))
    ;; clock event payload is zeroed (nbytes at +16)
    (if (i64.ne (i64.load (i32.add (local.get $out) (i32.const 16))) (i64.const 0)) (then unreachable))
    (drop (call $fd_write (i32.const 1) (i32.const 400) (i32.const 1) (i32.const 408)))))
