///|
/// Encode once so capacity checks and writes use identical UTF-8 byte counts.
fn encode_string_table(
  strings : Array[String],
) -> Result[(Array[FixedArray[Byte]], Int), Int] {
  let encoded : Array[FixedArray[Byte]] = []
  let mut size = 0L
  for string in strings {
    let bytes = match string_to_cstring(string) {
      Some(bytes) => bytes
      None => return Err(native_last_errno_to_wasi())
    }
    size += bytes.length().to_int64()
    if size > 0x7FFFFFFFL {
      return Err(Errno::Overflow.to_i32())
    }
    encoded.push(bytes)
  }
  Ok((encoded, size.to_int()))
}

///|
fn string_table_sizes(
  mem : @runtime.Memory,
  strings : Array[String],
  count_ptr : Int,
  size_ptr : Int,
) -> Int {
  if !check_mem_range(mem, count_ptr, 4) || !check_mem_range(mem, size_ptr, 4) {
    return Errno::Fault.to_i32()
  }
  let (_, size) = match encode_string_table(strings) {
    Ok(value) => value
    Err(error) => return error
  }
  mem.write_i32(count_ptr, strings.length())
  mem.write_i32(size_ptr, size)
  0
}

///|
fn write_string_table(
  mem : @runtime.Memory,
  strings : Array[String],
  pointers : Int,
  data : Int,
) -> Int {
  if strings.length() > 0x1FFFFFFF ||
    !check_mem_range(mem, pointers, strings.length() * 4) {
    return Errno::Fault.to_i32()
  }
  let (encoded, size) = match encode_string_table(strings) {
    Ok(value) => value
    Err(error) => return error
  }
  if !check_mem_range(mem, data, size) {
    return Errno::Fault.to_i32()
  }
  let mut offset = 0
  for i, bytes in encoded {
    mem.write_i32(pointers + i * 4, data + offset)
    for j in 0..<bytes.length() {
      mem.write_byte(data + offset + j, bytes[j])
    }
    offset += bytes.length()
  }
  0
}
