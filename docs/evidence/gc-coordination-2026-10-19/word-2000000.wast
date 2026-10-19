(module
(import "spectest" "print_char" (func $boundary (param i32)))
(type $s (struct (field i64)))
(func (export "test") (result i64) (local $i i32) (local $sum i64)
(call $boundary (i32.const 1))
(loop $loop
(local.set $sum (i64.add (local.get $sum) (struct.get $s 0 (struct.new $s (i64.extend_i32_u (local.get $i))))))
(local.set $i (i32.add (local.get $i) (i32.const 1)))
(br_if $loop (i32.lt_u (local.get $i) (i32.const 2000000))))
(call $boundary (i32.const 2))
(local.get $sum)))
(assert_return (invoke "test") (i64.const 1999999000000))
