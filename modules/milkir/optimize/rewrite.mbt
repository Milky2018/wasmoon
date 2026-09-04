///|
fn integer_width(ty : @milkir.Type) -> Int? {
  match ty {
    I32 => Some(32)
    I64 => Some(64)
    _ => None
  }
}

///|
fn integer_mask(width : Int) -> Int64 {
  match width {
    32 => 0xFFFFFFFFL
    64 => -1L
    _ => -1L
  }
}

///|
fn sign_extend_integer(value : Int64, width : Int) -> Int64 {
  if width >= 64 {
    value
  } else {
    let mask = integer_mask(width)
    let masked = value & mask
    let sign_bit = 1L << (width - 1)
    if (masked & sign_bit) != 0L {
      masked | (-1L ^ mask)
    } else {
      masked
    }
  }
}

///|
fn normalized_shift(value : Int64, width : Int) -> Int {
  (value & (width - 1).to_int64()).to_int()
}

///|
fn power_of_two_shift(value : Int64) -> Int? {
  if value <= 0L || (value & (value - 1L)) != 0L {
    return None
  }
  let mut shift = 0
  let mut remaining = value
  while remaining > 1L {
    remaining = remaining >> 1
    shift = shift + 1
  }
  Some(shift)
}

///|
fn is_commutative_integer_op(op : @milkir.IntBinaryOp) -> Bool {
  op is (Add | Mul | And | Or | Xor)
}

///|
fn OptimizerSession::canonicalize_commutative_constant(
  self : OptimizerSession,
  inst : @milkir.Inst,
  op : @milkir.IntBinaryOp,
) -> Bool {
  if !is_commutative_integer_op(op) || inst.operands.length() != 2 {
    return false
  }
  if self.int_constant(inst.operands[0]) is Some(_) &&
    self.int_constant(inst.operands[1]) is None {
    let left = inst.operands[0]
    inst.operands[0] = inst.operands[1]
    inst.operands[1] = left
    true
  } else {
    false
  }
}

///|
fn OptimizerSession::rewrite_int_binary(
  self : OptimizerSession,
  inst : @milkir.Inst,
  op : @milkir.IntBinaryOp,
  prefix : Array[@milkir.Inst],
) -> Bool {
  guard inst.operands is [left, right] else { return false }
  if self.int_constant(left) is Some(a) &&
    self.int_constant(right) is Some(b) &&
    integer_width(left.ty) is Some(width) &&
    fold_pure_integer_binary(op, a, b, width) is Some(value) {
    return self.replace_with_constant(inst, value)
  }
  if is_commutative_integer_op(op) &&
    self.combine_branch_constants(inst, op, prefix) {
    return true
  }
  match op {
    Add => {
      if self.int_constant(right) is Some(0L) {
        return self.replace_with_alias(inst, left)
      }
      self.rewrite_arithmetic(inst, Add, prefix) ||
      self.rewrite_nested_integer(inst, Add, prefix)
    }
    Sub => {
      if self.int_constant(right) is Some(0L) {
        return self.replace_with_alias(inst, left)
      }
      if self.canonical_value(left).id == self.canonical_value(right).id {
        return self.replace_with_constant(inst, 0L)
      }
      self.rewrite_arithmetic(inst, Sub, prefix) ||
      self.rewrite_nested_integer(inst, Sub, prefix)
    }
    Mul => {
      let right_constant = self.int_constant(right)
      if right_constant is Some(0L) {
        return self.replace_with_constant(inst, 0L)
      }
      if right_constant is Some(1L) {
        return self.replace_with_alias(inst, left)
      }
      if self.rewrite_arithmetic(inst, Mul, prefix) ||
        self.rewrite_nested_integer(inst, Mul, prefix) {
        return true
      }
      if right_constant is Some(constant) &&
        power_of_two_shift(constant) is Some(shift) &&
        inst.first_result() is Some(result) {
        let marker = self.begin_candidates()
        guard self.stage_int_binary_with_constant(
            ShiftLeft,
            left,
            result.ty,
            shift.to_int64(),
          )
          is Some(shifted) else {
          self.discard_candidates(marker)
          return false
        }
        if !self.commit_candidates_if_cheaper(
            marker,
            pure_candidate_cost(inst.opcode),
            prefix,
          ) {
          return false
        }
        return self.replace_with_alias(inst, shifted)
      }
      false
    }
    And => {
      let right_constant = self.int_constant(right)
      if right_constant is Some(0L) {
        return self.replace_with_constant(inst, 0L)
      }
      if right_constant is Some(1L) && self.boolean_compare(left) is Some(_) {
        return self.replace_with_alias(inst, left)
      }
      if right_constant is Some(-1L) ||
        self.canonical_value(left).id == self.canonical_value(right).id {
        return self.replace_with_alias(inst, left)
      }
      if self.rewrite_bitwise_relation(inst, And, left, right, prefix) {
        return true
      }
      self.rewrite_extended_bitwise(inst, And, prefix) ||
      self.rewrite_nested_integer(inst, And, prefix)
    }
    Or => {
      let right_constant = self.int_constant(right)
      if right_constant is Some(0L) ||
        self.canonical_value(left).id == self.canonical_value(right).id {
        return self.replace_with_alias(inst, left)
      }
      if right_constant is Some(-1L) {
        return self.replace_with_constant(inst, -1L)
      }
      if self.rewrite_bitwise_relation(inst, Or, left, right, prefix) {
        return true
      }
      self.rewrite_extended_bitwise(inst, Or, prefix) ||
      self.rewrite_nested_integer(inst, Or, prefix)
    }
    Xor => {
      if self.int_constant(right) is Some(0L) {
        return self.replace_with_alias(inst, left)
      }
      if self.canonical_value(left).id == self.canonical_value(right).id {
        return self.replace_with_constant(inst, 0L)
      }
      if self.int_constant(right) == Some(-1L) {
        inst.set_opcode(Scalar(IntUnary(Not)))
        inst.operands.remove(1) |> ignore
        return true
      }
      if self.rewrite_bitwise_relation(inst, Xor, left, right, prefix) {
        return true
      }
      self.rewrite_extended_bitwise(inst, Xor, prefix) ||
      self.rewrite_nested_integer(inst, Xor, prefix)
    }
    ShiftLeft | SignedShiftRight | UnsignedShiftRight => {
      if self.int_constant(right) is Some(amount) &&
        integer_width(left.ty) is Some(width) &&
        normalized_shift(amount, width) == 0 {
        return self.replace_with_alias(inst, left)
      }
      if self.int_constant(left) is Some(0L) {
        return self.replace_with_constant(inst, 0L)
      }
      self.rewrite_nested_shift(inst, op, prefix) ||
      self.reassociate_constant_shift(inst, op, prefix) ||
      (op == UnsignedShiftRight && self.shift_masked_shift(inst, prefix))
    }
    RotateLeft | RotateRight => {
      if self.int_constant(right) is Some(amount) &&
        integer_width(left.ty) is Some(width) &&
        normalized_shift(amount, width) == 0 {
        return self.replace_with_alias(inst, left)
      }
      self.rewrite_rotation(inst, op, prefix)
    }
    UnsignedMulHigh
    | SignedMulHigh
    | SignedDiv
    | UnsignedDiv
    | SignedRem
    | UnsignedRem => false
  }
}

///|
fn OptimizerSession::rewrite_nested_integer(
  self : OptimizerSession,
  inst : @milkir.Inst,
  op : @milkir.IntBinaryOp,
  prefix : Array[@milkir.Inst],
) -> Bool {
  guard inst.operands is [left, right] else { return false }
  guard self.definition(left) is Some(inner) &&
    inner.operands is [inner_left, inner_right] else {
    return false
  }
  match (op, inner.opcode) {
    (Sub, Scalar(IntBinary(Add))) => {
      if self.canonical_value(inner_right).id == self.canonical_value(right).id {
        return self.replace_with_alias(inst, inner_left)
      }
      if self.canonical_value(inner_left).id == self.canonical_value(right).id {
        return self.replace_with_alias(inst, inner_right)
      }
    }
    (Add, Scalar(IntBinary(Sub))) =>
      if self.canonical_value(inner_right).id == self.canonical_value(right).id {
        return self.replace_with_alias(inst, inner_left)
      }
    _ => ()
  }
  guard self.int_constant(right) is Some(outer_constant) &&
    self.has_single_use(left) else {
    return false
  }
  if op is (Add | Sub) &&
    inner.opcode is Scalar(IntBinary(Sub)) &&
    self.int_constant(inner_left) is Some(c) {
    let marker = self.begin_candidates()
    let combined = if op == Add {
      c + outer_constant
    } else {
      c - outer_constant
    }
    if self.stage_pure_candidate(Scalar(IntConst(combined)), [], left.ty)
      is Some(c) {
      self.commit_candidates(marker, prefix)
      return self.replace_binary(inst, Sub, c, inner_right)
    }
    self.discard_candidates(marker)
    return false
  }
  guard self.int_constant(inner_right) is Some(inner_constant) else {
    return false
  }
  let combined : (@milkir.IntBinaryOp, Int64)? = match (op, inner.opcode) {
    (Mul, Scalar(IntBinary(Mul))) =>
      Some((Mul, inner_constant * outer_constant))
    (Mul, Scalar(IntBinary(ShiftLeft))) =>
      match integer_width(left.ty) {
        Some(width) =>
          Some((Mul, outer_constant << normalized_shift(inner_constant, width)))
        None => None
      }
    (Add, Scalar(IntBinary(Add))) =>
      Some((Add, inner_constant + outer_constant))
    (Sub, Scalar(IntBinary(Add))) =>
      Some((Add, inner_constant - outer_constant))
    (Add, Scalar(IntBinary(Sub))) =>
      Some((Add, outer_constant - inner_constant))
    (Sub, Scalar(IntBinary(Sub))) =>
      Some((Sub, inner_constant + outer_constant))
    (And, Scalar(IntBinary(And))) =>
      Some((And, inner_constant & outer_constant))
    (Or, Scalar(IntBinary(Or))) => Some((Or, inner_constant | outer_constant))
    (Xor, Scalar(IntBinary(Xor))) =>
      Some((Xor, inner_constant ^ outer_constant))
    _ => None
  }
  guard combined is Some((new_op, new_constant)) &&
    inst.first_result() is Some(result) else {
    return false
  }
  let marker = self.begin_candidates()
  guard self.stage_int_binary_with_constant(
      new_op,
      inner_left,
      result.ty,
      new_constant,
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
fn OptimizerSession::rewrite_nested_shift(
  self : OptimizerSession,
  inst : @milkir.Inst,
  op : @milkir.IntBinaryOp,
  prefix : Array[@milkir.Inst],
) -> Bool {
  if !(op is (ShiftLeft | SignedShiftRight | UnsignedShiftRight)) ||
    inst.operands.length() != 2 ||
    inst.first_result() is None {
    return false
  }
  let left = inst.operands[0]
  let right = inst.operands[1]
  guard self.int_constant(right) is Some(outer) &&
    self.has_single_use(left) &&
    self.definition(left) is Some(inner) &&
    inner.opcode is Scalar(IntBinary(inner_op)) &&
    inner.operands is [source, inner_amount] &&
    self.int_constant(inner_amount) is Some(inner_constant) &&
    inst.first_result() is Some(result) &&
    integer_width(result.ty) is Some(width) else {
    return false
  }
  let outer_shift = normalized_shift(outer, width)
  let inner_shift = normalized_shift(inner_constant, width)
  let is_mask_pair = (op == ShiftLeft && inner_op == UnsignedShiftRight) ||
    (op == UnsignedShiftRight && inner_op == ShiftLeft)
  if is_mask_pair {
    if outer_shift != inner_shift {
      return false
    }
    if outer_shift == 0 {
      return self.replace_with_alias(inst, source)
    }
    let mask_bits = if op is ShiftLeft {
      (integer_mask(width) << outer_shift) & integer_mask(width)
    } else {
      low_bits_mask(width - outer_shift)
    }
    let marker = self.begin_candidates()
    guard self.stage_int_binary_with_constant(
        And,
        source,
        result.ty,
        sign_extend_integer(mask_bits, width),
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
    return self.replace_with_alias(inst, replacement)
  }
  if inner_op != op {
    return false
  }
  let total = inner_shift + outer_shift
  let combined = if total < width {
    total
  } else {
    match op {
      ShiftLeft | UnsignedShiftRight =>
        return self.replace_with_constant(inst, 0L)
      SignedShiftRight => width - 1
      _ => return false
    }
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
fn OptimizerSession::rewrite_conversion(
  self : OptimizerSession,
  inst : @milkir.Inst,
  conversion : @milkir.ConversionOp,
) -> Bool {
  guard inst.operands is [source] && inst.first_result() is Some(result) else {
    return false
  }
  if source.ty == result.ty {
    return self.replace_with_alias(inst, source)
  }
  if self.int_constant(source) is Some(constant) &&
    integer_width(source.ty) is Some(source_width) &&
    integer_width(result.ty) is Some(result_width) {
    match conversion {
      UnsignedExtend =>
        return self.replace_with_constant(
          inst,
          constant & integer_mask(source_width),
        )
      IntReduce =>
        return self.replace_with_constant(
          inst,
          constant & integer_mask(result_width),
        )
      SignedExtend =>
        return self.replace_with_constant(
          inst,
          sign_extend_integer(constant, source_width),
        )
      _ => ()
    }
  }
  if conversion == SignedExtend && self.boolean_compare(source) is Some(_) {
    inst.set_opcode(Scalar(Convert(UnsignedExtend)))
    return true
  }
  guard self.definition(source) is Some(inner) &&
    inner.operands is [inner_source] else {
    return false
  }
  match (conversion, inner.opcode) {
    (UnsignedExtend, Scalar(Convert(UnsignedExtend)))
    | (SignedExtend, Scalar(Convert(SignedExtend))) => {
      inst.operands[0] = inner_source
      true
    }
    (SignedExtend, Scalar(Convert(UnsignedExtend))) => {
      inst.set_opcode(Scalar(Convert(UnsignedExtend)))
      inst.operands[0] = inner_source
      true
    }
    (IntReduce, Scalar(Convert(UnsignedExtend | SignedExtend))) =>
      if inner_source.ty == result.ty {
        self.replace_with_alias(inst, inner_source)
      } else {
        false
      }
    (IntReduce, Scalar(Convert(IntReduce))) => {
      inst.operands[0] = inner_source
      true
    }
    _ => false
  }
}

///|
fn OptimizerSession::rewrite_select_identity(
  self : OptimizerSession,
  inst : @milkir.Inst,
) -> Bool {
  guard inst.operands is [condition, if_true, if_false] else { return false }
  if self.canonical_value(if_true).id == self.canonical_value(if_false).id {
    return self.replace_with_alias(inst, if_true)
  }
  match self.int_constant(condition) {
    Some(0L) => self.replace_with_alias(inst, if_false)
    Some(_) => self.replace_with_alias(inst, if_true)
    None => false
  }
}

///|
fn OptimizerSession::rewrite_inst(
  self : OptimizerSession,
  inst : @milkir.Inst,
  prefix : Array[@milkir.Inst],
) -> Bool {
  let mut changed = self.canonicalize_operands(inst)
  self.stats.attempts = self.stats.attempts + 1
  let applied = match inst.opcode {
    Scalar(IntBinary(op)) => {
      let canonicalized = self.canonicalize_commutative_constant(inst, op)
      changed = changed || canonicalized
      self.rewrite_int_binary(inst, op, prefix)
    }
    Scalar(IntUnary(op)) => self.rewrite_integer_unary(inst, op, prefix)
    Scalar(IntCompare(cc)) => self.rewrite_compare(inst, cc, prefix)
    Scalar(Convert(conversion)) =>
      self.rewrite_conversion(inst, conversion) ||
      (conversion == IntReduce && self.rewrite_reduce_expression(inst, prefix))
    Scalar(Select) => self.rewrite_select(inst)
    Scalar(FloatUnary(op)) => self.rewrite_float_unary(inst, op)
    Scalar(FloatBinary(op)) => self.rewrite_float_minmax(inst, op)
    Vector(op) => self.rewrite_vector(inst, op, prefix)
    _ => false
  }
  if applied {
    self.stats.applied = self.stats.applied + 1
    changed = true
  }
  if changed {
    self.stats.changed = true
  }
  self.record_definition(inst)
  changed
}
