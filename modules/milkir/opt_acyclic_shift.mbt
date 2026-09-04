// Direct shift and rotate rewrites for the bounded acyclic optimizer.

///|
fn opposite_rotation(op : IntBinaryOp) -> IntBinaryOp? {
  match op {
    RotateLeft => Some(RotateRight)
    RotateRight => Some(RotateLeft)
    _ => None
  }
}

///|
fn OptimizerSession::rewrite_rotation(
  self : OptimizerSession,
  inst : Inst,
  op : IntBinaryOp,
  prefix : Array[Inst],
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
  guard inner_op == op &&
    self.has_single_use(rotated) &&
    self.int_constant(inner_amount) is Some(inner_constant) &&
    self.int_constant(amount) is Some(outer_constant) else {
    return false
  }
  let combined = (
      normalized_shift(inner_constant, width) +
      normalized_shift(outer_constant, width)
    ) %
    width
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
