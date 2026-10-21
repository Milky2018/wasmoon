///|
/// C Heap wrapper for GC objects
/// This wraps the C-managed GC heap that can be used by both
/// the interpreter and JIT-compiled code.

// ============================================================
// Error Types
// ============================================================

///|
/// CHeap error types for runtime errors
pub(all) suberror CHeapError {
  OutOfBoundsArrayAccess
  NullReference
  OutOfMemory
}

// ============================================================
// Value Encoding Constants
// ============================================================

// Object kinds (must match GC_KIND_* in gc_heap.h)

///|
const GC_KIND_STRUCT : Int32 = 1

///|
const GC_KIND_ARRAY : Int32 = 2

///|
/// Managed GC heap handle. Copies retain the heap independently of its owner.
pub using @jit_ffi {type GCHeapHandle}

///|
/// Logical owner of a shared managed GC heap.
pub struct CHeap {
  priv mut ptr : GCHeapHandle
} derive(Debug)

///|
/// Create a new C heap with the given initial capacity
pub fn CHeap::CHeap(
  capacity~ : Int32 = @types.ONE_MIB_BYTES,
) -> CHeap raise CHeapError {
  let ptr = GCHeapHandle::new(capacity.to_int64())
  guard !ptr.is_null() else { raise OutOfMemory }
  { ptr, }
}

///|
/// Close this owner. Other managed handles, contexts and root leases stay live.
pub fn CHeap::free(self : CHeap) -> Unit {
  self.ptr.clear_root_visitor()
  self.ptr = GCHeapHandle::null()
}

///|
/// Retain the managed C heap for JIT or exception use.
pub fn CHeap::get_ptr(self : CHeap) -> GCHeapHandle {
  self.ptr
}

///|
/// Return an owner-bound action that reclaims later allocations unless they
/// remain reachable when the action runs. Retained object-table indices are
/// never reused.
pub fn CHeap::make_allocation_rollback(
  self : CHeap,
  roots : () -> Array[@types.Value],
) -> () -> Unit {
  let object_count = self.get_object_count()
  fn() {
    let current_roots = roots()
    let num_roots = current_roots.length()
    let raw_roots = FixedArray::makei(num_roots, fn(i) {
      value_to_i64(current_roots[i])
    })
    c_gc_heap_rollback_allocations(self.ptr, object_count, raw_roots, num_roots)
    |> ignore
  }
}

// ============================================================
// Value Encoding/Decoding
// ============================================================

///|
/// Flatten values into the [lo, hi] word pairs the wide C entry points take.
fn slots_to_words(values : Array[@types.Value]) -> FixedArray[Int64] {
  FixedArray::makei(values.length() * 2, fn(i) {
    let slot = value_to_slot(values[i / 2])
    if i % 2 == 0 {
      slot.lo
    } else {
      slot.hi
    }
  })
}

// ============================================================
// Struct Operations
// ============================================================

///|
/// Allocate a new struct
/// Returns gc_ref (0-based index for external use)
pub fn CHeap::alloc_struct(
  self : CHeap,
  type_idx : Int32,
  fields : Array[@types.Value],
  runtime_type~ : Int32 = -1,
) -> Int32 raise CHeapError {
  let num_fields = fields.length()
  let raw_fields = slots_to_words(fields)
  let gc_ref = if runtime_type >= 0 {
    self.ptr.allocate_typed(
      runtime_type, type_idx, raw_fields, num_fields, false,
    )
  } else {
    c_gc_heap_alloc_struct_wide(self.ptr, type_idx, raw_fields, num_fields)
  }
  if gc_ref <= 0 {
    raise OutOfMemory
  }
  // C heap returns 1-based gc_ref, convert to 0-based for external use
  gc_ref - 1
}

///|
/// Get a struct field value
pub fn CHeap::struct_get(
  self : CHeap,
  struct_idx : Int32,
  field_idx : Int32,
  field_type : @types.ValueType,
) -> @types.Value {
  // Convert 0-based to 1-based for C heap
  let gc_ref = struct_idx + 1
  let out = FixedArray::make(2, 0L)
  c_gc_heap_struct_get_wide(self.ptr, gc_ref, field_idx, out)
  slot_to_value({ lo: out[0], hi: out[1], }, field_type)
}

///|
/// Set a struct field value
pub fn CHeap::struct_set(
  self : CHeap,
  struct_idx : Int32,
  field_idx : Int32,
  value : @types.Value,
) -> Unit {
  let gc_ref = struct_idx + 1
  let slot = value_to_slot(value)
  c_gc_heap_struct_set_wide(self.ptr, gc_ref, field_idx, slot.lo, slot.hi)
}

// ============================================================
// Array Operations
// ============================================================

///|
/// Allocate a new array with initial value
/// Returns gc_ref (0-based index for external use)
pub fn CHeap::alloc_array(
  self : CHeap,
  type_idx : Int32,
  len : Int32,
  init_value : @types.Value,
  runtime_type~ : Int32 = -1,
) -> Int32 raise CHeapError {
  let slot = value_to_slot(init_value)
  let gc_ref = if runtime_type >= 0 {
    self.ptr.allocate_typed(
      runtime_type,
      type_idx,
      [slot.lo, slot.hi],
      len,
      true,
    )
  } else {
    c_gc_heap_alloc_array_wide(self.ptr, type_idx, len, slot.lo, slot.hi)
  }
  if gc_ref <= 0 {
    raise OutOfMemory
  }
  gc_ref - 1
}

///|
/// Allocate a new array from existing values
/// Returns gc_ref (0-based index for external use)
pub fn CHeap::alloc_array_from_values(
  self : CHeap,
  type_idx : Int32,
  elements : Array[@types.Value],
  runtime_type~ : Int32 = -1,
) -> Int32 raise CHeapError {
  let len = elements.length()
  let raw_values = slots_to_words(elements)
  let gc_ref = if runtime_type >= 0 {
    self.ptr.allocate_typed(runtime_type, type_idx, raw_values, len, false)
  } else {
    c_gc_heap_alloc_array_from_slots(self.ptr, type_idx, raw_values, len)
  }
  if gc_ref <= 0 {
    raise OutOfMemory
  }
  gc_ref - 1
}

///|
/// Get array length
pub fn CHeap::array_len(self : CHeap, array_idx : Int32) -> Int32 {
  let gc_ref = array_idx + 1
  c_gc_heap_array_len(self.ptr, gc_ref)
}

///|
/// Get an array element
pub fn CHeap::array_get(
  self : CHeap,
  array_idx : Int32,
  elem_idx : Int32,
  elem_type : @types.ValueType,
) -> @types.Value raise CHeapError {
  let gc_ref = array_idx + 1
  // Check bounds before accessing
  let len = c_gc_heap_array_len(self.ptr, gc_ref)
  if elem_idx < 0 || elem_idx >= len {
    raise OutOfBoundsArrayAccess
  }
  let out = FixedArray::make(2, 0L)
  c_gc_heap_array_get_wide(self.ptr, gc_ref, elem_idx, out)
  slot_to_value({ lo: out[0], hi: out[1], }, elem_type)
}

///|
/// Set an array element
pub fn CHeap::array_set(
  self : CHeap,
  array_idx : Int32,
  elem_idx : Int32,
  value : @types.Value,
) -> Unit raise CHeapError {
  let gc_ref = array_idx + 1
  // Check bounds before accessing
  let len = c_gc_heap_array_len(self.ptr, gc_ref)
  if elem_idx < 0 || elem_idx >= len {
    raise OutOfBoundsArrayAccess
  }
  let slot = value_to_slot(value)
  c_gc_heap_array_set_wide(self.ptr, gc_ref, elem_idx, slot.lo, slot.hi)
}

///|
/// Fill array elements with a value
pub fn CHeap::array_fill(
  self : CHeap,
  array_idx : Int32,
  offset : Int32,
  value : @types.Value,
  count : Int32,
) -> Unit raise CHeapError {
  let gc_ref = array_idx + 1
  // Check bounds before filling
  let len = c_gc_heap_array_len(self.ptr, gc_ref)
  if offset < 0 || count < 0 || offset + count > len {
    raise OutOfBoundsArrayAccess
  }
  let slot = value_to_slot(value)
  c_gc_heap_array_fill_wide(self.ptr, gc_ref, offset, slot.lo, slot.hi, count)
}

///|
/// Copy array elements
pub fn CHeap::array_copy(
  self : CHeap,
  dst_idx : Int32,
  dst_offset : Int32,
  src_idx : Int32,
  src_offset : Int32,
  count : Int32,
) -> Unit raise CHeapError {
  let dst_ref = dst_idx + 1
  let src_ref = src_idx + 1
  // Check bounds before copying
  let dst_len = c_gc_heap_array_len(self.ptr, dst_ref)
  let src_len = c_gc_heap_array_len(self.ptr, src_ref)
  if dst_offset < 0 ||
    src_offset < 0 ||
    count < 0 ||
    dst_offset + count > dst_len ||
    src_offset + count > src_len {
    raise OutOfBoundsArrayAccess
  }
  c_gc_heap_array_copy(
    self.ptr,
    dst_ref,
    dst_offset,
    src_ref,
    src_offset,
    count,
  )
}

// ============================================================
// Type Information
// ============================================================

///|
/// Get the type index of an object
pub fn CHeap::get_type_idx(self : CHeap, idx : Int32) -> Int32 {
  let gc_ref = idx + 1
  c_gc_heap_get_type_idx(self.ptr, gc_ref)
}

///|
/// Get the kind of an object (1=struct, 2=array)
pub fn CHeap::get_kind(self : CHeap, idx : Int32) -> Int32 {
  let gc_ref = idx + 1
  c_gc_heap_get_kind(self.ptr, gc_ref)
}

///|
/// Check if this is a struct
pub fn CHeap::is_struct(self : CHeap, idx : Int32) -> Bool {
  self.get_kind(idx) == GC_KIND_STRUCT
}

///|
/// Check if this is an array
pub fn CHeap::is_array(self : CHeap, idx : Int32) -> Bool {
  self.get_kind(idx) == GC_KIND_ARRAY
}

///|
/// Check if an object reference is valid
pub fn CHeap::is_valid(self : CHeap, idx : Int32) -> Bool {
  let gc_ref = idx + 1
  c_gc_heap_is_valid(self.ptr, gc_ref) != 0
}

// ============================================================
// GC Operations
// ============================================================

///|
/// Perform garbage collection with given roots
/// Returns the number of objects collected
pub fn CHeap::collect(self : CHeap, roots : Array[@types.Value]) -> Int32 {
  let num_roots = roots.length()
  let raw_roots = FixedArray::makei(num_roots, fn(i) { value_to_i64(roots[i]) })
  c_gc_heap_collect(self.ptr, raw_roots, num_roots)
}

///|
/// Complete native root words, including tagged exception snapshots.
pub fn CHeap::collect_raw(self : CHeap, roots : Array[Int64]) -> Int32 {
  let buffer = FixedArray::makei(roots.length(), i => roots[i])
  c_gc_heap_collect(self.ptr, buffer, buffer.length())
}

///|
/// Supply a transitive typed root set before collection (phase 0), and release
/// unreachable auxiliary handles after sweep (phase 1). Bind outside execution.
pub fn CHeap::bind_root_visitor(
  self : CHeap,
  visitor : (Int32, FixedArray[Int64]) -> FixedArray[Int64],
) -> Unit {
  self.ptr.bind_root_visitor(visitor)
}

///|
/// Low words for conservative tracing of allocations without a declared type.
pub fn CHeap::reference_candidates(
  self : CHeap,
  index : Int32,
) -> FixedArray[Int64] {
  self.ptr.reference_candidates(index + 1)
}

///|
/// Verify heap invariants (for debugging)
pub fn CHeap::verify(self : CHeap, verbose~ : Bool = false) -> Bool {
  c_gc_heap_verify(self.ptr, if verbose { 1 } else { 0 }) != 0
}

// ============================================================
// JIT Utilities
// ============================================================

///|
/// Get heap base pointer (for JIT inline access)
pub fn CHeap::get_base(self : CHeap) -> Int64 {
  c_gc_heap_get_base(self.ptr)
}

///|
/// Get object offset in heap (for JIT inline access)
pub fn CHeap::get_offset(self : CHeap, idx : Int32) -> Int32 {
  let gc_ref = idx + 1
  c_gc_heap_get_offset(self.ptr, gc_ref)
}

// ============================================================
// GC Statistics
// ============================================================

///|
/// Get current heap size (bytes used)
pub fn CHeap::get_size(self : CHeap) -> Int64 {
  c_gc_heap_get_size(self.ptr)
}

///|
/// Get heap capacity (total allocated bytes)
pub fn CHeap::get_capacity(self : CHeap) -> Int64 {
  c_gc_heap_get_capacity(self.ptr)
}

///|
/// Get heap usage ratio (0.0 to 1.0)
pub fn CHeap::get_usage_ratio(self : CHeap) -> Double {
  let size = self.get_size()
  let capacity = self.get_capacity()
  if capacity == 0L {
    0.0
  } else {
    size.to_double() / capacity.to_double()
  }
}

///|
/// Get number of objects in heap
pub fn CHeap::get_object_count(self : CHeap) -> Int32 {
  c_gc_heap_get_object_count(self.ptr)
}

///|
/// Get total number of write-barrier calls recorded
pub fn CHeap::get_barrier_writes(self : CHeap) -> Int32 {
  c_gc_heap_get_barrier_writes(self.ptr)
}

///|
/// Get total number of allocations since heap creation
pub fn CHeap::get_total_allocations(self : CHeap) -> Int32 {
  c_gc_heap_get_total_allocations(self.ptr)
}

///|
/// Get total number of GC cycles performed
pub fn CHeap::get_total_collections(self : CHeap) -> Int32 {
  c_gc_heap_get_total_collections(self.ptr)
}

///|
/// Check if GC should be triggered based on heap usage
/// Default threshold is 75% of capacity
pub fn CHeap::should_collect(self : CHeap, threshold~ : Double = 0.75) -> Bool {
  self.get_usage_ratio() >= threshold
}

///|
/// Configure allocation fault injection for debugging
pub fn gc_debug_set_fail_alloc(
  fail_at : Int32,
  fail_every~ : Int32 = 0,
) -> Unit {
  c_gc_heap_debug_set_fail_alloc(fail_at, fail_every)
}

///|
#borrow(pointer)
extern "c" fn get_runtime_type(
  pointer : GCHeapHandle,
  reference : Int32,
) -> Int32 = "wasmoon_gc_heap_get_runtime_type"

///|
#borrow(pointer)
extern "c" fn set_runtime_type(
  pointer : GCHeapHandle,
  reference : Int32,
  identity : Int32,
) -> Unit = "wasmoon_gc_heap_set_runtime_type"

///|
pub fn CHeap::runtime_type(self : CHeap, index : Int32) -> Int32 {
  get_runtime_type(self.ptr, index + 1)
}

///|
pub fn CHeap::set_runtime_type(
  self : CHeap,
  index : Int32,
  identity : Int32,
) -> Unit {
  set_runtime_type(self.ptr, index + 1, identity)
}

///|
/// Release a scoped embedding visitor after execution or collection completes.
pub fn CHeap::clear_root_visitor(self : CHeap) -> Unit {
  self.ptr.clear_root_visitor()
}
