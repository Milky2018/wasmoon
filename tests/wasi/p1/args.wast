;; WASI Args Tests
;; Tests args_sizes_get and args_get

;; Test 1: args_sizes_get
(module
  (memory 1)

  (func $args_sizes_get (param i32 i32) (result i32)
    ;; Return argc = 3, argv_buf_size = 18
    (i32.store (local.get 0) (i32.const 3))
    (i32.store (local.get 1) (i32.const 18))
    (return (i32.const 0))
  )

  (func (export "test_argc") (result i32)
    (drop (call $args_sizes_get (i32.const 100) (i32.const 104)))
    (i32.load (i32.const 100))
  )

  (func (export "test_argv_buf_size") (result i32)
    (drop (call $args_sizes_get (i32.const 100) (i32.const 104)))
    (i32.load (i32.const 104))
  )
)
(assert_return (invoke "test_argc") (i32.const 3))
(assert_return (invoke "test_argv_buf_size") (i32.const 18))

;; Test 2: args_get
(module
  (memory 2)

  (func $args_get (param i32 i32) (result i32)
    (local $argv i32)
    (local $argv_buf i32)
    (local.set $argv (local.get 0))
    (local.set $argv_buf (local.get 1))

    ;; Write argv pointers
    (i32.store (local.get $argv) (local.get $argv_buf))
    (i32.store (i32.add (local.get $argv) (i32.const 4))
              (i32.add (local.get $argv_buf) (i32.const 8)))
    (i32.store (i32.add (local.get $argv) (i32.const 8))
              (i32.add (local.get $argv_buf) (i32.const 12)))

    ;; Write "program" at argv_buf
    (i32.store8 (local.get $argv_buf) (i32.const 112))
    (i32.store8 (i32.add (local.get $argv_buf) (i32.const 1)) (i32.const 114))
    (i32.store8 (i32.add (local.get $argv_buf) (i32.const 2)) (i32.const 111))
    (i32.store8 (i32.add (local.get $argv_buf) (i32.const 3)) (i32.const 103))
    (i32.store8 (i32.add (local.get $argv_buf) (i32.const 4)) (i32.const 114))
    (i32.store8 (i32.add (local.get $argv_buf) (i32.const 5)) (i32.const 97))
    (i32.store8 (i32.add (local.get $argv_buf) (i32.const 6)) (i32.const 109))
    (i32.store8 (i32.add (local.get $argv_buf) (i32.const 7)) (i32.const 0))

    ;; Write "arg1" at argv_buf + 8
    (i32.store8 (i32.add (local.get $argv_buf) (i32.const 8)) (i32.const 97))
    (i32.store8 (i32.add (local.get $argv_buf) (i32.const 9)) (i32.const 114))
    (i32.store8 (i32.add (local.get $argv_buf) (i32.const 10)) (i32.const 103))
    (i32.store8 (i32.add (local.get $argv_buf) (i32.const 11)) (i32.const 49))
    (i32.store8 (i32.add (local.get $argv_buf) (i32.const 12)) (i32.const 0))

    ;; Write "arg2" at argv_buf + 13
    (i32.store8 (i32.add (local.get $argv_buf) (i32.const 13)) (i32.const 97))
    (i32.store8 (i32.add (local.get $argv_buf) (i32.const 14)) (i32.const 114))
    (i32.store8 (i32.add (local.get $argv_buf) (i32.const 15)) (i32.const 103))
    (i32.store8 (i32.add (local.get $argv_buf) (i32.const 16)) (i32.const 50))
    (i32.store8 (i32.add (local.get $argv_buf) (i32.const 17)) (i32.const 0))

    (return (i32.const 0))
  )

  (func (export "test") (result i32)
    (call $args_get (i32.const 100) (i32.const 200))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 3: Combined - get sizes then get args
(module
  (memory 2)

  (func $args_sizes_get (param i32 i32) (result i32)
    (i32.store (local.get 0) (i32.const 3))
    (i32.store (local.get 1) (i32.const 18))
    (return (i32.const 0))
  )

  (func $args_get (param i32 i32) (result i32)
    (local $argv i32)
    (local $argv_buf i32)
    (local.set $argv (local.get 0))
    (local.set $argv_buf (local.get 1))

    (i32.store (local.get $argv) (local.get $argv_buf))
    (i32.store (i32.add (local.get $argv) (i32.const 4))
              (i32.add (local.get $argv_buf) (i32.const 8)))
    (i32.store (i32.add (local.get $argv) (i32.const 8))
              (i32.add (local.get $argv_buf) (i32.const 12)))
    (return (i32.const 0))
  )

  (func (export "test") (result i32)
    (drop (call $args_sizes_get (i32.const 100) (i32.const 104)))
    (call $args_get (i32.const 200) (i32.const 300))
  )
)
(assert_return (invoke "test") (i32.const 0))
