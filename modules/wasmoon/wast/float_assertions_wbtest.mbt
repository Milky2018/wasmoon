///|
fn float_expectation(source : String) -> @wat.WastValue raise {
  let script = parse("(assert_return (invoke \"f\") " + source + ")")
  guard script.commands[0].0 is AssertReturn(_, [expected]) else {
    fail("expected one result assertion")
  }
  expected
}

///|
test "floating assertions distinguish zero signs and explicit NaN bits" {
  for
    case in [
      (0, "0", true),
      (0x80000000, "0", false),
      (0x7fc00001, "nan:0x400002", false),
      (0x7f800001, "nan:0x1", true),
      (0xff800001, "nan:0x1", false),
    ] {
    let (actual, expected, matches) = case
    inspect(
      values_match(
        F32(Float::reinterpret_from_int(actual)),
        float_expectation("(f32.const " + expected + ")"),
      ) ==
      matches,
      content="true",
    )
  }
  for
    case in [
      (0L, "0", true),
      (0x8000000000000000L, "0", false),
      (0x7ff8000000000001L, "nan:0x8000000000002", false),
      (0x7ff0000000000001L, "nan:0x1", true),
      (0xfff0000000000001L, "nan:0x1", false),
    ] {
    let (actual, expected, matches) = case
    inspect(
      values_match(
        F64(actual.reinterpret_as_double()),
        float_expectation("(f64.const " + expected + ")"),
      ) ==
      matches,
      content="true",
    )
  }
}

///|
test "NaN patterns require canonical payloads or the quiet bit in every lane" {
  let canon32 = float_expectation("(f32.const nan:canonical)")
  let arith32 = float_expectation("(f32.const nan:arithmetic)")
  let vector_canon32 = float_expectation(
    "(v128.const f32x4 nan:canonical nan:canonical nan:canonical nan:canonical)",
  )
  let vector_arith32 = float_expectation(
    "(v128.const f32x4 nan:arithmetic nan:arithmetic nan:arithmetic nan:arithmetic)",
  )
  for
    case in [
      (0x7fc00000, true, true),
      (0xffc00000, true, true),
      (0x7fc00001, false, true),
      (0x7f800001, false, false),
      (0x7f800000, false, false),
      (0, false, false),
    ] {
    let (bits, canonical, arithmetic) = case
    inspect(
      values_match(F32(Float::reinterpret_from_int(bits)), canon32) == canonical,
      content="true",
    )
    inspect(
      values_match(F32(Float::reinterpret_from_int(bits)), arith32) ==
      arithmetic,
      content="true",
    )
    let bytes = Bytes::from_array(
      Array::makei(16, i => (bits >> (i % 4 * 8)).to_byte()),
    )
    inspect(
      values_match(V128(bytes), vector_canon32) == canonical,
      content="true",
    )
    inspect(
      values_match(V128(bytes), vector_arith32) == arithmetic,
      content="true",
    )
  }
  let canon64 = float_expectation("(f64.const nan:canonical)")
  let arith64 = float_expectation("(f64.const nan:arithmetic)")
  let vector_canon64 = float_expectation(
    "(v128.const f64x2 nan:canonical nan:canonical)",
  )
  let vector_arith64 = float_expectation(
    "(v128.const f64x2 nan:arithmetic nan:arithmetic)",
  )
  for
    case in [
      (0x7ff8000000000000L, true, true),
      (0xfff8000000000000L, true, true),
      (0x7ff8000000000001L, false, true),
      (0x7ff0000000000001L, false, false),
      (0x7ff0000000000000L, false, false),
      (0L, false, false),
    ] {
    let (bits, canonical, arithmetic) = case
    inspect(
      values_match(F64(bits.reinterpret_as_double()), canon64) == canonical,
      content="true",
    )
    inspect(
      values_match(F64(bits.reinterpret_as_double()), arith64) == arithmetic,
      content="true",
    )
    let bytes = Bytes::from_array(
      Array::makei(16, i => (bits >> (i % 8 * 8)).to_int().to_byte()),
    )
    inspect(
      values_match(V128(bytes), vector_canon64) == canonical,
      content="true",
    )
    inspect(
      values_match(V128(bytes), vector_arith64) == arithmetic,
      content="true",
    )
  }
}
