///|
/// GC Runtime Helpers for JIT
///
/// This module provides runtime helper functions for GC operations in JIT code.
/// All GC operations (allocation, access, type checking) are implemented as
/// libcalls that access global state set up before JIT execution.
///
/// Value representation in JIT (Int64):
/// - i31ref: (value << 1) | 1 (lowest bit = 1 for tagging)
/// - StructRef/ArrayRef: heap index (positive integer, lowest bit = 0)
/// - null: 0
///
/// Before calling JIT code with GC operations, the runtime must:
/// 1. Call gc_setup() to prepare the C-side heap snapshot
/// 2. After JIT returns, call gc_teardown() to sync changes back

// ============ Value Encoding/Decoding ============

///|
/// Encode an i31 value for JIT (tagged pointer with lowest bit = 1)
pub fn encode_i31(value : Int) -> Int64 {
  // i31 stores 31 bits, mask and tag
  let masked = value & 0x7FFFFFFF
  (masked.to_int64() << 1) | 1L
}

///|
/// Decode an i31 value from JIT representation
pub fn decode_i31(encoded : Int64) -> Int {
  // Remove tag and get signed 31-bit value
  let value = (encoded >> 1).to_int()
  // Sign extend from 31 bits
  if (value & 0x40000000) != 0 {
    value | -2147483648
  } else { // 0x80000000
    value
  }
}

///|
/// Check if a JIT value is an i31 (has tag bit set)
pub fn is_i31(value : Int64) -> Bool {
  (value & 1L) == 1L
}

///|
/// Check if a JIT value is null
pub fn is_null(value : Int64) -> Bool {
  value == @types.NULL_REF
}

///|
/// Encode a heap reference (struct or array) for JIT
/// heap_idx is 0-based (from MoonBit Store/CHeap)
/// JIT uses 1-based gc_ref internally to avoid collision with null (0)
pub fn encode_heap_ref(heap_idx : Int) -> Int64 {
  // Convert 0-based to 1-based, then shift left by 1
  // This ensures encoded value is never 0 (which is null)
  (heap_idx + 1).to_int64() << 1
}

///|
/// Decode a heap reference from JIT representation
/// Returns 0-based heap_idx for MoonBit Store/CHeap
pub fn decode_heap_ref(encoded : Int64) -> Int {
  // Shift right to get 1-based gc_ref, then convert to 0-based
  (encoded >> 1).to_int() - 1
}

// ============ GC Libcall Function Pointers ============
// These return function pointers to C helper functions

///|
/// Get ref.test libcall function pointer
/// Signature: int gc_ref_test(int64_t ref, int type_idx, int nullable)
/// Returns 1 if test passes, 0 otherwise
pub fn get_gc_ref_test_ptr() -> Int64 {
  @jit_ffi.c_jit_get_gc_ref_test_ptr()
}

///|
/// Get ref.cast libcall function pointer
/// Signature: int64_t gc_ref_cast(int64_t ref, int type_idx, int nullable)
/// Returns the ref if cast succeeds, traps on failure
pub fn get_gc_ref_cast_ptr() -> Int64 {
  @jit_ffi.c_jit_get_gc_ref_cast_ptr()
}

///|
/// Get struct.new libcall function pointer
/// Signature: int64_t gc_struct_new(int type_idx, int64_t* fields, int num_fields)
/// Returns encoded StructRef
pub fn get_gc_struct_new_ptr() -> Int64 {
  @jit_ffi.c_jit_get_gc_struct_new_ptr()
}

///|
/// Get struct.get libcall function pointer
/// Signature: int64_t gc_struct_get(int64_t ref, int type_idx, int field_idx)
/// Returns the field value
pub fn get_gc_struct_get_ptr() -> Int64 {
  @jit_ffi.c_jit_get_gc_struct_get_ptr()
}

///|
/// Get struct.set libcall function pointer
/// Signature: void gc_struct_set(int64_t ref, int type_idx, int field_idx, int64_t value)
pub fn get_gc_struct_set_ptr() -> Int64 {
  @jit_ffi.c_jit_get_gc_struct_set_ptr()
}

///|
/// Get array.new libcall function pointer
/// Signature: int64_t gc_array_new(int type_idx, int len, int64_t fill)
/// Returns encoded ArrayRef
pub fn get_gc_array_new_ptr() -> Int64 {
  @jit_ffi.c_jit_get_gc_array_new_ptr()
}

///|
/// Get array.get libcall function pointer
/// Signature: int64_t gc_array_get(int64_t ref, int type_idx, int idx)
/// Returns the element value
pub fn get_gc_array_get_ptr() -> Int64 {
  @jit_ffi.c_jit_get_gc_array_get_ptr()
}

///|
/// Get array.set libcall function pointer
/// Signature: void gc_array_set(int64_t ref, int type_idx, int idx, int64_t value)
pub fn get_gc_array_set_ptr() -> Int64 {
  @jit_ffi.c_jit_get_gc_array_set_ptr()
}

///|
/// Get array.len libcall function pointer
/// Signature: int gc_array_len(int64_t ref)
/// Returns the array length
pub fn get_gc_array_len_ptr() -> Int64 {
  @jit_ffi.c_jit_get_gc_array_len_ptr()
}

///|
/// Get array.fill libcall function pointer
/// Signature: void gc_array_fill(int64_t ref, int32_t offset, int64_t value, int32_t count)
/// Fills array elements with a value
pub fn get_gc_array_fill_ptr() -> Int64 {
  @jit_ffi.c_jit_get_gc_array_fill_ptr()
}

///|
/// Get array.copy libcall function pointer
/// Signature: void gc_array_copy(int64_t dst_ref, int32_t dst_off, int64_t src_ref, int32_t src_off, int32_t count)
/// Copies array elements from source to destination
pub fn get_gc_array_copy_ptr() -> Int64 {
  @jit_ffi.c_jit_get_gc_array_copy_ptr()
}

///|
/// Get type check subtype libcall function pointer for call_indirect with subtyping
/// Signature: void gc_type_check_subtype(int32_t actual_type, int32_t expected_type)
/// Traps if actual_type is not a subtype of expected_type
pub fn get_gc_type_check_subtype_ptr() -> Int64 {
  @jit_ffi.c_jit_get_gc_type_check_subtype_ptr()
}

// ============ GC Context Setup ============
// Note: The actual gc_setup function that takes Store/Instance is in
// jit/ffi_jit.mbt, which has access to the runtime package.
// This file only contains the low-level helpers.

///|
/// Set up the type cache for subtyping checks from raw type data
/// types: Array of SubType from the module
/// canonical_indices: Array of canonical type indices
pub fn setup_type_cache_from_types(
  types : Array[@types.SubType],
  canonical_indices : Array[Int],
) -> Unit {
  let num_types = types.length()
  // Extended format: [super_idx, kind, num_fields] per type
  let types_data = FixedArray::make(num_types * 3, 0)
  for i in 0..<num_types {
    let subtype = types[i]
    // Store supertype index (-1 if none)
    let super_idx = if subtype.supertypes.is_empty() {
      -1
    } else {
      subtype.supertypes[0]
    }
    types_data[i * 3] = super_idx
    // Store composite type kind: 0=func, 1=struct, 2=array
    // And field count for struct types
    let (kind, num_fields) = match subtype.composite {
      Func(_) => (0, 0)
      Struct(st) => (1, st.fields.length())
      Array(_) => (2, 0)
    }
    types_data[i * 3 + 1] = kind
    types_data[i * 3 + 2] = num_fields
  }
  // Set the type cache in C
  @jit_ffi.c_jit_gc_set_type_cache(types_data, num_types)
  // Also set canonical indices if available
  if canonical_indices.length() > 0 {
    let canonical = FixedArray::make(canonical_indices.length(), 0)
    for i, idx in canonical_indices {
      canonical[i] = idx
    }
    @jit_ffi.c_jit_gc_set_canonical_indices(
      canonical,
      canonical_indices.length(),
    )
  }
}

///|
/// Clean up GC context after JIT execution
pub fn gc_teardown() -> Unit {
  // Clear the type cache
  @jit_ffi.c_jit_gc_clear_cache()
  // Clear the heap pointer
  @jit_ffi.c_jit_gc_clear_heap()
}

///|
/// Set up the GC heap for JIT execution
/// heap: The CHeap pointer from Store
pub fn gc_set_heap(heap : CHeap) -> Unit {
  @jit_ffi.c_jit_gc_set_heap(heap.get_ptr())
}

///|
/// Clear the GC heap pointer after JIT execution
pub fn gc_clear_heap() -> Unit {
  @jit_ffi.c_jit_gc_clear_heap()
}

///|
/// Full GC setup for JIT: set heap and type cache
pub fn gc_setup(
  heap : CHeap,
  types : Array[@types.SubType],
  canonical_indices : Array[Int],
  func_type_indices? : Array[Int] = [],
  func_table_ptr? : Int64 = 0L,
  num_funcs? : Int = 0,
) -> Unit {
  gc_set_heap(heap)
  setup_type_cache_from_types(types, canonical_indices)
  // Also set function type indices for funcref subtyping
  if func_type_indices.length() > 0 {
    let indices = FixedArray::make(func_type_indices.length(), 0)
    for i, idx in func_type_indices {
      indices[i] = idx
    }
    @jit_ffi.c_jit_gc_set_func_type_indices(indices, func_type_indices.length())
  }
  // Set function table pointer for tagged pointer funcref lookups
  if func_table_ptr != 0L && num_funcs > 0 {
    @jit_ffi.c_jit_gc_set_func_table(func_table_ptr, num_funcs)
  }
}
