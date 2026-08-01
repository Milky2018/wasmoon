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
