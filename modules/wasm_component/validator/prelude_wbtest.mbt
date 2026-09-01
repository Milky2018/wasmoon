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
