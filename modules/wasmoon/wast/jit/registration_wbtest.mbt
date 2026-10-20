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
test "table encoding invalidates when native function registration changes" {
  let store = @runtime.Store::Store()
  defer store.close()
  let address = store.alloc_host_func(fn(_) { [] })
  let table = @runtime.Table::Table(
    FuncRef,
    1,
    Some(1),
    init_value=FuncRef(address),
  )
  let owner = @wasmoon_jit.JITTableOwner::try_alloc(1, Some(1L)).unwrap()
  defer owner.close()
  let native = owner.table()
  let module_ = @compiled_jit.JITModule::JITModule()
  defer module_.close()
  let instance = @runtime.ModuleInstance::ModuleInstance()
  let first = store.register_jit_funcrefs([
    StoreFuncrefEntry(store_addr=address, func_ptr=100L),
  ])
  defer first.release()
  sync_table_to_jit(table, native, module_, instance, store)
  assert_eq(native.get_entry_value(0), @wasmoon_jit.tag_funcref_ptr(100L))
  let revision = native.raw_ptr().revision()
  sync_table_to_jit(table, native, module_, instance, store)
  assert_eq(native.raw_ptr().revision(), revision)
  let second = store.register_jit_funcrefs([
    StoreFuncrefEntry(store_addr=address, func_ptr=200L),
  ])
  defer second.release()
  sync_table_to_jit(table, native, module_, instance, store)
  assert_eq(native.get_entry_value(0), @wasmoon_jit.tag_funcref_ptr(200L))
  second.release()
  sync_table_to_jit(table, native, module_, instance, store)
  assert_eq(native.get_entry_value(0), @wasmoon_jit.tag_funcref_ptr(100L))
}

///|
test "empty and failed runtime table mutations do not invalidate synchronized entries" {
  let store = @runtime.Store::Store()
  defer store.close()
  let table = @runtime.Table::Table(FuncRef, 1, Some(1))
  let owner = @wasmoon_jit.JITTableOwner::try_alloc(1, Some(1L)).unwrap()
  defer owner.close()
  let native = owner.table()
  let module_ = @compiled_jit.JITModule::JITModule()
  defer module_.close()
  let instance = @runtime.ModuleInstance::ModuleInstance()
  sync_table_to_jit(table, native, module_, instance, store)
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
  sync_table_to_jit(table, native, module_, instance, store)
  assert_eq(native.raw_ptr().revision(), revision)
  // Distinct module encodings must not share a checkpoint even with equal epochs.
  let other = @compiled_jit.JITModule::JITModule()
  defer other.close()
  sync_table_to_jit(table, native, other, instance, store)
  assert_true(native.raw_ptr().revision() != revision)
}
