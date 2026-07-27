///|
test "component error code mapping: enum string is stable" {
  inspect(
    component_error_code_string(CompUnsupported),
    content="COMP_UNSUPPORTED",
  )
  inspect(
    component_test_error_code_string(CompTestUnsupportedCommand),
    content="COMP_TEST_UNSUPPORTED_COMMAND",
  )
}

///|
test "component error code mapping: validate unsupported -> COMP_UNSUPPORTED" {
  inspect(
    component_error_code_string(
      component_validation_error_code(UnsupportedComponentImport),
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

///|
test "WASI command status follows run result and structured exit" {
  debug_inspect(
    [
      component_command_status([Variant(0, None)], None),
      component_command_status([Variant(1, None)], None),
      component_command_status([Variant(0, None)], Some(7)),
    ],
    content="[0, 1, 7]",
  )
}

///|
test "WASI command context preserves arguments and environment values" {
  let ctx = component_command_context(
    "command.wasm",
    ["first", "second"],
    ["LANG=C", "EMPTY="],
    [],
    "loopback",
  ) catch {
    e => return fail("could not build command context: \{e}")
  }
  defer ctx.close()
  debug_inspect(
    (ctx.arguments(), ctx.environment()),
    content="([\"command.wasm\", \"first\", \"second\"], [(\"LANG\", \"C\"), (\"EMPTY\", \"\")])",
  )
}

///|
test "component command executes a pinned Preview 2 run export" {
  let status = run_wasi_component_command(
    "testsuite/fixtures/wasi-command-ok.component.wasm",
    ["argument"],
    ["LANG=C"],
    [],
    "deny",
    true,
    Text,
  )
  debug_inspect(status, content="0")
}

///|
test "component command lowers Preview 2 filesystem preopens end to end" {
  let status = run_wasi_component_command(
    "testsuite/fixtures/wasi-command-filesystem.component.wasm",
    [],
    [],
    ["/tmp::/sandbox"],
    "deny",
    true,
    Text,
  )
  debug_inspect(status, content="0")
}

///|
test "component command executes a pinned Preview 3 async run export" {
  let status = run_wasi_component_command(
    "testsuite/fixtures/wasi-command-async-ok.component.wasm",
    [],
    [],
    [],
    "deny",
    true,
    Text,
  )
  debug_inspect(status, content="0")
}

///|
test "component-test json helper includes status fields" {
  let result = ScriptResult::ScriptResult()
  result.add_passed()
  result.add_failed("x")
  let json = component_test_json(
    false,
    Some(CompTestAssertFailed),
    "execute",
    "component-test has failing commands",
    Some(result),
  )
  inspect(json.contains("\"ok\":false"), content="true")
  inspect(json.contains("\"code\":\"COMP_TEST_ASSERT_FAILED\""), content="true")
  inspect(json.contains("\"passed\":1"), content="true")
  inspect(json.contains("\"failed\":1"), content="true")
}

///|
test "component-test returns non-zero on failing assertions" {
  @fs.create_dir("tmp") catch {
    _ => ()
  }
  let path = "tmp/component_test_fail.json"
  let json = "{\"commands\":[{\"type\":\"component\",\"path\":\"testsuite/fixtures/minimal.component.wasm\",\"instantiate\":true},{\"type\":\"assert_return\",\"field\":\"missing\",\"args\":[],\"expected\":[]}]}"
  @fs.write_string_to_file(path, json) catch {
    IOError(e) => fail(e)
  }
  let status = run_component_script(path, Json)
  inspect(status, content="1")
  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
test "component-test returns non-zero on unsupported command" {
  @fs.create_dir("tmp") catch {
    _ => ()
  }
  let path = "tmp/component_test_unsupported.json"
  let json = "{\"commands\":[{\"type\":\"component\",\"path\":\"testsuite/fixtures/minimal.component.wasm\",\"instantiate\":true},{\"type\":\"assert_magic_typo\",\"field\":\"missing\",\"args\":[],\"expected\":[]}]}"
  @fs.write_string_to_file(path, json) catch {
    IOError(e) => fail(e)
  }
  let status = run_component_script(path, Json)
  inspect(status, content="1")
  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
test "component-test returns non-zero on malformed script json" {
  @fs.create_dir("tmp") catch {
    _ => ()
  }
  let path = "tmp/component_test_bad_json.json"
  @fs.write_string_to_file(path, "{\"commands\":[") catch {
    IOError(e) => fail(e)
  }
  let status = run_component_script(path, Json)
  inspect(status, content="1")
  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
test "component-test supports component_definition and component_instance commands" {
  @fs.create_dir("tmp") catch {
    _ => ()
  }
  let path = "tmp/component_test_instance.json"
  let json = "{\"commands\":[{\"type\":\"component_definition\",\"name\":\"$c\",\"path\":\"testsuite/fixtures/minimal.component.wasm\"},{\"type\":\"component_instance\",\"name\":\"$i\",\"component\":\"$c\"}]}"
  @fs.write_string_to_file(path, json) catch {
    IOError(e) => fail(e)
  }
  let status = run_component_script(path, Json)
  inspect(status, content="0")
  @fs.remove_file(path) catch {
    _ => ()
  }
}
