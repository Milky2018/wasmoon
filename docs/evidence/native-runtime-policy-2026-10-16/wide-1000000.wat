(module
(type $s (struct (field v128)))
(func (export "test") (result i32) (local $i i32) (local $sum i32)
(loop $loop
(local.set $sum (i32.add (local.get $sum) (i32x4.extract_lane 0 (struct.get $s 0 (struct.new $s (i32x4.splat (local.get $i)))))))
(local.set $i (i32.add (local.get $i) (i32.const 1)))
(br_if $loop (i32.lt_u (local.get $i) (i32.const 1000000))))
(local.get $sum)))