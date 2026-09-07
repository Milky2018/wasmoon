///|
test "wasi readdir writes UTF-8 byte lengths and truncated names" {
  let root = "/tmp/wasmoon-p1-readdir"
  @wasi.native_unlinkat(0, root + "/Д", 0) |> ignore
  @wasi.native_unlinkat(0, root, @wasi.AT_REMOVEDIR) |> ignore
  assert_true(@wasi.native_mkdir(root, 0o700))
  defer @wasi.native_unlinkat(0, root, @wasi.AT_REMOVEDIR) |> ignore
  assert_true(@wasi.native_symlinkat("missing", 0, root + "/Д"))
  defer @wasi.native_unlinkat(0, root + "/Д", 0) |> ignore
  let ctx = @wasi.WasiContextBuilder::WasiContextBuilder()
    .preopen_dir(root, "/")
    .build()
  let mem = @runtime.Memory::Memory(1, None)
  // Cookie 2 skips the synthetic dot entries. Buffer holds one byte of name.
  inspect(@wasi.fd_readdir(ctx, mem, 3, 0, 25, 2L, 100), content="0")
  inspect(mem.read_i32(100), content="25")
  inspect(mem.read_i32(16), content="2")
  inspect(mem.read_byte(24).to_int(), content="208")
  inspect(@wasi.fd_readdir(ctx, mem, 3, 0, 26, 2L, 100), content="0")
  inspect(mem.read_i32(100), content="26")
  inspect(mem.read_byte(25).to_int(), content="148")
}
