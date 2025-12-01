///|
test "wasi: fd_write to stdout" {
  let ctx = WasiContextBuilder::new().build()
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
  // Check that time is non-zero (timestamp written to address 0)
  let time = mem.read_i32(0)
  inspect(time > 0, content="true")
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
  // Other fds can be "closed" (returns success even if not open)
  inspect(fd_close(ctx, 3), content="0") // Success
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
