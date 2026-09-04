// Direct bitwise rewrites for the bounded acyclic optimizer.

///|
fn OptimizerSession::other_operand_if_contains(
  self : OptimizerSession,
  definition : Inst?,
  op : IntBinaryOp,
  needle : Value,
) -> Value? {
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
  definition : Inst?,
  value : Value,
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
  inst : Inst,
  op : IntBinaryOp,
  left : Value,
  right : Value,
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
