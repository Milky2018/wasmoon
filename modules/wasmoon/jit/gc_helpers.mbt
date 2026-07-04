/// GC helper compatibility wrappers.
///
/// The implementation lives in `Milky2018/wasmoon_jit`; this package keeps the
/// historical `Milky2018/wasmoon/jit` API while Wasmoon call sites migrate.

///|
pub type GCSetupError = @wasmoon_jit.GCSetupError

///|
pub fn encode_i31(value : Int) -> Int64 {
  @wasmoon_jit.encode_i31(value)
}

///|
pub fn decode_i31(encoded : Int64) -> Int {
  @wasmoon_jit.decode_i31(encoded)
}

///|
pub fn is_i31(value : Int64) -> Bool {
  @wasmoon_jit.is_i31(value)
}

///|
pub fn is_null(value : Int64) -> Bool {
  @wasmoon_jit.is_null(value)
}

///|
pub fn encode_heap_ref(heap_idx : Int) -> Int64 {
  @wasmoon_jit.encode_heap_ref(heap_idx)
}

///|
pub fn decode_heap_ref(encoded : Int64) -> Int {
  @wasmoon_jit.decode_heap_ref(encoded)
}

///|
pub fn get_gc_ref_test_ptr() -> Int64 {
  @wasmoon_jit.get_gc_ref_test_ptr()
}

///|
pub fn get_gc_ref_cast_ptr() -> Int64 {
  @wasmoon_jit.get_gc_ref_cast_ptr()
}

///|
pub fn get_gc_struct_new_ptr() -> Int64 {
  @wasmoon_jit.get_gc_struct_new_ptr()
}

///|
pub fn get_gc_struct_get_ptr() -> Int64 {
  @wasmoon_jit.get_gc_struct_get_ptr()
}

///|
pub fn get_gc_struct_set_ptr() -> Int64 {
  @wasmoon_jit.get_gc_struct_set_ptr()
}

///|
pub fn get_gc_array_new_ptr() -> Int64 {
  @wasmoon_jit.get_gc_array_new_ptr()
}

///|
pub fn get_gc_array_get_ptr() -> Int64 {
  @wasmoon_jit.get_gc_array_get_ptr()
}

///|
pub fn get_gc_array_set_ptr() -> Int64 {
  @wasmoon_jit.get_gc_array_set_ptr()
}

///|
pub fn get_gc_array_len_ptr() -> Int64 {
  @wasmoon_jit.get_gc_array_len_ptr()
}

///|
pub fn get_gc_array_fill_ptr() -> Int64 {
  @wasmoon_jit.get_gc_array_fill_ptr()
}

///|
pub fn get_gc_array_copy_ptr() -> Int64 {
  @wasmoon_jit.get_gc_array_copy_ptr()
}

///|
pub fn get_gc_type_check_subtype_ptr() -> Int64 {
  @wasmoon_jit.get_gc_type_check_subtype_ptr()
}

///|
pub fn setup_type_cache_from_types(
  ctx_ptr : Int64,
  types : Array[@types.SubType],
  canonical_indices : Array[Int],
) -> Unit {
  @wasmoon_jit.setup_type_cache_from_types(ctx_ptr, types, canonical_indices)
}

///|
pub fn gc_teardown(ctx_ptr : Int64) -> Unit {
  @wasmoon_jit.gc_teardown(ctx_ptr)
}

///|
pub fn gc_set_heap(ctx_ptr : Int64, heap : CHeap) -> Unit {
  @wasmoon_jit.gc_set_heap(ctx_ptr, heap)
}

///|
pub fn gc_clear_heap(ctx_ptr : Int64) -> Unit {
  @wasmoon_jit.gc_clear_heap(ctx_ptr)
}

///|
pub fn gc_begin_frame(ctx_ptr : Int64, frame_id : Int64) -> Unit {
  @wasmoon_jit.gc_begin_frame(ctx_ptr, frame_id)
}

///|
pub fn gc_end_frame(ctx_ptr : Int64) -> Unit {
  @wasmoon_jit.gc_end_frame(ctx_ptr)
}

///|
pub fn gc_set_root_scratch(ctx_ptr : Int64, roots : Array[Int64]) -> Bool {
  @wasmoon_jit.gc_set_root_scratch(ctx_ptr, roots)
}

///|
pub fn gc_collect_for_alloc(ctx_ptr : Int64, roots : Array[Int64]) -> Int {
  @wasmoon_jit.gc_collect_for_alloc(ctx_ptr, roots)
}

///|
pub fn gc_set_safepoint_table(ctx_ptr : Int64, table_ptr : Int64) -> Unit {
  @wasmoon_jit.gc_set_safepoint_table(ctx_ptr, table_ptr)
}

///|
pub fn gc_setup(
  heap : CHeap,
  types : Array[@types.SubType],
  canonical_indices : Array[Int],
  ctx_ptr~ : Int64,
  func_type_indices~ : Array[Int],
  func_table_ptr~ : Int64,
  num_funcs~ : Int,
) -> Unit raise @wasmoon_jit.GCSetupError {
  @wasmoon_jit.gc_setup(
    heap,
    types,
    canonical_indices,
    ctx_ptr~,
    func_type_indices~,
    func_table_ptr~,
    num_funcs~,
  )
}
