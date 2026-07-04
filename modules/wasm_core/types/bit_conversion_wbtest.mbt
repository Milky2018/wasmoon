///|
test "bytes_to_int64_le decodes little-endian bytes" {
  let bytes = Bytes::from_array([
    b'\x01', b'\x02', b'\x03', b'\x04', b'\x05', b'\x06', b'\x07', b'\x08', b'\xff',
  ])
  inspect(bytes_to_int64_le(bytes, 0), content="578437695752307201")
  inspect(bytes_to_int64_le(bytes, 1), content="-69798071788895486")
}
