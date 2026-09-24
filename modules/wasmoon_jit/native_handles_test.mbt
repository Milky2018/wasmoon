///|
test "managed memory handles preserve identity and pointer-array ABI" {
  let first = @wasmoon_jit.alloc_memory_desc(65536L, Some(2L))
  guard !first.is_null() else { fail("first memory allocation failed") }
  let second = @wasmoon_jit.alloc_memory_desc(131072L, Some(2L))
  guard !second.is_null() else { fail("second memory allocation failed") }
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
  assert_eq(read_context_memory(context, 0, 3), b"one")
  assert_eq(read_context_memory(context, 1, 3), b"two")
  assert_eq(@wasmoon_jit.memory_descriptor_copy(second, 0L, first, 0L, 3L), 0)
  assert_eq(read_context_memory(context, 1, 3), b"one")
  context.set_memory_pointers([
    MemoryInfo(second, 131072L, Some(2)),
    MemoryInfo(first, 65536L, Some(2)),
  ])
  inspect(context.memory_size(0), content="131072")
  inspect(context.memory_size(1), content="65536")
  // Replacing bindings releases the context references.
  context.set_memory_pointers([
    MemoryInfo(@wasmoon_jit.MemoryDescriptor::null(), 0L, None),
    MemoryInfo(@wasmoon_jit.MemoryDescriptor::null(), 0L, None),
  ])
}

///|
test "managed table handles preserve pointer-array ABI and close aliases" {
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

///|
extern "c" fn memory_live_count() -> Int64 = "wasmoon_memory_descriptor_live_count"

///|
extern "c" fn heap_live_count() -> Int64 = "wasmoon_gc_heap_live_count"

///|
extern "c" fn table_live_count() -> Int64 = "wasmoon_jit_debug_shared_indirect_table_live_count"

///|
fn context_retaining_memory() -> @wasmoon_jit.NativeJITContext raise {
  let memory = @wasmoon_jit.alloc_memory_desc(65536L, Some(1L))
  guard !memory.is_null() else { fail("memory allocation failed") }
  assert_eq(
    @wasmoon_jit.memory_descriptor_write_bytes(memory, 0L, b"live", 4),
    0,
  )
  guard @wasmoon_jit.NativeJITContext::try_alloc(0) is Some(context) else {
    fail("context allocation failed")
  }
  context.set_memory_pointers([MemoryInfo(memory, 65536L, Some(1))])
  context
}

///|
fn exercise_context_memory(baseline : Int64) -> Unit raise {
  let context = context_retaining_memory()
  assert_eq(memory_live_count(), baseline + 1L)
  assert_eq(read_context_memory(context, 0, 4), b"live")
}

///|
test "context retains memory until its own finalizer runs" {
  let baseline = memory_live_count()
  exercise_context_memory(baseline)
  assert_eq(memory_live_count(), baseline)
}

///|
fn waiter_retaining_memory() -> @wasmoon_jit.NativeAtomicWait raise {
  let memory = @wasmoon_jit.alloc_memory_desc(65536L, Some(1L), is_shared=true)
  guard @wasmoon_jit.atomic_wait_begin(memory, 0L, 4, 0L, -1L) is Some(waiter) else {
    fail("wait allocation failed")
  }
  waiter
}

///|
test "wait registration retains memory after the allocating scope returns" {
  let baseline = memory_live_count()
  let waiter = waiter_retaining_memory()
  assert_eq(memory_live_count(), baseline + 1L)
  assert_eq(waiter.poll(), -1)
  waiter.cancel()
  waiter.cancel()
  assert_eq(memory_live_count(), baseline)
}

///|
fn context_retaining_closed_heap() -> @wasmoon_jit.NativeJITContext raise {
  let heap = @wasmoon_jit.CHeap()
  let saved_handle = heap.get_ptr()
  guard @wasmoon_jit.NativeJITContext::try_alloc(0) is Some(context) else {
    fail("context allocation failed")
  }
  heap.free()
  heap.free()
  assert_true(heap.get_ptr().is_null())
  assert_false(saved_handle.is_null())
  context.set_gc_heap_ptr(saved_handle)
  context
}

///|
test "GC heap handle and context survive logical owner close" {
  let baseline = heap_live_count()
  let context = context_retaining_closed_heap()
  assert_eq(heap_live_count(), baseline + 1L)
  assert_eq(context.gc_collect_for_alloc([]), 0)
  context.clear_gc_heap()
  assert_eq(heap_live_count(), baseline)
}

///|
fn populate_exception_heap(
  state : @wasmoon_jit.NativeExecutionState,
) -> Int64 raise {
  let heap = @wasmoon_jit.CHeap()
  let reference = heap.alloc_struct(0, [I32(42)])
  let arena = state.exceptions()
  assert_true(arena.define_tag(7, [RefNullStruct(0)]))
  let exception = arena.insert(heap.get_ptr(), 7, [
    @wasmoon_jit.encode_heap_ref(reference),
  ])
  assert_true(exception != 0L)
  heap.free()
  exception
}

///|
test "exception root registration retains heap until arena clear" {
  let baseline = heap_live_count()
  let state = @wasmoon_jit.NativeExecutionState()
  let reference = populate_exception_heap(state)
  assert_eq(heap_live_count(), baseline + 1L)
  assert_true(state.exceptions().snapshot(reference) is Some(_))
  state.seal()
  assert_eq(heap_live_count(), baseline)
}

///|
fn table_from_expired_owner() -> @wasmoon_jit.JITTable raise {
  guard @wasmoon_jit.JITTableOwner::try_alloc(1, None) is Some(owner) else {
    fail("table allocation failed")
  }
  owner.table().set(0, 123L, 4)
  owner.table()
}

///|
fn exercise_retained_table(baseline : Int64) -> Unit raise {
  let table = table_from_expired_owner()
  assert_eq(table_live_count(), baseline + 1L)
  assert_eq(table.get_entry_value(0), 123L)
  assert_eq(table.get_entry_type(0), 4)
}

///|
test "table view retains allocation without an explicit owner close" {
  let baseline = table_live_count()
  exercise_retained_table(baseline)
  assert_eq(table_live_count(), baseline)
}

///|
fn exercise_context_table(baseline : Int64) -> Unit raise {
  guard @wasmoon_jit.JITTableOwner::try_alloc(1, None) is Some(owner) else {
    fail("table allocation failed")
  }
  guard @wasmoon_jit.NativeJITContext::try_alloc(0) is Some(context) else {
    fail("context allocation failed")
  }
  context.set_table_pointers([Some(owner.table())])
  owner.close()
  assert_eq(table_live_count(), baseline + 1L)
  assert_false(context.refresh_table_layout(0))
  context.set_table_pointers([])
  assert_eq(table_live_count(), baseline)
}

///|
test "context binding retains table after logical owner close" {
  let baseline = table_live_count()
  exercise_context_table(baseline)
  assert_eq(table_live_count(), baseline)
}

///|
test "empty managed handles remain empty after rejected operations" {
  let empty = @wasmoon_jit.MemoryDescriptor::null()
  assert_true(empty == @wasmoon_jit.MemoryDescriptor::null())
  assert_eq(@wasmoon_jit.memory_descriptor_grow64(empty, 1L), -1L)
  assert_eq(@wasmoon_jit.memory_descriptor_grow64(empty, 0L), -1L)
  assert_true(empty.is_null())
  let failed = @wasmoon_jit.alloc_memory_desc(-1L, None)
  assert_true(failed.is_null())
  assert_true(failed == empty)
}

///|
test "clearing context memory bindings releases their last references" {
  let baseline = memory_live_count()
  let context = context_retaining_memory()
  assert_eq(memory_live_count(), baseline + 1L)
  context.set_memory_pointers([])
  assert_eq(context.memory_size(0), 0L)
  assert_eq(memory_live_count(), baseline)
}

///|
fn exercise_automatic_heap() -> Unit raise {
  let heap = @wasmoon_jit.CHeap()
  let value = heap.alloc_struct(0, [I32(1)])
  assert_true(heap.is_valid(value))
}

///|
test "GC heap finalizer releases an unclosed owner" {
  let baseline = heap_live_count()
  exercise_automatic_heap()
  assert_eq(heap_live_count(), baseline)
}

///|
fn read_context_memory(
  context : @wasmoon_jit.NativeJITContext,
  index : Int,
  size : Int,
) -> Bytes raise {
  let output = FixedArray::make(size, b'\x00')
  assert_eq(
    @wasmoon_jit.memory_descriptor_read(
      context.memory_descriptor(index),
      0L,
      output,
      size,
    ),
    0,
  )
  Bytes::from_array(Array::makei(size, i => output[i]))
}

///|
fn descriptor_from_expired_context() -> @wasmoon_jit.MemoryDescriptor raise {
  let context = context_retaining_memory()
  context.memory_descriptor(0)
}

///|
test "descriptor returned by a context survives that context's finalizer" {
  let baseline = memory_live_count()
  fn read_after_context_drop() -> Unit raise {
    let descriptor = descriptor_from_expired_context()
    assert_eq(memory_live_count(), baseline + 1L)
    let output = FixedArray::make(4, b'\x00')
    assert_eq(@wasmoon_jit.memory_descriptor_read(descriptor, 0L, output, 4), 0)
    assert_eq(Bytes::from_array(Array::makei(4, i => output[i])), b"live")
  }
  read_after_context_drop()
  assert_eq(memory_live_count(), baseline)
}
