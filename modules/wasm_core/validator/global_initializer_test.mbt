///|
test "contextual module validation checks global initializer types" {
  let module_ = @wat.parse("(module (global i32 (i64.const 0)))")
  try @validator.validate_module(module_) catch {
    TypeMismatch(_) => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("invalid global initializer passed validation")
  }
  try @validator.validate_module_with_context(module_) catch {
    WithContext(details) =>
      inspect(
        details.error_msg,
        content="type mismatch: constant expression: expected I32, got I64",
      )
    error => fail(error.to_string())
  } noraise {
    _ => fail("contextual validation accepted an invalid global initializer")
  }
}

///|
test "try_table catch references require an exception reference label type" {
  for handler in ["catch_ref $tag", "catch_all_ref"] {
    let module_ = @wat.parse(
      "(module (tag $tag) (func (result i32) (block $exit (result i32) (try_table (result i32) (\{handler} $exit) i32.const 1))))",
    )
    try @validator.validate_module(module_) catch {
      TypeMismatch(message) =>
        inspect(message.contains("exception reference"), content="true")
      error => fail(error.to_string())
    } noraise {
      _ =>
        fail("try_table allowed an exception reference to enter an i32 label")
    }
    try @validator.validate_module_with_context(module_) catch {
      WithContext(details) => {
        inspect(details.func_idx == Some(0), content="true")
        inspect(details.instr_offset == Some(0), content="true")
      }
      error => fail(error.to_string())
    } noraise {
      _ => fail("contextual validation allowed the mismatched catch label")
    }
  }
}
