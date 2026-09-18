// Direct shift and rotate rewrites for the bounded acyclic optimizer.

///|
fn opposite_rotation(op : @milkir.IntBinaryOp) -> @milkir.IntBinaryOp? {
  match op {
    RotateLeft => Some(RotateRight)
    RotateRight => Some(RotateLeft)
    _ => None
  }
}

///|
fn OptimizerSession::rewrite_rotation(
  self : OptimizerSession,
  inst : @milkir.Inst,
  op : @milkir.IntBinaryOp,
  prefix : Array[@milkir.Inst],
) -> Bool {
  guard inst.operands is [rotated, amount] &&
    inst.first_result() is Some(result) &&
    integer_width(result.ty) is Some(width) &&
    self.definition(rotated) is Some(inner) &&
    inner.opcode is Scalar(IntBinary(inner_op)) &&
    inner.operands is [source, inner_amount] else {
    return false
  }
  if opposite_rotation(op) is Some(opposite) &&
    inner_op == opposite &&
    self.canonical_value(amount).id == self.canonical_value(inner_amount).id {
    return self.replace_with_alias(inst, source)
  }
  guard inner_op is (RotateLeft | RotateRight) &&
    self.has_single_use(rotated) &&
    self.int_constant(inner_amount) is Some(inner_constant) &&
    self.int_constant(amount) is Some(outer_constant) else {
    return false
  }
  let combined = (
      normalized_shift(outer_constant, width) +
      (if inner_op == op {
        normalized_shift(inner_constant, width)
      } else {
        -normalized_shift(inner_constant, width)
      })
    ) &
    (width - 1)
  if combined == 0 {
    return self.replace_with_alias(inst, source)
  }
  let marker = self.begin_candidates()
  guard self.stage_int_binary_with_constant(
      op,
      source,
      result.ty,
      combined.to_int64(),
    )
    is Some(replacement) else {
    self.discard_candidates(marker)
    return false
  }
  if !self.commit_candidates_if_cheaper(
      marker,
      pure_candidate_cost(inner.opcode) + pure_candidate_cost(inst.opcode),
      prefix,
    ) {
    return false
  }
  self.replace_with_alias(inst, replacement)
}

///|
fn low_bits_mask(bits : Int) -> Int64 {
  match bits {
    64 => -1L
    63 => 0x7FFFFFFFFFFFFFFFL
    _ => (1L << bits) - 1L
  }
}

///|
fn OptimizerSession::rewrite_rotate_pair(
  self : OptimizerSession,
  inst : @milkir.Inst,
  left : @milkir.Inst?,
  right : @milkir.Inst?,
  prefix : Array[@milkir.Inst],
) -> Bool {
  guard left is Some(l) &&
    right is Some(r) &&
    l.operands is [a, n] &&
    r.operands is [b, m] &&
    l.opcode is Scalar(IntBinary(lop)) &&
    r.opcode is Scalar(IntBinary(rop)) &&
    (
      (lop == ShiftLeft && rop == UnsignedShiftRight) ||
      (lop == UnsignedShiftRight && rop == ShiftLeft)
    ) &&
    self.same_value(a, b) &&
    integer_width(a.ty) is Some(width) &&
    self.int_constant(n) is Some(n) &&
    self.int_constant(m) is Some(m) else {
    return false
  }
  let n = normalized_shift(n, width)
  let m = normalized_shift(m, width)
  guard n + m == width else { return false }
  let marker = self.begin_candidates()
  if self.stage_pure_candidate(
      Scalar(IntConst((if lop == ShiftLeft { n } else { m }).to_int64())),
      [],
      a.ty,
    )
    is Some(amount) {
    self.commit_candidates(marker, prefix)
    return self.replace_binary(inst, RotateLeft, a, amount)
  }
  self.discard_candidates(marker)
  false
}

///|
fn OptimizerSession::factor_common_shift(
  self : OptimizerSession,
  inst : @milkir.Inst,
  op : @milkir.IntBinaryOp,
  prefix : Array[@milkir.Inst],
) -> Bool {
  guard inst.operands is [left, right] &&
    self.has_single_use(left) &&
    self.has_single_use(right) &&
    self.definition(left) is Some(l) &&
    self.definition(right) is Some(r) &&
    l.opcode is Scalar(IntBinary(ShiftLeft)) &&
    r.opcode is Scalar(IntBinary(ShiftLeft)) &&
    l.operands is [a, n] &&
    r.operands is [b, m] &&
    self.same_value(n, m) else {
    return false
  }
  let marker = self.begin_candidates()
  if self.stage_pure_candidate(Scalar(IntBinary(op)), [a, b], left.ty)
    is Some(value) &&
    self.stage_pure_candidate(Scalar(IntBinary(ShiftLeft)), [value, n], left.ty)
    is Some(result) &&
    self.commit_candidates_if_cheaper(marker, 3, prefix) {
    return self.replace_with_alias(inst, result)
  }
  self.discard_candidates(marker)
  false
}
