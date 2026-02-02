// AArch64 immediates (bitmask/logical form)
// Ported from Cranelift (ImmLogic::maybe_from_u64), originally from VIXL.

///|
fn lowest_set_bit(value : UInt64) -> UInt64 {
  if value == 0UL {
    return 0UL
  }
  let bit = value.ctz()
  if bit < 0 || bit >= 64 {
    return 0UL
  }
  1UL << bit
}

///|
fn is_power_of_two_i(value : Int) -> Bool {
  if value <= 0 {
    return false
  }
  (value & (value - 1)) == 0
}

///|
fn multiplier_for_period(period : Int) -> UInt64? {
  match period {
    64 => Some(0x0000000000000001UL)
    32 => Some(0x0000000100000001UL)
    16 => Some(0x0001000100010001UL)
    8 => Some(0x0101010101010101UL)
    4 => Some(0x1111111111111111UL)
    2 => Some(0x5555555555555555UL)
    _ => None
  }
}

///|
/// AArch64 logical immediates are encoded as N:immr:imms (1:6:6), placed at bits 22..10.
///
/// `is_64` selects whether the encoding is for a 64-bit or 32-bit instruction.
/// For 32-bit, we follow Cranelift: duplicate the low 32 bits into both halves of a u64,
/// then run the same encoder.
pub fn aarch64_logic_imm_enc_bits(value : Int64, is_64 : Bool) -> Int? {
  let original = value.reinterpret_as_uint64()
  let mut v = if is_64 {
    original
  } else {
    let v32 = original & 0xFFFFFFFFUL
    (v32 << 32) | v32
  }

  // If the low bit is set, invert to avoid the rotated-wrap-around case.
  let mut inverted = false
  if (v & 1UL) == 1UL {
    v = v.lnot()
    inverted = true
  }
  if v == 0UL {
    return None
  }
  let a = lowest_set_bit(v)
  if a == 0UL {
    return None
  }
  let value_plus_a = v + a
  let b = lowest_set_bit(value_plus_a)
  let value_plus_a_minus_b = value_plus_a - b
  let c = lowest_set_bit(value_plus_a_minus_b)
  let mut period = 0
  let mut clz_a = 0
  let mut out_n = 0
  let mut mask = 0UL
  if c != 0UL {
    clz_a = a.clz()
    let clz_c = c.clz()
    period = clz_a - clz_c
    out_n = 0
    if period <= 0 || period >= 64 {
      return None
    }
    mask = (1UL << period) - 1UL
  } else {
    // Single run: period is 64 and N is 1.
    period = 64
    clz_a = a.clz()
    out_n = 1
    mask = 0xFFFFFFFFFFFFFFFFUL
  }
  if !is_power_of_two_i(period) {
    return None
  }
  guard multiplier_for_period(period) is Some(multiplier) else { return None }
  let stretch = b - a
  if (stretch & mask.lnot()) != 0UL {
    return None
  }
  let candidate = stretch * multiplier
  if v != candidate {
    return None
  }

  // Count set bits in the base stretch.
  let clz_b = if b == 0UL { -1 } else { b.clz() }
  let mut s = clz_a - clz_b
  let mut r = 0
  if inverted {
    s = period - s
    r = (clz_b + 1) & (period - 1)
  } else {
    r = (clz_a + 1) & (period - 1)
  }

  // Encode imms: ((2*-period) | (s-1)) & 0x3f
  let imms = (-(period * 2) | (s - 1)) & 63
  let immr = r & 63
  let n = out_n & 1
  Some((n << 12) | (immr << 6) | imms)
}
