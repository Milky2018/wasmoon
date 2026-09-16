///|
test "Preview 1 allocation and positioned append preserve the logical cursor" {
  let path = @test_fs.temp_dir() +
    "/wasmoon-p1-file-\{@wasi.native_clock_gettime_monotonic()}"
  let native = @wasi.native_open(path, [ReadWrite, Create, Exclusive], 0o600).unwrap()
  defer @wasi.native_unlinkat(0, path, 0) |> ignore
  let ctx = @wasi.WasiContextBuilder::WasiContextBuilder().build()
  let fd = ctx.alloc_fd({
    native_fd: native,
    file_type: RegularFile,
    host_path: path,
    position: 0L,
    socket_input: b"",
    flags: 0,
    rights_base: 0x1FFFFFFFL,
    rights_inheriting: 0L,
  })
  defer ctx.close_fd(fd) |> ignore
  let store = @runtime.Store::Store()
  defer store.close()
  let mem = @runtime.Memory::Memory(1, None)
  store.alloc_mem(mem) |> ignore
  mem.write_i32(0, 100)
  mem.write_i32(4, 3)
  for i, byte in b"abc" {
    mem.write_byte(100 + i, byte)
  }
  inspect(@wasi.fd_write(ctx, mem, fd, 0, 1, 16), content="0")
  inspect(@wasi.fd_allocate_impl(ctx, fd, 8L, 8L), content="0")
  inspect(@wasi.fd_allocate_impl(ctx, fd, 0L, 4L), content="0")
  inspect(@wasi.native_fstat(native).unwrap().size, content="16")
  inspect(@wasi.fd_tell(ctx, mem, fd, 24), content="0")
  inspect(mem.read_i64(24), content="3")
  inspect(
    @wasi.fd_allocate_impl(ctx, fd, 0x7FFFFFFFFFFFFFFFL, 1L),
    content="61",
  )
  inspect(@wasi.fd_allocate_impl(ctx, fd, 0L, 0L), content="28")
  inspect(@wasi.fd_pread(ctx, mem, fd, 0, 1, 0L, 16), content="0")
  inspect(mem.read_bytes(100, 3), content="b\"abc\"")
  inspect(@wasi.fd_tell(ctx, mem, fd, 24), content="0")
  inspect(mem.read_i64(24), content="3")
  inspect(@wasi.fd_filestat_set_size_impl(ctx, fd, 3L), content="0")
  inspect(@wasi.fd_fdstat_set_flags_impl(ctx, fd, 1), content="0")
  mem.write_i32(4, 1)
  mem.write_byte(100, b'x')
  inspect(@wasi.fd_pwrite(ctx, mem, fd, 0, 1, 999L, 16), content="0")
  inspect(@wasi.fd_tell(ctx, mem, fd, 24), content="0")
  inspect(mem.read_i64(24), content="3")
  inspect(@wasi.native_fstat(native).unwrap().size, content="4")
  inspect(@wasi.fd_read(ctx, mem, fd, 0, 1, 16), content="0")
  inspect(mem.read_byte(100) == b'x', content="true")
  inspect(@wasi.fd_tell(ctx, mem, fd, 24), content="0")
  inspect(mem.read_i64(24), content="4")
  for flags in [2, 8, 16, 26, 0] {
    inspect(@wasi.fd_fdstat_set_flags_impl(ctx, fd, flags), content="0")
    inspect(@wasi.fd_fdstat_get(ctx, mem, fd, 200), content="0")
    inspect(mem.read_byte(202).to_int() == flags, content="true")
    inspect(@wasi.fd_pwrite(ctx, mem, fd, 0, 1, 0L, 16), content="0")
    inspect(@wasi.fd_pread(ctx, mem, fd, 0, 1, 0L, 16), content="0")
  }
  for count in [0x20000000, 0x40000000, 0x7FFFFFFF] {
    inspect(@wasi.fd_read(ctx, mem, fd, 0, count, 16), content="21")
    inspect(@wasi.fd_write(ctx, mem, fd, 0, count, 16), content="21")
    inspect(@wasi.fd_pread(ctx, mem, fd, 0, count, 0L, 16), content="21")
    inspect(@wasi.fd_pwrite(ctx, mem, fd, 0, count, 0L, 16), content="21")
  }
  inspect(@wasi.fd_renumber_impl(ctx, fd, 1), content="0")
  defer ctx.close_fd(1) |> ignore
  inspect(@wasi.fd_tell(ctx, mem, 1, 24), content="0")
  inspect(mem.read_i64(24), content="4")
}
