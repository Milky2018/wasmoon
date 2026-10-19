(module
(import "spectest" "print_char" (func $boundary (param i32)))
(type $s (struct (field v128)))
(func (export "test") (result i32) (local $i i32) (local $sum i32)
(call $boundary (i32.const 1))
(loop $loop
(local.set $sum (i32.add (local.get $sum) (i32x4.extract_lane 0 (struct.get $s 0 (struct.new $s (i32x4.splat (local.get $i)))))))
(local.set $i (i32.add (local.get $i) (i32.const 1)))
(br_if $loop (i32.lt_u (local.get $i) (i32.const 30000))))
(call $boundary (i32.const 2))
(local.get $sum)))
(assert_return (invoke "test") (i32.const 449985000))
