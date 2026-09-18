///|
fn fold_pure_integer_binary(
  op : @milkir.IntBinaryOp,
  a : Int64,
  b : Int64,
  width : Int,
) -> Int64? {
  let a = sign_extend_integer(a, width)
  let b = sign_extend_integer(b, width)
  let amount = normalized_shift(b, width)
  let unsigned = a.reinterpret_as_uint64() &
    integer_mask(width).reinterpret_as_uint64()
  let result = match op {
    Add => a + b
    Sub => a - b
    Mul => a * b
    And => a & b
    Or => a | b
    Xor => a ^ b
    ShiftLeft => a << amount
    SignedShiftRight => a >> amount
    UnsignedShiftRight => (unsigned >> amount).reinterpret_as_int64()
    RotateLeft =>
      if amount == 0 {
        a
      } else {
        ((unsigned << amount) | (unsigned >> (width - amount))).reinterpret_as_int64()
      }
    RotateRight =>
      if amount == 0 {
        a
      } else {
        ((unsigned >> amount) | (unsigned << (width - amount))).reinterpret_as_int64()
      }
    _ => return None
  }
  Some(sign_extend_integer(result, width))
}

///|
fn fold_integer_unary(op : @milkir.IntUnaryOp, a : Int64, width : Int) -> Int64 {
  let a = a.reinterpret_as_uint64() &
    integer_mask(width).reinterpret_as_uint64()
  match op {
    Not =>
      sign_extend_integer(
        (a ^ integer_mask(width).reinterpret_as_uint64()).reinterpret_as_int64(),
        width,
      )
    CountLeadingZeros => (a.clz() - (64 - width)).to_int64()
    CountTrailingZeros => (if a == 0UL { width } else { a.ctz() }).to_int64()
    PopulationCount => a.popcnt().to_int64()
  }
}

///|
fn OptimizerSession::rewrite_integer_unary(
  self : OptimizerSession,
  inst : @milkir.Inst,
  op : @milkir.IntUnaryOp,
  prefix : Array[@milkir.Inst],
) -> Bool {
  guard inst.operands is [source] && integer_width(source.ty) is Some(width) else {
    return false
  }
  if self.int_constant(source) is Some(value) {
    return self.replace_with_constant(
      inst,
      fold_integer_unary(op, value, width),
    )
  }
  if op != Not {
    return false
  }
  guard self.definition(source) is Some(inner) else { return false }
  if inner.opcode is Scalar(IntUnary(Not)) && inner.operands is [original] {
    return self.replace_with_alias(inst, original)
  }
  if inner.operands is [a, b] &&
    self.int_constant(b) is Some(c) &&
    (
      (inner.opcode is Scalar(IntBinary(Sub)) && c == 1L) ||
      (inner.opcode is Scalar(IntBinary(Add)) && c == -1L)
    ) {
    let marker = self.begin_candidates()
    if self.stage_pure_candidate(Scalar(IntConst(0L)), [], source.ty)
      is Some(zero) {
      self.commit_candidates(marker, prefix)
      return self.replace_binary(inst, Sub, zero, a)
    }
    self.discard_candidates(marker)
  }
  false
}
