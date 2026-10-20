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
/// - funcref: tagged Store function identity (0 = null)
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
    FuncRef(idx) => { lo: encode_store_funcref(idx), hi: 0L, }
    ExternRef(idx) => { lo: encode_externref(idx), hi: 0L, }
    ExnRef(idx) => { lo: encode_exception_ref(idx), hi: 0L, }
    // Store-owned continuation handles use an odd word, outside GC object indices.
    ContRef(handle) => { lo: (handle << 1) | 1L, hi: 0L, }
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
      } else if decode_externref(raw) is Some(index) {
        ExternRef(index)
      } else if (raw & 1L) != 0L {
        I31((raw >> 1).to_int())
      } else {
        StructRef(((raw >> 1) - 1L).to_int())
      }
    ContRef
    | RefCont
    | RefContTyped(_)
    | RefNullContTyped(_)
    | NullContRef
    | RefNoCont =>
      if raw == @wasm_milkir.NULL_REF {
        Null
      } else {
        ContRef(raw >> 1)
      }
    ExnRef =>
      if raw == @wasm_milkir.NULL_REF {
        Null
      } else {
        ExnRef(((raw & 0x0FFF_FFFF_FFFF_FFFFL) >> 1).to_int())
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
