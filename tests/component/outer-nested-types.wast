(component
  (type $padding (tuple u32 u32))
  (type $t (list (list (list u8))))
  (component $C
    (core module $M
      (memory (export "mem") 1)
      (func (export "get") (result i32) i32.const 0))
    (core instance $m (instantiate $M))
    (alias core export $m "mem" (core memory $mem))
    (func (export "get") (result $t)
      (canon lift (core func $m "get") (memory $mem))))
  (component $B
    (import "a" (instance $a (export "get" (func (result $t)))))
    (core module $M (func (export "run") (result i32) i32.const 42))
    (core instance $m (instantiate $M))
    (func (export "run") (result u32) (canon lift (core func $m "run"))))
  (instance $c (instantiate $C))
  (instance $b (instantiate $B (with "a" (instance $c))))
  (export "run" (func $b "run")))
(assert_return (invoke "run") (u32.const 42))
