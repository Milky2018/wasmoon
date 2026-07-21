///|
/// Safe semantic-construction seam used by MilkIR dialect adapters.
///
/// The context exposes only verified operands, explicit environment values,
/// target-neutral MachV construction, and structured control-flow builders. It
/// does not expose mutable MachV storage, target instructions, or ABI details.
struct InstructionContext {
  builder : @machv.FunctionBuilder
  operands : Array[@machv.Value]
  operand_types : Array[@machv.ValueType]
  result_types : Array[@machv.ValueType]
  function_result_types : Array[@machv.ValueType]
  environment : Array[@machv.Value]
  source : @machv.SourceLocation?
  live_gc_roots : Array[@machv.Value]
  completed : Ref[Bool]
  terminates_block : Ref[Bool]
  error : Ref[String?]
  complete : (Array[@machv.Value]) -> Unit
}

///|
pub fn InstructionContext::new(
  builder : @machv.FunctionBuilder,
  operands : Array[@machv.Value],
  operand_types : Array[@machv.ValueType],
  result_types : Array[@machv.ValueType],
  function_result_types : Array[@machv.ValueType],
  environment : Array[@machv.Value],
  source : @machv.SourceLocation?,
  live_gc_roots : Array[@machv.Value],
  complete : (Array[@machv.Value]) -> Unit,
) -> InstructionContext {
  {
    builder,
    operands: operands.copy(),
    operand_types: operand_types.copy(),
    result_types: result_types.copy(),
    function_result_types: function_result_types.copy(),
    environment: environment.copy(),
    source,
    live_gc_roots: live_gc_roots.copy(),
    completed: Ref(false),
    terminates_block: Ref(false),
    error: Ref(None),
    complete,
  }
}

///|
fn InstructionContext::record_error(
  self : InstructionContext,
  message : String,
) -> Unit {
  if self.error.val is None {
    self.error.val = Some(message)
  }
}

///|
fn InstructionContext::complete_once(
  self : InstructionContext,
  results : Array[@machv.Value],
) -> Unit {
  if self.completed.val {
    self.record_error("dialect instruction completed more than once")
    return
  }
  if results.length() != self.result_types.length() {
    self.record_error(
      "dialect instruction produced \{results.length()} results, expected \{self.result_types.length()}",
    )
    return
  }
  self.completed.val = true
  (self.complete)(results)
}

///|
fn InstructionContext::instruction_metadata(
  self : InstructionContext,
  include_gc_roots : Bool,
) -> @machv.InstructionMetadata {
  @machv.InstructionMetadata::new(
    self.source,
    if include_gc_roots {
      self.live_gc_roots
    } else {
      []
    },
  )
}

///|
fn InstructionContext::terminator_metadata(
  self : InstructionContext,
) -> @machv.TerminatorMetadata {
  @machv.TerminatorMetadata::new(self.source, self.live_gc_roots)
}

///|
pub fn InstructionContext::operands(
  self : InstructionContext,
) -> Array[@machv.Value] {
  self.operands.copy()
}

///|
pub fn InstructionContext::result_types(
  self : InstructionContext,
) -> Array[@machv.ValueType] {
  self.result_types.copy()
}

///|
pub fn InstructionContext::operand_types(
  self : InstructionContext,
) -> Array[@machv.ValueType] {
  self.operand_types.copy()
}

///|
pub fn InstructionContext::function_result_types(
  self : InstructionContext,
) -> Array[@machv.ValueType] {
  self.function_result_types.copy()
}

///|
pub fn InstructionContext::environment(
  self : InstructionContext,
) -> Array[@machv.Value] {
  self.environment.copy()
}

///|
pub fn InstructionContext::source(
  self : InstructionContext,
) -> @machv.SourceLocation? {
  self.source
}

///|
pub fn InstructionContext::emit(
  self : InstructionContext,
  operation : @machv.Operation,
  operands : Array[@machv.Value],
  result_types : Array[@machv.ValueType],
) -> Array[@machv.Value] {
  self.builder.emit_with_metadata(
    operation,
    operands,
    result_types,
    self.instruction_metadata(false),
  )
}

///|
pub fn InstructionContext::finish_operation(
  self : InstructionContext,
  operation : @machv.Operation,
  operands : Array[@machv.Value],
) -> Unit {
  let results = self.builder.emit_with_metadata(
    operation,
    operands,
    self.result_types,
    self.instruction_metadata(false),
  )
  self.complete_once(results)
}

///|
pub fn InstructionContext::emit_call(
  self : InstructionContext,
  call : @machv.SemanticCall,
  operands : Array[@machv.Value],
  result_types : Array[@machv.ValueType],
) -> Array[@machv.Value] {
  self.builder.emit_with_metadata(
    Call(call),
    operands,
    result_types,
    self.instruction_metadata(true),
  )
}

///|
pub fn InstructionContext::emit_call_without_roots(
  self : InstructionContext,
  call : @machv.SemanticCall,
  operands : Array[@machv.Value],
  result_types : Array[@machv.ValueType],
) -> Array[@machv.Value] {
  self.builder.emit_with_metadata(
    Call(call),
    operands,
    result_types,
    self.instruction_metadata(false),
  )
}

///|
pub fn InstructionContext::finish_call(
  self : InstructionContext,
  call : @machv.SemanticCall,
  operands : Array[@machv.Value],
) -> Unit {
  let results = self.emit_call(call, operands, self.result_types)
  self.complete_once(results)
}

///|
pub fn InstructionContext::finish_call_without_roots(
  self : InstructionContext,
  call : @machv.SemanticCall,
  operands : Array[@machv.Value],
) -> Unit {
  let results = self.emit_call_without_roots(call, operands, self.result_types)
  self.complete_once(results)
}

///|
pub fn InstructionContext::forward_results(
  self : InstructionContext,
  values : Array[@machv.Value],
) -> Unit {
  if values.length() != self.result_types.length() {
    self.record_error(
      "dialect instruction forwarded \{values.length()} results, expected \{self.result_types.length()}",
    )
    return
  }
  let results : Array[@machv.Value] = []
  for index, value in values {
    let copied = self.builder.emit_with_metadata(
      Copy,
      [value],
      [self.result_types[index]],
      self.instruction_metadata(false),
    )
    if copied.length() != 1 {
      self.record_error("failed to construct dialect result copy")
      return
    }
    results.push(copied[0])
  }
  self.complete_once(results)
}

///|
pub fn InstructionContext::finish_void(self : InstructionContext) -> Unit {
  self.complete_once([])
}

///|
pub fn InstructionContext::create_block(
  self : InstructionContext,
  parameter_types : Array[@machv.ValueType],
) -> @machv.Block {
  self.builder.create_block(parameter_types)
}

///|
pub fn InstructionContext::create_stack_object(
  self : InstructionContext,
  size : Int,
  alignment : Int,
) -> @machv.StackObject {
  self.builder.create_stack_object(size, alignment)
}

///|
pub fn InstructionContext::block_parameters(
  self : InstructionContext,
  block : @machv.Block,
) -> Array[@machv.Value] {
  self.builder.block_parameters(block)
}

///|
pub fn InstructionContext::switch_to_block(
  self : InstructionContext,
  block : @machv.Block,
) -> Unit {
  self.builder.switch_to_block(block)
}

///|
pub fn InstructionContext::jump(
  self : InstructionContext,
  target : @machv.Block,
  arguments : Array[@machv.Value],
) -> Unit {
  self.builder.jump(target, arguments)
}

///|
pub fn InstructionContext::branch(
  self : InstructionContext,
  condition : @machv.Value,
  true_target : @machv.Block,
  true_arguments : Array[@machv.Value],
  false_target : @machv.Block,
  false_arguments : Array[@machv.Value],
) -> Unit {
  self.builder.branch(
    condition, true_target, true_arguments, false_target, false_arguments,
  )
}

///|
pub fn InstructionContext::trap(
  self : InstructionContext,
  reason : @machv.TrapReason,
) -> Unit {
  self.builder.trap(reason)
  if self.source is Some(source) {
    self.builder.set_terminator_source(source)
  }
  self.terminates_block.val = true
  self.finish_void()
}

///|
/// Terminate an adapter-created side block without completing the source
/// dialect instruction. The adapter must switch to a continuation block and
/// complete the instruction there.
pub fn InstructionContext::set_trap_terminator(
  self : InstructionContext,
  reason : @machv.TrapReason,
) -> Unit {
  self.builder.trap(reason)
  if self.source is Some(source) {
    self.builder.set_terminator_source(source)
  }
}

///|
pub fn InstructionContext::tail_call(
  self : InstructionContext,
  call : @machv.SemanticCall,
  operands : Array[@machv.Value],
) -> Unit {
  self.builder.tail_call_with_metadata(
    call,
    operands,
    self.terminator_metadata(),
  )
  self.terminates_block.val = true
  self.finish_void()
}

///|
pub fn InstructionContext::noreturn_call(
  self : InstructionContext,
  call : @machv.SemanticCall,
  operands : Array[@machv.Value],
) -> Unit {
  let metadata = if call.behavior.gc_safepoint {
    self.terminator_metadata()
  } else {
    @machv.TerminatorMetadata::new(self.source, [])
  }
  self.builder.noreturn_call_with_metadata(call, operands, metadata)
  self.terminates_block.val = true
  self.finish_void()
}

///|
pub fn InstructionContext::terminates_block(self : InstructionContext) -> Bool {
  self.terminates_block.val
}

///|
pub fn InstructionContext::status(self : InstructionContext) -> String? {
  match self.error.val {
    Some(message) => Some(message)
    None =>
      if self.completed.val {
        None
      } else {
        Some("dialect instruction did not complete its result contract")
      }
  }
}
