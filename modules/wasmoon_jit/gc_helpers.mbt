///|
/// GC Runtime Helpers for JIT
///
/// This module provides runtime helper functions for GC operations in JIT code.
/// All GC operations (allocation, access, type checking) are implemented as
/// libcalls that access VMContext-local state set up before JIT execution.
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
  let masked = value & @types.I32_MAX
  (masked.to_int64() << 1) | 1L
}

///|
/// Decode an i31 value from JIT representation
pub fn decode_i31(encoded : Int64) -> Int {
  // Remove tag and get signed 31-bit value
  let value = (encoded >> 1).to_int()
  // Sign extend from 31 bits
  if (value & 0x40000000) != 0 {
    value | @types.I32_MIN
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
pub fn value_type_may_hold_gc_ref(ty : @types.ValueType) -> Bool {
  match ty {
    AnyRef
    | ExnRef
    | StructRef
    | ArrayRef
    | RefStruct(_)
    | RefNullStruct(_)
    | RefArray(_)
    | RefNullArray(_)
    | RefAny
    | RefEq
    | RefNullEq
    | RefI31
    | RefNullI31
    | RefStructAbs
    | RefArrayAbs
    | NullRef => true
    _ => false
  }
}

///|
pub fn collect_gc_root_args(
  args : Array[Int64],
  param_types : Array[@types.ValueType],
) -> Array[Int64] {
  let roots : Array[Int64] = []
  let upto = if args.length() < param_types.length() {
    args.length()
  } else {
    param_types.length()
  }
  for i in 0..<upto {
    let ty = param_types[i]
    if !value_type_may_hold_gc_ref(ty) {
      continue
    }
    let value = args[i]
    if value > 0L && (value & 1L) == 0L {
      roots.push(value)
    }
  }
  roots
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
  ctx_ptr : Int64,
  types : Array[@types.SubType],
  canonical_indices : Array[Int],
) -> Unit {
  let num_types = types.length()
  // Extended format (stride = 6, keep in sync with `jit_ffi/jit_internal.h`):
  //   [super_idx, kind, struct_num_fields, array_elem_tag, array_elem_bytes, array_elem_flags]
  let type_stride = 6
  let types_data = FixedArray::make(num_types * type_stride, 0)
  for i in 0..<num_types {
    let subtype = types[i]
    // Store supertype index (-1 if none)
    let super_idx = if subtype.supertypes.is_empty() {
      -1
    } else {
      subtype.supertypes[0]
    }
    let base = i * type_stride
    types_data[base + 0] = super_idx

    // kind: 0=func, 1=struct, 2=array
    // array_elem_tag: 0=none/unknown, 1=i8, 2=i16, 3=i32, 4=i64, 5=f32, 6=f64, 7=ref/other
    // array_elem_bytes: byte width of element data in segments (0 for ref/unknown)
    // array_elem_flags: reserved for future (0 for now)
    match subtype.composite {
      Func(_) => {
        types_data[base + 1] = 0
        types_data[base + 2] = 0
        types_data[base + 3] = 0
        types_data[base + 4] = 0
        types_data[base + 5] = 0
      }
      Struct(st) => {
        types_data[base + 1] = 1
        types_data[base + 2] = st.fields.length()
        types_data[base + 3] = 0
        types_data[base + 4] = 0
        types_data[base + 5] = 0
      }
      Array(at) => {
        types_data[base + 1] = 2
        types_data[base + 2] = 0
        let (tag, bytes) = match at.element.storage_type {
          Packed(I8) => (1, 1)
          Packed(I16) => (2, 2)
          Val(I32) => (3, 4)
          Val(I64) => (4, 8)
          Val(F32) => (5, 4)
          Val(F64) => (6, 8)
          _ => (7, 0)
        }
        types_data[base + 3] = tag
        types_data[base + 4] = bytes
        types_data[base + 5] = 0
      }
    }
  }
  // Set the type cache in C
  @jit_ffi.c_jit_gc_set_type_cache(ctx_ptr, types_data, num_types)
  // Also set canonical indices if available
  if canonical_indices.length() > 0 {
    let canonical = FixedArray::make(canonical_indices.length(), 0)
    for i, idx in canonical_indices {
      canonical[i] = idx
    }
    @jit_ffi.c_jit_gc_set_canonical_indices(
      ctx_ptr,
      canonical,
      canonical_indices.length(),
    )
  }
}

///|
/// Clean up GC context after JIT execution
pub fn gc_teardown(ctx_ptr : Int64) -> Unit {
  // Clear the type cache
  @jit_ffi.c_jit_gc_clear_cache(ctx_ptr)
  // Clear the heap pointer
  @jit_ffi.c_jit_gc_clear_heap(ctx_ptr)
}

///|
/// Set up the GC heap for JIT execution
/// heap: The CHeap pointer from Store
pub fn gc_set_heap(ctx_ptr : Int64, heap : CHeap) -> Unit {
  @jit_ffi.c_jit_gc_set_heap(ctx_ptr, heap.get_ptr())
}

///|
/// Clear the GC heap pointer after JIT execution
pub fn gc_clear_heap(ctx_ptr : Int64) -> Unit {
  @jit_ffi.c_jit_gc_clear_heap(ctx_ptr)
}

///|
/// Begin a GC frame scope for current JIT context.
pub fn gc_begin_frame(ctx_ptr : Int64, frame_id : Int64) -> Unit {
  @jit_ffi.c_jit_gc_begin_frame(ctx_ptr, frame_id)
}

///|
/// End a GC frame scope for current JIT context.
pub fn gc_end_frame(ctx_ptr : Int64) -> Unit {
  @jit_ffi.c_jit_gc_end_frame(ctx_ptr)
}

///|
/// Merge roots into context-local scratch storage for allocation retries.
pub fn gc_set_root_scratch(ctx_ptr : Int64, roots : Array[Int64]) -> Bool {
  let raw_roots = FixedArray::makei(roots.length(), fn(i) { roots[i] })
  @jit_ffi.c_jit_gc_set_root_scratch(ctx_ptr, raw_roots, roots.length()) == 1
}

///|
/// Trigger a GC cycle for allocation retry.
pub fn gc_collect_for_alloc(ctx_ptr : Int64, roots : Array[Int64]) -> Int {
  let raw_roots = FixedArray::makei(roots.length(), fn(i) { roots[i] })
  @jit_ffi.c_jit_gc_collect_for_alloc(ctx_ptr, raw_roots, roots.length())
}

///|
/// Set safepoint metadata table pointer for current context.
pub fn gc_set_safepoint_table(ctx_ptr : Int64, table_ptr : Int64) -> Unit {
  @jit_ffi.c_jit_gc_set_safepoint_table(ctx_ptr, table_ptr)
}

///|
/// Error for invalid JIT GC setup context
pub suberror GCSetupError {
  MissingJITContext
  InvalidFuncCount(num_funcs~ : Int)
  FuncTypeIndicesLengthMismatch(func_type_indices_len~ : Int, num_funcs~ : Int)
  MissingFunctionTableContext(num_funcs~ : Int)
} derive(Debug)

///|
/// Keep `Show` behavior while migrating from deprecated `derive(Show)` to
/// `derive(Debug)`.
pub impl Show for GCSetupError with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(to_repr(self).to_string()))
}

///|
/// Full GC setup for JIT: set heap and type cache
/// `func_type_indices`, `func_table_ptr`, and `num_funcs` are required to keep
/// typed funcref/ref.func operations safe and deterministic.
pub fn gc_setup(
  heap : CHeap,
  types : Array[@types.SubType],
  canonical_indices : Array[Int],
  ctx_ptr~ : Int64,
  func_type_indices~ : Array[Int],
  func_table_ptr~ : Int64,
  num_funcs~ : Int,
) -> Unit raise GCSetupError {
  if ctx_ptr == 0L {
    raise MissingJITContext
  }
  if num_funcs < 0 {
    raise InvalidFuncCount(num_funcs~)
  }
  if func_type_indices.length() != num_funcs {
    raise FuncTypeIndicesLengthMismatch(
      func_type_indices_len=func_type_indices.length(),
      num_funcs~,
    )
  }
  if num_funcs > 0 && func_table_ptr == 0L {
    raise MissingFunctionTableContext(num_funcs~)
  }
  gc_set_heap(ctx_ptr, heap)
  setup_type_cache_from_types(ctx_ptr, types, canonical_indices)
  // Set function type indices for funcref subtyping
  let indices = FixedArray::make(func_type_indices.length(), 0)
  for i, idx in func_type_indices {
    indices[i] = idx
  }
  @jit_ffi.c_jit_gc_set_func_type_indices(
    ctx_ptr,
    indices,
    func_type_indices.length(),
  )

  // Set function table pointer for tagged pointer funcref lookups.
  @jit_ffi.c_jit_gc_set_func_table(ctx_ptr, func_table_ptr, num_funcs)
}
