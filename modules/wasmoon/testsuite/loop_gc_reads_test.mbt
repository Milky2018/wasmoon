///|
test "loop GC read motion preserves zero-trip nulls traps and alias mutation" {
  for
    (body, expected) in [
      (
        (
          #|(local $p (ref null $s))
          #|(block $done (loop $again
          #|  i32.const 0 i32.eqz br_if $done
          #|  local.get $p struct.get $s 0 drop br $again))
          #|i32.const 42
        ),
        42,
      ),
      (
        (
          #|(local $p (ref $s)) (local $i i32) (local $sum i32)
          #|i32.const 7 i32.const 0 struct.new $s local.set $p
          #|local.get $p struct.get $s 1 drop
          #|(loop $again
          #| local.get $sum local.get $p struct.get $s 0 i32.add local.set $sum
          #| local.get $p local.get $i struct.set $s 1
          #| local.get $i i32.const 1 i32.add local.tee $i
          #| i32.const 150 i32.lt_u br_if $again)
          #|local.get $sum
        ),
        1050,
      ),
      (
        (
          #|(local $p (ref $s)) (local $alias (ref $s))
          #|(local $i i32) (local $sum i32)
          #|i32.const 0 i32.const 0 struct.new $s local.tee $p local.set $alias
          #|local.get $p struct.get $s 1 drop
          #|(loop $again
          #| local.get $alias local.get $i struct.set $s 0
          #| local.get $sum local.get $p struct.get $s 0 i32.add local.set $sum
          #| local.get $i i32.const 1 i32.add local.tee $i
          #| i32.const 10 i32.lt_u br_if $again)
          #|local.get $sum
        ),
        45,
      ),
    ] {
    let wat = "(module (type $s (struct (field (mut i32)) (field (mut i32)))) (func (export \"test\") (result i32) \{body}))"
    for level in [0, 2, 3] {
      let result = @testsuite.compare_jit_interp_with_opt_level(
        wat,
        "test",
        [],
        level,
      )
      assert_true(@testsuite.compare_result_is_match(result))
      assert_eq(@testsuite.run_interp_only(wat, "test", []).unwrap(), [
        I32(expected),
      ])
    }
  }
}

///|
test "loop length caching keeps first-use null checks and conditional execution" {
  for
    (setup, limit, expected) in [
      ("ref.null $a", 0, 0),
      ("i32.const 7 i32.const 5 array.new $a", 10, 50),
    ] {
    let wat =
      $|(module (type $a (array (mut i32)))
      $| (func (export "test") (result i32)
      $| (local $a (ref null $a)) (local $i i32) (local $sum i32)
      $| \{setup} local.set $a
      $| (block $done (loop $again
      $|  local.get $i i32.const \{limit} i32.ge_u br_if $done
      $|  local.get $sum local.get $a array.len i32.add local.set $sum
      $|  local.get $i i32.const 1 i32.add local.set $i
      $|  br $again)) local.get $sum))
    for level in [0, 2, 3] {
      let comparison = @testsuite.compare_jit_interp_with_opt_level(
        wat,
        "test",
        [],
        level,
      )
      assert_true(
        @testsuite.compare_result_is_match(comparison),
        msg="O\{level} \{limit}: \{comparison}",
      )
      assert_eq(@testsuite.run_interp_only(wat, "test", []).unwrap(), [
        I32(expected),
      ])
    }
  }
  // The original null check is after a potentially trapping division. Moving
  // the query to the loop preheader would change which trap the guest sees.
  let wat =
    #|(module (type $a (array i32))
    #| (func (export "test") (result i32) (local $a (ref null $a))
    #| (loop $again i32.const 1 i32.const 0 i32.div_s drop
    #|  local.get $a array.len drop br $again) i32.const 42))
  for level in [0, 2, 3] {
    assert_true(
      @testsuite.compare_result_errors_contain(
        @testsuite.compare_jit_interp_with_opt_level(wat, "test", [], level),
        "divide by zero",
      ),
    )
  }
}

///|
test "guarded first-iteration checks preserve dynamic zero-trip null behaviour" {
  let source =
    #|(module (type $s (struct (field i32)))
    #| (func (export "test") (param $limit i32) (result i32)
    #|  (local $p (ref null $s)) (local $i i32)
    #|  (block $done (loop $again
    #|   local.get $i local.get $limit i32.ge_u br_if $done
    #|   local.get $p struct.get $s 0 drop
    #|   local.get $i i32.const 1 i32.add local.set $i br $again))
    #|  i32.const 42))
  for level in [0, 2, 3] {
    assert_true(
      @testsuite.compare_jit_interp_with_opt_level(
        source,
        "test",
        [I32(0)],
        level,
      ).matched(),
    )
    assert_true(
      @testsuite.compare_result_errors_contain(
        @testsuite.compare_jit_interp_with_opt_level(
          source,
          "test",
          [I32(1)],
          level,
        ),
        "null reference",
      ),
    )
  }
}

///|
test "merged loop entries preserve initial values zero trips and alias writes" {
  let source =
    #|(module (type $s (struct (field (mut i32)) (field (mut i32))))
    #| (func (export "test") (param $left i32) (param $limit i32) (param $null i32) (result i32)
    #|  (local $p (ref null $s)) (local $i i32) (local $sum i32)
    #|  local.get $null i32.eqz
    #|  if i32.const 7 i32.const 0 struct.new $s local.set $p end
    #|  local.get $left
    #|  if local.get $limit local.set $i
    #|  else local.get $limit i32.const 1 i32.add local.set $i end
    #|  (block $done (loop $again
    #|   local.get $i i32.const 0 i32.le_s br_if $done
    #|   local.get $sum local.get $p struct.get $s 0 i32.add local.set $sum
    #|   local.get $p local.get $i struct.set $s 1
    #|   local.get $i i32.const 1 i32.sub local.set $i br $again))
    #|  local.get $sum))
  for level in [0, 2, 3] {
    for
      (left, limit, null_, expected) in [
        (1, 0, 1, 0),
        (0, -1, 1, 0),
        (1, 3, 0, 21),
        (0, 3, 0, 28),
      ] {
      let args : Array[@types.Value] = [I32(left), I32(limit), I32(null_)]
      let result = @testsuite.compare_jit_interp_with_opt_level(
        source, "test", args, level,
      )
      assert_true(result.matched(), msg="O\{level}: \{result}")
      assert_eq(@testsuite.run_interp_only(source, "test", args).unwrap(), [
        I32(expected),
      ])
    }
    for left in [0, 1] {
      assert_true(
        @testsuite.compare_result_errors_contain(
          @testsuite.compare_jit_interp_with_opt_level(
            source,
            "test",
            [I32(left), I32(1), I32(1)],
            level,
          ),
          "null reference",
        ),
      )
    }
  }
}

///|
test "dynamic GC loops preserve every exit and ordered array update" {
  let source =
    #|(module (type $a (array (mut i32)))
    #| (func (export "test") (param $count i32) (param $stop i32) (result i32)
    #|  (local $a (ref $a)) (local $i i32) (local $sum i32) (local $value i32)
    #|  i32.const 7 i32.const 12 array.new $a local.set $a
    #|  (block $done (loop $again
    #|   local.get $i local.get $count i32.ge_u br_if $done
    #|   local.get $i local.get $stop i32.eq br_if $done
    #|   local.get $a local.get $i array.get $a local.set $value
    #|   local.get $a local.get $i local.get $value i32.const 1 i32.add array.set $a
    #|   local.get $sum local.get $value i32.add local.set $sum
    #|   local.get $i i32.const 1 i32.add local.set $i br $again))
    #|  local.get $sum i32.const 100 i32.mul
    #|  local.get $a i32.const 0 array.get $a i32.add))
  for count in [0, 1, 2, 3, 7, 12, 13] {
    for stop in [-1, 0, 1, 2, 9] {
      for level in [0, 2, 3] {
        let comparison = @testsuite.compare_jit_interp_with_opt_level(
          source,
          "test",
          [I32(count), I32(stop)],
          level,
        )
        if count == 13 && stop == -1 {
          assert_true(
            @testsuite.compare_result_errors_contain(comparison, "bounds"),
          )
        } else {
          assert_true(@testsuite.compare_result_is_match(comparison))
        }
      }
    }
  }
}

///|
test "private reference box SSA carries fresh objects through calls and backedges" {
  let source =
    #|(module
    #| (type $item (struct (field i32)))
    #| (type $box (struct (field (mut (ref null $item)))))
    #| (type $bytes (array (mut i8)))
    #| (func $allocate i32.const 8192 array.new_default $bytes drop)
    #| (func (export "test") (result i32)
    #|  (local $box (ref null $box)) (local $i i32) (local $sum i32)
    #|  i32.const 42 struct.new $item struct.new $box local.set $box
    #|  (loop $again
    #|   call $allocate
    #|   local.get $sum local.get $box struct.get $box 0 struct.get $item 0
    #|   i32.add local.set $sum
    #|   local.get $box local.get $i i32.const 43 i32.add struct.new $item
    #|   struct.set $box 0
    #|   local.get $i i32.const 1 i32.add local.tee $i
    #|   i32.const 1024 i32.lt_u br_if $again)
    #|  local.get $sum))
  assert_eq(@testsuite.run_interp_only(source, "test", []).unwrap(), [
    I32(566784),
  ])
  for level in [0, 2, 3] {
    assert_true(
      @testsuite.compare_result_is_match(
        @testsuite.compare_jit_interp_with_opt_level(source, "test", [], level),
      ),
    )
  }
}
