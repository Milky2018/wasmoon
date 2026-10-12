///|
test "component validation accepts nesting limit and rejects its successor" {
  for depth in [100, 101] {
    let declarations : Array[String] = ["(type (list u32))"]
    for index in 1..<depth {
      declarations.push("(type (list \{index - 1}))")
    }
    let component = @component.parse_component(
      parse_component_wat("(component \{declarations.join(" ")})"),
    )
    try @component_model.validate_component(component) catch {
      SectionParseError(7, _) => inspect(depth, content="101")
      error => fail("unexpected validation error: \{error}")
    } noraise {
      _ => inspect(depth, content="100")
    }
  }
}

///|
test "component validation accepts effective size limit and rejects its successor" {
  // The first tuple has effective size 100. Referencing it 999 times plus
  // 99 primitive fields makes the second tuple size 100000 including itself.
  let base_fields = Array::make(99, "u32").join(" ")
  let references = Array::make(999, "0").join(" ")
  for primitive_count in [99, 100] {
    let fields = Array::make(primitive_count, "u32").join(" ")
    let component = @component.parse_component(
      parse_component_wat(
        "(component (type (tuple \{base_fields})) (type (tuple \{references} \{fields})))",
      ),
    )
    try @component_model.validate_component(component) catch {
      SectionParseError(7, _) => inspect(primitive_count, content="100")
      error => fail("unexpected validation error: \{error}")
    } noraise {
      _ => inspect(primitive_count, content="99")
    }
  }
}
