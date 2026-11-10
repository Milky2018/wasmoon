///|
test "loop cast motion preserves zero-trip nulls and field mutations" {
  for setup in ["ref.null $s", "i32.const 7 struct.new $s"] {
    let source =
      $|(module (type $s (struct (field (mut i32))))
      $| (func (export "test") (param $count i32) (result i32)
      $|   (local $p (ref null $s)) (local $i i32)
      $|   \{setup} local.set $p
      $|   (block $done (loop $again
      $|     local.get $i local.get $count i32.ge_u br_if $done
      $|     local.get $p ref.cast (ref $s) local.get $i struct.set $s 0
      $|     local.get $i i32.const 1 i32.add local.set $i br $again))
      $|   local.get $i))
    for level in [0, 2, 3] {
      for count in [0, 1, 8] {
        let comparison = @testsuite.compare_jit_interp_with_opt_level(
          source,
          "test",
          [I32(count)],
          level,
        )
        if setup == "ref.null $s" && count > 0 {
          assert_true(
            @testsuite.compare_result_errors_contain(comparison, "cast"),
          )
        } else {
          assert_true(@testsuite.compare_result_is_match(comparison))
          assert_eq(
            @testsuite.run_interp_only(source, "test", [I32(count)]).unwrap(),
            [I32(count)],
          )
        }
      }
    }
  }
}
