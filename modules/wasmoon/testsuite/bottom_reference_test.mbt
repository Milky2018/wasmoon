///|
test "bottom references: non-null ref.test rejects null and inhabited values" {
  let source =
    #|(module
    #| (type $s (struct))
    #| (func (export "test") (result i32)
    #|   (ref.test (ref none) (ref.null any))
    #|   (ref.test (ref none) (struct.new_default $s)) i32.or
    #|   (ref.test (ref none) (ref.i31 (i32.const 42))) i32.or))
  assert_eq(@testsuite.run_interp_only(source, "test", []), Ok([I32(0)]))
  for level in [0, 2, 3] {
    inspect(
      @testsuite.compare_jit_interp_with_opt_level(source, "test", [], level),
      content="matched",
    )
  }
}

///|
test "bottom references: explicit nullable tests and casts accept null" {
  let source =
    #|(module
    #| (func (export "test") (result i32)
    #|   (ref.test (ref null none) (ref.null any))
    #|   (ref.is_null (ref.cast (ref null none) (ref.null any))) i32.and))
  assert_eq(@testsuite.run_interp_only(source, "test", []), Ok([I32(1)]))
  for level in [0, 2, 3] {
    inspect(
      @testsuite.compare_jit_interp_with_opt_level(source, "test", [], level),
      content="matched",
    )
  }
}

///|
test "bottom references: non-null casts compile and trap on null" {
  let source =
    #|(module
    #| (func (export "test") (result i32)
    #|   ref.null any ref.cast (ref none) drop i32.const 42))
  for level in [0, 2, 3] {
    assert_true(
      @testsuite.compare_result_errors_contain(
        @testsuite.compare_jit_interp_with_opt_level(source, "test", [], level),
        "cast failure",
      ),
    )
  }
}
