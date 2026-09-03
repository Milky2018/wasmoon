// Direct, acyclic MilkIR rewriting.
//
// The optimizer deliberately keeps MilkIR values and instructions as the only
// expression graph. Dense tables are indexes into that graph, not a second IR.

///|
priv struct AcyclicRewriteStats {
  mut changed : Bool
  mut attempts : Int
  mut applied : Int
  mut created_instructions : Int
}

///|
fn AcyclicRewriteStats::new() -> AcyclicRewriteStats {
  { changed: false, attempts: 0, applied: 0, created_instructions: 0, }
}

///|
priv struct OptimizerSession {
  func : Function
  // Optimizer-private typed unions. Links are directional from a newly
  // defined SSA value to an older canonical value and roll back with the
  // dominator scope. Keep these arrays inline: canonical lookup is one of the
  // hottest operations in the optimizer.
  union_parents : Array[Value?]
  union_changes : Array[(Int, Value?)]
  constants : Array[Int64?]
  use_counts : Array[Int]
  mut staged_candidates : Array[Inst]?
  stats : AcyclicRewriteStats
}

///|
fn OptimizerSession::new(func : Function) -> OptimizerSession {
  let self = {
    func,
    union_parents: Array::make(func.next_value_id, None),
    union_changes: [],
    constants: Array::make(func.next_value_id, None),
    use_counts: compute_use_counts(func),
    staged_candidates: None,
    stats: AcyclicRewriteStats::new(),
  }
  for block in func.blocks {
    for inst_id in block.instructions {
      let inst = func.instructions[inst_id]
      self.index_definition(inst)
    }
  }
  self
}

///|
fn OptimizerSession::begin_candidates(self : OptimizerSession) -> Int {
  match self.staged_candidates {
    Some(candidates) => candidates.length()
    None => 0
  }
}

///|
fn OptimizerSession::stage_pure_candidate(
  self : OptimizerSession,
  opcode : Opcode,
  operands : Array[Value],
  result_type : Type,
) -> Value? {
  if !opcode.semantics().can_stage_as_pure_candidate() {
    return None
  }
  let result = self.func.new_value(result_type)
  let inst = self.func.new_inst(opcode, operands, [result])
  let candidates = match self.staged_candidates {
    Some(candidates) => candidates
    None => {
      let candidates : Array[Inst] = []
      self.staged_candidates = Some(candidates)
      candidates
    }
  }
  candidates.push(inst)
  self.index_definition(inst)
  Some(result)
}

///|
fn OptimizerSession::commit_candidates(
  self : OptimizerSession,
  marker : Int,
  output : Array[Inst],
) -> Unit {
  guard self.staged_candidates is Some(candidates) else { return }
  for index in marker..<candidates.length() {
    output.push(candidates[index])
    self.stats.created_instructions = self.stats.created_instructions + 1
  }
  candidates.truncate(marker)
}

///|
fn OptimizerSession::discard_candidates(
  self : OptimizerSession,
  marker : Int,
) -> Unit {
  guard self.staged_candidates is Some(candidates) else { return }
  for index in marker..<candidates.length() {
    self.func.owner.val.mark_instruction_deleted(candidates[index].id)
  }
  candidates.truncate(marker)
}

///|
fn OptimizerSession::begin_scope(self : OptimizerSession) -> Int {
  self.union_changes.length()
}

///|
fn OptimizerSession::end_scope(self : OptimizerSession, marker : Int) -> Unit {
  while self.union_changes.length() > marker {
    let (value_id, previous) = self.union_changes.pop().unwrap()
    self.union_parents[value_id] = previous
  }
}

///|
fn OptimizerSession::ensure_value_capacity(
  self : OptimizerSession,
  value_id : Int,
) -> Unit {
  while self.union_parents.length() <= value_id {
    self.union_parents.push(None)
    self.constants.push(None)
    self.use_counts.push(0)
  }
}

///|
fn OptimizerSession::has_single_use(
  self : OptimizerSession,
  value : Value,
) -> Bool {
  let canonical = self.canonical_value(value)
  canonical.id >= 0 &&
  canonical.id < self.use_counts.length() &&
  self.use_counts[canonical.id] == 1
}

///|
fn OptimizerSession::canonical_value(
  self : OptimizerSession,
  value : Value,
) -> Value {
  let mut current = value
  let mut remaining = self.union_parents.length()
  while remaining > 0 && current.id < self.union_parents.length() {
    match self.union_parents[current.id] {
      Some(next) if next.id != current.id => current = next
      _ => break
    }
    remaining = remaining - 1
  }
  current
}

///|
fn OptimizerSession::index_definition(
  self : OptimizerSession,
  inst : Inst,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  self.ensure_value_capacity(result.id)
  self.constants[result.id] = None
  match inst.opcode {
    Scalar(IntConst(value)) => self.constants[result.id] = Some(value)
    _ => ()
  }
}

///|
fn OptimizerSession::record_definition(
  self : OptimizerSession,
  inst : Inst,
) -> Unit {
  self.index_definition(inst)
  if inst.opcode is Scalar(Copy) &&
    inst.first_result() is Some(result) &&
    inst.operands is [source] {
    self.record_alias(result, source)
  }
}

///|
fn OptimizerSession::record_alias(
  self : OptimizerSession,
  result : Value,
  source : Value,
) -> Unit {
  self.ensure_value_capacity(result.id)
  let canonical = self.canonical_value(source)
  if self.union_parents[result.id] is Some(previous) &&
    previous.id == canonical.id {
    return
  }
  self.union_changes.push((result.id, self.union_parents[result.id]))
  self.union_parents[result.id] = Some(canonical)
  self.constants[result.id] = self.int_constant(canonical)
}

///|
fn OptimizerSession::int_constant(
  self : OptimizerSession,
  value : Value,
) -> Int64? {
  let canonical = self.canonical_value(value)
  if canonical.id >= 0 && canonical.id < self.constants.length() {
    self.constants[canonical.id]
  } else {
    None
  }
}

///|
fn OptimizerSession::definition(
  self : OptimizerSession,
  value : Value,
) -> Inst? {
  let canonical = self.canonical_value(value)
  self.func.defining_inst(canonical)
}

///|
fn OptimizerSession::canonicalize_operands(
  self : OptimizerSession,
  inst : Inst,
) -> Bool {
  let mut changed = false
  for index in 0..<inst.operands.length() {
    let canonical = self.canonical_value(inst.operands[index])
    if canonical.id != inst.operands[index].id {
      inst.operands[index] = canonical
      changed = true
    }
  }
  changed
}

///|
fn OptimizerSession::replace_with_alias(
  self : OptimizerSession,
  inst : Inst,
  source : Value,
) -> Bool {
  let canonical = self.canonical_value(source)
  inst.opcode = Scalar(Copy)
  inst.operands.clear()
  inst.operands.push(canonical)
  if inst.first_result() is Some(result) {
    self.record_alias(result, canonical)
  }
  true
}

///|
fn OptimizerSession::replace_with_constant(
  self : OptimizerSession,
  inst : Inst,
  value : Int64,
) -> Bool {
  inst.opcode = Scalar(IntConst(value))
  inst.operands.clear()
  self.record_definition(inst)
  true
}

///|
fn OptimizerSession::append_int_constant(
  self : OptimizerSession,
  output : Array[Inst],
  ty : Type,
  value : Int64,
) -> Value {
  let result = self.func.new_value(ty)
  let inst = self.func.new_inst(Scalar(IntConst(value)), [], [result])
  output.push(inst)
  self.index_definition(inst)
  self.stats.created_instructions = self.stats.created_instructions + 1
  result
}

///|
fn integer_width(ty : Type) -> Int? {
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
fn is_commutative_integer_op(op : IntBinaryOp) -> Bool {
  op is (Add | Mul | And | Or | Xor)
}

///|
fn OptimizerSession::canonicalize_commutative_constant(
  self : OptimizerSession,
  inst : Inst,
  op : IntBinaryOp,
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
fn OptimizerSession::rewrite_integer_identity(
  self : OptimizerSession,
  inst : Inst,
  op : IntBinaryOp,
  prefix : Array[Inst],
) -> Bool {
  guard inst.operands is [left, right] else { return false }
  let left_const = self.int_constant(left)
  let right_const = self.int_constant(right)
  let same = self.canonical_value(left).id == self.canonical_value(right).id
  match op {
    Add => {
      if right_const is Some(0L) {
        return self.replace_with_alias(inst, left)
      }
      if same && inst.first_result() is Some(result) {
        let one = self.append_int_constant(prefix, result.ty, 1L)
        inst.opcode = Scalar(IntBinary(ShiftLeft))
        inst.operands.clear()
        inst.operands.push(left)
        inst.operands.push(one)
        return true
      }
    }
    Sub => {
      if right_const is Some(0L) {
        return self.replace_with_alias(inst, left)
      }
      if same {
        return self.replace_with_constant(inst, 0L)
      }
    }
    Mul => {
      if right_const is Some(0L) {
        return self.replace_with_constant(inst, 0L)
      }
      if right_const is Some(1L) {
        return self.replace_with_alias(inst, left)
      }
      if right_const is Some(constant) &&
        power_of_two_shift(constant) is Some(shift) &&
        inst.first_result() is Some(result) {
        let marker = self.begin_candidates()
        guard self.stage_pure_candidate(
            Scalar(IntConst(shift.to_int64())),
            [],
            result.ty,
          )
          is Some(amount) else {
          self.discard_candidates(marker)
          return false
        }
        guard self.stage_pure_candidate(
            Scalar(IntBinary(ShiftLeft)),
            [left, amount],
            result.ty,
          )
          is Some(shifted) else {
          self.discard_candidates(marker)
          return false
        }
        self.commit_candidates(marker, prefix)
        return self.replace_with_alias(inst, shifted)
      }
    }
    And => {
      if right_const is Some(0L) {
        return self.replace_with_constant(inst, 0L)
      }
      if right_const is Some(-1L) || same {
        return self.replace_with_alias(inst, left)
      }
    }
    Or => {
      if right_const is Some(0L) || same {
        return self.replace_with_alias(inst, left)
      }
      if right_const is Some(-1L) {
        return self.replace_with_constant(inst, -1L)
      }
    }
    Xor => {
      if right_const is Some(0L) {
        return self.replace_with_alias(inst, left)
      }
      if same {
        return self.replace_with_constant(inst, 0L)
      }
    }
    ShiftLeft | SignedShiftRight | UnsignedShiftRight => {
      if right_const is Some(0L) {
        return self.replace_with_alias(inst, left)
      }
      if left_const is Some(0L) {
        return self.replace_with_constant(inst, 0L)
      }
    }
    RotateLeft | RotateRight =>
      if right_const is Some(0L) {
        return self.replace_with_alias(inst, left)
      }
    _ => ()
  }
  false
}

///|
fn OptimizerSession::rewrite_nested_integer(
  self : OptimizerSession,
  inst : Inst,
  op : IntBinaryOp,
  prefix : Array[Inst],
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
    self.int_constant(inner_right) is Some(inner_constant) &&
    self.has_single_use(left) else {
    return false
  }
  let combined : (IntBinaryOp, Int64)? = match (op, inner.opcode) {
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
  let constant = self.append_int_constant(prefix, result.ty, new_constant)
  inst.opcode = Scalar(IntBinary(new_op))
  inst.operands.clear()
  inst.operands.push(inner_left)
  inst.operands.push(constant)
  true
}

///|
fn OptimizerSession::rewrite_nested_shift(
  self : OptimizerSession,
  inst : Inst,
  op : IntBinaryOp,
  prefix : Array[Inst],
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
    inner.opcode == Scalar(IntBinary(op)) &&
    inner.operands is [source, inner_amount] &&
    self.int_constant(inner_amount) is Some(inner_constant) &&
    inst.first_result() is Some(result) &&
    integer_width(result.ty) is Some(width) else {
    return false
  }
  let total = normalized_shift(inner_constant, width) +
    normalized_shift(outer, width)
  if total >= width {
    return false
  }
  let amount = self.append_int_constant(prefix, result.ty, total.to_int64())
  inst.operands.clear()
  inst.operands.push(source)
  inst.operands.push(amount)
  true
}

///|
fn self_compare_result(cc : IntCC) -> Int64 {
  match cc {
    Eq | Sle | Sge | Ule | Uge => 1L
    Ne | Slt | Sgt | Ult | Ugt => 0L
  }
}

///|
fn OptimizerSession::rewrite_compare(
  self : OptimizerSession,
  inst : Inst,
  cc : IntCC,
) -> Bool {
  guard inst.operands is [left, right] else { return false }
  if self.canonical_value(left).id == self.canonical_value(right).id {
    return self.replace_with_constant(inst, self_compare_result(cc))
  }
  if self.int_constant(right) is Some(0L) {
    match cc {
      Ult => return self.replace_with_constant(inst, 0L)
      Uge => return self.replace_with_constant(inst, 1L)
      _ => ()
    }
  }
  false
}

///|
fn OptimizerSession::rewrite_conversion(
  self : OptimizerSession,
  inst : Inst,
  conversion : ConversionOp,
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
      inst.opcode = Scalar(Convert(UnsignedExtend))
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
    (SignedExtend, Scalar(IntCompare(_))) => {
      inst.opcode = Scalar(Convert(UnsignedExtend))
      true
    }
    _ => false
  }
}

///|
fn OptimizerSession::rewrite_select(
  self : OptimizerSession,
  inst : Inst,
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
  inst : Inst,
  prefix : Array[Inst],
) -> Bool {
  let mut changed = self.canonicalize_operands(inst)
  self.stats.attempts = self.stats.attempts + 1
  let applied = match inst.opcode {
    Scalar(IntBinary(op)) => {
      let canonicalized = self.canonicalize_commutative_constant(inst, op)
      changed = changed || canonicalized
      self.rewrite_integer_identity(inst, op, prefix) ||
      self.rewrite_nested_shift(inst, op, prefix) ||
      self.rewrite_nested_integer(inst, op, prefix)
    }
    Scalar(IntUnary(Not)) => {
      guard inst.operands is [source] else { false }
      match self.definition(source) {
        Some(inner) if inner.opcode is Scalar(IntUnary(Not)) &&
          inner.operands is [original] =>
          self.replace_with_alias(inst, original)
        _ => false
      }
    }
    Scalar(IntCompare(cc)) => self.rewrite_compare(inst, cc)
    Scalar(Convert(conversion)) => self.rewrite_conversion(inst, conversion)
    Scalar(Select) => self.rewrite_select(inst)
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
