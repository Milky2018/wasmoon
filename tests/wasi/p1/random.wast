;; WASI Random Tests
;; Tests random_get with REAL WASI implementation (not mock)

;; Test 1: random_get with 8 bytes - returns success
(module
  (import "wasi_snapshot_preview1" "random_get" (func $random_get (param i32 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    ;; Get 8 random bytes at address 100
    (call $random_get (i32.const 100) (i32.const 8))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 2: random_get with 0 bytes (should succeed)
(module
  (import "wasi_snapshot_preview1" "random_get" (func $random_get (param i32 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (call $random_get (i32.const 100) (i32.const 0))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 3: random_get with 32 bytes
(module
  (import "wasi_snapshot_preview1" "random_get" (func $random_get (param i32 i32) (result i32)))
  (memory (export "memory") 2)

  (func (export "test") (result i32)
    (call $random_get (i32.const 200) (i32.const 32))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 4: random_get actually writes bytes (verify not all zeros)
;; We initialize buffer to 0 and check that at least some bytes changed
(module
  (import "wasi_snapshot_preview1" "random_get" (func $random_get (param i32 i32) (result i32)))
  (memory (export "memory") 1)

  ;; Initialize memory at 100-115 to zero (data segment)
  (data (i32.const 100) "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00")

  (func (export "test") (result i32)
    (local $sum i32)
    ;; Get 16 random bytes
    (drop (call $random_get (i32.const 100) (i32.const 16)))

    ;; Sum all bytes - extremely unlikely to be 0 if random
    (local.set $sum (i32.const 0))
    (local.set $sum (i32.add (local.get $sum) (i32.load8_u (i32.const 100))))
    (local.set $sum (i32.add (local.get $sum) (i32.load8_u (i32.const 101))))
    (local.set $sum (i32.add (local.get $sum) (i32.load8_u (i32.const 102))))
    (local.set $sum (i32.add (local.get $sum) (i32.load8_u (i32.const 103))))
    (local.set $sum (i32.add (local.get $sum) (i32.load8_u (i32.const 104))))
    (local.set $sum (i32.add (local.get $sum) (i32.load8_u (i32.const 105))))
    (local.set $sum (i32.add (local.get $sum) (i32.load8_u (i32.const 106))))
    (local.set $sum (i32.add (local.get $sum) (i32.load8_u (i32.const 107))))
    (local.set $sum (i32.add (local.get $sum) (i32.load8_u (i32.const 108))))
    (local.set $sum (i32.add (local.get $sum) (i32.load8_u (i32.const 109))))
    (local.set $sum (i32.add (local.get $sum) (i32.load8_u (i32.const 110))))
    (local.set $sum (i32.add (local.get $sum) (i32.load8_u (i32.const 111))))
    (local.set $sum (i32.add (local.get $sum) (i32.load8_u (i32.const 112))))
    (local.set $sum (i32.add (local.get $sum) (i32.load8_u (i32.const 113))))
    (local.set $sum (i32.add (local.get $sum) (i32.load8_u (i32.const 114))))
    (local.set $sum (i32.add (local.get $sum) (i32.load8_u (i32.const 115))))

    ;; Return 1 if sum > 0, else 0
    (i32.gt_u (local.get $sum) (i32.const 0))
  )
)
(assert_return (invoke "test") (i32.const 1))

;; Test 5: random_get two calls produce different values (with very high probability)
(module
  (import "wasi_snapshot_preview1" "random_get" (func $random_get (param i32 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    ;; Get first 8 bytes at 100
    (drop (call $random_get (i32.const 100) (i32.const 8)))
    ;; Get second 8 bytes at 200
    (drop (call $random_get (i32.const 200) (i32.const 8)))

    ;; Compare the two 64-bit values - should be different with 2^-64 probability of being same
    (i64.ne (i64.load (i32.const 100)) (i64.load (i32.const 200)))
  )
)
(assert_return (invoke "test") (i32.const 1))

;; Test 6: random_get with 1 byte
(module
  (import "wasi_snapshot_preview1" "random_get" (func $random_get (param i32 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (call $random_get (i32.const 100) (i32.const 1))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 7: random_get with large buffer (256 bytes)
(module
  (import "wasi_snapshot_preview1" "random_get" (func $random_get (param i32 i32) (result i32)))
  (memory (export "memory") 2)

  (func (export "test") (result i32)
    (call $random_get (i32.const 100) (i32.const 256))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 8: random_get with very large buffer (4096 bytes)
(module
  (import "wasi_snapshot_preview1" "random_get" (func $random_get (param i32 i32) (result i32)))
  (memory (export "memory") 2)

  (func (export "test") (result i32)
    (call $random_get (i32.const 0) (i32.const 4096))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 9: random_get entropy quality check - verify not all same byte
(module
  (import "wasi_snapshot_preview1" "random_get" (func $random_get (param i32 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (local $first_byte i32)
    (local $all_same i32)

    ;; Get 16 random bytes
    (drop (call $random_get (i32.const 100) (i32.const 16)))

    ;; Check if all bytes are the same as the first byte (very unlikely for true random)
    (local.set $first_byte (i32.load8_u (i32.const 100)))
    (local.set $all_same (i32.const 1))

    ;; Compare each byte with the first
    (if (i32.ne (i32.load8_u (i32.const 101)) (local.get $first_byte))
      (then (local.set $all_same (i32.const 0)))
    )
    (if (i32.ne (i32.load8_u (i32.const 102)) (local.get $first_byte))
      (then (local.set $all_same (i32.const 0)))
    )
    (if (i32.ne (i32.load8_u (i32.const 103)) (local.get $first_byte))
      (then (local.set $all_same (i32.const 0)))
    )
    (if (i32.ne (i32.load8_u (i32.const 104)) (local.get $first_byte))
      (then (local.set $all_same (i32.const 0)))
    )
    (if (i32.ne (i32.load8_u (i32.const 105)) (local.get $first_byte))
      (then (local.set $all_same (i32.const 0)))
    )
    (if (i32.ne (i32.load8_u (i32.const 106)) (local.get $first_byte))
      (then (local.set $all_same (i32.const 0)))
    )
    (if (i32.ne (i32.load8_u (i32.const 107)) (local.get $first_byte))
      (then (local.set $all_same (i32.const 0)))
    )

    ;; Return 1 if NOT all same (good entropy), 0 if all same (bad)
    (i32.xor (local.get $all_same) (i32.const 1))
  )
)
(assert_return (invoke "test") (i32.const 1))

;; Test 10: random_get multiple sequential calls
(module
  (import "wasi_snapshot_preview1" "random_get" (func $random_get (param i32 i32) (result i32)))
  (memory (export "memory") 1)

  (func (export "test") (result i32)
    (local $result i32)
    ;; Multiple calls should all succeed
    (local.set $result (call $random_get (i32.const 0) (i32.const 8)))
    (if (local.get $result) (then (return (local.get $result))))

    (local.set $result (call $random_get (i32.const 8) (i32.const 8)))
    (if (local.get $result) (then (return (local.get $result))))

    (local.set $result (call $random_get (i32.const 16) (i32.const 8)))
    (if (local.get $result) (then (return (local.get $result))))

    (local.set $result (call $random_get (i32.const 24) (i32.const 8)))
    (local.get $result)
  )
)
(assert_return (invoke "test") (i32.const 0))
