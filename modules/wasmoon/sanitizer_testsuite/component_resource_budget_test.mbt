///|
test "public Component facade preserves allocation denial and can reuse released admission" {
  let source =
    #|(component (core module $m (memory 1)) (core instance $i (instantiate $m)))
  let bytes = @component_text.parse_component_wat(source)
  let empty = @component_text.parse_component_wat("(component)")
  for
    engine in [
      @component.interpreter_component_engine(),
      @component.native_component_engine(opt_level=0),
    ] {
    let budget = @runtime.ResourceBudget::new(memory_bytes=0L)
    let runtime = @component.ComponentRuntime(
      engine~,
      resource_budget=Some(budget),
    )
    defer runtime.close()
    try runtime.instantiate("denied", bytes) catch {
      ResourceLimitExceeded(MemoryBytes) => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("public runtime lost the memory policy")
    }
    assert_eq(budget.used(Instances), 0L)
    assert_eq(budget.used(InputBytes), 0L)
    assert_eq(budget.used(CompilationUnits), 0L)
    runtime.instantiate("healthy", empty) |> ignore
    runtime.close()
    assert_eq(budget.used(Instances), 0L)
    assert_eq(budget.used(InputBytes), 0L)
    assert_eq(budget.used(CompilationUnits), 0L)
  }
}

///|
test "public Component decoder preflights compressed Core expansion and component nesting" {
  // A tiny module expands its one local group to 4096 i32 locals.
  let compressed = b"\x00asm\x0d\x00\x01\x00\x01\x1b\x00asm\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00\x03\x02\x01\x00\x0a\x07\x01\x05\x01\x80\x20\x7f\x0b"
  let budget = @runtime.ResourceBudget::new(
    input_bytes=200L,
    compilation_units=200L,
    compilation_depth=1,
  )
  let runtime = @component.ComponentRuntime(
    engine=@component.interpreter_component_engine(),
    resource_budget=Some(budget),
  )
  defer runtime.close()
  try runtime.instantiate("compressed", compressed) catch {
    ResourceLimitExceeded(CompilationUnits) => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("embedded Core locals expanded before admission")
  }
  let nested = @component_text.parse_component_wat(
    "(component (component (component)))",
  )
  try runtime.instantiate("nested", nested) catch {
    ResourceLimitExceeded(CompilationUnits) => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("component nesting bypassed policy")
  }
  assert_eq(budget.used(InputBytes), 0L)
  assert_eq(budget.used(CompilationUnits), 0L)
  runtime.instantiate(
    "healthy",
    @component_text.parse_component_wat("(component)"),
  )
  |> ignore
}

///|
test "public Component facade classifies compute exhaustion in both engines" {
  let source =
    #|(component
    #|  (core module $m (func (export "run") (loop $spin br $spin)))
    #|  (core instance $i (instantiate $m))
    #|  (func (export "run") (canon lift (core func $i "run"))))
  let bytes = @component_text.parse_component_wat(source)
  for
    engine in [
      @component.interpreter_component_engine(),
      @component.native_component_engine(opt_level=0),
    ] {
    let budget = @runtime.ResourceBudget::new(pending_work=16L)
    let runtime = @component.ComponentRuntime(
      engine~,
      resource_budget=Some(budget),
    )
    defer runtime.close()
    let function = runtime.instantiate("compute", bytes).bind("run")
    try
      runtime.with_execution_limits(
        () => function.call([]),
        safepoints=Some(16L),
      )
    catch {
      @component.ComponentRuntimeError::ExecutionBudgetExceeded => ()
      error => fail(error.to_string())
    } noraise {
      _ => fail("public component compute ignored its scope")
    }
    runtime.close()
    assert_eq(budget.used(PendingWork), 0L)
    assert_eq(budget.used(Instances), 0L)
    assert_eq(budget.used(CodeBytes), 0L)
  }
}
