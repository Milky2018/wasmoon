///|
test "native value slots retain byte offsets above signed i32" {
  // Only the first and last two slots are touched in this virtual allocation.
  let base = alloc_memory(2147483664L)
  guard base != 0L else { fail("could not allocate native slot fixture") }
  defer free_memory(base)
  native_value_slot_write(base, 0, 11L)
  native_value_slot_write(base, 1, 22L)
  native_value_slot_write(base, 0x10000000, 33L)
  native_value_slot_write(base, 0x10000001, 44L)
  inspect(native_value_slot_read(base, 0), content="11")
  inspect(native_value_slot_read(base, 0x10000000), content="33")
}

///|
test "native table slots retain byte offsets above signed i32" {
  let pointer = @native_test_support.sparse_table(0x08000001)
  guard pointer.size() == 0x08000001 else {
    fail("could not allocate native table fixture")
  }
  let table : JITTable = { table_ptr: pointer, max: None, }
  table.set(0, 11L, 22)
  table.set(0x08000000, 33L, 44)
  inspect(table.get_entry_value(0), content="11")
  inspect(table.get_entry_type(0), content="22")
  inspect(table.get_entry_value(0x08000000), content="33")
  inspect(table.get_entry_type(0x08000000), content="44")
}

///|
#borrow(context)
extern "c" fn grow_context_table(
  context : JITContext,
  index : Int,
  delta : Int64,
) -> Int64 = "wasmoon_test_table_grow"

///|
test "growing a shared table publishes its layout to every context and alias" {
  guard JITTableOwner::try_alloc(1, None) is Some(owner) else {
    fail("table allocation failed")
  }
  guard NativeJITContext::try_alloc(0) is Some(first) else {
    fail("context allocation failed")
  }
  guard NativeJITContext::try_alloc(0) is Some(second) else {
    fail("context allocation failed")
  }
  let table = owner.table()
  first.set_table_pointers([Some(table), Some(table)])
  second.set_table_pointers([Some(table)])
  table.set(0, 111L, 2)
  assert_eq(grow_context_table(first.handle, 0, 2L), 1L)
  assert_eq(table.get_size(), 3)
  assert_eq(context_table_size(first.handle, 1), 3)
  assert_eq(context_table_size(second.handle, 0), 3)
  table.set(2, 222L, 3)
  // The second growth copies the layout published by the first context.
  assert_eq(grow_context_table(second.handle, 0, 1L), 3L)
  assert_eq(table.get_size(), 4)
  assert_eq(table.get_entry_value(0), 111L)
  assert_eq(table.get_entry_value(2), 222L)
  owner.close()
  assert_false(first.refresh_table_layout(0))
  assert_eq(grow_context_table(second.handle, 0, 1L), 4L)
  first.set_table_pointers([None])
  second.set_table_pointers([None])
}
