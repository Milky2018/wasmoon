// Reassociate only when constants remove an operation. Pure tree balancing
// without an operation reduction belongs to a separately measured scheduling
// decision, not to this algebraic normalizer.

///|
fn OptimizerSession::combine_branch_constants(
  self : OptimizerSession,
  inst : Inst,
  op : IntBinaryOp,
  prefix : Array[Inst],
) -> Bool {
  guard inst.operands is [left, right] &&
    self.has_single_use(left) &&
    self.has_single_use(right) &&
    self.definition(left) is Some(l) &&
    self.definition(right) is Some(r) &&
    l.opcode == Scalar(IntBinary(op)) &&
    r.opcode == Scalar(IntBinary(op)) &&
    l.operands is [a, k1] &&
    r.operands is [b, k2] &&
    self.int_constant(k1) is Some(c1) &&
    self.int_constant(k2) is Some(c2) &&
    integer_width(left.ty) is Some(width) &&
    fold_pure_integer_binary(op, c1, c2, width) is Some(c) else {
    return false
  }
  let marker = self.begin_candidates()
  if self.stage_pure_candidate(Scalar(IntBinary(op)), [a, b], left.ty)
    is Some(value) &&
    self.stage_int_binary_with_constant(op, value, left.ty, c) is Some(result) &&
    self.commit_candidates_if_cheaper(
      marker,
      3 * pure_candidate_cost(inst.opcode),
      prefix,
    ) {
    return self.replace_with_alias(inst, result)
  }
  self.discard_candidates(marker)
  false
}

///|
fn OptimizerSession::reassociate_constant_shift(
  self : OptimizerSession,
  inst : Inst,
  op : IntBinaryOp,
  prefix : Array[Inst],
) -> Bool {
  guard inst.operands is [left, right] &&
    self.int_constant(right) is Some(outer) &&
    self.has_single_use(left) &&
    self.definition(left) is Some(inner) &&
    inner.opcode == Scalar(IntBinary(op)) &&
    inner.operands is [source, amount] &&
    self.int_constant(source) is Some(value) &&
    integer_width(left.ty) is Some(width) &&
    fold_pure_integer_binary(op, value, outer, width) is Some(value) else {
    return false
  }
  let marker = self.begin_candidates()
  if self.stage_pure_candidate(Scalar(IntConst(value)), [], left.ty)
    is Some(value) {
    self.commit_candidates(marker, prefix)
    return self.replace_binary(inst, op, value, amount)
  }
  self.discard_candidates(marker)
  false
}

///|
fn OptimizerSession::shift_masked_shift(
  self : OptimizerSession,
  inst : Inst,
  prefix : Array[Inst],
) -> Bool {
  guard inst.operands is [masked, amount] &&
    self.has_single_use(masked) &&
    self.definition(masked) is Some(mask) &&
    mask.opcode is Scalar(IntBinary(And)) &&
    mask.operands is [a, b] else {
    return false
  }
  let left = self.definition(a)
  let right = self.definition(b)
  let pair = if left is Some(shift) &&
    shift.opcode is Scalar(IntBinary(ShiftLeft)) &&
    shift.operands is [source, n] &&
    self.same_value(n, amount) &&
    self.has_single_use(a) {
    Some((source, b))
  } else if right is Some(shift) &&
    shift.opcode is Scalar(IntBinary(ShiftLeft)) &&
    shift.operands is [source, n] &&
    self.same_value(n, amount) &&
    self.has_single_use(b) {
    Some((source, a))
  } else {
    None
  }
  guard pair is Some((source, mask)) else { return false }
  let marker = self.begin_candidates()
  if self.stage_pure_candidate(
      Scalar(IntBinary(UnsignedShiftRight)),
      [mask, amount],
      source.ty,
    )
    is Some(mask) &&
    self.stage_pure_candidate(Scalar(IntBinary(And)), [source, mask], source.ty)
    is Some(result) &&
    self.commit_candidates_if_cheaper(marker, 3, prefix) {
    return self.replace_with_alias(inst, result)
  }
  self.discard_candidates(marker)
  false
}
