///|
extern "c" fn component_test_executable_mapping_count() -> Int = "wasmoon_jit_exec_mapping_count"

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
test "component script parses named composite values against function types" {
  let types : Array[@component.TypeDef?] = [
    Some(Enum(["red", "green", "blue"])),
    Some(Flags(["a", "b", "c"])),
    Some(
      Variant([
        { label: "number", ty: Some(Prim(U32)), refines: None },
        { label: "text", ty: Some(Prim(String)), refines: None },
      ]),
    ),
    Some(
      Record([
        { label: "color", ty: TypeIdx(0) },
        { label: "features", ty: TypeIdx(1) },
        { label: "payload", ty: TypeIdx(2) },
      ]),
    ),
  ]
  let value : JsonValue = {
    type_: "record",
    value: None,
    label: None,
    labels: None,
    items: Some([
      {
        type_: "variant",
        value: Some("text"),
        label: Some("payload"),
        labels: None,
        items: Some([
          {
            type_: "str",
            value: Some("ok"),
            label: None,
            labels: None,
            items: None,
          },
        ]),
      },
      {
        type_: "flags",
        value: None,
        label: Some("features"),
        labels: Some(["a", "c"]),
        items: None,
      },
      {
        type_: "enum",
        value: Some("green"),
        label: Some("color"),
        labels: None,
        items: None,
      },
    ]),
  }
  debug_inspect(
    parse_typed_component_value(value, TypeIdx(3), types),
    content="([U32(1), U32(5), Variant(1, Some(String(\"ok\")))])",
  )
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
test "component command reads the Preview 3 monotonic clock through JIT" {
  let evidence = ComponentJITExecutionEvidence::new()
  let status = run_wasi_component_command_with_evidence(
    "testsuite/fixtures/wasi-command-clock-preview3.component.wasm",
    [],
    [],
    [],
    "deny",
    true,
    Text,
    true,
    Some(evidence),
  )
  debug_inspect(
    (
      status,
      evidence.native_run_to_return.val,
      evidence.native_resumable.val,
      evidence.explicit_interpreter.val,
    ),
    content="(0, 0, 1, 0)",
  )
}

///|
test "component command repeatedly releases Preview 3 JIT executions" {
  let evidence = ComponentJITExecutionEvidence::new()
  let failures = Ref(0)
  let executable_mappings_before = component_test_executable_mapping_count()
  for _iteration in 0..<64 {
    let status = run_wasi_component_command_with_evidence(
      "testsuite/fixtures/wasi-command-clock-preview3.component.wasm",
      [],
      [],
      [],
      "deny",
      true,
      Text,
      true,
      Some(evidence),
    )
    if status != 0 {
      failures.val = failures.val + 1
    }
  }
  debug_inspect(
    (
      failures.val,
      evidence.native_run_to_return.val,
      evidence.native_resumable.val,
      evidence.explicit_interpreter.val,
      component_test_executable_mapping_count() - executable_mappings_before,
    ),
    content="(0, 0, 64, 0, 0)",
  )
}

///|
test "component command enumerates Preview 3 filesystem preopens through JIT" {
  let evidence = ComponentJITExecutionEvidence::new()
  let status = run_wasi_component_command_with_evidence(
    "testsuite/fixtures/wasi-command-filesystem-preview3.component.wasm",
    [],
    [],
    ["/tmp::/sandbox"],
    "deny",
    true,
    Text,
    true,
    Some(evidence),
  )
  debug_inspect(
    (
      status,
      evidence.native_run_to_return.val,
      evidence.native_resumable.val,
      evidence.explicit_interpreter.val,
    ),
    content="(0, 2, 1, 0)",
  )
}

///|
test "component command creates and drops a Preview 3 socket through JIT" {
  let evidence = ComponentJITExecutionEvidence::new()
  let status = run_wasi_component_command_with_evidence(
    "testsuite/fixtures/wasi-command-sockets-preview3.component.wasm",
    [],
    [],
    [],
    "deny",
    true,
    Text,
    true,
    Some(evidence),
  )
  debug_inspect(
    (
      status,
      evidence.native_run_to_return.val,
      evidence.native_resumable.val,
      evidence.explicit_interpreter.val,
    ),
    content="(0, 0, 1, 0)",
  )
}

///|
test "component command passes inherited stdin to Preview 3 streams" {
  @fs.create_dir("tmp") catch {
    _ => ()
  }
  let path = "tmp/component-preview3-stdin"
  @fs.write_bytes_to_file(path, b"hello") catch {
    IOError(error) => return fail(error)
  }
  defer (@fs.remove_file(path) catch { _ => () })
  guard @wasi.native_open(path, [ReadOnly], 0) is Some(input_fd) else {
    return fail("could not open inherited stdin fixture")
  }
  defer @wasi.native_close(input_fd) |> ignore
  guard @wasi.native_dup(0) is Some(saved_stdin) else {
    return fail("could not preserve stdin")
  }
  defer @wasi.native_close(saved_stdin) |> ignore
  guard @wasi.native_dup2(input_fd, 0) else {
    return fail("could not redirect stdin")
  }
  defer @wasi.native_dup2(saved_stdin, 0) |> ignore
  let evidence = ComponentJITExecutionEvidence::new()
  let status = run_wasi_component_command_with_evidence(
    "testsuite/fixtures/wasi-command-async-stdin.component.wasm",
    [],
    [],
    [],
    "deny",
    true,
    Text,
    true,
    Some(evidence),
  )
  debug_inspect(
    (
      status,
      evidence.native_run_to_return.val,
      evidence.native_resumable.val,
      evidence.explicit_interpreter.val,
    ),
    content="(0, 0, 1, 0)",
  )
}

///|
test "component command returns Preview 3 stdin errors through the future" {
  guard @wasi.native_dup(0) is Some(saved_stdin) else {
    return fail("could not preserve stdin")
  }
  defer @wasi.native_close(saved_stdin) |> ignore
  guard @wasi.native_close(0) else { return fail("could not close stdin") }
  defer @wasi.native_dup2(saved_stdin, 0) |> ignore
  let status = run_wasi_component_command(
    "testsuite/fixtures/wasi-command-async-stdin.component.wasm",
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
test "component invoke evaluates a nested export with typed JSON" {
  @fs.create_dir("tmp") catch {
    _ => ()
  }
  let path = "tmp/component-invoke.component.wasm"
  let bytes = @component_text.parse_component_wat(
    (
      #|(component
      #|  (core module $m
      #|    (func (export "increment") (param i32) (result i32)
      #|      local.get 0
      #|      i32.const 1
      #|      i32.add))
      #|  (core instance $i (instantiate $m))
      #|  (func $increment (param "value" u32) (result u32)
      #|    (canon lift (core func $i "increment")))
      #|  (instance $math (export "increment" (func $increment)))
      #|  (export "math" (instance $math)))
      #|
    ),
  )
  @fs.write_bytes_to_file(path, bytes) catch {
    IOError(error) => fail(error)
  }
  defer (@fs.remove_file(path) catch { _ => () })
  let success = run_component_invoke_eval(path, "math#increment", ["41"], true)
  debug_inspect(
    (success.ok, success.phase, success.detail, success.values),
    content=(
      #|(true, "invoke", "math#increment", [U32(42)])
    ),
  )
  let failure = run_component_invoke_eval(
    path,
    "math#increment",
    ["\"bad\""],
    true,
  )
  debug_inspect(
    (failure.ok, failure.phase, failure.detail, failure.values),
    content=(
      #|(
      #|  false,
      #|  "arguments",
      #|  "argument 0: JsonValueError(\"invalid u32 integer 'bad'\")",
      #|  [],
      #|)
    ),
  )
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
