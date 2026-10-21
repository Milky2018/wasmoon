(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 1)
  ;; First string at 200
  (data (i32.const 200) "Hello ")
  ;; Second string at 210
  (data (i32.const 210) "World!\n")
  ;; iovec array at 0: two entries
  (data (i32.const 0) "\c8\00\00\00")   ;; iov[0].buf = 200
  (data (i32.const 4) "\06\00\00\00")   ;; iov[0].len = 6
  (data (i32.const 8) "\d2\00\00\00")   ;; iov[1].buf = 210
  (data (i32.const 12) "\07\00\00\00")  ;; iov[1].len = 7
  (func (export "_start")
    (local $errno i32)
    (local $written i32)
    (local.set $errno (call $fd_write (i32.const 1) (i32.const 0) (i32.const 2) (i32.const 100)))
    (if (i32.ne (local.get $errno) (i32.const 0)) (then unreachable))
    ;; fd_write may perform a short write, but it must report forward progress.
    (local.set $written (i32.load (i32.const 100)))
    (if (i32.eqz (local.get $written)) (then unreachable))
    (if (i32.gt_u (local.get $written) (i32.const 13)) (then unreachable))))
