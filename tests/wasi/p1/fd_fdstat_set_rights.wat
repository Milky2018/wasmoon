(module
  (import "wasi_snapshot_preview1" "fd_fdstat_set_rights"
    (func $fd_fdstat_set_rights (param i32 i64 i64) (result i32)))
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_fdstat_get"
    (func $fd_fdstat_get (param i32 i32) (result i32)))
  (memory (export "memory") 1)
  (data (i32.const 200) "fd_fdstat_set_rights: OK\n")
  (data (i32.const 100) "\c8\00\00\00")
  (data (i32.const 104) "\18\00\00\00")
  (func (export "_start")
    (local $errno i32)
    ;; Attenuate stderr while retaining stdout for the success message.
    (local.set $errno (call $fd_fdstat_set_rights (i32.const 2) (i64.const 0) (i64.const 0)))
    (if (local.get $errno) (then unreachable))
    (if (call $fd_fdstat_get (i32.const 2) (i32.const 0)) (then unreachable))
    (if (i64.ne (i64.load (i32.const 8)) (i64.const 0)) (then unreachable))
    (if (i64.ne (i64.load (i32.const 16)) (i64.const 0)) (then unreachable))
    ;; Removed FD_WRITE cannot be restored or exercised.
    (local.set $errno (call $fd_fdstat_set_rights (i32.const 2) (i64.const 64) (i64.const 0)))
    (if (i32.ne (local.get $errno) (i32.const 76)) (then unreachable))
    (local.set $errno (call $fd_write (i32.const 2) (i32.const 100) (i32.const 1) (i32.const 108)))
    (if (i32.ne (local.get $errno) (i32.const 76)) (then unreachable))
    (drop (call $fd_write (i32.const 1) (i32.const 100) (i32.const 1) (i32.const 108)))))
