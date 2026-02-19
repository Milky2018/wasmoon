///|
test "component text parser: empty component" {
  let bytes = parse_component_wat("(component)") catch {
    e => {
      inspect(e)
      panic()
    }
  }
  let parsed = @component.parse_component(bytes) catch {
    e => {
      inspect(e)
      panic()
    }
  }
  inspect(parsed.binary.layer, content="1")
  inspect(parsed.binary.sections.length(), content="0")
}

///|
test "component text parser: nested component import func" {
  let text = "(component (component (import \"a\" (func))))"
  let bytes = parse_component_wat(text) catch {
    e => {
      inspect(e)
      panic()
    }
  }
  let parsed = @component.parse_component(bytes) catch {
    e => {
      inspect(e)
      panic()
    }
  }
  inspect(parsed.components.length(), content="1")
  inspect(parsed.components[0].types.length(), content="1")
  inspect(parsed.components[0].imports.length(), content="1")
  inspect(try? @component_model.validate_component(parsed), content="Ok(())")
}
