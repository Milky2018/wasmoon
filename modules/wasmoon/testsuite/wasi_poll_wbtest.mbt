///|
test "wasi jit: poll fd payload follows aligned subscription union" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "poll_oneoff"
    #|    (func $poll (param i32 i32 i32 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (func (export "test") (result i32)
    #|    (i64.store (i32.const 0) (i64.const 123))
    #|    (i32.store8 (i32.const 8) (i32.const 2))
    #|    ;; Poison the padding: the fd is at offset 16, not 12.
    #|    (i32.store (i32.const 12) (i32.const -1))
    #|    (i32.store (i32.const 16) (i32.const 1))
    #|    (if (call $poll (i32.const 0) (i32.const 64) (i32.const 1) (i32.const 100))
    #|      (then (return (i32.const 1))))
    #|    (if (i32.ne (i32.load (i32.const 100)) (i32.const 1))
    #|      (then (return (i32.const 2))))
    #|    (if (i64.ne (i64.load (i32.const 64)) (i64.const 123))
    #|      (then (return (i32.const 3))))
    #|    (if (i32.load16_u (i32.const 72))
    #|      (then (return (i32.const 4))))
    #|    (if (i32.ne (i32.load8_u (i32.const 74)) (i32.const 2))
    #|      (then (return (i32.const 5))))
    #|    (i32.const 0)))
  let result = compare_wasi(source, "test")
  inspect(wasi_i32_from_result(result.interp_result), content="0")
  inspect(wasi_i32_from_result(result.jit_result), content="0")
}
