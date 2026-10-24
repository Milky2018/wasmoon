///|
/// Opaque handles used only while one MilkIR function is streamed into a
/// target selector. They do not own an SSA graph.
pub(all) struct Value {
  id : Int32
} derive(Debug, Eq, Hash)

///|
pub(all) struct Block {
  id : Int32
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
  BranchIntCompare(
    IntComparison,
    Value,
    Value,
    Block,
    Array[Value],
    Block,
    Array[Value]
  )
  BranchIntCompareImmediate(
    IntComparison,
    Value,
    UInt64,
    Block,
    Array[Value],
    Block,
    Array[Value]
  )
  Switch(Value, Array[SwitchCase], Block, Array[Value])
  Return(Array[Value])
  TailCall(@native.NativeCall, Array[Value])
  NoReturnCall(@native.NativeCall, Array[Value])
  Trap(@native.TrapReason)
} derive(Debug, Eq)

///|
pub(all) struct TargetSwitchCase {
  bits : UInt64
  target : Int32
  arguments : Array[Int32]
}

///|
pub(all) struct TargetTerminatorMetadata {
  source : @native.SourceLocation?
  live_gc_roots : Array[Int32]
}

///|
pub(all) enum TargetTerminator {
  Jump(Int32, Array[Int32])
  Branch(Int32, Int32, Array[Int32], Int32, Array[Int32])
  BranchIntCompare(
    IntComparison,
    Int32,
    Int32,
    Int32,
    Array[Int32],
    Int32,
    Array[Int32]
  )
  BranchIntCompareImmediate(
    IntComparison,
    Int32,
    UInt64,
    Int32,
    Array[Int32],
    Int32,
    Array[Int32]
  )
  Switch(Int32, Array[TargetSwitchCase], Int32, Array[Int32])
  Return(Array[Int32])
  TailCall(@native.NativeCall, Array[Int32])
  NoReturnCall(@native.NativeCall, Array[Int32])
  Trap(@native.TrapReason)
}

///|
/// Target-owned callbacks. Integer ids refer to target VCode values, blocks,
/// and stack-object requests; `DirectBuilder` is the only component that
/// exposes typed transient handles to legalization code.
pub struct TargetSink {
  priv supports_int_compare_immediate : (@native.ValueType, UInt64) -> Bool
  priv folds_unsigned_index_into_memory : Bool
  priv parameters : () -> Array[Int32]
  priv entry_block : () -> Int32
  priv create_block : (Array[@native.ValueType]) -> (Int32, Array[Int32])
  priv create_stack_object : (Int32, Int32) -> Int32
  priv switch_to_block : (Int32) -> Unit
  priv emit : (
    Int32,
    Operation,
    Array[Int32],
    Array[@native.ValueType],
    @native.SourceLocation?,
    Array[Int32],
    @native.StackMapMetadata?,
  ) -> Array[Int32]
  priv terminate : (Int32, TargetTerminator, TargetTerminatorMetadata) -> Unit
  priv finish : () -> Unit
}

///|
pub fn TargetSink::new(
  parameters : () -> Array[Int32],
  entry_block : () -> Int32,
  create_block : (Array[@native.ValueType]) -> (Int32, Array[Int32]),
  create_stack_object : (Int32, Int32) -> Int32,
  switch_to_block : (Int32) -> Unit,
  emit : (
    Int32,
    Operation,
    Array[Int32],
    Array[@native.ValueType],
    @native.SourceLocation?,
    Array[Int32],
    @native.StackMapMetadata?,
  ) -> Array[Int32],
  terminate : (Int32, TargetTerminator, TargetTerminatorMetadata) -> Unit,
  finish : () -> Unit,
  folds_unsigned_index_into_memory~ : Bool = false,
  supports_int_compare_immediate~ : (@native.ValueType, UInt64) -> Bool = fn(
    _,
    _,
  ) {
    false
  },
) -> TargetSink {
  {
    supports_int_compare_immediate,
    folds_unsigned_index_into_memory,
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
/// Whether an indexed memory operation consumes an unsigned 32-bit index
/// without materializing a separate extension and address addition.
pub fn TargetSink::folds_unsigned_index_into_memory(self : TargetSink) -> Bool {
  self.folds_unsigned_index_into_memory
}

///|
/// Whether a scalar comparison can consume this constant without materializing it.
pub fn TargetSink::supports_int_compare_immediate(
  self : TargetSink,
  ty : @native.ValueType,
  bits : UInt64,
) -> Bool {
  (self.supports_int_compare_immediate)(ty, bits)
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
  priv target_values : Array[Int32]
  priv block_parameters : Array[Array[Value]]
  priv target_blocks : Array[Int32]
  priv stack_objects : Array[@native.StackObject]
  priv call_abi : CallAbiElaboration?
  priv root_scope_capacity : Int32
  priv mut root_scope_object : @native.StackObject?
  priv mut function_root_frame : (Value, Value, Value, Value, Int32)?
  priv function_root_slots : Map[Int32, Int32]
  priv mut next_stack_map_id : Int32
  priv error : Ref[String?]
  priv mut current_block : Block
  priv mut pending_terminator : (Terminator, TerminatorMetadata)?
}

///|
fn DirectBuilder::wrap_target_value(
  self : DirectBuilder,
  target_value : Int32,
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
  root_scope_capacity~ : Int32 = 0,
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
    root_scope_capacity,
    root_scope_object: None,
    function_root_frame: None,
    function_root_slots: Map([]),
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
  builder
}

///|
/// Reserve one precise shadow frame for the function. Slots are filled once
/// where SSA values are defined; only liveness mask words change at safepoints.
pub fn DirectBuilder::begin_function_roots(
  self : DirectBuilder,
  capacity : Int32,
) -> Unit {
  guard capacity > 0 &&
    self.call_abi is Some(abi) &&
    abi.function_frame is Some(frame) else {
    return
  }
  if self.function_root_frame is Some(_) {
    self.record_error("function root frame was already entered")
    return
  }
  guard self.parameter_values.get(frame.environment_parameter)
    is Some(environment) &&
    self.value_type(environment) == Some(Ptr64) else {
    self.record_error(
      "function root frame requires an execution environment parameter",
    )
    return
  }
  let header = self.create_stack_object(32, 16)
  let roots = self.create_stack_object(capacity * 8, 16)
  let mask = self.create_stack_object((capacity + 63) / 64 * 8, 8)
  let header_address = self.emit_raw(
      StackAddress(header),
      [],
      [Ptr64],
      InstructionMetadata::empty(),
    )[0]
  let roots_address = self.emit_raw(
      StackAddress(roots),
      [],
      [Ptr64],
      InstructionMetadata::empty(),
    )[0]
  let mask_address = self.emit_raw(
      StackAddress(mask),
      [],
      [Ptr64],
      InstructionMetadata::empty(),
    )[0]
  self.function_root_frame = Some(
    (environment, header_address, roots_address, mask_address, capacity),
  )
  self.update_function_roots([])
  let count = self.emit_raw(
      I32Const(capacity.reinterpret_as_uint()),
      [],
      [I32],
      InstructionMetadata::empty(),
    )[0]
  let call = @native.NativeCall::new(
    External(frame.enter_symbol),
    @native.Signature::new([Ptr64, Ptr64, Ptr64, Ptr64, I32], []),
    Platform,
    @native.CallBehavior::new(ReadWrite, true, false, false, false),
  )
  self.emit_raw(
    Call(call),
    [environment, header_address, roots_address, mask_address, count],
    [],
    InstructionMetadata::empty(),
  )
  |> ignore
}

///|
pub fn DirectBuilder::define_function_root(
  self : DirectBuilder,
  value : Value,
) -> Unit {
  guard self.function_root_frame is Some((_, _, roots, _, capacity)) else {
    return
  }
  // Different SSA copies may share this native handle. Publish at every
  // binding site: a store on one sibling path does not dominate another.
  let slot = self.function_root_slots
    .get(value.id)
    .unwrap_or(self.function_root_slots.length())
  if slot >= capacity || self.value_type(value) != Some(GcRef64) {
    self.record_error("function root definition exceeds its admitted slot plan")
    return
  }
  self.function_root_slots[value.id] = slot
  self.emit_raw(
    Store(StoreSpec::new(W64, GcRef64, (slot * 8).to_uint64(), Little, None)),
    [roots, value],
    [],
    InstructionMetadata::empty(),
  )
  |> ignore
}

///|
fn DirectBuilder::update_function_roots(
  self : DirectBuilder,
  live : Array[Value],
) -> Unit {
  guard self.function_root_frame is Some((_, _, _, address, capacity)) else {
    return
  }
  let masks : Array[UInt64] = Array::make((capacity + 63) / 64, 0UL)
  for root in live {
    guard self.function_root_slots.get(root.id) is Some(slot) else {
      self.record_error(
        "safepoint root has no dominating function slot definition",
      )
      continue
    }
    masks[slot / 64] = masks[slot / 64] | (1UL << (slot % 64))
  }
  for index, bits in masks {
    let value = self.emit_raw(
        I64Const(bits),
        [],
        [I64],
        InstructionMetadata::empty(),
      )[0]
    self.emit_raw(
      Store(StoreSpec::new(W64, I64, (index * 8).to_uint64(), Little, None)),
      [address, value],
      [],
      InstructionMetadata::empty(),
    )
    |> ignore
  }
}

///|
fn DirectBuilder::leave_function_roots(self : DirectBuilder) -> Unit {
  guard self.function_root_frame is Some((environment, header, _, _, _)) &&
    self.call_abi is Some(abi) &&
    abi.function_frame is Some(frame) else {
    return
  }
  let call = @native.NativeCall::new(
    External(frame.leave_symbol),
    @native.Signature::new([Ptr64, Ptr64], []),
    Platform,
    @native.CallBehavior::new(ReadWrite, true, false, false, false),
  )
  self.emit_raw(
    Call(call),
    [environment, header],
    [],
    InstructionMetadata::empty(),
  )
  |> ignore
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
  let value_id = fn(value : Value) -> Int32 { self.target_values[value.id] }
  let block_id = fn(block : Block) -> Int32 { self.target_blocks[block.id] }
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
    BranchIntCompare(
      comparison,
      left,
      right,
      true_target,
      true_arguments,
      false_target,
      false_arguments
    ) =>
      BranchIntCompare(
        comparison,
        value_id(left),
        value_id(right),
        block_id(true_target),
        true_arguments.map(value_id),
        block_id(false_target),
        false_arguments.map(value_id),
      )
    BranchIntCompareImmediate(
      comparison,
      input,
      bits,
      true_target,
      true_arguments,
      false_target,
      false_arguments
    ) =>
      BranchIntCompareImmediate(
        comparison,
        value_id(input),
        bits,
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
) -> Int32? {
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
          if hidden.owner is Some(owner) {
            let owner_value = self.emit_raw(
                I32Const(owner.reinterpret_as_uint()),
                [],
                [I32],
                InstructionMetadata::empty(),
              )[0]
            lowered_operands.push(owner_value)
            parameters.push(I32)
          }
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
  if self.function_root_frame is Some(_) {
    if call.behavior.returns_twice && !metadata.live_gc_roots.is_empty() {
      self.record_error("returns-twice calls cannot transport live SSA roots")
    }
    if call.behavior.gc_safepoint ||
      call.behavior.cancellation_safepoint ||
      !metadata.live_gc_roots.is_empty() {
      self.update_function_roots(metadata.live_gc_roots)
    }
  } else if !metadata.live_gc_roots.is_empty() {
    if call.behavior.returns_twice {
      self.record_error("returns-twice calls cannot use a caller root scope")
    } else if elaboration.root_scope is Some(scope) &&
      metadata.live_gc_roots.length() <= self.root_scope_capacity {
      if self.root_scope_object is None {
        self.root_scope_object = Some(
          self.create_stack_object(self.root_scope_capacity * 8, 16),
        )
      }
      guard self.root_scope_object is Some(object) else {
        abort("native lowering root-scope object was not created")
      }
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
    } else if elaboration.root_scope is None {
      self.record_error("live GC roots require a caller root-scope ABI")
    } else {
      self.record_error("live GC roots exceed the caller root-scope capacity")
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
  size : Int32,
  alignment : Int32,
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
pub fn DirectBuilder::branch_int_compare(
  self : DirectBuilder,
  comparison : IntComparison,
  left : Value,
  right : Value,
  true_target : Block,
  true_arguments : Array[Value],
  false_target : Block,
  false_arguments : Array[Value],
) -> Unit {
  self.set_terminator(
    BranchIntCompare(
      comparison,
      left,
      right,
      true_target,
      true_arguments.copy(),
      false_target,
      false_arguments.copy(),
    ),
    TerminatorMetadata::new(None, []),
  )
}

///|
pub fn DirectBuilder::branch_int_compare_immediate(
  self : DirectBuilder,
  comparison : IntComparison,
  input : Value,
  bits : UInt64,
  true_target : Block,
  true_arguments : Array[Value],
  false_target : Block,
  false_arguments : Array[Value],
) -> Unit {
  self.set_terminator(
    BranchIntCompareImmediate(
      comparison,
      input,
      bits,
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
  self.leave_function_roots()
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
  self.leave_function_roots()
  self.set_terminator(TailCall(call, operands.copy()), metadata)
}

///|
pub fn DirectBuilder::noreturn_call_with_metadata(
  self : DirectBuilder,
  call : @native.NativeCall,
  operands : Array[Value],
  metadata : TerminatorMetadata,
) -> Unit {
  self.update_function_roots(metadata.live_gc_roots)
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
