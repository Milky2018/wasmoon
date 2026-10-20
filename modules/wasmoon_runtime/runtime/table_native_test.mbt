///|
test "host and native table writes are immediately visible without a JIT boundary" {
  let store = @runtime.Store::Store()
  defer store.close()
  let table = @runtime.Table::Table(RefNullEq, 1, Some(4), init_value=I31(1))
  let address = store.alloc_table(table)
  let native = store.get_jit_table(address).unwrap()
  table.set(0, I31(7))
  assert_eq(native.get_entry_value(0), 15L)
  native.set(0, 19L, -1)
  assert_eq(table.get(0), I31(9))
  assert_eq(store.alloc_table(table), address)
  table.fill(0, I31(11), 1)
  assert_eq(native.get_entry_value(0), 23L)
}

///|
test "native growth is authoritative for runtime size limits copy and quota" {
  let budget = @runtime.ResourceBudget::new(table_elements=4L)
  let store = @runtime.Store::Store(resource_budget=Some(budget))
  defer store.close()
  let table = @runtime.Table::Table(RefNullEq, 1, Some(4), init_value=I31(1))
  let native = store.get_jit_table(store.alloc_table(table)).unwrap()
  assert_eq(native.raw_ptr().grow_value(2L, 19L, -1), 1L)
  assert_eq(table.size(), 3)
  assert_eq(table.get_limits64(), (3L, Some(4L)))
  assert_eq(table.get(2), I31(9))
  table.copy_from(0, table, 2, 1)
  assert_eq(table.get(0), I31(9))
  assert_eq(table.grow(1, I31(11)), 3)
  assert_eq(native.get_entry_value(3), 23L)
  assert_eq(budget.used(TableElements), 4L)
  assert_eq(table.grow(1, Null), -1)
  table.close()
  assert_eq(native.get_size(), 0)
  assert_eq(native.raw_ptr().grow_value(1L, 0L, -1), -1L)
  store.close()
  assert_eq(budget.used(TableElements), 0L)
}

///|
test "native external tables preserve wrapper identity and root it across collection" {
  let store = @runtime.Store::with_c_heap()
  defer store.close()
  let wrapped = store.wrap_as_extern(I31(7))
  let table = @runtime.Table::Table(ExternRef, 1, None, init_value=wrapped)
  let native = store.get_jit_table(store.alloc_table(table)).unwrap()
  assert_eq(table.get(0), wrapped)
  assert_eq(table.get(0), wrapped)
  store.collect_garbage() |> ignore
  assert_eq(table.get(0), wrapped)
  assert_eq(store.unwrap_extern(table.get(0)), I31(7))
  // A guest write supplies an unwrapped native word. Materialize its host
  // wrapper once, then retain that identity through the authoritative entry.
  native.set(0, 19L, -1)
  let replacement = table.get(0)
  assert_eq(store.unwrap_extern(replacement), I31(9))
  assert_eq(table.get(0), replacement)
  store.collect_garbage() |> ignore
  assert_eq(table.get(0), replacement)
}

///|
extern "c" fn shared_table_live_count() -> Int64 = "wasmoon_jit_debug_shared_indirect_table_live_count"

///|
fn allocate_unretained_table_store() -> Unit raise {
  let store = @runtime.Store::Store()
  store.alloc_table(Table(FuncRef, 1, None)) |> ignore
}

///|
test "native table backing does not retain an otherwise unreferenced Store" {
  let before = shared_table_live_count()
  allocate_unretained_table_store()
  assert_eq(shared_table_live_count(), before)
}
