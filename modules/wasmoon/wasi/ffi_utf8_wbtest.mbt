///|
fn append_u32_le(bytes : Array[Byte], value : Int) -> Unit {
  bytes.push((value & 0xff).to_byte())
  bytes.push(((value >> 8) & 0xff).to_byte())
  bytes.push(((value >> 16) & 0xff).to_byte())
  bytes.push(((value >> 24) & 0xff).to_byte())
}

///|
fn append_native_directory_entry(bytes : Array[Byte], name : String) -> Unit {
  let encoded = @utf8.encode(name)
  bytes.push(4)
  append_u32_le(bytes, encoded.length())
  for byte in encoded {
    bytes.push(byte)
  }
}

///|
test "native strings encode complete Unicode scalars as UTF-8" {
  let encoded = string_to_cstring("é|中文|e\u{0301}|😀")
  debug_inspect(
    Bytes::makei(encoded.length(), fn(i) { encoded[i] }),
    content=(
      #|<Bytes:
      #|  [
      #|    0xc3,
      #|    0xa9,
      #|    0x7c,
      #|    0xe4,
      #|    0xb8,
      #|    0xad,
      #|    0xe6,
      #|    0x96,
      #|    0x87,
      #|    0x7c,
      #|    0x65,
      #|    0xcc,
      #|    0x81,
      #|    0x7c,
      #|    0xf0,
      #|    0x9f,
      #|    0x98,
      #|    0x80,
      #|    0x00,
      #|  ]>
    ),
  )
}

///|
test "native directory entries decode UTF-8 names" {
  let wire : Array[Byte] = []
  append_u32_le(wire, 3)
  append_native_directory_entry(wire, "中文.txt")
  append_native_directory_entry(wire, "e\u{0301}.txt")
  append_native_directory_entry(wire, "😀.txt")
  debug_inspect(
    parse_native_readdir(Some(Bytes::from_array(wire))),
    content=(
      #|Some([("中文.txt", 4), ("é.txt", 4), ("😀.txt", 4)])
    ),
  )
}
