///|
test "module-shaped contexts retain and replace inline memory and table arrays" {
  let layout = @wasmoon_jit.ContextLayout::new(Module(2, 2, 0)).unwrap()
  let memory_baseline = memory_live_count()
  let table_baseline = table_live_count()
  exercise_shaped_contexts(layout)
  assert_eq(memory_live_count(), memory_baseline)
  assert_eq(table_live_count(), table_baseline)
}

///|
fn exercise_shaped_contexts(layout : @wasmoon_jit.ContextLayout) -> Unit raise {
  let first = @wasmoon_jit.alloc_memory_desc(65536L, Some(2L))
  let second = @wasmoon_jit.alloc_memory_desc(131072L, Some(2L))
  let table = @wasmoon_jit.JITTableOwner::try_alloc(1, None).unwrap()
  defer table.close()
  let a = @wasmoon_jit.NativeJITContext::try_alloc(0, layout=Some(layout)).unwrap()
  let b = @wasmoon_jit.NativeJITContext::try_alloc(0, layout=Some(layout)).unwrap()
  for context in [a, b] {
    context.set_memory_pointers([
      MemoryInfo(first, 65536L, Some(2)),
      MemoryInfo(second, 131072L, Some(2)),
    ])
    context.set_table_pointers([Some(table.table()), Some(table.table())])
  }
  a.set_memory_pointers([
    MemoryInfo(second, 131072L, Some(2)),
    MemoryInfo(first, 65536L, Some(2)),
  ])
  debug_inspect((a.memory_size(0), a.memory_size(1)), content="(131072, 65536)")
  debug_inspect((b.memory_size(0), b.memory_size(1)), content="(65536, 131072)")
  a.set_table_pointers([Some(table.table()), Some(table.table())])
  table.table().set(0, 123L, 4)
  assert_true(a.refresh_table_layout(1))
  assert_true(b.refresh_table_layout(0))
  a.set_memory_pointers([])
  a.set_table_pointers([])
  assert_eq(b.memory_size(0), 65536L)
  b.set_memory_pointers([])
  b.set_table_pointers([])
}

///|
test "empty shaped context supports cleanup and GC binding without memory fields" {
  let layout = @wasmoon_jit.ContextLayout::new(Module(0, 0, 0)).unwrap()
  let context = @wasmoon_jit.NativeJITContext::try_alloc(0, layout=Some(layout)).unwrap()
  inspect(context.memory_size(0), content="0")
  context.set_memory_pointers([])
  context.set_table_pointers([])
  context.bind_globals([]) |> ignore
  let heap = @wasmoon_jit.CHeap()
  context.set_gc_heap_ptr(heap.get_ptr())
  context.clear_gc_heap()
  heap.free()
}

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
  builder.register() |> ignore
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
  first.register() |> ignore
  first.register() |> ignore
  first.unregister()
  first.unregister()
  first.register() |> ignore
  assert_eq(active_dwarf_low_pc(), 4096UL)
  let second = @wasmoon_jit.DWARFBuilder::DWARFBuilder()
  second.add_function("second", 8192L, 16, 2)
  second.register() |> ignore
  first.destroy()
  retained.destroy()
  retained.add_function("closed", 8192L, 16, 9)
  retained.register() |> ignore
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
  index : Int32,
  size : Int32,
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

///|
test "descriptor access validates ranges before touching memory" {
  let memory = @wasmoon_jit.alloc_memory_desc(8L, None)
  let output = FixedArray::make(8, b'\x5A')
  // This first assertion reproduces the old contract failure without an unsafe access.
  assert_eq(@wasmoon_jit.memory_descriptor_read(memory, 8L, output, 0), 0)
  assert_eq(
    @wasmoon_jit.memory_descriptor_write_bytes(memory, 0L, b"abcdefgh", 8),
    0,
  )
  for
    (offset, size) in [
      (-1L, 1),
      (8L, 1),
      (9L, 0),
      (0L, -1),
      (0L, 9),
      (9223372036854775807L, 1),
    ] {
    assert_eq(
      @wasmoon_jit.memory_descriptor_read(memory, offset, output, size),
      -1,
    )
    assert_eq(
      @wasmoon_jit.memory_descriptor_write(memory, offset, output, size),
      -1,
    )
    assert_eq(
      @wasmoon_jit.memory_descriptor_write_bytes(
        memory, offset, b"12345678", size,
      ),
      -1,
    )
    assert_eq(@wasmoon_jit.memory_descriptor_fill(memory, offset, 0, size), -1)
    assert_eq(
      @wasmoon_jit.memory_descriptor_fill64(memory, offset, 0, size.to_int64()),
      -1,
    )
    assert_eq(@wasmoon_jit.memory_descriptor_move(memory, 0L, offset, size), -1)
    assert_eq(@wasmoon_jit.memory_descriptor_move(memory, offset, 0L, size), -1)
    assert_eq(
      @wasmoon_jit.memory_descriptor_copy(
        memory,
        0L,
        memory,
        offset,
        size.to_int64(),
      ),
      -1,
    )
    assert_eq(
      @wasmoon_jit.memory_descriptor_copy(
        memory,
        offset,
        memory,
        0L,
        size.to_int64(),
      ),
      -1,
    )
  }
  for byte in output {
    assert_eq(byte, b'\x5A')
  }
  assert_eq(@wasmoon_jit.memory_descriptor_read(memory, 0L, output, 8), 0)
  assert_eq(Bytes::from_array(Array::makei(8, i => output[i])), b"abcdefgh")
  let small = FixedArray::make(1, b'\x5A')
  assert_eq(@wasmoon_jit.memory_descriptor_read(memory, 0L, small, 2), -1)
  assert_eq(small[0], b'\x5A')
  assert_eq(@wasmoon_jit.memory_descriptor_write(memory, 0L, small, 2), -1)
  assert_eq(@wasmoon_jit.memory_descriptor_write_bytes(memory, 0L, b"x", 2), -1)
  assert_eq(
    @wasmoon_jit.memory_descriptor_fill64(memory, 1L, 0, 9223372036854775807L),
    -1,
  )
  assert_eq(
    @wasmoon_jit.memory_descriptor_copy(
      memory, 0L, memory, 1L, 9223372036854775807L,
    ),
    -1,
  )
  assert_eq(@wasmoon_jit.memory_descriptor_read(memory, 0L, output, 8), 0)
  assert_eq(Bytes::from_array(Array::makei(8, i => output[i])), b"abcdefgh")
}

///|
test "descriptor zero-length operations distinguish empty allocations from absent handles" {
  let memory = @wasmoon_jit.alloc_memory_desc(0L, None)
  let absent = @wasmoon_jit.MemoryDescriptor::null()
  let buffer = FixedArray::make(0, b'\x00')
  for (handle, result) in [(memory, 0), (absent, -1)] {
    assert_eq(
      @wasmoon_jit.memory_descriptor_read(handle, 0L, buffer, 0),
      result,
    )
    assert_eq(
      @wasmoon_jit.memory_descriptor_write(handle, 0L, buffer, 0),
      result,
    )
    assert_eq(
      @wasmoon_jit.memory_descriptor_write_bytes(handle, 0L, b"", 0),
      result,
    )
    assert_eq(@wasmoon_jit.memory_descriptor_move(handle, 0L, 0L, 0), result)
    assert_eq(@wasmoon_jit.memory_descriptor_fill(handle, 0L, 0, 0), result)
    assert_eq(@wasmoon_jit.memory_descriptor_fill64(handle, 0L, 0, 0L), result)
    assert_eq(
      @wasmoon_jit.memory_descriptor_copy(handle, 0L, memory, 0L, 0L),
      result,
    )
    assert_eq(
      @wasmoon_jit.memory_descriptor_copy(memory, 0L, handle, 0L, 0L),
      result,
    )
    assert_eq(@wasmoon_jit.memory_descriptor_read(handle, 1L, buffer, 0), -1)
  }
}

///|
test "descriptor copy preserves overlap and validates both allocations before mutation" {
  let memory = @wasmoon_jit.alloc_memory_desc(8L, None)
  let other = @wasmoon_jit.alloc_memory_desc(2L, None)
  let output = FixedArray::make(8, b'\x00')
  assert_eq(
    @wasmoon_jit.memory_descriptor_write_bytes(memory, 0L, b"abcdefgh", 8),
    0,
  )
  assert_eq(@wasmoon_jit.memory_descriptor_move(memory, 2L, 0L, 6), 0)
  assert_eq(@wasmoon_jit.memory_descriptor_read(memory, 0L, output, 8), 0)
  assert_eq(Bytes::from_array(Array::makei(8, i => output[i])), b"ababcdef")
  assert_eq(@wasmoon_jit.memory_descriptor_copy(memory, 0L, memory, 2L, 6L), 0)
  assert_eq(@wasmoon_jit.memory_descriptor_read(memory, 0L, output, 8), 0)
  assert_eq(Bytes::from_array(Array::makei(8, i => output[i])), b"abcdefef")
  assert_eq(@wasmoon_jit.memory_descriptor_copy(memory, 0L, other, 0L, 3L), -1)
  assert_eq(@wasmoon_jit.memory_descriptor_copy(other, 0L, memory, 0L, 3L), -1)
  assert_eq(@wasmoon_jit.memory_descriptor_read(memory, 0L, output, 8), 0)
  assert_eq(Bytes::from_array(Array::makei(8, i => output[i])), b"abcdefef")
  let small = FixedArray::make(2, b'\x01')
  assert_eq(@wasmoon_jit.memory_descriptor_read(other, 0L, small, 2), 0)
  assert_eq(small[0], b'\x00')
  assert_eq(small[1], b'\x00')
}

///|
test "guarded and shared descriptor access uses committed length rather than reservation" {
  for
    memory in [
      @wasmoon_jit.alloc_guarded_memory_desc(1, Some(2)),
      @wasmoon_jit.alloc_memory_desc(65536L, Some(2L), is_shared=true),
    ] {
    assert_false(memory.is_null())
    assert_eq(
      @wasmoon_jit.memory_descriptor_write_bytes(memory, 65535L, b"x", 1),
      0,
    )
    assert_eq(
      @wasmoon_jit.memory_descriptor_write_bytes(memory, 65536L, b"x", 1),
      -1,
    )
    assert_eq(@wasmoon_jit.memory_descriptor_fill64(memory, 65536L, 0, 0L), 0)
    assert_eq(@wasmoon_jit.memory_descriptor_grow64(memory, 1L), 1L)
    assert_eq(
      @wasmoon_jit.memory_descriptor_write_bytes(memory, 65536L, b"x", 1),
      0,
    )
    assert_eq(
      @wasmoon_jit.memory_descriptor_write_bytes(memory, 131072L, b"x", 1),
      -1,
    )
  }
}

///|
test "context allocates optional segment state on demand and releases it on reset" {
  inspect(@native_test_support.context_optional_state(), content="1")
}

///|
test "Store callable registry updates are shared and preserve instance isolation" {
  let first = @wasmoon_jit.NativeCallableRegistry::new()
  let second = @wasmoon_jit.NativeCallableRegistry::new()
  assert_true(first.replace([-1, 0], [(16777216L, 1)]))
  assert_true(second.replace([-1, 0], [(16777216L, 0)]))
  let a = @jit_ffi.JITContext::new(1)
  let b = @jit_ffi.JITContext::new(1)
  let c = @jit_ffi.JITContext::new(1)
  a.bind_callable_registry(first, [0], [7])
  b.bind_callable_registry(first, [1], [8])
  c.bind_callable_registry(second, [0], [9])
  inspect(@native_test_support.context_callable_tag(a), content="7")
  inspect(@native_test_support.context_callable_tag(b), content="8")
  inspect(
    @native_test_support.context_callable_lookup(a, 16777216L),
    content="1",
  )
  inspect(
    @native_test_support.context_callable_lookup(c, 16777216L),
    content="0",
  )
  inspect(
    @native_test_support.context_callable_subtype(a, 16777216L, 0),
    content="1",
  )
  assert_true(first.replace([-1, -1], [(16777216L, 1)]))
  inspect(
    @native_test_support.context_callable_subtype(a, 16777216L, 0),
    content="0",
  )
  assert_true(first.replace([-1, 0], [(16777216L, 0)]))
  inspect(
    @native_test_support.context_callable_lookup(b, 16777216L),
    content="0",
  )
  inspect(
    @native_test_support.context_callable_subtype(b, 16777216L, 0),
    content="0",
  )
  inspect(
    @native_test_support.context_callable_subtype(a, 16777216L, 2147483647),
    content="0",
  )
  a.bind_callable_registry(second, [0], [10])
  first.clear()
  first.clear()
  inspect(
    @native_test_support.context_callable_lookup(b, 16777216L),
    content="-1",
  )
  inspect(
    @native_test_support.context_callable_lookup(a, 16777216L),
    content="0",
  )
  assert_true(second.replace([-1, 0], [(16777216L, 1)]))
  inspect(
    @native_test_support.context_callable_lookup(a, 16777216L),
    content="1",
  )
  inspect(@native_test_support.context_callable_tag(a), content="10")
}

///|
fn context_outliving_registry() -> @jit_ffi.JITContext {
  let registry = @wasmoon_jit.NativeCallableRegistry::new()
  assert_true(registry.replace([-1], [(16L, 0)])) catch {
    _ => abort("registry setup failed")
  }
  let context = @jit_ffi.JITContext::new(1)
  context.bind_callable_registry(registry, [0], [7])
  context
}

///|
test "context retains MoonBit array storage after registry owner leaves scope" {
  let context = context_outliving_registry()
  inspect(
    @native_test_support.context_callable_lookup(context, 16L),
    content="0",
  )
  inspect(
    @native_test_support.context_callable_subtype(context, 16L, 0),
    content="1",
  )
  inspect(@native_test_support.context_callable_tag(context), content="7")
}

///|
test "safepoint tables own copied metadata through replacement and teardown" {
  inspect(@native_test_support.safepoint_ownership(), content="1")
}

///|
test "callable lookup sorts privately and preserves the first duplicate" {
  let registry = @wasmoon_jit.NativeCallableRegistry::new()
  let entries = [(48L, 2), (16L, 1), (32L, 0), (16L, 9)]
  assert_true(registry.replace([-1, 0, 0], entries))
  assert_eq(entries, [(48L, 2), (16L, 1), (32L, 0), (16L, 9)])
  for
    (pointer, expected) in [(16L, 1), (32L, 0), (48L, 2), (24L, -1), (64L, -1)] {
    assert_eq(@native_test_support.callable_lookup(registry, pointer), expected)
  }
  entries[1] = (16L, 7)
  assert_true(registry.replace([-1, 0, 0], entries))
  inspect(@native_test_support.callable_lookup(registry, 16L), content="7")
  let many = Array::makei(1024, i => ((1024 - i).to_int64() * 16, i))
  assert_true(registry.replace([], many))
  for i in 0..<1024 {
    assert_eq(
      @native_test_support.callable_lookup(registry, (1024 - i).to_int64() * 16),
      i,
    )
  }
  registry.clear()
  inspect(@native_test_support.callable_lookup(registry, 16L), content="-1")
}

///|
test "activation scratch roots survive reentry and isolate parked abandonment" {
  inspect(@native_test_support.activation_scratch_isolation(), content="1")
}

///|
test "parked scratch roots survive GC and resume restores the actual caller" {
  inspect(@native_test_support.activation_resume_roots(), content="1")
}

///|
fn context_with_owned_gc_metadata() -> @jit_ffi.JITContext raise {
  let context = @jit_ffi.JITContext::new(2)
  let types : FixedArray[Int32] = [-1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  let indices : FixedArray[Int32] = [0, 1]
  context.bind_gc_metadata(types, indices, indices)
  // Both slots alias one array; rebinding must retain before releasing either.
  context.bind_gc_metadata(types, indices, indices)
  assert_eq(
    @native_test_support.context_gc_metadata_shares(
      context, types, indices, indices,
    ),
    1,
  ) catch {
    _ => abort("GC metadata was copied")
  }
  context
}

///|
test "GC metadata survives MoonBit owners and supports replacement and clearing" {
  let first = context_with_owned_gc_metadata()
  let second = context_with_owned_gc_metadata()
  inspect(@native_test_support.context_gc_legacy_rebind(second), content="1")
  second.bind_gc_metadata([-1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [], [0, 1])
  inspect(
    @native_test_support.context_gc_funcref_subtype(first, 1, 0),
    content="1",
  )
  first.bind_gc_metadata([-1, 0, 0, 0, 0, 0, -1, 0, 0, 0, 0, 0], [], [0, 1])
  inspect(
    @native_test_support.context_gc_funcref_subtype(first, 1, 0),
    content="0",
  )
  inspect(
    @native_test_support.context_gc_funcref_subtype(second, 1, 0),
    content="1",
  )
  first.bind_gc_metadata([-1, 0, 0, 0, 0, 0], [], [0, 0])
  inspect(
    @native_test_support.context_gc_funcref_subtype(first, 1, 0),
    content="1",
  )
  first.bind_gc_metadata([], [], [])
  first.bind_gc_metadata([], [], [])
  inspect(
    @native_test_support.context_gc_funcref_subtype(first, 1, 0),
    content="0",
  )
}

///|
fn context_with_owned_gc_payloads() -> @jit_ffi.JITContext {
  let context = @jit_ffi.JITContext::new(2)
  let blob = Bytes::from_array([1, 2, 3])
  let offsets : FixedArray[Int32] = [4, 12]
  let addresses : FixedArray[Int64] = [16L, 32L]
  for _ in 0..<2 {
    guard context.bind_gc_safepoints(0, blob, offsets) else {
      abort("binding failed")
    }
    context.bind_gc_function_addresses(addresses)
  }
  guard @native_test_support.context_gc_payload_shares(
      context, blob, offsets, addresses,
    ) ==
    1 else {
    abort("GC payloads were copied")
  }
  context
}

///|
test "GC payloads retain MoonBit owners through replacement and legacy bindings" {
  let first = context_with_owned_gc_payloads()
  let second = context_with_owned_gc_payloads()
  inspect(@native_test_support.context_gc_payload_valid(first), content="1")
  assert_false(first.bind_gc_safepoints(-1, b"", []))
  assert_false(first.bind_gc_safepoints(2, b"", []))
  inspect(@native_test_support.context_gc_payload_valid(first), content="1")
  inspect(@native_test_support.context_gc_payload_legacy(first), content="1")
  assert_true(first.bind_gc_safepoints(0, b"", []))
  first.bind_gc_function_addresses([])
  inspect(@native_test_support.context_gc_payload_empty(first), content="1")
  assert_true(first.bind_gc_safepoints(0, b"", []))
  first.bind_gc_function_addresses([])
  inspect(@native_test_support.context_gc_payload_valid(second), content="1")
  assert_true(
    first.bind_gc_safepoints(0, Bytes::from_array([1, 2, 3]), [4, 12]),
  )
  first.bind_gc_function_addresses([16L, 32L])
  inspect(@native_test_support.context_gc_payload_valid(first), content="1")
}

///|
test "invocation controls isolate reentry and retain parked cancellation captures" {
  inspect(@native_test_support.activation_controls(), content="1")
}

///|
fn contexts_with_owned_segments() -> (@jit_ffi.JITContext, @jit_ffi.JITContext) {
  let first = @jit_ffi.JITContext::new(1)
  let second = @jit_ffi.JITContext::new(1)
  let blob = Bytes::from_array([1, 2, 3])
  let data = [blob]
  let elements = [[16L, 0L]]
  guard first.set_segments(data, elements) &&
    second.set_segments(data, elements) else {
    abort("segment binding failed")
  }
  guard @native_test_support.context_segments_share_data(first, blob) == 1 else {
    abort("immutable segment data was copied")
  }
  data[0] = b"changed"
  elements[0][0] = 99L
  (first, second)
}

///|
test "segment snapshots retain data and isolate mutable inputs and instance drop state" {
  let (first, second) = contexts_with_owned_segments()
  inspect(@native_test_support.context_segments_valid(first), content="1")
  inspect(@native_test_support.context_segments_valid(second), content="1")
  inspect(@native_test_support.context_segments_legacy(first), content="1")
  inspect(@native_test_support.context_segments_valid(second), content="1")
  assert_true(first.set_segments([], []))
  assert_true(first.set_segments([], []))
  inspect(@native_test_support.context_segments_empty(first), content="1")
  assert_true(
    first.set_segments([Bytes::from_array([1, 2, 3])], [[16L, 0L, 99L]]),
  )
  inspect(@native_test_support.context_segments_valid(first), content="1")
}

///|
test "function address arrays retain storage without owning executable pointers" {
  inspect(
    @native_test_support.context_function_array(@jit_ffi.JITContext::new(0)),
    content="1",
  )
  inspect(
    @native_test_support.context_function_array(@jit_ffi.JITContext::new(2)),
    content="1",
  )
  inspect(@native_test_support.raw_context_function_array(), content="1")
  assert_true(@wasmoon_jit.NativeJITContext::try_alloc(-1) is None)
}

///|
test "global pointer tables snapshot addresses and release both ownership modes" {
  guard @wasmoon_jit.NativeJITContext::try_alloc(0) is Some(context) else {
    fail("context allocation failed")
  }
  let addresses = FixedArray::make(2, 16L)
  let table = context.bind_globals(addresses)
  addresses[0] = 32L
  inspect(@wasmoon_jit.native_value_slot_read(table, 0), content="16")
  inspect(@wasmoon_jit.native_value_slot_read(table, 1), content="16")
  context.bind_globals([]) |> ignore
  context.bind_globals([48L]) |> ignore
  inspect(@native_test_support.context_globals_ownership(), content="1")
}

///|
test "trap recovery preserves thread masks and alternate signal stack" {
  inspect(@native_test_support.trap_signal_masks(), content="1")
}

///|
fn contexts_with_shared_safepoints() -> (
  @jit_ffi.JITContext,
  @jit_ffi.JITContext,
) raise {
  let offsets : FixedArray[Int32] = [4]
  let owner = @jit_ffi.PreparedSafepoints::new([b"\x01"], [offsets])
  offsets[0] = 99
  let a = @jit_ffi.JITContext::new(2)
  let b = @jit_ffi.JITContext::new(2)
  assert_true(a.bind_prepared_safepoints(owner))
  assert_true(b.bind_prepared_safepoints(owner))
  assert_false(@jit_ffi.JITContext::new(0).bind_prepared_safepoints(owner))
  (a, b)
}

///|
test "empty safepoints allocate no table and clearing still releases an entry" {
  for count in [1, 1000] {
    let context = @jit_ffi.JITContext::new(count)
    for i in 0..<count {
      assert_true(context.bind_gc_safepoints(i, b"", []))
    }
    inspect(@native_test_support.safepoint_slots(context), content="0")
    assert_true(context.bind_gc_safepoints(0, b"\x01", [4]))
    assert_eq(@native_test_support.safepoint_slots(context), count)
    assert_true(context.bind_gc_safepoints(0, b"", []))
  }
}

///|
test "shared safepoints outlive their caller and isolate rebinding from parked frames" {
  let (a, b) = contexts_with_shared_safepoints()
  inspect(@native_test_support.safepoints_shared(a, b), content="1")
  inspect(@native_test_support.safepoint_parked_sharing(a, b), content="1")
  inspect(@native_test_support.safepoints_shared(a, b), content="0")
  assert_true(a.bind_gc_safepoints(0, b"", []))
  assert_true(b.bind_gc_safepoints(0, b"", []))
}

///|
test "safepoint allocation respects external object payload bounds" {
  inspect(@native_test_support.safepoint_allocation_bounds(), content="1")
}

///|
extern "c" fn fail_native_allocation_for_tests(attempt : Int32) -> Unit = "wasmoon_native_fail_allocation_for_tests"

///|
test "native allocation denial restores invocation state and remains recoverable" {
  inspect(@native_test_support.native_failure_recovery(), content="1")
}

///|
test "native segment allocation failure leaves the context reusable" {
  let context = @jit_ffi.JITContext::new(0)
  fail_native_allocation_for_tests(1)
  defer fail_native_allocation_for_tests(0)
  inspect(context.set_segments([b"abc"], [[1L, 2L]]), content="false")
  inspect(context.set_segments([b"abc"], [[1L, 2L]]), content="true")
}

///|
test "invalid native metadata is rejected before a valid replacement" {
  let context = @jit_ffi.JITContext::new(1)
  let invalid_stride = try {
    context.bind_gc_metadata([1], [], [])
    false
  } catch {
    _ => true
  }
  inspect(invalid_stride, content="true")
  context.bind_gc_metadata([-1, 0, 0, 0, 0, 0], [0], [0])
  let mismatch = try {
    @jit_ffi.PreparedSafepoints::new([b""], []) |> ignore
    false
  } catch {
    _ => true
  }
  inspect(mismatch, content="true")
  let oversized = try {
    @jit_ffi.PreparedSafepoints::check_count(0x7fffffff)
    false
  } catch {
    _ => true
  }
  inspect(oversized, content="true")
  @jit_ffi.PreparedSafepoints::new([], []) |> ignore
}

///|
test "DWARF allocation denial does not publish partial debugger metadata" {
  let active = @wasmoon_jit.DWARFBuilder::DWARFBuilder()
  defer active.destroy()
  active.add_function("existing", 4096L, 16, 0)
  assert_true(active.register())
  let mut rejected = 0
  let mut accepted = 0
  for attempt in 1..<=24 {
    let builder = @wasmoon_jit.DWARFBuilder::DWARFBuilder()
    for index in 0..<40 {
      builder.add_function(
        "long_function_name_for_allocation_recovery_\{index}",
        8192L + index.to_int64() * 16L,
        16,
        index,
      )
    }
    fail_native_allocation_for_tests(attempt)
    let registered = builder.register()
    fail_native_allocation_for_tests(0)
    if registered {
      accepted += 1
    } else {
      rejected += 1
      inspect(active_dwarf_low_pc(), content="4096")
    }
    assert_true(builder.register())
    assert_true(builder.lookup_address(8193L) is Some(_))
    builder.destroy()
    assert_true(active.register())
  }
  assert_true(rejected >= 4)
  assert_true(accepted > 0)
}

///|
test "native memory and table replacement denial preserves both ownership views" {
  let first = @wasmoon_jit.alloc_memory_desc(65536L, Some(2L))
  let second = @wasmoon_jit.alloc_memory_desc(131072L, Some(2L))
  let context = @wasmoon_jit.NativeJITContext::try_alloc(0).unwrap()
  context.set_memory_pointers([MemoryInfo(first, 65536L, Some(2))])
  fail_native_allocation_for_tests(1)
  defer fail_native_allocation_for_tests(0)
  let memory_denied = try {
    context.set_memory_pointers([MemoryInfo(second, 131072L, Some(2))])
    false
  } catch {
    MemoryBindingAllocationFailed => true
    _ => false
  }
  inspect(memory_denied, content="true")
  inspect(context.memory_size(0), content="65536")
  context.set_memory_pointers([MemoryInfo(second, 131072L, Some(2))])
  inspect(context.memory_size(0), content="131072")
  let first_table = @wasmoon_jit.JITTableOwner::try_alloc(1, None).unwrap()
  let second_table = @wasmoon_jit.JITTableOwner::try_alloc(2, None).unwrap()
  defer first_table.close()
  defer second_table.close()
  context.set_table_pointers([Some(first_table.table())])
  for attempt in 1..<=4 {
    fail_native_allocation_for_tests(attempt)
    let table_denied = try {
      context.set_table_pointers([Some(second_table.table())])
      false
    } catch {
      TableBindingAllocationFailed => true
      _ => false
    }
    inspect(table_denied, content="true")
    assert_true(context.refresh_table_layout(0))
    inspect(first_table.table().get_size(), content="1")
    inspect(second_table.table().get_size(), content="2")
  }
  context.set_table_pointers([Some(second_table.table())])
  assert_true(context.refresh_table_layout(0))
  context.set_memory_pointers([])
  context.set_table_pointers([])
}

///|
test "native binding layout rejection preserves the previous valid bindings" {
  let layout = @wasmoon_jit.ContextLayout::new(Module(1, 0, 0)).unwrap()
  let context = @wasmoon_jit.NativeJITContext::try_alloc(0, layout=Some(layout)).unwrap()
  let memory = @wasmoon_jit.alloc_memory_desc(1L, None, is_memory64=true)
  let info = @wasmoon_jit.MemoryInfo::MemoryInfo(memory, 1L, None)
  context.set_memory_pointers([info])
  let invalid = try {
    context.set_memory_pointers([info, info])
    false
  } catch {
    InvalidBinding(_) => true
    _ => false
  }
  inspect(invalid, content="true")
  inspect(context.memory_size(0), content="1")
  context.set_memory_pointers([])
}

///|
test "executable allocation denial is typed and a later installation succeeds" {
  let installer = @wasmoon_jit.JitCodeInstaller::new(fn(_) { None })
  let code = match @wasmoon_jit.host_native_target() {
    AArch64 => [0xC0, 0x03, 0x5F, 0xD6]
    X64 => [0xC3]
  }
  fail_native_allocation_for_tests(1)
  defer fail_native_allocation_for_tests(0)
  let denied = try {
    installer.install_trampoline(code).release()
    false
  } catch {
    TrampolineAllocationFailed(code_size~) => code_size == code.length()
    _ => false
  }
  inspect(denied, content="true")
  let installed = installer.install_trampoline(code)
  assert_true(installed.entry_address() != 0L)
  installed.release()
}

///|
test "Windows fiber preparation failure returns to the host without running its entry" {
  if @jit_ffi.is_windows() {
    let entered = Ref(false)
    let fiber = @wasmoon_jit.NativeFiber::new(fn() {
      entered.val = true
      37L
    })
    fail_native_allocation_for_tests(1)
    defer fail_native_allocation_for_tests(0)
    let rejected = try {
      fiber.continue_with() |> ignore
      false
    } catch {
      NativeFailure(-5) => true
      _ => false
    }
    inspect(rejected, content="true")
    inspect(entered.val, content="false")
    debug_inspect(fiber.phase(), content="Ready")
    debug_inspect(fiber.continue_with(), content="Finished(37)")
    let started = Ref(false)
    let second = @wasmoon_jit.NativeFiber::new(fn() {
      started.val = true
      42L
    })
    fail_native_allocation_for_tests(2)
    let startup_failed = try {
      second.continue_with() |> ignore
      false
    } catch {
      NativeFailure(-5) => true
      _ => false
    }
    inspect(startup_failed, content="true")
    inspect(started.val, content="false")
    debug_inspect(second.phase(), content="Cancelled")
    let next = @wasmoon_jit.NativeFiber::new(fn() { 42L })
    debug_inspect(next.continue_with(), content="Finished(42)")
  }
}

///|
test "DWARF function capacity denial does not register a truncated object" {
  let active = @wasmoon_jit.DWARFBuilder::DWARFBuilder()
  defer active.destroy()
  active.add_function("existing", 4096L, 16, 0)
  assert_true(active.register())
  let builder = @wasmoon_jit.DWARFBuilder::DWARFBuilder()
  defer builder.destroy()
  for index in 0..<1025 {
    builder.add_function("function", 8192L + index.to_int64() * 16L, 16, index)
  }
  inspect(builder.register(), content="false")
  inspect(active_dwarf_low_pc(), content="4096")
}

///|
fn exercise_cleanup_capture(early : Bool, calls : Ref[Int32]) -> Unit {
  let capture = @native_test_support.callback_capture()
  let cleanup = @jit_ffi.CleanupOwner::new(fn() {
    capture.touch()
    calls.val += 1
  })
  if early {
    cleanup.close()
    cleanup.close()
  }
}

///|
test "managed cleanup releases its callback capture after close or RC finalization" {
  @native_test_support.reset_callback_capture()
  let calls = Ref(0)
  for early in [false, true] {
    exercise_cleanup_capture(early, calls)
    assert_eq(@native_test_support.callback_capture_release_count(), calls.val)
  }
  inspect(calls.val, content="2")
}

///|
fn context_retaining_exception_registry() -> @jit_ffi.JITContext raise {
  let heap = @wasmoon_jit.CHeap()
  let arena = @jit_ffi.NativeExceptionArena::new()
  arena.enable_reclamation()
  assert_true(arena.define_tag(7, []))
  assert_true(arena.insert(heap.get_ptr(), 7, []) > 0L)
  let context = @jit_ffi.JITContext::new(0)
  context.bind_exception_arena(arena)
  heap.free()
  context
}

///|
fn exercise_context_exception_registry(baseline : Int64) -> Unit raise {
  let context = context_retaining_exception_registry()
  // The public arena and heap wrappers have expired; only the context retains
  // the registry, whose zero-word snapshot still owns a heap root lease.
  assert_eq(heap_live_count(), baseline + 1L)
  context.bind_globals([]) |> ignore
}

///|
test "context retains MoonBit exception state without a cycle through its heap" {
  let baseline = heap_live_count()
  exercise_context_exception_registry(baseline)
  assert_eq(heap_live_count(), baseline)
}

///|
test "exception payload and root allocation failures roll back quota and identity" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  let arena = @jit_ffi.NativeExceptionArena::new()
  defer arena.clear()
  arena.enable_reclamation()
  assert_true(arena.define_tag(7, [I64]))
  let bytes = @jit_ffi.Quota::new(32L)
  let objects = @jit_ffi.Quota::new(1L)
  assert_true(arena.bind_quotas(bytes, objects))
  let mut previous = 0L
  // Backing storage, payload, root registration and root buffer are fallible.
  for attempt in [1, 2, 3, 4] {
    fail_native_allocation_for_tests(attempt)
    let failed = arena.insert(heap.get_ptr(), 7, [42L])
    fail_native_allocation_for_tests(0)
    assert_eq(failed, 0L)
    assert_eq(bytes.used(), 0L)
    assert_eq(objects.used(), 0L)
    let reference = arena.insert(heap.get_ptr(), 7, [42L])
    assert_true(reference > previous)
    previous = reference
    assert_eq(arena.snapshot(reference), Some((7, [42L])))
    assert_eq(bytes.used(), 32L)
    assert_eq(objects.used(), 1L)
    arena.release_snapshot(reference)
    arena.release_snapshot(reference)
    assert_true(arena.snapshot(reference) is None)
    assert_eq(bytes.used(), 0L)
    assert_eq(objects.used(), 0L)
  }
  // A mismatched typed payload is rejected before acquiring any quota.
  assert_eq(arena.insert(heap.get_ptr(), 7, []), 0L)
  assert_eq(bytes.used(), 0L)
  arena.clear()
  assert_eq(arena.insert(heap.get_ptr(), 7, [42L]), 0L)
  assert_false(arena.define_tag(8, []))
}

///|
test "only the last exception root lease releases a heap's borrowed arena" {
  let heap = @wasmoon_jit.CHeap()
  defer heap.free()
  let first = @jit_ffi.NativeExceptionArena::new()
  let next = @jit_ffi.NativeExceptionArena::new()
  defer first.clear()
  defer next.clear()
  first.enable_reclamation()
  next.enable_reclamation()
  let a = first.insert(heap.get_ptr(), 7, [])
  let b = first.insert(heap.get_ptr(), 7, [])
  assert_true(a > 0L && b > a)
  first.release_snapshot(a)
  assert_eq(next.insert(heap.get_ptr(), 7, []), 0L)
  assert_eq(first.snapshot(b), Some((7, [])))
  first.release_snapshot(b)
  let c = next.insert(heap.get_ptr(), 7, [])
  assert_true(c > 0L)
  next.release_snapshot(c)
  // Also exercise collection after the last traced registration disappears.
  let dead = heap.alloc_struct(0, [I32(42)])
  assert_eq(heap.collect([]), 1)
  assert_false(heap.is_valid(dead))
}

///|
test "exception registry preserves identity across unordered release and per-heap sweep" {
  let first = @wasmoon_jit.CHeap()
  let second = @wasmoon_jit.CHeap()
  defer first.free()
  defer second.free()
  let arena = @jit_ffi.NativeExceptionArena::new()
  defer arena.clear()
  arena.enable_reclamation()
  assert_true(arena.define_tag(7, [I64]))
  first.get_ptr().bind_root_visitor(fn(_, roots) { roots })
  second.get_ptr().bind_root_visitor(fn(_, roots) { roots })
  defer first.get_ptr().clear_root_visitor()
  defer second.get_ptr().clear_root_visitor()
  let references : Array[Int64] = []
  for i in 0..<128 {
    let heap = if i % 2 == 0 { first } else { second }
    references.push(arena.insert(heap.get_ptr(), 7, [i.to_int64()]))
  }
  // Release in a different order from creation before collecting one heap.
  for i = 126; i >= 0; i = i - 3 {
    arena.release_snapshot(references[i])
  }
  first.collect_raw([references[2]]) |> ignore
  for i, reference in references {
    if i == 2 || (i % 2 == 1 && i % 3 != 0) {
      assert_eq(arena.snapshot(reference), Some((7, [i.to_int64()])))
    } else {
      assert_true(arena.snapshot(reference) is None)
    }
  }
  second.collect_raw([]) |> ignore
  assert_eq(arena.snapshot(references[2]), Some((7, [2L])))
  first.collect_raw([]) |> ignore
  for reference in references {
    assert_true(arena.snapshot(reference) is None)
  }
  let fresh = arena.insert(first.get_ptr(), 7, [42L])
  assert_true(fresh > references[127])
  for
    invalid in [
      0L,
      -1L,
      fresh + 1L,
      fresh ^ 0x100000000L,
      fresh ^ 0x2000000000000000L,
    ] {
    assert_true(arena.snapshot(invalid) is None)
    arena.release_snapshot(invalid)
  }
  assert_eq(arena.snapshot(fresh), Some((7, [42L])))
}

///|
test "exception layout cache observes tag definitions and alternating payload shapes" {
  let arena = @jit_ffi.NativeExceptionArena::new()
  defer arena.clear()
  let heap = @jit_ffi.GCHeapHandle::null()
  // An unknown tag initially permits a conservative payload description.
  let unknown = arena.insert(heap, 7, [7L])
  assert_true(unknown > 0L)
  assert_true(arena.define_tag(7, [I64]))
  assert_eq(arena.insert(heap, 7, []), 0L)
  assert_true(arena.define_tag(8, []))
  for _ in 0..<4 {
    assert_eq(arena.insert(heap, 8, [8L]), 0L)
    let empty = arena.insert(heap, 8, [])
    let word = arena.insert(heap, 7, [42L])
    assert_true(empty > 0L && word > empty)
    assert_eq(arena.snapshot(empty), Some((8, [])))
    assert_eq(arena.snapshot(word), Some((7, [42L])))
    arena.release_snapshot(empty)
    arena.release_snapshot(word)
  }
  assert_eq(arena.snapshot(unknown), Some((7, [7L])))
}

///|
test "DWARF owns long UTF-8 names independently across registered builders" {
  let first = @wasmoon_jit.DWARFBuilder()
  defer first.destroy()
  let second = @wasmoon_jit.DWARFBuilder()
  defer second.destroy()
  let name = String::from_array(Array::make(400, '叶')) + "😀"
  first.add_function(name, 4096L, 64, 7)
  assert_true(first.register())
  second.add_function("other😀", 8192L, 64, 9)
  assert_true(second.register())
  guard first.lookup_address(4101L) is Some(info) else {
    fail("lost first owner")
  }
  assert_eq(info.name, name)
  assert_eq(info.func_idx, 7)
  assert_eq(info.offset, 5L)
  guard second.lookup_address(8199L) is Some(other) else {
    fail("lost second owner")
  }
  assert_eq(other.name, "other😀")
  first.destroy()
  assert_true(first.lookup_address(4101L) is None)
  assert_true(second.lookup_address(8199L) is Some(_))
}

///|
test "DWARF name allocation failure keeps the previous registered owner intact" {
  let active = @wasmoon_jit.DWARFBuilder()
  defer active.destroy()
  active.add_function("active", 4096L, 64, 1)
  assert_true(active.register())
  let rejected = @wasmoon_jit.DWARFBuilder()
  defer rejected.destroy()
  fail_native_allocation_for_tests(1)
  rejected.add_function("allocation-denied", 8192L, 64, 2)
  fail_native_allocation_for_tests(0)
  assert_false(rejected.register())
  assert_true(rejected.lookup_address(8193L) is None)
  assert_eq(active_dwarf_low_pc(), 4096UL)
  assert_true(active.lookup_address(4097L) is Some(_))
}
