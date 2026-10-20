///|
fn assert_export_error(
  module_ : @types.Module,
  message : String,
  contextual~ : Bool,
) -> Unit raise {
  try {
    if contextual {
      @validator.validate_module_with_context(module_)
    } else {
      @validator.validate_module(module_)
    }
  } catch {
    UnknownExport(actual) => {
      assert_false(contextual)
      assert_eq(actual, message)
    }
    WithContext(context) => {
      assert_true(contextual)
      assert_eq(context.error_msg, message)
    }
    error => fail(error.to_string())
  } noraise {
    _ => fail("accepted invalid export: \{message}")
  }
}

///|
fn check_tag_export_bounds(contextual~ : Bool) -> Unit raise {
  for
    source in [
      "(module)", "(module (tag (param i32)))", "(module (import \"host\" \"tag\" (tag (param i32))))",
      "(module (import \"host\" \"tag\" (tag (param i32))) (tag (param i32)))",
    ] {
    let module_ = @wat.parse(source)
    let count = module_.tags.length() + module_.imports.length()
    for index in [-1, -2147483648, count, 2147483647] {
      let invalid = module_.snapshot()
      invalid.exports.push({ name: "bad", desc: Tag(index), })
      assert_export_error(invalid, "unknown tag \{index}", contextual~)
    }
    for index in 0..<count {
      module_.exports.push({ name: "tag\{index}", desc: Tag(index), })
    }
    if contextual {
      @validator.validate_module_with_context(module_)
    } else {
      @validator.validate_module(module_)
    }
    @validator.ValidatedModule::new(module_) |> ignore
  }
}

///|
test "ordinary validation rejects negative and out-of-range tag exports" {
  check_tag_export_bounds(contextual=false)
}

///|
test "contextual validation rejects negative and out-of-range tag exports" {
  check_tag_export_bounds(contextual=true)
}

///|
test "protected validation evidence rejects negative tag exports" {
  let module_ = @types.Module::empty()
  module_.exports.push({ name: "bad", desc: Tag(-1), })
  try @validator.ValidatedModule::new(module_) catch {
    UnknownExport(message) => assert_eq(message, "unknown tag -1")
    error => fail(error.to_string())
  } noraise {
    _ => fail("protected validation accepted a negative tag export")
  }
}

///|
test "both validators reject unknown exports of every entity kind" {
  for index in [-1, 0] {
    for
      (kind, desc) in [
        ("function", @types.ExportDesc::Func(index)),
        ("global", Global(index)),
        ("table", Table(index)),
        ("memory", Memory(index)),
      ] {
      let module_ = @types.Module::empty()
      module_.exports.push({ name: "bad", desc, })
      for contextual in [false, true] {
        assert_export_error(module_, "unknown \{kind} \{index}", contextual~)
      }
    }
  }
}

///|
test "both validators reject duplicate export names across entity kinds" {
  let module_ = @wat.parse(
    "(module (func (export \"same\")) (tag (export \"same\") (param i32)))",
  )
  try @validator.validate_module(module_) catch {
    DuplicateExportName(name) => assert_eq(name, "same")
    error => fail(error.to_string())
  } noraise {
    _ => fail("ordinary validation accepted duplicate exports")
  }
  try @validator.validate_module_with_context(module_) catch {
    WithContext(context) =>
      assert_eq(context.error_msg, "duplicate export name: same")
    error => fail(error.to_string())
  } noraise {
    _ => fail("contextual validation accepted duplicate exports")
  }
}
