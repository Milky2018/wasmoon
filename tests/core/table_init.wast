;; Test table.init instruction

(module
  (table $t 10 funcref)
  (elem $e func $f0 $f1 $f2)

  (func $f0 (result i32) (i32.const 0))
  (func $f1 (result i32) (i32.const 1))
  (func $f2 (result i32) (i32.const 2))

  (func (export "init") (param $dst i32) (param $src i32) (param $len i32)
    (table.init $t $e (local.get $dst) (local.get $src) (local.get $len)))

  (func (export "call") (param $idx i32) (result i32)
    (call_indirect $t (result i32) (local.get $idx))))

;; Initialize table[0..2] from elem[0..2]
(invoke "init" (i32.const 0) (i32.const 0) (i32.const 3))
(assert_return (invoke "call" (i32.const 0)) (i32.const 0))
(assert_return (invoke "call" (i32.const 1)) (i32.const 1))
(assert_return (invoke "call" (i32.const 2)) (i32.const 2))

;; Initialize table[5..6] from elem[1..2]
(invoke "init" (i32.const 5) (i32.const 1) (i32.const 2))
(assert_return (invoke "call" (i32.const 5)) (i32.const 1))
(assert_return (invoke "call" (i32.const 6)) (i32.const 2))


;; Test elem.drop instruction
(module
  (table $t 10 funcref)
  (elem $e func $f0)

  (func $f0 (result i32) (i32.const 42))

  (func (export "init") (param $dst i32) (param $src i32) (param $len i32)
    (table.init $t $e (local.get $dst) (local.get $src) (local.get $len)))

  (func (export "drop")
    (elem.drop $e))

  (func (export "call") (param $idx i32) (result i32)
    (call_indirect $t (result i32) (local.get $idx))))

;; Init before drop
(invoke "init" (i32.const 0) (i32.const 0) (i32.const 1))
(assert_return (invoke "call" (i32.const 0)) (i32.const 42))

;; Drop the element segment
(invoke "drop")

;; Zero-length init after drop works
(invoke "init" (i32.const 5) (i32.const 0) (i32.const 0))

;; Non-zero init after drop should trap
(assert_trap (invoke "init" (i32.const 5) (i32.const 0) (i32.const 1)) "out of bounds")

;; Multiple drops allowed
(invoke "drop")
(invoke "drop")
