///|
test "canonical memory keeps compound variant stride separate from flat ABI" {
  let store = @runtime.Store::Store()
  let mem_addr = store.alloc_mem(Memory(1, None))
  let mem = store.get_mem(mem_addr) catch { _ => return fail("missing memory") }
  let types : Array[TypeDef?] = [
    Some(Tuple([Prim(U32), Prim(U32)])),
    Some(
      Variant([
        { label: "none", ty: None, refines: None, },
        { label: "pair", ty: Some(TypeIdx(0)), refines: None, },
      ]),
    ),
  ]
  let layout = canonical_memory_layout(TypeIdx(1), types, false) catch {
    e => return fail("layout failed: \{e}")
  }
  store_flat_component_value_to_memory(
    mem,
    64,
    TypeIdx(1),
    [I32(1), I32(10), I32(20)],
    types,
    false,
  ) catch {
    e => return fail("first store failed: \{e}")
  }
  store_flat_component_value_to_memory(
    mem,
    76,
    TypeIdx(1),
    [I32(1), I32(30), I32(40)],
    types,
    false,
  ) catch {
    e => return fail("second store failed: \{e}")
  }
  debug_inspect(
    (
      layout,
      load_flat_component_value_from_memory(mem, 64, TypeIdx(1), types, false),
      load_flat_component_value_from_memory(mem, 76, TypeIdx(1), types, false),
    ),
    content="((12, 4), [I32(1), I32(10), I32(20)], [I32(1), I32(30), I32(40)])",
  )
}
