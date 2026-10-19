///|
test "numeric indirect-call type indices are checked after text decoding" {
  for opcode in ["call_indirect", "return_call_indirect"] {
    for index in ["1", "1012321300", "0xffffffff"] {
      let module_ = @wat.parse(
        "(module (table 0 funcref) (func (" +
        opcode +
        " (type " +
        index +
        ") (i32.const 0))))",
      )
      try @validator.validate_module(module_) catch {
        InvalidTypeIndex(_) => ()
        error => fail(error.to_string())
      } noraise {
        _ => fail("missing numeric type index passed validation")
      }
    }
    let valid = @wat.parse(
      "(module (type (func)) (table 0 funcref) (func (" +
      opcode +
      " (type 0) (i32.const 0))))",
    )
    @validator.validate_module(valid)
    try
      @wat.parse(
        "(module (table 0 funcref) (func (" +
        opcode +
        " (type $missing) (i32.const 0))))",
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("unresolved type name passed text decoding")
    }
  }
}
