;; Wasmtime 40 executes an immediately trapping async callee before a sync lower blocks.
(component
  (component $A
    (core func $return (canon task.return (result u32)))
    (core module $M
      (import "" "return" (func $return (param i32)))
      (func (export "run") (param i32)  unreachable )
      (func (export "callback") (param i32 i32 i32) (result i32) i32.const 0))
    (core instance $m (instantiate $M (with "" (instance (export "return" (func $return))))))
    (func (export "run") async (param "x" u32) (result u32)
      (canon lift (core func $m "run") async )))
  (component $B
    (import "f" (func $f async (param "x" u32) (result u32)))
    (core func $f (canon lower (func $f)))
    (core module $M
      (import "" "f" (func $f (param i32) (result i32)))
      (func (export "run") (result i32) i32.const 42 call $f))
    (core instance $m (instantiate $M (with "" (instance (export "f" (func $f))))))
    (func (export "run") (result u32) (canon lift (core func $m "run"))))
  (instance $a (instantiate $A))
  (instance $b (instantiate $B (with "f" (func $a "run"))))
  (export "run" (func $b "run")))
(assert_trap (invoke "run") "unreachable")
(component
  (component $A
    (core func $return (canon task.return (result u32)))
    (core module $M
      (import "" "return" (func $return (param i32)))
      (func (export "run") (param i32) (result i32) unreachable i32.const 1)
      (func (export "callback") (param i32 i32 i32) (result i32) i32.const 0))
    (core instance $m (instantiate $M (with "" (instance (export "return" (func $return))))))
    (func (export "run") async (param "x" u32) (result u32)
      (canon lift (core func $m "run") async (callback (core func $m "callback")))))
  (component $B
    (import "f" (func $f async (param "x" u32) (result u32)))
    (core func $f (canon lower (func $f)))
    (core module $M
      (import "" "f" (func $f (param i32) (result i32)))
      (func (export "run") (result i32) i32.const 42 call $f))
    (core instance $m (instantiate $M (with "" (instance (export "f" (func $f))))))
    (func (export "run") (result u32) (canon lift (core func $m "run"))))
  (instance $a (instantiate $A))
  (instance $b (instantiate $B (with "f" (func $a "run"))))
  (export "run" (func $b "run")))
(assert_trap (invoke "run") "unreachable")
;; A synchronous cancellation validates the handle before it could block.
(component
(core func $cancel (canon subtask.cancel))
(core module $M (import "" "cancel" (func $cancel (param i32) (result i32)))
(func (export "run") i32.const 0xdeadbeef call $cancel drop))
(core instance $m (instantiate $M (with "" (instance (export "cancel" (func $cancel))))))
(func (export "run") (canon lift (core func $m "run"))))
(assert_trap (invoke "run") "handle index")
