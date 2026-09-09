;; Bounds precede realloc, but Unicode validation follows a successful realloc.
(component definition $Ordering
  (component $Target
    (core module $M
      (memory (export "memory") 1)
      (global $allow (mut i32) (i32.const 0))
      (func (export "allow") (global.set $allow (i32.const 1)))
      (func (export "realloc") (param i32 i32 i32 i32) (result i32)
        (if (i32.eqz (global.get $allow)) (then unreachable))
        (global.set $allow (i32.const 0))
        (i32.const 0))
      (func (export "call") (param i32 i32)
        (drop (i32.div_u (i32.const 1) (i32.const 0)))))
    (core instance $m (instantiate $M))
    (func (export "call") (param "text" string)
      (canon lift (core func $m "call")
        (memory (core memory $m "memory")) (realloc (core func $m "realloc"))))
    (func (export "compact") (param "text" string)
      (canon lift (core func $m "call") string-encoding=latin1+utf16
        (memory (core memory $m "memory")) (realloc (core func $m "realloc"))))
    (func (export "allow") (canon lift (core func $m "allow"))))
  (instance $target (instantiate $Target))
  (component $Source
    (import "target" (instance $t
      (export "call" (func (param "text" string)))
      (export "compact" (func (param "text" string)))))
    (core module $Memory
      (memory (export "memory") 1)
      (data (i32.const 0) "\ff"))
    (core instance $memory (instantiate $Memory))
    (core func $lower (canon lower (func $t "call")
      (memory (core memory $memory "memory"))))
    (core func $compact (canon lower (func $t "compact")
      (memory (core memory $memory "memory"))))
    (core module $Call
      (import "" "call" (func $call (param i32 i32)))
      (import "" "compact" (func $compact (param i32 i32)))
      (func (export "compact") (param i32) (call $compact (i32.const 0) (local.get 0)))
      (func (export "call") (param i32)
        (call $call (i32.const 0) (local.get 0))))
    (core instance $call (instantiate $Call (with "" (instance (export "call" (func $lower)) (export "compact" (func $compact))))))
    (func (export "compact") (param "length" u32) (canon lift (core func $call "compact")))
    (func (export "call") (param "length" u32) (canon lift (core func $call "call"))))
  (instance $source (instantiate $Source (with "target" (instance $target))))
  (export "call" (func $source "call"))
  (export "compact" (func $source "compact"))
  (export "allow" (func $target "allow")))

(component instance $Ordering $Ordering)
(assert_trap (invoke "call" (u32.const 1)) "unreachable")
(component instance $Ordering $Ordering)
(assert_trap (invoke "call" (u32.const 65537)) "string content out-of-bounds")
(component instance $Ordering $Ordering)
(assert_trap (invoke "call" (u32.const 0)) "unreachable")
(component instance $Ordering $Ordering)
(assert_return (invoke "allow"))
(assert_trap (invoke "call" (u32.const 1)) "invalid utf8 encoding")

(component instance $Ordering $Ordering)
(assert_return (invoke "allow"))
(assert_trap (invoke "compact" (u32.const 1)) "unreachable")

(component definition $Utf16Ordering
  (component $Target
    (core module $M
      (memory (export "memory") 1)
      (global $allow (mut i32) (i32.const 0))
      (func (export "allow") (global.set $allow (i32.const 1)))
      (func (export "realloc") (param i32 i32 i32 i32) (result i32)
        (if (i32.eqz (global.get $allow)) (then unreachable))
        (global.set $allow (i32.const 0))
        (i32.const 0))
      (func (export "call") (param i32 i32)
        (drop (i32.div_u (i32.const 1) (i32.const 0)))))
    (core instance $m (instantiate $M))
    (func (export "call") (param "text" string)
      (canon lift (core func $m "call")
        (memory (core memory $m "memory")) (realloc (core func $m "realloc"))))
    (func (export "compact") (param "text" string)
      (canon lift (core func $m "call") string-encoding=latin1+utf16
        (memory (core memory $m "memory")) (realloc (core func $m "realloc"))))
    (func (export "allow") (canon lift (core func $m "allow"))))
  (instance $target (instantiate $Target))
  (component $Source
    (import "target" (instance $t
      (export "call" (func (param "text" string)))
      (export "compact" (func (param "text" string)))))
    (core module $Memory
      (memory (export "memory") 1)
      (data (i32.const 0) "\00\d8"))
    (core instance $memory (instantiate $Memory))
    (core func $lower (canon lower (func $t "call") string-encoding=utf16
      (memory (core memory $memory "memory"))))
    (core func $compact (canon lower (func $t "compact") string-encoding=utf16
      (memory (core memory $memory "memory"))))
    (core module $Call
      (import "" "call" (func $call (param i32 i32)))
      (import "" "compact" (func $compact (param i32 i32)))
      (func (export "compact") (param i32) (call $compact (i32.const 0) (local.get 0)))
      (func (export "call") (param i32)
        (call $call (i32.const 0) (local.get 0))))
    (core instance $call (instantiate $Call (with "" (instance (export "call" (func $lower)) (export "compact" (func $compact))))))
    (func (export "compact") (param "length" u32) (canon lift (core func $call "compact")))
    (func (export "call") (param "length" u32) (canon lift (core func $call "call"))))
  (instance $source (instantiate $Source (with "target" (instance $target))))
  (export "call" (func $source "call"))
  (export "compact" (func $source "compact"))
  (export "allow" (func $target "allow")))

(component instance $Utf16Ordering $Utf16Ordering)
(assert_return (invoke "allow"))
(assert_trap (invoke "compact" (u32.const 1)) "unreachable")
(component instance $Utf16Ordering $Utf16Ordering)
(assert_return (invoke "allow"))
(assert_trap (invoke "call" (u32.const 1)) "invalid utf16 encoding")
(component instance $Utf16Ordering $Utf16Ordering)
(assert_trap (invoke "call" (u32.const 1)) "unreachable")
(component instance $Utf16Ordering $Utf16Ordering)
(assert_trap (invoke "call" (u32.const 32769)) "string content out-of-bounds")
