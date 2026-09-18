// Direct bitwise rewrites for the bounded acyclic optimizer.

///|
fn OptimizerSession::other_operand_if_contains(
  self : OptimizerSession,
  definition : @milkir.Inst?,
  op : @milkir.IntBinaryOp,
  needle : @milkir.Value,
) -> @milkir.Value? {
  guard definition is Some(definition) &&
    definition.opcode == Scalar(IntBinary(op)) &&
    definition.operands is [left, right] else {
    return None
  }
  let needle_id = self.canonical_value(needle).id
  if self.canonical_value(left).id == needle_id {
    Some(right)
  } else if self.canonical_value(right).id == needle_id {
    Some(left)
  } else {
    None
  }
}

///|
fn OptimizerSession::definition_is_complement_of(
  self : OptimizerSession,
  definition : @milkir.Inst?,
  value : @milkir.Value,
) -> Bool {
  guard definition is Some(definition) &&
    definition.opcode is Scalar(IntUnary(Not)) &&
    definition.operands is [source] else {
    return false
  }
  self.canonical_value(source).id == self.canonical_value(value).id
}

///|
fn OptimizerSession::rewrite_bitwise_relation(
  self : OptimizerSession,
  inst : @milkir.Inst,
  op : @milkir.IntBinaryOp,
  left : @milkir.Value,
  right : @milkir.Value,
  prefix : Array[@milkir.Inst],
) -> Bool {
  let left_definition = self.definition(left)
  let right_definition = self.definition(right)
  if self.definition_is_complement_of(left_definition, right) ||
    self.definition_is_complement_of(right_definition, left) {
    return match op {
      And => self.replace_with_constant(inst, 0L)
      Or | Xor => self.replace_with_constant(inst, -1L)
      _ => false
    }
  }
  if left_definition is Some(l) &&
    right_definition is Some(r) &&
    l.operands is [a, b] &&
    r.operands is [c, d] {
    if op == Xor && self.same_pair(a, b, c, d) {
      let replacement : @milkir.IntBinaryOp? = match (l.opcode, r.opcode) {
        (Scalar(IntBinary(And)), Scalar(IntBinary(Xor)))
        | (Scalar(IntBinary(Xor)), Scalar(IntBinary(And))) => Some(Or)
        (Scalar(IntBinary(Or)), Scalar(IntBinary(And)))
        | (Scalar(IntBinary(And)), Scalar(IntBinary(Or))) => Some(Xor)
        _ => None
      }
      if replacement is Some(op) {
        return self.replace_binary(inst, op, a, b)
      }
    }
    if l.opcode is Scalar(IntCompare(lcc)) &&
      r.opcode is Scalar(IntCompare(rcc)) &&
      self.same_pair(a, b, c, d) {
      let rcc = if self.same_value(a, c) { rcc } else { swap_intcc(rcc) }
      let opposed = (lcc == Slt && rcc == Sgt) ||
        (lcc == Sgt && rcc == Slt) ||
        (lcc == Ult && rcc == Ugt) ||
        (lcc == Ugt && rcc == Ult)
      if opposed {
        if op == And {
          return self.replace_with_constant(inst, 0L)
        }
        if op is (Xor | Or) {
          return self.replace_with_compare(inst, Ne, a, b)
        }
      }
      if lcc == complement_intcc(rcc) {
        return self.replace_with_constant(inst, if op == And { 0L } else { 1L })
      }
    }
    if op == Xor &&
      l.opcode is Scalar(IntBinary(And)) &&
      r.opcode is Scalar(IntBinary(And)) &&
      self.has_single_use(left) &&
      self.has_single_use(right) {
      let common = if self.same_value(a, c) {
        Some((a, b, d))
      } else if self.same_value(a, d) {
        Some((a, b, c))
      } else if self.same_value(b, c) {
        Some((b, a, d))
      } else if self.same_value(b, d) {
        Some((b, a, c))
      } else {
        None
      }
      if common is Some((common, a, b)) {
        let marker = self.begin_candidates()
        if self.stage_pure_candidate(Scalar(IntBinary(Xor)), [a, b], left.ty)
          is Some(xor) &&
          self.stage_pure_candidate(
            Scalar(IntBinary(And)),
            [common, xor],
            left.ty,
          )
          is Some(result) &&
          self.commit_candidates_if_cheaper(marker, 3, prefix) {
          return self.replace_with_alias(inst, result)
        }
        self.discard_candidates(marker)
      }
    }
  }
  if op == Or {
    if self.absorb_complemented_and(
        inst, left_definition, right_definition, right,
      ) ||
      self.absorb_complemented_and(
        inst, right_definition, left_definition, left,
      ) {
      return true
    }
    if self.rewrite_rotate_pair(inst, left_definition, right_definition, prefix) {
      return true
    }
  }
  if op == And {
    if self.factor_common_shift(inst, And, prefix) {
      return true
    }
    if self.mask_extension(inst, left, right, left_definition) {
      return true
    }
    if self.rewrite_xor_complement_mask(inst, left_definition, right) ||
      self.rewrite_xor_complement_mask(inst, right_definition, left) {
      return true
    }
  }
  match op {
    And => {
      if self.other_operand_if_contains(left_definition, Or, right) is Some(_) {
        return self.replace_with_alias(inst, right)
      }
      if self.other_operand_if_contains(right_definition, Or, left) is Some(_) {
        return self.replace_with_alias(inst, left)
      }
      if self.other_operand_if_contains(left_definition, And, right) is Some(_) {
        return self.replace_with_alias(inst, left)
      }
      if self.other_operand_if_contains(right_definition, And, left) is Some(_) {
        return self.replace_with_alias(inst, right)
      }
      false
    }
    Or => {
      if self.other_operand_if_contains(left_definition, And, right) is Some(_) {
        return self.replace_with_alias(inst, right)
      }
      if self.other_operand_if_contains(right_definition, And, left) is Some(_) {
        return self.replace_with_alias(inst, left)
      }
      if self.other_operand_if_contains(left_definition, Or, right) is Some(_) {
        return self.replace_with_alias(inst, left)
      }
      if self.other_operand_if_contains(right_definition, Or, left) is Some(_) {
        return self.replace_with_alias(inst, right)
      }
      false
    }
    Xor => {
      match self.other_operand_if_contains(left_definition, Xor, right) {
        Some(remaining) => return self.replace_with_alias(inst, remaining)
        None => ()
      }
      match self.other_operand_if_contains(right_definition, Xor, left) {
        Some(remaining) => return self.replace_with_alias(inst, remaining)
        None => ()
      }
      false
    }
    _ => false
  }
}

///|
fn OptimizerSession::absorb_complemented_and(
  self : OptimizerSession,
  inst : @milkir.Inst,
  and_def : @milkir.Inst?,
  not_def : @milkir.Inst?,
  complement : @milkir.Value,
) -> Bool {
  guard not_def is Some(not_def) &&
    not_def.opcode is Scalar(IntUnary(Not)) &&
    not_def.operands is [source] &&
    self.other_operand_if_contains(and_def, And, source) is Some(other) else {
    return false
  }
  self.replace_binary(inst, Or, other, complement)
}

///|
fn OptimizerSession::rewrite_xor_complement_mask(
  self : OptimizerSession,
  inst : @milkir.Inst,
  xor_def : @milkir.Inst?,
  mask : @milkir.Value,
) -> Bool {
  guard self.other_operand_if_contains(xor_def, Xor, mask) is Some(complement) &&
    self.definition(complement) is Some(not_def) &&
    not_def.opcode is Scalar(IntUnary(Not)) &&
    not_def.operands is [source] else {
    return false
  }
  self.replace_binary(inst, And, mask, source)
}

///|
fn OptimizerSession::mask_extension(
  self : OptimizerSession,
  inst : @milkir.Inst,
  extended : @milkir.Value,
  mask : @milkir.Value,
  definition : @milkir.Inst?,
) -> Bool {
  guard definition is Some(extension) &&
    extension.opcode is Scalar(Convert(op)) &&
    op is (UnsignedExtend | SignedExtend) &&
    extension.operands is [source] &&
    integer_width(source.ty) is Some(bits) &&
    self.int_constant(mask) is Some(mask) else {
    return false
  }
  let low_mask = integer_mask(bits)
  if op == UnsignedExtend && (mask & low_mask) == low_mask {
    return self.replace_with_alias(inst, extended)
  }
  if op == SignedExtend && mask == low_mask {
    inst.set_opcode(Scalar(Convert(UnsignedExtend)))
    inst.operands.clear()
    inst.operands.push(source)
    return true
  }
  false
}
