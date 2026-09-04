// Narrow only modular operations. Shifts require a separate amount proof;
// signed arithmetic and division cannot be pushed through zero extension.

///|
fn OptimizerSession::stage_reduced_operand(
  self : OptimizerSession,
  value : Value,
  ty : Type,
) -> Value? {
  if value.ty == ty {
    return Some(value)
  }
  if self.int_constant(value) is Some(c) {
    return self.stage_pure_candidate(
      Scalar(IntConst(c.to_int().to_int64())),
      [],
      ty,
    )
  }
  if self.definition(value) is Some(inst) &&
    inst.opcode is Scalar(Convert(UnsignedExtend | SignedExtend)) &&
    inst.operands is [source] &&
    source.ty == ty {
    return Some(source)
  }
  self.stage_pure_candidate(Scalar(Convert(IntReduce)), [value], ty)
}

///|
fn OptimizerSession::rewrite_reduce_expression(
  self : OptimizerSession,
  inst : Inst,
  prefix : Array[Inst],
) -> Bool {
  guard inst.operands is [source] &&
    inst.first_result() is Some(result) &&
    result.ty == I32 &&
    self.has_single_use(source) &&
    self.definition(source) is Some(inner) else {
    return false
  }
  let marker = self.begin_candidates()
  let replacement : Value? = match (inner.opcode, inner.operands) {
    (Scalar(IntBinary(ShiftLeft)), [a, amount]) => {
      guard self.int_constant(amount) is Some(amount) else { None }
      let amount = normalized_shift(amount, 64)
      if amount >= 32 {
        self.stage_pure_candidate(Scalar(IntConst(0L)), [], I32)
      } else {
        match self.stage_reduced_operand(a, I32) {
          Some(a) =>
            self.stage_int_binary_with_constant(
              ShiftLeft,
              a,
              I32,
              amount.to_int64(),
            )
          None => None
        }
      }
    }
    (Scalar(IntUnary(Not)), [a]) =>
      match self.stage_reduced_operand(a, I32) {
        Some(a) => self.stage_pure_candidate(Scalar(IntUnary(Not)), [a], I32)
        None => None
      }
    (Scalar(IntBinary(op)), [a, b]) if op is (Add | Sub | Mul | And | Or | Xor) =>
      match
        (self.stage_reduced_operand(a, I32), self.stage_reduced_operand(b, I32)) {
        (Some(a), Some(b)) =>
          self.stage_pure_candidate(Scalar(IntBinary(op)), [a, b], I32)
        _ => None
      }
    _ => None
  }
  if replacement is Some(replacement) &&
    self.commit_candidates_if_cheaper(
      marker,
      1 + pure_candidate_cost(inner.opcode),
      prefix,
    ) {
    return self.replace_with_alias(inst, replacement)
  }
  self.discard_candidates(marker)
  false
}

///|
fn OptimizerSession::rewrite_extended_bitwise(
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
    l.opcode is Scalar(Convert(UnsignedExtend)) &&
    r.opcode is Scalar(Convert(UnsignedExtend)) &&
    l.operands is [a] &&
    r.operands is [b] &&
    a.ty == b.ty else {
    return false
  }
  let marker = self.begin_candidates()
  if self.stage_pure_candidate(Scalar(IntBinary(op)), [a, b], a.ty)
    is Some(value) &&
    self.stage_pure_candidate(Scalar(Convert(UnsignedExtend)), [value], left.ty)
    is Some(result) &&
    self.commit_candidates_if_cheaper(marker, 3, prefix) {
    return self.replace_with_alias(inst, result)
  }
  self.discard_candidates(marker)
  false
}
