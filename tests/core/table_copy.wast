;; Test table.copy instruction

(module
  (table $t 10 funcref)
  (elem $e func $f0 $f1 $f2 $f3 $f4)

  (func $f0 (result i32) (i32.const 0))
  (func $f1 (result i32) (i32.const 1))
  (func $f2 (result i32) (i32.const 2))
  (func $f3 (result i32) (i32.const 3))
  (func $f4 (result i32) (i32.const 4))

  (func (export "init") (param $dst i32) (param $src i32) (param $len i32)
    (table.init $t $e (local.get $dst) (local.get $src) (local.get $len)))

  (func (export "copy") (param $dst i32) (param $src i32) (param $len i32)
    (table.copy $t $t (local.get $dst) (local.get $src) (local.get $len)))

  (func (export "call") (param $idx i32) (result i32)
    (call_indirect $t (result i32) (local.get $idx))))

;; Initialize table[0..4] with f0..f4
(invoke "init" (i32.const 0) (i32.const 0) (i32.const 5))
(assert_return (invoke "call" (i32.const 0)) (i32.const 0))
(assert_return (invoke "call" (i32.const 1)) (i32.const 1))
(assert_return (invoke "call" (i32.const 2)) (i32.const 2))
(assert_return (invoke "call" (i32.const 3)) (i32.const 3))
(assert_return (invoke "call" (i32.const 4)) (i32.const 4))

;; Copy table[1..3] to table[5..7]
(invoke "copy" (i32.const 5) (i32.const 1) (i32.const 3))
(assert_return (invoke "call" (i32.const 5)) (i32.const 1))
(assert_return (invoke "call" (i32.const 6)) (i32.const 2))
(assert_return (invoke "call" (i32.const 7)) (i32.const 3))

;; Zero-length copy should succeed
(invoke "copy" (i32.const 9) (i32.const 0) (i32.const 0))

;; Overlapping copy: forward (dst > src)
;; Copy table[0..2] to table[1..3]
;; Before: [0, 1, 2, 3, 4, ...]
;; After:  [0, 0, 1, 2, 4, ...]
(invoke "copy" (i32.const 1) (i32.const 0) (i32.const 3))
(assert_return (invoke "call" (i32.const 0)) (i32.const 0))
(assert_return (invoke "call" (i32.const 1)) (i32.const 0))
(assert_return (invoke "call" (i32.const 2)) (i32.const 1))
(assert_return (invoke "call" (i32.const 3)) (i32.const 2))

