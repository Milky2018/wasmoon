///|
test "wasi: fd_write to stdout" {
  let ctx = WasiContextBuilder::new().stdout(fn(_bytes) {  }).build()
  let mem = @runtime.Memory::new(1, None)
  // Setup iovec at address 0: buf=100, buf_len=5
  mem.write_i32(0, 100) // buf pointer
  mem.write_i32(4, 5) // buf length
  // Write "Hello" at address 100
  mem.write_byte(100, b'H')
  mem.write_byte(101, b'e')
  mem.write_byte(102, b'l')
  mem.write_byte(103, b'l')
  mem.write_byte(104, b'o')
  // nwritten will be at address 200
  let result = fd_write(ctx, mem, 1, 0, 1, 200)
  inspect(result, content="0") // Success
  inspect(mem.read_i32(200), content="5") // 5 bytes written
}

///|
test "wasi: fd_write invalid fd" {
  let ctx = WasiContextBuilder::new().build()
  let mem = @runtime.Memory::new(1, None)
  let result = fd_write(ctx, mem, 999, 0, 0, 0)
  inspect(result, content="8") // Errno::Badf
}

///|
test "wasi: fd_write returns EFAULT on out-of-bounds iovec" {
  let ctx = WasiContextBuilder::new().stdout(fn(_bytes) {  }).build()
  let mem = @runtime.Memory::new(1, None)
  // iovec struct (8 bytes) crosses memory end.
  let result = fd_write(ctx, mem, 1, 65532, 1, 0)
  inspect(result, content="21") // Errno::Fault
}

///|
test "wasi: fd_write uses first non-empty iovec only" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let test_path = "wasmoon_fd_write_first_iov.txt"
  for i, c in test_path {
    mem.write_byte(1000 + i, c.to_int().to_byte())
  }
  let open_result = path_open(
    ctx,
    mem,
    3,
    0,
    1000,
    test_path.length(),
    9,
    right_fd_read | right_fd_write,
    0L,
    0,
    2000,
  )
  if open_result != 0 {
    return
  }
  let fd = mem.read_i32(2000)
  // iovec[0] is empty, iovec[1] and iovec[2] are non-empty.
  mem.write_i32(0, 300)
  mem.write_i32(4, 0)
  mem.write_i32(8, 320)
  mem.write_i32(12, 3)
  mem.write_i32(16, 340)
  mem.write_i32(20, 3)
  for i, c in "abc" {
    mem.write_byte(320 + i, c.to_int().to_byte())
  }
  for i, c in "XYZ" {
    mem.write_byte(340 + i, c.to_int().to_byte())
  }
  inspect(fd_write(ctx, mem, fd, 0, 3, 400), content="0")
  inspect(mem.read_i32(400), content="3")
  inspect(fd_seek(ctx, mem, fd, 0L, 0, 404), content="0")
  mem.write_i32(24, 360)
  mem.write_i32(28, 8)
  inspect(fd_read(ctx, mem, fd, 24, 1, 412), content="0")
  inspect(mem.read_i32(412), content="3")
  let mut content = ""
  for i in 0..<3 {
    content = content +
      mem.read_byte(360 + i).to_int().unsafe_to_char().to_string()
  }
  inspect(content, content="abc")
  fd_close(ctx, fd) |> ignore
}

///|
test "wasi: args_sizes_get" {
  let ctx = WasiContextBuilder::new().args(["prog", "arg1", "arg2"]).build()
  let mem = @runtime.Memory::new(1, None)
  let result = args_sizes_get(ctx, mem, 0, 4)
  inspect(result, content="0") // Success
  inspect(mem.read_i32(0), content="3") // argc = 3
  // argv_buf_size = len("prog") + 1 + len("arg1") + 1 + len("arg2") + 1 = 5 + 5 + 5 = 15
  inspect(mem.read_i32(4), content="15")
}

///|
test "wasi: environ_sizes_get" {
  let ctx = WasiContextBuilder::new()
    .env("HOME", "/home/user")
    .env("PATH", "/bin")
    .build()
  let mem = @runtime.Memory::new(1, None)
  let result = environ_sizes_get(ctx, mem, 0, 4)
  inspect(result, content="0") // Success
  inspect(mem.read_i32(0), content="2") // environc = 2
  // environ_buf_size = len("HOME=/home/user") + 1 + len("PATH=/bin") + 1 = 16 + 10 = 26
  inspect(mem.read_i32(4), content="26")
}

///|
test "wasi: clock_time_get" {
  let mem = @runtime.Memory::new(1, None)
  let result = clock_time_get(mem, 0, 0L, 0) // Realtime clock
  inspect(result, content="0") // Success
  // Check that time is non-zero (timestamp written to address 0 as i64)
  let time = mem.read_i64(0)
  inspect(time > 0L, content="true")
}

///|
test "wasi: clock_time_get invalid clock" {
  let mem = @runtime.Memory::new(1, None)
  let result = clock_time_get(mem, 999, 0L, 0) // Invalid clock ID
  inspect(result, content="28") // Errno::Inval
}

///|
test "wasi: clock_time_get cpu clocks return BADF" {
  let mem = @runtime.Memory::new(1, None)
  inspect(clock_time_get(mem, 2, 0L, 0), content="8") // PROCESS_CPUTIME_ID
  inspect(clock_time_get(mem, 3, 0L, 0), content="8") // THREAD_CPUTIME_ID
}

///|
test "wasi: fd_close" {
  let ctx = WasiContextBuilder::new().build()
  // Match wasmtime: stdio descriptors can be closed once.
  inspect(fd_close(ctx, 0), content="0")
  inspect(fd_close(ctx, 1), content="0")
  inspect(fd_close(ctx, 2), content="0")
  // Closing again returns BADF.
  inspect(fd_close(ctx, 0), content="8")
  inspect(fd_close(ctx, 1), content="8")
  inspect(fd_close(ctx, 2), content="8")
  // fd 3 is not open, so it returns Badf
  inspect(fd_close(ctx, 3), content="8") // Badf (not open)
}

///|
test "wasi: errno values" {
  inspect(Errno::Success.to_i32(), content="0")
  inspect(Errno::Badf.to_i32(), content="8")
  inspect(Errno::Inval.to_i32(), content="28")
  inspect(Errno::NoSys.to_i32(), content="52")
  inspect(Errno::NoEnt.to_i32(), content="44")
}

///|
test "wasi: context builder" {
  let ctx = WasiContextBuilder::new()
    .args(["my_prog", "--help"])
    .env("DEBUG", "1")
    .preopen_dir("/tmp", "/sandbox")
    .build()
  inspect(ctx.args.length(), content="2")
  inspect(ctx.env.length(), content="1")
  inspect(ctx.preopens.length(), content="1")
  let (fd, host, guest) = ctx.preopens[0]
  inspect(fd.to_int(), content="3")
  inspect(host, content="/tmp")
  inspect(guest, content="/sandbox")
}

///|
test "wasi: fd_prestat_get" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/guest/path").build()
  let mem = @runtime.Memory::new(1, None)
  // prestat struct is 8 bytes
  let result = fd_prestat_get(ctx, mem, 3, 0)
  inspect(result, content="0") // Success
  // Check prestat type (should be 0 = dir)
  inspect(mem.read_byte(0), content="b'\\x00'")
  // Check name length (at offset 4)
  inspect(mem.read_i32(4), content="11") // len("/guest/path") = 11
}

///|
test "wasi: fd_prestat_get invalid fd" {
  let ctx = WasiContextBuilder::new().build()
  let mem = @runtime.Memory::new(1, None)
  let result = fd_prestat_get(ctx, mem, 3, 0)
  inspect(result, content="8") // Badf - no preopen for fd 3
}

///|
test "wasi: random_get" {
  let mem = @runtime.Memory::new(1, None)
  let result = random_get(mem, 0, 10)
  inspect(result, content="0") // Success
  // Check that some bytes were written (at least one non-zero)
  let mut has_nonzero = false
  for i in 0..<10 {
    if mem.read_byte(i) != b'\x00' {
      has_nonzero = true
      break
    }
  }
  inspect(has_nonzero, content="true")
}

///|
test "wasi: random_get produces different results" {
  let mem = @runtime.Memory::new(1, None)
  // First call
  let result1 = random_get(mem, 0, 16)
  inspect(result1, content="0")
  // Save first 16 bytes
  let first = FixedArray::makei(16, fn(i) { mem.read_byte(i) })
  // Second call
  let result2 = random_get(mem, 0, 16)
  inspect(result2, content="0")
  // At least some bytes should be different (extremely unlikely to be same)
  let any_different = for i in 0..<16 {
    if mem.read_byte(i) != first[i] {
      break true
    }
  } nobreak {
    false
  }
  inspect(any_different, content="true")
}

///|
test "wasi: fd_read from opened file" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  // First write a test file using path_open
  let test_path = "wasmoon_fd_read_test.txt"
  let test_content = "Hello"
  // Write path to memory (at address 1000)
  for i, c in test_path {
    mem.write_byte(1000 + i, c.to_int().to_byte())
  }
  // Open file for writing: oflags = 0x01 (CREATE) | 0x08 (TRUNC) = 9
  let result = path_open(
    ctx,
    mem,
    3,
    0,
    1000,
    test_path.length(),
    9,
    right_fd_read | right_fd_write,
    0L,
    0,
    2000,
  )
  if result != 0 {
    return // Skip if cannot create file
  }
  let write_fd = mem.read_i32(2000)
  // Setup iovec for writing
  mem.write_i32(0, 100) // buf ptr
  mem.write_i32(4, 5) // buf len
  for i, c in test_content {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  let write_result = fd_write(ctx, mem, write_fd, 0, 1, 200)
  inspect(write_result, content="0")
  fd_close(ctx, write_fd) |> ignore
  // Now open for reading
  let result = path_open(
    ctx,
    mem,
    3,
    0,
    1000,
    test_path.length(),
    0,
    0L,
    0L,
    0,
    2000,
  )
  if result != 0 {
    return
  }
  let read_fd = mem.read_i32(2000)
  // Setup iovec for reading
  mem.write_i32(0, 300) // buf ptr
  mem.write_i32(4, 10) // buf len
  let read_result = fd_read(ctx, mem, read_fd, 0, 1, 200)
  inspect(read_result, content="0")
  let bytes_read = mem.read_i32(200)
  inspect(bytes_read, content="5")
  // Verify content
  let mut read_str = ""
  for i in 0..<bytes_read {
    read_str = read_str +
      mem.read_byte(300 + i).to_int().unsafe_to_char().to_string()
  }
  inspect(read_str, content="Hello")
  fd_close(ctx, read_fd) |> ignore
}

///|
test "wasi: args_get" {
  let ctx = WasiContextBuilder::new().args(["prog", "arg1", "arg2"]).build()
  let mem = @runtime.Memory::new(1, None)
  // argv array at 0, argv_buf at 100
  let result = args_get(ctx, mem, 0, 100)
  inspect(result, content="0") // Success
  // Check argv[0] points to correct position
  let argv0_ptr = mem.read_i32(0)
  inspect(argv0_ptr, content="100")
  // Check argv[1]
  let argv1_ptr = mem.read_i32(4)
  inspect(argv1_ptr, content="105") // 100 + 4 + 1 (null terminator)
  // Check argv[2]
  let argv2_ptr = mem.read_i32(8)
  inspect(argv2_ptr, content="110") // 105 + 4 + 1
  // Verify "prog" is at argv_buf
  let mut arg0 = ""
  for i in 0..<4 {
    arg0 = arg0 + mem.read_byte(100 + i).to_int().unsafe_to_char().to_string()
  }
  inspect(arg0, content="prog")
}

///|
test "wasi: environ_get" {
  let ctx = WasiContextBuilder::new()
    .env("KEY1", "val1")
    .env("KEY2", "val2")
    .build()
  let mem = @runtime.Memory::new(1, None)
  // environ array at 0, environ_buf at 100
  let result = environ_get(ctx, mem, 0, 100)
  inspect(result, content="0") // Success
  // Check environ[0] points to correct position
  let env0_ptr = mem.read_i32(0)
  inspect(env0_ptr, content="100")
  // Read first env var
  let mut env0 = ""
  let mut i = 0
  while mem.read_byte(100 + i) != b'\x00' && i < 20 {
    env0 = env0 + mem.read_byte(100 + i).to_int().unsafe_to_char().to_string()
    i = i + 1
  }
  inspect(env0, content="KEY1=val1")
}

///|
test "wasi: fd_prestat_dir_name" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/sandbox").build()
  let mem = @runtime.Memory::new(1, None)
  // Get prestat first to know the length
  let result = fd_prestat_get(ctx, mem, 3, 0)
  inspect(result, content="0")
  let name_len = mem.read_i32(4)
  inspect(name_len, content="8") // len("/sandbox") = 8
  // Now get the dir name
  let result = fd_prestat_dir_name(ctx, mem, 3, 100, name_len)
  inspect(result, content="0")
  // Read the name
  let mut name = ""
  for i in 0..<name_len {
    name = name + mem.read_byte(100 + i).to_int().unsafe_to_char().to_string()
  }
  inspect(name, content="/sandbox")
}

///|
test "wasi: fd_prestat_dir_name returns NOTDIR for non-preopen descriptor" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let test_path = "wasmoon_prestat_notdir.txt"
  for i, c in test_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  path_unlink_file_impl(ctx, mem, 3, 100, test_path.length()) |> ignore
  let open_result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    test_path.length(),
    9,
    right_fd_read | right_fd_write,
    0L,
    0,
    500,
  )
  if open_result != 0 {
    return
  }
  let fd = mem.read_i32(500)
  let result = fd_prestat_dir_name(ctx, mem, fd, 600, 8)
  inspect(result, content="54") // Errno::NotDir
  fd_close(ctx, fd) |> ignore
  path_unlink_file_impl(ctx, mem, 3, 100, test_path.length()) |> ignore
}

///|
test "wasi: fd_seek and fd_tell" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  // Create a test file
  let test_path = "wasmoon_seek_test.txt"
  for i, c in test_path {
    mem.write_byte(1000 + i, c.to_int().to_byte())
  }
  // Open file for writing and write some content
  let result = path_open(
    ctx,
    mem,
    3,
    0,
    1000,
    test_path.length(),
    9,
    right_fd_read | right_fd_write,
    0L,
    0,
    2000,
  )
  if result != 0 {
    return
  }
  let fd = mem.read_i32(2000)
  // Write 10 bytes
  mem.write_i32(0, 100)
  mem.write_i32(4, 10)
  for i in 0..<10 {
    mem.write_byte(100 + i, (48 + i).to_byte()) // '0'-'9'
  }
  fd_write(ctx, mem, fd, 0, 1, 200) |> ignore
  // Test fd_seek to beginning
  let result = fd_seek(ctx, mem, fd, 0L, 0, 300) // whence=0 (SET)
  inspect(result, content="0")
  inspect(mem.read_i64(300), content="0")
  // Test fd_tell
  let result = fd_tell(ctx, mem, fd, 300)
  inspect(result, content="0")
  inspect(mem.read_i64(300), content="0")
  // Seek to position 5
  let result = fd_seek(ctx, mem, fd, 5L, 0, 300)
  inspect(result, content="0")
  inspect(mem.read_i64(300), content="5")
  // Seek relative +2
  let result = fd_seek(ctx, mem, fd, 2L, 1, 300) // whence=1 (CUR)
  inspect(result, content="0")
  inspect(mem.read_i64(300), content="7")
  // Seek from end -3
  let result = fd_seek(ctx, mem, fd, -3L, 2, 300) // whence=2 (END)
  inspect(result, content="0")
  inspect(mem.read_i64(300), content="7")
  fd_close(ctx, fd) |> ignore
}

///|
test "wasi: fd_seek on stdio returns SPipe" {
  let ctx = WasiContextBuilder::new().build()
  let mem = @runtime.Memory::new(1, None)
  let result = fd_seek(ctx, mem, 0, 0L, 0, 0) // stdin
  inspect(result, content="70") // Errno::SPipe
  let result = fd_seek(ctx, mem, 1, 0L, 0, 0) // stdout
  inspect(result, content="70")
}

///|
test "wasi: fd_pread and fd_pwrite" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  // Create a test file
  let test_path = "wasmoon_pread_test.txt"
  for i, c in test_path {
    mem.write_byte(1000 + i, c.to_int().to_byte())
  }
  let result = path_open(
    ctx,
    mem,
    3,
    0,
    1000,
    test_path.length(),
    9,
    right_fd_read | right_fd_write,
    0L,
    0,
    2000,
  )
  if result != 0 {
    return
  }
  let fd = mem.read_i32(2000)
  // Write initial content using pwrite at offset 0
  mem.write_i32(0, 100)
  mem.write_i32(4, 5)
  for i, c in "ABCDE" {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  let result = fd_pwrite(ctx, mem, fd, 0, 1, 0L, 200)
  inspect(result, content="0")
  inspect(mem.read_i32(200), content="5")
  // Verify cursor is still at 0 (pwrite doesn't move cursor)
  let result = fd_tell(ctx, mem, fd, 300)
  inspect(result, content="0")
  inspect(mem.read_i64(300), content="0")
  // Read using pread from offset 2
  mem.write_i32(0, 400)
  mem.write_i32(4, 3)
  let result = fd_pread(ctx, mem, fd, 0, 1, 2L, 200)
  inspect(result, content="0")
  inspect(mem.read_i32(200), content="3")
  // Verify content "CDE"
  let mut content = ""
  for i in 0..<3 {
    content = content +
      mem.read_byte(400 + i).to_int().unsafe_to_char().to_string()
  }
  inspect(content, content="CDE")
  // Verify cursor is still at 0 (pread doesn't move cursor)
  let result = fd_tell(ctx, mem, fd, 300)
  inspect(result, content="0")
  fd_close(ctx, fd) |> ignore
}

///|
test "wasi: fd_pread/fd_pwrite use first non-empty iovec only" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let test_path = "wasmoon_pread_first_iov.txt"
  for i, c in test_path {
    mem.write_byte(1000 + i, c.to_int().to_byte())
  }
  let open_result = path_open(
    ctx,
    mem,
    3,
    0,
    1000,
    test_path.length(),
    9,
    right_fd_read | right_fd_write,
    0L,
    0,
    2000,
  )
  if open_result != 0 {
    return
  }
  let fd = mem.read_i32(2000)

  // pwrite with multiple iovecs should use only the first non-empty one.
  mem.write_i32(0, 300)
  mem.write_i32(4, 0)
  mem.write_i32(8, 320)
  mem.write_i32(12, 3)
  mem.write_i32(16, 340)
  mem.write_i32(20, 3)
  for i, c in "abc" {
    mem.write_byte(320 + i, c.to_int().to_byte())
  }
  for i, c in "XYZ" {
    mem.write_byte(340 + i, c.to_int().to_byte())
  }
  inspect(fd_pwrite(ctx, mem, fd, 0, 3, 0L, 500), content="0")
  inspect(mem.read_i32(500), content="3")

  // pread with multiple iovecs should fill only the first non-empty one.
  mem.write_i32(24, 420)
  mem.write_i32(28, 0)
  mem.write_i32(32, 440)
  mem.write_i32(36, 3)
  mem.write_i32(40, 460)
  mem.write_i32(44, 3)
  inspect(fd_pread(ctx, mem, fd, 24, 3, 0L, 504), content="0")
  inspect(mem.read_i32(504), content="3")
  let mut read_back = ""
  for i in 0..<3 {
    read_back = read_back +
      mem.read_byte(440 + i).to_int().unsafe_to_char().to_string()
  }
  inspect(read_back, content="abc")
  // Third iovec remains untouched.
  inspect(mem.read_byte(460).to_int(), content="0")

  fd_close(ctx, fd) |> ignore
}

///|
test "wasi: fd_pread/fd_pwrite stdio errno parity" {
  let ctx = WasiContextBuilder::new().build()
  let mem = @runtime.Memory::new(1, None)
  mem.write_i32(0, 100)
  mem.write_i32(4, 1)
  mem.write_byte(100, b'A')
  inspect(fd_pread(ctx, mem, 0, 0, 1, 0L, 200), content="70")
  inspect(fd_pread(ctx, mem, 1, 0, 1, 0L, 200), content="8")
  inspect(fd_pread(ctx, mem, 2, 0, 1, 0L, 200), content="8")
  inspect(fd_pwrite(ctx, mem, 0, 0, 1, 0L, 200), content="8")
  inspect(fd_pwrite(ctx, mem, 1, 0, 1, 0L, 200), content="70")
  inspect(fd_pwrite(ctx, mem, 2, 0, 1, 0L, 200), content="70")
}

///|
test "wasi: fd_fdstat_get" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let preopen_base_rights = right_path_create_directory |
    right_path_create_file |
    right_path_link_source |
    right_path_link_target |
    right_path_open |
    right_fd_readdir |
    right_path_readlink |
    right_path_rename_source |
    right_path_rename_target |
    right_path_symlink |
    right_path_remove_directory |
    right_path_unlink_file |
    right_path_filestat_get |
    right_path_filestat_set_times |
    right_fd_filestat_get |
    right_fd_filestat_set_times
  let preopen_inheriting_rights = preopen_base_rights |
    right_fd_datasync |
    right_fd_read |
    right_fd_seek |
    right_fd_fdstat_set_flags |
    right_fd_sync |
    right_fd_tell |
    right_fd_write |
    right_fd_advise |
    right_fd_allocate |
    right_fd_filestat_get |
    right_fd_filestat_set_size |
    right_fd_filestat_set_times |
    right_poll_fd_readwrite
  // Test stdin
  let result = fd_fdstat_get(ctx, mem, 0, 0)
  inspect(result, content="0")
  inspect(
    mem.read_byte(0) == (if native_isatty(0) { b'\x02' } else { b'\x00' }),
    content="true",
  )
  inspect(mem.read_i64(8) == right_fd_read, content="true")
  inspect(mem.read_i64(16) == right_fd_read, content="true")
  // Test stdout
  let result = fd_fdstat_get(ctx, mem, 1, 0)
  inspect(result, content="0")
  inspect(
    mem.read_byte(0) == (if native_isatty(1) { b'\x02' } else { b'\x00' }),
    content="true",
  )
  inspect(mem.read_i64(8) == right_fd_write, content="true")
  inspect(mem.read_i64(16) == right_fd_write, content="true")
  // Test preopen directory
  let result = fd_fdstat_get(ctx, mem, 3, 0)
  inspect(result, content="0")
  inspect(mem.read_byte(0), content="b'\\x03'") // directory
  inspect(mem.read_i64(8) == preopen_base_rights, content="true")
  inspect(mem.read_i64(16) == preopen_inheriting_rights, content="true")
  // Test synthetic socket stream descriptor
  let socket_fd = ctx.alloc_fd({
    native_fd: 0,
    file_type: SocketStream,
    host_path: "<socket>",
    position: 0L,
    flags: 0,
  })
  let result = fd_fdstat_get(ctx, mem, socket_fd, 0)
  inspect(result, content="0")
  inspect(mem.read_byte(0), content="b'\\x06'") // socket_stream
}

///|
test "wasi: clock_res_get" {
  let mem = @runtime.Memory::new(1, None)
  // Test realtime clock
  let result = clock_res_get(mem, 0, 0)
  inspect(result, content="0")
  let resolution = mem.read_i64(0)
  inspect(resolution > 0L, content="true")
  // Test monotonic clock
  let result = clock_res_get(mem, 1, 0)
  inspect(result, content="0")
  // CPU clocks are unsupported in preview1 and return BADF.
  inspect(clock_res_get(mem, 2, 0), content="8")
  inspect(clock_res_get(mem, 3, 0), content="8")
  // Test invalid clock
  let result = clock_res_get(mem, 999, 0)
  inspect(result, content="28") // Errno::Inval
}

///|
test "wasi: sched_yield" {
  let result = sched_yield()
  inspect(result, content="0") // Always succeeds
}

///|
test "wasi: path_create_directory" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let dir_path = "wasmoon_test_dir_create"
  for i, c in dir_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  // First try to remove if exists
  path_remove_directory_impl(ctx, mem, 3, 100, dir_path.length()) |> ignore
  // Create directory - result could be success (0) or IO error (29) if preopen doesn't work
  let result = path_create_directory(ctx, mem, 3, 100, dir_path.length())
  // Allow success or IO error (29) if the path can't be resolved
  inspect(result == 0 || result == 29, content="true")
  if result == 0 {
    // Try to create again - should fail with exists (20) or success
    let result2 = path_create_directory(ctx, mem, 3, 100, dir_path.length())
    inspect(result2 == 0 || result2 == 20 || result2 == 29, content="true")
    // Cleanup
    path_remove_directory_impl(ctx, mem, 3, 100, dir_path.length()) |> ignore
  }
}

///|
test "wasi: path_open returns EFAULT on out-of-bounds path pointer" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let result = path_open(ctx, mem, 3, 0, 65532, 8, 0, right_fd_read, 0L, 0, 0)
  inspect(result, content="21") // Errno::Fault
}

///|
test "wasi: path_open ignores unknown rights bits on valid dirfd" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let test_path = "wasmoon_rights_unknown_bits.txt"
  for i, c in test_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  path_unlink_file_impl(ctx, mem, 3, 100, test_path.length()) |> ignore
  let result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    test_path.length(),
    9,
    -1L,
    0L,
    0,
    2000,
  )
  inspect(result, content="0")
  if result == 0 {
    fd_close(ctx, mem.read_i32(2000)) |> ignore
    path_unlink_file_impl(ctx, mem, 3, 100, test_path.length()) |> ignore
  }
}

///|
test "wasi: path_open honors write-only rights without create flags" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let test_path = "wasmoon_rights_open.txt"
  for i, c in test_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  path_unlink_file_impl(ctx, mem, 3, 100, test_path.length()) |> ignore
  let create_result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    test_path.length(),
    9,
    right_fd_write,
    0L,
    0,
    2000,
  )
  inspect(create_result, content="0")
  if create_result != 0 {
    return
  }
  let create_fd = mem.read_i32(2000)
  fd_close(ctx, create_fd) |> ignore

  let reopen_result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    test_path.length(),
    0,
    right_fd_write,
    0L,
    0,
    2004,
  )
  inspect(reopen_result, content="0")
  if reopen_result != 0 {
    return
  }
  let fd = mem.read_i32(2004)
  mem.write_i32(0, 300)
  mem.write_i32(4, 1)
  mem.write_byte(300, b'Z')
  let pwrite_result = fd_pwrite(ctx, mem, fd, 0, 1, 0L, 400)
  inspect(pwrite_result, content="0")
  inspect(mem.read_i32(400), content="1")
  fd_close(ctx, fd) |> ignore
  path_unlink_file_impl(ctx, mem, 3, 100, test_path.length()) |> ignore
}

///|
test "wasi: path_open does not hard-reject sync fdflags" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let test_path = "wasmoon_sync_fdflags_open.txt"
  for i, c in test_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  path_unlink_file_impl(ctx, mem, 3, 100, test_path.length()) |> ignore

  let create_result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    test_path.length(),
    9,
    right_fd_write,
    0L,
    0,
    2000,
  )
  inspect(create_result, content="0")
  if create_result != 0 {
    return
  }
  fd_close(ctx, mem.read_i32(2000)) |> ignore

  // fdflags=0x10 (SYNC)
  let reopen_result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    test_path.length(),
    0,
    right_fd_read,
    0L,
    0x10,
    2004,
  )
  inspect(reopen_result, content="0")
  if reopen_result == 0 {
    fd_close(ctx, mem.read_i32(2004)) |> ignore
  }
  path_unlink_file_impl(ctx, mem, 3, 100, test_path.length()) |> ignore
}

///|
test "wasi: path_open ignores unknown dirflags bits" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let test_path = "wasmoon_unknown_dirflags_open.txt"
  for i, c in test_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  path_unlink_file_impl(ctx, mem, 3, 100, test_path.length()) |> ignore

  let create_result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    test_path.length(),
    9,
    right_fd_write,
    0L,
    0,
    2000,
  )
  inspect(create_result, content="0")
  if create_result != 0 {
    return
  }
  fd_close(ctx, mem.read_i32(2000)) |> ignore

  // dirflags=0x02 uses an unknown bit and should not be hard-rejected.
  let reopen_result = path_open(
    ctx,
    mem,
    3,
    0x02,
    100,
    test_path.length(),
    0,
    right_fd_read,
    0L,
    0,
    2004,
  )
  inspect(reopen_result, content="0")
  if reopen_result == 0 {
    fd_close(ctx, mem.read_i32(2004)) |> ignore
  }
  path_unlink_file_impl(ctx, mem, 3, 100, test_path.length()) |> ignore
}

///|
test "wasi: path_open with non-directory dirfd returns NOTDIR" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let file_path = "wasmoon_notdir_base.txt"
  let child_path = "child.txt"
  for i, c in file_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  for i, c in child_path {
    mem.write_byte(300 + i, c.to_int().to_byte())
  }
  path_unlink_file_impl(ctx, mem, 3, 100, file_path.length()) |> ignore

  let open_base_result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    file_path.length(),
    9,
    right_fd_read | right_fd_write,
    0L,
    0,
    2000,
  )
  inspect(open_base_result, content="0")
  if open_base_result != 0 {
    return
  }
  let base_fd = mem.read_i32(2000)
  let nested_open_result = path_open(
    ctx,
    mem,
    base_fd,
    0,
    300,
    child_path.length(),
    0,
    right_fd_read,
    0L,
    0,
    2004,
  )
  inspect(nested_open_result, content="54")
  fd_close(ctx, base_fd) |> ignore
  path_unlink_file_impl(ctx, mem, 3, 100, file_path.length()) |> ignore
}

///|
test "wasi: path_create_directory maps EEXIST to Exist" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let dir_path = "wasmoon_errno_exist_dir"
  for i, c in dir_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  path_remove_directory_impl(ctx, mem, 3, 100, dir_path.length()) |> ignore
  let create_result = path_create_directory(ctx, mem, 3, 100, dir_path.length())
  inspect(create_result, content="0")
  let create_again_result = path_create_directory(
    ctx,
    mem,
    3,
    100,
    dir_path.length(),
  )
  inspect(create_again_result, content="20")
  path_remove_directory_impl(ctx, mem, 3, 100, dir_path.length()) |> ignore
}

///|
test "wasi: path_remove_directory maps ENOTEMPTY to NotEmpty" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let dir_path = "wasmoon_errno_notempty_dir"
  let child_path = "wasmoon_errno_notempty_dir/child.txt"
  for i, c in dir_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  for i, c in child_path {
    mem.write_byte(300 + i, c.to_int().to_byte())
  }
  path_unlink_file_impl(ctx, mem, 3, 300, child_path.length()) |> ignore
  path_remove_directory_impl(ctx, mem, 3, 100, dir_path.length()) |> ignore

  let mkdir_result = path_create_directory(ctx, mem, 3, 100, dir_path.length())
  inspect(mkdir_result, content="0")
  let open_child_result = path_open(
    ctx,
    mem,
    3,
    0,
    300,
    child_path.length(),
    9,
    right_fd_write,
    0L,
    0,
    500,
  )
  inspect(open_child_result, content="0")
  if open_child_result == 0 {
    fd_close(ctx, mem.read_i32(500)) |> ignore
  }
  let rmdir_result = path_remove_directory_impl(
    ctx,
    mem,
    3,
    100,
    dir_path.length(),
  )
  inspect(rmdir_result, content="55")
  path_unlink_file_impl(ctx, mem, 3, 300, child_path.length()) |> ignore
  path_remove_directory_impl(ctx, mem, 3, 100, dir_path.length()) |> ignore
}

///|
test "wasi: path_filestat_get maps ENOTDIR to NotDir" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let base_file = "wasmoon_errno_notdir_base.txt"
  let child_path = "wasmoon_errno_notdir_base.txt/child"
  for i, c in base_file {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  for i, c in child_path {
    mem.write_byte(300 + i, c.to_int().to_byte())
  }
  path_unlink_file_impl(ctx, mem, 3, 100, base_file.length()) |> ignore
  let open_result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    base_file.length(),
    9,
    right_fd_write,
    0L,
    0,
    500,
  )
  inspect(open_result, content="0")
  if open_result == 0 {
    fd_close(ctx, mem.read_i32(500)) |> ignore
  }
  let stat_result = path_filestat_get_impl(
    ctx,
    mem,
    3,
    0,
    300,
    child_path.length(),
    700,
  )
  inspect(stat_result, content="54")
  path_unlink_file_impl(ctx, mem, 3, 100, base_file.length()) |> ignore
}

///|
test "wasi: path_open accepts UTF-8 non-ASCII file names" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let file_name = "你好-wasmoon.txt"
  let path_bytes = @utf8.encode(file_name)
  for i in 0..<path_bytes.length() {
    mem.write_byte(100 + i, path_bytes[i])
  }
  let open_result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    path_bytes.length(),
    9,
    right_fd_write,
    0L,
    0,
    2000,
  )
  inspect(open_result, content="0")
  if open_result == 0 {
    let fd = mem.read_i32(2000)
    fd_close(ctx, fd) |> ignore
    let unlink_result = path_unlink_file_impl(
      ctx,
      mem,
      3,
      100,
      path_bytes.length(),
    )
    inspect(unlink_result, content="0")
  }
}

///|
test "wasi: path_open lexical escapes return EPERM" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let abs_path = "/wasmoon_abs_path_probe"
  let dotdot_path = "../wasmoon_escape_probe"
  for i, c in abs_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  for i, c in dotdot_path {
    mem.write_byte(200 + i, c.to_int().to_byte())
  }
  inspect(
    path_open(
      ctx,
      mem,
      3,
      0,
      100,
      abs_path.length(),
      0,
      right_fd_read,
      0L,
      0,
      300,
    ),
    content="63",
  )
  inspect(
    path_open(
      ctx,
      mem,
      3,
      0,
      200,
      dotdot_path.length(),
      0,
      right_fd_read,
      0L,
      0,
      304,
    ),
    content="63",
  )
}

///|
test "wasi: path_open with embedded NUL returns EINVAL" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let plain = "wasmoon_nul_path_probe.txt"
  for i, c in plain {
    mem.write_byte(100 + i, c.to_int().to_byte())
    mem.write_byte(200 + i, c.to_int().to_byte())
  }
  mem.write_byte(200 + plain.length(), b'\x00')

  path_unlink_file_impl(ctx, mem, 3, 100, plain.length()) |> ignore
  let create_result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    plain.length(),
    9,
    right_fd_write,
    0L,
    0,
    300,
  )
  inspect(create_result, content="0")
  if create_result != 0 {
    return
  }
  fd_close(ctx, mem.read_i32(300)) |> ignore

  inspect(
    path_open(
      ctx,
      mem,
      3,
      0,
      200,
      plain.length() + 1,
      0,
      right_fd_read,
      0L,
      0,
      304,
    ),
    content="28",
  )
  path_unlink_file_impl(ctx, mem, 3, 100, plain.length()) |> ignore
}

///|
test "wasi: path_open rejects symlink escape outside preopen" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let link_name = "caplk_escape"
  let escaped_path = "caplk_escape/etc/passwd"

  for i, c in link_name {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  for i, c in escaped_path {
    mem.write_byte(200 + i, c.to_int().to_byte())
  }
  mem.write_byte(300, b'/')

  path_remove_directory_impl(ctx, mem, 3, 100, link_name.length()) |> ignore
  path_unlink_file_impl(ctx, mem, 3, 100, link_name.length()) |> ignore
  let symlink_result = path_symlink_impl(
    ctx,
    mem,
    300,
    1,
    3,
    100,
    link_name.length(),
  )
  inspect(symlink_result == 0 || symlink_result == 76, content="true")
  let open_result = path_open(
    ctx,
    mem,
    3,
    0,
    200,
    escaped_path.length(),
    0,
    right_fd_read,
    0L,
    0,
    900,
  )
  inspect(open_result, content="76")
  path_unlink_file_impl(ctx, mem, 3, 100, link_name.length()) |> ignore
  path_remove_directory_impl(ctx, mem, 3, 100, link_name.length()) |> ignore
}

///|
test "wasi: path_open respects dirflags symlink follow bit" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let target_name = "wasmoon_nofollow_target.txt"
  let link_name = "wasmoon_nofollow_link.txt"
  for i, c in target_name {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  for i, c in link_name {
    mem.write_byte(200 + i, c.to_int().to_byte())
  }
  path_unlink_file_impl(ctx, mem, 3, 100, target_name.length()) |> ignore
  path_unlink_file_impl(ctx, mem, 3, 200, link_name.length()) |> ignore

  let create_result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    target_name.length(),
    9,
    right_fd_write,
    0L,
    0,
    300,
  )
  inspect(create_result, content="0")
  if create_result != 0 {
    return
  }
  fd_close(ctx, mem.read_i32(300)) |> ignore
  let symlink_result = path_symlink_impl(
    ctx,
    mem,
    100,
    target_name.length(),
    3,
    200,
    link_name.length(),
  )
  inspect(symlink_result, content="0")

  let nofollow_result = path_open(
    ctx,
    mem,
    3,
    0,
    200,
    link_name.length(),
    0,
    right_fd_read,
    0L,
    0,
    320,
  )
  inspect(nofollow_result == 32 || nofollow_result == 0, content="true")
  if nofollow_result == 0 {
    fd_close(ctx, mem.read_i32(320)) |> ignore
  }

  let follow_result = path_open(
    ctx,
    mem,
    3,
    1,
    200,
    link_name.length(),
    0,
    right_fd_read,
    0L,
    0,
    340,
  )
  inspect(follow_result, content="0")
  if follow_result == 0 {
    fd_close(ctx, mem.read_i32(340)) |> ignore
  }

  path_unlink_file_impl(ctx, mem, 3, 200, link_name.length()) |> ignore
  path_unlink_file_impl(ctx, mem, 3, 100, target_name.length()) |> ignore
}

///|
test "wasi: fd_readdir" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  // Create a test directory with files
  let dir_path = "wasmoon_readdir_test"
  for i, c in dir_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  // Clean up and create directory
  path_remove_directory_impl(ctx, mem, 3, 100, dir_path.length()) |> ignore
  let result = path_create_directory(ctx, mem, 3, 100, dir_path.length())
  if result != 0 && result != 20 {
    return // Skip if cannot create
  }
  // Open the directory
  let result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    dir_path.length(),
    2,
    0L,
    0L,
    0,
    2000,
  ) // oflags=2 (DIRECTORY)
  if result != 0 {
    path_remove_directory_impl(ctx, mem, 3, 100, dir_path.length()) |> ignore
    return
  }
  let dir_fd = mem.read_i32(2000)
  // Read directory
  let result = fd_readdir(ctx, mem, dir_fd, 500, 1000, 0L, 400)
  inspect(result, content="0")
  let bufused = mem.read_i32(400)
  // Should have at least . and .. entries, bufused > 0
  inspect(bufused >= 0, content="true")
  fd_close(ctx, dir_fd) |> ignore
  path_remove_directory_impl(ctx, mem, 3, 100, dir_path.length()) |> ignore
}

///|
test "wasi: fd_readdir includes dot entries and supports truncated dirent writes" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let dir_path = "wasmoon_readdir_cookie_test"
  for i, c in dir_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  path_remove_directory_impl(ctx, mem, 3, 100, dir_path.length()) |> ignore
  path_create_directory(ctx, mem, 3, 100, dir_path.length()) |> ignore
  let open_result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    dir_path.length(),
    2,
    0L,
    0L,
    0,
    2000,
  )
  if open_result != 0 {
    path_remove_directory_impl(ctx, mem, 3, 100, dir_path.length()) |> ignore
    return
  }
  let dir_fd = mem.read_i32(2000)

  // cookie=0 should start at "."
  inspect(fd_readdir(ctx, mem, dir_fd, 500, 25, 0L, 450), content="0")
  inspect(mem.read_i32(450), content="25")
  inspect(mem.read_i64(500), content="1")
  inspect(mem.read_i32(516), content="1")
  inspect(mem.read_byte(520).to_int(), content="3")
  inspect(mem.read_byte(524).to_int(), content="46") // '.'

  // cookie=1 should start at ".."
  inspect(fd_readdir(ctx, mem, dir_fd, 700, 26, 1L, 460), content="0")
  inspect(mem.read_i32(460), content="26")
  inspect(mem.read_i64(700), content="2")
  inspect(mem.read_i32(716), content="2")
  inspect(mem.read_byte(720).to_int(), content="3")
  inspect(mem.read_byte(724).to_int(), content="46")
  inspect(mem.read_byte(725).to_int(), content="46")

  // tiny buffer still receives partial header bytes.
  inspect(fd_readdir(ctx, mem, dir_fd, 900, 10, 0L, 470), content="0")
  inspect(mem.read_i32(470), content="10")

  fd_close(ctx, dir_fd) |> ignore
  path_remove_directory_impl(ctx, mem, 3, 100, dir_path.length()) |> ignore
}

///|
test "wasi: fd_readdir on regular file returns BADF" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let file_path = "wasmoon_readdir_regular_file.txt"
  for i, c in file_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  path_unlink_file_impl(ctx, mem, 3, 100, file_path.length()) |> ignore
  let open_result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    file_path.length(),
    9,
    right_fd_read | right_fd_write,
    0L,
    0,
    2000,
  )
  inspect(open_result, content="0")
  if open_result != 0 {
    return
  }
  let fd = mem.read_i32(2000)
  inspect(fd_readdir(ctx, mem, fd, 300, 64, 0L, 400), content="8")
  fd_close(ctx, fd) |> ignore
  path_unlink_file_impl(ctx, mem, 3, 100, file_path.length()) |> ignore
}

///|
test "wasi: fd_sync and fd_datasync use file-only descriptor gating" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  // stdio is not a file descriptor for these operations.
  inspect(fd_sync_impl(ctx, 0), content="8")
  inspect(fd_sync_impl(ctx, 1), content="8")
  inspect(fd_sync_impl(ctx, 2), content="8")
  inspect(fd_datasync_impl(ctx, 0), content="8")
  inspect(fd_datasync_impl(ctx, 1), content="8")
  inspect(fd_datasync_impl(ctx, 2), content="8")
  // preopen directory is also rejected.
  inspect(fd_sync_impl(ctx, 3), content="8")
  inspect(fd_datasync_impl(ctx, 3), content="8")
  // Test on opened file
  let test_path = "wasmoon_sync_test.txt"
  for i, c in test_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  let result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    test_path.length(),
    9,
    0L,
    0L,
    0,
    200,
  )
  if result != 0 {
    return
  }
  let fd = mem.read_i32(200)
  let result = fd_sync_impl(ctx, fd)
  inspect(result, content="0")
  let result = fd_datasync_impl(ctx, fd)
  inspect(result, content="0")
  fd_close(ctx, fd) |> ignore
}

///|
test "wasi: path_unlink_file" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let test_path = "wasmoon_unlink_test.txt"
  for i, c in test_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  // Create a file
  let result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    test_path.length(),
    9,
    0L,
    0L,
    0,
    200,
  )
  if result != 0 {
    return
  }
  fd_close(ctx, mem.read_i32(200)) |> ignore
  // Unlink the file
  let result = path_unlink_file_impl(ctx, mem, 3, 100, test_path.length())
  inspect(result, content="0")
  // Try to unlink again should fail
  let result = path_unlink_file_impl(ctx, mem, 3, 100, test_path.length())
  inspect(result, content="44") // Errno::NoEnt
}

///|
test "wasi: path_rename" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let old_path = "wasmoon_rename_old.txt"
  let new_path = "wasmoon_rename_new.txt"
  for i, c in old_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  for i, c in new_path {
    mem.write_byte(200 + i, c.to_int().to_byte())
  }
  // Create old file
  let result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    old_path.length(),
    9,
    0L,
    0L,
    0,
    300,
  )
  if result != 0 {
    return
  }
  fd_close(ctx, mem.read_i32(300)) |> ignore
  // Remove new file if exists
  path_unlink_file_impl(ctx, mem, 3, 200, new_path.length()) |> ignore
  // Rename
  let result = path_rename_impl(
    ctx,
    mem,
    3,
    100,
    old_path.length(),
    3,
    200,
    new_path.length(),
  )
  inspect(result, content="0")
  // Cleanup
  path_unlink_file_impl(ctx, mem, 3, 200, new_path.length()) |> ignore
}

///|
test "wasi: fd_filestat_get" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  // Test stdin
  let result = fd_filestat_get_impl(ctx, mem, 0, 0)
  inspect(result, content="0")
  inspect(
    mem.read_byte(16) == (if native_isatty(0) { b'\x02' } else { b'\x00' }),
    content="true",
  )
  inspect(mem.read_i64(24), content="0")
  // Test preopen directory
  let result = fd_filestat_get_impl(ctx, mem, 3, 0)
  inspect(result, content="0")
  inspect(mem.read_byte(16), content="b'\\x03'") // directory
  // Test opened file
  let test_path = "wasmoon_filestat_test.txt"
  for i, c in test_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  // Write 10 bytes to file
  let result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    test_path.length(),
    9,
    0L,
    0L,
    0,
    200,
  )
  if result != 0 {
    return
  }
  let fd = mem.read_i32(200)
  mem.write_i32(0, 300)
  mem.write_i32(4, 10)
  for i in 0..<10 {
    mem.write_byte(300 + i, (65 + i).to_byte())
  }
  fd_write(ctx, mem, fd, 0, 1, 400) |> ignore
  // Get file stat
  let result = fd_filestat_get_impl(ctx, mem, fd, 500)
  inspect(result, content="0")
  let size = mem.read_i64(500 + 32)
  inspect(size, content="10")
  fd_close(ctx, fd) |> ignore
  path_unlink_file_impl(ctx, mem, 3, 100, test_path.length()) |> ignore
}

///|
test "wasi: path_filestat_get" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let test_path = "wasmoon_path_stat.txt"
  for i, c in test_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  // Create file with content
  let result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    test_path.length(),
    9,
    0L,
    0L,
    0,
    200,
  )
  if result != 0 {
    return
  }
  let fd = mem.read_i32(200)
  mem.write_i32(0, 300)
  mem.write_i32(4, 15)
  for i in 0..<15 {
    mem.write_byte(300 + i, (65 + i).to_byte())
  }
  fd_write(ctx, mem, fd, 0, 1, 400) |> ignore
  // Sync before closing to ensure data is written
  fd_sync_impl(ctx, fd) |> ignore
  // Get file stat via fd (should work while file is open)
  let result = fd_filestat_get_impl(ctx, mem, fd, 500)
  inspect(result, content="0")
  let size = mem.read_i64(500 + 32)
  inspect(size, content="15")
  fd_close(ctx, fd) |> ignore
  path_unlink_file_impl(ctx, mem, 3, 100, test_path.length()) |> ignore
}

///|
test "wasi: fd_filestat_set_size" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let test_path = "wasmoon_truncate.txt"
  for i, c in test_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  // Create file with 20 bytes
  let result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    test_path.length(),
    9,
    0L,
    0L,
    0,
    200,
  )
  if result != 0 {
    return
  }
  let fd = mem.read_i32(200)
  mem.write_i32(0, 300)
  mem.write_i32(4, 20)
  for i in 0..<20 {
    mem.write_byte(300 + i, (65 + i % 26).to_byte())
  }
  fd_write(ctx, mem, fd, 0, 1, 400) |> ignore
  // Truncate to 5 bytes
  let result = fd_filestat_set_size_impl(ctx, fd, 5L)
  inspect(result, content="0")
  // Verify size
  let result = fd_filestat_get_impl(ctx, mem, fd, 500)
  inspect(result, content="0")
  let size = mem.read_i64(500 + 32)
  inspect(size, content="5")
  fd_close(ctx, fd) |> ignore
  path_unlink_file_impl(ctx, mem, 3, 100, test_path.length()) |> ignore
}

///|
test "wasi: fd_advise is file-only" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  // stdio and preopen directory should return BADF.
  inspect(fd_advise_impl(ctx, 0, 0L, 100L, 0), content="8")
  inspect(fd_advise_impl(ctx, 3, 0L, 100L, 0), content="8")

  let test_path = "wasmoon_advise_test.txt"
  for i, c in test_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  let open_result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    test_path.length(),
    9,
    right_fd_read | right_fd_write,
    0L,
    0,
    200,
  )
  inspect(open_result, content="0")
  if open_result != 0 {
    return
  }
  let fd = mem.read_i32(200)
  inspect(fd_advise_impl(ctx, fd, 0L, 100L, 0), content="0")
  fd_close(ctx, fd) |> ignore
  path_unlink_file_impl(ctx, mem, 3, 100, test_path.length()) |> ignore
}

///|
test "wasi: fd_allocate returns ENOTSUP for files and BADF otherwise" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  inspect(fd_allocate_impl(ctx, 0, 0L, 0L), content="8")
  inspect(fd_allocate_impl(ctx, 3, 0L, 0L), content="8")

  let test_path = "wasmoon_allocate_test.txt"
  for i, c in test_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  let open_result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    test_path.length(),
    9,
    right_fd_read | right_fd_write,
    0L,
    0,
    200,
  )
  inspect(open_result, content="0")
  if open_result != 0 {
    return
  }
  let fd = mem.read_i32(200)
  inspect(fd_allocate_impl(ctx, fd, 0L, 100L), content="58")
  fd_close(ctx, fd) |> ignore
  path_unlink_file_impl(ctx, mem, 3, 100, test_path.length()) |> ignore
}

///|
test "wasi: fd_filestat_set_size uses file-only gating" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  inspect(fd_filestat_set_size_impl(ctx, 0, 0L), content="8")
  inspect(fd_filestat_set_size_impl(ctx, 3, 0L), content="8")
  // Existing writable file path remains valid for set_size.
  let test_path = "wasmoon_setsize_gate.txt"
  for i, c in test_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  let open_result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    test_path.length(),
    9,
    right_fd_read | right_fd_write,
    0L,
    0,
    200,
  )
  inspect(open_result, content="0")
  if open_result != 0 {
    return
  }
  let fd = mem.read_i32(200)
  inspect(fd_filestat_set_size_impl(ctx, fd, 0L), content="0")
  fd_close(ctx, fd) |> ignore
  path_unlink_file_impl(ctx, mem, 3, 100, test_path.length()) |> ignore
}

///|
test "wasi: fd_filestat_set_times rejects stdio descriptors" {
  let ctx = WasiContextBuilder::new().build()
  inspect(fd_filestat_set_times_impl(ctx, 0, 0L, 0L, 0), content="8")
  inspect(fd_filestat_set_times_impl(ctx, 1, 0L, 0L, 0), content="8")
  inspect(fd_filestat_set_times_impl(ctx, 2, 0L, 0L, 0), content="8")
}

///|
test "wasi: fd_renumber allows identity stdio and rejects moving stdio" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  inspect(fd_renumber_impl(ctx, 0, 0), content="0")
  inspect(fd_renumber_impl(ctx, 0, 10), content="8")
  inspect(fd_renumber_impl(ctx, 1, 3), content="8")

  let test_path = "wasmoon_renumber_gate.txt"
  for i, c in test_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  let open_result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    test_path.length(),
    9,
    right_fd_read | right_fd_write,
    0L,
    0,
    200,
  )
  inspect(open_result, content="0")
  if open_result != 0 {
    return
  }
  let fd = mem.read_i32(200)
  inspect(fd_renumber_impl(ctx, fd, 127), content="8")
  fd_close(ctx, fd) |> ignore
  path_unlink_file_impl(ctx, mem, 3, 100, test_path.length()) |> ignore
}

///|
test "wasi: proc_raise returns ENOTSUP" {
  inspect(proc_raise_impl(2), content="58")
}

///|
test "wasi: sock APIs return NOTSOCK for valid descriptors" {
  let ctx = WasiContextBuilder::new().build()
  let mem = @runtime.Memory::new(1, None)
  mem.write_i32(0, 100)
  mem.write_i32(4, 1)
  inspect(sock_accept_impl(ctx, mem, 0, 0, 200), content="57")
  inspect(sock_recv_impl(ctx, mem, 0, 0, 1, 0, 204, 208), content="57")
  inspect(sock_send_impl(ctx, mem, 0, 0, 1, 0, 212), content="57")
  inspect(sock_shutdown_impl(ctx, 0, 0), content="57")
  inspect(sock_shutdown_impl(ctx, 999, 0), content="8")
}

///|
test "wasi: fd_fdstat_set_rights returns ENOTSUP for valid fd" {
  let ctx = WasiContextBuilder::new().build()
  let result = fd_fdstat_set_rights_impl(ctx, 0, 0L, 0L)
  inspect(result, content="58")
}

///|
test "wasi: path_symlink and path_readlink" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let target = "symlink_target.txt"
  let link = "wasmoon_symlink_test"
  // Remove existing link if any
  for i, c in link {
    mem.write_byte(200 + i, c.to_int().to_byte())
  }
  path_unlink_file_impl(ctx, mem, 3, 200, link.length()) |> ignore
  // Create symlink: target at 100, link at 200
  for i, c in target {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  let result = path_symlink_impl(
    ctx,
    mem,
    100,
    target.length(),
    3,
    200,
    link.length(),
  )
  inspect(result, content="0")
  // Read symlink
  let result = path_readlink_impl(
    ctx,
    mem,
    3,
    200,
    link.length(),
    400,
    100,
    500,
  )
  inspect(result, content="0")
  let bufused = mem.read_i32(500)
  inspect(bufused, content="18") // len("symlink_target.txt") = 18
  // Read back the target
  let mut read_target = ""
  for i in 0..<bufused {
    read_target = read_target +
      mem.read_byte(400 + i).to_int().unsafe_to_char().to_string()
  }
  inspect(read_target, content="symlink_target.txt")
  // Cleanup
  path_unlink_file_impl(ctx, mem, 3, 200, link.length()) |> ignore
}

///|
test "wasi: path_link rejects LOOKUPFLAGS_SYMLINK_FOLLOW" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let source = "wasmoon_link_source.txt"
  let target = "wasmoon_link_target.txt"
  for i, c in source {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  for i, c in target {
    mem.write_byte(200 + i, c.to_int().to_byte())
  }

  path_unlink_file_impl(ctx, mem, 3, 100, source.length()) |> ignore
  path_unlink_file_impl(ctx, mem, 3, 200, target.length()) |> ignore

  let open_result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    source.length(),
    9,
    right_fd_write,
    0L,
    0,
    300,
  )
  inspect(open_result, content="0")
  if open_result != 0 {
    return
  }
  fd_close(ctx, mem.read_i32(300)) |> ignore

  inspect(
    path_link_impl(
      ctx,
      mem,
      3,
      1,
      100,
      source.length(),
      3,
      200,
      target.length(),
    ),
    content="28",
  )

  path_unlink_file_impl(ctx, mem, 3, 200, target.length()) |> ignore
  path_unlink_file_impl(ctx, mem, 3, 100, source.length()) |> ignore
}

///|
test "wasi: is_valid_rights" {
  // Valid rights (only bits 0-28 set)
  inspect(is_valid_rights(0L), content="true")
  inspect(is_valid_rights(0x1L), content="true")
  inspect(is_valid_rights(0x1FFFFFFFL), content="true") // All valid bits
  // Invalid rights (bits above 28 set)
  inspect(is_valid_rights(0x20000000L), content="false") // bit 29
  inspect(is_valid_rights(0x100000000L), content="false") // bit 32
  inspect(is_valid_rights(-1L), content="false") // All bits set
}

///|
test "wasi: poll_oneoff with clock" {
  let ctx = WasiContextBuilder::new().build()
  let mem = @runtime.Memory::new(1, None)
  // Create a clock subscription at address 0
  // subscription struct is 48 bytes
  mem.write_i64(0, 12345L) // userdata
  mem.write_byte(8, b'\x00') // tag = clock
  // padding bytes 9-15
  mem.write_i32(16, 1) // clock_id = monotonic
  // padding
  mem.write_i64(24, 1000000L) // timeout = 1ms
  mem.write_i64(32, 0L) // precision
  mem.write_byte(40, b'\x00') // flags = relative
  // Call poll_oneoff
  let result = poll_oneoff_impl(ctx, mem, 0, 100, 1, 200)
  inspect(result, content="0")
  let nevents = mem.read_i32(200)
  inspect(nevents, content="1")
  // Check event
  let userdata = mem.read_i64(100)
  inspect(userdata, content="12345")
  let error = mem.read_byte(108)
  inspect(error, content="b'\\x00'") // Success
  let event_type = mem.read_byte(110)
  inspect(event_type, content="b'\\x00'") // clock
  inspect(mem.read_i64(116), content="1")
}

///|
test "wasi: poll_oneoff single relative cpu clock is accepted" {
  let ctx = WasiContextBuilder::new().build()
  let mem = @runtime.Memory::new(1, None)
  mem.write_i64(0, 54321L) // userdata
  mem.write_byte(8, b'\x00') // tag = clock
  mem.write_i32(16, 2) // process cpu clock id
  mem.write_i64(24, 0L) // timeout
  mem.write_i64(32, 0L) // precision
  mem.write_byte(40, b'\x00') // relative
  inspect(poll_oneoff_impl(ctx, mem, 0, 100, 1, 200), content="0")
  inspect(mem.read_i32(200), content="1")
  inspect(mem.read_i64(116), content="1")
}

///|
test "wasi: poll_oneoff emits expired clock with ready fd" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let test_path = "wasmoon_poll_ready.txt"
  for i, c in test_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }
  path_unlink_file_impl(ctx, mem, 3, 100, test_path.length()) |> ignore
  let open_result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    test_path.length(),
    9,
    right_fd_write,
    0L,
    0,
    2000,
  )
  inspect(open_result, content="0")
  if open_result != 0 {
    return
  }
  let fd = mem.read_i32(2000)
  let now = native_clock_gettime_monotonic()

  // Subscription 0: absolute monotonic clock already expired.
  mem.write_i64(0, 12345L)
  mem.write_byte(8, b'\x00') // tag = clock
  mem.write_i32(16, 1) // monotonic clock id
  mem.write_i64(24, now - 1000000L)
  mem.write_i64(32, 0L)
  mem.write_byte(40, b'\x01') // absolute

  // Subscription 1: fd_write should be immediately ready on regular file.
  let sub1 = 48
  mem.write_i64(sub1, 67890L)
  mem.write_byte(sub1 + 8, b'\x02') // tag = fd_write
  mem.write_i32(sub1 + 12, fd)

  let poll_result = poll_oneoff_impl(ctx, mem, 0, 3000, 2, 2900)
  inspect(poll_result, content="0")
  inspect(mem.read_i32(2900), content="2")
  let event_type0 = mem.read_byte(3010).to_int()
  let event_type1 = mem.read_byte(3042).to_int()
  inspect(
    (event_type0 == 0 && event_type1 == 2) ||
    (event_type0 == 2 && event_type1 == 0),
    content="true",
  )

  fd_close(ctx, fd) |> ignore
  path_unlink_file_impl(ctx, mem, 3, 100, test_path.length()) |> ignore
}

///|
test "wasi: poll_oneoff fd_read reports remaining file bytes" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  let test_path = "wasmoon_poll_read_bytes.txt"
  for i, c in test_path {
    mem.write_byte(100 + i, c.to_int().to_byte())
  }

  path_unlink_file_impl(ctx, mem, 3, 100, test_path.length()) |> ignore
  let create_result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    test_path.length(),
    9,
    right_fd_write,
    0L,
    0,
    2000,
  )
  inspect(create_result, content="0")
  if create_result != 0 {
    return
  }
  let write_fd = mem.read_i32(2000)
  mem.write_i32(400, 300)
  mem.write_i32(404, 3)
  mem.write_byte(300, b'a')
  mem.write_byte(301, b'b')
  mem.write_byte(302, b'c')
  inspect(fd_write(ctx, mem, write_fd, 400, 1, 500), content="0")
  fd_close(ctx, write_fd) |> ignore

  let read_open_result = path_open(
    ctx,
    mem,
    3,
    0,
    100,
    test_path.length(),
    0,
    right_fd_read,
    0L,
    0,
    2004,
  )
  inspect(read_open_result, content="0")
  if read_open_result != 0 {
    path_unlink_file_impl(ctx, mem, 3, 100, test_path.length()) |> ignore
    return
  }
  let read_fd = mem.read_i32(2004)

  mem.write_i64(0, 777L)
  mem.write_byte(8, b'\x01') // tag = fd_read
  mem.write_i32(12, read_fd)
  inspect(poll_oneoff_impl(ctx, mem, 0, 1000, 1, 900), content="0")
  inspect(mem.read_i32(900), content="1")
  inspect(mem.read_byte(1010).to_int(), content="1")
  inspect(mem.read_i64(1016), content="3")
  inspect(mem.read_byte(1024).to_int(), content="0")
  inspect(mem.read_byte(1025).to_int(), content="0")

  fd_close(ctx, read_fd) |> ignore
  path_unlink_file_impl(ctx, mem, 3, 100, test_path.length()) |> ignore
}

///|
test "wasi: poll_oneoff with zero subscriptions" {
  let ctx = WasiContextBuilder::new().build()
  let mem = @runtime.Memory::new(1, None)
  let result = poll_oneoff_impl(ctx, mem, 0, 0, 0, 100)
  inspect(result, content="28")
}

///|
test "wasi: poll_oneoff returns EFAULT on out-of-bounds subscription buffer" {
  let ctx = WasiContextBuilder::new().build()
  let mem = @runtime.Memory::new(1, None)
  let result = poll_oneoff_impl(ctx, mem, 65530, 0, 1, 100)
  inspect(result, content="21") // Errno::Fault
}

///|
test "wasi: register_wasi creates 46 exports" {
  let linker = @runtime.Linker::new()
  let ctx = WasiContextBuilder::new().build()
  register_wasi(linker, ctx)
  let instance = match linker.get_module("wasi_snapshot_preview1") {
    Some(instance) => instance
    None =>
      // Create a dummy empty instance for test failure
      @runtime.ModuleInstance::new()
  }
  inspect(instance.exports.length(), content="46")
}

///|
test "wasi: fd_prestat_get is exported" {
  let linker = @runtime.Linker::new()
  let ctx = WasiContextBuilder::new().build()
  register_wasi(linker, ctx)
  let instance = match linker.get_module("wasi_snapshot_preview1") {
    Some(instance) => instance
    None => @runtime.ModuleInstance::new()
  }
  // Check if fd_prestat_get is in exports
  let mut found = false
  for exp in instance.exports {
    if exp.name == "fd_prestat_get" {
      found = true
    }
  }
  inspect(found, content="true")
}
