;; Notify must check addresses even when there are no waiters and no memory read.
(module
  (memory 4 4)
  (func (export "notify") (result i32)
    (memory.atomic.notify offset=65536 (i32.const -64) (i32.const 1)))
  (func (export "wait") (result i32)
    (memory.atomic.wait32 (i32.const 0) (i32.const 0) (i64.const 0))))
(assert_trap (invoke "notify") "out of bounds memory access")
(assert_trap (invoke "wait") "atomic wait on non-shared memory")

;; Imported memories retain their address width, sharing, and minimum size.
(module $mem (memory (export "memory") i64 1 1 shared))
(register "mem" $mem)
(module
  (memory (import "mem" "memory") i64 1 1 shared)
  (func (export "notify") (param i64) (result i32)
    (memory.atomic.notify offset=512 (local.get 0) (i32.const 1)))
  (func (export "wait") (param i64) (result i32)
    (memory.atomic.wait32 offset=512 (local.get 0) (i32.const 1) (i64.const 0))))
(assert_return (invoke "notify" (i64.const 0)) (i32.const 0))
(assert_return (invoke "wait" (i64.const 0)) (i32.const 1))
(assert_trap (invoke "notify" (i64.const 0xffffffffffffff00)) "out of bounds memory access")
(assert_trap (invoke "wait" (i64.const 0xffffffffffffff00)) "out of bounds memory access")
