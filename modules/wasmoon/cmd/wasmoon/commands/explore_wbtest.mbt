///|
suberror ExpectedExploreCompileFailure

///|
test "explore keeps an earlier compile failure after a later success" {
  let stamp = @env.now()
  let wat_path = "/tmp/wasmoon-explore-status-\{stamp}.wat"
  let html_path = "/tmp/wasmoon-explore-status-\{stamp}.html"
  @fs.write_string_to_file(
    wat_path,
    (
      #|(module
      #|  (func (export "first") (result i32) (i32.const 1))
      #|  (func (export "second") (result i32) (i32.const 2)))
    ),
  )
  defer (@fs.remove_file(wat_path) catch { _ => () })
  defer (@fs.remove_file(html_path) catch { _ => () })
  let events : Array[String] = []
  let status = run_explore_with_compiler(
    wat_path,
    None,
    2,
    [],
    true,
    false,
    "x64",
    fn(function, validation_context, target) raise {
      if events.is_empty() {
        events.push("failed")
        raise ExpectedExploreCompileFailure
      }
      let diagnostics = @wasmoon_jit.compile_wasm_body_diagnostics_for_target(
        function, validation_context, target,
      )
      events.push("succeeded")
      diagnostics
    },
  )
  debug_inspect(events, content="[\"failed\", \"succeeded\"]")
  inspect(status, content="1")
}

///|
test "x64 exploration compiles spilled multi-result transfers" {
  for ty in ["i32", "f64", "v128"] {
    let results = Array::make(20, ty).join(" ")
    let constant = if ty == "v128" {
      "v128.const i32x4 0 1 2 3"
    } else {
      "\{ty}.const 0"
    }
    let values = Array::make(20, constant).join(" ")
    let path = "/tmp/wasmoon-x64-result-spills-\{ty}-\{@env.now()}.wat"
    let html = path[:path.length() - 4].to_owned() + ".html"
    @fs.write_string_to_file(
      path,
      "(module (func $callee (result \{results}) \{values}) (func (export \"run\") (result \{results}) call $callee))",
    )
    defer (@fs.remove_file(path) catch { _ => () })
    defer (@fs.remove_file(html) catch { _ => () })
    inspect(
      run_explore(path, None, 2, [], true, false, target_name="x64"),
      content="0",
    )
  }
}
