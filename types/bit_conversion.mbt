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
