///|
test "Store close invalidates retained Memory aliases" {
  let store = @runtime.Store::Store()
  let memory = @runtime.Memory::Memory(1, None)
  store.alloc_mem(memory) |> ignore
  store.close()
  debug_inspect((memory.byte_len(), memory.desc_ptr()), content="(0, 0)")
}

///|
test "Memory aliases shared by Stores are released exactly once" {
  let first = @runtime.Store::Store()
  let second = @runtime.Store::Store()
  let memory = @runtime.Memory::Memory(1, None)
  first.alloc_mem(memory) |> ignore
  second.alloc_mem(memory) |> ignore
  first.close()
  second.close()
  memory.write_i32(0, 42)
  memory.write_byte(0, b'\x2A')
  debug_inspect(
    (memory.byte_len(), memory.desc_ptr(), memory.grow(1), memory.read_i32(0)),
    content="(0, 0, -1, 0)",
  )
  debug_inspect(memory.read_bytes(0, 1), content="<Bytes: []>")
}

///|
test "raising Memory access reports a closed handle" {
  let store = @runtime.Store::Store()
  let memory = @runtime.Memory::Memory(1, None)
  store.alloc_mem(memory) |> ignore
  store.close()
  try memory.load_i32(0) catch {
    error => inspect(error, content="memory is closed")
  } noraise {
    _ => fail("expected closed Memory access to fail")
  }
}
