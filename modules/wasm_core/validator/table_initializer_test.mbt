///|
test "table initializer global scope is validated identically for text and binary" {
  for
    source in [
      "(module (global $g funcref (ref.null func)) (table 1 funcref (global.get $g)))",
      "(module (table 1 funcref (global.get 0)))", "(module (import \"m\" \"g\" (global $g (mut funcref))) (table 1 funcref (global.get $g)))",
      "(module (import \"m\" \"g\" (global funcref)) (global $g funcref (ref.null func)) (table 1 funcref (global.get $g)))",
    ] {
    let text = @wat.parse(source)
    let binary = @parser.parse_module(
      Bytes::from_array(@encoder.encode(text).map(value => value.to_byte())),
    )
    for module_ in [text, binary] {
      try @validator.validate_module(module_) catch {
        InvalidGlobalIndex(_) | MutableGlobalInConstExpr => ()
        error => fail(error.to_string())
      } noraise {
        _ => fail("invalid table initializer passed validation")
      }
      try @validator.validate_module_with_context(module_) catch {
        WithContext(_) => ()
        error => fail(error.to_string())
      } noraise {
        _ => fail("detailed validation accepted an invalid table initializer")
      }
    }
  }
  let valid = @wat.parse(
    "(module (import \"m\" \"g\" (global $g funcref)) (table 1 funcref (global.get $g)))",
  )
  @validator.validate_module(valid)
  @validator.validate_module_with_context(valid)
}
