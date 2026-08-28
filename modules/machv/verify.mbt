///|
/// Deterministic structured failures from the semantic MachV checkpoint.
pub suberror MachVVerifyError {
  EmptyFunction
  InvalidFunction(message~ : String)
  ForeignValue(value_id~ : Int)
  ForeignBlock(block_id~ : Int)
  ForeignInstruction(instruction_id~ : Int)
  ForeignStackObject(object_id~ : Int)
  InvalidStackObject(object_id~ : Int, message~ : String)
  TerminatorAlreadySet(block_id~ : Int)
  MissingTerminator(block_id~ : Int)
  EntryHasBlockParameters
  EntryHasPredecessor(block_id~ : Int)
  UnreachableBlock(block_id~ : Int)
  InvalidValueDefinition(value_id~ : Int)
  DuplicateValueDefinition(value_id~ : Int)
  DuplicateInstructionMembership(instruction_id~ : Int)
  OrphanInstruction(instruction_id~ : Int)
  RemovedValueUse(value_id~ : Int)
  UseBeforeDefinition(value_id~ : Int, block_id~ : Int, instruction_id~ : Int)
  NonDominatingUse(
    value_id~ : Int,
    defining_block_id~ : Int,
    use_block_id~ : Int
  )
  InvalidOperation(block_id~ : Int, message~ : String)
  InvalidInstruction(block_id~ : Int, instruction_id~ : Int, message~ : String)
  InvalidEdge(block_id~ : Int, target_id~ : Int, message~ : String)
  InvalidTerminator(block_id~ : Int, message~ : String)
  InvalidSafepoint(block_id~ : Int, message~ : String)
  MissingGcRoot(block_id~ : Int, instruction_id~ : Int, value_id~ : Int)
  InvalidMetadata(block_id~ : Int, message~ : String)
} derive(Debug, Eq)

///|
pub impl Show for MachVVerifyError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
fn is_power_of_two(value : Int) -> Bool {
  value > 0 && (value & (value - 1)) == 0
}

///|
fn terminator_values(terminator : Terminator) -> Array[Value] {
  match terminator {
    Jump(edge) => edge.arguments.copy()
    Branch(condition, true_edge, false_edge) => {
      let values = [condition]
      values.append(true_edge.arguments)
      values.append(false_edge.arguments)
      values
    }
    Switch(index, cases, default_edge) => {
      let values = [index]
      for case in cases {
        values.append(case.edge.arguments)
      }
      values.append(default_edge.arguments)
      values
    }
    Return(values) | TailCall(_, values) | NoReturnCall(_, values) =>
      values.copy()
    Trap(_) => []
  }
}

///|
fn dominates(idom : Array[Int], dominator : Int, block : Int) -> Bool {
  if dominator == block {
    return true
  }
  let mut current = block
  while current != -1 && current != 0 {
    current = idom[current]
    if current == dominator {
      return true
    }
  }
  dominator == 0 && current == 0
}

///|
fn Function::require_value(
  self : Function,
  value : Value,
) -> Unit raise MachVVerifyError {
  if !self.owns_value(value) {
    raise ForeignValue(value_id=value.id)
  }
}

///|
fn Function::require_stack_object(
  self : Function,
  object : StackObject,
) -> Unit raise MachVVerifyError {
  if !self.owns_stack_object(object) {
    raise ForeignStackObject(object_id=object.id)
  }
}

///|
fn Function::require_edge(
  self : Function,
  source_block_id : Int,
  edge : Edge,
) -> Unit raise MachVVerifyError {
  if !self.owns_block(edge.target) {
    raise ForeignBlock(block_id=edge.target.id)
  }
  let parameters = self.blocks[edge.target.id].parameters
  if edge.arguments.length() != parameters.length() {
    raise InvalidEdge(
      block_id=source_block_id,
      target_id=edge.target.id,
      message="edge expects \{parameters.length()} arguments, got \{edge.arguments.length()}",
    )
  }
  for index, argument in edge.arguments {
    self.require_value(argument)
    let actual = self.values[argument.id].ty
    let expected = self.values[parameters[index].id].ty
    if actual != expected {
      raise InvalidEdge(
        block_id=source_block_id,
        target_id=edge.target.id,
        message="edge argument \{index} has type \{actual}, expected \{expected}",
      )
    }
  }
}

///|
fn Function::verify_metadata(
  self : Function,
  block_id : Int,
  semantics : OperationSemantics,
  metadata : InstructionMetadata,
) -> Unit raise MachVVerifyError {
  if metadata.source is Some(source) && !source.is_valid() {
    raise InvalidMetadata(
      block_id~,
      message="source location requires a non-empty file and non-negative coordinates",
    )
  }
  if !semantics.gc_safepoint && !metadata.live_gc_roots.is_empty() {
    raise InvalidSafepoint(
      block_id~,
      message="live GC roots require a GC safepoint operation",
    )
  }
  if metadata.stack_map is Some(stack_map) {
    if !semantics.gc_safepoint {
      raise InvalidMetadata(
        block_id~,
        message="stack-map metadata requires a GC safepoint operation",
      )
    }
    if stack_map.id < 0 || stack_map.argument_root_count < 0 {
      raise InvalidMetadata(
        block_id~,
        message="stack-map id and argument root count must be non-negative",
      )
    }
  }
  for index, root in metadata.live_gc_roots {
    self.require_value(root)
    if self.values[root.id].ty != GcRef64 {
      raise InvalidSafepoint(
        block_id~,
        message="live GC roots must have type gcref64",
      )
    }
    for previous in 0..<index {
      if metadata.live_gc_roots[previous] == root {
        raise InvalidSafepoint(
          block_id~,
          message="live GC roots must not contain duplicates",
        )
      }
    }
  }
}

///|
fn Function::verify_terminator_shape(
  self : Function,
  block_id : Int,
  record : TerminatorRecord,
) -> Unit raise MachVVerifyError {
  let terminator = record.kind
  if record.metadata.source is Some(source) && !source.is_valid() {
    raise InvalidMetadata(
      block_id~,
      message="source location requires a non-empty file and non-negative coordinates",
    )
  }
  for edge in terminator_edges(terminator) {
    self.require_edge(block_id, edge)
  }
  match terminator {
    Jump(_) | Trap(_) => ()
    Branch(condition, _, _) => {
      self.require_value(condition)
      if self.values[condition.id].ty != I32 {
        raise InvalidTerminator(
          block_id~,
          message="branch condition must have type i32",
        )
      }
    }
    Switch(index, cases, _) => {
      self.require_value(index)
      let index_type = self.values[index.id].ty
      if index_type != I32 && index_type != I64 {
        raise InvalidTerminator(
          block_id~,
          message="switch index must have type i32 or i64",
        )
      }
      for case_index, case in cases {
        if index_type == I32 && case.bits > 0xFFFFFFFFUL {
          raise InvalidTerminator(
            block_id~,
            message="i32 switch case value exceeds 32 bits",
          )
        }
        for previous in 0..<case_index {
          if cases[previous].bits == case.bits {
            raise InvalidTerminator(
              block_id~,
              message="switch case values must be unique",
            )
          }
        }
      }
    }
    Return(values) => {
      for value in values {
        self.require_value(value)
      }
      if values.length() != self.signature.results.length() {
        raise InvalidTerminator(
          block_id~,
          message="return expects \{self.signature.results.length()} values, got \{values.length()}",
        )
      }
      for index, value in values {
        let actual = self.values[value.id].ty
        let expected = self.signature.results[index]
        if actual != expected {
          raise InvalidTerminator(
            block_id~,
            message="return value \{index} has type \{actual}, expected \{expected}",
          )
        }
      }
    }
    TailCall(call, operands) => {
      for operand in operands {
        self.require_value(operand)
      }
      if call.signature.results != self.signature.results {
        raise InvalidTerminator(
          block_id~,
          message="tail-call results must match the enclosing function",
        )
      }
      if call.behavior.returns_twice {
        raise InvalidTerminator(
          block_id~,
          message="tail call cannot return twice",
        )
      }
      if verify_call_operands(
          call,
          operands.map(value => self.values[value.id].ty),
          "tail_call",
        )
        is Some(message) {
        raise InvalidTerminator(block_id~, message~)
      }
      let behavior = call.behavior.semantics()
      if !behavior.gc_safepoint && !record.metadata.live_gc_roots.is_empty() {
        raise InvalidSafepoint(
          block_id~,
          message="tail-call live GC roots require a GC safepoint",
        )
      }
    }
    NoReturnCall(call, operands) => {
      for operand in operands {
        self.require_value(operand)
      }
      if !call.signature.results.is_empty() {
        raise InvalidTerminator(
          block_id~,
          message="noreturn call must not declare results",
        )
      }
      if call.behavior.returns_twice {
        raise InvalidTerminator(
          block_id~,
          message="noreturn call cannot return twice",
        )
      }
      if verify_call_operands(
          call,
          operands.map(value => self.values[value.id].ty),
          "noreturn_call",
        )
        is Some(message) {
        raise InvalidTerminator(block_id~, message~)
      }
      let behavior = call.behavior.semantics()
      if !behavior.gc_safepoint && !record.metadata.live_gc_roots.is_empty() {
        raise InvalidSafepoint(
          block_id~,
          message="noreturn-call live GC roots require a GC safepoint",
        )
      }
    }
  }
  let permits_gc_roots = match terminator {
    TailCall(call, _) | NoReturnCall(call, _) => call.behavior.gc_safepoint
    Jump(_) | Branch(_, _, _) | Switch(_, _, _) | Return(_) | Trap(_) => false
  }
  if !permits_gc_roots && !record.metadata.live_gc_roots.is_empty() {
    raise InvalidSafepoint(
      block_id~,
      message="terminator live GC roots require a GC safepoint",
    )
  }
  for index, root in record.metadata.live_gc_roots {
    self.require_value(root)
    if self.values[root.id].ty != GcRef64 {
      raise InvalidSafepoint(
        block_id~,
        message="terminator live GC roots must have type gcref64",
      )
    }
    for previous in 0..<index {
      if record.metadata.live_gc_roots[previous] == root {
        raise InvalidSafepoint(
          block_id~,
          message="terminator live GC roots must not contain duplicates",
        )
      }
    }
  }
}

///|
fn Function::mark_gc_use(
  self : Function,
  value : Value,
  definitions : Array[Bool],
  uses : Array[Bool],
) -> Unit {
  if self.values[value.id].ty == GcRef64 && !definitions[value.id] {
    uses[value.id] = true
  }
}

///|
fn Function::compute_gc_liveness(
  self : Function,
  successors : Array[Array[Int]],
  predecessors : Array[Array[Int]],
) -> Array[Array[Bool]] {
  let block_count = self.blocks.length()
  let value_count = self.values.length()
  let block_uses : Array[Array[Bool]] = []
  let block_definitions : Array[Array[Bool]] = []
  for block_id, block in self.blocks {
    let definitions = Array::make(value_count, false)
    let uses = Array::make(value_count, false)
    if block_id == 0 {
      for parameter in self.parameters {
        if self.values[parameter.id].ty == GcRef64 {
          definitions[parameter.id] = true
        }
      }
    }
    for parameter in block.parameters {
      if self.values[parameter.id].ty == GcRef64 {
        definitions[parameter.id] = true
      }
    }
    for instruction in block.instructions {
      let data = self.instructions[instruction.id]
      for operand in data.operands {
        self.mark_gc_use(operand, definitions, uses)
      }
      for result in data.results {
        if self.values[result.id].ty == GcRef64 {
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
fn Function::require_gc_root_coverage(
  self : Function,
  block_id : Int,
  instruction_id : Int,
  live : Array[Bool],
  roots : Array[Value],
) -> Unit raise MachVVerifyError {
  let declared = Array::make(self.values.length(), false)
  for root in roots {
    declared[root.id] = true
  }
  for value_id, is_live in live {
    if is_live && self.values[value_id].ty == GcRef64 && !declared[value_id] {
      raise MissingGcRoot(block_id~, instruction_id~, value_id~)
    }
  }
}

///|
fn Function::verify_gc_safepoint_roots(
  self : Function,
  successors : Array[Array[Int]],
  predecessors : Array[Array[Int]],
) -> Unit raise MachVVerifyError {
  let mut has_gc_values = false
  for value in self.values {
    if value.ty == GcRef64 {
      has_gc_values = true
      break
    }
  }
  if !has_gc_values {
    return
  }
  let live_out = self.compute_gc_liveness(successors, predecessors)
  for block_id, block in self.blocks {
    let live = live_out[block_id].copy()
    if block.terminator is Some(record) {
      for value in terminator_values(record.kind) {
        if self.values[value.id].ty == GcRef64 {
          live[value.id] = true
        }
      }
      match record.kind {
        TailCall(call, _) =>
          if call.behavior.gc_safepoint {
            self.require_gc_root_coverage(
              block_id,
              -1,
              live,
              record.metadata.live_gc_roots,
            )
          }
        NoReturnCall(call, _) =>
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
      let data = self.instructions[instruction.id]
      for result in data.results {
        if self.values[result.id].ty == GcRef64 {
          live[result.id] = false
        }
      }
      for operand in data.operands {
        if self.values[operand.id].ty == GcRef64 {
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
fn Function::verify_value_use(
  self : Function,
  value : Value,
  use_block_id : Int,
  use_position : Int,
  use_instruction_id : Int,
  instruction_blocks : Array[Int],
  instruction_positions : Array[Int],
  idom : Array[Int],
) -> Unit raise MachVVerifyError {
  self.require_value(value)
  match self.values[value.id].definition {
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
      if !self.owns_instruction(instruction) ||
        !self.instructions[instruction.id].alive {
        raise RemovedValueUse(value_id=value.id)
      }
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
    RemovedInstructionResult(instruction, result_index) => {
      if !self.owns_instruction(instruction) ||
        result_index < 0 ||
        result_index >= self.instructions[instruction.id].results.length() ||
        self.instructions[instruction.id].results[result_index] != value {
        raise InvalidValueDefinition(value_id=value.id)
      }
      raise RemovedValueUse(value_id=value.id)
    }
  }
}

///|
/// Verify the complete target-neutral MachV checkpoint without consulting a
/// target, ABI, construction history, or mutable validator callback.
pub fn Function::verify(self : Function) -> Unit raise MachVVerifyError {
  self.verified = false
  if self.blocks.is_empty() {
    raise EmptyFunction
  }
  for object_id, object in self.stack_objects {
    if object.size <= 0 {
      raise InvalidStackObject(
        object_id~,
        message="stack object size must be positive",
      )
    }
    if !is_power_of_two(object.alignment) {
      raise InvalidStackObject(
        object_id~,
        message="stack object alignment must be a positive power of two",
      )
    }
  }
  if !self.blocks[0].parameters.is_empty() {
    raise EntryHasBlockParameters
  }
  let definitions = Array::make(self.values.length(), false)
  for index, parameter in self.parameters {
    self.require_value(parameter)
    match self.values[parameter.id].definition {
      FunctionParameter(actual_index) =>
        if actual_index != index {
          raise InvalidValueDefinition(value_id=parameter.id)
        }
      _ => raise InvalidValueDefinition(value_id=parameter.id)
    }
    if self.values[parameter.id].ty != self.signature.params[index] {
      raise InvalidValueDefinition(value_id=parameter.id)
    }
    if definitions[parameter.id] {
      raise DuplicateValueDefinition(value_id=parameter.id)
    }
    definitions[parameter.id] = true
  }
  let instruction_blocks = Array::make(self.instructions.length(), -1)
  let instruction_positions = Array::make(self.instructions.length(), -1)
  let instruction_membership = Array::make(self.instructions.length(), false)
  let stack_map_ids : Array[Int] = []
  for block_id, block in self.blocks {
    if block.terminator is None {
      raise MissingTerminator(block_id~)
    }
    for parameter_index, parameter in block.parameters {
      self.require_value(parameter)
      match self.values[parameter.id].definition {
        BlockParameter(defining_block, defining_index) =>
          if defining_block.id != block_id || defining_index != parameter_index {
            raise InvalidValueDefinition(value_id=parameter.id)
          }
        _ => raise InvalidValueDefinition(value_id=parameter.id)
      }
      if definitions[parameter.id] {
        raise DuplicateValueDefinition(value_id=parameter.id)
      }
      definitions[parameter.id] = true
    }
    for position, instruction in block.instructions {
      if !self.owns_instruction(instruction) {
        raise ForeignInstruction(instruction_id=instruction.id)
      }
      if instruction_membership[instruction.id] {
        raise DuplicateInstructionMembership(instruction_id=instruction.id)
      }
      instruction_membership[instruction.id] = true
      instruction_blocks[instruction.id] = block_id
      instruction_positions[instruction.id] = position
      let data = self.instructions[instruction.id]
      if !data.alive || data.parent != Some(Block::new(self.owner, block_id)) {
        raise OrphanInstruction(instruction_id=instruction.id)
      }
      for operand in data.operands {
        self.require_value(operand)
      }
      if data.operation is StackAddress(object) {
        self.require_stack_object(object)
      }
      for result_index, result in data.results {
        self.require_value(result)
        match self.values[result.id].definition {
          InstructionResult(defining_instruction, defining_index) =>
            if defining_instruction != instruction ||
              defining_index != result_index {
              raise InvalidValueDefinition(value_id=result.id)
            }
          _ => raise InvalidValueDefinition(value_id=result.id)
        }
        if definitions[result.id] {
          raise DuplicateValueDefinition(value_id=result.id)
        }
        definitions[result.id] = true
      }
      if verify_operation_contract(
          data.operation,
          data.operands.map(value => self.values[value.id].ty),
          data.results.map(value => self.values[value.id].ty),
        )
        is Some(message) {
        raise InvalidInstruction(
          block_id~,
          instruction_id=instruction.id,
          message~,
        )
      }
      self.verify_metadata(block_id, data.operation.semantics(), data.metadata)
      if data.metadata.stack_map is Some(stack_map) {
        if stack_map_ids.contains(stack_map.id) {
          raise InvalidMetadata(
            block_id~,
            message="stack-map ids must be unique and dense from zero",
          )
        }
        stack_map_ids.push(stack_map.id)
      }
    }
    if block.terminator is Some(record) {
      self.verify_terminator_shape(block_id, record)
    }
  }
  for instruction_id, data in self.instructions {
    if data.alive && !instruction_membership[instruction_id] {
      raise OrphanInstruction(instruction_id~)
    }
  }
  for id in 0..<stack_map_ids.length() {
    if !stack_map_ids.contains(id) {
      raise InvalidMetadata(
        block_id=0,
        message="stack-map ids must be unique and dense from zero",
      )
    }
  }
  for value_id, data in self.values {
    match data.definition {
      RemovedInstructionResult(instruction, result_index) =>
        if !self.owns_instruction(instruction) ||
          self.instructions[instruction.id].alive ||
          result_index < 0 ||
          result_index >= self.instructions[instruction.id].results.length() ||
          self.instructions[instruction.id].results[result_index].id != value_id {
          raise InvalidValueDefinition(value_id~)
        }
      _ => if !definitions[value_id] { raise InvalidValueDefinition(value_id~) }
    }
  }
  let (successors, predecessors) = build_cfg(self)
  if !predecessors[0].is_empty() {
    raise EntryHasPredecessor(block_id=0)
  }
  let order = reverse_postorder(successors)
  if order.length() != self.blocks.length() {
    let reachable = Array::make(self.blocks.length(), false)
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
  for block_id, block in self.blocks {
    for position, instruction in block.instructions {
      let data = self.instructions[instruction.id]
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
    if block.terminator is Some(record) {
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
  }
  self.verify_gc_safepoint_roots(successors, predecessors)
  self.verified = true
}

///|
/// Require the canonical function state established by its last verifier.
///
/// Public construction and transformation seams finish by verifying. If a
/// package-internal producer has not done so, this falls back to full
/// verification instead of trusting construction history.
pub fn Function::require_verified(
  self : Function,
) -> Unit raise MachVVerifyError {
  if !self.verified {
    self.verify()
  }
}
