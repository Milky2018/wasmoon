// Shared reference encoding used by Wasm MilkIR lowering and runtime interop.

///|
/// Null reference value in the lowered reference representation.
pub const NULL_REF : Int64 = 0L

///|
/// Legacy sentinel used by older funcref index encodings.
///
/// Do not use this as a null reference value. Null references are encoded as
/// `NULL_REF` (=0). This value remains available for compatibility with older
/// index-form funcref code paths.
pub const FUNCREF_NULL_SENTINEL : Int64 = -1L

///|
/// Tag for externref values: bit 62 set.
pub const EXTERNREF_TAG : Int64 = 0x4000000000000000L

///|
/// Tag for funcref pointer values: bit 61 set.
pub const FUNCREF_TAG : Int64 = 0x2000000000000000L
