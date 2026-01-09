;; WASI Random Tests
;; Tests random_get

;; Mock WASI module that provides testable implementations
(module $wasi_snapshot_preview1
  (global $last_errno (mut i32) (i32.const 0))
  (global $random_seed (mut i64) (i64.const 12345))

  (memory (export "memory") 1)

  ;; Simple PRNG for testing
  (func $prng_step (result i64)
    (local $new_seed i64)
    (local.set $new_seed (i64.mul (global.get $random_seed) (i64.const 1103515245)))
    (local.set $new_seed (i64.add (local.get $new_seed) (i64.const 12345)))
    (global.set $random_seed (local.get $new_seed))
    (local.get $new_seed)
  )

  ;; random_get(buf, buf_len) -> errno
  (func (export "random_get") (param i32 i32) (result i32)
    (local $buf i32)
    (local $buf_len i32)
    (local $i i32)
    (local $rand i64)

    (local.set $buf (local.get 0))
    (local.set $buf_len (local.get 1))

    ;; Validate buffer length
    (if (i32.eqz (local.get $buf_len))
      (then
        ;; Empty buffer is ok
        (global.set $last_errno (i32.const 0))
        (return (i32.const 0))
      )
    )

    ;; Fill buffer with random bytes
    (local.set $i (i32.const 0))
    (block $break (loop $continue
      (if (i32.ge_u (local.get $i) (local.get $buf_len))
        (then (br $break))
      )

      ;; Get random byte
      (local.set $rand (call $prng_step))
      (i32.store8 (i32.add (local.get $buf) (local.get $i))
                  (i32.wrap_i64 (local.get $rand)))

      ;; Increment i
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br $continue)
    ))

    (global.set $last_errno (i32.const 0))
    (return (i32.const 0))
  )

  ;; Helper to get last errno
  (func (export "get_last_errno") (result i32)
    (global.get $last_errno)
  )
)

;; Register the WASI module so subsequent modules can import from it
(register "wasi_snapshot_preview1" $wasi_snapshot_preview1)

;; Test 1: random_get with 8 bytes
(module
  (import "wasi_snapshot_preview1" "random_get" (func $random_get (param i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    ;; Get 8 random bytes at address 100
    (call $random_get (i32.const 100) (i32.const 8))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 2: random_get with 0 bytes (should succeed)
(module
  (import "wasi_snapshot_preview1" "random_get" (func $random_get (param i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    ;; Get 0 random bytes
    (call $random_get (i32.const 100) (i32.const 0))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 3: random_get with 32 bytes
(module
  (import "wasi_snapshot_preview1" "random_get" (func $random_get (param i32 i32) (result i32)))
  (memory 2)

  (func (export "test") (result i32)
    ;; Get 32 random bytes at address 200
    (call $random_get (i32.const 200) (i32.const 32))
  )
)
(assert_return (invoke "test") (i32.const 0))
