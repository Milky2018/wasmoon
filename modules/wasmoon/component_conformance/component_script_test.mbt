///|
fn run_script_fixture(name : String, contents : String) -> Int raise {
  @fs.create_dir("tmp") catch {
    _ => ()
  }
  let path = "tmp/\{name}.json"
  @fs.write_string_to_file(path, contents) catch {
    IOError(error) => fail(error)
  }
  defer (@fs.remove_file(path) catch { _ => () })
  @component_conformance.run_component_script(
    path,
    @component_conformance.ComponentTestOutputFormat::Json,
  )
}

///|
test "component conformance rejects a failing assertion" {
  inspect(
    run_script_fixture(
      "component_test_fail", "{\"commands\":[{\"type\":\"component\",\"path\":\"testsuite/fixtures/minimal.component.wasm\",\"instantiate\":true},{\"type\":\"assert_return\",\"field\":\"missing\",\"args\":[],\"expected\":[]}]}",
    ),
    content="1",
  )
}

///|
test "component conformance rejects an unsupported command" {
  inspect(
    run_script_fixture(
      "component_test_unsupported", "{\"commands\":[{\"type\":\"component\",\"path\":\"testsuite/fixtures/minimal.component.wasm\",\"instantiate\":true},{\"type\":\"assert_magic_typo\",\"field\":\"missing\",\"args\":[],\"expected\":[]}]}",
    ),
    content="1",
  )
}

///|
test "component conformance rejects malformed script JSON" {
  inspect(
    run_script_fixture("component_test_bad_json", "{\"commands\":["),
    content="1",
  )
}

///|
test "component conformance supports definitions and named instances" {
  inspect(
    run_script_fixture(
      "component_test_instance", "{\"commands\":[{\"type\":\"component_definition\",\"name\":\"$c\",\"path\":\"testsuite/fixtures/minimal.component.wasm\"},{\"type\":\"component_instance\",\"name\":\"$i\",\"component\":\"$c\"}]}",
    ),
    content="0",
  )
}
