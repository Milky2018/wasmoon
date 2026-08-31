///|
/// Construction state shared by the prepared and sealed selection handles.
priv enum SelectionPlanState {
  Prepared
  Sealed
}

///|
/// Verified semantic input that may still receive constrained target-neutral
/// elaboration before it becomes visible to target selection.
pub struct PreparedSelection {
  priv plan : SelectionPlan
}

///|
/// Immutable verified semantic input retained only for target selection.
///
/// Unlike `Function`, this type is produced directly from checked construction
/// storage. Only `PreparedSelection::seal` can create this handle, and no
/// transformation seam remains available after sealing.
pub struct SelectionPlan {
  priv construction : FunctionConstruction
  priv state : Ref[SelectionPlanState]
  priv mut verified : Bool
  priv mut layout : Array[Int]
}

///|
fn PreparedSelection::from_construction(
  construction : FunctionConstruction,
) -> PreparedSelection {
  {
    plan: { construction, state: Ref(Prepared), verified: false, layout: [], },
  }
}

///|
fn PreparedSelection::require_prepared(
  self : PreparedSelection,
) -> Unit raise MachVVerifyError {
  if self.plan.state.val is Sealed {
    raise InvalidSelectionState(
      message="selection input has already been sealed",
    )
  }
}

///|
/// Permanently seal verified semantic input for target selection.
pub fn PreparedSelection::seal(
  self : PreparedSelection,
) -> SelectionPlan raise MachVVerifyError {
  self.require_prepared()
  if !self.plan.verified {
    self.plan.verify_checked_construction()
  }
  self.plan.layout = self.plan.construction.block_indices_in_cfg_order()
  self.plan.state.val = Sealed
  self.plan
}

///|
fn SelectionPlan::mark_gc_use(
  self : SelectionPlan,
  value : Value,
  definitions : Array[Bool],
  uses : Array[Bool],
) -> Unit {
  if self.construction.values[value.id].ty == GcRef64 && !definitions[value.id] {
    uses[value.id] = true
  }
}

///|
fn SelectionPlan::compute_gc_liveness(
  self : SelectionPlan,
  successors : Array[Array[Int]],
  predecessors : Array[Array[Int]],
) -> Array[Array[Bool]] {
  let block_count = self.construction.blocks.length()
  let value_count = self.construction.values.length()
  let block_uses : Array[Array[Bool]] = []
  let block_definitions : Array[Array[Bool]] = []
  for block_id, block in self.construction.blocks {
    let definitions = Array::make(value_count, false)
    let uses = Array::make(value_count, false)
    if block_id == 0 {
      for parameter in self.construction.parameters {
        if self.construction.values[parameter.id].ty == GcRef64 {
          definitions[parameter.id] = true
        }
      }
    }
    for parameter in block.parameters {
      if self.construction.values[parameter.id].ty == GcRef64 {
        definitions[parameter.id] = true
      }
    }
    for instruction in block.instructions {
      let data = self.construction.instructions[instruction.id]
      for operand in data.operands {
        self.mark_gc_use(operand, definitions, uses)
      }
      for result in data.results {
        if self.construction.values[result.id].ty == GcRef64 {
          definitions[result.id] = true
        }
      }
    }
    if block.terminator is Some(record) {
      for value in terminator_values(record.kind) {
        self.mark_gc_use(value, definitions, uses)
      }
    }
    block_uses.push(uses)
    block_definitions.push(definitions)
  }
  let live_in : Array[Array[Bool]] = []
  let live_out : Array[Array[Bool]] = []
  for _ in 0..<block_count {
    live_in.push(Array::make(value_count, false))
    live_out.push(Array::make(value_count, false))
  }
  let worklist : Array[Int] = []
  let queued = Array::make(block_count, true)
  let mut block_id = block_count - 1
  while block_id >= 0 {
    worklist.push(block_id)
    block_id -= 1
  }
  let mut cursor = 0
  while cursor < worklist.length() {
    let block_id = worklist[cursor]
    cursor += 1
    queued[block_id] = false
    let mut input_changed = false
    for value_id in 0..<value_count {
      let mut out = false
      for successor in successors[block_id] {
        if live_in[successor][value_id] {
          out = true
          break
        }
      }
      let input = block_uses[block_id][value_id] ||
        (out && !block_definitions[block_id][value_id])
      live_out[block_id][value_id] = out
      if live_in[block_id][value_id] != input {
        live_in[block_id][value_id] = input
        input_changed = true
      }
    }
    if input_changed {
      for predecessor in predecessors[block_id] {
        if !queued[predecessor] {
          worklist.push(predecessor)
          queued[predecessor] = true
        }
      }
    }
  }
  live_out
}

///|
fn SelectionPlan::require_gc_root_coverage(
  self : SelectionPlan,
  block_id : Int,
  instruction_id : Int,
  live : Array[Bool],
  roots : Array[Value],
) -> Unit raise MachVVerifyError {
  let declared = Array::make(self.construction.values.length(), false)
  for root in roots {
    declared[root.id] = true
  }
  for value_id, is_live in live {
    if is_live &&
      self.construction.values[value_id].ty == GcRef64 &&
      !declared[value_id] {
      raise MissingGcRoot(block_id~, instruction_id~, value_id~)
    }
  }
}

///|
fn SelectionPlan::verify_gc_safepoint_roots(
  self : SelectionPlan,
  successors : Array[Array[Int]],
  predecessors : Array[Array[Int]],
) -> Unit raise MachVVerifyError {
  let mut has_gc_values = false
  for value in self.construction.values {
    if value.ty == GcRef64 {
      has_gc_values = true
      break
    }
  }
  if !has_gc_values {
    return
  }
  let live_out = self.compute_gc_liveness(successors, predecessors)
  for block_id, block in self.construction.blocks {
    let live = live_out[block_id].copy()
    if block.terminator is Some(record) {
      for value in terminator_values(record.kind) {
        if self.construction.values[value.id].ty == GcRef64 {
          live[value.id] = true
        }
      }
      match record.kind {
        TailCall(call, _) | NoReturnCall(call, _) =>
          if call.behavior.gc_safepoint {
            self.require_gc_root_coverage(
              block_id,
              -1,
              live,
              record.metadata.live_gc_roots,
            )
          }
        _ => ()
      }
    }
    let mut position = block.instructions.length() - 1
    while position >= 0 {
      let instruction = block.instructions[position]
      let data = self.construction.instructions[instruction.id]
      for result in data.results {
        if self.construction.values[result.id].ty == GcRef64 {
          live[result.id] = false
        }
      }
      for operand in data.operands {
        if self.construction.values[operand.id].ty == GcRef64 {
          live[operand.id] = true
        }
      }
      if data.operation.semantics().gc_safepoint {
        self.require_gc_root_coverage(
          block_id,
          instruction.id,
          live,
          data.metadata.live_gc_roots,
        )
      }
      position -= 1
    }
  }
}

///|
fn SelectionPlan::verify_value_use(
  self : SelectionPlan,
  value : Value,
  use_block_id : Int,
  use_position : Int,
  use_instruction_id : Int,
  instruction_blocks : Array[Int],
  instruction_positions : Array[Int],
  idom : Array[Int],
) -> Unit raise MachVVerifyError {
  if !self.construction.owns_value(value) {
    raise ForeignValue(value_id=value.id)
  }
  match self.construction.values[value.id].definition {
    FunctionParameter(_) => ()
    BlockParameter(defining_block, _) =>
      if defining_block.id != use_block_id &&
        !dominates(idom, defining_block.id, use_block_id) {
        raise NonDominatingUse(
          value_id=value.id,
          defining_block_id=defining_block.id,
          use_block_id~,
        )
      }
    InstructionResult(instruction, _) => {
      let defining_block_id = instruction_blocks[instruction.id]
      let defining_position = instruction_positions[instruction.id]
      if defining_block_id == use_block_id {
        if defining_position >= use_position {
          raise UseBeforeDefinition(
            value_id=value.id,
            block_id=use_block_id,
            instruction_id=use_instruction_id,
          )
        }
      } else if !dominates(idom, defining_block_id, use_block_id) {
        raise NonDominatingUse(
          value_id=value.id,
          defining_block_id~,
          use_block_id~,
        )
      }
    }
    RemovedInstructionResult(_, _) => raise RemovedValueUse(value_id=value.id)
  }
}

///|
fn SelectionPlan::verify_checked_construction(
  self : SelectionPlan,
) -> Unit raise MachVVerifyError {
  self.verified = false
  let block_count = self.construction.blocks.length()
  if block_count == 0 {
    raise EmptyFunction
  }
  let successors : Array[Array[Int]] = Array::makei(block_count, _ => [])
  let predecessors : Array[Array[Int]] = Array::makei(block_count, _ => [])
  let instruction_blocks = Array::make(
    self.construction.instructions.length(),
    -1,
  )
  let instruction_positions = Array::make(
    self.construction.instructions.length(),
    -1,
  )
  for block_id, block in self.construction.blocks {
    guard block.terminator is Some(record) else {
      raise MissingTerminator(block_id~)
    }
    for position, instruction in block.instructions {
      instruction_blocks[instruction.id] = block_id
      instruction_positions[instruction.id] = position
    }
    for edge in terminator_edges(record.kind) {
      successors[block_id].push(edge.target.id)
      predecessors[edge.target.id].push(block_id)
    }
  }
  if !predecessors[0].is_empty() {
    raise EntryHasPredecessor(block_id=0)
  }
  let order = reverse_postorder(successors)
  if order.length() != block_count {
    let reachable = Array::make(block_count, false)
    for block_id in order {
      reachable[block_id] = true
    }
    for block_id, is_reachable in reachable {
      if !is_reachable {
        raise UnreachableBlock(block_id~)
      }
    }
  }
  let idom = compute_dominators(successors, predecessors)
  for block_id, block in self.construction.blocks {
    for position, instruction in block.instructions {
      let data = self.construction.instructions[instruction.id]
      for operand in data.operands {
        self.verify_value_use(
          operand,
          block_id,
          position,
          instruction.id,
          instruction_blocks,
          instruction_positions,
          idom,
        )
      }
      for root in data.metadata.live_gc_roots {
        self.verify_value_use(
          root,
          block_id,
          position,
          instruction.id,
          instruction_blocks,
          instruction_positions,
          idom,
        )
      }
    }
    let record = block.terminator.unwrap()
    let use_position = block.instructions.length()
    for value in terminator_values(record.kind) {
      self.verify_value_use(
        value, block_id, use_position, -1, instruction_blocks, instruction_positions,
        idom,
      )
    }
    for root in record.metadata.live_gc_roots {
      self.verify_value_use(
        root, block_id, use_position, -1, instruction_blocks, instruction_positions,
        idom,
      )
    }
  }
  self.verify_gc_safepoint_roots(successors, predecessors)
  self.verified = true
}

///|
pub fn SelectionPlan::verify(
  self : SelectionPlan,
) -> Unit raise MachVVerifyError {
  if self.state.val is Prepared {
    raise InvalidSelectionState(
      message="selection input must be sealed before target selection",
    )
  }
  if !self.verified {
    self.verify_checked_construction()
  }
}

///|
pub fn SelectionPlan::require_verified(
  self : SelectionPlan,
) -> Unit raise MachVVerifyError {
  self.verify()
}
