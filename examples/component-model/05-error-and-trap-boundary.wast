;; Distinguish recoverable status-code return from trap.
(component
  (core module $m
    (func (export "fail-code") (result i32)
      (i32.const 7)
    )
    (func (export "boom")
      (unreachable)
    )
  )
  (core instance $i (instantiate $m))
  (func (export "fail-code") (result u32)
    (canon lift (core func $i "fail-code"))
  )
  (func (export "boom")
    (canon lift (core func $i "boom"))
  )
)

(assert_return (invoke "fail-code") (u32.const 7))
(assert_trap (invoke "boom") "unreachable")
