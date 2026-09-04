// Select remains the canonical representation of scalar min/max and absolute
// value. Do not introduce optimizer-only opcodes that must be expanded again.

///|
fn OptimizerSession::same_value(
  self : OptimizerSession,
  a : Value,
  b : Value,
) -> Bool {
  self.canonical_value(a).id == self.canonical_value(b).id
}

///|
fn OptimizerSession::rewrite_select(
  self : OptimizerSession,
  inst : Inst,
) -> Bool {
  if self.rewrite_select_identity(inst) {
    return true
  }
  guard inst.operands is [condition, if_true, if_false] else { return false }
  let mut changed = false
  let mut condition = condition
  if self.definition(condition) is Some(extension) &&
    extension.opcode is Scalar(Convert(UnsignedExtend | SignedExtend)) &&
    extension.operands is [source] {
    condition = source
    inst.operands[0] = source
    changed = true
  }
  for index in 1..<3 {
    if self.definition(inst.operands[index]) is Some(inner) &&
      inner.opcode is Scalar(Select) &&
      inner.operands is [inner_cond, yes, no] &&
      self.same_value(condition, inner_cond) {
      inst.operands[index] = if index == 1 { yes } else { no }
      changed = true
    }
  }
  if changed {
    return true
  }
  if self.boolean_compare(condition) is Some((boolean, cc, left, right)) {
    let replacement_cc = match
      (self.int_constant(if_true), self.int_constant(if_false)) {
      (Some(1L), Some(0L)) => {
        if if_true.ty == boolean.ty {
          return self.replace_with_alias(inst, boolean)
        }
        if if_true.ty == I64 {
          inst.opcode = Scalar(Convert(UnsignedExtend))
          inst.operands.clear()
          inst.operands.push(boolean)
          return true
        }
        Some(cc)
      }
      (Some(0L), Some(1L)) => Some(complement_intcc(cc))
      _ => None
    }
    if replacement_cc is Some(cc) {
      if if_true.ty == I32 {
        return self.replace_with_compare(inst, cc, left, right)
      }
    }
    // Equality selects are identities even for modular integers. Keep float
    // comparisons out: +0 and -0 compare equal but have distinct bit patterns.
    if cc is (Eq | Ne) {
      let (equal_arm, unequal_arm) = if cc == Eq {
        (if_true, if_false)
      } else {
        (if_false, if_true)
      }
      if (
          self.same_value(equal_arm, left) &&
          self.same_value(unequal_arm, right)
        ) ||
        (
          self.same_value(equal_arm, right) &&
          self.same_value(unequal_arm, left)
        ) {
        return self.replace_with_alias(inst, unequal_arm)
      }
    }
  }
  false
}

///|
// Prove comparisons against either arm of a canonical min/max select. This
// includes the old min-specific rules without manufacturing a min opcode.
fn OptimizerSession::compare_select_bound(
  self : OptimizerSession,
  inst : Inst,
  cc : IntCC,
  selected : Value,
  other : Value,
) -> Bool {
  guard self.definition(selected) is Some(select) &&
    select.opcode is Scalar(Select) &&
    select.operands is [condition, yes, no] &&
    self.boolean_compare(condition) is Some((_, condition_cc, a, b)) else {
    return false
  }
  let direct = self.same_value(yes, a) && self.same_value(no, b)
  let swapped = self.same_value(yes, b) && self.same_value(no, a)
  guard (direct || swapped) &&
    (self.same_value(other, a) || self.same_value(other, b)) else {
    return false
  }
  let signed = condition_cc is (Slt | Sle | Sgt | Sge)
  let unsigned = condition_cc is (Ult | Ule | Ugt | Uge)
  guard signed || unsigned else { return false }
  let minimum = (condition_cc is (Slt | Sle | Ult | Ule)) == direct
  let result = match (signed, minimum, cc) {
    (true, true, Sgt)
    | (true, false, Slt)
    | (false, true, Ugt)
    | (false, false, Ult) => Some(0L)
    (true, true, Sle)
    | (true, false, Sge)
    | (false, true, Ule)
    | (false, false, Uge) => Some(1L)
    _ => None
  }
  match result {
    Some(value) => self.replace_with_constant(inst, value)
    None => false
  }
}
