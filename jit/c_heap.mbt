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
} derive(Show)

///|
/// Create a new C heap with the given initial capacity
pub fn CHeap::new(capacity? : Int = 1048576) -> CHeap {
  let ptr = @jit_ffi.c_gc_heap_new(capacity.to_int64())
  { ptr, }
}

///|
/// Free the C heap (called explicitly if needed before GC)
pub fn CHeap::free(self : CHeap) -> Unit {
  @jit_ffi.c_gc_heap_free(self.ptr)
}

///|
/// Get the raw C pointer (for JIT)
pub fn CHeap::get_ptr(self : CHeap) -> Int64 {
  self.ptr
}

// ============================================================
// Value Encoding/Decoding
// ============================================================

///|
/// Encode a Value to Int64 for C heap storage
/// Encoding rules:
/// - i32: sign-extended to i64
/// - i64: as-is
/// - f32: lower 32 bits (IEEE 754 bits)
/// - f64: as-is (IEEE 754 bits)
/// - structref/arrayref: (gc_ref) << 1, where gc_ref = idx + 1 (even, low bit = 0)
/// - funcref: function index + 1 (0 = null)
/// - externref: extern index + 1 (0 = null)
/// - exnref: exception index + 1 (0 = null)
/// - i31: (value << 1) | 1 (tagged, low bit = 1)
/// - null: 0
///
/// GC reference detection in gc_heap_mark uses: (value & 1) == 0 && value > 0
pub fn value_to_i64(value : @types.Value) -> Int64 {
  match value {
    I32(n) => n.to_int64()
    I64(n) => n
    F32(f) => f.reinterpret_as_int().to_int64()
    F64(d) => d.reinterpret_as_int64()
    V128(_) => abort("V128 values not yet supported in JIT")
    // gc_ref is 1-based: StructRef(0) -> gc_ref=1 -> encoded=2
    StructRef(idx) => (idx + 1).to_int64() << 1
    ArrayRef(idx) => (idx + 1).to_int64() << 1
    FuncRef(idx) => (idx + 1).to_int64()
    ExternRef(idx) => (idx + 1).to_int64()
    ExnRef(idx) => (idx + 1).to_int64()
    I31(n) => (n.to_int64() << 1) | 1L
    Null => @types.NULL_REF
  }
}

///|
/// Decode an Int64 from C heap to a Value based on expected type
pub fn i64_to_value(raw : Int64, ty : @types.ValueType) -> @types.Value {
  match ty {
    I32 => @types.Value::I32(raw.to_int())
    I64 => @types.Value::I64(raw)
    F32 => @types.Value::F32(Float::reinterpret_from_int(raw.to_int()))
    F64 => @types.Value::F64(raw.reinterpret_as_double())
    RefStruct(_) | RefNullStruct(_) | StructRef | RefStructAbs =>
      if raw == @types.NULL_REF {
        @types.Value::Null
      } else {
        // Decode: gc_ref = raw >> 1, idx = gc_ref - 1
        @types.Value::StructRef(((raw >> 1) - 1L).to_int())
      }
    RefArray(_) | RefNullArray(_) | ArrayRef | RefArrayAbs =>
      if raw == @types.NULL_REF {
        @types.Value::Null
      } else {
        // Decode: gc_ref = raw >> 1, idx = gc_ref - 1
        @types.Value::ArrayRef(((raw >> 1) - 1L).to_int())
      }
    FuncRef | RefFunc | RefFuncTyped(_) | RefNullFuncTyped(_) =>
      if raw == @types.NULL_REF {
        @types.Value::Null
      } else {
        @types.Value::FuncRef((raw - 1L).to_int())
      }
    ExternRef | RefExtern =>
      if raw == @types.NULL_REF {
        @types.Value::Null
      } else {
        @types.Value::ExternRef((raw - 1L).to_int())
      }
    ExnRef =>
      if raw == @types.NULL_REF {
        @types.Value::Null
      } else {
        @types.Value::ExnRef((raw - 1L).to_int())
      }
    RefI31 | RefNullI31 =>
      if raw == @types.NULL_REF {
        @types.Value::Null
      } else {
        @types.Value::I31((raw >> 1).to_int())
      }
    RefEq | RefNullEq | AnyRef | RefAny =>
      // For abstract types, we need to decode based on the actual value
      if raw == @types.NULL_REF {
        @types.Value::Null
      } else if (raw & 1L) != 0L {
        // Tagged i31 (odd)
        @types.Value::I31((raw >> 1).to_int())
      } else {
        // GC reference (even, non-zero)
        // Decode: gc_ref = raw >> 1, idx = gc_ref - 1
        // We don't know if struct or array without querying the heap
        @types.Value::StructRef(((raw >> 1) - 1L).to_int())
      }
    NullRef | NullFuncRef | NullExnRef | NullExternRef | RefNone =>
      @types.Value::Null
    V128 => @types.Value::I64(raw) // V128 not fully supported
  }
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
) -> Int {
  let num_fields = fields.length()
  let raw_fields = FixedArray::makei(num_fields, fn(i) {
    value_to_i64(fields[i])
  })
  let gc_ref = @jit_ffi.c_gc_heap_alloc_struct(
    self.ptr,
    type_idx,
    raw_fields,
    num_fields,
  )
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
  let raw = @jit_ffi.c_gc_heap_struct_get(self.ptr, gc_ref, field_idx)
  i64_to_value(raw, field_type)
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
  let raw = value_to_i64(value)
  @jit_ffi.c_gc_heap_struct_set(self.ptr, gc_ref, field_idx, raw)
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
) -> Int {
  let raw_init = value_to_i64(init_value)
  let gc_ref = @jit_ffi.c_gc_heap_alloc_array(self.ptr, type_idx, len, raw_init)
  gc_ref - 1
}

///|
/// Allocate a new array from existing values
/// Returns gc_ref (0-based index for external use)
pub fn CHeap::alloc_array_from_values(
  self : CHeap,
  type_idx : Int,
  elements : Array[@types.Value],
) -> Int {
  let len = elements.length()
  let raw_values = FixedArray::makei(len, fn(i) { value_to_i64(elements[i]) })
  let gc_ref = @jit_ffi.c_gc_heap_alloc_array_from_values(
    self.ptr,
    type_idx,
    raw_values,
    len,
  )
  gc_ref - 1
}

///|
/// Get array length
pub fn CHeap::array_len(self : CHeap, array_idx : Int) -> Int {
  let gc_ref = array_idx + 1
  @jit_ffi.c_gc_heap_array_len(self.ptr, gc_ref)
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
  let len = @jit_ffi.c_gc_heap_array_len(self.ptr, gc_ref)
  if elem_idx < 0 || elem_idx >= len {
    raise OutOfBoundsArrayAccess
  }
  let raw = @jit_ffi.c_gc_heap_array_get(self.ptr, gc_ref, elem_idx)
  i64_to_value(raw, elem_type)
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
  let len = @jit_ffi.c_gc_heap_array_len(self.ptr, gc_ref)
  if elem_idx < 0 || elem_idx >= len {
    raise OutOfBoundsArrayAccess
  }
  let raw = value_to_i64(value)
  @jit_ffi.c_gc_heap_array_set(self.ptr, gc_ref, elem_idx, raw)
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
  let len = @jit_ffi.c_gc_heap_array_len(self.ptr, gc_ref)
  if offset < 0 || count < 0 || offset + count > len {
    raise OutOfBoundsArrayAccess
  }
  let raw = value_to_i64(value)
  @jit_ffi.c_gc_heap_array_fill(self.ptr, gc_ref, offset, raw, count)
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
  let dst_len = @jit_ffi.c_gc_heap_array_len(self.ptr, dst_ref)
  let src_len = @jit_ffi.c_gc_heap_array_len(self.ptr, src_ref)
  if dst_offset < 0 ||
    src_offset < 0 ||
    count < 0 ||
    dst_offset + count > dst_len ||
    src_offset + count > src_len {
    raise OutOfBoundsArrayAccess
  }
  @jit_ffi.c_gc_heap_array_copy(
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
  @jit_ffi.c_gc_heap_get_type_idx(self.ptr, gc_ref)
}

///|
/// Get the kind of an object (1=struct, 2=array)
pub fn CHeap::get_kind(self : CHeap, idx : Int) -> Int {
  let gc_ref = idx + 1
  @jit_ffi.c_gc_heap_get_kind(self.ptr, gc_ref)
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
  @jit_ffi.c_gc_heap_is_valid(self.ptr, gc_ref) != 0
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
  @jit_ffi.c_gc_heap_collect(self.ptr, raw_roots, num_roots)
}

// ============================================================
// JIT Utilities
// ============================================================

///|
/// Get heap base pointer (for JIT inline access)
pub fn CHeap::get_base(self : CHeap) -> Int64 {
  @jit_ffi.c_gc_heap_get_base(self.ptr)
}

///|
/// Get object offset in heap (for JIT inline access)
pub fn CHeap::get_offset(self : CHeap, idx : Int) -> Int {
  let gc_ref = idx + 1
  @jit_ffi.c_gc_heap_get_offset(self.ptr, gc_ref)
}

// ============================================================
// GC Statistics
// ============================================================

///|
/// Get current heap size (bytes used)
pub fn CHeap::get_size(self : CHeap) -> Int64 {
  @jit_ffi.c_gc_heap_get_size(self.ptr)
}

///|
/// Get heap capacity (total allocated bytes)
pub fn CHeap::get_capacity(self : CHeap) -> Int64 {
  @jit_ffi.c_gc_heap_get_capacity(self.ptr)
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
  @jit_ffi.c_gc_heap_get_object_count(self.ptr)
}

///|
/// Get total number of allocations since heap creation
pub fn CHeap::get_total_allocations(self : CHeap) -> Int {
  @jit_ffi.c_gc_heap_get_total_allocations(self.ptr)
}

///|
/// Get total number of GC cycles performed
pub fn CHeap::get_total_collections(self : CHeap) -> Int {
  @jit_ffi.c_gc_heap_get_total_collections(self.ptr)
}

///|
/// Check if GC should be triggered based on heap usage
/// Default threshold is 75% of capacity
pub fn CHeap::should_collect(self : CHeap, threshold? : Double = 0.75) -> Bool {
  self.get_usage_ratio() >= threshold
}
