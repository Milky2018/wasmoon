;; Compose two components: adder -> pipeline.
(component
  (component $adder
    (core module $m
      (func (export "inc") (param i32) (result i32)
        (local.get 0)
        (i32.const 1)
        (i32.add)
      )
    )
    (core instance $i (instantiate $m))
    (func (export "inc") (param "x" u32) (result u32)
      (canon lift (core func $i "inc"))
    )
  )

  (component $pipeline
    (import "upstream" (instance $upstream
      (export "inc" (func $inc (param "x" u32) (result u32)))
    ))
    (alias export $upstream "inc" (func $inc))
    (core func $inc (canon lower (func $inc)))

    (core module $m
      (import "" "inc" (func $inc (param i32) (result i32)))
      (func (export "apply") (param i32) (result i32)
        (local.get 0)
        (i32.const 1)
        (i32.shl)
        (call $inc)
      )
    )
    (core instance $i (instantiate $m
      (with "" (instance
        (export "inc" (func $inc))
      ))
    ))
    (func (export "apply") (param "x" u32) (result u32)
      (canon lift (core func $i "apply"))
    )
  )

  (instance $a (instantiate $adder))
  (instance $b (instantiate $pipeline
    (with "upstream" (instance $a))
  ))
  (func (export "apply") (alias export $b "apply"))
)

(assert_return (invoke "apply" (u32.const 21)) (u32.const 43))
