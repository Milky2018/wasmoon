///|
test "prepared Component code survives independent cancellation and terminal teardown" {
  let source =
    #|(component
    #| (core module $M
    #|  (global $g (mut i32) (i32.const 41))
    #|  (func (export "run") (param i32) (result i32)
    #|   local.get 0 if (loop $spin br $spin) end
    #|   global.get $g i32.const 1 i32.add global.set $g global.get $g))
    #| (core instance $m (instantiate $M))
    #| (func (export "run") (param "spin" u32) (result u32)
    #|  (canon lift (core func $m "run"))))
  let validated = @component_validator.validate_component_for_instantiation_with_config(
    @component_types.parse_component(
      @component_text.parse_component_wat(source),
    ),
    ComponentValidationConfig(false),
  )
  let code = @component_native.prepare_native_component_code(
    [validated],
    opt_level=0,
  )
  let budget = @runtime.ResourceBudget::new()
  let first = @runtime_impl.ComponentLinker::with_core_execution_engine(
    code.open_session(),
    resource_budget=Some(budget),
  )
  defer first.close()
  let second = @runtime_impl.ComponentLinker::with_core_execution_engine(
    code.open_session(),
  )
  defer second.close()
  let a = first.instantiate("first", validated)
  let b = second.instantiate("second", validated)
  assert_true(a.call_exported_func("run", [U32(0)]) is [U32(42)])
  assert_true(b.call_exported_func("run", [U32(0)]) is [U32(42)])
  assert_true(budget.used(CodeBytes) > 0L)
  let polls = Ref(0)
  try
    first
    .get_store()
    .with_execution_limits(
      () => a.call_exported_func("run", [U32(1)]),
      cancel=Some(fn() {
        polls.val += 1
        polls.val > 8
      }),
    )
  catch {
    @runtime_impl.ComponentRuntimeError::Cancelled => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("prepared code lost cancellation checks")
  }
  first.close()
  assert_eq(budget.used(CodeBytes), 0L)
  assert_eq(budget.used(Instances), 0L)
  try a.call_exported_func("run", [U32(0)]) catch {
    UnknownExport("run") => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("closed prepared session remained callable")
  }
  assert_true(b.call_exported_func("run", [U32(0)]) is [U32(43)])
  let replacement = @runtime_impl.ComponentLinker::with_core_execution_engine(
    code.open_session(),
    resource_budget=Some(budget),
  )
  defer replacement.close()
  let c = replacement.instantiate("replacement", validated)
  assert_true(c.call_exported_func("run", [U32(0)]) is [U32(42)])
  replacement.close()
  assert_eq(budget.used(CodeBytes), 0L)
  assert_eq(budget.used(Instances), 0L)
}
