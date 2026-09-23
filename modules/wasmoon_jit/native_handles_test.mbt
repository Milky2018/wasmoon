///|
test "external memory handles preserve identity and pointer-array ABI" {
  let first = @wasmoon_jit.alloc_memory_desc(65536L, Some(2L))
  guard !first.is_null() else { fail("first memory allocation failed") }
  defer @wasmoon_jit.free_memory_desc(first)
  let second = @wasmoon_jit.alloc_memory_desc(131072L, Some(2L))
  guard !second.is_null() else { fail("second memory allocation failed") }
  defer @wasmoon_jit.free_memory_desc(second)
  assert_true(first == first)
  assert_true(first != second)
  assert_true(first != @wasmoon_jit.MemoryDescriptor::null())
  assert_eq(@wasmoon_jit.memory_descriptor_write_bytes(first, 0L, b"one", 3), 0)
  assert_eq(
    @wasmoon_jit.memory_descriptor_write_bytes(second, 0L, b"two", 3),
    0,
  )
  guard @wasmoon_jit.NativeJITContext::try_alloc(0) is Some(context) else {
    fail("context allocation failed")
  }
  context.set_memory_pointers([
    MemoryInfo(first, 65536L, Some(2)),
    MemoryInfo(second, 131072L, Some(2)),
  ])
  inspect(context.memory_size(0), content="65536")
  inspect(context.memory_size(1), content="131072")
  assert_eq(@wasmoon_jit.memory_read(context.memory_ptr(0), 0L, 3), b"one")
  assert_eq(@wasmoon_jit.memory_read(context.memory_ptr(1), 0L, 3), b"two")
  assert_eq(@wasmoon_jit.memory_descriptor_copy(second, 0L, first, 0L, 3L), 0)
  assert_eq(@wasmoon_jit.memory_read(context.memory_ptr(1), 0L, 3), b"one")
  context.set_memory_pointers([
    MemoryInfo(second, 131072L, Some(2)),
    MemoryInfo(first, 65536L, Some(2)),
  ])
  inspect(context.memory_size(0), content="131072")
  inspect(context.memory_size(1), content="65536")
  // Remove borrowed descriptors before the explicit owners are released.
  context.set_memory_pointers([
    MemoryInfo(@wasmoon_jit.MemoryDescriptor::null(), 0L, None),
    MemoryInfo(@wasmoon_jit.MemoryDescriptor::null(), 0L, None),
  ])
}

///|
test "external table handles preserve pointer-array ABI and close aliases" {
  guard @wasmoon_jit.JITTableOwner::try_alloc(1, None) is Some(first) else {
    fail("first table allocation failed")
  }
  defer first.close()
  guard @wasmoon_jit.JITTableOwner::try_alloc(1, None) is Some(second) else {
    fail("second table allocation failed")
  }
  defer second.close()
  first.table().set(0, 111L, 7)
  second.table().set(0, 222L, 8)
  guard @wasmoon_jit.NativeJITContext::try_alloc(0) is Some(context) else {
    fail("context allocation failed")
  }
  context.set_table_pointers([Some(first.table()), Some(second.table())])
  assert_true(context.refresh_table_layout(0))
  assert_true(context.refresh_table_layout(1))
  assert_eq(first.table().get_entry_value(0), 111L)
  assert_eq(second.table().get_entry_value(0), 222L)
  assert_eq(first.table().get_entry_type(0), 7)
  assert_eq(second.table().get_entry_type(0), 8)
  context.set_table_pointers([None, None])
  let retained_table = first.table()
  first.close()
  first.close()
  assert_eq(retained_table.get_size(), 0)
  assert_eq(retained_table.get_entry_value(0), 0L)
}

///|
test "external DWARF handle preserves function lookup" {
  let dwarf = @wasmoon_jit.DWARFBuilder::DWARFBuilder()
  defer dwarf.destroy()
  dwarf.add_function("typed_handle", 4096L, 32, 7)
  guard dwarf.lookup_address(4101L) is Some(info) else {
    fail("function not found")
  }
  inspect(info.name, content="typed_handle")
  inspect(info.func_idx, content="7")
  inspect(info.offset, content="5")
  assert_true(dwarf.lookup_address(4128L) is None)
}
