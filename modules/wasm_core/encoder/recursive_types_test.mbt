///|
fn type_module(payload : Array[Int]) -> Bytes {
  let bytes = [0, 97, 115, 109, 1, 0, 0, 0, 1, payload.length()]
  bytes.append(payload)
  Bytes::makei(bytes.length(), i => bytes[i].to_byte())
}

///|
test "implicit singleton self references parse and retain composite kinds" {
  for
    subtype in [
      [0x60, 1, 0x63, 0, 0],
      [0x5f, 1, 0x63, 0, 0],
      [0x5e, 0x63, 0, 0],
    ] {
    let implicit = [1]
    implicit.append(subtype)
    let explicit = [1, 0x4e, 1]
    explicit.append(subtype)
    let module_ = @parser.parse_module(type_module(implicit))
    let control = @parser.parse_module(type_module(explicit))
    @validator.validate_module(module_)
    assert_eq(module_.types, control.types)
    assert_eq(module_.type_rec_groups, control.type_rec_groups)
    assert_eq(@encoder.encode(module_), @encoder.encode(control))
  }
}

///|
test "singleton groups encode without rec wrappers" {
  for
    subtype in [
      [0x60, 0, 0],
      [0x60, 1, 0x63, 0, 0],
      [0x5f, 1, 0x63, 0, 0],
      [0x5e, 0x63, 0, 0],
      [0x50, 0, 0x5f, 1, 0x63, 0, 0],
    ] {
    let explicit = [1, 0x4e, 1]
    explicit.append(subtype)
    let module_ = @parser.parse_module(type_module(explicit))
    let implicit = [1]
    implicit.append(subtype)
    let encoded = @encoder.encode(module_)
    assert_eq(
      Bytes::makei(encoded.length(), i => encoded[i].to_byte()),
      type_module(implicit),
    )
  }
}

///|
test "roundtrip preserves cycles and separate recursive group identities" {
  // Two mutually recursive structs, a three-type struct/array/function cycle,
  // and two separate self-recursive singletons. No group may be split or merged.
  let input = type_module([
    4, 0x4e, 2, 0x5f, 1, 0x63, 1, 0, 0x5f, 1, 0x63, 0, 0, 0x4e, 3, 0x5f, 1, 0x63,
    3, 0, 0x5e, 0x63, 4, 0, 0x60, 1, 0x63, 2, 0, 0x4e, 1, 0x5f, 1, 0x63, 5, 0, 0x4e,
    1, 0x5f, 1, 0x63, 6, 0,
  ])
  let original = @parser.parse_module(input)
  @validator.validate_module(original)
  let bytes = @encoder.encode(original)
  let roundtrip = @parser.parse_module(
    Bytes::makei(bytes.length(), i => bytes[i].to_byte()),
  )
  @validator.validate_module(roundtrip)
  assert_eq(roundtrip.types, original.types)
  assert_eq(roundtrip.type_rec_groups, original.type_rec_groups)
  assert_eq(roundtrip.types.length(), 7)
  assert_eq(bytes.length(), input.length() - 4)
}

///|
test "implicit groups do not admit references into a later group" {
  let input = type_module([2, 0x5f, 1, 0x63, 1, 0, 0x5f, 0])
  try @parser.parse_module(input) catch {
    _ => ()
  } noraise {
    _ => fail("cross-group forward reference must be rejected")
  }
}
