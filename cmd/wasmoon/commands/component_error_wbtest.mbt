///|
test "component error code mapping: enum string is stable" {
  inspect(
    component_error_code_string(CompUnsupported),
    content="COMP_UNSUPPORTED",
  )
}

///|
test "component error code mapping: validate unsupported -> COMP_UNSUPPORTED" {
  inspect(
    component_error_code_string(
      component_validation_error_code(
        @component_model.UnsupportedComponentImport,
      ),
    ),
    content="COMP_UNSUPPORTED",
  )
}

///|
test "component error json format includes structured fields" {
  let out = component_error_json(
    false,
    Some(CompUnsupported),
    "validate",
    "unsupported component type opcode: 1",
  )
  inspect(out.contains("\"ok\":false"), content="true")
  inspect(out.contains("\"code\":\"COMP_UNSUPPORTED\""), content="true")
  inspect(out.contains("\"phase\":\"validate\""), content="true")
}

///|
test "component command eval: non-component file returns parse error code" {
  let result = run_component_command_eval("README.mbt.md", true, true)
  inspect(result.ok, content="false")
  inspect(
    component_error_code_string(
      match result.code {
        Some(code) => code
        None => fail("expected parse error code")
      },
    ),
    content="COMP_PARSE_ERROR",
  )
}

///|
test "component command eval: minimal component validates ok" {
  let result = run_component_command_eval(
    "testsuite/fixtures/minimal.component.wasm", true, true,
  )
  inspect(result.ok, content="true")
  inspect(result.code is None, content="true")
}
