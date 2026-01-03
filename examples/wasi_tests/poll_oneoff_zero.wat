(module
  (import "wasi_snapshot_preview1" "poll_oneoff"
    (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "poll_oneoff zero: OK\n")
  (data (i32.const 100) "\c8\00\00\00")
  (data (i32.const 104) "\14\00\00\00")
  (func (export "_start")
    (if (i32.eqz (call $poll_oneoff (i32.const 0) (i32.const 0) (i32.const 0) (i32.const 50)))
      (then
        ;; Check nevents == 0
        (if (i32.eqz (i32.load (i32.const 50)))
          (then (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))))))
