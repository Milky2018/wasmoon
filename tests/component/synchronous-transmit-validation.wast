
;; stream.read: invalid-buffer
(component
 (type $T (stream u8))
 (core module $Memory (memory (export "memory") 1))
 (core instance $memory (instantiate $Memory))
 (core func $new (canon stream.new $T))
 (core func $op (canon stream.read $T (memory $memory "memory")))
 (core func $drop (canon stream.drop-writable $T))
 (core module $M
  (import "" "new" (func $new (result i64)))
  (import "" "op" (func $op (param i32 i32 i32) (result i32)))
  (import "" "drop" (func $drop (param i32)))
  (func (export "run") (result i32) (local $pair i64)
   i32.const 57005 i32.const -1 i32.const 1 call $op))
 (core instance $m (instantiate $M (with "" (instance
  (export "new" (func $new)) (export "op" (func $op)) (export "drop" (func $drop))))))
 (func (export "run") (result u32) (canon lift (core func $m "run"))))
(assert_trap (invoke "run") "out of bounds")

;; stream.read: invalid-handle
(component
 (type $T (stream u8))
 (core module $Memory (memory (export "memory") 1))
 (core instance $memory (instantiate $Memory))
 (core func $new (canon stream.new $T))
 (core func $op (canon stream.read $T (memory $memory "memory")))
 (core func $drop (canon stream.drop-writable $T))
 (core module $M
  (import "" "new" (func $new (result i64)))
  (import "" "op" (func $op (param i32 i32 i32) (result i32)))
  (import "" "drop" (func $drop (param i32)))
  (func (export "run") (result i32) (local $pair i64)
   i32.const 57005 i32.const 0 i32.const 1 call $op))
 (core instance $m (instantiate $M (with "" (instance
  (export "new" (func $new)) (export "op" (func $op)) (export "drop" (func $drop))))))
 (func (export "run") (result u32) (canon lift (core func $m "run"))))
(assert_trap (invoke "run") "handle index")

;; stream.read: blocked
(component
 (type $T (stream u8))
 (core module $Memory (memory (export "memory") 1))
 (core instance $memory (instantiate $Memory))
 (core func $new (canon stream.new $T))
 (core func $op (canon stream.read $T (memory $memory "memory")))
 (core func $drop (canon stream.drop-writable $T))
 (core module $M
  (import "" "new" (func $new (result i64)))
  (import "" "op" (func $op (param i32 i32 i32) (result i32)))
  (import "" "drop" (func $drop (param i32)))
  (func (export "run") (result i32) (local $pair i64)
   call $new local.set $pair
local.get $pair i32.wrap_i64 i32.const 0 i32.const 1 call $op))
 (core instance $m (instantiate $M (with "" (instance
  (export "new" (func $new)) (export "op" (func $op)) (export "drop" (func $drop))))))
 (func (export "run") (result u32) (canon lift (core func $m "run"))))
(assert_trap (invoke "run") "cannot block a synchronous task before returning")

;; stream.read: ready
(component
 (type $T (stream u8))
 (core module $Memory (memory (export "memory") 1))
 (core instance $memory (instantiate $Memory))
 (core func $new (canon stream.new $T))
 (core func $op (canon stream.read $T (memory $memory "memory")))
 (core func $drop (canon stream.drop-writable $T))
 (core module $M
  (import "" "new" (func $new (result i64)))
  (import "" "op" (func $op (param i32 i32 i32) (result i32)))
  (import "" "drop" (func $drop (param i32)))
  (func (export "run") (result i32) (local $pair i64)
   call $new local.set $pair
local.get $pair i64.const 32 i64.shr_u i32.wrap_i64 call $drop
local.get $pair i32.wrap_i64 i32.const 0 i32.const 1 call $op))
 (core instance $m (instantiate $M (with "" (instance
  (export "new" (func $new)) (export "op" (func $op)) (export "drop" (func $drop))))))
 (func (export "run") (result u32) (canon lift (core func $m "run"))))
(assert_return (invoke "run") (u32.const 1))

;; stream.write: invalid-buffer
(component
 (type $T (stream u8))
 (core module $Memory (memory (export "memory") 1))
 (core instance $memory (instantiate $Memory))
 (core func $new (canon stream.new $T))
 (core func $op (canon stream.write $T (memory $memory "memory")))
 (core func $drop (canon stream.drop-readable $T))
 (core module $M
  (import "" "new" (func $new (result i64)))
  (import "" "op" (func $op (param i32 i32 i32) (result i32)))
  (import "" "drop" (func $drop (param i32)))
  (func (export "run") (result i32) (local $pair i64)
   i32.const 57005 i32.const -1 i32.const 1 call $op))
 (core instance $m (instantiate $M (with "" (instance
  (export "new" (func $new)) (export "op" (func $op)) (export "drop" (func $drop))))))
 (func (export "run") (result u32) (canon lift (core func $m "run"))))
(assert_trap (invoke "run") "out of bounds")

;; stream.write: invalid-handle
(component
 (type $T (stream u8))
 (core module $Memory (memory (export "memory") 1))
 (core instance $memory (instantiate $Memory))
 (core func $new (canon stream.new $T))
 (core func $op (canon stream.write $T (memory $memory "memory")))
 (core func $drop (canon stream.drop-readable $T))
 (core module $M
  (import "" "new" (func $new (result i64)))
  (import "" "op" (func $op (param i32 i32 i32) (result i32)))
  (import "" "drop" (func $drop (param i32)))
  (func (export "run") (result i32) (local $pair i64)
   i32.const 57005 i32.const 0 i32.const 1 call $op))
 (core instance $m (instantiate $M (with "" (instance
  (export "new" (func $new)) (export "op" (func $op)) (export "drop" (func $drop))))))
 (func (export "run") (result u32) (canon lift (core func $m "run"))))
(assert_trap (invoke "run") "handle index")

;; stream.write: blocked
(component
 (type $T (stream u8))
 (core module $Memory (memory (export "memory") 1))
 (core instance $memory (instantiate $Memory))
 (core func $new (canon stream.new $T))
 (core func $op (canon stream.write $T (memory $memory "memory")))
 (core func $drop (canon stream.drop-readable $T))
 (core module $M
  (import "" "new" (func $new (result i64)))
  (import "" "op" (func $op (param i32 i32 i32) (result i32)))
  (import "" "drop" (func $drop (param i32)))
  (func (export "run") (result i32) (local $pair i64)
   call $new local.set $pair
local.get $pair i64.const 32 i64.shr_u i32.wrap_i64 i32.const 0 i32.const 1 call $op))
 (core instance $m (instantiate $M (with "" (instance
  (export "new" (func $new)) (export "op" (func $op)) (export "drop" (func $drop))))))
 (func (export "run") (result u32) (canon lift (core func $m "run"))))
(assert_trap (invoke "run") "cannot block a synchronous task before returning")

;; stream.write: ready
(component
 (type $T (stream u8))
 (core module $Memory (memory (export "memory") 1))
 (core instance $memory (instantiate $Memory))
 (core func $new (canon stream.new $T))
 (core func $op (canon stream.write $T (memory $memory "memory")))
 (core func $drop (canon stream.drop-readable $T))
 (core module $M
  (import "" "new" (func $new (result i64)))
  (import "" "op" (func $op (param i32 i32 i32) (result i32)))
  (import "" "drop" (func $drop (param i32)))
  (func (export "run") (result i32) (local $pair i64)
   call $new local.set $pair
local.get $pair i32.wrap_i64 call $drop
local.get $pair i64.const 32 i64.shr_u i32.wrap_i64 i32.const 0 i32.const 1 call $op))
 (core instance $m (instantiate $M (with "" (instance
  (export "new" (func $new)) (export "op" (func $op)) (export "drop" (func $drop))))))
 (func (export "run") (result u32) (canon lift (core func $m "run"))))
(assert_return (invoke "run") (u32.const 1))

;; future.read: invalid-buffer
(component
 (type $T (future u8))
 (core module $Memory (memory (export "memory") 1))
 (core instance $memory (instantiate $Memory))
 (core func $new (canon future.new $T))
 (core func $op (canon future.read $T (memory $memory "memory")))
 (core func $drop (canon future.drop-writable $T))
 (core module $M
  (import "" "new" (func $new (result i64)))
  (import "" "op" (func $op (param i32 i32) (result i32)))
  (import "" "drop" (func $drop (param i32)))
  (func (export "run") (result i32) (local $pair i64)
   i32.const 57005 i32.const -1 call $op))
 (core instance $m (instantiate $M (with "" (instance
  (export "new" (func $new)) (export "op" (func $op)) (export "drop" (func $drop))))))
 (func (export "run") (result u32) (canon lift (core func $m "run"))))
(assert_trap (invoke "run") "out of bounds")

;; future.read: invalid-handle
(component
 (type $T (future u8))
 (core module $Memory (memory (export "memory") 1))
 (core instance $memory (instantiate $Memory))
 (core func $new (canon future.new $T))
 (core func $op (canon future.read $T (memory $memory "memory")))
 (core func $drop (canon future.drop-writable $T))
 (core module $M
  (import "" "new" (func $new (result i64)))
  (import "" "op" (func $op (param i32 i32) (result i32)))
  (import "" "drop" (func $drop (param i32)))
  (func (export "run") (result i32) (local $pair i64)
   i32.const 57005 i32.const 0 call $op))
 (core instance $m (instantiate $M (with "" (instance
  (export "new" (func $new)) (export "op" (func $op)) (export "drop" (func $drop))))))
 (func (export "run") (result u32) (canon lift (core func $m "run"))))
(assert_trap (invoke "run") "handle index")

;; future.read: blocked
(component
 (type $T (future u8))
 (core module $Memory (memory (export "memory") 1))
 (core instance $memory (instantiate $Memory))
 (core func $new (canon future.new $T))
 (core func $op (canon future.read $T (memory $memory "memory")))
 (core func $drop (canon future.drop-writable $T))
 (core module $M
  (import "" "new" (func $new (result i64)))
  (import "" "op" (func $op (param i32 i32) (result i32)))
  (import "" "drop" (func $drop (param i32)))
  (func (export "run") (result i32) (local $pair i64)
   call $new local.set $pair
local.get $pair i32.wrap_i64 i32.const 0 call $op))
 (core instance $m (instantiate $M (with "" (instance
  (export "new" (func $new)) (export "op" (func $op)) (export "drop" (func $drop))))))
 (func (export "run") (result u32) (canon lift (core func $m "run"))))
(assert_trap (invoke "run") "cannot block a synchronous task before returning")

;; future.read: ready
(component
 (type $T (future u8))
 (core module $Memory (memory (export "memory") 1))
 (core instance $memory (instantiate $Memory))
 (core func $new (canon future.new $T))
 (core func $op (canon future.read $T (memory $memory "memory")))
 (core func $drop (canon future.write $T async (memory $memory "memory")))
 (core module $M
  (import "" "new" (func $new (result i64)))
  (import "" "op" (func $op (param i32 i32) (result i32)))
  (import "" "drop" (func $drop (param i32 i32) (result i32)))
  (func (export "run") (result i32) (local $pair i64)
   call $new local.set $pair
local.get $pair i64.const 32 i64.shr_u i32.wrap_i64 i32.const 0 call $drop drop
local.get $pair i32.wrap_i64 i32.const 0 call $op))
 (core instance $m (instantiate $M (with "" (instance
  (export "new" (func $new)) (export "op" (func $op)) (export "drop" (func $drop))))))
 (func (export "run") (result u32) (canon lift (core func $m "run"))))
(assert_return (invoke "run") (u32.const 0))

;; future.write: invalid-buffer
(component
 (type $T (future u8))
 (core module $Memory (memory (export "memory") 1))
 (core instance $memory (instantiate $Memory))
 (core func $new (canon future.new $T))
 (core func $op (canon future.write $T (memory $memory "memory")))
 (core func $drop (canon future.drop-readable $T))
 (core module $M
  (import "" "new" (func $new (result i64)))
  (import "" "op" (func $op (param i32 i32) (result i32)))
  (import "" "drop" (func $drop (param i32)))
  (func (export "run") (result i32) (local $pair i64)
   i32.const 57005 i32.const -1 call $op))
 (core instance $m (instantiate $M (with "" (instance
  (export "new" (func $new)) (export "op" (func $op)) (export "drop" (func $drop))))))
 (func (export "run") (result u32) (canon lift (core func $m "run"))))
(assert_trap (invoke "run") "out of bounds")

;; future.write: invalid-handle
(component
 (type $T (future u8))
 (core module $Memory (memory (export "memory") 1))
 (core instance $memory (instantiate $Memory))
 (core func $new (canon future.new $T))
 (core func $op (canon future.write $T (memory $memory "memory")))
 (core func $drop (canon future.drop-readable $T))
 (core module $M
  (import "" "new" (func $new (result i64)))
  (import "" "op" (func $op (param i32 i32) (result i32)))
  (import "" "drop" (func $drop (param i32)))
  (func (export "run") (result i32) (local $pair i64)
   i32.const 57005 i32.const 0 call $op))
 (core instance $m (instantiate $M (with "" (instance
  (export "new" (func $new)) (export "op" (func $op)) (export "drop" (func $drop))))))
 (func (export "run") (result u32) (canon lift (core func $m "run"))))
(assert_trap (invoke "run") "handle index")

;; future.write: blocked
(component
 (type $T (future u8))
 (core module $Memory (memory (export "memory") 1))
 (core instance $memory (instantiate $Memory))
 (core func $new (canon future.new $T))
 (core func $op (canon future.write $T (memory $memory "memory")))
 (core func $drop (canon future.drop-readable $T))
 (core module $M
  (import "" "new" (func $new (result i64)))
  (import "" "op" (func $op (param i32 i32) (result i32)))
  (import "" "drop" (func $drop (param i32)))
  (func (export "run") (result i32) (local $pair i64)
   call $new local.set $pair
local.get $pair i64.const 32 i64.shr_u i32.wrap_i64 i32.const 0 call $op))
 (core instance $m (instantiate $M (with "" (instance
  (export "new" (func $new)) (export "op" (func $op)) (export "drop" (func $drop))))))
 (func (export "run") (result u32) (canon lift (core func $m "run"))))
(assert_trap (invoke "run") "cannot block a synchronous task before returning")

;; future.write: ready
(component
 (type $T (future u8))
 (core module $Memory (memory (export "memory") 1))
 (core instance $memory (instantiate $Memory))
 (core func $new (canon future.new $T))
 (core func $op (canon future.write $T (memory $memory "memory")))
 (core func $drop (canon future.drop-readable $T))
 (core module $M
  (import "" "new" (func $new (result i64)))
  (import "" "op" (func $op (param i32 i32) (result i32)))
  (import "" "drop" (func $drop (param i32)))
  (func (export "run") (result i32) (local $pair i64)
   call $new local.set $pair
local.get $pair i32.wrap_i64 call $drop
local.get $pair i64.const 32 i64.shr_u i32.wrap_i64 i32.const 0 call $op))
 (core instance $m (instantiate $M (with "" (instance
  (export "new" (func $new)) (export "op" (func $op)) (export "drop" (func $drop))))))
 (func (export "run") (result u32) (canon lift (core func $m "run"))))
(assert_return (invoke "run") (u32.const 1))
