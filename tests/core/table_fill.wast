;; Test table.fill instruction

(module
  (table $t 10 funcref)
  (elem $e func $f42)

  (func $f42 (result i32) (i32.const 42))

  (func (export "init") (param $dst i32) (param $src i32) (param $len i32)
    (table.init $t $e (local.get $dst) (local.get $src) (local.get $len)))

  (func (export "fill") (param $idx i32) (param $len i32)
    (table.fill $t (local.get $idx) (ref.func $f42) (local.get $len)))

  (func (export "fill_null") (param $idx i32) (param $len i32)
    (table.fill $t (local.get $idx) (ref.null func) (local.get $len)))

  (func (export "call") (param $idx i32) (result i32)
    (call_indirect $t (result i32) (local.get $idx))))

;; Fill table[0..2] with f42
(invoke "fill" (i32.const 0) (i32.const 3))
(assert_return (invoke "call" (i32.const 0)) (i32.const 42))
(assert_return (invoke "call" (i32.const 1)) (i32.const 42))
(assert_return (invoke "call" (i32.const 2)) (i32.const 42))

;; Fill table[5..7] with f42
(invoke "fill" (i32.const 5) (i32.const 3))
(assert_return (invoke "call" (i32.const 5)) (i32.const 42))
(assert_return (invoke "call" (i32.const 6)) (i32.const 42))
(assert_return (invoke "call" (i32.const 7)) (i32.const 42))

;; Zero-length fill should succeed
(invoke "fill" (i32.const 9) (i32.const 0))

;; Fill with null - should succeed but call will trap
(invoke "fill_null" (i32.const 8) (i32.const 1))
(assert_trap (invoke "call" (i32.const 8)) "uninitialized element")

