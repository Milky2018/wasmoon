(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit"
    (func $proc_exit (param i32)))

  (memory (export "memory") 1)

  ;; Print helper
  (func $print (param $ptr i32) (param $len i32)
    (i32.store (i32.const 0) (local.get $ptr))
    (i32.store (i32.const 4) (local.get $len))
    (call $fd_write (i32.const 1) (i32.const 0) (i32.const 1) (i32.const 8))
    drop
  )

  ;; Test: print digit based on i32.add result
  (func $test_add (param $n i32)
    ;; Store '0' + n at position 100
    (i32.store8 (i32.const 100) (i32.add (i32.const 48) (local.get $n)))
    (i32.store8 (i32.const 101) (i32.const 10))  ;; newline
    (call $print (i32.const 100) (i32.const 2))
  )

  (func (export "_start")
    (call $test_add (i32.const 1))
    (call $test_add (i32.const 2))
    (call $test_add (i32.const 3))
    (call $test_add (i32.const 5))
    (call $test_add (i32.const 9))
    (call $proc_exit (i32.const 0))
  )
)
