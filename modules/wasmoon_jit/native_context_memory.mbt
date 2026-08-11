/// Linear-memory and indirect-table support for managed native JIT contexts.

///|
pub fn memory_descriptor_length(mem_desc_ptr : Int64) -> Int64 {
  c_mem_desc_get_len(mem_desc_ptr)
}

///|
pub fn memory_descriptor_grow(
  mem_desc_ptr : Int64,
  delta_pages : Int,
  max_pages : Int,
) -> Int {
  c_mem_desc_grow(mem_desc_ptr, delta_pages, max_pages)
}

///|
#borrow(out)
pub fn memory_descriptor_read(
  mem_desc_ptr : Int64,
  offset : Int64,
  out : FixedArray[Byte],
  size : Int,
) -> Int {
  c_mem_desc_read(mem_desc_ptr, offset, out, size)
}

///|
#borrow(data)
pub fn memory_descriptor_write(
  mem_desc_ptr : Int64,
  offset : Int64,
  data : FixedArray[Byte],
  size : Int,
) -> Int {
  c_mem_desc_write(mem_desc_ptr, offset, data, size)
}

///|
#borrow(data)
pub fn memory_descriptor_write_bytes(
  mem_desc_ptr : Int64,
  offset : Int64,
  data : Bytes,
  size : Int,
) -> Int {
  c_mem_desc_write_bytes(mem_desc_ptr, offset, data, size)
}

///|
pub fn memory_descriptor_move(
  mem_desc_ptr : Int64,
  destination : Int64,
  source : Int64,
  size : Int,
) -> Int {
  c_mem_desc_memmove(mem_desc_ptr, destination, source, size)
}

///|
pub fn memory_descriptor_fill(
  mem_desc_ptr : Int64,
  destination : Int64,
  value : Int,
  size : Int,
) -> Int {
  c_mem_desc_memset(mem_desc_ptr, destination, value, size)
}

///|
fn context_func_table_ptr(context : JITContext) -> Int64 {
  c_jit_ctx_get_func_table_managed(context)
}

///|
fn context_func_count(context : JITContext) -> Int {
  c_jit_ctx_get_func_count_managed(context)
}

///|
fn context_table_ptr(context : JITContext, table_idx : Int) -> Int64 {
  c_jit_ctx_get_table_ptr_managed(context, table_idx)
}

///|
fn context_table_size(context : JITContext, table_idx : Int) -> Int {
  c_jit_ctx_get_table_size_managed(context, table_idx)
}

///|
pub fn NativeJITContext::set_memory(
  self : NativeJITContext,
  mem0_ptr : Int64,
) -> Unit {
  c_jit_ctx_set_memory_managed(self.handle, mem0_ptr)
}

///|
pub fn NativeJITContext::alloc_guarded_memory(
  self : NativeJITContext,
  initial_pages : Int,
  max_pages : Int?,
) -> Int64 {
  c_jit_ctx_alloc_guarded_memory_managed(
    self.handle,
    initial_pages.to_int64(),
    max_pages.unwrap_or(-1).to_int64(),
  )
}

///|
pub fn NativeJITContext::func_ptr(
  self : NativeJITContext,
  func_idx : Int,
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
) -> Unit {
  self.jit_tables.clear()
  for jit_table in jit_tables {
    self.jit_tables.push(jit_table)
  }
  if jit_tables.is_empty() {
    return
  }
  let table_ptrs = FixedArray::make(jit_tables.length(), 0L)
  let table_sizes = FixedArray::make(jit_tables.length(), 0)
  let table_max_sizes = FixedArray::make(jit_tables.length(), -1)
  for i, jit_table_opt in jit_tables {
    match jit_table_opt {
      Some(jit_table) => {
        table_ptrs[i] = jit_table.raw_ptr()
        table_sizes[i] = jit_table.get_size()
        table_max_sizes[i] = jit_table.get_max().unwrap_or(-1)
      }
      None => ()
    }
  }
  c_jit_ctx_set_table_pointers_managed(
    self.handle,
    table_ptrs,
    table_sizes,
    table_max_sizes,
    jit_tables.length(),
  )
}

///|
/// Refresh one borrowed table from the context it was registered with.
/// The context supplies both the table identity and its live C-side layout.
pub fn NativeJITContext::refresh_table_layout(
  self : NativeJITContext,
  table_idx : Int,
) -> Bool {
  if table_idx < 0 || table_idx >= self.jit_tables.length() {
    return false
  }
  guard self.jit_tables[table_idx] is Some(jit_table) else { return false }
  let table_ptr = context_table_ptr(self.handle, table_idx)
  let size = context_table_size(self.handle, table_idx)
  if table_ptr == 0L || size < 0 {
    return false
  }
  jit_table.refresh_layout(table_ptr, size)
  true
}

///|
pub fn NativeJITContext::set_memory_pointers(
  self : NativeJITContext,
  memories : Array[MemoryInfo],
) -> Unit {
  if memories.is_empty() {
    return
  }
  let ptrs = FixedArray::make(memories.length(), 0L)
  for i, mem in memories {
    ptrs[i] = mem.ptr
  }
  c_jit_ctx_set_memory_pointers_managed(self.handle, ptrs, memories.length())
}

///|
pub fn NativeJITContext::memory_ptr(
  self : NativeJITContext,
  memidx : Int,
) -> Int64 {
  c_jit_ctx_get_memory_ptr_managed(self.handle, memidx)
}

///|
pub fn NativeJITContext::memory_size(
  self : NativeJITContext,
  memidx : Int,
) -> Int64 {
  c_jit_ctx_get_memory_size_managed(self.handle, memidx)
}

///|
/// Memory information for JIT execution.
pub struct MemoryInfo {
  ptr : Int64 // Pointer to `wasmoon_memory_t` (memory descriptor)
  size : Int64 // Initial size in bytes (informational)
  max_pages : Int? // Max pages (None = unlimited)
}

///|
/// Create a new MemoryInfo.
pub fn MemoryInfo::MemoryInfo(
  ptr : Int64,
  size : Int64,
  max_pages : Int?,
) -> MemoryInfo {
  { ptr, size, max_pages }
}

///|
/// Allocate linear memory for WASM (returns 0 on failure).
pub fn alloc_memory(size : Int64) -> Int64 {
  c_jit_alloc_memory(size)
}

///|
/// Allocate a `wasmoon_memory_t` descriptor with owned backing memory.
pub fn alloc_memory_desc(
  size_bytes : Int64,
  max_pages : Int?,
  is_memory64? : Bool = false,
  page_size_log2? : Int = 16,
  is_shared? : Bool = false,
) -> Int64 {
  c_jit_alloc_memory_desc(
    size_bytes,
    max_pages.unwrap_or(-1),
    if is_memory64 {
      1
    } else {
      0
    },
    page_size_log2,
    if is_shared {
      1
    } else {
      0
    },
  )
}

///|
/// Allocate a guarded (reserved) memory descriptor for memory32 memory0.
/// This is required for bounds-check elimination; out-of-bounds accesses trap via guard pages.
pub fn alloc_guarded_memory_desc(
  initial_pages : Int,
  max_pages : Int?,
) -> Int64 {
  c_jit_alloc_guarded_memory_desc(
    initial_pages.to_int64(),
    max_pages.unwrap_or(-1).to_int64(),
  )
}

///|
pub fn free_memory(mem_ptr : Int64) -> Unit {
  c_jit_free_memory(mem_ptr)
}

///|
pub fn free_memory_desc(mem_desc_ptr : Int64) -> Unit {
  c_jit_free_memory_desc(mem_desc_ptr)
}

///|
/// Initialize memory with data at offset.
pub fn memory_init(mem_ptr : Int64, offset : Int64, data : Bytes) -> Bool {
  let size = data.length()
  if size == 0 {
    return true
  }
  c_jit_memory_init_bytes(mem_ptr, offset, data, size) == 0
}

///|
/// Read `size` bytes from linear memory at offset.
pub fn memory_read(mem_ptr : Int64, offset : Int64, size : Int) -> Bytes {
  if mem_ptr == 0L || size <= 0 {
    return b""
  }
  let out = FixedArray::make(size, b'\x00')
  let rc = c_jit_memory_read(mem_ptr, offset, out, size)
  if rc != 0 {
    return b""
  }
  let arr : Array[Byte] = Array::make(size, b'\x00')
  for i in 0..<size {
    arr[i] = out[i]
  }
  Bytes::from_array(arr)
}

///|
/// Shared indirect table that can be used by multiple JIT modules.
struct JITTable {
  mut table_ptr : Int64 // Pointer to the shared C-side table
  mut size : Int
  max : Int?
} derive(Debug)

///|
/// Destruction capability for one shared JIT table allocation.
struct JITTableOwner {
  table : JITTable
} derive(Debug)

///|
/// Create a new owned shared JIT table.
/// Note: size 0 is valid (empty table that can grow later).
pub fn JITTableOwner::try_alloc(size : Int, max : Int?) -> JITTableOwner? {
  if size < 0 {
    return None
  }
  let alloc_size = if size == 0 { 1 } else { size }
  let table_ptr = c_jit_alloc_shared_indirect_table(alloc_size)
  if table_ptr == 0L {
    return None
  }
  Some({ table: { table_ptr, size, max } })
}

///|
/// Borrow the table without transferring its destruction capability.
pub fn JITTableOwner::table(self : JITTableOwner) -> JITTable {
  self.table
}

///|
/// Release the owned shared table allocation. Repeated close calls are harmless.
pub fn JITTableOwner::close(self : JITTableOwner) -> Unit {
  if self.table.table_ptr != 0L {
    c_jit_free_shared_indirect_table(self.table.table_ptr)
    self.table.table_ptr = 0L
    self.table.size = 0
  }
}

///|
/// Set an entry in the shared table.
pub fn JITTable::set(
  self : JITTable,
  table_idx : Int,
  func_ptr : Int64,
  type_hash : Int,
) -> Unit {
  if table_idx < 0 || table_idx >= self.size {
    return
  }
  c_jit_shared_table_set(self.table_ptr, table_idx, func_ptr, type_hash)
}

///|
/// Read raw entry value bits from the shared table.
pub fn JITTable::get_entry_value(self : JITTable, table_idx : Int) -> Int64 {
  if table_idx < 0 || table_idx >= self.size {
    return 0L
  }
  c_jit_read_i64(self.table_ptr + (table_idx * 16).to_int64())
}

///|
/// Read raw entry type index from the shared table.
pub fn JITTable::get_entry_type(self : JITTable, table_idx : Int) -> Int {
  if table_idx < 0 || table_idx >= self.size {
    return -1
  }
  c_jit_read_i64(self.table_ptr + (table_idx * 16 + 8).to_int64()).to_int()
}

///|
/// Get the table size.
pub fn JITTable::get_size(self : JITTable) -> Int {
  self.size
}

///|
/// Get the raw shared table pointer.
pub fn JITTable::raw_ptr(self : JITTable) -> Int64 {
  self.table_ptr
}

///|
/// Refresh table pointer and size from its registered JIT context view.
fn JITTable::refresh_layout(
  self : JITTable,
  table_ptr : Int64,
  size : Int,
) -> Unit {
  if table_ptr == 0L || size < 0 {
    return
  }
  self.table_ptr = table_ptr
  self.size = size
}

///|
/// Get the table max size.
pub fn JITTable::get_max(self : JITTable) -> Int? {
  self.max
}
