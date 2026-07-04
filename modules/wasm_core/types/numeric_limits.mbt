///|
/// Signed i8 max (0x7F).
pub const I8_MAX : Int = 0x7F

///|
/// Unsigned i8 max (0xFF).
pub const U8_MAX : Int = 0xFF

///|
/// ASCII DEL (127), the first non-printable codepoint after printable ASCII.
pub const ASCII_DEL : Int = 0x7F

///|
/// IEEE-754 f32 exponent bias.
pub const F32_EXP_BIAS : Int = 0x7F

///|
/// IEEE-754 f32 all-ones exponent field (Inf/NaN).
pub const F32_EXP_INF_NAN : Int = 0xFF

///|
/// Canonical f32 NaN bit-pattern used by WebAssembly tests.
pub const F32_CANONICAL_NAN_BITS : Int = 0x7FC00000

///|
/// Signed i32 minimum value.
pub const I32_MIN : Int = -0x80000000

///|
/// Signed i32 maximum value.
pub const I32_MAX : Int = 0x7FFFFFFF

///|
/// Signed i32 minimum value as f64.
pub const I32_MIN_F64 : Double = -2147483648.0

///|
/// Signed i32 maximum value as f64.
pub const I32_MAX_F64 : Double = 2147483647.0

///|
/// Signed i32 minimum value as f32.
pub const I32_MIN_F32 : Float = -2147483648.0

///|
/// Signed i32 maximum value as f32.
pub const I32_MAX_F32 : Float = 2147483647.0

///|
/// Unsigned i32 maximum value.
pub const U32_MAX : UInt = 0xFFFFFFFFU

///|
/// Unsigned i32 maximum value as f64.
pub const U32_MAX_F64 : Double = 4294967295.0

///|
/// Unsigned i32 maximum value as f32.
pub const U32_MAX_F32 : Float = 4294967295.0

///|
/// Unsigned i32 modulus (2^32) as i64.
pub const U32_MODULUS_I64 : Int64 = 0x100000000L

///|
/// Unsigned i32 modulus (2^32) as f64.
pub const U32_MODULUS_F64 : Double = 4294967296.0

///|
/// Unsigned i32 modulus (2^32) as f32.
pub const U32_MODULUS_F32 : Float = 4294967296.0

///|
/// WebAssembly page size in bytes.
pub const WASM_PAGE_SIZE_BYTES : Int64 = 0x10000L

///|
/// One mebibyte in bytes.
pub const ONE_MIB_BYTES : Int = 1 << 20

///|
/// Sixteen mebibytes in bytes.
pub const SIXTEEN_MIB_BYTES : Int64 = 0x1000000L
