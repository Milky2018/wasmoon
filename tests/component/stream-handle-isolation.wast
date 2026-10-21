;; Raw integer handles do not transfer endpoint ownership.
(component
 (component $A
  (type $S (stream u8))
  (core func $new (canon stream.new $S))
  (core module $M
   (import "" "new" (func $new (result i64)))
   (func (export "raw") (result i32) call $new i32.wrap_i64))
  (core instance $m (instantiate $M (with "" (instance (export "new" (func $new))))))
  (func (export "raw") (result u32) (canon lift (core func $m "raw"))))
 (component $B
  (import "raw" (func $raw (result u32)))
  (type $S (stream u8))
  (core module $Mem (memory (export "memory") 1))
  (core instance $mem (instantiate $Mem))
  (core func $read (canon stream.read $S async (memory $mem "memory")))
  (core func $raw (canon lower (func $raw)))
  (core module $M
   (import "" "raw" (func $raw (result i32)))
   (import "" "read" (func $read (param i32 i32 i32) (result i32)))
   (func (export "run") (result i32) call $raw i32.const 0 i32.const 1 call $read))
  (core instance $m (instantiate $M (with "" (instance (export "raw" (func $raw)) (export "read" (func $read))))))
  (func (export "run") (result u32) (canon lift (core func $m "run"))))
 (instance $a (instantiate $A))
 (instance $b (instantiate $B (with "raw" (func $a "raw"))))
 (export "run" (func $b "run")))

(assert_trap (invoke "run") "handle")

;; Canonical stream values transfer the readable endpoint to the consumer.
(component
 (component $A
  (type $S (stream u8))
  (core func $new (canon stream.new $S))
  (core module $M
   (import "" "new" (func $new (result i64)))
   (func (export "raw") (result i32) call $new i32.wrap_i64))
  (core instance $m (instantiate $M (with "" (instance (export "new" (func $new))))))
  (func (export "raw") (result (stream u8)) (canon lift (core func $m "raw"))))
 (component $B
  (import "raw" (func $raw (result (stream u8))))
  (type $S (stream u8))
  (core module $Mem (memory (export "memory") 1))
  (core instance $mem (instantiate $Mem))
  (core func $read (canon stream.read $S async (memory $mem "memory")))
  (core func $raw (canon lower (func $raw)))
  (core module $M
   (import "" "raw" (func $raw (result i32)))
   (import "" "read" (func $read (param i32 i32 i32) (result i32)))
   (func (export "run") (result i32) call $raw i32.const 0 i32.const 1 call $read))
  (core instance $m (instantiate $M (with "" (instance (export "raw" (func $raw)) (export "read" (func $read))))))
  (func (export "run") (result u32) (canon lift (core func $m "run"))))
 (instance $a (instantiate $A))
 (instance $b (instantiate $B (with "raw" (func $a "raw"))))
 (export "run" (func $b "run")))

(assert_return (invoke "run") (u32.const 4294967295))
