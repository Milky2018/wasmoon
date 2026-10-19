///|
test "numeric indirect-call type indices are checked after text decoding" {
  for opcode in ["call_indirect", "return_call_indirect"] {
    for
      index in [
        "1", "1012321300", "2147483648", "0x8000_0000", "4294967295", "0xffffffff",
      ] {
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

///|
test "indirect-call type indices require unsigned u32 literal syntax" {
  for opcode in ["call_indirect", "return_call_indirect"] {
    for
      index in ["-1", "-0", "+0", "-2147483648", "4294967296", "0x1_0000_0000"] {
      try
        @wat.parse(
          "(module (table 0 funcref) (func (" +
          opcode +
          " (type " +
          index +
          ") (i32.const 0))))",
        )
      catch {
        InvalidNumber(_, _) => ()
        error => fail(error.to_string())
      } noraise {
        _ => fail("malformed unsigned type index parsed: " + index)
      }
    }
  }
}
