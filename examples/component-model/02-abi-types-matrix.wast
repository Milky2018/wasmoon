;; Type-system coverage for canonical ABI definitions.
(component
  (core module $m
    (func (export "id") (param i32) (result i32)
      (local.get 0)
    )
  )
  (core instance $i (instantiate $m))

  (type $errno (enum "ok" "io" "perm"))
  (type $fdflags (flags "append" "dsync" "nonblock"))
  (type $fdstat (record
    (field "flags" $fdflags)
    (field "mode" u16)
  ))
  (type $payload (variant
    (case "none")
    (case "bytes" (list u8))
    (case "fd" $fdstat)
  ))
  (type $maybe-payload (option $payload))
  (type $open-result (result (tuple u32 $fdstat) (error $errno)))

  (type (func (param "req" $maybe-payload) (result $open-result)))

  (func (export "id-u32") (param "x" u32) (result u32)
    (canon lift (core func $i "id"))
  )
)

(assert_return (invoke "id-u32" (u32.const 7)) (u32.const 7))
