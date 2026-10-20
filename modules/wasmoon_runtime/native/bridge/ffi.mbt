///|
/// Allocate a new array from existing values
/// Returns gc_ref (1-based index), or 0 on failure
///
/// `values` is a flat run of [lo, hi] word pairs, two entries per element.
#borrow(values, heap)
extern "c" fn c_gc_heap_alloc_array_from_slots(
  heap : GCHeapHandle,
  type_idx : Int32,
  values : FixedArray[Int64],
  len : Int32,
) -> Int32 = "wasmoon_gc_heap_alloc_array_from_slots"

///|
/// Allocate a new array
/// Returns gc_ref (1-based index), or 0 on failure
#borrow(heap)
extern "c" fn c_gc_heap_alloc_array_wide(
  heap : GCHeapHandle,
  type_idx : Int32,
  len : Int32,
  lo : Int64,
  hi : Int64,
) -> Int32 = "wasmoon_gc_heap_alloc_array_wide"

///|
/// Allocate a new struct
/// Returns gc_ref (1-based index), or 0 on failure
///
/// `fields` is a flat run of [lo, hi] word pairs, two entries per field. The
/// narrow `wasmoon_gc_heap_alloc_struct` next to it in C is for JIT-emitted
/// code, which only ever produces runtime words; MoonBit always goes wide so
/// that a v128 field never has to be squeezed into one word.
#borrow(fields, heap)
extern "c" fn c_gc_heap_alloc_struct_wide(
  heap : GCHeapHandle,
  type_idx : Int32,
  fields : FixedArray[Int64],
  num_fields : Int32,
) -> Int32 = "wasmoon_gc_heap_alloc_struct_wide"

///|
/// Copy array elements
#borrow(heap)
extern "c" fn c_gc_heap_array_copy(
  heap : GCHeapHandle,
  dst_ref : Int32,
  dst_offset : Int32,
  src_ref : Int32,
  src_offset : Int32,
  count : Int32,
) -> Unit = "wasmoon_gc_heap_array_copy"

// ============ Type Information ============

///|
/// Fill array elements with a value
#borrow(heap)
extern "c" fn c_gc_heap_array_fill_wide(
  heap : GCHeapHandle,
  gc_ref : Int32,
  offset : Int32,
  lo : Int64,
  hi : Int64,
  count : Int32,
) -> Unit = "wasmoon_gc_heap_array_fill_wide"

///|
/// Read an array element into `out` as [lo, hi]
#borrow(out, heap)
extern "c" fn c_gc_heap_array_get_wide(
  heap : GCHeapHandle,
  gc_ref : Int32,
  idx : Int32,
  out : FixedArray[Int64],
) -> Unit = "wasmoon_gc_heap_array_get_wide"

///|
/// Get array length
#borrow(heap)
extern "c" fn c_gc_heap_array_len(heap : GCHeapHandle, gc_ref : Int32) -> Int32 = "wasmoon_gc_heap_array_len"

///|
/// Set an array element
#borrow(heap)
extern "c" fn c_gc_heap_array_set_wide(
  heap : GCHeapHandle,
  gc_ref : Int32,
  idx : Int32,
  lo : Int64,
  hi : Int64,
) -> Unit = "wasmoon_gc_heap_array_set_wide"

///|
/// Perform a full GC cycle (mark + sweep)
/// Returns number of objects collected
#borrow(roots, heap)
extern "c" fn c_gc_heap_collect(
  heap : GCHeapHandle,
  roots : FixedArray[Int64],
  num_roots : Int32,
) -> Int32 = "wasmoon_jit_collect_heap"

///|
/// Configure allocation fault injection:
/// - fail_at > 0: fail exactly on Nth allocation attempt
/// - fail_every > 0: fail on every Kth allocation attempt
extern "c" fn c_gc_heap_debug_set_fail_alloc(
  fail_at : Int32,
  fail_every : Int32,
) -> Unit = "wasmoon_gc_heap_debug_set_fail_alloc"

// ============ JIT Utilities ============

///|
/// Get total number of write-barrier calls recorded
#borrow(heap)
extern "c" fn c_gc_heap_get_barrier_writes(heap : GCHeapHandle) -> Int32 = "wasmoon_gc_heap_get_barrier_writes"

///|
/// Get heap base pointer (for JIT inline access)
#borrow(heap)
extern "c" fn c_gc_heap_get_base(heap : GCHeapHandle) -> Int64 = "wasmoon_gc_heap_get_base"

///|
/// Get heap capacity (total allocated bytes)
#borrow(heap)
extern "c" fn c_gc_heap_get_capacity(heap : GCHeapHandle) -> Int64 = "wasmoon_gc_heap_get_capacity"

///|
/// Get the kind of an object (1=struct, 2=array)
#borrow(heap)
extern "c" fn c_gc_heap_get_kind(heap : GCHeapHandle, gc_ref : Int32) -> Int32 = "wasmoon_gc_heap_get_kind"

///|
/// Get number of objects in heap
#borrow(heap)
extern "c" fn c_gc_heap_get_object_count(heap : GCHeapHandle) -> Int32 = "wasmoon_gc_heap_get_object_count"

///|
/// Get object offset in heap (for JIT inline access)
#borrow(heap)
extern "c" fn c_gc_heap_get_offset(
  heap : GCHeapHandle,
  gc_ref : Int32,
) -> Int32 = "wasmoon_gc_heap_get_offset"

///|
/// Get current heap size (bytes used)
#borrow(heap)
extern "c" fn c_gc_heap_get_size(heap : GCHeapHandle) -> Int64 = "wasmoon_gc_heap_get_size"

///|
/// Get total number of allocations since heap creation
#borrow(heap)
extern "c" fn c_gc_heap_get_total_allocations(heap : GCHeapHandle) -> Int32 = "wasmoon_gc_heap_get_total_allocations"

///|
/// Get total number of GC cycles performed
#borrow(heap)
extern "c" fn c_gc_heap_get_total_collections(heap : GCHeapHandle) -> Int32 = "wasmoon_gc_heap_get_total_collections"

// ============ Exception Handling ============

///|
/// Get the type index of an object
#borrow(heap)
extern "c" fn c_gc_heap_get_type_idx(
  heap : GCHeapHandle,
  gc_ref : Int32,
) -> Int32 = "wasmoon_gc_heap_get_type_idx"

///|
/// Check if a gc_ref is valid (non-null and within bounds)
#borrow(heap)
extern "c" fn c_gc_heap_is_valid(heap : GCHeapHandle, gc_ref : Int32) -> Int32 = "wasmoon_gc_heap_is_valid"

// ============ GC Operations ============

///|
/// Discard unreachable objects allocated after the supplied object-table boundary.
#borrow(roots, heap)
extern "c" fn c_gc_heap_rollback_allocations(
  heap : GCHeapHandle,
  object_count : Int32,
  roots : FixedArray[Int64],
  num_roots : Int32,
) -> Int32 = "wasmoon_gc_heap_rollback_allocations"

///|
/// Read a struct field into `out` as [lo, hi]
#borrow(out, heap)
extern "c" fn c_gc_heap_struct_get_wide(
  heap : GCHeapHandle,
  gc_ref : Int32,
  field_idx : Int32,
  out : FixedArray[Int64],
) -> Unit = "wasmoon_gc_heap_struct_get_wide"

///|
/// Set a struct field value
#borrow(heap)
extern "c" fn c_gc_heap_struct_set_wide(
  heap : GCHeapHandle,
  gc_ref : Int32,
  field_idx : Int32,
  lo : Int64,
  hi : Int64,
) -> Unit = "wasmoon_gc_heap_struct_set_wide"

// ============ Array Operations ============

///|
/// Verify C heap invariants (returns 1 when valid, 0 on failure)
#borrow(heap)
extern "c" fn c_gc_heap_verify(heap : GCHeapHandle, verbose : Int32) -> Int32 = "wasmoon_gc_heap_verify"

///|
/// Allocate guarded memory into a standalone descriptor.
/// Returns: `wasmoon_memory_t*` on success, 0 on failure.
extern "c" fn c_jit_alloc_guarded_memory_desc(
  initial_pages : Int64,
  max_pages : Int64,
  is_shared : Int32,
) -> MemoryDescriptor = "wasmoon_jit_alloc_guarded_memory_desc"

///|
/// Allocate linear memory for generic buffers (globals, etc.)
extern "c" fn c_jit_alloc_memory(size : Int64) -> Int64 = "wasmoon_jit_alloc_memory"

///|
/// Allocate a `wasmoon_memory_t` descriptor with an owned backing allocation.
/// max_pages is interpreted by the runtime; -1 means "unknown/unlimited".
extern "c" fn c_jit_alloc_memory_desc(
  size_bytes : Int64,
  max_pages : Int64,
  is_memory64 : Int32,
  page_size_log2 : Int32,
  is_shared : Int32,
) -> MemoryDescriptor = "wasmoon_jit_alloc_memory_desc"

///|
/// Allocate a shared indirect table that can be used by multiple JIT modules
extern "c" fn c_jit_alloc_shared_indirect_table(
  count : Int32,
) -> NativeTableHandle = "wasmoon_jit_alloc_shared_indirect_table"

///|
/// Free linear memory
extern "c" fn c_jit_free_memory(mem_ptr : Int64) -> Unit = "wasmoon_jit_free_memory"

///|
/// Set an entry in a shared indirect table
#borrow(table_ptr)
extern "c" fn c_jit_shared_table_set(
  table_ptr : NativeTableHandle,
  table_idx : Int32,
  func_ptr : Int64,
  type_hash : Int32,
) -> Unit = "wasmoon_jit_shared_table_set"

///|
/// Get current length in bytes from a `wasmoon_memory_t` descriptor.
#borrow(mem_desc_ptr)
extern "c" fn c_mem_desc_get_len(mem_desc_ptr : MemoryDescriptor) -> Int64 = "wasmoon_mem_desc_get_len"

///|
/// Grow a `wasmoon_memory_t` descriptor by `delta_pages`.
/// Returns old size in pages on success, or -1 on failure.
#borrow(mem_desc_ptr)
extern "c" fn c_mem_desc_grow(
  mem_desc_ptr : MemoryDescriptor,
  delta_pages : Int64,
  max_pages : Int32,
) -> Int64 = "wasmoon_mem_desc_grow"

///|
/// memmove within the same memory descriptor.
#borrow(mem_desc_ptr)
extern "c" fn c_mem_desc_memmove(
  mem_desc_ptr : MemoryDescriptor,
  dst : Int64,
  src : Int64,
  size : Int32,
) -> Int32 = "wasmoon_mem_desc_memmove"

///|
/// memset within the same memory descriptor.
#borrow(mem_desc_ptr)
extern "c" fn c_mem_desc_memset(
  mem_desc_ptr : MemoryDescriptor,
  dst : Int64,
  val : Int32,
  size : Int32,
) -> Int32 = "wasmoon_mem_desc_memset"

///|
/// Copy bytes from memory descriptor at offset into `out`.
#borrow(out, mem_desc_ptr)
extern "c" fn c_mem_desc_read(
  mem_desc_ptr : MemoryDescriptor,
  offset : Int64,
  out : FixedArray[Byte],
  size : Int32,
) -> Int32 = "wasmoon_mem_desc_read"

///|
/// Copy bytes from `data` into memory descriptor at offset.
#borrow(data, mem_desc_ptr)
extern "c" fn c_mem_desc_write(
  mem_desc_ptr : MemoryDescriptor,
  offset : Int64,
  data : FixedArray[Byte],
  size : Int32,
) -> Int32 = "wasmoon_mem_desc_write"

///|
/// Copy bytes from `data` into memory descriptor at offset (Bytes fast path).
#borrow(data, mem_desc_ptr)
extern "c" fn c_mem_desc_write_bytes(
  mem_desc_ptr : MemoryDescriptor,
  offset : Int64,
  data : Bytes,
  size : Int32,
) -> Int32 = "wasmoon_mem_desc_write_bytes"
