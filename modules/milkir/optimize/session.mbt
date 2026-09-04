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
  func : @milkir.Function
  // Optimizer-private typed unions. Links are directional from a newly
  // defined SSA value to an older canonical value and roll back with the
  // dominator scope. Keep these arrays inline: canonical lookup is one of the
  // hottest operations in the optimizer.
  union_parents : Array[@milkir.Value?]
  union_changes : Array[(Int, @milkir.Value?)]
  constants : Array[Int64?]
  use_counts : Array[Int]
  mut staged_candidates : Array[@milkir.Inst]?
  stats : AcyclicRewriteStats
}

///|
fn OptimizerSession::new(func : @milkir.Function) -> OptimizerSession {
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
    for inst_id in block.instruction_ids() {
      let inst = func.instruction_by_id(inst_id).unwrap()
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
  opcode : @milkir.Opcode,
  operands : Array[@milkir.Value],
  result_type : @milkir.Type,
) -> @milkir.Value? {
  if !opcode.semantics().can_stage_as_pure_candidate() {
    return None
  }
  let opcode : @milkir.Opcode = match (opcode, operands) {
    (Scalar(IntBinary(op)), [a, b]) =>
      if self.int_constant(a) is Some(a) &&
        self.int_constant(b) is Some(b) &&
        integer_width(result_type) is Some(width) &&
        fold_pure_integer_binary(op, a, b, width) is Some(value) {
        operands.clear()
        Scalar(IntConst(value))
      } else {
        opcode
      }
    _ => opcode
  }
  let result = self.func.new_value(result_type)
  let inst = self.func.new_inst(opcode, operands, [result])
  let candidates = match self.staged_candidates {
    Some(candidates) => candidates
    None => {
      let candidates : Array[@milkir.Inst] = []
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
  output : Array[@milkir.Inst],
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
    self.func.discard_inst(candidates[index])
  }
  candidates.truncate(marker)
}

///|
fn pure_candidate_cost(opcode : @milkir.Opcode) -> Int {
  match opcode {
    Scalar(IntConst(_) | FloatConst32(_) | FloatConst64(_) | Copy) => 0
    // This is an IR-complexity cost, not a target latency table. Integer
    // multiplication has greater algebraic complexity than the other pure
    // scalar primitives; target-specific instruction costs remain in target
    // lowering.
    Scalar(IntBinary(Mul)) | Vector(IntBinary(Mul, _)) => 2
    _ => 1
  }
}

///|
fn OptimizerSession::commit_candidates_if_cheaper(
  self : OptimizerSession,
  marker : Int,
  original_cost : Int,
  output : Array[@milkir.Inst],
) -> Bool {
  guard self.staged_candidates is Some(candidates) else { return false }
  let mut candidate_cost = 0
  for index in marker..<candidates.length() {
    candidate_cost = candidate_cost +
      pure_candidate_cost(candidates[index].opcode)
  }
  if candidate_cost >= original_cost {
    self.discard_candidates(marker)
    return false
  }
  self.commit_candidates(marker, output)
  true
}

///|
fn OptimizerSession::stage_int_binary_with_constant(
  self : OptimizerSession,
  op : @milkir.IntBinaryOp,
  left : @milkir.Value,
  result_type : @milkir.Type,
  constant : Int64,
) -> @milkir.Value? {
  guard self.stage_pure_candidate(Scalar(IntConst(constant)), [], result_type)
    is Some(right) else {
    return None
  }
  self.stage_pure_candidate(Scalar(IntBinary(op)), [left, right], result_type)
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
  value : @milkir.Value,
) -> Bool {
  let canonical = self.canonical_value(value)
  canonical.id >= 0 &&
  canonical.id < self.use_counts.length() &&
  self.use_counts[canonical.id] == 1
}

///|
fn OptimizerSession::canonical_value(
  self : OptimizerSession,
  value : @milkir.Value,
) -> @milkir.Value {
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
  inst : @milkir.Inst,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  self.ensure_value_capacity(result.id)
  self.constants[result.id] = None
  match inst.opcode {
    Scalar(IntConst(value)) =>
      self.constants[result.id] = Some(
        if result.ty == I32 {
          value.to_int().to_int64()
        } else {
          value
        },
      )
    _ => ()
  }
}

///|
fn OptimizerSession::record_definition(
  self : OptimizerSession,
  inst : @milkir.Inst,
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
  result : @milkir.Value,
  source : @milkir.Value,
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
  value : @milkir.Value,
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
  value : @milkir.Value,
) -> @milkir.Inst? {
  let canonical = self.canonical_value(value)
  self.func.defining_inst(canonical)
}

///|
fn OptimizerSession::canonicalize_operands(
  self : OptimizerSession,
  inst : @milkir.Inst,
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
  inst : @milkir.Inst,
  source : @milkir.Value,
) -> Bool {
  let canonical = self.canonical_value(source)
  inst.set_opcode(Scalar(Copy))
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
  inst : @milkir.Inst,
  value : Int64,
) -> Bool {
  inst.set_opcode(Scalar(IntConst(value)))
  inst.operands.clear()
  self.record_definition(inst)
  true
}
