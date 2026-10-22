///|
test "gc bulk: packed vector and reference ranges agree in interpreter and JIT" {
  let source =
    #|(module
    #| (type $s (struct (field i32)))
    #| (type $r (array (mut (ref null $s))))
    #| (type $b (array (mut i8)))
    #| (type $v (array (mut v128)))
    #| (func (export "test") (result i32)
    #|  (local $b (ref $b)) (local $v (ref $v)) (local $r (ref $r))
    #|  (local.set $b (array.new_default $b (i32.const 8)))
    #|  (array.fill $b (local.get $b) (i32.const 0) (i32.const -1) (i32.const 8))
    #|  (array.copy $b $b (local.get $b) (i32.const 1) (local.get $b) (i32.const 0) (i32.const 7))
    #|  (local.set $v (array.new_default $v (i32.const 4)))
    #|  (array.fill $v (local.get $v) (i32.const 1) (v128.const i32x4 1 2 3 42) (i32.const 2))
    #|  (array.copy $v $v (local.get $v) (i32.const 0) (local.get $v) (i32.const 1) (i32.const 3))
    #|  (local.set $r (array.new_default $r (i32.const 4)))
    #|  (array.fill $r (local.get $r) (i32.const 1) (struct.new $s (i32.const 42)) (i32.const 2))
    #|  (array.copy $r $r (local.get $r) (i32.const 0) (local.get $r) (i32.const 1) (i32.const 3))
    #|  (i32.add
    #|   (i32.add (array.get_s $b (local.get $b) (i32.const 7))
    #|    (i32x4.extract_lane 3 (array.get $v (local.get $v) (i32.const 0))))
    #|   (struct.get $s 0 (array.get $r (local.get $r) (i32.const 0))))))
  for level in [0, 2] {
    let result = @testsuite.compare_jit_interp_with_opt_level(
      source,
      "test",
      [],
      level,
    )
    inspect(result, content="matched")
  }
  assert_eq(@testsuite.run_interp_only(source, "test", []), Ok([I32(83)]))
}
