;; Large string payload lowering smoke (512-byte payload).
(component
  (core module $m
    (memory (export "memory") 1)
    (global $heap (mut i32) (i32.const 1024))

    (func (export "realloc")
      (param $old i32) (param $old_size i32) (param $align i32) (param $new_size i32)
      (result i32)
      (local $ret i32)
      (local.set $ret (global.get $heap))
      (global.set $heap (i32.add (local.get $ret) (local.get $new_size)))
      (local.get $ret)
    )

    (func (export "sink-512") (param i32 i32)
      (if (i32.ne (local.get 1) (i32.const 512))
        (then unreachable)
      )
    )
  )

  (core instance $i (instantiate $m))
  (func (export "sink-512") (param "payload" string)
    (canon lift (core func $i "sink-512")
      (memory $i "memory")
      (realloc (func $i "realloc"))
    )
  )
)

(assert_return
  (invoke "sink-512"
    (str.const "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-_abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-_abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-_abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-_abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-_abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-_abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-_abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-_")))
