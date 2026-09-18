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
