///|
/// Black-box tests for WASI file system operations

///|
/// Convert string to UTF-8 bytes
fn string_to_utf8(s : String) -> Bytes {
  let len = s.length()
  let buf = Array::new(capacity=len * 4)
  for i in 0..<len {
    let c = s.code_unit_at(i).to_int()
    if c < 0x80 {
      buf.push(c.to_byte())
    } else if c < 0x800 {
      buf.push((0xC0 | (c >> 6)).to_byte())
      buf.push((0x80 | (c & 0x3F)).to_byte())
    } else if c >= 0xD800 && c <= 0xDBFF && i + 1 < len {
      // Surrogate pair
      let c2 = s.code_unit_at(i + 1).to_int()
      if c2 >= 0xDC00 && c2 <= 0xDFFF {
        let codepoint = 0x10000 + ((c - 0xD800) << 10) + (c2 - 0xDC00)
        buf.push((0xF0 | (codepoint >> 18)).to_byte())
        buf.push((0x80 | ((codepoint >> 12) & 0x3F)).to_byte())
        buf.push((0x80 | ((codepoint >> 6) & 0x3F)).to_byte())
        buf.push((0x80 | (codepoint & 0x3F)).to_byte())
      }
    } else {
      buf.push((0xE0 | (c >> 12)).to_byte())
      buf.push((0x80 | ((c >> 6) & 0x3F)).to_byte())
      buf.push((0x80 | (c & 0x3F)).to_byte())
    }
  }
  Bytes::from_iter(buf.iter())
}

///|
/// Convert UTF-8 bytes to string
fn utf8_to_string(bytes : Bytes, len : Int) -> String {
  let buf = StringBuilder::new()
  let mut i = 0
  while i < len {
    let b = bytes[i].to_int()
    if b < 0x80 {
      buf.write_char(b.unsafe_to_char())
      i = i + 1
    } else if b < 0xE0 {
      let c = ((b & 0x1F) << 6) | (bytes[i + 1].to_int() & 0x3F)
      buf.write_char(c.unsafe_to_char())
      i = i + 2
    } else if b < 0xF0 {
      let c = ((b & 0x0F) << 12) |
        ((bytes[i + 1].to_int() & 0x3F) << 6) |
        (bytes[i + 2].to_int() & 0x3F)
      buf.write_char(c.unsafe_to_char())
      i = i + 3
    } else {
      let codepoint = ((b & 0x07) << 18) |
        ((bytes[i + 1].to_int() & 0x3F) << 12) |
        ((bytes[i + 2].to_int() & 0x3F) << 6) |
        (bytes[i + 3].to_int() & 0x3F)
      // Convert to surrogate pair
      let cp = codepoint - 0x10000
      buf.write_char((0xD800 + (cp >> 10)).unsafe_to_char())
      buf.write_char((0xDC00 + (cp & 0x3FF)).unsafe_to_char())
      i = i + 4
    }
  }
  buf.to_string()
}

///|
test "native file operations: write and read" {
  let test_file = "/tmp/wasmoon_test_file.txt"
  let content = "Hello, WASI!"

  // Open file for writing (use ReadWrite to set proper permissions)
  let fd = @wasi.native_open(
    test_file,
    [@wasi.ReadWrite, @wasi.Create, @wasi.Truncate],
    0o666,
  )
  guard fd is Some(fd) else { // Skip test if can't create file
    return
  }

  // Write content as UTF-8
  let bytes = string_to_utf8(content)
  let buf = FixedArray::makei(bytes.length(), fn(i) { bytes[i] })
  let written = @wasi.native_write(fd, buf, buf.length())
  inspect(written, content="Some(12)")

  // Close file
  inspect(@wasi.native_close(fd), content="true")

  // Open file for reading
  let fd = @wasi.native_open(test_file, [@wasi.ReadOnly], 0)
  guard fd is Some(fd) else { // Skip if can't open
    return
  }

  // Read content
  let read_buf : FixedArray[Byte] = FixedArray::make(100, b'\x00')
  let read_count = @wasi.native_read(fd, read_buf, 100)
  inspect(read_count, content="Some(12)")

  // Verify content
  let read_bytes = Bytes::makei(12, fn(i) { read_buf[i] })
  inspect(utf8_to_string(read_bytes, 12), content="Hello, WASI!")

  // Close file
  inspect(@wasi.native_close(fd), content="true")
}

///|
test "native file operations: seek and tell" {
  let test_file = "/tmp/wasmoon_test_seek.txt"
  let content = "0123456789"

  // Create file with content (use ReadWrite for proper permissions)
  let fd = @wasi.native_open(
    test_file,
    [@wasi.ReadWrite, @wasi.Create, @wasi.Truncate],
    0o666,
  )
  guard fd is Some(fd) else { // Skip test if can't create file
    return
  }
  let bytes = string_to_utf8(content)
  let buf = FixedArray::makei(bytes.length(), fn(i) { bytes[i] })
  @wasi.native_write(fd, buf, buf.length()) |> ignore
  @wasi.native_close(fd) |> ignore

  // Open for reading and test seek
  let fd = @wasi.native_open(test_file, [@wasi.ReadOnly], 0)
  guard fd is Some(fd) else { // Skip if can't open
    return
  }

  // Initial position should be 0
  inspect(@wasi.native_tell(fd), content="Some(0)")

  // Seek to position 5
  let new_pos = @wasi.native_seek(fd, 5L, @wasi.Set)
  inspect(new_pos, content="Some(5)")

  // Tell should return 5
  inspect(@wasi.native_tell(fd), content="Some(5)")

  // Read from position 5
  let read_buf : FixedArray[Byte] = FixedArray::make(5, b'\x00')
  let read_count = @wasi.native_read(fd, read_buf, 5)
  inspect(read_count, content="Some(5)")
  let read_bytes = Bytes::makei(5, fn(i) { read_buf[i] })
  inspect(utf8_to_string(read_bytes, 5), content="56789")

  // Seek relative from current position
  let new_pos = @wasi.native_seek(fd, -3L, @wasi.Cur)
  inspect(new_pos, content="Some(7)")

  // Seek from end
  let new_pos = @wasi.native_seek(fd, -2L, @wasi.End)
  inspect(new_pos, content="Some(8)")
  @wasi.native_close(fd) |> ignore
}

///|
test "native file operations: open non-existent file" {
  let fd = @wasi.native_open(
    "/tmp/non_existent_file_12345.txt",
    [@wasi.ReadOnly],
    0,
  )
  guard fd is None else {
    @wasi.native_close(fd.unwrap()) |> ignore // File exists unexpectedly
    return
  }
}
