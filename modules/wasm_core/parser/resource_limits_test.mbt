///|
fn expanded_locals_binary() -> Bytes {
  b"\x00asm\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00\x03\x02\x01\x00\x0a\x06\x01\x04\x01\x40\x7f\x0b"
}

///|
test "binary decoder bounds expanded work before allocating locals" {
  let bytes = expanded_locals_binary()
  let work = Ref(0L)
  let parsed = @parser.parse_module(
    bytes,
    admit_work=Some(fn(amount) {
      work.val += amount
      true
    }),
  )
  assert_eq(parsed.codes[0].locals.length(), 64)
  assert_true(work.val > bytes.length().to_int64())
  for allowance in [work.val - 1L, work.val, work.val + 1L] {
    try
      @parser.parse_module(bytes, limits={
        max_input_bytes: bytes.length().to_int64(),
        max_work: allowance,
        max_depth: 4,
      })
    catch {
      error => {
        assert_true(error.is_resource_exhaustion())
        assert_eq(allowance, work.val - 1L)
      }
    } noraise {
      module_ => {
        assert_true(allowance >= work.val)
        assert_eq(module_.codes[0].locals.length(), 64)
      }
    }
  }
  try
    @parser.parse_module(bytes, limits={
      max_input_bytes: bytes.length().to_int64() - 1L,
      max_work: work.val,
      max_depth: 4,
    })
  catch {
    error => assert_true(error.is_resource_exhaustion())
  } noraise {
    _ => fail("input quota ignored")
  }
}

///|
test "decoder expression nesting limit is independent of input length" {
  // One empty function with three nested blocks.
  let bytes = b"\x00asm\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00\x03\x02\x01\x00\x0a\x0d\x01\x0b\x00\x02\x40\x02\x40\x02\x40\x0b\x0b\x0b\x0b"
  for depth in [2, 3, 4] {
    try
      @parser.parse_module(bytes, limits={
        max_input_bytes: 100L,
        max_work: 100L,
        max_depth: depth,
      })
    catch {
      error => {
        assert_true(error.is_resource_exhaustion())
        assert_eq(depth, 2)
      }
    } noraise {
      _ => assert_true(depth >= 3)
    }
  }
}
