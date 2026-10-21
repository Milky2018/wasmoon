///|
test "function names roundtrip with deterministic index ordering" {
  let module_ = @types.Module::simple([], [], [Nop], "exported")
  module_.func_names.set(0, "叶😀")
  module_.func_names.set(-1, "invalid")
  module_.func_names.set(99, "invalid")
  let encoded = @encoder.encode(module_)
  let decoded = @parser.parse_module(
    Bytes::from_array(encoded.map(x => x.to_byte())),
  )
  assert_eq(decoded.func_names.get(0).unwrap_or("missing"), "叶😀")
  inspect(decoded.func_names.length(), content="1")
  @validator.validate_module(decoded)
  assert_eq(@encoder.encode(decoded), encoded)
}

///|
test "long UTF-8 function names survive repeated binary roundtrips" {
  let module_ = @types.Module::simple([], [], [Nop], "run")
  let name = String::from_array(Array::make(400, '叶')) + "😀"
  module_.func_names.set(0, name)
  let first = @encoder.encode(module_)
  let decoded = @parser.parse_module(
    Bytes::from_array(first.map(x => x.to_byte())),
  )
  assert_eq(decoded.func_names.get(0), Some(name))
  assert_eq(@encoder.encode(decoded), first)
}
