///|
/// Reciprocal division: return ceil(2^(width+shift)/divisor), with the
/// overflow-bit correction when the rounded reciprocal needs width+1 bits.
/// Long division at compile time avoids a host 128-bit arithmetic dependency.
fn unsigned_division_magic(
  divisor : UInt64,
  width : Int32,
) -> (UInt64, Int32, Bool) {
  let shift = 63 - divisor.clz()
  let mut remainder = 0UL
  let mut quotient = 0UL
  let mut bit = width + shift
  while bit >= 0 {
    let carry = remainder >> 63
    remainder = (remainder << 1) |
      (if bit == width + shift { 1UL } else { 0UL })
    if carry != 0UL || remainder >= divisor {
      remainder -= divisor
      if bit < width {
        quotient = quotient | (1UL << bit)
      }
    }
    bit -= 1
  }
  let add = divisor - remainder >= 1UL << shift
  if add {
    quotient *= 2UL
    let twice = remainder + remainder
    if twice >= divisor || twice < remainder {
      quotient += 1UL
    }
  }
  let mask = if width == 32 { 0xFFFFFFFFUL } else { 0xFFFFFFFFFFFFFFFFUL }
  ((quotient + 1UL) & mask, shift, add)
}

///|
/// Signed reciprocal search, stopping when the remainder bounds prove that
/// high multiplication plus a sign correction equals truncation toward zero.
fn signed_division_magic(divisor : UInt64, width : Int32) -> (UInt64, Int32) {
  let half = 1UL << (width - 1)
  let boundary = half - 1UL - half % divisor
  let mut q1 = half / boundary
  let mut r1 = half % boundary
  let mut q2 = half / divisor
  let mut r2 = half % divisor
  let mut power = width - 1
  while true {
    power += 1
    q1 *= 2UL
    r1 *= 2UL
    if r1 >= boundary {
      q1 += 1UL
      r1 -= boundary
    }
    q2 *= 2UL
    r2 *= 2UL
    if r2 >= divisor {
      q2 += 1UL
      r2 -= divisor
    }
    let delta = divisor - r2
    if q1 > delta || (q1 == delta && r1 != 0UL) {
      break
    }
  }
  let mask = if width == 32 { 0xFFFFFFFFUL } else { 0xFFFFFFFFFFFFFFFFUL }
  ((q2 + 1UL) & mask, power - width)
}

///|
fn OptimizerSession::divide_by_constant(
  self : OptimizerSession,
  inst : @milkir.Inst,
  op : @milkir.IntBinaryOp,
  prefix : Array[@milkir.Inst],
) -> Bool {
  guard inst.args is [numerator, divisor_value] &&
    inst.results is [result] &&
    self.int_constant(divisor_value) is Some(constant) &&
    integer_width(result.ty) is Some(width) else {
    return false
  }
  let mask = if width == 32 { 0xFFFFFFFFUL } else { 0xFFFFFFFFFFFFFFFFUL }
  let bits = constant.reinterpret_as_uint64() & mask
  if bits == 0UL {
    return false
  } // Retain the original divide-by-zero trap.
  let signed = op is (SignedDiv | SignedRem)
  if signed && bits == mask {
    if op == SignedRem {
      return self.replace_with_constant(inst, 0L)
    }
    return false // MIN / -1 retains its required overflow trap.
  }
  let negative = signed && bits >> (width - 1) != 0UL
  let divisor = if negative { (0UL - bits) & mask } else { bits }
  let marker = self.begin_candidates()
  fn binary(
    op : @milkir.IntBinaryOp,
    a : @milkir.Value,
    b : @milkir.Value,
  ) -> @milkir.Value {
    self.stage_pure_candidate(Scalar(IntBinary(op)), [a, b], result.ty).unwrap()
  }
  fn immediate(
    op : @milkir.IntBinaryOp,
    a : @milkir.Value,
    bits : UInt64,
  ) -> @milkir.Value {
    self
    .stage_int_binary_with_constant(
      op,
      a,
      result.ty,
      bits.reinterpret_as_int64(),
    )
    .unwrap()
  }
  if bits == 1UL {
    return if op is (SignedRem | UnsignedRem) {
      self.replace_with_constant(inst, 0L)
    } else {
      self.replace_with_alias(inst, numerator)
    }
  }
  fn high_multiply(magic : UInt64, signed : Bool) -> @milkir.Value {
    if width == 64 {
      return immediate(
        if signed {
          SignedMulHigh
        } else {
          UnsignedMulHigh
        },
        numerator,
        magic,
      )
    }
    let extended = self
      .stage_pure_candidate(
        Scalar(Convert(if signed { SignedExtend } else { UnsignedExtend })),
        [numerator],
        I64,
      )
      .unwrap()
    let constant = if signed {
      magic.to_int().to_int64()
    } else {
      magic.reinterpret_as_int64()
    }
    let multiplier = self
      .stage_pure_candidate(Scalar(IntConst(constant)), [], I64)
      .unwrap()
    let product = self
      .stage_pure_candidate(Scalar(IntBinary(Mul)), [extended, multiplier], I64)
      .unwrap()
    let high = self
      .stage_int_binary_with_constant(
        if signed {
          SignedShiftRight
        } else {
          UnsignedShiftRight
        },
        product,
        I64,
        32L,
      )
      .unwrap()
    self.stage_pure_candidate(Scalar(Convert(IntReduce)), [high], I32).unwrap()
  }
  let power_of_two = (divisor & (divisor - 1UL)) == 0UL
  let mut quotient = if signed {
    let value = if power_of_two {
      let sign = immediate(SignedShiftRight, numerator, (width - 1).to_uint64())
      let biased = binary(Add, numerator, immediate(And, sign, divisor - 1UL))
      immediate(SignedShiftRight, biased, (63 - divisor.clz()).to_uint64())
    } else {
      let (magic, shift) = signed_division_magic(divisor, width)
      let high = high_multiply(magic, true)
      let high = if magic >> (width - 1) != 0UL {
        binary(Add, high, numerator)
      } else {
        high
      }
      let value = if shift == 0 {
        high
      } else {
        immediate(SignedShiftRight, high, shift.to_uint64())
      }
      binary(
        Add,
        value,
        immediate(UnsignedShiftRight, value, (width - 1).to_uint64()),
      )
    }
    if negative {
      let zero = self
        .stage_pure_candidate(Scalar(IntConst(0L)), [], result.ty)
        .unwrap()
      binary(Sub, zero, value)
    } else {
      value
    }
  } else if power_of_two {
    immediate(UnsignedShiftRight, numerator, (63 - divisor.clz()).to_uint64())
  } else {
    let (magic, shift, add) = unsigned_division_magic(divisor, width)
    let high = high_multiply(magic, false)
    let high = if add {
      binary(
        Add,
        immediate(UnsignedShiftRight, binary(Sub, numerator, high), 1UL),
        high,
      )
    } else {
      high
    }
    if shift == 0 {
      high
    } else {
      immediate(UnsignedShiftRight, high, shift.to_uint64())
    }
  }
  if op is (SignedRem | UnsignedRem) {
    quotient = binary(Sub, numerator, binary(Mul, quotient, divisor_value))
  }
  self.commit_candidates(marker, prefix)
  self.replace_with_alias(inst, quotient)
}
