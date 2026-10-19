///|
pub using @runtime_bridge {
  memory_descriptor_length,
  memory_descriptor_grow,
  memory_descriptor_read,
  memory_descriptor_write,
  memory_descriptor_write_bytes,
  memory_descriptor_move,
  memory_descriptor_fill,
  type MemoryInfo,
  alloc_memory,
  alloc_memory_desc,
  alloc_guarded_memory_desc,
  free_memory,
  type JITTable,
  type JITTableOwner,
  memory_descriptor_copy,
  memory_descriptor_fill64,
  memory_descriptor_grow64,
  type MemoryDescriptor,
  type NativeTableHandle,
}

///|
fn context_func_table_ptr(context : JITContext) -> Int64 {
  c_jit_ctx_get_func_table_managed(context)
}

///|
fn context_func_count(context : JITContext) -> Int32 {
  c_jit_ctx_get_func_count_managed(context)
}

///|
fn context_table_ptr(
  context : JITContext,
  table_idx : Int32,
) -> NativeTableHandle {
  c_jit_ctx_get_table_ptr_managed(context, table_idx)
}

///|
fn context_table_size(context : JITContext, table_idx : Int32) -> Int32 {
  c_jit_ctx_get_table_size_managed(context, table_idx)
}

///|
pub fn NativeJITContext::set_memory(
  self : NativeJITContext,
  mem0_ptr : MemoryDescriptor,
) -> Unit {
  c_jit_ctx_set_memory_managed(self.handle, mem0_ptr)
}

///|
pub fn NativeJITContext::alloc_guarded_memory(
  self : NativeJITContext,
  initial_pages : Int32,
  max_pages : Int32?,
) -> MemoryDescriptor {
  c_jit_ctx_alloc_guarded_memory_managed(
    self.handle,
    initial_pages.to_int64(),
    max_pages.unwrap_or(-1).to_int64(),
  )
}

///|
pub fn NativeJITContext::func_ptr(
  self : NativeJITContext,
  func_idx : Int32,
) -> Int64 {
  let table_ptr = context_func_table_ptr(self.handle)
  let count = context_func_count(self.handle)
  if table_ptr != 0L && func_idx >= 0 && func_idx < count {
    native_value_slot_read(table_ptr, func_idx)
  } else {
    0L
  }
}

///|
pub fn NativeJITContext::set_table_pointers(
  self : NativeJITContext,
  jit_tables : Array[JITTable?],
) -> Unit raise NativeSetupError {
  let replacement = jit_tables.copy()
  let table_ptrs = FixedArray::make(
    jit_tables.length(),
    NativeTableHandle::null(),
  )
  let table_sizes = FixedArray::make(jit_tables.length(), 0)
  let table_max_sizes = FixedArray::make(jit_tables.length(), -1L)
  for i, jit_table_opt in jit_tables {
    match jit_table_opt {
      Some(jit_table) => {
        table_ptrs[i] = jit_table.raw_ptr()
        table_sizes[i] = jit_table.get_size()
        table_max_sizes[i] = jit_table.get_max().unwrap_or(-1L)
      }
      None => ()
    }
  }
  let status = c_jit_ctx_set_table_pointers_managed(
    self.handle,
    table_ptrs,
    table_sizes,
    table_max_sizes,
    jit_tables.length(),
  )
  match status {
    1 => ()
    0 => raise TableBindingAllocationFailed
    _ => raise InvalidBinding("table count exceeds layout or context is closed")
  }
  self.jit_tables.clear()
  for table in replacement {
    self.jit_tables.push(table)
  }
}

///|
/// Refresh one borrowed table from the context it was registered with.
/// The context supplies both the table identity and its live C-side layout.
pub fn NativeJITContext::refresh_table_layout(
  self : NativeJITContext,
  table_idx : Int32,
) -> Bool {
  if table_idx < 0 || table_idx >= self.jit_tables.length() {
    return false
  }
  guard self.jit_tables[table_idx] is Some(jit_table) else { return false }
  let table_ptr = context_table_ptr(self.handle, table_idx)
  let size = context_table_size(self.handle, table_idx)
  if jit_table.raw_ptr().is_null() || table_ptr.is_null() || size < 0 {
    return false
  }
  jit_table.refresh_layout(table_ptr, size)
  true
}

///|
pub fn NativeJITContext::set_memory_pointers(
  self : NativeJITContext,
  memories : Array[MemoryInfo],
) -> Unit raise NativeSetupError {
  let ptrs = FixedArray::make(memories.length(), MemoryDescriptor::null())
  for i, mem in memories {
    ptrs[i] = mem.ptr
  }
  match
    c_jit_ctx_set_memory_pointers_managed(self.handle, ptrs, memories.length()) {
    1 => ()
    0 => raise MemoryBindingAllocationFailed
    _ =>
      raise InvalidBinding("memory count exceeds layout or context is closed")
  }
}

///|
/// Borrow a raw byte address. Use memory_descriptor for accesses that must
/// retain the allocation independently of this context.
pub fn NativeJITContext::memory_ptr(
  self : NativeJITContext,
  memidx : Int32,
) -> Int64 {
  c_jit_ctx_get_memory_ptr_managed(self.handle, memidx)
}

///|
pub fn NativeJITContext::memory_size(
  self : NativeJITContext,
  memidx : Int32,
) -> Int64 {
  c_jit_ctx_get_memory_size_managed(self.handle, memidx)
}

///|
/// Retain a bound memory independently of this context. Invalid indices return
/// an empty handle. Passing this handle to descriptor operations keeps the
/// allocation alive throughout the operation.
pub fn NativeJITContext::memory_descriptor(
  self : NativeJITContext,
  memidx : Int32,
) -> MemoryDescriptor {
  c_jit_ctx_get_memory_descriptor_managed(self.handle, memidx)
}
