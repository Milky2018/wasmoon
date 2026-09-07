///|
test "wasi jit: positioned append ignores offset and preserves cursor" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_pwrite"
    #|    (func $pwrite (param i32 i32 i32 i64 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_tell"
    #|    (func $tell (param i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_filestat_get"
    #|    (func $stat (param i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_close"
    #|    (func $close (param i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $unlink (param i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon-p1-append")
    #|  (func (export "test") (result i32)
    #|    (local $fd i32)
    #|    (drop (call $unlink (i32.const 3) (i32.const 0) (i32.const 16)))
    #|    (if (call $open (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 16)
    #|      (i32.const 9) (i64.const 2097252) (i64.const 0) (i32.const 1) (i32.const 64))
    #|      (then (return (i32.const -1))))
    #|    (local.set $fd (i32.load (i32.const 64)))
    #|    (i32.store (i32.const 80) (i32.const 96))
    #|    (i32.store (i32.const 84) (i32.const 1))
    #|    (if (call $pwrite (local.get $fd) (i32.const 80) (i32.const 1) (i64.const 50) (i32.const 100))
    #|      (then (return (i32.const -2))))
    #|    (if (call $tell (local.get $fd) (i32.const 104))
    #|      (then (return (i32.const -3))))
    #|    (if (i64.ne (i64.load (i32.const 104)) (i64.const 0))
    #|      (then (return (i32.const -4))))
    #|    (if (call $stat (local.get $fd) (i32.const 128))
    #|      (then (return (i32.const -5))))
    #|    (drop (call $close (local.get $fd)))
    #|    (drop (call $unlink (i32.const 3) (i32.const 0) (i32.const 16)))
    #|    (i32.wrap_i64 (i64.load (i32.const 160)))))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(wasi_i32_from_result(result.interp_result), content="1")
  inspect(wasi_i32_from_result(result.jit_result), content="1")
}
