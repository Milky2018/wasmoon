// Magic number generation for division-by-constants optimization
// Based on "Hacker's Delight" by Henry Warren, 2003

///|
/// Magic numbers for unsigned 32-bit division
priv struct MagicU32 {
  mul_by : UInt
  do_add : Bool
  shift_by : Int
}

///|
/// Magic numbers for unsigned 64-bit division
priv struct MagicU64 {
  mul_by : UInt64
  do_add : Bool
  shift_by : Int
}

///|
/// Magic numbers for signed 32-bit division
priv struct MagicS32 {
  mul_by : Int
  shift_by : Int
}

///|
/// Magic numbers for signed 64-bit division
priv struct MagicS64 {
  mul_by : Int64
  shift_by : Int
}

///|
/// Compute magic numbers for unsigned 32-bit division by constant d
/// Requires: d != 0 && d != 1
fn magic_u32(d : UInt) -> MagicU32 {
  let mut do_add = false
  let mut p = 31
  // nc = (2^32 - 1) - (2^32 - 1) % d = largest multiple of d <= 2^32 - 1
  let nc = 0xFFFFFFFFU - (0U - d) % d
  let mut q1 = 0x80000000U / nc
  let mut r1 = 0x80000000U - q1 * nc
  let mut q2 = 0x7FFFFFFFU / d
  let mut r2 = 0x7FFFFFFFU - q2 * d
  while true {
    p = p + 1
    if r1 >= nc - r1 {
      q1 = 2U * q1 + 1U
      r1 = 2U * r1 - nc
    } else {
      q1 = 2U * q1
      r1 = 2U * r1
    }
    if r2 + 1U >= d - r2 {
      if q2 >= 0x7FFFFFFFU {
        do_add = true
      }
      q2 = 2U * q2 + 1U
      r2 = 2U * r2 + 1U - d
    } else {
      if q2 >= 0x80000000U {
        do_add = true
      }
      q2 = 2U * q2
      r2 = 2U * r2 + 1U
    }
    let delta = d - 1U - r2
    if not(p < 64 && (q1 < delta || (q1 == delta && r1 == 0U))) {
      break
    }
  }
  { mul_by: q2 + 1U, do_add, shift_by: p - 32 }
}

///|
/// Compute magic numbers for unsigned 64-bit division by constant d
/// Requires: d != 0 && d != 1
fn magic_u64(d : UInt64) -> MagicU64 {
  let mut do_add = false
  let mut p = 63
  let nc = 0xFFFFFFFFFFFFFFFFUL - (0UL - d) % d
  let mut q1 = 0x8000000000000000UL / nc
  let mut r1 = 0x8000000000000000UL - q1 * nc
  let mut q2 = 0x7FFFFFFFFFFFFFFFUL / d
  let mut r2 = 0x7FFFFFFFFFFFFFFFUL - q2 * d
  while true {
    p = p + 1
    if r1 >= nc - r1 {
      q1 = 2UL * q1 + 1UL
      r1 = 2UL * r1 - nc
    } else {
      q1 = 2UL * q1
      r1 = 2UL * r1
    }
    if r2 + 1UL >= d - r2 {
      if q2 >= 0x7FFFFFFFFFFFFFFFUL {
        do_add = true
      }
      q2 = 2UL * q2 + 1UL
      r2 = 2UL * r2 + 1UL - d
    } else {
      if q2 >= 0x8000000000000000UL {
        do_add = true
      }
      q2 = 2UL * q2
      r2 = 2UL * r2 + 1UL
    }
    let delta = d - 1UL - r2
    if not(p < 128 && (q1 < delta || (q1 == delta && r1 == 0UL))) {
      break
    }
  }
  { mul_by: q2 + 1UL, do_add, shift_by: p - 64 }
}

///|
/// Compute magic numbers for signed 32-bit division by constant d
/// Requires: d != -1 && d != 0 && d != 1
fn magic_s32(d : Int) -> MagicS32 {
  let two31 = 0x80000000U
  let mut p = 31
  let ad = if d < 0 {
    (0 - d).reinterpret_as_uint()
  } else {
    d.reinterpret_as_uint()
  }
  let t = two31 + (d.reinterpret_as_uint() >> 31)
  let anc = t - 1U - t % ad
  let mut q1 = two31 / anc
  let mut r1 = two31 - q1 * anc
  let mut q2 = two31 / ad
  let mut r2 = two31 - q2 * ad
  while true {
    p = p + 1
    q1 = 2U * q1
    r1 = 2U * r1
    if r1 >= anc {
      q1 = q1 + 1U
      r1 = r1 - anc
    }
    q2 = 2U * q2
    r2 = 2U * r2
    if r2 >= ad {
      q2 = q2 + 1U
      r2 = r2 - ad
    }
    let delta = ad - r2
    if not(q1 < delta || (q1 == delta && r1 == 0U)) {
      break
    }
  }
  let mul_by = if d < 0 {
    (0U - (q2 + 1U)).reinterpret_as_int()
  } else {
    (q2 + 1U).reinterpret_as_int()
  }
  { mul_by, shift_by: p - 32 }
}

///|
/// Compute magic numbers for signed 64-bit division by constant d
/// Requires: d != -1 && d != 0 && d != 1
fn magic_s64(d : Int64) -> MagicS64 {
  let two63 = 0x8000000000000000UL
  let mut p = 63
  let ad = if d < 0L {
    (0L - d).reinterpret_as_uint64()
  } else {
    d.reinterpret_as_uint64()
  }
  let t = two63 + (d.reinterpret_as_uint64() >> 63)
  let anc = t - 1UL - t % ad
  let mut q1 = two63 / anc
  let mut r1 = two63 - q1 * anc
  let mut q2 = two63 / ad
  let mut r2 = two63 - q2 * ad
  while true {
    p = p + 1
    q1 = 2UL * q1
    r1 = 2UL * r1
    if r1 >= anc {
      q1 = q1 + 1UL
      r1 = r1 - anc
    }
    q2 = 2UL * q2
    r2 = 2UL * r2
    if r2 >= ad {
      q2 = q2 + 1UL
      r2 = r2 - ad
    }
    let delta = ad - r2
    if not(q1 < delta || (q1 == delta && r1 == 0UL)) {
      break
    }
  }
  let mul_by = if d < 0L {
    (0UL - (q2 + 1UL)).reinterpret_as_int64()
  } else {
    (q2 + 1UL).reinterpret_as_int64()
  }
  { mul_by, shift_by: p - 64 }
}
