// Modular integer algebra. Every rule either removes an operation or exposes
// a canonical primitive; no distributive expansion of shared expressions.

///|
fn OptimizerSession::replace_binary(
  self : OptimizerSession,
  inst : @milkir.Inst,
  op : @milkir.IntBinaryOp,
  a : @milkir.Value,
  b : @milkir.Value,
) -> Bool {
  inst.set_opcode(Scalar(IntBinary(op)))
  inst.operands.clear()
  inst.operands.push(self.canonical_value(a))
  inst.operands.push(self.canonical_value(b))
  true
}

///|
fn OptimizerSession::negated_source(
  self : OptimizerSession,
  definition : @milkir.Inst?,
) -> @milkir.Value? {
  guard definition is Some(inst) &&
    inst.opcode is Scalar(IntBinary(Sub)) &&
    inst.operands is [zero, source] &&
    self.int_constant(zero) == Some(0L) else {
    return None
  }
  Some(source)
}

///|
fn OptimizerSession::same_pair(
  self : OptimizerSession,
  a : @milkir.Value,
  b : @milkir.Value,
  c : @milkir.Value,
  d : @milkir.Value,
) -> Bool {
  (self.same_value(a, c) && self.same_value(b, d)) ||
  (self.same_value(a, d) && self.same_value(b, c))
}

///|
fn OptimizerSession::rewrite_arithmetic(
  self : OptimizerSession,
  inst : @milkir.Inst,
  op : @milkir.IntBinaryOp,
  prefix : Array[@milkir.Inst],
) -> Bool {
  guard inst.operands is [left, right] else { return false }
  if op is (Add | Sub) && self.factor_common_shift(inst, op, prefix) {
    return true
  }
  let ldef = self.definition(left)
  let rdef = self.definition(right)
  if op is (Add | Sub) && self.negated_source(rdef) is Some(source) {
    return self.replace_binary(
      inst,
      if op == Add {
        Sub
      } else {
        Add
      },
      left,
      source,
    )
  }
  if op == Add && self.negated_source(ldef) is Some(source) {
    return self.replace_binary(inst, Sub, right, source)
  }
  if op == Sub {
    if self.int_constant(left) == Some(0L) &&
      rdef is Some(inner) &&
      inner.opcode is Scalar(IntBinary(UnsignedShiftRight)) &&
      inner.operands is [a, amount] &&
      self.int_constant(amount) is Some(k) &&
      integer_width(a.ty) is Some(width) &&
      normalized_shift(k, width) == width - 1 {
      return self.replace_binary(inst, SignedShiftRight, a, amount)
    }
    if self.int_constant(left) == Some(0L) &&
      rdef is Some(inner) &&
      inner.opcode is Scalar(IntBinary(Sub)) &&
      inner.operands is [a, b] {
      return self.replace_binary(inst, Sub, b, a)
    }
    if rdef is Some(inner) &&
      inner.opcode is Scalar(IntBinary(Sub)) &&
      inner.operands is [a, b] &&
      self.same_value(left, a) {
      return self.replace_with_alias(inst, b)
    }
    if ldef is Some(inner) &&
      inner.opcode is Scalar(IntBinary(Sub)) &&
      inner.operands is [a, b] &&
      self.same_value(a, right) {
      let marker = self.begin_candidates()
      if self.stage_pure_candidate(Scalar(IntConst(0L)), [], left.ty)
        is Some(zero) {
        self.commit_candidates(marker, prefix)
        return self.replace_binary(inst, Sub, zero, b)
      }
      self.discard_candidates(marker)
    }
  }
  if op == Add &&
    rdef is Some(inner) &&
    inner.opcode is Scalar(IntBinary(Sub)) &&
    inner.operands is [a, b] &&
    self.same_value(left, b) {
    return self.replace_with_alias(inst, a)
  }
  if op == Mul {
    if self.negated_source(ldef) is Some(a) &&
      self.negated_source(rdef) is Some(b) {
      return self.replace_binary(inst, Mul, a, b)
    }
    if self.int_constant(right) == Some(-1L) {
      let marker = self.begin_candidates()
      if self.stage_pure_candidate(Scalar(IntConst(0L)), [], left.ty)
        is Some(zero) {
        self.commit_candidates(marker, prefix)
        return self.replace_binary(inst, Sub, zero, left)
      }
      self.discard_candidates(marker)
    }
    if rdef is Some(shift) &&
      shift.opcode is Scalar(IntBinary(ShiftLeft)) &&
      shift.operands is [one, amount] &&
      self.int_constant(one) == Some(1L) {
      return self.replace_binary(inst, ShiftLeft, left, amount)
    }
    if ldef is Some(shift) &&
      shift.opcode is Scalar(IntBinary(ShiftLeft)) &&
      shift.operands is [one, amount] &&
      self.int_constant(one) == Some(1L) {
      return self.replace_binary(inst, ShiftLeft, right, amount)
    }
  }
  if ldef is Some(l) &&
    rdef is Some(r) &&
    l.operands is [a, b] &&
    r.operands is [c, d] {
    if self.same_pair(a, b, c, d) {
      let replacement : @milkir.IntBinaryOp? = match (op, l.opcode, r.opcode) {
        (Add, Scalar(IntBinary(And)), Scalar(IntBinary(Xor)))
        | (Add, Scalar(IntBinary(Xor)), Scalar(IntBinary(And))) => Some(Or)
        (Add, Scalar(IntBinary(And)), Scalar(IntBinary(Or)))
        | (Add, Scalar(IntBinary(Or)), Scalar(IntBinary(And))) => Some(Add)
        (Sub, Scalar(IntBinary(Add)), Scalar(IntBinary(Or))) => Some(And)
        _ => None
      }
      if replacement is Some(op) {
        return self.replace_binary(inst, op, a, b)
      }
    }
  }
  if op == Add && self.int_constant(right) is Some(k) && ldef is Some(inner) {
    if inner.opcode is Scalar(IntUnary(Not)) &&
      inner.operands is [source] &&
      k == 1L {
      let marker = self.begin_candidates()
      if self.stage_pure_candidate(Scalar(IntConst(0L)), [], left.ty)
        is Some(zero) {
        self.commit_candidates(marker, prefix)
        return self.replace_binary(inst, Sub, zero, source)
      }
      self.discard_candidates(marker)
    }
    if inner.opcode is Scalar(IntBinary(Or)) &&
      inner.operands is [source, mask] &&
      self.int_constant(mask) is Some(mask) &&
      k == -mask &&
      self.has_single_use(left) {
      let marker = self.begin_candidates()
      if self.stage_int_binary_with_constant(And, source, left.ty, -1L ^ mask)
        is Some(result) &&
        self.commit_candidates_if_cheaper(marker, 2, prefix) {
        return self.replace_with_alias(inst, result)
      }
      self.discard_candidates(marker)
    }
    if inner.opcode is Scalar(Select) &&
      inner.operands is [cond, yes, no] &&
      self.int_constant(yes) is Some(a) &&
      self.int_constant(no) is Some(b) &&
      self.has_single_use(left) &&
      integer_width(left.ty) is Some(width) {
      let marker = self.begin_candidates()
      if self.stage_pure_candidate(
          Scalar(IntConst(sign_extend_integer(a + k, width))),
          [],
          left.ty,
        )
        is Some(a) &&
        self.stage_pure_candidate(
          Scalar(IntConst(sign_extend_integer(b + k, width))),
          [],
          left.ty,
        )
        is Some(b) {
        self.commit_candidates(marker, prefix)
        inst.set_opcode(Scalar(Select))
        inst.operands.clear()
        inst.operands.append([cond, a, b])
        return true
      }
      self.discard_candidates(marker)
    }
  }
  false
}
