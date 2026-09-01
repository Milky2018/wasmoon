///|
/// Safe semantic-construction seam used by MilkIR dialect adapters.
///
/// The context exposes only verified operands, explicit environment values,
/// target-neutral native lowering construction, and structured control-flow builders. It
/// does not expose mutable native lowering storage, target instructions, or ABI details.
struct InstructionContext {
  builder : @lowering.DirectBuilder
  operands : Array[@lowering.Value]
  operand_types : Array[@native.ValueType]
  result_types : Array[@native.ValueType]
  function_result_types : Array[@native.ValueType]
  environment : Array[@lowering.Value]
  source : @native.SourceLocation?
  live_gc_roots : Array[@lowering.Value]
  completed : Ref[Bool]
  terminates_block : Ref[Bool]
  error : Ref[String?]
  complete : (Array[@lowering.Value]) -> Unit
}

///|
pub fn InstructionContext::new(
  builder : @lowering.DirectBuilder,
  operands : Array[@lowering.Value],
  operand_types : Array[@native.ValueType],
  result_types : Array[@native.ValueType],
  function_result_types : Array[@native.ValueType],
  environment : Array[@lowering.Value],
  source : @native.SourceLocation?,
  live_gc_roots : Array[@lowering.Value],
  complete : (Array[@lowering.Value]) -> Unit,
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
fn[T] InstructionContext::attempt(
  self : InstructionContext,
  action : () -> T raise,
  fallback : T,
) -> T {
  action() catch {
    error => {
      self.record_error(Repr(error).to_string())
      fallback
    }
  }
}

///|
fn InstructionContext::complete_once(
  self : InstructionContext,
  results : Array[@lowering.Value],
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
) -> @lowering.InstructionMetadata {
  @lowering.InstructionMetadata::new(
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
) -> @lowering.TerminatorMetadata {
  @lowering.TerminatorMetadata::new(self.source, self.live_gc_roots)
}

///|
pub fn InstructionContext::operands(
  self : InstructionContext,
) -> Array[@lowering.Value] {
  self.operands.copy()
}

///|
pub fn InstructionContext::result_types(
  self : InstructionContext,
) -> Array[@native.ValueType] {
  self.result_types.copy()
}

///|
pub fn InstructionContext::operand_types(
  self : InstructionContext,
) -> Array[@native.ValueType] {
  self.operand_types.copy()
}

///|
pub fn InstructionContext::function_result_types(
  self : InstructionContext,
) -> Array[@native.ValueType] {
  self.function_result_types.copy()
}

///|
pub fn InstructionContext::environment(
  self : InstructionContext,
) -> Array[@lowering.Value] {
  self.environment.copy()
}

///|
pub fn InstructionContext::source(
  self : InstructionContext,
) -> @native.SourceLocation? {
  self.source
}

///|
pub fn InstructionContext::emit(
  self : InstructionContext,
  operation : @lowering.Operation,
  operands : Array[@lowering.Value],
  result_types : Array[@native.ValueType],
) -> Array[@lowering.Value] {
  self.attempt(
    fn() {
      self.builder.emit_with_metadata(
        operation,
        operands,
        result_types,
        self.instruction_metadata(false),
      )
    },
    [],
  )
}

///|
pub fn InstructionContext::finish_operation(
  self : InstructionContext,
  operation : @lowering.Operation,
  operands : Array[@lowering.Value],
) -> Unit {
  let results = self.attempt(
    fn() {
      self.builder.emit_with_metadata(
        operation,
        operands,
        self.result_types,
        self.instruction_metadata(false),
      )
    },
    [],
  )
  self.complete_once(results)
}

///|
pub fn InstructionContext::emit_call(
  self : InstructionContext,
  call : @native.NativeCall,
  operands : Array[@lowering.Value],
  result_types : Array[@native.ValueType],
) -> Array[@lowering.Value] {
  self.attempt(
    fn() {
      self.builder.emit_with_metadata(
        Call(call),
        operands,
        result_types,
        self.instruction_metadata(true),
      )
    },
    [],
  )
}

///|
pub fn InstructionContext::emit_call_without_roots(
  self : InstructionContext,
  call : @native.NativeCall,
  operands : Array[@lowering.Value],
  result_types : Array[@native.ValueType],
) -> Array[@lowering.Value] {
  self.attempt(
    fn() {
      self.builder.emit_with_metadata(
        Call(call),
        operands,
        result_types,
        self.instruction_metadata(false),
      )
    },
    [],
  )
}

///|
pub fn InstructionContext::finish_call(
  self : InstructionContext,
  call : @native.NativeCall,
  operands : Array[@lowering.Value],
) -> Unit {
  let results = self.emit_call(call, operands, self.result_types)
  self.complete_once(results)
}

///|
pub fn InstructionContext::finish_call_without_roots(
  self : InstructionContext,
  call : @native.NativeCall,
  operands : Array[@lowering.Value],
) -> Unit {
  let results = self.emit_call_without_roots(call, operands, self.result_types)
  self.complete_once(results)
}

///|
pub fn InstructionContext::forward_results(
  self : InstructionContext,
  values : Array[@lowering.Value],
) -> Unit {
  if values.length() != self.result_types.length() {
    self.record_error(
      "dialect instruction forwarded \{values.length()} results, expected \{self.result_types.length()}",
    )
    return
  }
  for index, value in values {
    if self.builder.value_type(value) != Some(self.result_types[index]) {
      self.record_error(
        "forwarded dialect result {index} has the wrong semantic type",
      )
      return
    }
  }
  // The source result is already a value in this construction. Keeping an
  // owned Copy instruction only makes mandatory cleanup rediscover the alias.
  self.complete_once(values)
}

///|
pub fn InstructionContext::finish_void(self : InstructionContext) -> Unit {
  self.complete_once([])
}

///|
pub fn InstructionContext::create_block(
  self : InstructionContext,
  parameter_types : Array[@native.ValueType],
) -> @lowering.Block {
  self.attempt(
    fn() { self.builder.create_block(parameter_types) },
    ({ id: -1, } : @lowering.Block),
  )
}

///|
pub fn InstructionContext::create_stack_object(
  self : InstructionContext,
  size : Int,
  alignment : Int,
) -> @native.StackObject {
  self.builder.create_stack_object(size, alignment)
}

///|
pub fn InstructionContext::block_parameters(
  self : InstructionContext,
  block : @lowering.Block,
) -> Array[@lowering.Value] {
  self.builder.block_parameters(block)
}

///|
pub fn InstructionContext::switch_to_block(
  self : InstructionContext,
  block : @lowering.Block,
) -> Unit {
  self.attempt(fn() { self.builder.switch_to_block(block) }, ())
}

///|
pub fn InstructionContext::jump(
  self : InstructionContext,
  target : @lowering.Block,
  arguments : Array[@lowering.Value],
) -> Unit {
  self.attempt(fn() { self.builder.jump(target, arguments) }, ())
}

///|
pub fn InstructionContext::branch(
  self : InstructionContext,
  condition : @lowering.Value,
  true_target : @lowering.Block,
  true_arguments : Array[@lowering.Value],
  false_target : @lowering.Block,
  false_arguments : Array[@lowering.Value],
) -> Unit {
  self.attempt(
    fn() {
      self.builder.branch(
        condition, true_target, true_arguments, false_target, false_arguments,
      )
    },
    (),
  )
}

///|
pub fn InstructionContext::trap(
  self : InstructionContext,
  reason : @native.TrapReason,
) -> Unit {
  self.attempt(fn() { self.builder.trap(reason) }, ())
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
  reason : @native.TrapReason,
) -> Unit {
  self.attempt(fn() { self.builder.trap(reason) }, ())
  if self.source is Some(source) {
    self.builder.set_terminator_source(source)
  }
}

///|
pub fn InstructionContext::tail_call(
  self : InstructionContext,
  call : @native.NativeCall,
  operands : Array[@lowering.Value],
) -> Unit {
  self.attempt(
    fn() {
      self.builder.tail_call_with_metadata(
        call,
        operands,
        self.terminator_metadata(),
      )
    },
    (),
  )
  self.terminates_block.val = true
  self.finish_void()
}

///|
pub fn InstructionContext::noreturn_call(
  self : InstructionContext,
  call : @native.NativeCall,
  operands : Array[@lowering.Value],
) -> Unit {
  let metadata = if call.behavior.gc_safepoint {
    self.terminator_metadata()
  } else {
    @lowering.TerminatorMetadata::new(self.source, [])
  }
  self.attempt(
    fn() { self.builder.noreturn_call_with_metadata(call, operands, metadata) },
    (),
  )
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
