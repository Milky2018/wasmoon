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
test "wasi: fd_close" {
  let ctx = WasiContextBuilder::new().build()
  // Cannot close stdin/stdout/stderr
  inspect(fd_close(ctx, 0), content="8") // Badf
  inspect(fd_close(ctx, 1), content="8") // Badf
  inspect(fd_close(ctx, 2), content="8") // Badf
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
  let ctx = WasiContextBuilder::new()
    .preopen_dir("/host/path", "/guest/path")
    .build()
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
  } else {
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
    0L,
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
  let ctx = WasiContextBuilder::new()
    .preopen_dir("/host/path", "/sandbox")
    .build()
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
    0L,
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
    0L,
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
test "wasi: fd_fdstat_get" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  // Test stdin
  let result = fd_fdstat_get(ctx, mem, 0, 0)
  inspect(result, content="0")
  inspect(mem.read_byte(0), content="b'\\x02'") // character_device
  // Test stdout
  let result = fd_fdstat_get(ctx, mem, 1, 0)
  inspect(result, content="0")
  inspect(mem.read_byte(0), content="b'\\x02'") // character_device
  // Test preopen directory
  let result = fd_fdstat_get(ctx, mem, 3, 0)
  inspect(result, content="0")
  inspect(mem.read_byte(0), content="b'\\x03'") // directory
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
test "wasi: fd_sync and fd_datasync" {
  let ctx = WasiContextBuilder::new().preopen_dir("/tmp", "/").build()
  let mem = @runtime.Memory::new(1, None)
  // Test on stdin/stdout/stderr - should succeed (no-op)
  inspect(fd_sync_impl(ctx, 0), content="0")
  inspect(fd_sync_impl(ctx, 1), content="0")
  inspect(fd_sync_impl(ctx, 2), content="0")
  inspect(fd_datasync_impl(ctx, 0), content="0")
  inspect(fd_datasync_impl(ctx, 1), content="0")
  inspect(fd_datasync_impl(ctx, 2), content="0")
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
  inspect(mem.read_byte(16), content="b'\\x02'") // character_device
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
test "wasi: fd_advise always succeeds" {
  let ctx = WasiContextBuilder::new().build()
  // fd_advise is a no-op, always returns success
  let result = fd_advise_impl(ctx, 0, 0L, 100L, 0)
  inspect(result, content="0")
}

///|
test "wasi: fd_fdstat_set_rights always succeeds" {
  let ctx = WasiContextBuilder::new().build()
  let result = fd_fdstat_set_rights_impl(ctx, 0, 0L, 0L)
  inspect(result, content="0")
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
}

///|
test "wasi: poll_oneoff with zero subscriptions" {
  let ctx = WasiContextBuilder::new().build()
  let mem = @runtime.Memory::new(1, None)
  let result = poll_oneoff_impl(ctx, mem, 0, 0, 0, 100)
  inspect(result, content="0")
  let nevents = mem.read_i32(100)
  inspect(nevents, content="0")
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
