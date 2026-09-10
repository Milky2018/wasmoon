;; Each top-level instance owns a fresh store and does not inherit a previous trap.
(component
 (core module $M
  (func (export "trap") unreachable)
  (func (export "run")))
 (core instance $m (instantiate $M))
 (func (export "trap") (canon lift (core func $m "trap")))
 (func (export "run") (canon lift (core func $m "run"))))
(assert_trap (invoke "trap") "unreachable")
(component
 (core module $M (func (export "run")))
 (core instance $m (instantiate $M))
 (func (export "run") (canon lift (core func $m "run"))))
(assert_return (invoke "run"))
