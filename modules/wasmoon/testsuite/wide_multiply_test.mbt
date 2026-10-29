///|
fn wide_multiply_source() -> String {
  (
    #|(module (memory 1)
    #| (func $multiply (param $out i32) (param $a i64) (param $b i64)
    #|   (local $al i64) (local $bl i64) (local $ah i64) (local $bh i64)
    #|   (local $low i64) (local $carry i64) (local $middle i64)
    #|   local.get $a i64.const 4294967295 i64.and local.set $al
    #|   local.get $b i64.const 4294967295 i64.and local.set $bl
    #|   local.get $a i64.const 32 i64.shr_u local.set $ah
    #|   local.get $b i64.const 32 i64.shr_u local.set $bh
    #|   local.get $al local.get $bl i64.mul local.set $low
    #|   local.get $bl local.get $ah i64.mul
    #|   local.get $low i64.const 32 i64.shr_u i64.add local.set $carry
    #|   local.get $bh local.get $al i64.mul
    #|   local.get $carry i64.const 4294967295 i64.and i64.add local.set $middle
    #|   local.get $out
    #|   local.get $bh local.get $ah i64.mul
    #|   local.get $carry i64.const 32 i64.shr_u i64.add
    #|   local.get $middle i64.const 32 i64.shr_u i64.add i64.store offset=8
    #|   local.get $out local.get $low i64.const 4294967295 i64.and
    #|   local.get $middle i64.const 32 i64.shl i64.or i64.store)
    #| (func (export "test") (param i64 i64) (result i64 i64)
    #|   i32.const 0 local.get 0 local.get 1 call $multiply
    #|   i32.const 0 i64.load i32.const 8 i64.load)
    #| (func (export "checksum") (result i64)
    #|   (local $a i64) (local $b i64) (local $sum i64) (local $i i32)
    #|   i64.const 0x123456789abcdef0 local.set $a
    #|   i64.const 0xfedcba9876543210 local.set $b
    #|   loop $again
    #|     local.get $a local.get $a i64.const 13 i64.shl i64.xor local.set $a
    #|     local.get $a local.get $a i64.const 7 i64.shr_u i64.xor local.set $a
    #|     local.get $a local.get $a i64.const 17 i64.shl i64.xor local.set $a
    #|     local.get $b i64.const 6364136223846793005 i64.mul
    #|     i64.const 1442695040888963407 i64.add local.set $b
    #|     i32.const 0 local.get $a local.get $b call $multiply
    #|     local.get $sum i32.const 0 i64.load i32.const 8 i64.load i64.xor
    #|     i64.add local.set $sum
    #|     local.get $i i32.const 1 i32.add local.tee $i
    #|     i32.const 1024 i32.lt_u br_if $again
    #|   end local.get $sum))
  )
}

///|
test "wide unsigned products preserve both halves at integer boundaries" {
  for opt_level in [0, 2, 3] {
    for
      (a, b, low, high) in [
        (0L, 0L, 0L, 0L),
        (1L, -1L, -1L, 0L),
        (-1L, -1L, 1L, -2L),
        (-9223372036854775808L, 2L, 0L, 1L),
        (-9223372036854775808L, -9223372036854775808L, 0L, 4611686018427387904L),
        (4294967295L, 4294967295L, -8589934591L, 0L),
        (4294967296L, 4294967296L, 0L, 1L),
      ] {
      let result = @testsuite.compare_jit_interp_with_opt_level(
        wide_multiply_source(),
        "test",
        [I64(a), I64(b)],
        opt_level,
      )
      inspect(result, content="matched")
      assert_eq(
        @testsuite.run_interp_only(wide_multiply_source(), "test", [
          I64(a),
          I64(b),
        ]),
        Ok([I64(low), I64(high)]),
      )
    }
  }
}

///|
test "wide product random checksum agrees with arbitrary precision arithmetic" {
  for opt_level in [0, 2, 3] {
    let result = @testsuite.compare_jit_interp_with_opt_level(
      wide_multiply_source(),
      "checksum",
      [],
      opt_level,
    )
    inspect(result, content="matched")
    // Independently computed with unsigned arbitrary-precision products; the
    // interpreter still executes the original limb decomposition.
    assert_eq(
      @testsuite.run_interp_only(wide_multiply_source(), "checksum", []),
      Ok([I64(-3416368657776049373L)]),
    )
  }
}

///|
test "near-miss wide products retain their original arithmetic" {
  let source = wide_multiply_source()
  for
    source in [
      source.replace_all(old="4294967295", new="4294967294"),
      source.replace_all(old="i64.const 32", new="i64.const 31"),
      source.replace_all(old="i64.shr_u", new="i64.shr_s"),
      source.replace_all(
        old="local.get $bh local.get $ah i64.mul",
        new="local.get $bh local.get $al i64.mul",
      ),
      source.replace_all(
        old="local.get $al local.get $bl i64.mul",
        new="local.get $al local.get $al i64.mul",
      ),
    ] {
    for opt_level in [2, 3] {
      inspect(
        @testsuite.compare_jit_interp_with_opt_level(
          source,
          "checksum",
          [],
          opt_level,
        ),
        content="matched",
      )
    }
  }
}
