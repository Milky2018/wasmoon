;; Error contexts are cloned i32 handles owned by each component instance.
;; Run with Wasmtime component-model-async and component-model-error-context.

(component
  (component $Lib
    ;; Occupy handle zero with a different message to detect table confusion.
    (core module $Memory
      (memory (export "memory") 1)
      (data (i32.const 0) "other"))
    (core instance $memory (instantiate $Memory))
    (alias core export $memory "memory" (core memory $mem))
    (core func $new (canon error-context.new (memory $mem)))
    (core module $L
      (import "" "new" (func $new (param i32 i32) (result i32)))
      (func $start i32.const 0 i32.const 5 call $new drop)
      (start $start)
      (func (export "id") (param i32) (result i32) local.get 0))
    (core instance $l (instantiate $L (with "" (instance (export "new" (func $new))))))
    (func (export "id") (param "x" error-context) (result error-context)
      (canon lift (core func $l "id") )))
  (instance $lib (instantiate $Lib))
  (core module $Memory
    (memory (export "memory") 1)
    (data (i32.const 0) "hello")
    (global $heap (mut i32) (i32.const 1024))
    (func (export "realloc") (param i32 i32 i32 i32) (result i32)
      (local $p i32)
      global.get $heap local.set $p
      global.get $heap local.get 3 i32.add i32.const 15 i32.add i32.const -16 i32.and global.set $heap
      local.get $p))
  (core instance $memory (instantiate $Memory))
  (alias core export $memory "memory" (core memory $mem))
  (core func $new (canon error-context.new (memory $mem)))
  (core func $drop (canon error-context.drop))
  (core func $debug (canon error-context.debug-message (memory $mem) (realloc (func $memory "realloc"))))
  (core func $id (canon lower (func $lib "id") ))
  (core module $M
    (import "" "mem" (memory 1))
    (import "" "new" (func $new (param i32 i32) (result i32)))
    (import "" "drop" (func $drop (param i32)))
    (import "" "debug" (func $debug (param i32 i32)))
    (import "" "id" (func $id (param i32) (result i32)))
    (func (export "run") (result i32) (local $a i32) (local $b i32)
      i32.const 0 i32.const 5 call $new local.set $a
      local.get $a call $id local.set $b
      local.get $a call $drop
      local.get $b i32.const 80 call $debug
      i32.const 84 i32.load i32.const 5 i32.ne if unreachable end
      i32.const 80 i32.load i32.load8_u i32.const 104 i32.ne if unreachable end
      local.get $b call $drop
      i32.const 42))
  (core instance $m (instantiate $M (with "" (instance
    (export "mem" (memory $mem))
    (export "new" (func $new)) (export "drop" (func $drop))
    (export "debug" (func $debug)) (export "id" (func $id))))))
  (func (export "run") (result u32) (canon lift (core func $m "run"))))

(assert_return (invoke "run") (u32.const 42))

(component
  (component $Lib
    (core module $Memory
    (memory (export "memory") 1)
    (data (i32.const 0) "hello")
    (global $heap (mut i32) (i32.const 1024))
    (func (export "realloc") (param i32 i32 i32 i32) (result i32)
      (local $p i32)
      global.get $heap local.set $p
      global.get $heap local.get 3 i32.add i32.const 15 i32.add i32.const -16 i32.and global.set $heap
      local.get $p))
  (core instance $memory (instantiate $Memory))
  (alias core export $memory "memory" (core memory $mem))
    (core module $L (import "" "mem" (memory 1))
      (func (export "id") (param i32 i32 i32) (result i32) i32.const 64 local.get 0 i32.store8
        i32.const 68 local.get 1 i32.store
        i32.const 72 local.get 2 i32.store
        i32.const 64))
    (core instance $l (instantiate $L (with "" (instance (export "mem" (memory $mem))))))
    (func (export "id") (param "x" (tuple u8 error-context u32)) (result (tuple u8 error-context u32))
      (canon lift (core func $l "id") (memory $mem) (realloc (func $memory "realloc")))))
  (instance $lib (instantiate $Lib))
  (core module $Memory
    (memory (export "memory") 1)
    (data (i32.const 0) "hello")
    (global $heap (mut i32) (i32.const 1024))
    (func (export "realloc") (param i32 i32 i32 i32) (result i32)
      (local $p i32)
      global.get $heap local.set $p
      global.get $heap local.get 3 i32.add i32.const 15 i32.add i32.const -16 i32.and global.set $heap
      local.get $p))
  (core instance $memory (instantiate $Memory))
  (alias core export $memory "memory" (core memory $mem))
  (core func $new (canon error-context.new (memory $mem)))
  (core func $drop (canon error-context.drop))
  (core func $debug (canon error-context.debug-message (memory $mem) (realloc (func $memory "realloc"))))
  (core func $id (canon lower (func $lib "id") (memory $mem) (realloc (func $memory "realloc"))))
  (core module $M
    (import "" "mem" (memory 1))
    (import "" "new" (func $new (param i32 i32) (result i32)))
    (import "" "drop" (func $drop (param i32)))
    (import "" "debug" (func $debug (param i32 i32)))
    (import "" "id" (func $id (param i32 i32 i32 i32) ))
    (func (export "run") (result i32) (local $a i32) (local $b i32)
      i32.const 0 i32.const 5 call $new local.set $a
      i32.const 7 local.get $a i32.const 99 i32.const 64 call $id
      i32.const 64 i32.load8_u i32.const 7 i32.ne if unreachable end
      i32.const 72 i32.load i32.const 99 i32.ne if unreachable end
      i32.const 68 i32.load local.set $b
      local.get $a call $drop
      local.get $b i32.const 80 call $debug
      i32.const 84 i32.load i32.const 5 i32.ne if unreachable end
      i32.const 80 i32.load i32.load8_u i32.const 104 i32.ne if unreachable end
      local.get $b call $drop
      i32.const 42))
  (core instance $m (instantiate $M (with "" (instance
    (export "mem" (memory $mem))
    (export "new" (func $new)) (export "drop" (func $drop))
    (export "debug" (func $debug)) (export "id" (func $id))))))
  (func (export "run") (result u32) (canon lift (core func $m "run"))))

(assert_return (invoke "run") (u32.const 42))

(component
  (component $Lib
    (core module $Memory
    (memory (export "memory") 1)
    (data (i32.const 0) "hello")
    (global $heap (mut i32) (i32.const 1024))
    (func (export "realloc") (param i32 i32 i32 i32) (result i32)
      (local $p i32)
      global.get $heap local.set $p
      global.get $heap local.get 3 i32.add i32.const 15 i32.add i32.const -16 i32.and global.set $heap
      local.get $p))
  (core instance $memory (instantiate $Memory))
  (alias core export $memory "memory" (core memory $mem))
    (core module $L (import "" "mem" (memory 1))
      (func (export "id") (param i32 i32) (result i32) i32.const 64 local.get 0 i32.store
        i32.const 68 local.get 1 i32.store
        i32.const 64))
    (core instance $l (instantiate $L (with "" (instance (export "mem" (memory $mem))))))
    (func (export "id") (param "x" (list error-context)) (result (list error-context))
      (canon lift (core func $l "id") (memory $mem) (realloc (func $memory "realloc")))))
  (instance $lib (instantiate $Lib))
  (core module $Memory
    (memory (export "memory") 1)
    (data (i32.const 0) "hello")
    (global $heap (mut i32) (i32.const 1024))
    (func (export "realloc") (param i32 i32 i32 i32) (result i32)
      (local $p i32)
      global.get $heap local.set $p
      global.get $heap local.get 3 i32.add i32.const 15 i32.add i32.const -16 i32.and global.set $heap
      local.get $p))
  (core instance $memory (instantiate $Memory))
  (alias core export $memory "memory" (core memory $mem))
  (core func $new (canon error-context.new (memory $mem)))
  (core func $drop (canon error-context.drop))
  (core func $debug (canon error-context.debug-message (memory $mem) (realloc (func $memory "realloc"))))
  (core func $id (canon lower (func $lib "id") (memory $mem) (realloc (func $memory "realloc"))))
  (core module $M
    (import "" "mem" (memory 1))
    (import "" "new" (func $new (param i32 i32) (result i32)))
    (import "" "drop" (func $drop (param i32)))
    (import "" "debug" (func $debug (param i32 i32)))
    (import "" "id" (func $id (param i32 i32 i32) ))
    (func (export "run") (result i32) (local $a i32) (local $b i32)
      i32.const 0 i32.const 5 call $new local.set $a
      i32.const 32 local.get $a i32.store
      i32.const 36 local.get $a i32.store
      i32.const 32 i32.const 2 i32.const 64 call $id
      i32.const 68 i32.load i32.const 2 i32.ne if unreachable end
      i32.const 64 i32.load i32.load local.set $b
      i32.const 64 i32.load i32.const 4 i32.add i32.load call $drop
      local.get $a call $drop
      local.get $b i32.const 80 call $debug
      i32.const 84 i32.load i32.const 5 i32.ne if unreachable end
      i32.const 80 i32.load i32.load8_u i32.const 104 i32.ne if unreachable end
      local.get $b call $drop
      i32.const 42))
  (core instance $m (instantiate $M (with "" (instance
    (export "mem" (memory $mem))
    (export "new" (func $new)) (export "drop" (func $drop))
    (export "debug" (func $debug)) (export "id" (func $id))))))
  (func (export "run") (result u32) (canon lift (core func $m "run"))))

(assert_return (invoke "run") (u32.const 42))

(component
  (component $Lib

    (core module $L
      (func (export "id") (param i32) (result i32) local.get 0))
    (core instance $l (instantiate $L ))
    (func (export "id") (param "x" error-context) (result error-context)
      (canon lift (core func $l "id") )))
  (instance $lib (instantiate $Lib))
  (core module $Memory
    (memory (export "memory") 1)
    (data (i32.const 0) "hello")
    (global $heap (mut i32) (i32.const 1024))
    (func (export "realloc") (param i32 i32 i32 i32) (result i32)
      (local $p i32)
      global.get $heap local.set $p
      global.get $heap local.get 3 i32.add i32.const 15 i32.add i32.const -16 i32.and global.set $heap
      local.get $p))
  (core instance $memory (instantiate $Memory))
  (alias core export $memory "memory" (core memory $mem))
  (core func $new (canon error-context.new (memory $mem)))
  (core func $drop (canon error-context.drop))
  (core func $debug (canon error-context.debug-message (memory $mem) (realloc (func $memory "realloc"))))
  (core func $id (canon lower (func $lib "id") ))
  (core module $M
    (import "" "mem" (memory 1))
    (import "" "new" (func $new (param i32 i32) (result i32)))
    (import "" "drop" (func $drop (param i32)))
    (import "" "debug" (func $debug (param i32 i32)))
    (import "" "id" (func $id (param i32) (result i32)))
    (func (export "run") (result i32) (local $a i32) (local $b i32)
      i32.const 123 local.set $a
      local.get $a call $id local.set $b
      local.get $a call $drop
      local.get $b i32.const 80 call $debug
      i32.const 84 i32.load i32.const 5 i32.ne if unreachable end
      i32.const 80 i32.load i32.load8_u i32.const 104 i32.ne if unreachable end
      local.get $b call $drop
      i32.const 42))
  (core instance $m (instantiate $M (with "" (instance
    (export "mem" (memory $mem))
    (export "new" (func $new)) (export "drop" (func $drop))
    (export "debug" (func $debug)) (export "id" (func $id))))))
  (func (export "run") (result u32) (canon lift (core func $m "run"))))

(assert_trap (invoke "run") "unknown handle index")

;; Seventeen flat parameters force both argument and result indirection.
(component
  (component $Lib
    (core module $Memory
    (memory (export "memory") 1)
    (data (i32.const 0) "hello")
    (global $heap (mut i32) (i32.const 1024))
    (func (export "realloc") (param i32 i32 i32 i32) (result i32)
      (local $p i32)
      global.get $heap local.set $p
      global.get $heap local.get 3 i32.add i32.const 15 i32.add i32.const -16 i32.and global.set $heap
      local.get $p))
  (core instance $memory (instantiate $Memory))
  (alias core export $memory "memory" (core memory $mem))
    (core module $L (import "" "mem" (memory 1))
      (func (export "id") (param i32) (result i32) local.get 0))
    (core instance $l (instantiate $L (with "" (instance (export "mem" (memory $mem))))))
    (func (export "id") (param "x" (tuple u32 u32 u32 u32 u32 u32 u32 u32 u32 u32 u32 u32 u32 u32 u32 u32 error-context)) (result (tuple u32 u32 u32 u32 u32 u32 u32 u32 u32 u32 u32 u32 u32 u32 u32 u32 error-context))
      (canon lift (core func $l "id") (memory $mem) (realloc (func $memory "realloc")))))
  (instance $lib (instantiate $Lib))
  (core module $Memory
    (memory (export "memory") 1)
    (data (i32.const 0) "hello")
    (global $heap (mut i32) (i32.const 1024))
    (func (export "realloc") (param i32 i32 i32 i32) (result i32)
      (local $p i32)
      global.get $heap local.set $p
      global.get $heap local.get 3 i32.add i32.const 15 i32.add i32.const -16 i32.and global.set $heap
      local.get $p))
  (core instance $memory (instantiate $Memory))
  (alias core export $memory "memory" (core memory $mem))
  (core func $new (canon error-context.new (memory $mem)))
  (core func $drop (canon error-context.drop))
  (core func $debug (canon error-context.debug-message (memory $mem) (realloc (func $memory "realloc"))))
  (core func $id (canon lower (func $lib "id") (memory $mem) (realloc (func $memory "realloc"))))
  (core module $M
    (import "" "mem" (memory 1))
    (import "" "new" (func $new (param i32 i32) (result i32)))
    (import "" "drop" (func $drop (param i32)))
    (import "" "debug" (func $debug (param i32 i32)))
    (import "" "id" (func $id (param i32 i32) ))
    (func (export "run") (result i32) (local $a i32) (local $b i32)
      i32.const 0 i32.const 5 call $new local.set $a
      i32.const 32 i32.const 1 i32.store
      i32.const 36 i32.const 2 i32.store
      i32.const 40 i32.const 3 i32.store
      i32.const 44 i32.const 4 i32.store
      i32.const 48 i32.const 5 i32.store
      i32.const 52 i32.const 6 i32.store
      i32.const 56 i32.const 7 i32.store
      i32.const 60 i32.const 8 i32.store
      i32.const 64 i32.const 9 i32.store
      i32.const 68 i32.const 10 i32.store
      i32.const 72 i32.const 11 i32.store
      i32.const 76 i32.const 12 i32.store
      i32.const 80 i32.const 13 i32.store
      i32.const 84 i32.const 14 i32.store
      i32.const 88 i32.const 15 i32.store
      i32.const 92 i32.const 16 i32.store
      i32.const 96 local.get $a i32.store
      i32.const 32 i32.const 128 call $id
      i32.const 128 i32.load i32.const 1 i32.ne if unreachable end
      i32.const 132 i32.load i32.const 2 i32.ne if unreachable end
      i32.const 136 i32.load i32.const 3 i32.ne if unreachable end
      i32.const 140 i32.load i32.const 4 i32.ne if unreachable end
      i32.const 144 i32.load i32.const 5 i32.ne if unreachable end
      i32.const 148 i32.load i32.const 6 i32.ne if unreachable end
      i32.const 152 i32.load i32.const 7 i32.ne if unreachable end
      i32.const 156 i32.load i32.const 8 i32.ne if unreachable end
      i32.const 160 i32.load i32.const 9 i32.ne if unreachable end
      i32.const 164 i32.load i32.const 10 i32.ne if unreachable end
      i32.const 168 i32.load i32.const 11 i32.ne if unreachable end
      i32.const 172 i32.load i32.const 12 i32.ne if unreachable end
      i32.const 176 i32.load i32.const 13 i32.ne if unreachable end
      i32.const 180 i32.load i32.const 14 i32.ne if unreachable end
      i32.const 184 i32.load i32.const 15 i32.ne if unreachable end
      i32.const 188 i32.load i32.const 16 i32.ne if unreachable end
      i32.const 192 i32.load local.set $b
      local.get $a call $drop
      local.get $b i32.const 80 call $debug
      i32.const 84 i32.load i32.const 5 i32.ne if unreachable end
      i32.const 80 i32.load i32.load8_u i32.const 104 i32.ne if unreachable end
      local.get $b call $drop
      i32.const 42))
  (core instance $m (instantiate $M (with "" (instance
    (export "mem" (memory $mem))
    (export "new" (func $new)) (export "drop" (func $drop))
    (export "debug" (func $debug)) (export "id" (func $id))))))
  (func (export "run") (result u32) (canon lift (core func $m "run"))))

(assert_return (invoke "run") (u32.const 42))
