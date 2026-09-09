///|
test "Store rejects memory descriptors whose allocation failed" {
  let store = @runtime.Store::Store()
  defer store.close()
  let memory = @runtime.Memory::Memory(65537, None)
  let result = try {
    store.alloc_mem(memory) |> ignore
    "accepted"
  } catch {
    error => error.to_string()
  }
  inspect(result, content="out of memory")
  // A rejected allocation must not occupy a Store address.
  inspect(store.alloc_mem(Memory(0, None)), content="0")
}
