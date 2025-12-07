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

  ;; Same as benchmark.wat print_num
  (func $print_num (param $n i32)
    (if (i32.eq (local.get $n) (i32.const 10))
      (then
        (i32.store8 (i32.const 200) (i32.const 49))  ;; '1'
        (i32.store8 (i32.const 201) (i32.const 48))  ;; '0'
      )
      (else
        (i32.store8 (i32.const 200) (i32.const 32))  ;; ' '
        (i32.store8 (i32.const 201) (i32.add (i32.const 48) (local.get $n)))
      )
    )
    (call $print (i32.const 200) (i32.const 2))
  )

  (func (export "_start")
    (call $print_num (i32.const 1))
    (i32.store8 (i32.const 200) (i32.const 10)) ;; newline
    (call $print (i32.const 200) (i32.const 1))

    (call $print_num (i32.const 5))
    (i32.store8 (i32.const 200) (i32.const 10))
    (call $print (i32.const 200) (i32.const 1))

    (call $print_num (i32.const 9))
    (i32.store8 (i32.const 200) (i32.const 10))
    (call $print (i32.const 200) (i32.const 1))

    (call $print_num (i32.const 10))
    (i32.store8 (i32.const 200) (i32.const 10))
    (call $print (i32.const 200) (i32.const 1))

    (call $proc_exit (i32.const 0))
  )
)
