// Bit conversion traits for converting between numeric types and Int64 bit patterns
// Used for JIT calls, FFI, and low-level bit manipulation

///|
pub trait ToInt64 {
  to_int64_bits(Self) -> Int64
}

///|
pub impl ToInt64 for Int64 with to_int64_bits(self) {
  self
}

///|
pub impl ToInt64 for Int with to_int64_bits(self) {
  self.to_int64()
}

///|
pub impl ToInt64 for Double with to_int64_bits(self) {
  self.reinterpret_as_int64()
}

///|
pub impl ToInt64 for Float with to_int64_bits(self) {
  self.reinterpret_as_int().to_int64()
}

///|
pub trait FromInt64 {
  from_int64_bits(Int64) -> Self
}

///|
pub impl FromInt64 for Int64 with from_int64_bits(v) {
  v
}

///|
pub impl FromInt64 for Int with from_int64_bits(v) {
  v.to_int()
}

///|
pub impl FromInt64 for Double with from_int64_bits(v) {
  v.reinterpret_as_double()
}

///|
pub impl FromInt64 for Float with from_int64_bits(v) {
  Float::reinterpret_from_int(v.to_int())
}

// ============ Hex Conversion Utilities ============

///|
/// Convert a single byte (0-255) to a 2-character hex string
pub fn to_hex_byte(b : Int) -> String {
  let hi = (b >> 4) & 0xF
  let lo = b & 0xF
  let hi_c = if hi < 10 {
    (hi + 48).unsafe_to_char() // '0' = 48
  } else {
    (hi - 10 + 97).unsafe_to_char() // 'a' = 97
  }
  let lo_c = if lo < 10 {
    (lo + 48).unsafe_to_char()
  } else {
    (lo - 10 + 97).unsafe_to_char()
  }
  hi_c.to_string() + lo_c.to_string()
}

///|
/// Convert a 16-bit value to a 4-character hex string
pub fn to_hex_u16(n : Int) -> String {
  to_hex_byte((n >> 8) & 0xFF) + to_hex_byte(n & 0xFF)
}

///|
/// Convert an integer to a variable-length hex string (no leading zeros)
pub fn int_to_hex(n : Int) -> String {
  if n == 0 {
    return "0"
  }
  let mut result = ""
  let mut val = n
  while val > 0 {
    let digit = val & 0xF
    let c = if digit < 10 {
      (digit + 48).unsafe_to_char() // '0' = 48
    } else {
      (digit - 10 + 97).unsafe_to_char() // 'a' = 97
    }
    result = c.to_string() + result
    val = val >> 4
  }
  result
}
