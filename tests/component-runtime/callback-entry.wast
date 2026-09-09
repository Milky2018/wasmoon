;; A yielded callback no longer holds its component's entry lock.
(component
 (core func $return (canon task.return))
 (core module $Inner
  (import "" "return" (func $return))
  (memory (export "memory") 1)
  (global $visited (mut i32) (i32.const 0))
  (func (export "visited") (result i32) global.get $visited)
  (func (export "a") (result i32)
   i32.const 1 global.set $visited call $return i32.const 0)
  (func (export "callback") (param i32 i32 i32) (result i32) unreachable))
 (core instance $inner (instantiate $Inner (with "" (instance (export "return" (func $return))))))
 (func $a async (canon lift (core func $inner "a") async (callback (core func $inner "callback"))))
 (component $Child
  (import "a" (func $a async))
  (core module $Memory (memory (export "memory") 1))
  (core instance $memory (instantiate $Memory))
  (core func $a (canon lower (func $a) async (memory $memory "memory")))
  (core func $return (canon task.return))
  (core module $M
   (import "" "a" (func $a (result i32)))
   (import "" "return" (func $return))
   (func (export "run") (result i32) i32.const 1)
   (func (export "callback") (param i32 i32 i32) (result i32)
    call $a i32.const 2 i32.ne if unreachable end
    call $return i32.const 0))
  (core instance $m (instantiate $M (with "" (instance
   (export "a" (func $a)) (export "return" (func $return))))))
  (func (export "b") async (canon lift (core func $m "run") async (callback (core func $m "callback")))))
 (instance $child (instantiate $Child (with "a" (func $a))))
 (core func $b (canon lower (func $child "b") async (memory $inner "memory")))
 (core module $Outer
  (import "" "b" (func $b (result i32)))
  (import "" "visited" (func $visited (result i32)))
  (import "" "return" (func $return))
  (global $started (mut i32) (i32.const 0))
  (func (export "run") (result i32) i32.const 1)
  (func (export "callback") (param i32 i32 i32) (result i32)
   global.get $started i32.eqz if
    i32.const 1 global.set $started call $b drop
   end
   call $visited if call $return i32.const 0 return end
   i32.const 1))
 (core instance $outer (instantiate $Outer (with "" (instance
  (export "b" (func $b)) (export "visited" (func $inner "visited"))
  (export "return" (func $return))))))
 (func (export "run") async (canon lift (core func $outer "run") async (callback (core func $outer "callback")))))
(assert_return (invoke "run"))

;; Synchronous parent-to-child-to-parent calls may also reenter.
(component
 (core module $Inner (func (export "a") unreachable))
 (core instance $inner (instantiate $Inner))
 (func $a (canon lift (core func $inner "a")))
 (component $Child
  (import "a" (func $a))
  (core func $a (canon lower (func $a)))
  (core module $M
   (import "" "a" (func $a))
   (func (export "run") call $a))
  (core instance $m (instantiate $M (with "" (instance (export "a" (func $a))))))
  (func (export "b") (canon lift (core func $m "run"))))
 (instance $child (instantiate $Child (with "a" (func $a))))
 (core func $b (canon lower (func $child "b")))
 (core module $Outer
  (import "" "b" (func $b))
  (func (export "run") call $b))
 (core instance $outer (instantiate $Outer (with "" (instance (export "b" (func $b))))))
 (func (export "run") (canon lift (core func $outer "run"))))
(assert_trap (invoke "run") "unreachable")

;; A trap permanently prevents entry into the affected component.
(component
 (core module $M
  (func (export "trap") unreachable)
  (func (export "run")))
 (core instance $m (instantiate $M))
 (func (export "trap") (canon lift (core func $m "trap")))
 (func (export "run") (canon lift (core func $m "run"))))
(assert_trap (invoke "trap") "unreachable")
(assert_trap (invoke "run") "cannot enter component instance")

;; Poison is shared by all component instances in the same linker/store.
(component
 (component $A
  (core module $M (func (export "trap") unreachable))
  (core instance $m (instantiate $M))
  (func (export "trap") (canon lift (core func $m "trap"))))
 (component $B
  (core module $M (func (export "run")))
  (core instance $m (instantiate $M))
  (func (export "run") (canon lift (core func $m "run"))))
 (instance $a (instantiate $A))
 (instance $b (instantiate $B))
 (func (export "trap") (alias export $a "trap"))
 (func (export "run") (alias export $b "run")))
(assert_trap (invoke "trap") "unreachable")
(assert_trap (invoke "run") "cannot enter component instance")

;; A result decoding error is not a core trap and does not poison the store.
(component
 (core module $M
  (memory (export "mem") 1)
  (data (i32.const 0) "\08\00\00\00\01\00\00\00\00\d8")
  (func (export "get") (result i32) i32.const 0)
  (func (export "run")))
 (core instance $m (instantiate $M))
 (func (export "get") (result string)
  (canon lift (core func $m "get") (memory $m "mem") string-encoding=utf16))
 (func (export "run") (canon lift (core func $m "run"))))
(assert_trap (invoke "get") "unpaired surrogate")
(assert_return (invoke "run"))
