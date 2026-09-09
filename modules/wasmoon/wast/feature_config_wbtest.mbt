///|
test "bulk memory feature rejects instructions and passive segments" {
  for
    source in [
      "(module (memory 1) (table 1 funcref) (data (i32.const 0) \"\") (func $f) (elem (i32.const 0) func $f) (func unreachable memory.init 0))",
      "(module (memory 1) (table 1 funcref) (data (i32.const 0) \"\") (func $f) (elem (i32.const 0) func $f) (func unreachable data.drop 0))",
      "(module (memory 1) (table 1 funcref) (data (i32.const 0) \"\") (func $f) (elem (i32.const 0) func $f) (func unreachable memory.copy))",
      "(module (memory 1) (table 1 funcref) (data (i32.const 0) \"\") (func $f) (elem (i32.const 0) func $f) (func unreachable memory.fill))",
      "(module (memory 1) (table 1 funcref) (data (i32.const 0) \"\") (func $f) (elem (i32.const 0) func $f) (func unreachable table.init 0))",
      "(module (memory 1) (table 1 funcref) (data (i32.const 0) \"\") (func $f) (elem (i32.const 0) func $f) (func unreachable elem.drop 0))",
      "(module (memory 1) (table 1 funcref) (data (i32.const 0) \"\") (func $f) (elem (i32.const 0) func $f) (func unreachable table.copy))",
      "(module (memory 1) (data \"\"))", "(module (func $f) (elem func $f))", "(module (func $f) (elem declare func $f))",
    ] {
    let mod_ = @wat.parse(source)
    @validator.validate_module(mod_)
    @validator.validate_module_with_context(mod_)
    let basic_rejected = try {
      @validator.validate_module(mod_, bulk_memory=false)
      false
    } catch {
      _ => true
    }
    let contextual_rejected = try {
      @validator.validate_module_with_context(mod_, bulk_memory=false)
      false
    } catch {
      _ => true
    }
    inspect(basic_rejected && contextual_rejected, content="true")
    let script = parse(
      "(assert_invalid " + source + " \"bulk memory support is not enabled\")",
    )
    let disabled = run_wast_commands(
      script,
      ".",
      false,
      false,
      bulk_memory=false,
    )
    inspect((disabled.passed, disabled.failed), content="(1, 0)")
    let enabled = run_wast_commands(script, ".", false, false)
    inspect((enabled.passed, enabled.failed), content="(0, 1)")
  }
}

///|
test "disabled bulk memory retains active table64 elements and reference table operations" {
  let source =
    #|(module (memory 1) (table i64 1 funcref)
    #|  (func $f) (elem (i64.const 0) func $f) (data (i32.const 0) "ok")
    #|  (func (export "check") (result i64)
    #|    i64.const 0 ref.null func table.set
    #|    i64.const 0 table.get drop
    #|    i64.const 0 ref.null func i64.const 1 table.fill
    #|    ref.null func i64.const 0 table.grow drop
    #|    table.size))
    #|(assert_return (invoke "check") (i64.const 1))
  let result = run_wast_commands(
    parse(source),
    ".",
    false,
    false,
    bulk_memory=false,
  )
  inspect((result.passed, result.failed), content="(1, 0)")
}
