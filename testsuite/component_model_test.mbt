///|
test "component_sniff_minimal_preamble" {
  let bytes = Bytes::from_array([
    b'\x00',
    b'\x61',
    b'\x73',
    b'\x6d',
    b'\x01',
    b'\x00',
    b'\x01',
    b'\x00',
  ])
  let kind = @component.sniff_binary_kind(bytes)
  inspect(kind, content="Some(Component)")
}

///|
test "component_parse_minimal_preamble" {
  let bytes = Bytes::from_array([
    b'\x00',
    b'\x61',
    b'\x73',
    b'\x6d',
    b'\x01',
    b'\x00',
    b'\x01',
    b'\x00',
  ])
  let component = @component.parse_component(bytes)
  inspect(
    "version=\{component.binary.version} layer=\{component.binary.layer} sections=\{component.binary.sections.length()}",
    content="version=1 layer=1 sections=0",
  )
  inspect(
    "core_modules=\{component.core_modules.length()} components=\{component.components.length()}",
    content="core_modules=0 components=0",
  )
}

///|
test "component_validate_minimal_preamble" {
  let bytes = Bytes::from_array([
    b'\x00',
    b'\x61',
    b'\x73',
    b'\x6d',
    b'\x01',
    b'\x00',
    b'\x01',
    b'\x00',
  ])
  let component = @component.parse_component(bytes)
  inspect(try? @validator.validate_component(component), content="Ok(())")
}

///|
test "component_validate_embedded_core_module" {
  // Component with a single (empty) embedded core module.
  let bytes = Bytes::from_array([
    b'\x00',
    b'\x61',
    b'\x73',
    b'\x6d',
    b'\x01',
    b'\x00',
    b'\x01',
    b'\x00',
    // core module section (id=1): size=8
    b'\x01',
    b'\x08',
    // embedded core module (empty)
    b'\x00',
    b'\x61',
    b'\x73',
    b'\x6d',
    b'\x01',
    b'\x00',
    b'\x00',
    b'\x00',
  ])
  let component = @component.parse_component(bytes)
  inspect(try? @validator.validate_component(component), content="Ok(())")
}

///|
test "component_validate_import_typeidx_oob" {
  // Component with a single func import referencing typeidx=0 but no types defined.
  let bytes = Bytes::from_array([
    b'\x00',
    b'\x61',
    b'\x73',
    b'\x6d',
    b'\x01',
    b'\x00',
    b'\x01',
    b'\x00',
    // import section (id=10): size=5
    b'\x0a',
    b'\x05',
    // vec length = 1
    b'\x01',
    // importname = plain, name = empty
    b'\x00',
    b'\x00',
    // externdesc = functype, typeidx = 0
    b'\x01',
    b'\x00',
  ])
  let component = @component.parse_component(bytes)
  inspect(
    try? @validator.validate_component(component),
    content="Err(InvalidTypeIndex(0))",
  )
}

///|
test "component_validate_export_sortidx_oob" {
  // Component with a single export of Type 0 but no types in scope.
  let bytes = Bytes::from_array([
    b'\x00',
    b'\x61',
    b'\x73',
    b'\x6d',
    b'\x01',
    b'\x00',
    b'\x01',
    b'\x00',
    // export section (id=11): size=6
    b'\x0b',
    b'\x06',
    // vec length = 1
    b'\x01',
    // exportname = plain, name = empty
    b'\x00',
    b'\x00',
    // sortidx: Type, idx=0
    b'\x03',
    b'\x00',
    // opt externdesc = none
    b'\x00',
  ])
  let component = @component.parse_component(bytes)
  inspect(
    try? @validator.validate_component(component),
    content="Err(InvalidTypeIndex(0))",
  )
}

///|
test "component_validate_canon_string_requires_memory" {
  // Component defines a functype taking a string, then tries to canon.lift it
  // without providing memory/realloc options.
  let bytes = Bytes::from_array([
    b'\x00',
    b'\x61',
    b'\x73',
    b'\x6d',
    b'\x01',
    b'\x00',
    b'\x01',
    b'\x00',
    // type section (id=7): size=7
    b'\x07',
    b'\x07',
    // vec length = 1
    b'\x01',
    // functype (sync = 0x40)
    b'\x40',
    // params: 1
    b'\x01',
    // label: empty
    b'\x00',
    // valtype: string (primvaltype 0x73)
    b'\x73',
    // result: none (0x01 0x00)
    b'\x01',
    b'\x00',
    // canon section (id=8): size=6
    b'\x08',
    b'\x06',
    // vec length = 1
    b'\x01',
    // canon.lift
    b'\x00',
    // must_be_func
    b'\x00',
    // core funcidx = 0
    b'\x00',
    // opts: empty
    b'\x00',
    // typeidx = 0
    b'\x00',
  ])
  let component = @component.parse_component(bytes)
  inspect(
    try? @validator.validate_component(component),
    content=(
      #|Err(MissingCanonOption("memory"))
    ),
  )
}
