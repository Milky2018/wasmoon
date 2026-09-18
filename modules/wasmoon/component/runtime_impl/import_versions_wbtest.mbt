///|
test "versioned imports prefer exact names and otherwise the highest compatible stable version" {
  let linker = ComponentLinker()
  defer linker.close()
  linker.add_value("test:pkg/value@0.2.1", U32(1))
  linker.add_value("test:pkg/value@0.2.11", U32(11))
  linker.add_value("test:pkg/value@0.3.0", U32(30))
  linker.add_value("test:pkg/value@0.2.99-rc.1", U32(99))
  for
    (name, expected) in [
      ("test:pkg/value@0.2.1", 1),
      ("test:pkg/value@0.2.4", 11),
      ("test:pkg/value@0.2.20", 11),
      ("test:pkg/value@0.3.1", 30),
      ("test:pkg/value@0.2.99-rc.1", 99),
    ] {
    guard linker.get_import(name) is Some(Value(U32(value))) else { fail(name) }
    assert_eq(value, expected)
  }
  for
    name in [
      "test:pkg/value@0.4.0", "test:pkg/value@0.2.1-rc.2", "test:pkg/value", "other:pkg/value@0.2.1",
    ] {
    assert_true(linker.get_import(name) is None)
  }
}

///|
test "stable major and zero-major version tracks remain distinct" {
  let linker = ComponentLinker()
  defer linker.close()
  linker.add_value("test:pkg/value@1.2.3", U32(1))
  linker.add_value("test:pkg/value@0.0.3", U32(3))
  assert_true(linker.get_import("test:pkg/value@1.9.0") is Some(Value(U32(1))))
  assert_true(linker.get_import("test:pkg/value@2.0.0") is None)
  assert_true(linker.get_import("test:pkg/value@0.0.4") is None)
  assert_true(linker.get_import("test:pkg/value@0.0.3") is Some(Value(U32(3))))
}

///|
test "compatible instance lookup retains resource identity and checks function signatures" {
  let linker = ComponentLinker()
  defer linker.close()
  let runtime = linker.host_runtime_state()
  let resource = linker.new_host_resource_type()
  let builder = linker.host_instance_builder(
    "test:versioned/api@0.2.11", runtime,
  )
  builder.set_type_space([resource])
  builder.add_type("r", 0)
  builder.add_func(
    "value",
    { is_async: false, params: [], result: Some(Prim(U32)), },
    (_, _) => [U32(1)],
  )
  linker.add_instance("test:versioned/api@0.2.11", builder.finish())
  guard resource is Some(ResourceType(expected, _, _, _)) &&
    linker.get_import("test:versioned/api@0.2.4") is Some(Instance(instance)) &&
    instance.get_export("r") is Some(Type(Some(ResourceType(actual, _, _, _)))) else {
    fail("missing compatible resource")
  }
  assert_eq(actual, expected)
  let parsed = @component.parse_component(
    @component_text.parse_component_wat(
      (
        #|(component
        #|  (import "test:versioned/api@0.2.4"
        #|    (instance (export "value" (func (result u64))))))
      ),
    ),
  )
  let validated = @component_validator.validate_component_for_instantiation(
    parsed,
  )
  try linker.instantiate("incompatible", validated) catch {
    ImportTypeMismatch(_) => ()
    error => fail("wrong type error: \{error}")
  } noraise {
    _ => fail("incompatible function type was accepted")
  }
}
