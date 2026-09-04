// Bit-preserving float simplification. Arithmetic NaNs stay at runtime;
// sign operations work on bits and never quiet a signaling NaN.

///|
fn OptimizerSession::float_bits(
  self : OptimizerSession,
  value : Value,
) -> UInt64? {
  match self.definition(value) {
    Some({ opcode: Scalar(FloatConst32(bits)), .. }) => Some(bits.to_uint64())
    Some({ opcode: Scalar(FloatConst64(bits)), .. }) => Some(bits)
    _ => None
  }
}

///|
fn OptimizerSession::replace_float_bits(
  _self : OptimizerSession,
  inst : Inst,
  ty : Type,
  bits : UInt64,
) -> Bool {
  inst.opcode = if ty == F32 {
    Scalar(FloatConst32(bits.to_uint()))
  } else {
    Scalar(FloatConst64(bits))
  }
  inst.operands.clear()
  true
}

///|
fn nearest_even_float(value : Double) -> Double {
  if value.is_inf() || value == 0.0 || value.abs() >= 4503599627370496.0 {
    return value
  }
  let lower = value.floor()
  let fraction = value - lower
  let rounded = if fraction < 0.5 {
    lower
  } else if fraction > 0.5 {
    lower + 1.0
  } else if (lower.to_int64() & 1L) == 0L {
    lower
  } else {
    lower + 1.0
  }
  if rounded == 0.0 && value < 0.0 {
    -0.0
  } else {
    rounded
  }
}

///|
fn OptimizerSession::rewrite_float_unary(
  self : OptimizerSession,
  inst : Inst,
  op : FloatUnaryOp,
) -> Bool {
  guard inst.operands is [source] else { return false }
  if self.float_bits(source) is Some(bits) {
    let sign = if source.ty == F32 {
      0x80000000UL
    } else {
      0x8000000000000000UL
    }
    if op == Neg {
      return self.replace_float_bits(inst, source.ty, bits ^ sign)
    }
    if op == Abs {
      return self.replace_float_bits(inst, source.ty, bits & (sign - 1UL))
    }
    let value = if source.ty == F32 {
      Float::reinterpret_from_uint(bits.to_uint()).to_double()
    } else {
      bits.reinterpret_as_double()
    }
    if value.is_nan() {
      return false
    }
    let result = match op {
      Sqrt => value.sqrt()
      Ceil => value.ceil()
      Floor => value.floor()
      Trunc => value.trunc()
      Nearest => nearest_even_float(value)
      _ => return false
    }
    if result.is_nan() {
      return false
    }
    let bits = if source.ty == F32 {
      Float::from_double(result).reinterpret_as_uint().to_uint64()
    } else {
      result.reinterpret_as_uint64()
    }
    return self.replace_float_bits(inst, source.ty, bits)
  }
  guard self.definition(source) is Some(inner) &&
    inner.opcode is Scalar(FloatUnary(inner_op)) &&
    inner.operands is [original] else {
    return false
  }
  match (op, inner_op) {
    (Neg, Neg) => self.replace_with_alias(inst, original)
    (Abs, Abs) => self.replace_with_alias(inst, source)
    (Abs, Neg) => {
      inst.operands[0] = original
      true
    }
    _ => false
  }
}

///|
fn OptimizerSession::rewrite_float_minmax(
  self : OptimizerSession,
  inst : Inst,
  op : FloatBinaryOp,
) -> Bool {
  guard op is (Min | Max) &&
    inst.operands is [a, b] &&
    self.float_bits(a) is Some(abits) &&
    self.float_bits(b) is Some(bbits) else {
    return false
  }
  let av = if a.ty == F32 {
    Float::reinterpret_from_uint(abits.to_uint()).to_double()
  } else {
    abits.reinterpret_as_double()
  }
  let bv = if b.ty == F32 {
    Float::reinterpret_from_uint(bbits.to_uint()).to_double()
  } else {
    bbits.reinterpret_as_double()
  }
  if av.is_nan() || bv.is_nan() {
    return false
  }
  let bits = if av == 0.0 && bv == 0.0 {
    if op == Min {
      abits | bbits
    } else {
      abits & bbits
    }
  } else if (if op == Min { av < bv } else { av > bv }) {
    abits
  } else {
    bbits
  }
  self.replace_float_bits(inst, a.ty, bits)
}
