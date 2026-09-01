///|
/// Opaque handles used only while one MilkIR function is streamed into a
/// target selector. They do not own an SSA graph.
pub(all) struct Value {
  id : Int
} derive(Debug, Eq, Hash)

///|
pub(all) struct Block {
  id : Int
} derive(Debug, Eq, Hash)

///|
pub(all) struct InstructionMetadata {
  source : @native.SourceLocation?
  live_gc_roots : Array[Value]
  stack_map : @native.StackMapMetadata?
} derive(Debug, Eq)

///|
pub fn InstructionMetadata::empty() -> InstructionMetadata {
  { source: None, live_gc_roots: [], stack_map: None, }
}

///|
pub fn InstructionMetadata::new(
  source : @native.SourceLocation?,
  live_gc_roots : Array[Value],
  stack_map? : @native.StackMapMetadata,
) -> InstructionMetadata {
  { source, live_gc_roots: live_gc_roots.copy(), stack_map, }
}

///|
pub(all) struct TerminatorMetadata {
  source : @native.SourceLocation?
  live_gc_roots : Array[Value]
} derive(Debug, Eq)

///|
pub fn TerminatorMetadata::new(
  source : @native.SourceLocation?,
  live_gc_roots : Array[Value],
) -> TerminatorMetadata {
  { source, live_gc_roots: live_gc_roots.copy(), }
}

///|
pub(all) struct SwitchCase {
  bits : UInt64
  target : Block
  arguments : Array[Value]
} derive(Debug, Eq)

///|
pub(all) enum Terminator {
  Jump(Block, Array[Value])
  Branch(Value, Block, Array[Value], Block, Array[Value])
  Switch(Value, Array[SwitchCase], Block, Array[Value])
  Return(Array[Value])
  TailCall(@native.NativeCall, Array[Value])
  NoReturnCall(@native.NativeCall, Array[Value])
  Trap(@native.TrapReason)
} derive(Debug, Eq)

///|
pub(all) struct TargetSwitchCase {
  bits : UInt64
  target : Int
  arguments : Array[Int]
}

///|
pub(all) struct TargetTerminatorMetadata {
  source : @native.SourceLocation?
  live_gc_roots : Array[Int]
}

///|
pub(all) enum TargetTerminator {
  Jump(Int, Array[Int])
  Branch(Int, Int, Array[Int], Int, Array[Int])
  Switch(Int, Array[TargetSwitchCase], Int, Array[Int])
  Return(Array[Int])
  TailCall(@native.NativeCall, Array[Int])
  NoReturnCall(@native.NativeCall, Array[Int])
  Trap(@native.TrapReason)
}

///|
/// Target-owned callbacks. Integer ids refer to target VCode values, blocks,
/// and stack-object requests; `DirectBuilder` is the only component that
/// exposes typed transient handles to legalization code.
pub struct TargetSink {
  priv parameters : () -> Array[Int]
  priv entry_block : () -> Int
  priv create_block : (Array[@native.ValueType]) -> (Int, Array[Int])
  priv create_stack_object : (Int, Int) -> Int
  priv switch_to_block : (Int) -> Unit
  priv emit : (
    Int,
    Operation,
    Array[Int],
    Array[@native.ValueType],
    @native.SourceLocation?,
    Array[Int],
    @native.StackMapMetadata?,
  ) -> Array[Int]
  priv terminate : (Int, TargetTerminator, TargetTerminatorMetadata) -> Unit
  priv finish : () -> Unit
}

///|
pub fn TargetSink::new(
  parameters : () -> Array[Int],
  entry_block : () -> Int,
  create_block : (Array[@native.ValueType]) -> (Int, Array[Int]),
  create_stack_object : (Int, Int) -> Int,
  switch_to_block : (Int) -> Unit,
  emit : (
    Int,
    Operation,
    Array[Int],
    Array[@native.ValueType],
    @native.SourceLocation?,
    Array[Int],
    @native.StackMapMetadata?,
  ) -> Array[Int],
  terminate : (Int, TargetTerminator, TargetTerminatorMetadata) -> Unit,
  finish : () -> Unit,
) -> TargetSink {
  {
    parameters,
    entry_block,
    create_block,
    create_stack_object,
    switch_to_block,
    emit,
    terminate,
    finish,
  }
}

///|
/// Streaming construction state. It tracks handle types and one pending
/// terminator, but never stores instructions, uses, CFG edges, or SSA
/// definitions.
pub struct DirectBuilder {
  priv sink : TargetSink
  priv parameter_values : Array[Value]
  priv value_types : Array[@native.ValueType]
  priv integer_constants : Array[Int64?]
  priv target_values : Array[Int]
  priv block_parameters : Array[Array[Value]]
  priv target_blocks : Array[Int]
  priv stack_objects : Array[@native.StackObject]
  priv call_abi : CallAbiElaboration?
  priv mut root_scope_object : @native.StackObject?
  priv mut next_stack_map_id : Int
  priv error : Ref[String?]
  priv mut current_block : Block
  priv mut pending_terminator : (Terminator, TerminatorMetadata)?
}

///|
fn DirectBuilder::wrap_target_value(
  self : DirectBuilder,
  target_value : Int,
  ty : @native.ValueType,
) -> Value {
  let value : Value = { id: self.value_types.length(), }
  self.value_types.push(ty)
  self.integer_constants.push(None)
  self.target_values.push(target_value)
  value
}

///|
pub fn DirectBuilder::new(
  parameter_types : Array[@native.ValueType],
  sink : TargetSink,
  call_abi? : CallAbiElaboration,
  root_scope_capacity? : Int = 0,
) -> DirectBuilder {
  let builder = {
    sink,
    parameter_values: [],
    value_types: [],
    integer_constants: [],
    target_values: [],
    block_parameters: [[]],
    target_blocks: [],
    stack_objects: [],
    call_abi,
    root_scope_object: None,
    next_stack_map_id: 0,
    error: Ref(None),
    current_block: { id: (sink.entry_block)(), },
    pending_terminator: None,
  }
  let target_parameters = (sink.parameters)()
  if target_parameters.length() != parameter_types.length() {
    abort("native lowering target returned the wrong parameter count")
  }
  for index, ty in parameter_types {
    builder.parameter_values.push(
      builder.wrap_target_value(target_parameters[index], ty),
    )
  }
  builder.target_blocks.push(builder.current_block.id)
  builder.current_block = { id: 0, }
  if root_scope_capacity > 0 &&
    call_abi is Some(elaboration) &&
    elaboration.root_scope is Some(_) {
    builder.root_scope_object = Some(
      builder.create_stack_object(root_scope_capacity * 8, 16),
    )
  }
  builder
}

///|
pub fn DirectBuilder::parameters(self : DirectBuilder) -> Array[Value] {
  self.parameter_values.copy()
}

///|
pub fn DirectBuilder::entry_block(self : DirectBuilder) -> Block {
  ignore(self)
  { id: 0, }
}

///|
pub fn DirectBuilder::create_block(
  self : DirectBuilder,
  parameter_types : Array[@native.ValueType],
) -> Block {
  let (target_block, target_parameters) = (self.sink.create_block)(
    parameter_types,
  )
  if target_parameters.length() != parameter_types.length() {
    abort("native lowering target returned the wrong block parameter count")
  }
  let block : Block = { id: self.block_parameters.length(), }
  let parameters = []
  for index, ty in parameter_types {
    parameters.push(self.wrap_target_value(target_parameters[index], ty))
  }
  self.block_parameters.push(parameters)
  self.target_blocks.push(target_block)
  block
}

///|
pub fn DirectBuilder::block_parameters(
  self : DirectBuilder,
  block : Block,
) -> Array[Value] {
  self.block_parameters[block.id].copy()
}

///|
fn DirectBuilder::flush_terminator(self : DirectBuilder) -> Unit {
  guard self.pending_terminator is Some((terminator, metadata)) else {
    abort("native lowering block has no terminator")
  }
  let value_id = fn(value : Value) -> Int { self.target_values[value.id] }
  let block_id = fn(block : Block) -> Int { self.target_blocks[block.id] }
  let target_terminator = match terminator {
    Jump(target, arguments) =>
      TargetTerminator::Jump(block_id(target), arguments.map(value_id))
    Branch(
      condition,
      true_target,
      true_arguments,
      false_target,
      false_arguments
    ) =>
      Branch(
        value_id(condition),
        block_id(true_target),
        true_arguments.map(value_id),
        block_id(false_target),
        false_arguments.map(value_id),
      )
    Switch(value, cases, default_target, default_arguments) =>
      Switch(
        value_id(value),
        cases.map(case => {
          bits: case.bits,
          target: block_id(case.target),
          arguments: case.arguments.map(value_id),
        }),
        block_id(default_target),
        default_arguments.map(value_id),
      )
    Return(values) => Return(values.map(value_id))
    TailCall(call, operands) => TailCall(call, operands.map(value_id))
    NoReturnCall(call, operands) => NoReturnCall(call, operands.map(value_id))
    Trap(reason) => Trap(reason)
  }
  (self.sink.terminate)(
    self.target_blocks[self.current_block.id],
    target_terminator,
    {
      source: metadata.source,
      live_gc_roots: metadata.live_gc_roots.map(value_id),
    },
  )
  self.pending_terminator = None
}

///|
pub fn DirectBuilder::switch_to_block(
  self : DirectBuilder,
  block : Block,
) -> Unit {
  if block != self.current_block {
    self.flush_terminator()
    self.current_block = block
    (self.sink.switch_to_block)(self.target_blocks[block.id])
  }
}

///|
pub fn DirectBuilder::value_type(
  self : DirectBuilder,
  value : Value,
) -> @native.ValueType? {
  self.value_types.get(value.id)
}

///|
fn DirectBuilder::record_error(self : DirectBuilder, message : String) -> Unit {
  if self.error.val is None {
    self.error.val = Some(message)
  }
}

///|
fn DirectBuilder::emit_raw(
  self : DirectBuilder,
  operation : Operation,
  operands : Array[Value],
  result_types : Array[@native.ValueType],
  metadata : InstructionMetadata,
) -> Array[Value] {
  let target_results = (self.sink.emit)(
    self.target_blocks[self.current_block.id],
    operation,
    operands.map(value => self.target_values[value.id]),
    result_types,
    metadata.source,
    metadata.live_gc_roots.map(value => self.target_values[value.id]),
    metadata.stack_map,
  )
  if target_results.length() != result_types.length() {
    abort("native lowering target returned the wrong result count")
  }
  if metadata.stack_map is Some(stack_map) &&
    stack_map.id >= self.next_stack_map_id {
    self.next_stack_map_id = stack_map.id + 1
  }
  let results = Array::makei(result_types.length(), index => {
    self.wrap_target_value(target_results[index], result_types[index])
  })
  let constant = match operation {
    I32Const(bits) => Some(bits.reinterpret_as_int().to_int64() & 0xFFFFFFFFL)
    I64Const(bits) => Some(bits.reinterpret_as_int64())
    Copy if operands is [source] => self.integer_constants[source.id]
    _ => None
  }
  for result in results {
    self.integer_constants[result.id] = constant
  }
  results
}

///|
fn DirectBuilder::hidden_argument_root_count(
  self : DirectBuilder,
  call : @native.NativeCall,
  operands : Array[Value],
  abi : HiddenSafepointAbi,
) -> Int? {
  match abi.argument_roots {
    Fixed(count) if count >= 0 => Some(count)
    Fixed(_) => None
    I32ConstantOperand(index) => {
      guard index >= 0 &&
        index < operands.length() &&
        self.value_types[operands[index].id] == I32 &&
        self.integer_constants[operands[index].id] is Some(count) &&
        count >= 0L &&
        count <= 2147483647L else {
        return None
      }
      Some(count.to_int())
    }
    AllocationOperands =>
      match call.signature.params {
        [Ptr64, I32, I32, I64] => Some(1)
        [Ptr64, I32, Ptr64, I32] =>
          self.hidden_argument_root_count(
            call,
            operands,
            HiddenSafepointAbi::new(abi.symbol, I32ConstantOperand(3)),
          )
        _ => None
      }
  }
}

///|
fn DirectBuilder::emit_call_with_abi(
  self : DirectBuilder,
  call : @native.NativeCall,
  operands : Array[Value],
  result_types : Array[@native.ValueType],
  metadata : InstructionMetadata,
  elaboration : CallAbiElaboration,
) -> Array[Value] {
  let mut lowered_call = call
  let lowered_operands = operands.copy()
  let mut lowered_metadata = metadata
  if elaboration.hidden_safepoint(call) is Some(hidden) {
    if call.protocol != Platform ||
      !call.behavior.gc_safepoint ||
      metadata.stack_map is Some(_) {
      self.record_error("hidden safepoint has an invalid call contract")
    } else {
      match self.hidden_argument_root_count(call, operands, hidden) {
        Some(argument_root_count) => {
          let stack_map_id = self.next_stack_map_id
          let id = self.emit_raw(
              I32Const(stack_map_id.reinterpret_as_uint()),
              [],
              [I32],
              InstructionMetadata::empty(),
            )[0]
          lowered_operands.push(id)
          let parameters = call.signature.params.copy()
          parameters.push(I32)
          lowered_call = @native.NativeCall::new(
            call.callee,
            @native.Signature::new(parameters, call.signature.results),
            call.protocol,
            call.behavior,
          )
          lowered_metadata = InstructionMetadata::new(
            metadata.source,
            metadata.live_gc_roots,
            stack_map=@native.StackMapMetadata::new(
              stack_map_id,
              argument_root_count~,
            ),
          )
        }
        None =>
          self.record_error(
            "hidden safepoint root count is not a supported compile-time constant",
          )
      }
    }
  }
  let mut context : Value? = None
  if !metadata.live_gc_roots.is_empty() {
    if call.behavior.returns_twice {
      self.record_error("returns-twice calls cannot use a caller root scope")
    } else if elaboration.root_scope is Some(scope) &&
      self.root_scope_object is Some(object) {
      let context_index = match call.protocol {
        Internal => if call.callee is Indirect { 1 } else { 0 }
        Platform => 0
      }
      if context_index < 0 ||
        context_index >= operands.length() ||
        self.value_types[operands[context_index].id] != Ptr64 {
        self.record_error(
          "caller root scope requires a ptr64 execution environment",
        )
      } else {
        let environment = operands[context_index]
        context = Some(environment)
        let address = self.emit_raw(
            StackAddress(object),
            [],
            [Ptr64],
            InstructionMetadata::empty(),
          )[0]
        for index, root in metadata.live_gc_roots {
          self.emit_raw(
            Store(
              StoreSpec::new(
                W64,
                GcRef64,
                (index * 8).to_uint64(),
                Little,
                None,
              ),
            ),
            [address, root],
            [],
            InstructionMetadata::empty(),
          )
          |> ignore
        }
        let count = self.emit_raw(
            I32Const(metadata.live_gc_roots.length().reinterpret_as_uint()),
            [],
            [I32],
            InstructionMetadata::empty(),
          )[0]
        self.emit_raw(
          Call(root_scope_push_call(scope.push_symbol)),
          [environment, address, count],
          [],
          InstructionMetadata::empty(),
        )
        |> ignore
      }
    } else {
      self.record_error("live GC roots require a caller root-scope ABI")
    }
  }
  let results = self.emit_raw(
    Call(lowered_call),
    lowered_operands,
    result_types,
    lowered_metadata,
  )
  if context is Some(environment) && elaboration.root_scope is Some(scope) {
    self.emit_raw(
      Call(root_scope_pop_call(scope.pop_symbol)),
      [environment],
      [],
      InstructionMetadata::empty(),
    )
    |> ignore
  }
  results
}

///|
pub fn DirectBuilder::emit_with_metadata(
  self : DirectBuilder,
  operation : Operation,
  operands : Array[Value],
  result_types : Array[@native.ValueType],
  metadata : InstructionMetadata,
) -> Array[Value] {
  match (operation, self.call_abi) {
    (Call(call), Some(elaboration)) =>
      self.emit_call_with_abi(
        call, operands, result_types, metadata, elaboration,
      )
    _ => self.emit_raw(operation, operands, result_types, metadata)
  }
}

///|
pub fn DirectBuilder::create_stack_object(
  self : DirectBuilder,
  size : Int,
  alignment : Int,
) -> @native.StackObject {
  let target_id = (self.sink.create_stack_object)(size, alignment)
  let object : @native.StackObject = { id: self.stack_objects.length(), }
  if target_id != object.id {
    abort("native lowering target returned a non-dense stack-object id")
  }
  self.stack_objects.push(object)
  object
}

///|
fn DirectBuilder::set_terminator(
  self : DirectBuilder,
  terminator : Terminator,
  metadata : TerminatorMetadata,
) -> Unit {
  if self.pending_terminator is Some(_) {
    abort("native lowering block has more than one terminator")
  }
  self.pending_terminator = Some((terminator, metadata))
}

///|
pub fn DirectBuilder::jump(
  self : DirectBuilder,
  target : Block,
  arguments : Array[Value],
) -> Unit {
  self.set_terminator(
    Jump(target, arguments.copy()),
    TerminatorMetadata::new(None, []),
  )
}

///|
pub fn DirectBuilder::branch(
  self : DirectBuilder,
  condition : Value,
  true_target : Block,
  true_arguments : Array[Value],
  false_target : Block,
  false_arguments : Array[Value],
) -> Unit {
  self.set_terminator(
    Branch(
      condition,
      true_target,
      true_arguments.copy(),
      false_target,
      false_arguments.copy(),
    ),
    TerminatorMetadata::new(None, []),
  )
}

///|
pub fn DirectBuilder::switch(
  self : DirectBuilder,
  value : Value,
  cases : Array[(UInt64, Block, Array[Value])],
  default_target : Block,
  default_arguments : Array[Value],
) -> Unit {
  self.set_terminator(
    Switch(
      value,
      cases.map(case => {
        bits: case.0,
        target: case.1,
        arguments: case.2.copy(),
      }),
      default_target,
      default_arguments.copy(),
    ),
    TerminatorMetadata::new(None, []),
  )
}

///|
pub fn DirectBuilder::return_(
  self : DirectBuilder,
  values : Array[Value],
) -> Unit {
  self.set_terminator(Return(values.copy()), TerminatorMetadata::new(None, []))
}

///|
pub fn DirectBuilder::trap(
  self : DirectBuilder,
  reason : @native.TrapReason,
) -> Unit {
  self.set_terminator(Trap(reason), TerminatorMetadata::new(None, []))
}

///|
pub fn DirectBuilder::set_terminator_source(
  self : DirectBuilder,
  source : @native.SourceLocation,
) -> Unit {
  if self.pending_terminator is Some((terminator, metadata)) {
    self.pending_terminator = Some(
      (terminator, { ..metadata, source: Some(source), }),
    )
  }
}

///|
pub fn DirectBuilder::tail_call_with_metadata(
  self : DirectBuilder,
  call : @native.NativeCall,
  operands : Array[Value],
  metadata : TerminatorMetadata,
) -> Unit {
  self.set_terminator(TailCall(call, operands.copy()), metadata)
}

///|
pub fn DirectBuilder::noreturn_call_with_metadata(
  self : DirectBuilder,
  call : @native.NativeCall,
  operands : Array[Value],
  metadata : TerminatorMetadata,
) -> Unit {
  self.set_terminator(NoReturnCall(call, operands.copy()), metadata)
}

///|
pub fn DirectBuilder::finish(
  self : DirectBuilder,
) -> Unit raise DirectLoweringError {
  self.flush_terminator()
  (self.sink.finish)()
  if self.error.val is Some(message) {
    raise InvalidCallAbi(message~)
  }
}
