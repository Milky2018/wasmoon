///|
test "Preview 1 readlink and symlink preserve portable path semantics" {
  let root = @test_fs.temp_dir() +
    "/wasmoon-path-portability-\{@wasi.native_clock_gettime_monotonic()}"
  guard @wasi.native_mkdir(root, 0o700) else {
    fail("could not create path portability fixture")
  }
  defer @wasi.native_unlinkat(0, root, @wasi.AT_REMOVEDIR) |> ignore
  guard @wasi.native_open(root + "/file", [WriteOnly, Create], 0o600)
    is Some(fd) else {
    fail("could not create regular file")
  }
  @wasi.native_close(fd) |> ignore
  defer @wasi.native_unlinkat(0, root + "/file", 0) |> ignore
  guard @wasi.native_mkdir(root + "/directory", 0o700) else {
    fail("could not create subdirectory")
  }
  defer @wasi.native_unlinkat(0, root + "/directory", @wasi.AT_REMOVEDIR)
    |> ignore
  guard @wasi.native_symlinkat("file", 0, root + "/link") else {
    fail("could not create symbolic link")
  }
  defer @wasi.native_unlinkat(0, root + "/link", 0) |> ignore
  let ctx = @wasi.WasiContextBuilder::WasiContextBuilder()
    .preopen_dir(root, "/")
    .build()
  defer ctx.close_fd(3) |> ignore
  let store = @runtime.Store::Store()
  defer store.close()
  let mem = @runtime.Memory::Memory(1, None)
  store.alloc_mem(mem) |> ignore
  for case in [("link", 0), ("file", 28), ("missing", 44)] {
    let (path, expected) = case
    for i, byte in @utf8.encode(path) {
      mem.write_byte(i, byte)
    }
    mem.write_byte(100, b'!')
    mem.write_i32(200, -1)
    inspect(
      @wasi.path_readlink_impl(ctx, mem, 3, 0, path.length(), 100, 0, 200) ==
      expected,
      content="true",
    )
    inspect(mem.read_byte(100) == b'!', content="true")
    inspect(
      mem.read_i32(200) == (if expected == 0 { 0 } else { -1 }),
      content="true",
    )
  }
  mem.write_byte(100, b'x')
  for
    case in [
      ("missing/", 44),
      ("directory/", 20),
      ("directory", 20),
      ("file/", 54),
      ("file", 20),
    ] {
    let (path, portable_expected) = case
    // The upstream Windows profile reports the missing symlink target first.
    let expected = if @host_io.is_windows() { 44 } else { portable_expected }
    for i, byte in @utf8.encode(path) {
      mem.write_byte(i, byte)
    }
    inspect(
      @wasi.path_symlink_impl(ctx, mem, 100, 1, 3, 0, path.length()) == expected,
      content="true",
    )
  }
}

///|
test "Preview 1 path operations retain a renamed preopen capability" {
  let root = @test_fs.temp_dir() +
    "/wasmoon-p1-capability-\{@wasi.native_clock_gettime_monotonic()}"
  inspect(@wasi.native_mkdir(root, 0o700), content="true")
  let moved = root + "-moved"
  defer @wasi.native_unlinkat(0, moved, @wasi.AT_REMOVEDIR) |> ignore
  defer @wasi.native_unlinkat(0, root, @wasi.AT_REMOVEDIR) |> ignore
  let ctx = @wasi.WasiContextBuilder::WasiContextBuilder()
    .preopen_dir(root, "/")
    .build()
  defer ctx.close_fd(3) |> ignore
  inspect(@wasi.native_renameat(0, root, 0, moved), content="true")
  inspect(@wasi.native_mkdir(root, 0o700), content="true")
  let store = @runtime.Store::Store()
  defer store.close()
  let mem = @runtime.Memory::Memory(1, None)
  store.alloc_mem(mem) |> ignore
  for i, byte in b"child" {
    mem.write_byte(i, byte)
  }
  inspect(@wasi.path_create_directory(ctx, mem, 3, 0, 5), content="0")
  defer @wasi.native_unlinkat(0, moved + "/child", @wasi.AT_REMOVEDIR) |> ignore
  inspect(
    @wasi.native_fstatat(0, moved + "/child", 0) is Some(_),
    content="true",
  )
  inspect(@wasi.native_fstatat(0, root + "/child", 0) is None, content="true")
  inspect(@wasi.path_open(ctx, mem, 3, 0, 0, 5, 2, 0L, 0L, 0, 100), content="0")
  ctx.close_fd(mem.read_i32(100)) |> ignore
  inspect(@wasi.path_filestat_get_impl(ctx, mem, 3, 0, 0, 5, 200), content="0")
  inspect(mem.read_byte(216).to_int(), content="3")
  inspect(
    @wasi.path_filestat_set_times_impl(ctx, mem, 3, 1, 0, 5, 0L, 0L, 10),
    content="0",
  )
  for i, byte in b"other" {
    mem.write_byte(20 + i, byte)
  }
  inspect(@wasi.path_rename_impl(ctx, mem, 3, 0, 5, 3, 20, 5), content="0")
  defer @wasi.native_unlinkat(0, moved + "/other", @wasi.AT_REMOVEDIR) |> ignore
  inspect(
    @wasi.native_fstatat(0, moved + "/other", 0) is Some(_),
    content="true",
  )
  inspect(@wasi.path_remove_directory_impl(ctx, mem, 3, 20, 5), content="0")
}

///|
test "Preview 1 symlink metadata follows targets within its directory capability" {
  let root = @test_fs.temp_dir() +
    "/wasmoon-p1-links-\{@wasi.native_clock_gettime_monotonic()}"
  inspect(@wasi.native_mkdir(root, 0o700), content="true")
  defer @wasi.native_unlinkat(0, root, @wasi.AT_REMOVEDIR) |> ignore
  inspect(@wasi.native_mkdir(root + "/dir", 0o700), content="true")
  defer @wasi.native_unlinkat(0, root + "/dir", @wasi.AT_REMOVEDIR) |> ignore
  inspect(@wasi.native_symlinkat("dir", 0, root + "/link"), content="true")
  defer @wasi.native_unlinkat(0, root + "/link", 0) |> ignore
  inspect(@wasi.native_symlinkat("..", 0, root + "/escape"), content="true")
  defer @wasi.native_unlinkat(0, root + "/escape", 0) |> ignore
  let ctx = @wasi.WasiContextBuilder::WasiContextBuilder()
    .preopen_dir(root, "/")
    .build()
  defer ctx.close_fd(3) |> ignore
  let store = @runtime.Store::Store()
  defer store.close()
  let mem = @runtime.Memory::Memory(1, None)
  store.alloc_mem(mem) |> ignore
  for
    case in [
      ("link", 0, 0, 7),
      ("link", 1, 0, 3),
      ("link/", 0, 0, 3),
      ("escape", 0, 0, 7),
      ("escape", 1, 63, 0),
      ("escape/", 0, 63, 0),
      ("link/../dir", 1, 0, 3),
      ("dir/../../", 1, 63, 0),
    ] {
    let (path, flags, expected, kind) = case
    for i, byte in @utf8.encode(path) {
      mem.write_byte(i, byte)
    }
    let result = @wasi.path_filestat_get_impl(
      ctx,
      mem,
      3,
      flags,
      0,
      path.length(),
      200,
    )
    inspect(result == expected, content="true")
    if result == 0 {
      inspect(mem.read_byte(216).to_int() == kind, content="true")
    }
    inspect(
      @wasi.path_filestat_set_times_impl(
        ctx,
        mem,
        3,
        flags,
        0,
        path.length(),
        0L,
        0L,
        10,
      ) ==
      expected,
      content="true",
    )
  }
}
