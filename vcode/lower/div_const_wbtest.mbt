// Tests for magic number division optimization

///|
/// Helper: compute high 32 bits of u32 * u32 -> u64
fn mulhi_u32(x : UInt, y : UInt) -> UInt {
  let x64 = x.to_uint64()
  let y64 = y.to_uint64()
  let r64 = x64 * y64
  (r64 >> 32).to_uint()
}

///|
/// Helper: compute high 64 bits of u64 * u64 -> u128
/// Since MoonBit doesn't have u128, we implement using Karatsuba-style splitting
fn mulhi_u64(x : UInt64, y : UInt64) -> UInt64 {
  let x_lo = x & 0xFFFFFFFFUL
  let x_hi = x >> 32
  let y_lo = y & 0xFFFFFFFFUL
  let y_hi = y >> 32
  let lo_lo = x_lo * y_lo
  let lo_hi = x_lo * y_hi
  let hi_lo = x_hi * y_lo
  let hi_hi = x_hi * y_hi
  let mid = (lo_lo >> 32) + (lo_hi & 0xFFFFFFFFUL) + (hi_lo & 0xFFFFFFFFUL)
  hi_hi + (lo_hi >> 32) + (hi_lo >> 32) + (mid >> 32)
}

///|
/// Helper: compute high 32 bits of signed i32 * i32 -> i64
fn mulhi_s32(x : Int, y : Int) -> Int {
  let x64 = x.to_int64()
  let y64 = y.to_int64()
  let r64 = x64 * y64
  (r64 >> 32).to_int()
}

///|
/// Helper: compute high 64 bits of signed i64 * i64 -> i128
fn mulhi_s64(x : Int64, y : Int64) -> Int64 {
  // Use unsigned mulhi and adjust for sign
  let xu = x.reinterpret_as_uint64()
  let yu = y.reinterpret_as_uint64()
  let mut result = mulhi_u64(xu, yu).reinterpret_as_int64()
  // Adjust for signed multiplication
  if x < 0L {
    result = result - y
  }
  if y < 0L {
    result = result - x
  }
  result
}

///|
/// Evaluate unsigned 32-bit division using magic numbers
fn eval_magic_u32(n : UInt, magic : MagicU32) -> UInt {
  let mut q = mulhi_u32(n, magic.mul_by)
  if magic.do_add {
    let mut t = n - q
    t = t >> 1
    t = t + q
    q = t >> (magic.shift_by - 1)
  } else {
    q = q >> magic.shift_by
  }
  q
}

///|
/// Evaluate unsigned 64-bit division using magic numbers
fn eval_magic_u64(n : UInt64, magic : MagicU64) -> UInt64 {
  let mut q = mulhi_u64(n, magic.mul_by)
  if magic.do_add {
    let mut t = n - q
    t = t >> 1
    t = t + q
    q = t >> (magic.shift_by - 1)
  } else {
    q = q >> magic.shift_by
  }
  q
}

///|
/// Evaluate signed 32-bit division using magic numbers
fn eval_magic_s32(n : Int, d : Int, magic : MagicS32) -> Int {
  let mut q = mulhi_s32(n, magic.mul_by)
  if d > 0 && magic.mul_by < 0 {
    q = q + n
  } else if d < 0 && magic.mul_by > 0 {
    q = q - n
  }
  q = q >> magic.shift_by
  let t = q.reinterpret_as_uint() >> 31
  q + t.reinterpret_as_int()
}

///|
/// Evaluate signed 64-bit division using magic numbers
fn eval_magic_s64(n : Int64, d : Int64, magic : MagicS64) -> Int64 {
  let mut q = mulhi_s64(n, magic.mul_by)
  if d > 0L && magic.mul_by < 0L {
    q = q + n
  } else if d < 0L && magic.mul_by > 0L {
    q = q - n
  }
  q = q >> magic.shift_by
  let t = q.reinterpret_as_uint64() >> 63
  q + t.reinterpret_as_int64()
}

///|
test "magic_u32 basic" {
  // Test division by 3
  let magic3 = magic_u32(3U)
  inspect(eval_magic_u32(0U, magic3), content="0")
  inspect(eval_magic_u32(3U, magic3), content="1")
  inspect(eval_magic_u32(6U, magic3), content="2")
  inspect(eval_magic_u32(9U, magic3), content="3")
  inspect(eval_magic_u32(100U, magic3), content="33")
  inspect(eval_magic_u32(1000U, magic3), content="333")
  // Test division by 7
  let magic7 = magic_u32(7U)
  inspect(eval_magic_u32(0U, magic7), content="0")
  inspect(eval_magic_u32(7U, magic7), content="1")
  inspect(eval_magic_u32(14U, magic7), content="2")
  inspect(eval_magic_u32(21U, magic7), content="3")
  inspect(eval_magic_u32(100U, magic7), content="14")
  // Test division by 10
  let magic10 = magic_u32(10U)
  inspect(eval_magic_u32(0U, magic10), content="0")
  inspect(eval_magic_u32(10U, magic10), content="1")
  inspect(eval_magic_u32(100U, magic10), content="10")
  inspect(eval_magic_u32(1000U, magic10), content="100")
  inspect(eval_magic_u32(12345U, magic10), content="1234")
}

///|
test "magic_u64 basic" {
  // Test division by 3
  let magic3 = magic_u64(3UL)
  inspect(eval_magic_u64(0UL, magic3), content="0")
  inspect(eval_magic_u64(3UL, magic3), content="1")
  inspect(eval_magic_u64(6UL, magic3), content="2")
  inspect(eval_magic_u64(1000000UL, magic3), content="333333")
  // Test division by 10
  let magic10 = magic_u64(10UL)
  inspect(eval_magic_u64(0UL, magic10), content="0")
  inspect(eval_magic_u64(10UL, magic10), content="1")
  inspect(eval_magic_u64(1000000UL, magic10), content="100000")
  inspect(eval_magic_u64(12345678901234UL, magic10), content="1234567890123")
}

///|
test "magic_s32 basic" {
  // Test division by 3
  let magic3 = magic_s32(3)
  inspect(eval_magic_s32(0, 3, magic3), content="0")
  inspect(eval_magic_s32(3, 3, magic3), content="1")
  inspect(eval_magic_s32(9, 3, magic3), content="3")
  inspect(eval_magic_s32(-3, 3, magic3), content="-1")
  inspect(eval_magic_s32(-9, 3, magic3), content="-3")
  inspect(eval_magic_s32(100, 3, magic3), content="33")
  inspect(eval_magic_s32(-100, 3, magic3), content="-33")
  // Test division by -3
  let magic_neg3 = magic_s32(-3)
  inspect(eval_magic_s32(9, -3, magic_neg3), content="-3")
  inspect(eval_magic_s32(-9, -3, magic_neg3), content="3")
  // Test division by 7
  let magic7 = magic_s32(7)
  inspect(eval_magic_s32(14, 7, magic7), content="2")
  inspect(eval_magic_s32(-14, 7, magic7), content="-2")
}

///|
test "magic_s64 basic" {
  // Test division by 3
  let magic3 = magic_s64(3L)
  inspect(eval_magic_s64(0L, 3L, magic3), content="0")
  inspect(eval_magic_s64(9L, 3L, magic3), content="3")
  inspect(eval_magic_s64(-9L, 3L, magic3), content="-3")
  inspect(eval_magic_s64(1000000L, 3L, magic3), content="333333")
  // Test division by -7
  let magic_neg7 = magic_s64(-7L)
  inspect(eval_magic_s64(14L, -7L, magic_neg7), content="-2")
  inspect(eval_magic_s64(-14L, -7L, magic_neg7), content="2")
}

///|
test "magic_u32 edge cases" {
  // Test large divisors
  let magic_large = magic_u32(0x7FFFFFFFU)
  inspect(eval_magic_u32(0x7FFFFFFFU, magic_large), content="1")
  inspect(eval_magic_u32(0xFFFFFFFEU, magic_large), content="2")
  // Test with remainders
  let magic5 = magic_u32(5U)
  inspect(eval_magic_u32(4U, magic5), content="0")
  inspect(eval_magic_u32(5U, magic5), content="1")
  inspect(eval_magic_u32(9U, magic5), content="1")
  inspect(eval_magic_u32(10U, magic5), content="2")
}
