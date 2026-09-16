///|
test "P1 pointers use the upper half of wasm32 memory" {
  let store = @runtime.Store::Store()
  defer store.close()
  let memory = @runtime.Memory::Memory(32769, Some(32769))
  store.alloc_mem(memory) |> ignore
  let output : Array[Bytes] = []
  let context = @wasi.WasiContextBuilder::WasiContextBuilder()
    .args(["猫😀"])
    .stdout(bytes => output.push(bytes))
    .build()
  let base = 0x80000000
  inspect(@wasi.args_sizes_get(context, memory, base, base + 4), content="0")
  assert_eq(memory.load_i32_at(0x80000000L), 1)
  assert_eq(memory.load_i32_at(0x80000004L), 8)
  inspect(@wasi.args_get(context, memory, base + 16, base + 32), content="0")
  assert_eq(memory.load_i32_at(0x80000010L), base + 32)
  memory.store_i32_at(0x80000014L, 7)
  inspect(
    @wasi.fd_write(context, memory, 1, base + 16, 1, base + 24),
    content="0",
  )
  assert_eq(output[0], b"\xe7\x8c\xab\xf0\x9f\x98\x80")
  memory.store_i64_at(0x80000100L, 123L)
  inspect(
    @wasi.poll_oneoff_impl(
      context,
      memory,
      base + 256,
      base + 320,
      1,
      base + 400,
    ),
    content="0",
  )
  assert_eq(memory.load_i64_at(0x80000140L), 123L)
  assert_eq(memory.load_i32_at(0x80000190L), 1)
}
