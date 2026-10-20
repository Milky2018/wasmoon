///|
test "memory constructor capacity denial leaves Store allocation unchanged" {
  let store = @runtime.Store::Store()
  defer store.close()
  let rejected = try {
    let memory = @runtime.Memory::Memory(65537, None)
    store.alloc_mem(memory) |> ignore
    false
  } catch {
    MemoryMinimumExceedsLimits(65537L) => true
    _ => false
  }
  inspect(rejected, content="true")
  inspect(store.alloc_mem(Memory(0, None)), content="0")
}
