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
  value == @wasm_milkir.NULL_REF
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
/// Set up the type cache for subtyping checks from raw type data
/// types: Array of SubType from the module
/// canonical_indices: Array of canonical type indices
fn setup_type_cache_from_types(
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
  c_jit_gc_set_type_cache(ctx_ptr, types_data, num_types)
  // Also set canonical indices if available
  if canonical_indices.length() > 0 {
    let canonical = FixedArray::make(canonical_indices.length(), 0)
    for i, idx in canonical_indices {
      canonical[i] = idx
    }
    c_jit_gc_set_canonical_indices(
      ctx_ptr,
      canonical,
      canonical_indices.length(),
    )
  }
}

///|
/// Clean up GC context after JIT execution
fn gc_teardown(ctx_ptr : Int64) -> Unit {
  // Clear the type cache
  c_jit_gc_clear_cache(ctx_ptr)
  // Clear the heap pointer
  c_jit_gc_clear_heap(ctx_ptr)
}

///|
/// Set up the GC heap for JIT execution
/// heap: The CHeap pointer from Store
fn gc_set_heap(ctx_ptr : Int64, heap : CHeap) -> Unit {
  c_jit_gc_set_heap(ctx_ptr, heap.get_ptr())
}

///|
fn gc_set_context_heap_ptr(ctx_ptr : Int64, heap_ptr : Int64) -> Unit {
  c_jit_ctx_set_gc_heap(ctx_ptr, heap_ptr)
}

///|
/// Begin a GC frame scope for current JIT context.
fn gc_begin_frame(ctx_ptr : Int64, frame_id : Int64) -> Unit {
  c_jit_gc_begin_frame(ctx_ptr, frame_id)
}

///|
/// End a GC frame scope for current JIT context.
fn gc_end_frame(ctx_ptr : Int64) -> Unit {
  c_jit_gc_end_frame(ctx_ptr)
}

///|
fn gc_push_root_scope_symbol() -> String {
  "wasmoon.runtime.gc.push_root_scope"
}

///|
fn gc_pop_root_scope_symbol() -> String {
  "wasmoon.runtime.gc.pop_root_scope"
}

///|
/// Merge roots into context-local scratch storage for allocation retries.
fn gc_set_root_scratch(ctx_ptr : Int64, roots : Array[Int64]) -> Bool {
  let raw_roots = FixedArray::makei(roots.length(), fn(i) { roots[i] })
  c_jit_gc_set_root_scratch(ctx_ptr, raw_roots, roots.length()) == 1
}

///|
/// Trigger a GC cycle for allocation retry.
fn gc_collect_for_alloc(ctx_ptr : Int64, roots : Array[Int64]) -> Int {
  let raw_roots = FixedArray::makei(roots.length(), fn(i) { roots[i] })
  c_jit_gc_collect_for_alloc(ctx_ptr, raw_roots, roots.length())
}

///|
/// Set safepoint metadata table pointer for current context.
fn gc_set_safepoint_table(ctx_ptr : Int64, table_ptr : Int64) -> Unit {
  c_jit_gc_set_safepoint_table(ctx_ptr, table_ptr)
}

///|
/// Install verified code-object safepoints into context-owned GC metadata.
fn gc_set_code_object_safepoints(
  ctx_ptr : Int64,
  func_idx : Int,
  safepoints : Array[@code_object.SafepointSite],
) -> Bool {
  let entries : Array[GcSafepoint] = []
  let root_counts : Array[Int] = []
  for site in safepoints {
    let root_count = match site.stack_map {
      Some(stack_map) => stack_map.argument_root_count
      None => 0
    }
    entries.push(
      GcSafepoint(
        site.offset,
        Array::makei(root_count, index => index),
        root_count.to_int64(),
      ),
    )
    root_counts.push(root_count)
  }
  let stackmap_blob = compiled_build_gc_stackmap_blob_v2(entries, root_counts)
  let offsets = FixedArray::makei(entries.length(), fn(i) {
    entries[i].code_offset
  })
  c_jit_gc_set_func_safepoints(
    ctx_ptr,
    func_idx,
    stackmap_blob,
    stackmap_blob.length(),
    offsets,
    entries.length(),
  ) ==
  1
}

///|
fn gc_use_func_safepoints(ctx_ptr : Int64, func_idx : Int) -> Unit {
  c_jit_gc_use_func_safepoints(ctx_ptr, func_idx)
}

///|
/// Error for invalid JIT GC setup context
pub(all) suberror GCSetupError {
  MissingJITContext
  InvalidFuncCount(num_funcs~ : Int)
  FuncTypeIndicesLengthMismatch(func_type_indices_len~ : Int, num_funcs~ : Int)
  MissingFunctionTableContext(num_funcs~ : Int)
} derive(Debug)

///|
/// Keep `Show` behavior while migrating from deprecated `derive(Show)` to
/// `derive(Debug)`.
pub impl Show for GCSetupError with fn output(self, logger) {
  logger.write_string(@types.compact_show_repr(Repr(self).to_string()))
}

///|
/// Full GC setup for JIT: set heap and type cache
/// `func_type_indices`, `func_table_ptr`, and `num_funcs` are required to keep
/// typed funcref/ref.func operations safe and deterministic.
fn gc_setup(
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
  c_jit_gc_set_func_type_indices(ctx_ptr, indices, func_type_indices.length())

  // Set function table pointer for tagged pointer funcref lookups.
  c_jit_gc_set_func_table(ctx_ptr, func_table_ptr, num_funcs)
}

///|
pub fn NativeJITContext::setup_gc(
  self : NativeJITContext,
  heap : CHeap,
  types : Array[@types.SubType],
  canonical_indices : Array[Int],
  func_type_indices : Array[Int],
) -> Unit raise GCSetupError {
  self.with_ptr(fn(ptr) raise GCSetupError {
    let num_funcs = context_func_count(ptr)
    gc_setup(
      heap,
      types,
      canonical_indices,
      ctx_ptr=ptr,
      func_type_indices~,
      func_table_ptr=context_func_table_ptr(ptr),
      num_funcs~,
    )
  })
}

///|
pub fn NativeJITContext::setup_gc_with_func_table(
  self : NativeJITContext,
  heap : CHeap,
  types : Array[@types.SubType],
  canonical_indices : Array[Int],
  func_type_indices : Array[Int],
  func_table_ptr : Int64,
  num_funcs : Int,
) -> Unit raise GCSetupError {
  self.with_ptr(fn(ptr) raise GCSetupError {
    gc_setup(
      heap,
      types,
      canonical_indices,
      ctx_ptr=ptr,
      func_type_indices~,
      func_table_ptr~,
      num_funcs~,
    )
  })
}

///|
pub fn NativeJITContext::teardown_gc(self : NativeJITContext) -> Unit {
  self.with_ptr(fn(ptr) { gc_teardown(ptr) })
}

///|
pub fn NativeJITContext::set_gc_heap_ptr(
  self : NativeJITContext,
  heap_ptr : Int64,
) -> Unit {
  self.with_ptr(fn(ptr) { gc_set_context_heap_ptr(ptr, heap_ptr) })
}

///|
pub fn NativeJITContext::set_gc_heap(
  self : NativeJITContext,
  heap : CHeap,
) -> Unit {
  self.with_ptr(fn(ptr) { gc_set_heap(ptr, heap) })
}

///|
pub fn NativeJITContext::gc_begin_frame(
  self : NativeJITContext,
  frame_id : Int64,
) -> Unit {
  self.with_ptr(fn(ptr) { gc_begin_frame(ptr, frame_id) })
}

///|
pub fn NativeJITContext::gc_end_frame(self : NativeJITContext) -> Unit {
  self.with_ptr(fn(ptr) { gc_end_frame(ptr) })
}

///|
pub fn NativeJITContext::gc_set_root_scratch(
  self : NativeJITContext,
  roots : Array[Int64],
) -> Bool {
  self.with_ptr(fn(ptr) { gc_set_root_scratch(ptr, roots) })
}

///|
pub fn NativeJITContext::gc_collect_for_alloc(
  self : NativeJITContext,
  roots : Array[Int64],
) -> Int {
  self.with_ptr(fn(ptr) { gc_collect_for_alloc(ptr, roots) })
}

///|
pub fn NativeJITContext::gc_set_safepoint_table(
  self : NativeJITContext,
  table_ptr : Int64,
) -> Unit {
  self.with_ptr(fn(ptr) { gc_set_safepoint_table(ptr, table_ptr) })
}

///|
pub fn NativeJITContext::register_safepoints(
  self : NativeJITContext,
  func_idx : Int,
  safepoints : Array[@code_object.SafepointSite],
) -> Bool {
  self.with_ptr(fn(ptr) {
    gc_set_code_object_safepoints(ptr, func_idx, safepoints)
  })
}

///|
pub fn NativeJITContext::gc_use_func_safepoints(
  self : NativeJITContext,
  func_idx : Int,
) -> Unit {
  self.with_ptr(fn(ptr) { gc_use_func_safepoints(ptr, func_idx) })
}

///|
pub fn NativeJITContext::gc_environment_is_clear(
  self : NativeJITContext,
) -> Bool {
  self.with_ptr(fn(ptr) { c_jit_gc_environment_is_clear(ptr) == 1 })
}
