///|
test "Preview 1 readlink and symlink preserve portable path semantics" {
  let root = "/tmp/wasmoon-path-portability-\{@wasi.native_clock_gettime_monotonic()}"
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
    let (path, expected) = case
    for i, byte in @utf8.encode(path) {
      mem.write_byte(i, byte)
    }
    inspect(
      @wasi.path_symlink_impl(ctx, mem, 100, 1, 3, 0, path.length()) == expected,
      content="true",
    )
  }
}
