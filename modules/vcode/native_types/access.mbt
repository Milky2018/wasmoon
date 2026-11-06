///|
pub fn valid_scalar_load(
  width : AccessWidth,
  extension : LoadExtension,
  result_type : ValueType,
) -> Bool {
  match (result_type, width, extension) {
    (I32, W8 | W16, Signed | Unsigned) | (I32, W32, None) => true
    (I64, W8 | W16 | W32, Signed | Unsigned) | (I64, W64, None) => true
    (Ptr64 | GcRef64, W64, None) => true
    (F32, W32, None) | (F64, W64, None) => true
    _ => false
  }
}

///|
pub fn valid_scalar_store(width : AccessWidth, value_type : ValueType) -> Bool {
  match (value_type, width) {
    (I32, W8 | W16 | W32) => true
    (I64, W8 | W16 | W32 | W64) => true
    (Ptr64 | GcRef64, W64) => true
    (F32, W32) | (F64, W64) => true
    _ => false
  }
}

///|
pub fn valid_atomic_access(width : AccessWidth, ty : ValueType) -> Bool {
  match (ty, width) {
    (I32, W8 | W16 | W32) => true
    (I64, W8 | W16 | W32 | W64) => true
    _ => false
  }
}

///|
pub fn valid_scalar_bitcast(from : ValueType, to : ValueType) -> Bool {
  match (from, to) {
    (I32, I32 | F32) | (F32, I32 | F32) => true
    (I64, I64 | Ptr64 | F64)
    | (Ptr64, I64 | Ptr64 | F64)
    | (F64, I64 | Ptr64 | F64) => true
    _ => false
  }
}
