///|
test "funcref registration release preserves duplicate active owner" {
  let store = @runtime.Store::Store()
  defer store.close()
  let first = register_funcref_entries(store, [
    StoreFuncrefEntry(store_addr=0, func_ptr=100L),
  ])
  let second = register_funcref_entries(store, [
    StoreFuncrefEntry(store_addr=0, func_ptr=100L),
  ])
  first.release()
  debug_inspect(registered_funcref_ptr(store, 0), content="Some(100)")
  second.release()
  debug_inspect(registered_funcref_ptr(store, 0), content="None")
}

///|
test "funcref registration release restores previous owner" {
  let store = @runtime.Store::Store()
  defer store.close()
  let previous = register_funcref_entries(store, [
    StoreFuncrefEntry(store_addr=0, func_ptr=100L),
  ])
  let replacement = register_funcref_entries(store, [
    StoreFuncrefEntry(store_addr=0, func_ptr=200L),
  ])
  replacement.release()
  debug_inspect(registered_funcref_ptr(store, 0), content="Some(100)")
  previous.release()
}

///|
fn register_funcref_entries(
  store : @runtime.Store,
  entries : Array[@runtime.StoreFuncrefEntry],
) -> FuncrefRegistration {
  { lease: store.register_jit_funcrefs(entries), }
}

///|
test "shared table values remain Store-local when function registrations change" {
  let store = @runtime.Store::Store()
  defer store.close()
  let address = store.alloc_host_func(fn(_) { [] })
  let table = @runtime.Table::Table(
    FuncRef,
    1,
    Some(1),
    init_value=FuncRef(address),
  )
  let index = store.alloc_table(table)
  let native = store.get_jit_table(index).unwrap()
  let word = native.get_entry_value(0)
  let revision = native.raw_ptr().revision()
  let first = store.register_jit_funcrefs([
    StoreFuncrefEntry(store_addr=address, func_ptr=100L),
  ])
  defer first.release()
  let second = store.register_jit_funcrefs([
    StoreFuncrefEntry(store_addr=address, func_ptr=200L),
  ])
  second.release()
  assert_eq(native.get_entry_value(0), word)
  assert_eq(native.raw_ptr().revision(), revision)
  assert_eq(table.get(0), FuncRef(address))
}

///|
test "empty and failed runtime mutations preserve the shared descriptor" {
  let store = @runtime.Store::Store()
  defer store.close()
  let table = @runtime.Table::Table(FuncRef, 1, Some(1))
  let index = store.alloc_table(table)
  let native = store.get_jit_table(index).unwrap()
  let revision = native.raw_ptr().revision()
  table.fill(1, Null, 0)
  table.copy_from(1, table, 1, 0)
  assert_eq(table.grow(0, Null), 1)
  assert_eq(table.grow(1, Null), -1)
  try table.set(1, Null) catch {
    OutOfBoundsTableAccess => ()
    error => fail(error.to_string())
  } noraise {
    _ => fail("invalid set succeeded")
  }
  assert_eq(native.raw_ptr().revision(), revision)
}
