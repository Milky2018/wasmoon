(component
  (type $error-code (enum "io" "illegal-byte-sequence" "pipe"))
  (import "wasi:cli/types@0.3.0"
    (instance $types
      (export "error-code" (type (eq $error-code)))))
  (alias export $types "error-code" (type $imported-error-code))
  (type $stdin-stream (stream u8))
  (type $stdin-result (result (error $imported-error-code)))
  (type $stdin-future (future $stdin-result))
  (import "wasi:cli/stdin@0.3.0"
    (instance $stdin
      (export "error-code" (type (eq $imported-error-code)))
      (type $imported-stdin-stream (stream u8))
      (type $imported-stdin-result (result (error $imported-error-code)))
      (type $imported-stdin-future (future $imported-stdin-result))
      (type $imported-stdin-pair
        (tuple $imported-stdin-stream $imported-stdin-future))
      (export "read-via-stream"
        (func (result $imported-stdin-pair)))))
  (alias export $stdin "read-via-stream" (func $read-via-stream))

  (core module $memory-module
    (memory (export "memory") 1))
  (core instance $memory (instantiate $memory-module))
  (core func $read-via-stream-core
    (canon lower (func $read-via-stream)
      (memory (core memory $memory "memory"))))
  (canon stream.read $stdin-stream
    (memory (core memory $memory "memory"))
    (core func $stream-read))
  (canon stream.drop-readable $stdin-stream
    (core func $stream-drop-readable))
  (canon future.read $stdin-future
    (memory (core memory $memory "memory"))
    (core func $future-read))
  (canon future.drop-readable $stdin-future
    (core func $future-drop-readable))

  (core module $module
    (import "" "memory" (memory 1))
    (import "" "read-via-stream" (func $read-via-stream (param i32)))
    (import "" "stream-read"
      (func $stream-read (param i32 i32 i32) (result i32)))
    (import "" "stream-drop-readable"
      (func $stream-drop-readable (param i32)))
    (import "" "future-read"
      (func $future-read (param i32 i32) (result i32)))
    (import "" "future-drop-readable"
      (func $future-drop-readable (param i32)))

    (func (export "run") (result i32)
      (local $stream i32)
      (local $future i32)
      (local $status i32)
      (local $future-status i32)
      (call $read-via-stream (i32.const 0))
      (local.set $stream (i32.load (i32.const 0)))
      (local.set $future (i32.load (i32.const 4)))
      (local.set $status
        (call $stream-read
          (local.get $stream)
          (i32.const 16)
          (i32.const 5)))
      (local.set $future-status
        (call $future-read
          (local.get $future)
          (i32.const 32)))
      (call $stream-drop-readable (local.get $stream))
      (call $future-drop-readable (local.get $future))
      (if (result i32)
        (i32.eq
          (i32.shr_u (local.get $status) (i32.const 4))
          (i32.const 5))
        (then
          (i32.and
            (i32.and
              (i32.eq (local.get $future-status) (i32.const 0))
              (i32.eq
                (i32.load8_u (i32.const 32))
                (i32.const 0)))
            (i32.and
              (i32.eq
                (i32.load (i32.const 16))
                (i32.const 0x6c6c6568))
              (i32.eq
                (i32.load8_u (i32.const 20))
                (i32.const 0x6f)))))
        (else (i32.const 0)))
      (if (result i32)
        (then (i32.const 0))
        (else (i32.const 1)))))

  (core instance $instance
    (instantiate $module
      (with "" (instance
        (export "memory" (memory $memory "memory"))
        (export "read-via-stream" (func $read-via-stream-core))
        (export "stream-read" (func $stream-read))
        (export "stream-drop-readable" (func $stream-drop-readable))
        (export "future-read" (func $future-read))
        (export "future-drop-readable" (func $future-drop-readable))))))
  (type $run-result (result))
  (func $run async (result $run-result)
    (canon lift (core func $instance "run")))
  (instance $run-interface
    (export "run" (func $run)))
  (export "wasi:cli/run@0.3.0" (instance $run-interface))
)
