///|
test "canonical lowering preserves host exit status across core execution" {
  for status in [0, 1, 7, 125] {
    let linker = ComponentLinker()
    defer linker.close()
    let runtime = linker.host_runtime_state()
    let builder = linker.host_instance_builder("test:exit/host@0.2.11", runtime)
    builder.add_func("exit", { is_async: false, params: [], result: None, }, (
      _,
      _,
    ) => raise HostExit(status))
    linker.add_instance("test:exit/host@0.2.11", builder.finish())
    let parsed = @component.parse_component(
      @component_text.parse_component_wat(
        (
          #|(component
          #|  (import "test:exit/host@0.2.4" (instance $host (export "exit" (func))))
          #|  (core func $exit (canon lower (func $host "exit")))
          #|  (core module $M
          #|    (import "" "exit" (func $exit))
          #|    (func (export "run") call $exit))
          #|  (core instance $m (instantiate $M (with "" (instance (export "exit" (func $exit))))))
          #|  (func (export "run") (canon lift (core func $m "run"))))
        ),
      ),
    )
    let instance = linker.instantiate(
      "exit-test",
      @component_validator.validate_component_for_instantiation(parsed),
    )
    try instance.call_exported_func("run", []) catch {
      HostExit(actual) => assert_eq(actual, status)
      error => fail("expected HostExit, got \{error}")
    } noraise {
      _ => fail("guest should exit")
    }
  }
}
