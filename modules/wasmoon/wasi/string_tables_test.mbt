///|
test "P1 argument and environment tables use UTF-8 byte sizes and offsets" {
  let context = @wasi.WasiContextBuilder::WasiContextBuilder()
    .args(["猫😀", "é"])
    .env("名", "😀")
    .build()
  let memory = @runtime.Memory::Memory(1, None)
  inspect(@wasi.args_sizes_get(context, memory, 0, 4), content="0")
  inspect(memory.read_i32(0), content="2")
  inspect(memory.read_i32(4), content="11")
  inspect(@wasi.args_get(context, memory, 16, 100), content="0")
  inspect(memory.read_i32(16), content="100")
  inspect(memory.read_i32(20), content="108")
  assert_eq(
    memory.read_bytes(100, 11),
    b"\xe7\x8c\xab\xf0\x9f\x98\x80\x00\xc3\xa9\x00",
  )
  inspect(@wasi.environ_sizes_get(context, memory, 0, 4), content="0")
  inspect(memory.read_i32(4), content="9")
  inspect(@wasi.environ_get(context, memory, 16, 100), content="0")
  assert_eq(memory.read_bytes(100, 9), b"\xe5\x90\x8d=\xf0\x9f\x98\x80\x00")
  memory.write_i32(16, 123)
  inspect(@wasi.args_get(context, memory, 16, 65530), content="21")
  inspect(memory.read_i32(16), content="123")
}

///|
test "P1 preopen directory names preserve UTF-8 without a terminator" {
  let root = @test_fs.temp_dir()
  let context = @wasi.WasiContextBuilder::WasiContextBuilder()
    .preopen_dir(root, "猫😀")
    .build()
  defer context.close_fd(3) |> ignore
  let memory = @runtime.Memory::Memory(1, None)
  inspect(@wasi.fd_prestat_get(context, memory, 3, 0), content="0")
  inspect(memory.read_i32(4), content="7")
  inspect(@wasi.fd_prestat_dir_name(context, memory, 3, 32, 6), content="37")
  memory.write_byte(39, b'X')
  inspect(@wasi.fd_prestat_dir_name(context, memory, 3, 32, 7), content="0")
  assert_eq(memory.read_bytes(32, 8), b"\xe7\x8c\xab\xf0\x9f\x98\x80X")
}
