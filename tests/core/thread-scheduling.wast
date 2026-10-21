;;! threads = true

(module $Memory (memory (export "memory") 1 1 shared))
(register "shared" $Memory)
(module $Check
  (memory (import "shared" "memory") 1 1 shared)
  (func (export "read-start-result") (result i32)
    i32.const 4 i32.load)
  (func (export "spin-until-child") (result i32)
    (loop $again
      i32.const 8 i32.atomic.load i32.const 7 i32.ne br_if $again)
    i32.const 8 i32.atomic.load))

;; A module start must park while another script thread prepares its notifier.
(thread $notifier (shared (module $Memory))
  (register "shared" $Memory)
  (module
    (memory (import "shared" "memory") 1 1 shared)
    (func (export "notify")
      (loop $again
        i32.const 0 i32.const 1 memory.atomic.notify i32.eqz br_if $again)))
  (invoke "notify"))
(module
  (memory (import "shared" "memory") 1 1 shared)
  (func $start
    i32.const 0 i32.const 0 i64.const -1 memory.atomic.wait32 drop
    i32.const 4 i32.const 42 i32.store)
  (start $start))
(wait $notifier)
(assert_return (invoke $Check "read-start-result") (i32.const 42))

;; Module-trap assertions also resume the selected engine's start activation.
(thread $trap-notifier (shared (module $Memory))
  (register "shared" $Memory)
  (module
    (memory (import "shared" "memory") 1 1 shared)
    (func (export "notify")
      (loop $again
        i32.const 16 i32.const 1 memory.atomic.notify i32.eqz br_if $again)))
  (invoke "notify"))
(assert_trap
  (module
    (memory (import "shared" "memory") 1 1 shared)
    (func $start
      i32.const 16 i32.const 0 i64.const -1 memory.atomic.wait32 drop
      unreachable)
    (start $start))
  "unreachable")
(wait $trap-notifier)

;; Both scopes join implicitly; the main thread must yield its producer loop.
(thread $child (shared (module $Memory))
  (thread $grandchild (shared (module $Memory))
    (register "shared" $Memory)
    (module
      (memory (import "shared" "memory") 1 1 shared)
      (func (export "finish")
        i32.const 8 i32.const 7 i32.atomic.store))
    (invoke "finish")))
(assert_return (invoke $Check "spin-until-child") (i32.const 7))
