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

///|
test "component text parser: core module and canon lift" {
  let text = "(component " +
    "(core module $M " +
    "(memory (export \"mem\") 1) " +
    "(func (export \"f\") (result i32) (i32.const 0))" +
    ") " +
    "(core instance $m (instantiate $M)) " +
    "(func (export \"f\") (result string) (canon lift (core func $m \"f\") (memory $m \"mem\")))" +
    ")"
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
  inspect(parsed.core_modules.length(), content="1")
  inspect(parsed.core_instances.length(), content="1")
  inspect(parsed.canons.length(), content="1")
  inspect(parsed.exports.length(), content="1")
  inspect(try? @component_model.validate_component(parsed), content="Ok(())")
}
