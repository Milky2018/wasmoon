;; Minimal string parameter/return smoke test.
(component
  (core module $m
    (memory (export "memory") 1)
    (global $heap (mut i32) (i32.const 64))

    (func (export "realloc")
      (param $old i32) (param $old_size i32) (param $align i32) (param $new_size i32)
      (result i32)
      (local $ret i32)
      (local.set $ret (global.get $heap))
      (global.set $heap (i32.add (local.get $ret) (local.get $new_size)))
      (local.get $ret)
    )

    (func (export "greet") (param i32 i32) (result i32)
      (i32.store (i32.const 0) (i32.const 32))
      (i32.store (i32.const 4) (i32.const 16))
      (i32.store8 (i32.const 32) (i32.const 104)) ;; h
      (i32.store8 (i32.const 33) (i32.const 101)) ;; e
      (i32.store8 (i32.const 34) (i32.const 108)) ;; l
      (i32.store8 (i32.const 35) (i32.const 108)) ;; l
      (i32.store8 (i32.const 36) (i32.const 111)) ;; o
      (i32.store8 (i32.const 37) (i32.const 44))  ;; ,
      (i32.store8 (i32.const 38) (i32.const 32))  ;; space
      (i32.store8 (i32.const 39) (i32.const 99))  ;; c
      (i32.store8 (i32.const 40) (i32.const 111)) ;; o
      (i32.store8 (i32.const 41) (i32.const 109)) ;; m
      (i32.store8 (i32.const 42) (i32.const 112)) ;; p
      (i32.store8 (i32.const 43) (i32.const 111)) ;; o
      (i32.store8 (i32.const 44) (i32.const 110)) ;; n
      (i32.store8 (i32.const 45) (i32.const 101)) ;; e
      (i32.store8 (i32.const 46) (i32.const 110)) ;; n
      (i32.store8 (i32.const 47) (i32.const 116)) ;; t
      (i32.const 0)
    )
  )

  (core instance $i (instantiate $m))
  (func (export "greet") (param "name" string) (result string)
    (canon lift (core func $i "greet")
      (memory $i "memory")
      (realloc (func $i "realloc"))
    )
  )
)

(assert_return (invoke "greet" (str.const "wasmoon")) (str.const "hello, component"))
