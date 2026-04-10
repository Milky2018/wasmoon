;; Resource creation/representation/drop behavior.
(component
  (type $r (resource (rep i32)))
  (core func $rep (canon resource.rep $r))
  (core func $new (canon resource.new $r))
  (core func $drop (canon resource.drop $r))

  (core module $m
    (import "" "rep" (func $rep (param i32) (result i32)))
    (import "" "new" (func $new (param i32) (result i32)))
    (import "" "drop" (func $drop (param i32)))

    (func (export "roundtrip")
      (local $h i32)
      (local.set $h (call $new (i32.const 100)))
      (if (i32.ne (call $rep (local.get $h)) (i32.const 100))
        (then unreachable)
      )
      (call $drop (local.get $h))
    )

    (func (export "drop-missing")
      (call $drop (i32.const 0))
    )
  )

  (core instance $i (instantiate $m
    (with "" (instance
      (export "rep" (func $rep))
      (export "new" (func $new))
      (export "drop" (func $drop))
    ))
  ))

  (func (export "roundtrip") (canon lift (core func $i "roundtrip")))
  (func (export "drop-missing") (canon lift (core func $i "drop-missing")))
)

(assert_return (invoke "roundtrip"))
(assert_trap (invoke "drop-missing") "unknown handle index 0")
