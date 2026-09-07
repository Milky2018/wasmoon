///|
test "wasi jit: readlink preserves UTF-8 bytes when truncated inside a character" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_symlink"
    #|    (func $symlink (param i32 i32 i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_readlink"
    #|    (func $readlink (param i32 i32 i32 i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $unlink (param i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "\d0\94")
    #|  (data (i32.const 32) "wasmoon-p1-readlink")
    #|  (func (export "test") (result i32)
    #|    (drop (call $unlink (i32.const 3) (i32.const 32) (i32.const 19)))
    #|    (if (call $symlink (i32.const 0) (i32.const 2) (i32.const 3) (i32.const 32) (i32.const 19))
    #|      (then (return (i32.const 1))))
    #|    (if (call $readlink (i32.const 3) (i32.const 32) (i32.const 19) (i32.const 100) (i32.const 1) (i32.const 104))
    #|      (then (return (i32.const 2))))
    #|    (drop (call $unlink (i32.const 3) (i32.const 32) (i32.const 19)))
    #|    (if (i32.ne (i32.load (i32.const 104)) (i32.const 1))
    #|      (then (return (i32.const 3))))
    #|    (i32.load8_u (i32.const 100))))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(wasi_i32_from_result(result.interp_result), content="208")
  inspect(wasi_i32_from_result(result.jit_result), content="208")
}

///|
test "wasi jit: trailing slash cannot create or unlink a symlink leaf" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_symlink"
    #|    (func $symlink (param i32 i32 i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $unlink (param i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "missing")
    #|  (data (i32.const 32) "wasmoon-p1-slash/")
    #|  (func (export "test") (result i32)
    #|    (local $create i32) (local $unlink_result i32)
    #|    (drop (call $unlink (i32.const 3) (i32.const 32) (i32.const 16)))
    #|    (local.set $create (call $symlink (i32.const 0) (i32.const 7) (i32.const 3) (i32.const 32) (i32.const 17)))
    #|    (drop (call $unlink (i32.const 3) (i32.const 32) (i32.const 16)))
    #|    (if (call $symlink (i32.const 0) (i32.const 7) (i32.const 3) (i32.const 32) (i32.const 16))
    #|      (then (return (i32.const 1))))
    #|    (local.set $unlink_result (call $unlink (i32.const 3) (i32.const 32) (i32.const 17)))
    #|    (drop (call $unlink (i32.const 3) (i32.const 32) (i32.const 16)))
    #|    (i32.and (i32.ne (local.get $create) (i32.const 0)) (i32.ne (local.get $unlink_result) (i32.const 0)))))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(wasi_i32_from_result(result.interp_result), content="1")
  inspect(wasi_i32_from_result(result.jit_result), content="1")
}
