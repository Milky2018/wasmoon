;; A function reference retains the instance that defines its code.
(module $owner
  (type $get (func (result i32)))
  (global $value (mut i32) (i32.const 11))
  (memory (export "memory") 1)
  (table (export "table") 1 funcref)
  (func $get (export "get") (type $get)
    global.get $value i32.const 1 i32.add global.set $value
    global.get $value)
  (elem (i32.const 0) $get))
(register "owner" $owner)
(module $caller
  (type $get (func (result i32)))
  (import "owner" "table" (table 1 funcref))
  (global (mut i32) (i32.const 90))
  (func (export "indirect") (result i32)
    i32.const 0 call_indirect (type $get)))
(assert_return (invoke $caller "indirect") (i32.const 12))
(assert_return (invoke $owner "get") (i32.const 13))
(assert_return (invoke $caller "indirect") (i32.const 14))

(module $gc-owner
  (type $box (struct (field i32)))
  (type $call (func (result i32)))
  (table (export "table") 1 funcref)
  (func $box (type $call) (result i32)
    i32.const 37 struct.new $box
    ref.cast (ref $box)
    struct.get $box 0)
  (elem (i32.const 0) $box))
(register "gc-owner" $gc-owner)
(module $gc-caller
  (type $padding (array i64))
  (type $call (func (result i32)))
  (import "gc-owner" "table" (table 1 funcref))
  (func (export "call") (result i32)
    i32.const 0 call_indirect (type $call)))
(assert_return (invoke $gc-caller "call") (i32.const 37))

(module $gc-producer
  (type $box (struct (field i32)))
  (type $make (func (result (ref $box))))
  (table (export "table") 1 funcref)
  (func $make (type $make) (result (ref $box))
    i32.const 73 struct.new $box)
  (elem (i32.const 0) $make))
(register "gc-producer" $gc-producer)
(module $gc-consumer
  (type $padding (array i64))
  (type $box (struct (field i32)))
  (type $make (func (result (ref $box))))
  (import "gc-producer" "table" (table 1 funcref))
  (func (export "call") (result i32)
    i32.const 0 call_indirect (type $make)
    ref.cast (ref $box)
    struct.get $box 0))
(assert_return (invoke $gc-consumer "call") (i32.const 73))

(module $tail-owner
  (type $step (func (param i32) (result i32)))
  (global i32 (i32.const 47))
  (table (export "table") 2 funcref)
  (func $step (export "step") (type $step) (param i32) (result i32)
    local.get 0 i32.eqz
    if (result i32)
      global.get 0
    else
      local.get 0 i32.const 1 i32.sub
      i32.const 0 return_call_indirect (type $step)
    end)
  (elem (i32.const 1) $step))
(register "tail-owner" $tail-owner)
(module $tail-caller
  (type $step (func (param i32) (result i32)))
  (import "tail-owner" "table" (table 2 funcref))
  (global i32 (i32.const 83))
  (func $step (export "step") (type $step) (param i32) (result i32)
    local.get 0 i32.eqz
    if (result i32)
      global.get 0
    else
      local.get 0 i32.const 1 i32.sub
      i32.const 1 return_call_indirect (type $step)
    end)
  (elem (i32.const 0) $step))
(assert_return (invoke $tail-caller "step" (i32.const 100001)) (i32.const 47))
(assert_return (invoke $tail-owner "step" (i32.const 100001)) (i32.const 83))

;; A live caller reference remains a precise root while another instance allocates.
(module $allocator
  (type $box (struct (field i64)))
  (func (export "churn") (param $remaining i32)
    (loop $again
      i64.const 1 struct.new $box drop
      local.get $remaining i32.const 1 i32.sub local.tee $remaining
      br_if $again)))
(register "allocator" $allocator)
(module $root-owner
  (type $box (struct (field i32)))
  (import "allocator" "churn" (func $churn (param i32)))
  (func (export "keep") (result i32) (local $root (ref null $box))
    i32.const 91 struct.new $box local.set $root
    i32.const 200000 call $churn
    local.get $root struct.get $box 0))
(assert_return (invoke $root-owner "keep") (i32.const 91))

(module $thrower
  (type $call (func))
  (tag (param i64))
  (tag $shared (export "tag") (param i32))
  (table (export "table") 1 funcref)
  (func $throw (type $call) i32.const 33 throw $shared)
  (elem (i32.const 0) $throw))
(register "thrower" $thrower)
(module $catcher
  (type $call (func))
  (import "thrower" "tag" (tag $shared (param i32)))
  (import "thrower" "table" (table 1 funcref))
  (func (export "catch") (result i32)
    (block $caught (result i32)
      (try_table (catch $shared $caught)
        i32.const 0 call_indirect (type $call))
      i32.const 0)))
(assert_return (invoke $catcher "catch") (i32.const 33))
(assert_return (invoke $catcher "catch") (i32.const 33))

(module $memory-owner
  (type $load (func (result i32)))
  (memory 1)
  (data (i32.const 0) "\2a\00\00\00")
  (table (export "table") 1 funcref)
  (func $load (type $load) (result i32)
    i32.const 0
    i32.const 0 i32.load i32.const 1 i32.add
    i32.store
    i32.const 0 i32.load)
  (elem (i32.const 0) $load))
(register "memory-owner" $memory-owner)
(module $memory-caller
  (type $load (func (result i32)))
  (import "memory-owner" "table" (table 1 funcref))
  (memory 1)
  (data (i32.const 0) "\63\00\00\00")
  (func (export "load") (result i32)
    i32.const 0 call_indirect (type $load)))
(assert_return (invoke $memory-caller "load") (i32.const 43))
(assert_return (invoke $memory-caller "load") (i32.const 44))
