///|
test "canonical payload budget is shared across nested list elements" {
  let store = @runtime.Store::Store()
  defer store.close()
  let memory = store.get_mem(store.alloc_mem(Memory(1, None)))
  memory.store_i32(0, 64)
  memory.store_i32(4, 4)
  memory.store_i32(8, 64)
  memory.store_i32(12, 4)
  let types : Array[TypeDef?] = [Some(List(Prim(U8))), Some(List(TypeIdx(0)))]
  let error = try {
    lift_component_value_from_flat(
      TypeIdx(1),
      [I32(0), I32(2)],
      types,
      Some(memory),
      false,
      Utf8,
      ResourceTable(),
      budget=CanonicalCopyBudget::new(limit=256L),
    )
    |> ignore
    "missing error"
  } catch {
    error => error.to_string()
  }
  inspect(
    error.contains("fuel allocated for hostcalls has been exhausted"),
    content="true",
  )
  let budget = CanonicalCopyBudget::new(limit=320L)
  let value = lift_component_value_from_flat(
    TypeIdx(1),
    [I32(0), I32(2)],
    types,
    Some(memory),
    false,
    Utf8,
    ResourceTable(),
    budget~,
  )
  inspect(budget.remaining.val, content="0")
  guard value is List(items) else { fail("expected list") }
  inspect(items.length(), content="2")
}

///|
test "canonical budget cannot replace a guest memory bounds error" {
  let store = @runtime.Store::Store()
  defer store.close()
  let memory = store.get_mem(store.alloc_mem(Memory(1, None)))
  let error = try {
    lift_component_value_from_flat(
      TypeIdx(0),
      [I32(65536), I32(2)],
      [Some(List(Prim(U32)))],
      Some(memory),
      false,
      Utf8,
      ResourceTable(),
      budget=CanonicalCopyBudget::new(limit=0L),
    )
    |> ignore
    "missing error"
  } catch {
    error => error.to_string()
  }
  inspect(error.contains("out of bounds"), content="true")
}
