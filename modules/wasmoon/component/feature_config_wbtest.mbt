///|
test "embedding rejects disabled implements before instantiation" {
  let bytes = @component_text.parse_component_wat(
    "(component (instance $i) (export \"a\" (implements \"a:b/c\") (instance $i)))",
  )
  for engine in [interpreter_component_engine(), native_component_engine()] {
    let enabled = ComponentRuntime(engine~)
    defer enabled.close()
    enabled.instantiate("enabled", bytes) |> ignore
    let disabled = ComponentRuntime(engine~, component_implements=false)
    defer disabled.close()
    let error = try {
      disabled.instantiate("disabled", bytes) |> ignore
      "missing error"
    } catch {
      error => error.to_string()
    }
    inspect(
      error.contains("the `cm-implements` feature is not active"),
      content="true",
    )
  }
}
