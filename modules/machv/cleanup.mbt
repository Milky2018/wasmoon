///|
pub struct CleanupStats {
  aliases_rewritten : Int
  instructions_removed : Int
} derive(Debug, Eq)

///|
fn resolve_alias(aliases : Array[Int], value_id : Int) -> Int {
  let mut current = value_id
  while aliases[current] != current {
    current = aliases[current]
  }
  current
}

///|
fn Function::is_zero_integer_constant(self : Function, value : Value) -> Bool {
  match self.values[value.id].definition {
    InstructionResult(instruction, _) =>
      if self.instructions[instruction.id].alive {
        match self.instructions[instruction.id].operation {
          I32Const(bits) => bits == 0U
          I64Const(bits) => bits == 0UL
          _ => false
        }
      } else {
        false
      }
    _ => false
  }
}

///|
fn Function::collect_aliases(self : Function) -> Array[Int] {
  let aliases = Array::makei(self.values.length(), index => index)
  for block in self.blocks {
    for instruction in block.instructions {
      let data = self.instructions[instruction.id]
      if data.results.length() == 1 {
        match data.operation {
          Copy =>
            aliases[data.results[0].id] = resolve_alias(
              aliases,
              data.operands[0].id,
            )
          IntBinary(
            ShiftLeft
            | SignedShiftRight
            | UnsignedShiftRight
            | RotateLeft
            | RotateRight
          ) =>
            if self.is_zero_integer_constant(data.operands[1]) {
              aliases[data.results[0].id] = resolve_alias(
                aliases,
                data.operands[0].id,
              )
            }
          _ => ()
        }
      }
    }
  }
  aliases
}

///|
fn Function::rewrite_value(
  self : Function,
  value : Value,
  aliases : Array[Int],
) -> Value {
  Value::new(self.owner, resolve_alias(aliases, value.id))
}

///|
fn Function::rewrite_values(
  self : Function,
  values : Array[Value],
  aliases : Array[Int],
) -> Int {
  let mut changed = 0
  for index, value in values {
    let replacement = self.rewrite_value(value, aliases)
    if replacement != value {
      values[index] = replacement
      changed += 1
    }
  }
  changed
}

///|
fn Function::rewrite_edge(
  self : Function,
  edge : Edge,
  aliases : Array[Int],
) -> (Edge, Int) {
  let arguments = edge.arguments.copy()
  let changed = self.rewrite_values(arguments, aliases)
  (Edge::new(edge.target, arguments), changed)
}

///|
fn Function::rewrite_terminator(
  self : Function,
  record : TerminatorRecord,
  aliases : Array[Int],
) -> (TerminatorRecord, Int) {
  let mut changed = 0
  let kind = match record.kind {
    Jump(edge) => {
      let (edge, edge_changed) = self.rewrite_edge(edge, aliases)
      changed += edge_changed
      Jump(edge)
    }
    Branch(condition, true_edge, false_edge) => {
      let rewritten_condition = self.rewrite_value(condition, aliases)
      if rewritten_condition != condition {
        changed += 1
      }
      let (true_edge, true_changed) = self.rewrite_edge(true_edge, aliases)
      let (false_edge, false_changed) = self.rewrite_edge(false_edge, aliases)
      changed += true_changed + false_changed
      Branch(rewritten_condition, true_edge, false_edge)
    }
    Switch(index, cases, default_edge) => {
      let rewritten_index = self.rewrite_value(index, aliases)
      if rewritten_index != index {
        changed += 1
      }
      let rewritten_cases : Array[SwitchCase] = []
      for case in cases {
        let (edge, edge_changed) = self.rewrite_edge(case.edge, aliases)
        changed += edge_changed
        rewritten_cases.push(SwitchCase::new(case.bits, edge))
      }
      let (default_edge, default_changed) = self.rewrite_edge(
        default_edge, aliases,
      )
      changed += default_changed
      Switch(rewritten_index, rewritten_cases, default_edge)
    }
    Return(values) => {
      let values = values.copy()
      changed += self.rewrite_values(values, aliases)
      Return(values)
    }
    TailCall(call, operands) => {
      let operands = operands.copy()
      changed += self.rewrite_values(operands, aliases)
      TailCall(call, operands)
    }
    Trap(reason) => Trap(reason)
  }
  let roots = record.metadata.live_gc_roots.copy()
  changed += self.rewrite_values(roots, aliases)
  (
    TerminatorRecord::new(
      kind,
      TerminatorMetadata::new(record.metadata.source, roots),
    ),
    changed,
  )
}

///|
fn Function::rewrite_aliases(self : Function, aliases : Array[Int]) -> Int {
  let mut changed = 0
  for data in self.instructions {
    if data.alive {
      changed += self.rewrite_values(data.operands, aliases)
      changed += self.rewrite_values(data.metadata.live_gc_roots, aliases)
    }
  }
  for block_id, block in self.blocks {
    if block.terminator is Some(record) {
      let (record, rewritten) = self.rewrite_terminator(record, aliases)
      self.blocks[block_id].terminator = Some(record)
      changed += rewritten
    }
  }
  changed
}

///|
fn Function::value_use_counts(self : Function) -> Array[Int] {
  let counts = Array::make(self.values.length(), 0)
  for data in self.instructions {
    if data.alive {
      for operand in data.operands {
        counts[operand.id] += 1
      }
      for root in data.metadata.live_gc_roots {
        counts[root.id] += 1
      }
    }
  }
  for block in self.blocks {
    if block.terminator is Some(record) {
      for value in terminator_values(record.kind) {
        counts[value.id] += 1
      }
      for root in record.metadata.live_gc_roots {
        counts[root.id] += 1
      }
    }
  }
  counts
}

///|
fn Function::remove_dead_instructions(self : Function) -> Int {
  let use_counts = self.value_use_counts()
  let worklist : Array[Instruction] = []
  let queued = Array::make(self.instructions.length(), false)
  for instruction_id, data in self.instructions {
    let mut results_unused = true
    for result in data.results {
      if use_counts[result.id] != 0 {
        results_unused = false
        break
      }
    }
    if data.alive &&
      results_unused &&
      !data.operation.semantics().must_preserve_if_unused() {
      worklist.push(Instruction::new(self.owner, instruction_id))
      queued[instruction_id] = true
    }
  }
  let mut removed = 0
  let mut cursor = 0
  while cursor < worklist.length() {
    let instruction = worklist[cursor]
    cursor += 1
    let data = self.instructions[instruction.id]
    if !data.alive {
      continue
    }
    let mut results_unused = true
    for result in data.results {
      if use_counts[result.id] != 0 {
        results_unused = false
        break
      }
    }
    if !results_unused || data.operation.semantics().must_preserve_if_unused() {
      continue
    }
    data.alive = false
    data.parent = None
    for result_index, result in data.results {
      self.values[result.id].definition = RemovedInstructionResult(
        instruction, result_index,
      )
    }
    removed += 1
    let released_uses = data.operands.copy()
    released_uses.append(data.metadata.live_gc_roots)
    for operand in released_uses {
      use_counts[operand.id] -= 1
      if use_counts[operand.id] == 0 {
        match self.values[operand.id].definition {
          InstructionResult(definition, _) =>
            if self.instructions[definition.id].alive && !queued[definition.id] {
              worklist.push(definition)
              queued[definition.id] = true
            }
          _ => ()
        }
      }
    }
  }
  if removed > 0 {
    for block in self.blocks {
      let retained = block.instructions.filter(instruction => {
        self.instructions[instruction.id].alive
      })
      block.instructions.clear()
      block.instructions.append(retained)
    }
  }
  removed
}

///|
/// Mandatory target-neutral late cleanup. It performs no target or ABI query:
/// visible aliases are canonicalized and unused pure non-trapping operations
/// are removed. Observable effects, traps, calls, and safepoints are retained.
pub fn Function::run_mandatory_cleanup(
  self : Function,
) -> CleanupStats raise MachVVerifyError {
  self.verify()
  let aliases = self.collect_aliases()
  let aliases_rewritten = self.rewrite_aliases(aliases)
  let instructions_removed = self.remove_dead_instructions()
  self.verify()
  { aliases_rewritten, instructions_removed }
}
