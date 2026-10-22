///|
test "private GC integer boxes preserve loop and branch values across calls" {
  let wat =
    #|(module
    #| (type $i (struct (field (mut i32))))
    #| (type $l (struct (field (mut i64))))
    #| (func $step (param i64) (result i64) (i64.add (local.get 0) (i64.const 1)))
    #| (func (export "test") (result i64)
    #|  (local $i (ref $i)) (local $l (ref $l))
    #|  (local.set $i (struct.new $i (i32.const 0)))
    #|  (local.set $l (struct.new $l (i64.const 0)))
    #|  (loop $loop
    #|   (if (i32.eqz (i32.and (struct.get $i 0 (local.get $i)) (i32.const 1)))
    #|    (then (struct.set $l 0 (local.get $l)
    #|      (call $step (struct.get $l 0 (local.get $l))))))
    #|   (struct.set $i 0 (local.get $i)
    #|     (i32.add (struct.get $i 0 (local.get $i)) (i32.const 1)))
    #|   (br_if $loop (i32.lt_s (struct.get $i 0 (local.get $i)) (i32.const 100))))
    #|  (i64.add (struct.get $l 0 (local.get $l))
    #|    (i64.extend_i32_u (struct.get $i 0 (local.get $i))))))
  for level in [0, 2, 3] {
    assert_true(
      @testsuite.compare_result_is_match(
        @testsuite.compare_jit_interp_with_opt_level(wat, "test", [], level),
      ),
    )
  }
  debug_inspect(
    @testsuite.run_interp_only(wat, "test", []),
    content="Ok([I64(150)])",
  )
}
