;; Test memory.init instruction

;; Basic memory.init from passive data segment
(module
  (memory 1)
  (data $d "\aa\bb\cc\dd")

  (func (export "init") (param $dst i32) (param $src i32) (param $len i32)
    (memory.init $d (local.get $dst) (local.get $src) (local.get $len)))

  (func (export "load8") (param $addr i32) (result i32)
    (i32.load8_u (local.get $addr))))

;; Copy 2 bytes from data[1] to memory[0]
(invoke "init" (i32.const 0) (i32.const 1) (i32.const 2))
(assert_return (invoke "load8" (i32.const 0)) (i32.const 0xbb))
(assert_return (invoke "load8" (i32.const 1)) (i32.const 0xcc))

;; Copy all 4 bytes to memory[10]
(invoke "init" (i32.const 10) (i32.const 0) (i32.const 4))
(assert_return (invoke "load8" (i32.const 10)) (i32.const 0xaa))
(assert_return (invoke "load8" (i32.const 11)) (i32.const 0xbb))
(assert_return (invoke "load8" (i32.const 12)) (i32.const 0xcc))
(assert_return (invoke "load8" (i32.const 13)) (i32.const 0xdd))

;; Zero-length init should succeed
(invoke "init" (i32.const 100) (i32.const 0) (i32.const 0))


;; Test data.drop instruction
(module
  (memory 1)
  (data $d "hello")

  (func (export "init") (param $dst i32) (param $src i32) (param $len i32)
    (memory.init $d (local.get $dst) (local.get $src) (local.get $len)))

  (func (export "drop")
    (data.drop $d))

  (func (export "load8") (param $addr i32) (result i32)
    (i32.load8_u (local.get $addr))))

;; Init before drop works
(invoke "init" (i32.const 0) (i32.const 0) (i32.const 5))
(assert_return (invoke "load8" (i32.const 0)) (i32.const 0x68)) ;; 'h'
(assert_return (invoke "load8" (i32.const 4)) (i32.const 0x6f)) ;; 'o'

;; Drop the segment
(invoke "drop")

;; Zero-length init after drop still works
(invoke "init" (i32.const 50) (i32.const 0) (i32.const 0))

;; Non-zero init after drop should trap
(assert_trap (invoke "init" (i32.const 50) (i32.const 0) (i32.const 1)) "out of bounds")

;; Multiple drops are allowed
(invoke "drop")
(invoke "drop")
