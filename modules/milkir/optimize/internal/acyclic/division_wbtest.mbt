///|
fn reference_high_product(a : UInt64, b : UInt64) -> UInt64 {
  let mask = 0xFFFFFFFFUL
  let low = (a & mask) * (b & mask)
  let middle = (a >> 32) * (b & mask) + (low >> 32)
  let next = (a & mask) * (b >> 32) + (middle & mask)
  (a >> 32) * (b >> 32) + (middle >> 32) + (next >> 32)
}

///|
test "constant reciprocal generation agrees with independent unsigned division" {
  let mut seed = 0x9E3779B97F4A7C15UL
  for width in [32, 64] {
    let mask = if width == 32 { 0xFFFFFFFFUL } else { 0xFFFFFFFFFFFFFFFFUL }
    for _ in 0..<200 {
      seed = seed * 6364136223846793005UL + 1UL
      let candidate = (seed & mask) | 1UL
      let divisor = if candidate < 3UL { 3UL } else { candidate }
      let (magic, shift, add) = unsigned_division_magic(divisor, width)
      for i in 0..<100 {
        seed = seed * 6364136223846793005UL + 1UL
        let n = if i == 0 {
          mask
        } else if i == 1 {
          divisor
        } else if i == 2 {
          divisor - 1UL
        } else {
          seed & mask
        }
        let high = if width == 32 {
          (n * magic) >> 32
        } else {
          reference_high_product(n, magic)
        }
        let q = (if add { ((n - high) >> 1) + high } else { high }) >> shift
        assert_eq(
          q,
          n / divisor,
          msg="width=\{width}, divisor=\{divisor}, n=\{n}",
        )
      }
    }
  }
}

///|
test "signed reciprocal bounds preserve truncation toward zero" {
  let mut seed = 0xA0761D6478BD642FUL
  for width in [32, 64] {
    let mask = if width == 32 { 0x7FFFFFFFUL } else { 0x7FFFFFFFFFFFFFFFUL }
    for _ in 0..<200 {
      seed = seed * 6364136223846793005UL + 1UL
      let candidate = (seed & mask) | 1UL
      let divisor = if candidate < 3UL { 3UL } else { candidate }
      let (magic, shift) = signed_division_magic(divisor, width)
      let multiplier = if width == 32 {
        magic.to_int().to_int64()
      } else {
        magic.reinterpret_as_int64()
      }
      for i in 0..<100 {
        seed = seed * 6364136223846793005UL + 1UL
        let bits = if i == 0 {
          1UL << (width - 1)
        } else if i == 1 {
          mask
        } else {
          seed
        }
        let n = if width == 32 {
          bits.to_int().to_int64()
        } else {
          bits.reinterpret_as_int64()
        }
        let mut q = if width == 32 {
          (n * multiplier) >> 32
        } else {
          let a = n.reinterpret_as_uint64()
          let b = multiplier.reinterpret_as_uint64()
          (reference_high_product(a, b) -
          (if n < 0L { b } else { 0UL }) -
          (if multiplier < 0L { a } else { 0UL })).reinterpret_as_int64()
        }
        if multiplier < 0L {
          q += n
        }
        if width == 32 {
          q = q.to_int().to_int64()
        }
        q = q >> shift
        q += if q < 0L { 1L } else { 0L }
        assert_eq(
          q,
          n / divisor.reinterpret_as_int64(),
          msg="width=\{width}, divisor=\{divisor}, n=\{n}",
        )
      }
    }
  }
}
