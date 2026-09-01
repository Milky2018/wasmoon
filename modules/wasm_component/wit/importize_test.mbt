///|
test "wit: importize-world converts exports to imports and drops original imports" {
  let src = "package docs:calculator@0.1.0;\n\ninterface evaluate {\n  evaluate: func(x: u32, y: u32) -> u32;\n}\n\nworld calculator {\n  import evaluate;\n  export evaluate;\n}\n"
  let pkg = @wit.parse_package(src) catch { e => fail(e.to_string()) }
  let res = @wit.resolve_package(pkg, []) catch { e => fail(e.to_string()) }
  let out_pkg = @wit.importize_resolved_package(res, "calculator") catch {
    e => fail(e.to_string())
  }
  inspect(
    @wit.format_package(out_pkg),
    content="package docs:calculator@0.1.0;\n\ninterface evaluate {\n  evaluate: func(x: u32, y: u32) -> u32;\n}\n\nworld calculator-importized {\n  import evaluate;\n}\n",
  )
}
