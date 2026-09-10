;; Capacity is charged to live resources; dropping returns slots.
(component
  (import "wasmtime" (instance $w
    (export "set-max-table-capacity" (func (param "max" u32)))))
  (core func $cap (canon lower (func $w "set-max-table-capacity")))
  (core func $new (canon waitable-set.new))
  (core func $drop (canon waitable-set.drop))
  (core module $m
    (import "" "cap" (func $cap (param i32)))
    (import "" "new" (func $new (result i32)))
    (import "" "drop" (func $drop (param i32)))
    (func (export "run") (local $remaining i32)
      i32.const 100 call $cap
      i32.const 1000 local.set $remaining
      (loop $again
        call $new
        call $drop
        local.get $remaining i32.const 1 i32.sub local.tee $remaining
        br_if $again)))
  (core instance $i (instantiate $m
    (with "" (instance (export "cap" (func $cap))
      (export "new" (func $new)) (export "drop" (func $drop))))))
  (func (export "run") (canon lift (core func $i "run"))))

(assert_return (invoke "run"))

(component
  (import "wasmtime" (instance $w
    (export "set-max-table-capacity" (func (param "max" u32)))))
  (core func $cap (canon lower (func $w "set-max-table-capacity")))
  (core func $new (canon waitable-set.new))
  (core func $drop (canon waitable-set.drop))
  (core module $m
    (import "" "cap" (func $cap (param i32)))
    (import "" "new" (func $new (result i32)))
    (import "" "drop" (func $drop (param i32)))
    (func (export "run") (local $remaining i32)
      i32.const 100 call $cap
      i32.const 1000 local.set $remaining
      (loop $again
        call $new
        drop
        local.get $remaining i32.const 1 i32.sub local.tee $remaining
        br_if $again)))
  (core instance $i (instantiate $m
    (with "" (instance (export "cap" (func $cap))
      (export "new" (func $new)) (export "drop" (func $drop))))))
  (func (export "run") (canon lift (core func $i "run"))))

(assert_trap (invoke "run") "resource table has no free keys")
