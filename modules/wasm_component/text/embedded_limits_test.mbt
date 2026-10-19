///|
test "embedded Core limits never narrow into valid 32-bit limits" {
  for limit in ["4294967296", "0x8000000000000000", "18446744073709551615"] {
    for
      declaration in [
        "(memory " + limit + ")",
        "(memory 0 " + limit + ")",
        "(table " + limit + " funcref)",
        "(table 0 " + limit + " funcref)",
        "(memory (import \"m\" \"memory\") " + limit + ")",
        "(memory (import \"m\" \"memory\") 0 " + limit + ")",
        "(table (import \"m\" \"table\") " + limit + " funcref)",
        "(table (import \"m\" \"table\") 0 " + limit + " funcref)",
        "(import \"m\" \"memory\" (memory " + limit + "))",
        "(import \"m\" \"memory\" (memory 0 " + limit + "))",
        "(import \"m\" \"table\" (table " + limit + " funcref))",
        "(import \"m\" \"table\" (table 0 " + limit + " funcref))",
      ] {
      let component = @component.parse_component(
        @text.parse_component_wat(
          "(component (core module " + declaration + "))",
        ),
      )
      try @component_model.validate_component(component) catch {
        CoreModuleError(_) => ()
        error => fail(error.to_string())
      } noraise {
        _ => fail("embedded Core limit was silently narrowed: " + declaration)
      }
    }
  }
}

///|
test "embedded Core limits preserve supported 32-bit and 64-bit values" {
  for
    declaration in [
      "(memory 0 65536)", "(table 0 0xffffffff funcref)", "(memory i64 4294967296)",
      "(table i64 4294967296 funcref)", "(import \"m\" \"memory\" (memory 0 65536))",
      "(import \"m\" \"table\" (table 0 0xffffffff funcref))", "(import \"m\" \"memory\" (memory i64 4294967296))",
      "(import \"m\" \"table\" (table i64 4294967296 funcref))",
    ] {
    let component = @component.parse_component(
      @text.parse_component_wat("(component (core module " + declaration + "))"),
    )
    @component_model.validate_component(component)
  }
}
