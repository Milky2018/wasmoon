///|
test "escaped Core export names resolve through component aliases" {
  for
    (expected, spellings) in [
      ("é", ["é", "\\c3\\a9", "\\u{e9}"]),
      ("💩", ["💩", "\\f0\\9f\\92\\a9", "\\u{1f4a9}"]),
      ("\u{feff}", ["\u{feff}", "\\ef\\bb\\bf", "\\u{feff}"]),
    ] {
    for exported in spellings {
      for aliased in spellings {
        let source = "(component (core module $m (func (export \"" +
          exported +
          "\"))) (core instance $i (instantiate $m)) (alias core export $i \"" +
          aliased +
          "\" (core func $f)))"
        let parsed = @component.parse_component(
          @text.parse_component_wat(source),
        )
        @component_model.validate_component(parsed)
        assert_eq(parsed.aliases[0].target, CoreExport(0, expected))
      }
    }
  }
}

///|
test "component binary strings retain raw bytes and UTF-8 literal encodings" {
  for spelling in ["é", "\\c3\\a9", "\\u{e9}"] {
    let bytes = @text.parse_component_wat(
      "(component binary \"\\00asm\\0d\\00\\01\\00\\00\\03\\00\" \"" +
      spelling +
      "\")",
    )
    assert_eq(bytes, b"\x00asm\x0d\x00\x01\x00\x00\x03\x00\xc3\xa9")
    @component_model.validate_component(@component.parse_component(bytes))
  }
  let raw = @text.parse_component_wat(
    (
      #|(component binary "\00asm\0d\00\01\00\00\03\00\01\ff")
    ),
  )
  assert_eq(raw, b"\x00asm\x0d\x00\x01\x00\x00\x03\x00\x01\xff")
  @component_model.validate_component(@component.parse_component(raw))
}

///|
test "component names reject invalid UTF-8 and malformed escapes" {
  for
    spelling in [
      "\\80", "\\c0\\af", "\\ed\\a0\\80", "\\q", "\\u{d800}", "\\u{110000}",
    ] {
    try
      @text.parse_component_wat(
        "(component (core module $m) (core instance $i (instantiate $m)) (alias core export $i \"" +
        spelling +
        "\" (core func $f)))",
      )
    catch {
      _ => ()
    } noraise {
      _ => fail("malformed name was accepted: " + spelling)
    }
  }
}
