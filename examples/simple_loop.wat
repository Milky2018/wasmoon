(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))

  (memory (export "memory") 1)

  ;; Messages
  (data (i32.const 128) "Loop iteration\n")
  (data (i32.const 144) "Done!\n")

  (func $print (param $ptr i32) (param $len i32)
    (i32.store (i32.const 0) (local.get $ptr))
    (i32.store (i32.const 4) (local.get $len))
    (call $fd_write (i32.const 1) (i32.const 0) (i32.const 1) (i32.const 8))
    drop
  )

  (func (export "_start")
    (local $i i32)
    (local.set $i (i32.const 0))

    (block $done
      (loop $loop
        ;; Exit if i >= 3
        (br_if $done (i32.ge_u (local.get $i) (i32.const 3)))

        ;; Print "Loop iteration"
        (call $print (i32.const 128) (i32.const 15))

        ;; i = i + 1
        (local.set $i (i32.add (local.get $i) (i32.const 1)))

        ;; Continue loop
        (br $loop)
      )
    )

    ;; Print "Done!"
    (call $print (i32.const 144) (i32.const 6))
  )
)
