///|
/// Black-box tests for WASI file system operations

///|
/// Convert string to UTF-8 bytes
fn string_to_utf8(s : String) -> Bytes {
  @utf8.encode(s)
}

///|
/// Convert UTF-8 bytes to string
fn utf8_to_string(bytes : Bytes, len : Int) -> String {
  @utf8.decode_lossy(bytes[:len])
}

///|
test "native file operations: write and read" {
  let test_file = "/tmp/wasmoon_test_file.txt"
  let content = "Hello, WASI!"

  // Open file for writing (use ReadWrite to set proper permissions)
  let fd = @wasi.native_open(test_file, [ReadWrite, Create, Truncate], 0o666)
  guard fd is Some(fd) else { // Skip test if can't create file
    return
  }

  // Write content as UTF-8
  let bytes = string_to_utf8(content)
  let buf = FixedArray::makei(bytes.length(), fn(i) { bytes[i] })
  let written = @wasi.native_write(fd, buf, buf.length())
  inspect(@debug.to_string(written), content="Some(12)")

  // Close file
  inspect(@wasi.native_close(fd), content="true")

  // Open file for reading
  let fd = @wasi.native_open(test_file, [ReadOnly], 0)
  guard fd is Some(fd) else { // Skip if can't open
    return
  }

  // Read content
  let read_buf : FixedArray[Byte] = FixedArray::make(100, b'\x00')
  let read_count = @wasi.native_read(fd, read_buf, 100)
  inspect(@debug.to_string(read_count), content="Some(12)")

  // Verify content
  let read_bytes = Bytes::makei(12, fn(i) { read_buf[i] })
  inspect(utf8_to_string(read_bytes, 12), content="Hello, WASI!")

  // Close file
  inspect(@wasi.native_close(fd), content="true")
}

///|
test "native paths reject embedded NUL before filesystem access" {
  let prefix = "/tmp/wasmoon-native-embedded-nul"
  @wasi.native_unlinkat(0, prefix, 0) |> ignore
  guard @wasi.native_open(prefix, [WriteOnly, Create, Truncate], 0o600)
    is Some(fd) else {
    fail("could not create embedded-NUL fixture")
  }
  defer @wasi.native_unlinkat(0, prefix, 0) |> ignore
  let contents = string_to_utf8("safe")
  let buffer = FixedArray::makei(contents.length(), fn(i) { contents[i] })
  guard @wasi.native_write(fd, buffer, buffer.length()) is Some(_) else {
    fail("could not write embedded-NUL fixture")
  }
  @wasi.native_close(fd) |> ignore
  debug_inspect(
    @wasi.native_open(prefix + "\u{0000}-suffix", [WriteOnly, Truncate], 0),
    content="None",
  )
  inspect(@wasi.native_last_errno_to_wasi(), content="28")
  guard @wasi.native_fstatat(0, prefix, 0) is Some(stat) else {
    fail("could not stat embedded-NUL fixture")
  }
  inspect(stat.size, content="4")
}

///|
test "native readdir preserves directory entry file types" {
  let root = "/tmp/wasmoon-native-readdir-file-types"
  let file = root + "/file"
  let directory = root + "/directory"
  let symlink = root + "/symlink"
  @wasi.native_unlinkat(0, symlink, 0) |> ignore
  @wasi.native_unlinkat(0, file, 0) |> ignore
  @wasi.native_unlinkat(0, directory, @wasi.AT_REMOVEDIR) |> ignore
  @wasi.native_unlinkat(0, root, @wasi.AT_REMOVEDIR) |> ignore
  guard @wasi.native_mkdir(root, 0o700) else {
    fail("could not create readdir fixture directory")
  }
  defer @wasi.native_unlinkat(0, root, @wasi.AT_REMOVEDIR) |> ignore
  guard @wasi.native_open(file, [WriteOnly, Create, Truncate], 0o600)
    is Some(fd) else {
    fail("could not create readdir fixture file")
  }
  @wasi.native_close(fd) |> ignore
  defer @wasi.native_unlinkat(0, file, 0) |> ignore
  guard @wasi.native_mkdir(directory, 0o700) else {
    fail("could not create readdir fixture subdirectory")
  }
  defer @wasi.native_unlinkat(0, directory, @wasi.AT_REMOVEDIR) |> ignore
  guard @wasi.native_symlinkat("file", 0, symlink) else {
    fail("could not create readdir fixture symlink")
  }
  defer @wasi.native_unlinkat(0, symlink, 0) |> ignore
  guard @wasi.native_open(root, [ReadOnly], 0) is Some(directory_fd) else {
    fail("could not open fixture directory")
  }
  defer @wasi.native_close(directory_fd) |> ignore
  guard @wasi.native_readdir_fd(directory_fd) is Some(entries) else {
    fail("could not read fixture directory")
  }
  let mut file_type = -1
  let mut directory_type = -1
  let mut symlink_type = -1
  for entry in entries {
    let (name, native_type) = entry
    match name {
      "file" => file_type = native_type
      "directory" => directory_type = native_type
      "symlink" => symlink_type = native_type
      _ => ()
    }
  }
  debug_inspect([file_type, directory_type, symlink_type], content="[4, 3, 7]")
}

///|
test "native file names round-trip through UTF-8 directory entries" {
  let root = "/tmp/wasmoon-native-readdir-utf8"
  let expected = ["中文.txt", "e\u{0301}.txt", "😀.txt"]
  for name in expected {
    @wasi.native_unlinkat(0, root + "/" + name, 0) |> ignore
  }
  @wasi.native_unlinkat(0, root, @wasi.AT_REMOVEDIR) |> ignore
  guard @wasi.native_mkdir(root, 0o700) else {
    fail("could not create UTF-8 readdir fixture")
  }
  defer {
    for name in expected {
      @wasi.native_unlinkat(0, root + "/" + name, 0) |> ignore
    }
    @wasi.native_unlinkat(0, root, @wasi.AT_REMOVEDIR) |> ignore
  }
  for name in expected {
    let path = root + "/" + name
    guard @wasi.native_open(path, [WriteOnly, Create, Truncate], 0o600)
      is Some(fd) else {
      fail("could not create UTF-8 file \{name}")
    }
    @wasi.native_close(fd) |> ignore
  }
  guard @wasi.native_open(root, [ReadOnly, Directory], 0) is Some(directory_fd) else {
    fail("could not open UTF-8 readdir fixture")
  }
  defer @wasi.native_close(directory_fd) |> ignore
  guard @wasi.native_readdir_fd(directory_fd) is Some(entries) else {
    fail("could not read UTF-8 readdir fixture")
  }
  let actual = entries.map(entry => entry.0)
  actual.sort()
  expected.sort()
  debug_inspect(actual, content="[\"é.txt\", \"中文.txt\", \"😀.txt\"]")
  for name in actual {
    guard @wasi.native_open(root + "/" + name, [ReadOnly], 0) is Some(fd) else {
      fail("could not reopen UTF-8 directory entry \{name}")
    }
    @wasi.native_close(fd) |> ignore
  }
}

///|
test "native file operations: seek and tell" {
  let test_file = "/tmp/wasmoon_test_seek.txt"
  let content = "0123456789"

  // Create file with content (use ReadWrite for proper permissions)
  let fd = @wasi.native_open(test_file, [ReadWrite, Create, Truncate], 0o666)
  guard fd is Some(fd) else { // Skip test if can't create file
    return
  }
  let bytes = string_to_utf8(content)
  let buf = FixedArray::makei(bytes.length(), fn(i) { bytes[i] })
  @wasi.native_write(fd, buf, buf.length()) |> ignore
  @wasi.native_close(fd) |> ignore

  // Open for reading and test seek
  let fd = @wasi.native_open(test_file, [ReadOnly], 0)
  guard fd is Some(fd) else { // Skip if can't open
    return
  }

  // Initial position should be 0
  inspect(@debug.to_string(@wasi.native_tell(fd)), content="Some(0)")

  // Seek to position 5
  let new_pos = @wasi.native_seek(fd, 5L, Set)
  inspect(@debug.to_string(new_pos), content="Some(5)")

  // Tell should return 5
  inspect(@debug.to_string(@wasi.native_tell(fd)), content="Some(5)")

  // Read from position 5
  let read_buf : FixedArray[Byte] = FixedArray::make(5, b'\x00')
  let read_count = @wasi.native_read(fd, read_buf, 5)
  inspect(@debug.to_string(read_count), content="Some(5)")
  let read_bytes = Bytes::makei(5, fn(i) { read_buf[i] })
  inspect(utf8_to_string(read_bytes, 5), content="56789")

  // Seek relative from current position
  let new_pos = @wasi.native_seek(fd, -3L, Cur)
  inspect(@debug.to_string(new_pos), content="Some(7)")

  // Seek from end
  let new_pos = @wasi.native_seek(fd, -2L, End)
  inspect(@debug.to_string(new_pos), content="Some(8)")
  @wasi.native_close(fd) |> ignore
}

///|
test "native file operations: open non-existent file" {
  let fd = @wasi.native_open("/tmp/non_existent_file_12345.txt", [ReadOnly], 0)
  guard fd is None else {
    @wasi.native_close(fd.unwrap()) |> ignore // File exists unexpectedly
    return
  }
}
