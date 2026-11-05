///|
fn ascii_name_bytes(name : String) -> Bytes {
  let bytes : Array[Byte] = []
  for char in name {
    bytes.push(char.to_int().to_byte())
  }
  Bytes::from_array(bytes)
}

///|
test "component extern package names allow kebab-case interface casing only" {
  let names = [
    "ns-1-a:b-1-c/D-2", "ns-1-a:b-1-c/d-2", "ns:A/b", "ns:pkg-A/b", "ns:pkg/aA",
  ]
  let results = []
  for name in names {
    results.push((name, is_package_name(ascii_name_bytes(name))))
  }
  debug_inspect(
    results,
    content=(
      #|[
      #|  ("ns-1-a:b-1-c/D-2", true),
      #|  ("ns-1-a:b-1-c/d-2", true),
      #|  ("ns:A/b", false),
      #|  ("ns:pkg-A/b", false),
      #|  ("ns:pkg/aA", false),
      #|]
    ),
  )
}

///|
test "core module type validation consumes tag attributes and typed references" {
  validate_component(
    @component.parse_component(
      Bytes::from_array([
        0x0, 0x61, 0x73, 0x6d, 0xd, 0x0, 0x1, 0x0, 0x7, 0x18, 0x1, 0x42, 0x2, 0x0,
        0x50, 0x2, 0x1, 0x60, 0x1, 0x7f, 0x0, 0x3, 0x1, 0x74, 0x4, 0x0, 0x0, 0x4,
        0x0, 0x1, 0x6d, 0x0, 0x11, 0x0,
      ]),
    ),
  )
  validate_component(
    @component.parse_component(
      Bytes::from_array([
        0x0, 0x61, 0x73, 0x6d, 0xd, 0x0, 0x1, 0x0, 0x7, 0x16, 0x1, 0x42, 0x2, 0x0,
        0x50, 0x1, 0x0, 0x0, 0x1, 0x74, 0x1, 0x64, 0x6c, 0x0, 0x1, 0x4, 0x0, 0x1,
        0x6d, 0x0, 0x11, 0x0,
      ]),
    ),
  )
}

///|
test "a core instance cannot be the sort of an outer alias" {
  let component = @component.parse_component(
    Bytes::from_array([
      0x00, 0x61, 0x73, 0x6D, 0x0D, 0x00, 0x01, 0x00,
      // One core instance with no exports.
       0x02, 0x03, 0x01, 0x01, 0x00,
      // One outer alias claiming to introduce a core instance.
       0x06, 0x06, 0x01, 0x00, 0x12, 0x02, 0x00, 0x00,
    ]),
  )
  let rejected = try {
    validate_component(component)
    false
  } catch {
    UnsupportedCoreSort(0x12) => true
    _ => false
  }
  inspect(rejected, content="true")
}

///|
test "aliased core module types retain their known export signatures" {
  let prefix : Array[Byte] = [
    0x00, 0x61, 0x73, 0x6d, 0x0d, 0x00, 0x01, 0x00,
    // Core module type exporting a function named "f".
     0x03, 0x0c, 0x01, 0x50, 0x02, 0x01, 0x60, 0x00, 0x00, 0x03, 0x01, 0x66, 0x00,
    0x00,
    // Alias the type and instantiate a module imported with that alias.
     0x06, 0x06, 0x01, 0x00, 0x10, 0x02, 0x00, 0x00, 0x0a, 0x07, 0x01, 0x00, 0x01,
    0x6d, 0x00, 0x11, 0x01, 0x02, 0x04, 0x01, 0x00, 0x00, 0x00,
  ]
  let export_alias : Array[Byte] = [
    0x06, 0x07, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01,
  ]
  validate_component(
    @component.parse_component(
      Bytes::from_array(prefix + export_alias + [0x66]),
    ),
  )
  let missing = @component.parse_component(
    Bytes::from_array(prefix + export_alias + [0x67]),
  )
  try validate_component(missing) catch {
    MissingCoreInstanceExport(0, "g") => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("the aliased module type allowed a missing export")
  }
}
