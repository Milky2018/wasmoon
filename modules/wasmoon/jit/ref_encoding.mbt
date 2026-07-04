/// Reference encoding compatibility wrappers.
///
/// The implementation lives in `Milky2018/wasmoon_jit`; this package keeps the
/// historical `Milky2018/wasmoon/jit` API while Wasmoon call sites migrate.

///|
pub fn is_null_ref(raw : Int64) -> Bool {
  @wasmoon_jit.is_null_ref(raw)
}

///|
pub fn encode_null_ref() -> Int64 {
  @wasmoon_jit.encode_null_ref()
}

///|
pub fn encode_funcref_idx(func_idx : Int) -> Int64 {
  @wasmoon_jit.encode_funcref_idx(func_idx)
}

///|
pub fn decode_funcref_idx(raw : Int64) -> Int? {
  @wasmoon_jit.decode_funcref_idx(raw)
}

///|
pub fn is_funcref_ptr(raw : Int64) -> Bool {
  @wasmoon_jit.is_funcref_ptr(raw)
}

///|
pub fn tag_funcref_ptr(func_ptr : Int64) -> Int64 {
  @wasmoon_jit.tag_funcref_ptr(func_ptr)
}

///|
pub fn untag_funcref_ptr(tagged_ptr : Int64) -> Int64 {
  @wasmoon_jit.untag_funcref_ptr(tagged_ptr)
}

///|
pub fn encode_externref(host_idx : Int) -> Int64 {
  @wasmoon_jit.encode_externref(host_idx)
}

///|
pub fn decode_externref(raw : Int64) -> Int? {
  @wasmoon_jit.decode_externref(raw)
}

///|
pub fn encode_gc_heap_ref(heap_idx0 : Int) -> Int64 {
  @wasmoon_jit.encode_gc_heap_ref(heap_idx0)
}

///|
pub fn decode_gc_heap_ref(raw : Int64) -> Int? {
  @wasmoon_jit.decode_gc_heap_ref(raw)
}
