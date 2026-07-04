/// Reference encoding helpers for JIT/runtime interop.
///
/// There are multiple representations used for references:
/// - Raw (JIT ABI for values): null = 0
/// - Funcref (index form): raw = -(func_idx + 1)  (so -1 is func_idx 0, not null)
/// - Funcref (pointer form): raw = func_ptr | FUNCREF_TAG
/// - Externref: raw = EXTERNREF_TAG | (host_idx << 1)
/// - GC refs: raw = (heap_idx0 + 1) << 1
/// - i31: raw = (value << 1) | 1

///|
pub fn is_null_ref(raw : Int64) -> Bool {
  raw == @types.NULL_REF
}

///|
pub fn encode_null_ref() -> Int64 {
  @types.NULL_REF
}

///|
pub fn encode_funcref_idx(func_idx : Int) -> Int64 {
  -(func_idx.to_int64() + 1L)
}

///|
pub fn decode_funcref_idx(raw : Int64) -> Int? {
  if raw < 0L {
    Some((-(raw + 1L)).to_int())
  } else {
    None
  }
}

///|
pub fn is_funcref_ptr(raw : Int64) -> Bool {
  (raw & @types.FUNCREF_TAG) != 0L
}

///|
pub fn tag_funcref_ptr(func_ptr : Int64) -> Int64 {
  func_ptr | @types.FUNCREF_TAG
}

///|
pub fn untag_funcref_ptr(tagged_ptr : Int64) -> Int64 {
  // Clear bit 61
  tagged_ptr & 0xDFFFFFFFFFFFFFFFL
}

///|
pub fn encode_externref(host_idx : Int) -> Int64 {
  @types.EXTERNREF_TAG | (host_idx.to_int64() << 1)
}

///|
pub fn decode_externref(raw : Int64) -> Int? {
  if (raw & @types.EXTERNREF_TAG) != 0L {
    // Clear the tag bit and shift back.
    Some(((raw ^ @types.EXTERNREF_TAG) >> 1).to_int())
  } else {
    None
  }
}

///|
pub fn encode_gc_heap_ref(heap_idx0 : Int) -> Int64 {
  (heap_idx0 + 1).to_int64() << 1
}

///|
pub fn decode_gc_heap_ref(raw : Int64) -> Int? {
  if raw == @types.NULL_REF {
    None
  } else if (raw & (@types.FUNCREF_TAG | @types.EXTERNREF_TAG)) != 0L {
    None
  } else if (raw & 1L) == 1L {
    None
  } else {
    Some(((raw >> 1) - 1L).to_int())
  }
}
