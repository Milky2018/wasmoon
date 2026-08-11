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
