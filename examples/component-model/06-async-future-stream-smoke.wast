;; Async future smoke.
(component
  (component $child
    (core module $mem (memory (export "memory") 1))
    (core instance $mem (instantiate $mem))

    (type $future (future))
    (core func $read (canon future.read $future (memory $mem "memory") async))

    (core module $m
      (import "" "read" (func $read (param i32 i32) (result i32)))
      (func (export "run") (param $future i32)
        (call $read (local.get $future) (i32.const 0))
        drop
      )
    )
    (core instance $i (instantiate $m
      (with "" (instance
        (export "read" (func $read))
      ))
    ))
    (func (export "run") (param "x" $future)
      (canon lift (core func $i "run"))
    )
  )

  (instance $child (instantiate $child))

  (type $future (future))
  (core func $new (canon future.new $future))
  (core func $child-run (canon lower (func $child "run")))

  (core module $m
    (import "" "new" (func $new (result i64)))
    (import "" "child-run" (func $child-run (param i32)))
    (func (export "run")
      (call $child-run (i32.wrap_i64 (call $new)))
    )
  )
  (core instance $i (instantiate $m
    (with "" (instance
      (export "new" (func $new))
      (export "child-run" (func $child-run))
    ))
  ))
  (func (export "run")
    (canon lift (core func $i "run"))
  )
)

(assert_return (invoke "run"))

;; Stream smoke.
(component
  (type $s (stream u8))
  (core func $new (canon stream.new $s))
  (core func $drop-r (canon stream.drop-readable $s))
  (core func $drop-w (canon stream.drop-writable $s))

  (core module $m
    (import "" "new" (func $new (result i64)))
    (import "" "drop-r" (func $drop-r (param i32)))
    (import "" "drop-w" (func $drop-w (param i32)))

    (func (export "run")
      (local $pair i64)
      (local $r i32)
      (local $w i32)
      (local.set $pair (call $new))
      (local.set $r (i32.wrap_i64 (local.get $pair)))
      (local.set $w (i32.wrap_i64 (i64.shr_u (local.get $pair) (i64.const 32))))
      (call $drop-r (local.get $r))
      (call $drop-w (local.get $w))
    )
  )

  (core instance $i (instantiate $m
    (with "" (instance
      (export "new" (func $new))
      (export "drop-r" (func $drop-r))
      (export "drop-w" (func $drop-w))
    ))
  ))
  (func (export "run") (canon lift (core func $i "run")))
)

(assert_return (invoke "run"))
