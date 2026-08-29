///|
/// Owner-aware construction seam for semantic MachV functions.
pub struct FunctionBuilder {
  priv construction : FunctionConstruction
  priv mut current_block : Block
  priv mut construction_error : MachVVerifyError?
  priv stack_map_ids : Array[Bool]
  priv mut stack_map_count : Int
  priv copy_inputs : Bool
}

///|
pub fn FunctionBuilder::new(
  name : String,
  protocol : CallProtocol,
  params : Array[ValueType],
  results : Array[ValueType],
) -> FunctionBuilder {
  FunctionBuilder::new_with_storage_policy(
    name, protocol, params, results, true,
  )
}

///|
/// Create a checked builder for direct immutable selection-plan production.
/// Emitted operation and operand collections are consumed without defensive
/// copies; the producer must not mutate them after emission.
pub fn FunctionBuilder::new_selection_plan(
  name : String,
  protocol : CallProtocol,
  params : Array[ValueType],
  results : Array[ValueType],
) -> FunctionBuilder {
  FunctionBuilder::new_with_storage_policy(
    name, protocol, params, results, false,
  )
}

///|
fn FunctionBuilder::new_with_storage_policy(
  name : String,
  protocol : CallProtocol,
  params : Array[ValueType],
  results : Array[ValueType],
  copy_inputs : Bool,
) -> FunctionBuilder {
  let construction = FunctionConstruction::new(
    name,
    protocol,
    Signature::new(params, results),
  )
  let builder = {
    construction,
    current_block: Block::new(construction.owner, 0),
    construction_error: None,
    stack_map_ids: [],
    stack_map_count: 0,
    copy_inputs,
  }
  if name.is_empty() {
    builder.record_error(
      InvalidFunction(message="function name must not be empty"),
    )
  }
  builder
}

///|
fn FunctionBuilder::record_error(
  self : FunctionBuilder,
  error : MachVVerifyError,
) -> Unit {
  if self.construction_error is None {
    self.construction_error = Some(error)
  }
}

///|
pub fn FunctionBuilder::parameters(self : FunctionBuilder) -> Array[Value] {
  self.construction.parameters.copy()
}

///|
pub fn FunctionBuilder::entry_block(self : FunctionBuilder) -> Block {
  Block::new(self.construction.owner, 0)
}

///|
pub fn FunctionBuilder::current_block(self : FunctionBuilder) -> Block {
  self.current_block
}

///|
pub fn FunctionBuilder::create_block(
  self : FunctionBuilder,
  parameter_types : Array[ValueType],
) -> Block {
  self.construction.allocate_block(parameter_types)
}

///|
pub fn FunctionBuilder::create_stack_object(
  self : FunctionBuilder,
  size : Int,
  alignment : Int,
) -> StackObject {
  if size <= 0 {
    self.record_error(
      InvalidStackObject(
        object_id=self.construction.stack_objects.length(),
        message="stack object size must be positive",
      ),
    )
    return StackObject::new(self.construction.owner, -1)
  }
  if !is_power_of_two(alignment) {
    self.record_error(
      InvalidStackObject(
        object_id=self.construction.stack_objects.length(),
        message="stack object alignment must be a positive power of two",
      ),
    )
    return StackObject::new(self.construction.owner, -1)
  }
  self.construction.allocate_stack_object(size, alignment)
}

///|
pub fn FunctionBuilder::block_parameters(
  self : FunctionBuilder,
  block : Block,
) -> Array[Value] {
  if !self.construction.owns_block(block) {
    self.record_error(ForeignBlock(block_id=block.id))
    return []
  }
  self.construction.block_parameters(block)
}

///|
/// Read the type of a value owned by this checked construction.
pub fn FunctionBuilder::value_type(
  self : FunctionBuilder,
  value : Value,
) -> ValueType? {
  self.construction.value_type(value)
}

///|
pub fn FunctionBuilder::switch_to_block(
  self : FunctionBuilder,
  block : Block,
) -> Unit {
  if !self.construction.owns_block(block) {
    self.record_error(ForeignBlock(block_id=block.id))
    return
  }
  self.current_block = block
}

///|
fn FunctionBuilder::require_values(
  self : FunctionBuilder,
  values : Array[Value],
) -> Bool {
  for value in values {
    if !self.construction.owns_value(value) {
      self.record_error(ForeignValue(value_id=value.id))
      return false
    }
  }
  true
}

///|
fn FunctionBuilder::require_block_open(self : FunctionBuilder) -> Bool {
  if self.construction.blocks[self.current_block.id].terminator is Some(_) {
    self.record_error(TerminatorAlreadySet(block_id=self.current_block.id))
    return false
  }
  true
}

///|
fn FunctionBuilder::value_types(
  self : FunctionBuilder,
  values : Array[Value],
) -> Array[ValueType] {
  values.map(value => self.construction.values[value.id].ty)
}

///|
fn FunctionBuilder::require_unique_roots(
  self : FunctionBuilder,
  roots : Array[Value],
) -> Bool {
  for index, root in roots {
    for earlier in 0..<index {
      if roots[earlier] == root {
        self.record_error(
          InvalidSafepoint(
            block_id=self.current_block.id,
            message="live GC roots must not contain duplicates",
          ),
        )
        return false
      }
    }
  }
  true
}

///|
fn FunctionBuilder::record_stack_map(
  self : FunctionBuilder,
  stack_map_id : Int?,
) -> Unit {
  if stack_map_id is Some(id) {
    while self.stack_map_ids.length() <= id {
      self.stack_map_ids.push(false)
    }
    self.stack_map_ids[id] = true
    self.stack_map_count += 1
  }
}

///|
/// Append one parameterized semantic operation after validating its local
/// ownership and typed operation contract.
pub fn FunctionBuilder::emit(
  self : FunctionBuilder,
  operation : Operation,
  operands : Array[Value],
  result_types : Array[ValueType],
) -> Array[Value] {
  self.emit_with_metadata(
    operation,
    operands,
    result_types,
    InstructionMetadata::empty(),
  )
}

///|
pub fn FunctionBuilder::emit_with_metadata(
  self : FunctionBuilder,
  operation : Operation,
  operands : Array[Value],
  result_types : Array[ValueType],
  metadata : InstructionMetadata,
) -> Array[Value] {
  if !self.require_block_open() ||
    !self.require_values(operands) ||
    !self.require_values(metadata.live_gc_roots) ||
    !self.require_unique_roots(metadata.live_gc_roots) {
    return []
  }
  if operation is StackAddress(object) &&
    !self.construction.owns_stack_object(object) {
    self.record_error(ForeignStackObject(object_id=object.id))
    return []
  }
  if metadata.source is Some(source) && !source.is_valid() {
    self.record_error(
      InvalidMetadata(
        block_id=self.current_block.id,
        message="source location requires a non-empty file and non-negative coordinates",
      ),
    )
    return []
  }
  let operand_types = self.value_types(operands)
  if verify_operation_contract(operation, operand_types, result_types)
    is Some(message) {
    self.record_error(
      InvalidOperation(block_id=self.current_block.id, message~),
    )
    return []
  }
  let semantics = operation.semantics()
  let stack_map_id = match metadata.stack_map {
    Some(stack_map) => {
      if !semantics.gc_safepoint {
        self.record_error(
          InvalidMetadata(
            block_id=self.current_block.id,
            message="stack-map metadata requires a GC safepoint operation",
          ),
        )
        return []
      }
      if stack_map.id < 0 || stack_map.argument_root_count < 0 {
        self.record_error(
          InvalidMetadata(
            block_id=self.current_block.id,
            message="stack-map id and argument root count must be non-negative",
          ),
        )
        return []
      }
      if stack_map.id < self.stack_map_ids.length() &&
        self.stack_map_ids[stack_map.id] {
        self.record_error(
          InvalidMetadata(
            block_id=self.current_block.id,
            message="stack-map ids must be unique and dense from zero",
          ),
        )
        return []
      }
      Some(stack_map.id)
    }
    None => None
  }
  if !semantics.gc_safepoint && !metadata.live_gc_roots.is_empty() {
    self.record_error(
      InvalidSafepoint(
        block_id=self.current_block.id,
        message="live GC roots require a GC safepoint operation",
      ),
    )
    return []
  }
  for root in metadata.live_gc_roots {
    if self.construction.values[root.id].ty != GcRef64 {
      self.record_error(
        InvalidSafepoint(
          block_id=self.current_block.id,
          message="live GC roots must have type gcref64",
        ),
      )
      return []
    }
  }
  let results = self.construction.append_instruction(
    self.current_block,
    operation,
    operands,
    result_types,
    metadata,
    self.copy_inputs,
  )
  self.record_stack_map(stack_map_id)
  results
}

///|
fn FunctionBuilder::validate_edge(
  self : FunctionBuilder,
  target : Block,
  arguments : Array[Value],
  context : String,
) -> Bool {
  if !self.construction.owns_block(target) {
    self.record_error(ForeignBlock(block_id=target.id))
    return false
  }
  if !self.require_values(arguments) {
    return false
  }
  let parameters = self.construction.blocks[target.id].parameters
  if arguments.length() != parameters.length() {
    self.record_error(
      InvalidEdge(
        block_id=self.current_block.id,
        target_id=target.id,
        message="\{context} expects \{parameters.length()} arguments, got \{arguments.length()}",
      ),
    )
    return false
  }
  for index, argument in arguments {
    let actual = self.construction.values[argument.id].ty
    let expected = self.construction.values[parameters[index].id].ty
    if actual != expected {
      self.record_error(
        InvalidEdge(
          block_id=self.current_block.id,
          target_id=target.id,
          message="\{context} argument \{index} has type \{actual}, expected \{expected}",
        ),
      )
      return false
    }
  }
  true
}

///|
pub fn FunctionBuilder::jump(
  self : FunctionBuilder,
  target : Block,
  arguments : Array[Value],
) -> Unit {
  if !self.require_block_open() ||
    !self.validate_edge(target, arguments, "jump") {
    return
  }
  self.construction.blocks[self.current_block.id].terminator = Some(
    TerminatorRecord::new(
      Jump(Edge::new(target, arguments)),
      TerminatorMetadata::empty(),
    ),
  )
}

///|
pub fn FunctionBuilder::branch(
  self : FunctionBuilder,
  condition : Value,
  true_target : Block,
  true_arguments : Array[Value],
  false_target : Block,
  false_arguments : Array[Value],
) -> Unit {
  if !self.require_block_open() || !self.require_values([condition]) {
    return
  }
  if self.construction.values[condition.id].ty != I32 {
    self.record_error(
      InvalidTerminator(
        block_id=self.current_block.id,
        message="branch condition must have type i32",
      ),
    )
    return
  }
  if !self.validate_edge(true_target, true_arguments, "branch") ||
    !self.validate_edge(false_target, false_arguments, "branch") {
    return
  }
  self.construction.blocks[self.current_block.id].terminator = Some(
    TerminatorRecord::new(
      Branch(
        condition,
        Edge::new(true_target, true_arguments),
        Edge::new(false_target, false_arguments),
      ),
      TerminatorMetadata::empty(),
    ),
  )
}

///|
pub fn FunctionBuilder::switch(
  self : FunctionBuilder,
  index : Value,
  cases : Array[(UInt64, Block, Array[Value])],
  default_target : Block,
  default_arguments : Array[Value],
) -> Unit {
  if !self.require_block_open() || !self.require_values([index]) {
    return
  }
  let index_type = self.construction.values[index.id].ty
  if index_type != I32 && index_type != I64 {
    self.record_error(
      InvalidTerminator(
        block_id=self.current_block.id,
        message="switch index must have type i32 or i64",
      ),
    )
    return
  }
  let switch_cases : Array[SwitchCase] = []
  for case_index, item in cases {
    let (bits, target, arguments) = item
    if index_type == I32 && bits > 0xFFFFFFFFUL {
      self.record_error(
        InvalidTerminator(
          block_id=self.current_block.id,
          message="i32 switch case value exceeds 32 bits",
        ),
      )
      return
    }
    for previous in 0..<case_index {
      if cases[previous].0 == bits {
        self.record_error(
          InvalidTerminator(
            block_id=self.current_block.id,
            message="switch case values must be unique",
          ),
        )
        return
      }
    }
    if !self.validate_edge(target, arguments, "switch") {
      return
    }
    switch_cases.push(SwitchCase::new(bits, Edge::new(target, arguments)))
  }
  if !self.validate_edge(default_target, default_arguments, "switch") {
    return
  }
  self.construction.blocks[self.current_block.id].terminator = Some(
    TerminatorRecord::new(
      Switch(index, switch_cases, Edge::new(default_target, default_arguments)),
      TerminatorMetadata::empty(),
    ),
  )
}

///|
pub fn FunctionBuilder::return_(
  self : FunctionBuilder,
  values : Array[Value],
) -> Unit {
  if !self.require_block_open() || !self.require_values(values) {
    return
  }
  if values.length() != self.construction.signature.results.length() {
    self.record_error(
      InvalidTerminator(
        block_id=self.current_block.id,
        message="return expects \{self.construction.signature.results.length()} values, got \{values.length()}",
      ),
    )
    return
  }
  for index, value in values {
    let actual = self.construction.values[value.id].ty
    let expected = self.construction.signature.results[index]
    if actual != expected {
      self.record_error(
        InvalidTerminator(
          block_id=self.current_block.id,
          message="return value \{index} has type \{actual}, expected \{expected}",
        ),
      )
      return
    }
  }
  self.construction.blocks[self.current_block.id].terminator = Some(
    TerminatorRecord::new(Return(values.copy()), TerminatorMetadata::empty()),
  )
}

///|
pub fn FunctionBuilder::tail_call(
  self : FunctionBuilder,
  call : SemanticCall,
  operands : Array[Value],
) -> Unit {
  self.tail_call_with_metadata(call, operands, TerminatorMetadata::empty())
}

///|
pub fn FunctionBuilder::tail_call_with_metadata(
  self : FunctionBuilder,
  call : SemanticCall,
  operands : Array[Value],
  metadata : TerminatorMetadata,
) -> Unit {
  if !self.require_block_open() ||
    !self.require_values(operands) ||
    !self.require_values(metadata.live_gc_roots) ||
    !self.require_unique_roots(metadata.live_gc_roots) {
    return
  }
  if metadata.source is Some(source) && !source.is_valid() {
    self.record_error(
      InvalidMetadata(
        block_id=self.current_block.id,
        message="source location requires a non-empty file and non-negative coordinates",
      ),
    )
    return
  }
  if call.signature.results != self.construction.signature.results {
    self.record_error(
      InvalidTerminator(
        block_id=self.current_block.id,
        message="tail-call results must match the enclosing function",
      ),
    )
    return
  }
  if call.behavior.returns_twice {
    self.record_error(
      InvalidTerminator(
        block_id=self.current_block.id,
        message="tail call cannot return twice",
      ),
    )
    return
  }
  if verify_call_operands(call, self.value_types(operands), "tail_call")
    is Some(message) {
    self.record_error(
      InvalidTerminator(block_id=self.current_block.id, message~),
    )
    return
  }
  if !call.behavior.gc_safepoint && !metadata.live_gc_roots.is_empty() {
    self.record_error(
      InvalidSafepoint(
        block_id=self.current_block.id,
        message="tail-call live GC roots require a GC safepoint",
      ),
    )
    return
  }
  for root in metadata.live_gc_roots {
    if self.construction.values[root.id].ty != GcRef64 {
      self.record_error(
        InvalidSafepoint(
          block_id=self.current_block.id,
          message="tail-call live GC roots must have type gcref64",
        ),
      )
      return
    }
  }
  self.construction.blocks[self.current_block.id].terminator = Some(
    TerminatorRecord::new(TailCall(call, operands.copy()), metadata),
  )
}

///|
pub fn FunctionBuilder::noreturn_call(
  self : FunctionBuilder,
  call : SemanticCall,
  operands : Array[Value],
) -> Unit {
  self.noreturn_call_with_metadata(call, operands, TerminatorMetadata::empty())
}

///|
pub fn FunctionBuilder::noreturn_call_with_metadata(
  self : FunctionBuilder,
  call : SemanticCall,
  operands : Array[Value],
  metadata : TerminatorMetadata,
) -> Unit {
  if !self.require_block_open() ||
    !self.require_values(operands) ||
    !self.require_values(metadata.live_gc_roots) ||
    !self.require_unique_roots(metadata.live_gc_roots) {
    return
  }
  if metadata.source is Some(source) && !source.is_valid() {
    self.record_error(
      InvalidMetadata(
        block_id=self.current_block.id,
        message="source location requires a non-empty file and non-negative coordinates",
      ),
    )
    return
  }
  if !call.signature.results.is_empty() {
    self.record_error(
      InvalidTerminator(
        block_id=self.current_block.id,
        message="noreturn call must not declare results",
      ),
    )
    return
  }
  if call.behavior.returns_twice {
    self.record_error(
      InvalidTerminator(
        block_id=self.current_block.id,
        message="noreturn call cannot return twice",
      ),
    )
    return
  }
  if verify_call_operands(call, self.value_types(operands), "noreturn_call")
    is Some(message) {
    self.record_error(
      InvalidTerminator(block_id=self.current_block.id, message~),
    )
    return
  }
  if !call.behavior.gc_safepoint && !metadata.live_gc_roots.is_empty() {
    self.record_error(
      InvalidSafepoint(
        block_id=self.current_block.id,
        message="noreturn-call live GC roots require a GC safepoint",
      ),
    )
    return
  }
  for root in metadata.live_gc_roots {
    if self.construction.values[root.id].ty != GcRef64 {
      self.record_error(
        InvalidSafepoint(
          block_id=self.current_block.id,
          message="noreturn-call live GC roots must have type gcref64",
        ),
      )
      return
    }
  }
  self.construction.blocks[self.current_block.id].terminator = Some(
    TerminatorRecord::new(NoReturnCall(call, operands.copy()), metadata),
  )
}

///|
pub fn FunctionBuilder::trap(
  self : FunctionBuilder,
  reason : TrapReason,
) -> Unit {
  if !self.require_block_open() {
    return
  }
  self.construction.blocks[self.current_block.id].terminator = Some(
    TerminatorRecord::new(Trap(reason), TerminatorMetadata::empty()),
  )
}

///|
/// Attach a source location to the current block terminator without exposing
/// mutable terminator storage.
pub fn FunctionBuilder::set_terminator_source(
  self : FunctionBuilder,
  source : SourceLocation,
) -> Unit {
  if !source.is_valid() {
    self.record_error(
      InvalidMetadata(
        block_id=self.current_block.id,
        message="source location requires a non-empty file and non-negative coordinates",
      ),
    )
    return
  }
  match self.construction.blocks[self.current_block.id].terminator {
    None =>
      self.record_error(
        InvalidTerminator(
          block_id=self.current_block.id,
          message="terminator source requires an existing terminator",
        ),
      )
    Some(record) =>
      self.construction.blocks[self.current_block.id].terminator = Some(
        TerminatorRecord::new(
          record.kind,
          TerminatorMetadata::new(Some(source), record.metadata.live_gc_roots),
        ),
      )
  }
}

///|
/// Seal checked construction with global CFG validation, then run cleanup that
/// preserves the verified invariants.
pub fn FunctionBuilder::finish(
  self : FunctionBuilder,
  on_cleanup_phase? : (MandatoryCleanupPhase) -> Unit = fn(_) { () },
) -> Function raise MachVVerifyError {
  if self.construction_error is Some(error) {
    raise error
  }
  if self.stack_map_count != self.stack_map_ids.length() {
    raise InvalidMetadata(
      block_id=0,
      message="stack-map ids must be unique and dense from zero",
    )
  }
  on_cleanup_phase(VerifyInput)
  let function = Function::from_construction(self.construction)
  function.verify_checked_construction()
  function.run_mandatory_cleanup_verified(on_phase=on_cleanup_phase) |> ignore
  function
}

///|
/// Seal checked construction directly as immutable target-selection input.
/// This path deliberately does not materialize the richer public `Function`
/// checkpoint or run transformations that require its mutable diagnostics.
pub fn FunctionBuilder::finish_selection_plan(
  self : FunctionBuilder,
  on_cleanup_phase? : (MandatoryCleanupPhase) -> Unit = fn(_) { () },
) -> SelectionPlan raise MachVVerifyError {
  if self.construction_error is Some(error) {
    raise error
  }
  if self.stack_map_count != self.stack_map_ids.length() {
    raise InvalidMetadata(
      block_id=0,
      message="stack-map ids must be unique and dense from zero",
    )
  }
  let plan = SelectionPlan::from_construction(self.construction)
  on_cleanup_phase(VerifyInput)
  plan.verify_checked_construction()
  plan.construction.run_mandatory_cleanup_verified(on_phase=on_cleanup_phase)
  |> ignore
  plan.verified = true
  plan
}
