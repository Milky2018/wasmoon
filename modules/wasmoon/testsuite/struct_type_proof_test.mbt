///|
test "struct type reuse preserves conditional nulls bounds and the first trap" {
  let source =
    #|(module
    #| (type $bytes (array (mut i8)))
    #| (type $s (struct (field (ref null $bytes)) (field (mut i32))))
    #| (func (export "test") (param $limit i32) (param $null i32) (result i32)
    #|  (local $s (ref null $s)) (local $a (ref null $bytes))
    #|  (local $i i32) (local $sum i32)
    #|  local.get $null i32.const 2 i32.ne
    #|  if i32.const 42 i32.const 8 array.new $bytes local.set $a end
    #|  local.get $null i32.const 1 i32.ne
    #|  if local.get $a i32.const 0 struct.new $s local.set $s end
    #|  local.get $s struct.get $s 1 drop
    #|  i32.const 1024 array.new_default $bytes drop
    #|  (block $done (loop $again
    #|   local.get $i local.get $limit i32.ge_s br_if $done
    #|   local.get $s struct.get $s 0 array.len drop
    #|   local.get $sum local.get $s struct.get $s 0 local.get $i
    #|   array.get_u $bytes i32.add local.set $sum
    #|   local.get $i i32.const 1 i32.add local.set $i br $again))
    #|  local.get $s struct.get $s 0 drop local.get $sum))
  for level in [0, 2, 3] {
    for (limit, null_) in [(0, 0), (1, 0), (8, 0), (0, 2)] {
      let result = @testsuite.compare_jit_interp_with_opt_level(
        source,
        "test",
        [I32(limit), I32(null_)],
        level,
      )
      assert_true(result.matched(), msg="O\{level}: \{result}")
    }
    for
      (limit, null_, error) in [
        (0, 1, "null reference"),
        (1, 2, "null reference"),
        (9, 0, "bounds"),
      ] {
      assert_true(
        @testsuite.compare_result_errors_contain(
          @testsuite.compare_jit_interp_with_opt_level(
            source,
            "test",
            [I32(limit), I32(null_)],
            level,
          ),
          error,
        ),
      )
    }
  }
}

///|
test "struct type reuse retains mutable fields and subtype prefix layouts" {
  let source =
    #|(module
    #| (type $base (sub (struct (field (mut i32)) (field i64))))
    #| (type $child (sub $base (struct (field (mut i32)) (field i64) (field i32))))
    #| (type $bytes (array (mut i8)))
    #| (func $read (param $object (ref $base)) (result i32)
    #|  local.get $object struct.get $base 1 drop
    #|  local.get $object i32.const 42 struct.set $base 0
    #|  i32.const 1024 array.new_default $bytes drop
    #|  local.get $object struct.get $base 0)
    #| (func (export "test") (result i32)
    #|  i32.const 7 i64.const 99 i32.const 123 struct.new $child call $read))
  for level in [0, 2, 3] {
    let result = @testsuite.compare_jit_interp_with_opt_level(
      source,
      "test",
      [],
      level,
    )
    assert_true(result.matched(), msg="O\{level}: \{result}")
  }
}
