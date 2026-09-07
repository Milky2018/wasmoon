///|
test "wasi jit: path_open preserves zero rights and irreversible inheritance bounds" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_fdstat_get"
    #|    (func $stat (param i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_fdstat_set_rights"
    #|    (func $reduce (param i32 i64 i64) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) ".")
    #|  (func $open (param $fd i32) (param $base i64) (param $inherit i64) (result i32)
    #|    (call $path_open (local.get $fd) (i32.const 1) (i32.const 0) (i32.const 1)
    #|      (i32.const 2) (local.get $base) (local.get $inherit) (i32.const 0) (i32.const 64)))
    #|  (func (export "test") (result i32)
    #|    (local $fd i32)
    #|    (if (call $open (i32.const 3) (i64.const 0) (i64.const 0))
    #|      (then (return (i32.const 1))))
    #|    (local.set $fd (i32.load (i32.const 64)))
    #|    (if (call $stat (local.get $fd) (i32.const 80))
    #|      (then (return (i32.const 2))))
    #|    (if (i64.ne (i64.or (i64.load (i32.const 88)) (i64.load (i32.const 96))) (i64.const 0))
    #|      (then (return (i32.const 3))))
    #|    (if (i32.ne (call $open (local.get $fd) (i64.const 0) (i64.const 0)) (i32.const 76))
    #|      (then (return (i32.const 4))))
    #|    ;; PATH_OPEN is the only capability needed to open another directory.
    #|    (if (call $open (i32.const 3) (i64.const 8192) (i64.const 8192))
    #|      (then (return (i32.const 5))))
    #|    (local.set $fd (i32.load (i32.const 64)))
    #|    (if (call $open (local.get $fd) (i64.const 8192) (i64.const 0))
    #|      (then (return (i32.const 6))))
    #|    (if (call $reduce (local.get $fd) (i64.const 8192) (i64.const 0))
    #|      (then (return (i32.const 7))))
    #|    (if (i32.ne (call $open (local.get $fd) (i64.const 8192) (i64.const 0)) (i32.const 76))
    #|      (then (return (i32.const 8))))
    #|    (if (call $reduce (local.get $fd) (i64.const 0) (i64.const 0))
    #|      (then (return (i32.const 9))))
    #|    (if (i32.ne (call $reduce (local.get $fd) (i64.const 8192) (i64.const 0)) (i32.const 76))
    #|      (then (return (i32.const 10))))
    #|    (i32.const 0)))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(wasi_i32_from_result(result.interp_result), content="0")
  inspect(wasi_i32_from_result(result.jit_result), content="0")
}
