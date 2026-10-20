///|
pub using @runtime_bridge {
  encode_exception_ref,
  is_exception_ref,
  is_null_ref,
  encode_null_ref,
  encode_funcref_idx,
  decode_funcref_idx,
  is_funcref_ptr,
  tag_funcref_ptr,
  untag_funcref_ptr,
  encode_externref,
  decode_externref,
  encode_gc_heap_ref,
  decode_gc_heap_ref,
}

///|
pub const EXCEPTION_REF_TAG : Int64 = @runtime_bridge.EXCEPTION_REF_TAG
