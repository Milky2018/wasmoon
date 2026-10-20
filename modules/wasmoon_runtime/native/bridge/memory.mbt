///|
pub using @jit_ffi {type MemoryDescriptor}

/// Linear-memory and indirect-table support for managed native JIT contexts.

///|
pub fn memory_descriptor_length(mem_desc_ptr : MemoryDescriptor) -> Int64 {
  c_mem_desc_get_len(mem_desc_ptr)
}

///|
pub fn memory_descriptor_grow(
  mem_desc_ptr : MemoryDescriptor,
  delta_pages : Int32,
  max_pages : Int32,
) -> Int32 {
  c_mem_desc_grow(mem_desc_ptr, delta_pages.to_int64(), max_pages).to_int()
}

///|
/// Return 0 on success, -1 for an invalid descriptor, memory range or destination
/// buffer length. Rejected operations leave the destination unchanged.
#borrow(out)
pub fn memory_descriptor_read(
  mem_desc_ptr : MemoryDescriptor,
  offset : Int64,
  out : FixedArray[Byte],
  size : Int32,
) -> Int32 {
  if size < 0 || size > out.length() {
    return -1
  }
  c_mem_desc_read(mem_desc_ptr, offset, out, size)
}

///|
/// Return 0 on success, -1 for an invalid descriptor, memory range or source
/// buffer length. Rejected operations leave the destination unchanged.
#borrow(data)
pub fn memory_descriptor_write(
  mem_desc_ptr : MemoryDescriptor,
  offset : Int64,
  data : FixedArray[Byte],
  size : Int32,
) -> Int32 {
  if size < 0 || size > data.length() {
    return -1
  }
  c_mem_desc_write(mem_desc_ptr, offset, data, size)
}

///|
/// Return 0 on success, -1 for an invalid descriptor, memory range or source
/// buffer length. Rejected operations leave the destination unchanged.
/// Return 0 on success, -1 for an invalid descriptor, memory range or source
/// buffer length. Rejected operations leave the destination unchanged.
#borrow(data)
pub fn memory_descriptor_write_bytes(
  mem_desc_ptr : MemoryDescriptor,
  offset : Int64,
  data : Bytes,
  size : Int32,
) -> Int32 {
  if size < 0 || size > data.length() {
    return -1
  }
  c_mem_desc_write_bytes(mem_desc_ptr, offset, data, size)
}

///|
pub fn memory_descriptor_move(
  mem_desc_ptr : MemoryDescriptor,
  destination : Int64,
  source : Int64,
  size : Int32,
) -> Int32 {
  c_mem_desc_memmove(mem_desc_ptr, destination, source, size)
}

///|
pub fn memory_descriptor_fill(
  mem_desc_ptr : MemoryDescriptor,
  destination : Int64,
  value : Int32,
  size : Int32,
) -> Int32 {
  c_mem_desc_memset(mem_desc_ptr, destination, value, size)
}

///|
/// Memory information for JIT execution.
pub struct MemoryInfo {
  ptr : MemoryDescriptor // Pointer to `wasmoon_memory_t` (memory descriptor)
  size : Int64 // Initial size in bytes (informational)
  max_pages : Int32? // Max pages (None = unlimited)
}

///|
/// Create a new MemoryInfo.
pub fn MemoryInfo::MemoryInfo(
  ptr : MemoryDescriptor,
  size : Int64,
  max_pages : Int32?,
) -> MemoryInfo {
  { ptr, size, max_pages, }
}

///|
/// Allocate unmanaged storage for native ABI fixtures (returns 0 on failure).
/// The caller owns its bounds and must free it exactly once. Use descriptors
/// for linear-memory access through checked operations.
pub fn alloc_memory(size : Int64) -> Int64 {
  c_jit_alloc_memory(size)
}

///|
/// Allocate a `wasmoon_memory_t` descriptor with owned backing memory.
pub fn alloc_memory_desc(
  size_bytes : Int64,
  max_pages : Int64?,
  is_memory64~ : Bool = false,
  page_size_log2~ : Int32 = 16,
  is_shared~ : Bool = false,
) -> MemoryDescriptor {
  c_jit_alloc_memory_desc(
    size_bytes,
    match max_pages {
      Some(max) => max
      None => -1L
    },
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
  initial_pages : Int32,
  max_pages : Int32?,
  is_shared~ : Bool = false,
) -> MemoryDescriptor {
  c_jit_alloc_guarded_memory_desc(
    initial_pages.to_int64(),
    max_pages.unwrap_or(-1).to_int64(),
    if is_shared {
      1
    } else {
      0
    },
  )
}

///|
/// Release an unmanaged allocation returned by alloc_memory. The caller must
/// ensure no aliases remain and must not pass a descriptor backing address.
pub fn free_memory(mem_ptr : Int64) -> Unit {
  c_jit_free_memory(mem_ptr)
}

///|
pub using @jit_ffi {type NativeTableHandle}

///|
#borrow(table)
extern "c" fn table_entry_word(
  table : NativeTableHandle,
  index : Int32,
  word : Int32,
) -> Int64 = "wasmoon_native_table_entry_word"

///|
/// Shared indirect table that can be used by multiple JIT modules.
struct JITTable {
  mut table_ptr : NativeTableHandle // Pointer to the shared C-side table
  max : Int64?
} derive(Debug)

///|
/// Logical close capability for one shared JIT table view.
struct JITTableOwner {
  table : JITTable
} derive(Debug)

///|
/// Create a new owned shared JIT table.
/// Note: size 0 is valid (empty table that can grow later).
pub fn JITTableOwner::try_alloc(size : Int32, max : Int64?) -> JITTableOwner? {
  if size < 0 {
    return None
  }
  let table_ptr = c_jit_alloc_shared_indirect_table(size)
  if table_ptr.is_null() {
    return None
  }
  Some({ table: { table_ptr, max, }, })
}

///|
/// Borrow the table without transferring its destruction capability.
pub fn JITTableOwner::table(self : JITTableOwner) -> JITTable {
  self.table
}

///|
/// Close all aliases of this view and release its reference. Context bindings
/// and independently retained handles remain live. Repeated close is harmless.
pub fn JITTableOwner::close(self : JITTableOwner) -> Unit {
  if !self.table.table_ptr.is_null() {
    self.table.table_ptr = NativeTableHandle::null()
  }
}

///|
/// Set an entry in the shared table.
pub fn JITTable::set(
  self : JITTable,
  table_idx : Int32,
  func_ptr : Int64,
  type_hash : Int32,
) -> Unit {
  if table_idx < 0 || table_idx >= self.get_size() {
    return
  }
  c_jit_shared_table_set(self.table_ptr, table_idx, func_ptr, type_hash)
}

///|
/// Read raw entry value bits from the shared table.
pub fn JITTable::get_entry_value(self : JITTable, table_idx : Int32) -> Int64 {
  if table_idx < 0 || table_idx >= self.get_size() {
    return 0L
  }
  table_entry_word(self.table_ptr, table_idx, 0)
}

///|
/// Read raw entry type index from the shared table.
pub fn JITTable::get_entry_type(self : JITTable, table_idx : Int32) -> Int32 {
  if table_idx < 0 || table_idx >= self.get_size() {
    return -1
  }
  table_entry_word(self.table_ptr, table_idx, 1).to_int()
}

///|
/// Get the table size.
pub fn JITTable::get_size(self : JITTable) -> Int32 {
  self.table_ptr.size()
}

///|
/// Retain the stable managed table descriptor.
pub fn JITTable::raw_ptr(self : JITTable) -> NativeTableHandle {
  self.table_ptr
}

///|
/// Refresh table pointer and size from its registered JIT context view.
pub fn JITTable::refresh_layout(
  self : JITTable,
  table_ptr : NativeTableHandle,
  size : Int32,
) -> Unit {
  if self.table_ptr.is_null() || table_ptr.is_null() || size < 0 {
    return
  }
  self.table_ptr = table_ptr
}

///|
/// Get the table max size.
pub fn JITTable::get_max(self : JITTable) -> Int64? {
  self.max
}

///|
/// Copy checked byte ranges between live memory descriptors.
pub fn memory_descriptor_copy(
  destination_memory : MemoryDescriptor,
  destination : Int64,
  source_memory : MemoryDescriptor,
  source : Int64,
  length : Int64,
) -> Int32 {
  c_memory_descriptor_copy(
    destination_memory, destination, source_memory, source, length,
  )
}

///|
#borrow(destination_memory, source_memory)
extern "c" fn c_memory_descriptor_copy(
  destination_memory : MemoryDescriptor,
  destination : Int64,
  source_memory : MemoryDescriptor,
  source : Int64,
  length : Int64,
) -> Int32 = "wasmoon_mem_desc_copy64"

///|
/// Fill a checked byte range of a live memory descriptor.
pub fn memory_descriptor_fill64(
  memory : MemoryDescriptor,
  destination : Int64,
  value : Int32,
  length : Int64,
) -> Int32 {
  c_memory_descriptor_fill64(memory, destination, value, length)
}

///|
#borrow(memory)
extern "c" fn c_memory_descriptor_fill64(
  memory : MemoryDescriptor,
  destination : Int64,
  value : Int32,
  length : Int64,
) -> Int32 = "wasmoon_mem_desc_memset64"

///|
pub fn memory_descriptor_grow64(
  mem_desc_ptr : MemoryDescriptor,
  delta_pages : Int64,
) -> Int64 {
  c_mem_desc_grow(mem_desc_ptr, delta_pages, -1)
}

///|
/// Retain a checked native table view without exposing its internal fields.
pub fn borrow_table(pointer : NativeTableHandle, max : Int64?) -> JITTable {
  { table_ptr: pointer, max, }
}
