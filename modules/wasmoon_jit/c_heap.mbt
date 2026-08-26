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
const GC_KIND_STRUCT : Int = 1

///|
const GC_KIND_ARRAY : Int = 2

// ============================================================
// CHeap Type
// ============================================================

///|
/// C-managed GC Heap
/// The heap is automatically freed when this object is garbage collected.
pub struct CHeap {
  ptr : Int64 // C GcHeap* pointer
} derive(Debug)

///|
/// Create a new C heap with the given initial capacity
pub fn CHeap::CHeap(capacity? : Int = @types.ONE_MIB_BYTES) -> CHeap {
  let ptr = c_gc_heap_new(capacity.to_int64())
  { ptr, }
}

///|
/// Free the C heap (called explicitly if needed before GC)
pub fn CHeap::free(self : CHeap) -> Unit {
  c_gc_heap_free(self.ptr)
}

///|
/// Get the raw C pointer (for JIT)
pub fn CHeap::get_ptr(self : CHeap) -> Int64 {
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
/// One field or element as the C heap stores it.
///
/// `lo` is the runtime word. Every value kind except v128 is encoded entirely
/// into it, and it is the only word the collector scans for references, so a
/// reference must never be written to `hi`.
pub struct GcSlot {
  lo : Int64
  hi : Int64
} derive(Eq, Debug)

///|
/// Encode a Value into a C heap slot.
///
/// Total, and that is the point: a slot is 16 bytes, so there is no value
/// this cannot represent and no case left to abort on.
///
/// Encoding rules for `lo`:
/// - i32: sign-extended to i64
/// - i64: as-is
/// - f32: lower 32 bits (IEEE 754 bits)
/// - f64: as-is (IEEE 754 bits)
/// - v128: low 8 bytes, with the high 8 in `hi`
/// - structref/arrayref: (gc_ref) << 1, where gc_ref = idx + 1 (even, low bit = 0)
/// - funcref: function index + 1 (0 = null)
/// - externref: extern index + 1 (0 = null)
/// - exnref: exception index + 1 (0 = null)
/// - i31: (value << 1) | 1 (tagged, low bit = 1)
/// - null: 0
///
/// GC reference detection in gc_heap_mark uses: (lo & 1) == 0 && lo > 0
pub fn value_to_slot(value : @types.Value) -> GcSlot {
  match value {
    I32(n) => { lo: n.to_int64(), hi: 0L, }
    I64(n) => { lo: n, hi: 0L, }
    F32(f) => { lo: f.reinterpret_as_int().to_int64(), hi: 0L, }
    F64(d) => { lo: d.reinterpret_as_int64(), hi: 0L, }
    V128(bytes) =>
      {
        lo: @types.bytes_to_int64_le(bytes, 0),
        hi: @types.bytes_to_int64_le(bytes, 8),
      }
    // gc_ref is 1-based: StructRef(0) -> gc_ref=1 -> encoded=2
    StructRef(idx) => { lo: (idx + 1).to_int64() << 1, hi: 0L, }
    ArrayRef(idx) => { lo: (idx + 1).to_int64() << 1, hi: 0L, }
    FuncRef(idx) => { lo: (idx + 1).to_int64(), hi: 0L, }
    ExternRef(idx) => { lo: (idx + 1).to_int64(), hi: 0L, }
    ExnRef(idx) => { lo: (idx + 1).to_int64(), hi: 0L, }
    I31(n) => { lo: (n.to_int64() << 1) | 1L, hi: 0L, }
    Null => { lo: @wasm_milkir.NULL_REF, hi: 0L, }
  }
}

///|
/// Encode a Value as a bare runtime word, for the root array the collector
/// scans. A root's high word would never be read, so dropping it is not a
/// loss of information here.
pub fn value_to_i64(value : @types.Value) -> Int64 {
  value_to_slot(value).lo
}

///|
/// Decode a runtime word to a Value based on expected type.
///
/// A word carries no high half, so a `V128` request yields a vector whose
/// upper 8 bytes are zero. Callers reading a stored field want
/// `slot_to_value`, which has the other half.
pub fn i64_to_value(raw : Int64, ty : @types.ValueType) -> @types.Value {
  slot_to_value({ lo: raw, hi: 0L, }, ty)
}

///|
/// Decode a C heap slot to a Value based on expected type.
///
/// Total, and inverse to `value_to_slot`: every `ValueType` names a value
/// this can produce, so no case has to fall back to a value of some other
/// type the way `V128 => I64(raw)` once did.
pub fn slot_to_value(slot : GcSlot, ty : @types.ValueType) -> @types.Value {
  let raw = slot.lo
  match ty {
    I32 => I32(raw.to_int())
    I64 => I64(raw)
    F32 => F32(Float::reinterpret_from_int(raw.to_int()))
    F64 => F64(raw.reinterpret_as_double())
    RefStruct(_) | RefNullStruct(_) | StructRef | RefStructAbs =>
      if raw == @wasm_milkir.NULL_REF {
        Null
      } else {
        // Decode: gc_ref = raw >> 1, idx = gc_ref - 1
        StructRef(((raw >> 1) - 1L).to_int())
      }
    RefArray(_) | RefNullArray(_) | ArrayRef | RefArrayAbs =>
      if raw == @wasm_milkir.NULL_REF {
        Null
      } else {
        // Decode: gc_ref = raw >> 1, idx = gc_ref - 1
        ArrayRef(((raw >> 1) - 1L).to_int())
      }
    FuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) =>
      if raw == @wasm_milkir.NULL_REF {
        Null
      } else {
        FuncRef((raw - 1L).to_int())
      }
    ExternRef | RefExtern =>
      if raw == @wasm_milkir.NULL_REF {
        Null
      } else {
        ExternRef((raw - 1L).to_int())
      }
    ExnRef =>
      if raw == @wasm_milkir.NULL_REF {
        Null
      } else {
        ExnRef((raw - 1L).to_int())
      }
    RefI31 | RefNullI31 =>
      if raw == @wasm_milkir.NULL_REF {
        Null
      } else {
        I31((raw >> 1).to_int())
      }
    RefEq | RefNullEq | AnyRef | RefAny =>
      // For abstract types, we need to decode based on the actual value
      if raw == @wasm_milkir.NULL_REF {
        Null
      } else if (raw & 1L) != 0L {
        // Tagged i31 (odd)
        I31((raw >> 1).to_int())
      } else {
        // GC reference (even, non-zero)
        // Decode: gc_ref = raw >> 1, idx = gc_ref - 1
        // We don't know if struct or array without querying the heap
        StructRef(((raw >> 1) - 1L).to_int())
      }
    NullRef | NullFuncRef | NullExnRef | NullExternRef | RefNone => Null
    V128 => V128(@types.int64_pair_to_v128_le(slot.lo, slot.hi))
  }
}

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
  type_idx : Int,
  fields : Array[@types.Value],
) -> Int raise CHeapError {
  let num_fields = fields.length()
  let raw_fields = slots_to_words(fields)
  let gc_ref = c_gc_heap_alloc_struct_wide(
    self.ptr,
    type_idx,
    raw_fields,
    num_fields,
  )
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
  struct_idx : Int,
  field_idx : Int,
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
  struct_idx : Int,
  field_idx : Int,
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
  type_idx : Int,
  len : Int,
  init_value : @types.Value,
) -> Int raise CHeapError {
  let slot = value_to_slot(init_value)
  let gc_ref = c_gc_heap_alloc_array_wide(
    self.ptr,
    type_idx,
    len,
    slot.lo,
    slot.hi,
  )
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
  type_idx : Int,
  elements : Array[@types.Value],
) -> Int raise CHeapError {
  let len = elements.length()
  let raw_values = slots_to_words(elements)
  let gc_ref = c_gc_heap_alloc_array_from_slots(
    self.ptr,
    type_idx,
    raw_values,
    len,
  )
  if gc_ref <= 0 {
    raise OutOfMemory
  }
  gc_ref - 1
}

///|
/// Get array length
pub fn CHeap::array_len(self : CHeap, array_idx : Int) -> Int {
  let gc_ref = array_idx + 1
  c_gc_heap_array_len(self.ptr, gc_ref)
}

///|
/// Get an array element
pub fn CHeap::array_get(
  self : CHeap,
  array_idx : Int,
  elem_idx : Int,
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
  array_idx : Int,
  elem_idx : Int,
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
  array_idx : Int,
  offset : Int,
  value : @types.Value,
  count : Int,
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
  dst_idx : Int,
  dst_offset : Int,
  src_idx : Int,
  src_offset : Int,
  count : Int,
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
pub fn CHeap::get_type_idx(self : CHeap, idx : Int) -> Int {
  let gc_ref = idx + 1
  c_gc_heap_get_type_idx(self.ptr, gc_ref)
}

///|
/// Get the kind of an object (1=struct, 2=array)
pub fn CHeap::get_kind(self : CHeap, idx : Int) -> Int {
  let gc_ref = idx + 1
  c_gc_heap_get_kind(self.ptr, gc_ref)
}

///|
/// Check if this is a struct
pub fn CHeap::is_struct(self : CHeap, idx : Int) -> Bool {
  self.get_kind(idx) == GC_KIND_STRUCT
}

///|
/// Check if this is an array
pub fn CHeap::is_array(self : CHeap, idx : Int) -> Bool {
  self.get_kind(idx) == GC_KIND_ARRAY
}

///|
/// Check if an object reference is valid
pub fn CHeap::is_valid(self : CHeap, idx : Int) -> Bool {
  let gc_ref = idx + 1
  c_gc_heap_is_valid(self.ptr, gc_ref) != 0
}

// ============================================================
// GC Operations
// ============================================================

///|
/// Perform garbage collection with given roots
/// Returns the number of objects collected
pub fn CHeap::collect(self : CHeap, roots : Array[@types.Value]) -> Int {
  let num_roots = roots.length()
  let raw_roots = FixedArray::makei(num_roots, fn(i) { value_to_i64(roots[i]) })
  c_gc_heap_collect(self.ptr, raw_roots, num_roots)
}

///|
/// Verify heap invariants (for debugging)
pub fn CHeap::verify(self : CHeap, verbose? : Bool = false) -> Bool {
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
pub fn CHeap::get_offset(self : CHeap, idx : Int) -> Int {
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
pub fn CHeap::get_object_count(self : CHeap) -> Int {
  c_gc_heap_get_object_count(self.ptr)
}

///|
/// Get total number of write-barrier calls recorded
pub fn CHeap::get_barrier_writes(self : CHeap) -> Int {
  c_gc_heap_get_barrier_writes(self.ptr)
}

///|
/// Get total number of allocations since heap creation
pub fn CHeap::get_total_allocations(self : CHeap) -> Int {
  c_gc_heap_get_total_allocations(self.ptr)
}

///|
/// Get total number of GC cycles performed
pub fn CHeap::get_total_collections(self : CHeap) -> Int {
  c_gc_heap_get_total_collections(self.ptr)
}

///|
/// Check if GC should be triggered based on heap usage
/// Default threshold is 75% of capacity
pub fn CHeap::should_collect(self : CHeap, threshold? : Double = 0.75) -> Bool {
  self.get_usage_ratio() >= threshold
}

///|
/// Configure allocation fault injection for debugging
pub fn gc_debug_set_fail_alloc(fail_at : Int, fail_every? : Int = 0) -> Unit {
  c_gc_heap_debug_set_fail_alloc(fail_at, fail_every)
}
