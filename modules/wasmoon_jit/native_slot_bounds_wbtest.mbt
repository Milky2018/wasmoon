///|
test "native value and table slots retain byte offsets above signed i32" {
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
  let table : JITTable = { table_ptr: base, size: 0x08000001, max: None, }
  inspect(table.get_entry_value(0), content="11")
  inspect(table.get_entry_type(0), content="22")
  inspect(table.get_entry_value(0x08000000), content="33")
  inspect(table.get_entry_type(0x08000000), content="44")
}
