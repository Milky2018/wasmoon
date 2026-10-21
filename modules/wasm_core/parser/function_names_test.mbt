///|
fn debug_name_binary(payload : Array[Byte]) -> Bytes {
  let bytes = b"\x00\x61\x73\x6d\x01\x00\x00\x00\x01\x04\x01\x60\x00\x00\x02\x07\x01\x01\x68\x01\x66\x00\x00\x03\x03\x02\x00\x00\x07\x07\x01\x03\x72\x75\x6e\x00\x02\x0a\x07\x02\x02\x00\x0b\x02\x00\x0b".to_array()
  let section : Array[Byte] = [4, 110, 97, 109, 101]
  section.append(payload)
  bytes.push(0)
  let mut size = section.length()
  while size >= 128 {
    bytes.push(((size & 127) | 128).to_byte())
    size = size >> 7
  }
  bytes.push(size.to_byte())
  bytes.append(section)
  Bytes::from_array(bytes)
}

///|
test "binary function names preserve imported index offsets and skip unknown subsections" {
  let bytes = debug_name_binary([
    99, 3, 1, 2, 3, 1, 16, 2, 0, 4, 104, 111, 115, 116, 1, 7, 229, 143, 182, 240,
    159, 152, 128,
  ])
  let module_ = @parser.parse_module(bytes)
  assert_eq(module_.func_names.get(0).unwrap_or("missing"), "host")
  assert_eq(module_.func_names.get(1).unwrap_or("missing"), "叶😀")
  assert_true(module_.func_names.get(2) is None)
}

///|
test "malformed nonsemantic function names do not reject an executable module" {
  for payload in [[1, 1, 128], [1, 4, 1, 0, 1, 255], [1, 100, 0]] {
    let module_ = @parser.parse_module(
      debug_name_binary(payload.map(x => x.to_byte())),
    )
    inspect(module_.funcs.length(), content="2")
    inspect(module_.func_names.length(), content="0")
  }
}

///|
test "function name work admission is not swallowed as malformed metadata" {
  let bytes = debug_name_binary([1, 5, 1, 0, 2, 111, 107])
  try
    @parser.parse_module(bytes, limits={
      max_input_bytes: 1000L,
      max_work: bytes.length().to_int64(),
      max_depth: 100,
    })
  catch {
    error => assert_true(error.is_resource_exhaustion())
  } noraise {
    _ => fail("name processing must obey the shared work budget")
  }
}
