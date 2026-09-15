///|
test "component script releases only unreachable instance Stores" {
  let runtime = ComponentScriptRuntime::new(false)
  defer runtime.close()
  let component = load_component("testsuite/fixtures/minimal.component.wasm")
  let first = runtime.instantiate("first", component).unwrap()
  let first_memory = @runtime.Memory::Memory(1, None)
  first.store.alloc_mem(first_memory) |> ignore
  runtime.instances.set("$instance", first)
  runtime.instances.set("$alias", first)
  let second = runtime.instantiate("second", component).unwrap()
  let second_memory = @runtime.Memory::Memory(1, None)
  second.store.alloc_mem(second_memory) |> ignore
  runtime.instances.set("$instance", second)
  runtime.release_unreferenced(Some(second))
  inspect(first_memory.byte_len(), content="65536")
  runtime.instances.remove("$alias")
  runtime.release_unreferenced(Some(first))
  inspect(first_memory.byte_len(), content="65536")
  runtime.release_unreferenced(Some(second))
  inspect(first_memory.byte_len(), content="0")
  second_memory.store_i32(0, 42)
  inspect(second_memory.load_i32(0), content="42")
}
