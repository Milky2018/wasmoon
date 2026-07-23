///|
fn lowest_set_bit(value : UInt64) -> UInt64 {
  if value == 0UL {
    return 0UL
  }
  1UL << value.ctz()
}

///|
fn immediate_period_multiplier(period : Int) -> UInt64? {
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
fn logical_immediate_bits(value : UInt64, width : GprWidth) -> Int? {
  let mut current = if width == W64 {
    value
  } else {
    let low = value & 0xFFFFFFFFUL
    (low << 32) | low
  }
  let mut inverted = false
  if (current & 1UL) == 1UL {
    current = current.lnot()
    inverted = true
  }
  if current == 0UL {
    return None
  }
  let a = lowest_set_bit(current)
  let value_plus_a = current + a
  let b = lowest_set_bit(value_plus_a)
  let c = lowest_set_bit(value_plus_a - b)
  let (period, leading_a, n, mask) = if c != 0UL {
    let leading_a = a.clz()
    let period = leading_a - c.clz()
    if period <= 0 || period >= 64 {
      return None
    }
    (period, leading_a, 0, (1UL << period) - 1UL)
  } else {
    (64, a.clz(), 1, 0xFFFFFFFFFFFFFFFFUL)
  }
  if period <= 0 || (period & (period - 1)) != 0 {
    return None
  }
  guard immediate_period_multiplier(period) is Some(multiplier) else {
    return None
  }
  let stretch = b - a
  if (stretch & mask.lnot()) != 0UL || current != stretch * multiplier {
    return None
  }
  let leading_b = if b == 0UL { -1 } else { b.clz() }
  let mut size = leading_a - leading_b
  let rotation = if inverted {
    size = period - size
    (leading_b + 1) & (period - 1)
  } else {
    (leading_a + 1) & (period - 1)
  }
  let imms = (-(period * 2) | (size - 1)) & 63
  Some(((n & 1) << 12) | ((rotation & 63) << 6) | imms)
}

///|
fn add_sub_immediate_shift(bits : UInt64) -> Int? {
  if bits <= 4095UL {
    Some(0)
  } else if (bits & 0xFFFUL) == 0UL && bits >> 12 <= 4095UL {
    Some(12)
  } else {
    None
  }
}

///|
fn valid_int_binary_immediate(
  width : GprWidth,
  operation : AArch64IntBinary,
  bits : UInt64,
) -> Bool {
  match operation {
    Add | Sub => add_sub_immediate_shift(bits) is Some(_)
    And | Orr | Eor => logical_immediate_bits(bits, width) is Some(_)
    Mul | Sdiv | Udiv => false
  }
}

///|
fn encode_int_binary_immediate(
  width : GprWidth,
  operation : AArch64IntBinary,
  bits : UInt64,
  destination : @vcode.PhysicalReg,
  source : @vcode.PhysicalReg,
) -> UInt {
  let base = match (width, operation) {
    (W32, Add) => 0x11000000U
    (W64, Add) => 0x91000000U
    (W32, Sub) => 0x51000000U
    (W64, Sub) => 0xD1000000U
    (W32, And) => 0x12000000U
    (W64, And) => 0x92000000U
    (W32, Orr) => 0x32000000U
    (W64, Orr) => 0xB2000000U
    (W32, Eor) => 0x52000000U
    (W64, Eor) => 0xD2000000U
    _ => abort("invalid AArch64 integer immediate operation")
  }
  let encoded = match operation {
    Add | Sub => {
      let shift = add_sub_immediate_shift(bits).unwrap()
      let immediate = if shift == 0 { bits } else { bits >> 12 }
      (immediate.to_uint() << 10) | (if shift == 12 { 1U << 22 } else { 0U })
    }
    And | Orr | Eor =>
      logical_immediate_bits(bits, width).unwrap().reinterpret_as_uint() << 10
    _ => abort("invalid AArch64 integer immediate operation")
  }
  base | encoded | (reg_bits(source) << 5) | reg_bits(destination)
}
