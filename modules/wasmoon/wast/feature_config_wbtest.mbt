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
    debug_inspect(basic_rejected && contextual_rejected, content="true")
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
    assert_eq((disabled.passed, disabled.failed), (1, 0))
    let enabled = run_wast_commands(script, ".", false, false)
    assert_eq((enabled.passed, enabled.failed), (0, 1))
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
  assert_eq((result.passed, result.failed), (1, 0))
}

///|
test "Wasmtime invalidity profile checks only the typed engine build restriction" {
  let module_ =
    #|(module (type $f (func)) (type $c (cont $f))
    #| (type $s (struct (field (ref null $c))))
    #| (func struct.new_default $s drop))
  @validator.validate_module(@wat.parse(module_), stack_switching=true)
  let assertion = "(assert_invalid " +
    module_ +
    " \"Stack switching feature not compatible with GC\")"
  for use_jit in [false, true] {
    let strict = run_wast_commands(
      parse(assertion),
      ".",
      use_jit,
      false,
      stack_switching=true,
    )
    assert_eq((strict.passed, strict.failed), (0, 1))
    let compatible = run_wast_commands(
      parse(assertion),
      ".",
      use_jit,
      false,
      stack_switching=true,
      wasmtime_validation=true,
    )
    assert_eq((compatible.passed, compatible.failed), (1, 0))
    for
      source in [
        "(assert_invalid (module) \"Stack switching feature not compatible with GC\")",
        "(assert_invalid (module quote \"(module (func i32.const 0e))\") \"Stack switching feature not compatible with GC\")",
        "(assert_invalid " + module_ + " \"unrelated build error\")",
      ] {
      let result = run_wast_commands(
        parse(source),
        ".",
        use_jit,
        false,
        stack_switching=true,
        wasmtime_validation=true,
      )
      assert_eq((result.passed, result.failed), (0, 1))
    }
    let nested = run_wast_commands(
      parse("(thread $child " + assertion + ") (wait $child)"),
      ".",
      use_jit,
      false,
      stack_switching=true,
      wasmtime_validation=true,
    )
    assert_eq((nested.passed, nested.failed), (1, 0))
  }
}
