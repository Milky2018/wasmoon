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
