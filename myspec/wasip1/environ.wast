;; WASI Environ Tests
;; Tests environ_sizes_get and environ_get

;; Test 1: environ_sizes_get
(module
  (memory 1)

  (func $environ_sizes_get (param i32 i32) (result i32)
    ;; Return environc = 2, environ_buf_size = 22
    (i32.store (local.get 0) (i32.const 2))
    (i32.store (local.get 1) (i32.const 22))
    (return (i32.const 0))
  )

  (func (export "test_environc") (result i32)
    (drop (call $environ_sizes_get (i32.const 100) (i32.const 104)))
    (i32.load (i32.const 100))
  )

  (func (export "test_buf_size") (result i32)
    (drop (call $environ_sizes_get (i32.const 100) (i32.const 104)))
    (i32.load (i32.const 104))
  )
)
(assert_return (invoke "test_environc") (i32.const 2))
(assert_return (invoke "test_buf_size") (i32.const 22))

;; Test 2: environ_get
(module
  (memory 2)

  (func $environ_get (param i32 i32) (result i32)
    (local $environ i32)
    (local $environ_buf i32)
    (local.set $environ (local.get 0))
    (local.set $environ_buf (local.get 1))

    ;; Write environ pointers
    (i32.store (local.get $environ) (local.get $environ_buf))
    (i32.store (i32.add (local.get $environ) (i32.const 4))
              (i32.add (local.get $environ_buf) (i32.const 10)))

    ;; Write "KEY=value" (10 bytes)
    (i32.store8 (local.get $environ_buf) (i32.const 75))
    (i32.store8 (i32.add (local.get $environ_buf) (i32.const 1)) (i32.const 69))
    (i32.store8 (i32.add (local.get $environ_buf) (i32.const 2)) (i32.const 89))
    (i32.store8 (i32.add (local.get $environ_buf) (i32.const 3)) (i32.const 61))
    (i32.store8 (i32.add (local.get $environ_buf) (i32.const 4)) (i32.const 118))
    (i32.store8 (i32.add (local.get $environ_buf) (i32.const 5)) (i32.const 97))
    (i32.store8 (i32.add (local.get $environ_buf) (i32.const 6)) (i32.const 108))
    (i32.store8 (i32.add (local.get $environ_buf) (i32.const 7)) (i32.const 117))
    (i32.store8 (i32.add (local.get $environ_buf) (i32.const 8)) (i32.const 101))
    (i32.store8 (i32.add (local.get $environ_buf) (i32.const 9)) (i32.const 0))

    ;; Write "ANOTHER=data" (12 bytes)
    (i32.store8 (i32.add (local.get $environ_buf) (i32.const 10)) (i32.const 65))
    (i32.store8 (i32.add (local.get $environ_buf) (i32.const 11)) (i32.const 78))
    (i32.store8 (i32.add (local.get $environ_buf) (i32.const 12)) (i32.const 79))
    (i32.store8 (i32.add (local.get $environ_buf) (i32.const 13)) (i32.const 84))
    (i32.store8 (i32.add (local.get $environ_buf) (i32.const 14)) (i32.const 72))
    (i32.store8 (i32.add (local.get $environ_buf) (i32.const 15)) (i32.const 69))
    (i32.store8 (i32.add (local.get $environ_buf) (i32.const 16)) (i32.const 82))
    (i32.store8 (i32.add (local.get $environ_buf) (i32.const 17)) (i32.const 61))
    (i32.store8 (i32.add (local.get $environ_buf) (i32.const 18)) (i32.const 100))
    (i32.store8 (i32.add (local.get $environ_buf) (i32.const 19)) (i32.const 97))
    (i32.store8 (i32.add (local.get $environ_buf) (i32.const 20)) (i32.const 116))
    (i32.store8 (i32.add (local.get $environ_buf) (i32.const 21)) (i32.const 0))

    (return (i32.const 0))
  )

  (func (export "test") (result i32)
    (call $environ_get (i32.const 100) (i32.const 200))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 3: Combined - get sizes then get environ
(module
  (memory 2)

  (func $environ_sizes_get (param i32 i32) (result i32)
    (i32.store (local.get 0) (i32.const 2))
    (i32.store (local.get 1) (i32.const 22))
    (return (i32.const 0))
  )

  (func $environ_get (param i32 i32) (result i32)
    (local $environ i32)
    (local $environ_buf i32)
    (local.set $environ (local.get 0))
    (local.set $environ_buf (local.get 1))

    (i32.store (local.get $environ) (local.get $environ_buf))
    (i32.store (i32.add (local.get $environ) (i32.const 4))
              (i32.add (local.get $environ_buf) (i32.const 10)))
    (return (i32.const 0))
  )

  (func (export "test") (result i32)
    (drop (call $environ_sizes_get (i32.const 100) (i32.const 104)))
    (call $environ_get (i32.const 200) (i32.const 300))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 4: environ_get with empty environ
(module
  (memory 1)

  (func $environ_sizes_get (param i32 i32) (result i32)
    (i32.store (local.get 0) (i32.const 0))
    (i32.store (local.get 1) (i32.const 0))
    (return (i32.const 0))
  )

  (func $environ_get (param i32 i32) (result i32)
    (return (i32.const 0))
  )

  (func (export "test") (result i32)
    (drop (call $environ_sizes_get (i32.const 100) (i32.const 104)))
    (call $environ_get (i32.const 100) (i32.const 200))
  )
)
(assert_return (invoke "test") (i32.const 0))
