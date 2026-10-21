(component
  (core module $M (memory (export "mem") 1)
    (data (i32.const 0) "\08\00\00\00\01\00\00\00\00\d8")
    (func (export "get") (result i32) i32.const 0))
  (core instance $m (instantiate $M))
  (alias core export $m "mem" (core memory $mem))
  (func (export "get") (result string) (canon lift (core func $m "get") (memory $mem) string-encoding=utf16)))
(assert_trap (invoke "get") "unpaired surrogate")

(component
  (core module $M (memory (export "mem") 1)
    (data (i32.const 0) "\08\00\00\00\01\00\00\80\00\d8")
    (func (export "get") (result i32) i32.const 0))
  (core instance $m (instantiate $M))
  (alias core export $m "mem" (core memory $mem))
  (func (export "get") (result string) (canon lift (core func $m "get") (memory $mem) string-encoding=latin1+utf16)))
(assert_trap (invoke "get") "unpaired surrogate")

(component
  (core module $M (memory (export "mem") 1)
    (data (i32.const 0) "\08\00\00\00\01\00\00\00\00\dc")
    (func (export "get") (result i32) i32.const 0))
  (core instance $m (instantiate $M))
  (alias core export $m "mem" (core memory $mem))
  (func (export "get") (result string) (canon lift (core func $m "get") (memory $mem) string-encoding=utf16)))
(assert_trap (invoke "get") "unpaired surrogate")

(component
  (core module $M (memory (export "mem") 1)
    (data (i32.const 0) "\08\00\00\00\01\00\00\80\00\dc")
    (func (export "get") (result i32) i32.const 0))
  (core instance $m (instantiate $M))
  (alias core export $m "mem" (core memory $mem))
  (func (export "get") (result string) (canon lift (core func $m "get") (memory $mem) string-encoding=latin1+utf16)))
(assert_trap (invoke "get") "unpaired surrogate")

(component
  (core module $M (memory (export "mem") 1)
    (data (i32.const 0) "\08\00\00\00\02\00\00\00\00\d8\41\00")
    (func (export "get") (result i32) i32.const 0))
  (core instance $m (instantiate $M))
  (alias core export $m "mem" (core memory $mem))
  (func (export "get") (result string) (canon lift (core func $m "get") (memory $mem) string-encoding=utf16)))
(assert_trap (invoke "get") "unpaired surrogate")

(component
  (core module $M (memory (export "mem") 1)
    (data (i32.const 0) "\08\00\00\00\02\00\00\80\00\d8\41\00")
    (func (export "get") (result i32) i32.const 0))
  (core instance $m (instantiate $M))
  (alias core export $m "mem" (core memory $mem))
  (func (export "get") (result string) (canon lift (core func $m "get") (memory $mem) string-encoding=latin1+utf16)))
(assert_trap (invoke "get") "unpaired surrogate")

(component
  (core module $M (memory (export "mem") 1)
    (data (i32.const 0) "\08\00\00\00\02\00\00\00\00\d8\00\d8")
    (func (export "get") (result i32) i32.const 0))
  (core instance $m (instantiate $M))
  (alias core export $m "mem" (core memory $mem))
  (func (export "get") (result string) (canon lift (core func $m "get") (memory $mem) string-encoding=utf16)))
(assert_trap (invoke "get") "unpaired surrogate")

(component
  (core module $M (memory (export "mem") 1)
    (data (i32.const 0) "\08\00\00\00\02\00\00\80\00\d8\00\d8")
    (func (export "get") (result i32) i32.const 0))
  (core instance $m (instantiate $M))
  (alias core export $m "mem" (core memory $mem))
  (func (export "get") (result string) (canon lift (core func $m "get") (memory $mem) string-encoding=latin1+utf16)))
(assert_trap (invoke "get") "unpaired surrogate")

(component
  (core module $M (memory (export "mem") 1)
    (data (i32.const 0) "\08\00\00\00\00\00\00\40")
    (func (export "get") (result i32) i32.const 0))
  (core instance $m (instantiate $M))
  (alias core export $m "mem" (core memory $mem))
  (func (export "get") (result string) (canon lift (core func $m "get") (memory $mem) string-encoding=utf16)))
(assert_trap (invoke "get") "out of bounds")

(component
  (core module $M (memory (export "mem") 1)
    (data (i32.const 0) "\08\00\00\00\00\00\00\c0")
    (func (export "get") (result i32) i32.const 0))
  (core instance $m (instantiate $M))
  (alias core export $m "mem" (core memory $mem))
  (func (export "get") (result string) (canon lift (core func $m "get") (memory $mem) string-encoding=latin1+utf16)))
(assert_trap (invoke "get") "out of bounds")

;; A valid surrogate pair must still produce the original scalar value.
(component
  (core module $M (memory (export "mem") 1)
    (data (i32.const 0) "\08\00\00\00\02\00\00\00\3d\d8\42\de")
    (func (export "get") (result i32) i32.const 0))
  (core instance $m (instantiate $M))
  (alias core export $m "mem" (core memory $mem))
  (func (export "get") (result string)
    (canon lift (core func $m "get") (memory $mem) string-encoding=utf16)))
(assert_return (invoke "get") (str.const "🙂"))
