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
test "managed DWARF builder preserves function lookup" {
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

///|
// Observe the C-side weak reference without creating a MoonBit owner.
extern "c" fn active_dwarf_low_pc() -> UInt64 = "wasmoon_dwarf_get_low_pc"

///|
fn retained_dwarf_lookup() -> () -> Bool {
  let builder = @wasmoon_jit.DWARFBuilder::DWARFBuilder()
  builder.add_function("retained", 8192L, 16, 3)
  builder.register()
  fn() { builder.lookup_address(8193L) is Some(_) }
}

///|
fn exercise_retained_dwarf() -> Unit raise {
  let lookup = retained_dwarf_lookup()
  // The creating function has returned; only the closure owns the builder.
  assert_eq(active_dwarf_low_pc(), 8192UL)
  assert_true(lookup())
}

///|
test "DWARF finalizer runs after the last closure owner is released" {
  exercise_retained_dwarf()
  // No explicit destroy or forced collection is involved.
  assert_eq(active_dwarf_low_pc(), 0UL)
}

///|
test "DWARF close invalidates aliases without clearing another active builder" {
  let first = @wasmoon_jit.DWARFBuilder::DWARFBuilder()
  let retained = first
  first.add_function("first", 4096L, 16, 1)
  first.register()
  first.register()
  first.unregister()
  first.unregister()
  first.register()
  assert_eq(active_dwarf_low_pc(), 4096UL)
  let second = @wasmoon_jit.DWARFBuilder::DWARFBuilder()
  second.add_function("second", 8192L, 16, 2)
  second.register()
  first.destroy()
  retained.destroy()
  retained.add_function("closed", 8192L, 16, 9)
  retained.register()
  retained.unregister()
  assert_true(retained.lookup_address(4097L) is None)
  assert_true(retained.lookup_address(8193L) is None)
  assert_eq(active_dwarf_low_pc(), 8192UL)
  assert_true(second.lookup_address(8193L) is Some(_))
  second.destroy()
  second.destroy()
  assert_eq(active_dwarf_low_pc(), 0UL)
  assert_true(second.lookup_address(8193L) is None)
}
