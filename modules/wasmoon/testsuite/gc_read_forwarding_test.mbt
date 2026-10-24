///|
test "optimized GC reads respect aliases calls loops and packed writes" {
  let wat =
    #|(module
    #| (type $s (struct (field (mut i32)) (field (mut i32)) (field (mut i8))))
    #| (type $a (array (mut i32)))
    #| (func $mutate (param $p (ref $s))
    #|   (struct.set $s 0 (local.get $p) (i32.const 42)))
    #| (func (export "test") (result i32)
    #|   (local $s (ref $s)) (local $alias (ref $s))
    #|   (local $a (ref $a)) (local $i i32) (local $sum i32)
    #|   (local.set $s (struct.new $s (i32.const 1) (i32.const 0) (i32.const 0)))
    #|   (local.set $alias (local.get $s))
    #|   (local.set $a (array.new $a (i32.const 0) (i32.const 8)))
    #|   (loop $loop
    #|     (local.set $sum (i32.add (local.get $sum) (struct.get $s 0 (local.get $s))))
    #|     (struct.set $s 1 (local.get $s) (local.get $i))
    #|     (array.set $a (local.get $a) (i32.const 0) (local.get $sum))
    #|     (local.set $sum (i32.add (local.get $sum) (struct.get $s 0 (local.get $s))))
    #|     (struct.set $s 0 (local.get $alias) (i32.add (local.get $i) (i32.const 2)))
    #|     (local.set $i (i32.add (local.get $i) (i32.const 1)))
    #|     (br_if $loop (i32.lt_u (local.get $i) (array.len (local.get $a)))))
    #|   (drop (struct.get $s 0 (local.get $s)))
    #|   (call $mutate (local.get $alias))
    #|   (struct.set $s 2 (local.get $s) (i32.const 511))
    #|   (i32.add (local.get $sum)
    #|     (i32.add (struct.get $s 0 (local.get $s))
    #|       (i32.add (struct.get_s $s 2 (local.get $s))
    #|         (struct.get_u $s 2 (local.get $s)))))))
  for level in [0, 2, 3] {
    let result = @testsuite.compare_jit_interp_with_opt_level(
      wat,
      "test",
      [],
      level,
    )
    assert_true(@testsuite.compare_result_is_match(result))
    debug_inspect(
      @testsuite.run_interp_only(wat, "test", []),
      content="Ok([I32(368)])",
    )
  }
}

///|
test "optimized unused GC reads retain null and array bounds traps" {
  for
    (body, trap) in [
      ("(drop (struct.get $s 0 (ref.null $s))) (i32.const 42)", "null"),
      (
        "(drop (array.get $a (array.new $a (i32.const 0) (i32.const 0)) (i32.const 0))) (i32.const 42)",
        "out of bounds",
      ),
    ] {
    let wat = "(module (type $s (struct (field i32))) (type $a (array (mut i32))) (func (export \"test\") (result i32) \{body}))"
    let result = @testsuite.compare_jit_interp_with_opt_level(
      wat,
      "test",
      [],
      2,
    )
    assert_true(@testsuite.compare_result_errors_contain(result, trap))
  }
}

///|
test "large struct declarations keep checked access beyond the exact view prefix" {
  let fields = Array::make(17, "(field (mut i32))").join(" ")
  let source =
    $|(module (type $large (struct \{fields}))
    $| (func (export "test") (result i32) (local $p (ref $large))
    $|  struct.new_default $large local.set $p
    $|  local.get $p i32.const 42 struct.set $large 16
    $|  local.get $p struct.get $large 16))
  for level in [0, 2, 3] {
    assert_true(
      @testsuite.compare_jit_interp_with_opt_level(source, "test", [], level).matched(),
    )
  }
}
