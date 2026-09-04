// Direct integer-comparison rewrites for the bounded acyclic optimizer.

///|
fn complement_intcc(cc : IntCC) -> IntCC {
  match cc {
    Eq => Ne
    Ne => Eq
    Slt => Sge
    Sle => Sgt
    Sgt => Sle
    Sge => Slt
    Ult => Uge
    Ule => Ugt
    Ugt => Ule
    Uge => Ult
  }
}

///|
fn swap_intcc(cc : IntCC) -> IntCC {
  match cc {
    Eq => Eq
    Ne => Ne
    Slt => Sgt
    Sle => Sge
    Sgt => Slt
    Sge => Sle
    Ult => Ugt
    Ule => Uge
    Ugt => Ult
    Uge => Ule
  }
}

///|
fn self_compare_result(cc : IntCC) -> Int64 {
  match cc {
    Eq | Sle | Sge | Ule | Uge => 1L
    Ne | Slt | Sgt | Ult | Ugt => 0L
  }
}

///|
fn OptimizerSession::boolean_compare(
  self : OptimizerSession,
  value : Value,
) -> (Value, IntCC, Value, Value)? {
  let canonical = self.canonical_value(value)
  guard self.definition(value) is Some(definition) else { return None }
  match definition.opcode {
    Scalar(IntCompare(cc)) =>
      match definition.operands {
        [left, right] => Some((canonical, cc, left, right))
        _ => None
      }
    Scalar(Convert(UnsignedExtend | SignedExtend)) => {
      guard definition.operands is [source] &&
        self.definition(source) is Some(inner) &&
        inner.opcode is Scalar(IntCompare(cc)) else {
        return None
      }
      match inner.operands {
        [left, right] => Some((self.canonical_value(source), cc, left, right))
        _ => None
      }
    }
    _ => None
  }
}

///|
fn OptimizerSession::replace_with_compare(
  self : OptimizerSession,
  inst : Inst,
  cc : IntCC,
  left : Value,
  right : Value,
) -> Bool {
  inst.opcode = Scalar(IntCompare(cc))
  inst.operands.clear()
  inst.operands.push(self.canonical_value(left))
  inst.operands.push(self.canonical_value(right))
  true
}

///|
fn OptimizerSession::rewrite_boolean_compare(
  self : OptimizerSession,
  inst : Inst,
  cc : IntCC,
  left : Value,
  right : Value,
) -> Bool {
  if !(cc is (Eq | Ne)) {
    return false
  }
  let (boolean, constant) = match
    (self.int_constant(left), self.int_constant(right)) {
    (None, Some(constant)) => (left, constant)
    (Some(constant), None) => (right, constant)
    _ => return false
  }
  guard self.boolean_compare(boolean)
    is Some((inner_result, inner_cc, inner_left, inner_right)) else {
    return false
  }
  match (cc, constant) {
    (Eq, 0L) | (Ne, 1L) =>
      self.replace_with_compare(
        inst,
        complement_intcc(inner_cc),
        inner_left,
        inner_right,
      )
    (Ne, 0L) | (Eq, 1L) => self.replace_with_alias(inst, inner_result)
    (Eq, _) => self.replace_with_constant(inst, 0L)
    (Ne, _) => self.replace_with_constant(inst, 1L)
    _ => false
  }
}

///|
fn OptimizerSession::cancel_common_addend(
  self : OptimizerSession,
  inst : Inst,
  cc : IntCC,
  left : Value,
  right : Value,
) -> Bool {
  if !(cc is (Eq | Ne)) {
    return false
  }
  guard self.definition(left) is Some(left_add) &&
    left_add.opcode is Scalar(IntBinary(Add)) &&
    left_add.operands is [left0, left1] &&
    self.definition(right) is Some(right_add) &&
    right_add.opcode is Scalar(IntBinary(Add)) &&
    right_add.operands is [right0, right1] else {
    return false
  }
  let left0_id = self.canonical_value(left0).id
  let left1_id = self.canonical_value(left1).id
  let right0_id = self.canonical_value(right0).id
  let right1_id = self.canonical_value(right1).id
  if left1_id == right1_id {
    self.replace_with_compare(inst, cc, left0, right0)
  } else if left1_id == right0_id {
    self.replace_with_compare(inst, cc, left0, right1)
  } else if left0_id == right1_id {
    self.replace_with_compare(inst, cc, left1, right0)
  } else if left0_id == right0_id {
    self.replace_with_compare(inst, cc, left1, right1)
  } else {
    false
  }
}

///|
fn OptimizerSession::rewrite_compare_through_extension(
  self : OptimizerSession,
  inst : Inst,
  cc : IntCC,
  extended : Value,
  prefix : Array[Inst],
) -> Bool {
  guard self.definition(extended) is Some(extension) &&
    extension.operands is [source] &&
    extension.opcode is Scalar(Convert(conversion)) &&
    conversion is (SignedExtend | UnsignedExtend) &&
    integer_width(source.ty) is Some(source_width) &&
    integer_width(extended.ty) is Some(extended_width) &&
    source_width < extended_width else {
    return false
  }
  if conversion is UnsignedExtend {
    match cc {
      Slt => return self.replace_with_constant(inst, 0L)
      Sge => return self.replace_with_constant(inst, 1L)
      _ => ()
    }
  }
  let narrow_cc : IntCC? = match (conversion, cc) {
    (_, Eq | Ne) => Some(cc)
    (SignedExtend, Slt | Sle | Sgt | Sge) => Some(cc)
    (UnsignedExtend, Sle) => Some(Eq)
    (UnsignedExtend, Sgt) => Some(Ne)
    _ => None
  }
  guard narrow_cc is Some(narrow_cc) && self.has_single_use(extended) else {
    return false
  }
  let marker = self.begin_candidates()
  guard self.stage_pure_candidate(Scalar(IntConst(0L)), [], source.ty)
    is Some(zero) &&
    self.stage_pure_candidate(
      Scalar(IntCompare(narrow_cc)),
      [source, zero],
      I32,
    )
    is Some(replacement) else {
    self.discard_candidates(marker)
    return false
  }
  if !self.commit_candidates_if_cheaper(
      marker,
      pure_candidate_cost(extension.opcode) + pure_candidate_cost(inst.opcode),
      prefix,
    ) {
    return false
  }
  self.replace_with_alias(inst, replacement)
}

///|
fn OptimizerSession::rewrite_compare(
  self : OptimizerSession,
  inst : Inst,
  cc : IntCC,
  prefix : Array[Inst],
) -> Bool {
  guard inst.operands is [left, right] else { return false }
  if self.rewrite_boolean_compare(inst, cc, left, right) {
    return true
  }
  if self.cancel_common_addend(inst, cc, left, right) {
    return true
  }
  if self.canonical_value(left).id == self.canonical_value(right).id {
    return self.replace_with_constant(inst, self_compare_result(cc))
  }
  if self.compare_select_bound(inst, cc, left, right) ||
    self.compare_select_bound(inst, swap_intcc(cc), right, left) {
    return true
  }
  let mut compare_cc = cc
  let mut compare_left = left
  let mut compare_right = right
  let mut changed = false
  if self.int_constant(left) is Some(_) && self.int_constant(right) is None {
    compare_cc = swap_intcc(cc)
    compare_left = right
    compare_right = left
    inst.opcode = Scalar(IntCompare(compare_cc))
    inst.operands[0] = compare_left
    inst.operands[1] = compare_right
    changed = true
  }
  if self.int_constant(compare_right) is Some(0L) {
    if self.rewrite_compare_through_extension(
        inst, compare_cc, compare_left, prefix,
      ) {
      return true
    }
    match compare_cc {
      Ult => return self.replace_with_constant(inst, 0L)
      Uge => return self.replace_with_constant(inst, 1L)
      Ule =>
        return self.replace_with_compare(inst, Eq, compare_left, compare_right)
      Ugt =>
        return self.replace_with_compare(inst, Ne, compare_left, compare_right)
      _ => ()
    }
  }
  if self.rewrite_compare_constant(
      inst, compare_cc, compare_left, compare_right, prefix,
    ) {
    return true
  }
  if self.rewrite_compare_relation(
      inst, compare_cc, compare_left, compare_right, prefix,
    ) {
    return true
  }
  changed
}

///|
fn OptimizerSession::rewrite_compare_constant(
  self : OptimizerSession,
  inst : Inst,
  cc : IntCC,
  left : Value,
  right : Value,
  prefix : Array[Inst],
) -> Bool {
  guard self.int_constant(right) is Some(raw) &&
    integer_width(left.ty) is Some(width) else {
    return false
  }
  let constant = sign_extend_integer(raw, width)
  let maximum = low_bits_mask(width - 1)
  let minimum = sign_extend_integer(1L << (width - 1), width)
  let bound = match (cc, constant) {
    (Ugt, -1L) => Some(0L)
    (Ule, -1L) => Some(1L)
    (Sgt, c) if c == maximum => Some(0L)
    (Sle, c) if c == maximum => Some(1L)
    (Slt, c) if c == minimum => Some(0L)
    (Sge, c) if c == minimum => Some(1L)
    _ => None
  }
  if bound is Some(value) {
    return self.replace_with_constant(inst, value)
  }
  let equality = match (cc, constant) {
    (Uge, -1L) => true
    (Sge, c) if c == maximum => true
    (Sle, c) if c == minimum => true
    _ => false
  }
  if equality {
    return self.replace_with_compare(inst, Eq, left, right)
  }
  let normalized : IntCC? = match (cc, constant) {
    (Uge, 1L) => Some(Ne)
    (Ult, 1L) => Some(Eq)
    (Sge, 1L) => Some(Sgt)
    (Slt, 1L) => Some(Sle)
    (Sgt, -1L) => Some(Sge)
    (Sle, -1L) => Some(Slt)
    _ => None
  }
  if normalized is Some(new_cc) {
    let marker = self.begin_candidates()
    if self.stage_pure_candidate(Scalar(IntConst(0L)), [], left.ty)
      is Some(zero) {
      self.commit_candidates(marker, prefix)
      return self.replace_with_compare(inst, new_cc, left, zero)
    }
    self.discard_candidates(marker)
  }
  guard cc is (Eq | Ne) &&
    self.has_single_use(left) &&
    self.definition(left) is Some(inner) &&
    inner.operands is [a, b] &&
    self.int_constant(b) is Some(k) else {
    return false
  }
  let adjusted = match inner.opcode {
    Scalar(IntBinary(Add)) => constant - k
    Scalar(IntBinary(Sub)) => constant + k
    _ => return false
  }
  let marker = self.begin_candidates()
  guard self.stage_pure_candidate(
      Scalar(IntConst(sign_extend_integer(adjusted, width))),
      [],
      a.ty,
    )
    is Some(k) else {
    self.discard_candidates(marker)
    return false
  }
  self.commit_candidates(marker, prefix)
  self.replace_with_compare(inst, cc, a, k)
}

///|
fn OptimizerSession::rewrite_compare_relation(
  self : OptimizerSession,
  inst : Inst,
  cc : IntCC,
  left : Value,
  right : Value,
  prefix : Array[Inst],
) -> Bool {
  let left_def = self.definition(left)
  let right_def = self.definition(right)
  if cc is (Eq | Ne) {
    if left_def is Some(l) &&
      right_def is Some(r) &&
      l.opcode is Scalar(IntBinary(Add)) &&
      r.opcode is Scalar(IntBinary(Add)) &&
      l.operands is [a, k1] &&
      r.operands is [b, k2] &&
      self.has_single_use(left) &&
      self.has_single_use(right) &&
      self.int_constant(k1) is Some(c1) &&
      self.int_constant(k2) is Some(c2) {
      let marker = self.begin_candidates()
      if self.stage_int_binary_with_constant(Add, b, b.ty, c2 - c1)
        is Some(adjusted) &&
        self.commit_candidates_if_cheaper(marker, 2, prefix) {
        return self.replace_with_compare(inst, cc, a, adjusted)
      }
      self.discard_candidates(marker)
    }
    let other = match self.other_operand_if_contains(left_def, Xor, right) {
      Some(other) => Some(other)
      None => self.other_operand_if_contains(right_def, Xor, left)
    }
    if other is Some(other) {
      let marker = self.begin_candidates()
      if self.stage_pure_candidate(Scalar(IntConst(0L)), [], other.ty)
        is Some(zero) {
        self.commit_candidates(marker, prefix)
        return self.replace_with_compare(inst, cc, other, zero)
      }
      self.discard_candidates(marker)
    }
  }
  if left_def is Some(l) &&
    right_def is Some(r) &&
    l.opcode is Scalar(IntUnary(Not)) &&
    r.opcode is Scalar(IntUnary(Not)) &&
    l.operands is [a] &&
    r.operands is [b] {
    return self.replace_with_compare(inst, swap_intcc(cc), a, b)
  }
  if cc is (Ugt | Ule) &&
    left_def is Some(sub) &&
    sub.opcode is Scalar(IntBinary(Sub)) &&
    sub.operands is [a, b] &&
    self.same_value(a, right) {
    return self.replace_with_compare(
      inst,
      if cc == Ugt {
        Ult
      } else {
        Uge
      },
      a,
      b,
    )
  }
  false
}
