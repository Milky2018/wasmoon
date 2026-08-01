///|
test "failed component instantiation closes native JIT registrations" {
  let provider_bytes = @component_text.parse_component_wat(
    (
      #|(component
      #|  (core module $provider
      #|    (func (export "f") (result i32) (i32.const 7)))
      #|  (core instance $provider (instantiate $provider)))
      #|
    ),
  )
  let provider = @component.parse_component(provider_bytes)
  let provider_validated = @component_validator.validate_component_for_instantiation_with_config(
    provider,
    @component_validator.ComponentValidationConfig(false),
  )
  let bytes = @component_text.parse_component_wat(
    (
      #|(component
      #|  (core module $ok
      #|    (table 1 funcref)
      #|    (memory 1)
      #|    (global i32 (i32.const 1))
      #|    (func (export "f") (result i32) (i32.const 1)))
      #|  (core instance $registered (instantiate $ok))
      #|  (core module $boom (func $start unreachable) (start $start))
      #|  (core instance $trapped (instantiate $boom)))
      #|
    ),
  )
  let component = @component.parse_component(bytes)
  let validated = @component_validator.validate_component_for_instantiation_with_config(
    component,
    @component_validator.ComponentValidationConfig(false),
  )
  let (engine, contexts) = native_component_session_with_contexts(0, fn(
    _event,
  ) {
    ()
  })
  let linker = @runtime_impl.ComponentLinker::with_core_execution_engine(engine)
  linker.instantiate("provider", provider_validated) |> ignore
  let baseline = contexts.length()
  assert_eq(baseline, 1)
  for root_name in ["first", "second"] {
    try linker.instantiate(root_name, validated) catch {
      _ => ()
    } noraise {
      _ => fail("expected core start to trap")
    }
    assert_eq(contexts.length(), baseline)
  }
  linker.close()
}

///|
test "failed native registration cannot reappear at a reused Store index" {
  @wast.clear_funcref_registry()
  defer @wast.clear_funcref_registry()
  let failing_bytes = @component_text.parse_component_wat(
    (
      #|(component
      #|  (core module $old
      #|    (func (export "f") (result i32) (i32.const 1)))
      #|  (core instance $old (instantiate $old))
      #|  (core module $boom (func $start unreachable) (start $start))
      #|  (core instance $trapped (instantiate $boom)))
      #|
    ),
  )
  let failing = @component_validator.validate_component_for_instantiation_with_config(
    @component.parse_component(failing_bytes),
    @component_validator.ComponentValidationConfig(false),
  )
  let failed_linker = @runtime_impl.ComponentLinker::with_core_execution_engine(
    open_native_component_session(opt_level=0),
  )
  try failed_linker.instantiate("failed", failing) catch {
    _ => ()
  } noraise {
    _ => fail("expected core start to trap")
  }
  failed_linker.close()
  let provider_bytes = @component_text.parse_component_wat(
    (
      #|(component
      #|  (core module $new
      #|    (func (export "f") (result i32) (i32.const 2)))
      #|  (core instance $new (instantiate $new)))
      #|
    ),
  )
  let provider = @component_validator.validate_component_for_instantiation_with_config(
    @component.parse_component(provider_bytes),
    @component_validator.ComponentValidationConfig(false),
  )
  let linker = @runtime_impl.ComponentLinker::with_core_execution_engine(
    open_native_component_session(opt_level=0),
  )
  linker.instantiate("new", provider) |> ignore
  assert_eq(
    @wast.collect_registered_funcref_entries(linker.get_store()).length(),
    1,
  )
  linker.close()
}
