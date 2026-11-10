///|
test "guarded scalar reference calls preserve hits misses and null traps" {
  let source =
    #|(module
    #| (type $t (func (param i32) (result i32)))
    #| (func $fast (type $t) local.get 0 i32.const 1 i32.add)
    #| (func $other (type $t)
    #|   local.get 0 if (result i32)
    #|     local.get 0 i32.const 2 i32.add
    #|   else i32.const 99 end)
    #| (elem declare func $fast $other)
    #| (func (export "test") (param $which i32) (result i32)
    #|   (local $f (ref null $t))
    #|   local.get $which i32.const 2 i32.eq
    #|   if (result (ref null $t)) ref.null $t
    #|   else local.get $which
    #|     if (result (ref $t)) ref.func $fast else ref.func $other end
    #|   end local.set $f
    #|   i32.const 40 local.get $f call_ref $t))
  for level in [0, 2, 3] {
    for which in [0, 1] {
      assert_true(
        @testsuite.compare_result_is_match(
          @testsuite.compare_jit_interp_with_opt_level(
            source,
            "test",
            [I32(which)],
            level,
          ),
        ),
      )
    }
    assert_true(
      @testsuite.compare_result_errors_contain(
        @testsuite.compare_jit_interp_with_opt_level(
          source,
          "test",
          [I32(2)],
          level,
        ),
        "null",
      ),
    )
  }
}

///|
test "reference loop versions retain zero trips allocation order and indirect misses" {
  let source =
    #|(module
    #| (type $t (func (param i32) (result i32)))
    #| (type $box (struct (field i32)))
    #| (func $fast (type $t) local.get 0 i32.const 1 i32.add)
    #| (func $other (type $t)
    #|   local.get 0 if (result i32)
    #|     local.get 0 i32.const 2 i32.add
    #|   else i32.const 99 end)
    #| (elem declare func $fast $other)
    #| (func (export "test") (param $which i32) (param $count i32) (result i32)
    #|   (local $f (ref null $t)) (local $i i32) (local $sum i32)
    #|   local.get $which i32.const 2 i32.eq
    #|   if (result (ref null $t)) ref.null $t
    #|   else local.get $which
    #|     if (result (ref $t)) ref.func $fast else ref.func $other end
    #|   end local.set $f
    #|   block $exit loop $loop
    #|     local.get $i local.get $count i32.ge_s br_if $exit
    #|     local.get $i struct.new $box drop
    #|     local.get $sum local.get $f call_ref $t local.set $sum
    #|     local.get $i i32.const 1 i32.add local.set $i
    #|     br $loop
    #|   end end local.get $sum))
  for level in [0, 2, 3] {
    for (which, count) in [(0, 0), (1, 0), (2, 0), (0, 32), (1, 32)] {
      assert_true(
        @testsuite.compare_result_is_match(
          @testsuite.compare_jit_interp_with_opt_level(
            source,
            "test",
            [I32(which), I32(count)],
            level,
          ),
        ),
      )
    }
    assert_true(
      @testsuite.compare_result_errors_contain(
        @testsuite.compare_jit_interp_with_opt_level(
          source,
          "test",
          [I32(2), I32(3)],
          level,
        ),
        "null",
      ),
    )
  }
}
