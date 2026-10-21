;; Exported resource identities survive reflection into fresh script stores.
(component $A
 (type $r (resource (rep i32)))
 (export "x" (type $r))
 (export "y" (type $r)))
(component $B
 (import "A" (instance $a (export "x" (type (sub resource)))))
 (alias export $a "x" (type $r))
 (export "x" (type $r)))
(component
 (import "A" (instance $a
  (export "x" (type $r (sub resource)))
  (export "y" (type (eq $r)))))
 (alias export $a "x" (type $r))
 (import "B" (instance (export "x" (type (eq $r)))))
 (core module $M (func (export "run")))
 (core instance $m (instantiate $M))
 (func (export "run") (canon lift (core func $m "run"))))
(assert_return (invoke "run"))
(component $D
 (type $r (resource (rep i32)))
 (export "x" (type $r)))
(assert_unlinkable
 (component
  (import "A" (instance $a (export "x" (type (sub resource)))))
  (alias export $a "x" (type $r))
  (import "D" (instance (export "x" (type (eq $r))))))
 "mismatched resource types")
