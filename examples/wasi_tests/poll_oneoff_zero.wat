(module
  (import "wasi_snapshot_preview1" "poll_oneoff"
    (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  ;; Sentinel values to ensure poll_oneoff(…, nsubscriptions=0, …) only writes nevents.
  (data (i32.const 50) "\ff\ff\ff\ff")   ;; nevents out sentinel
  (data (i32.const 150) "\ef\be\ad\de")  ;; out buffer sentinel (0xdeadbeef)
  (data (i32.const 200) "poll_oneoff zero: OK\n")
  (data (i32.const 100) "\c8\00\00\00")
  (data (i32.const 104) "\14\00\00\00")
  (func (export "_start")
    (local $errno i32)
    (local.set $errno (call $poll_oneoff
      (i32.const 0)    ;; in (ignored)
      (i32.const 150)  ;; out (should be untouched)
      (i32.const 0)    ;; nsubscriptions
      (i32.const 50))) ;; nevents out
    (if (i32.ne (local.get $errno) (i32.const 0)) (then unreachable))
    ;; Check nevents == 0
    (if (i32.ne (i32.load (i32.const 50)) (i32.const 0)) (then unreachable))
    ;; Check out buffer sentinel unchanged
    (if (i32.ne (i32.load (i32.const 150)) (i32.const -559038737)) (then unreachable))
    (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))
