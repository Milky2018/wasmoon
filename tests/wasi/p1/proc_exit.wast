;; WASI proc_exit Tests
;; Tests proc_exit with REAL WASI implementation
;;
;; NOTE: proc_exit terminates the program with a given exit code.
;; The JIT implementation calls exit() directly, which terminates the entire process.
;; This means we cannot use assert_trap to test it - the test runner would exit.
;;
;; For now, we only verify that proc_exit is callable (the module loads correctly).
;; Testing the actual exit behavior requires running the module as a separate process.

;; Test 1: Module with proc_exit import compiles and runs (without calling proc_exit)
(module
  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (memory (export "memory") 1)

  (func (export "get_answer") (result i32)
    (i32.const 42)
  )
)
(assert_return (invoke "get_answer") (i32.const 42))

;; Test 2: proc_exit can be combined with other WASI imports
(module
  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (import "wasi_snapshot_preview1" "clock_time_get" (func $clock_time_get (param i32 i64 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test_clock") (result i32)
    ;; Just test clock, don't call proc_exit
    (call $clock_time_get (i32.const 1) (i64.const 1000) (i32.const 100))
  )
)
(assert_return (invoke "test_clock") (i32.const 0))

;; Test 3: Conditional proc_exit (condition is false, so doesn't call)
(module
  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (memory (export "memory") 1)

  (func (export "conditional") (param $should_exit i32) (result i32)
    (if (local.get $should_exit)
      (then (call $proc_exit (i32.const 1)))
    )
    (i32.const 100)
  )
)
;; Call with 0 (don't exit)
(assert_return (invoke "conditional" (i32.const 0)) (i32.const 100))

;; NOTE: To test actual proc_exit behavior, use:
;;   ./wasmoon run --invoke exit_with_code proc_exit_test.wat
;; And check the process exit code with: echo $?
