///|
/// Embedding-owned identities required by WebAssembly semantic lowering.
///
/// Symbols remain unresolved and target-neutral. Address resolution belongs to
/// the embedding product after target emission.
struct Environment {
  function_symbol : (Int) -> @machv.CodeSymbol
}

///|
pub fn Environment::new(
  function_symbol : (Int) -> @machv.CodeSymbol,
) -> Environment {
  { function_symbol, }
}

///|
fn direct_call_contract(
  context : @adapter.InstructionContext,
  function_index : Int,
  environment : Environment,
  result_types : Array[@machv.ValueType],
) -> (@machv.SemanticCall, Array[@machv.Value]) {
  let parameter_types : Array[@machv.ValueType] = [Ptr64]
  for ty in context.operand_types() {
    parameter_types.push(ty)
  }
  let operands = context.environment()
  for operand in context.operands() {
    operands.push(operand)
  }
  (
    @machv.SemanticCall::new(
      Internal((environment.function_symbol)(function_index)),
      @machv.Signature::new(parameter_types, result_types),
      Internal,
      @machv.CallBehavior::conservative(),
    ),
    operands,
  )
}

///|
fn lower_direct_call(
  context : @adapter.InstructionContext,
  function_index : Int,
  environment : Environment,
) -> Unit {
  let (call, operands) = direct_call_contract(
    context,
    function_index,
    environment,
    context.result_types(),
  )
  context.finish_call(call, operands)
}

///|
fn lower_direct_tail_call(
  context : @adapter.InstructionContext,
  function_index : Int,
  environment : Environment,
) -> Unit {
  let (call, operands) = direct_call_contract(
    context,
    function_index,
    environment,
    context.function_result_types(),
  )
  context.tail_call(call, operands)
}

///|
fn untag_callable_reference(
  context : @adapter.InstructionContext,
  reference : @machv.Value,
) -> @machv.Value {
  let address = context.emit(GcRefAddress, [reference], [Ptr64])[0]
  let bits = context.emit(Convert(Bitcast(Ptr64, I64)), [address], [I64])[0]
  let mask = context.emit(I64Const(0xDFFFFFFFFFFFFFFFUL), [], [I64])[0]
  let untagged = context.emit(IntBinary(And), [bits, mask], [I64])[0]
  context.emit(Convert(Bitcast(I64, Ptr64)), [untagged], [Ptr64])[0]
}

///|
fn indirect_reference_call_contract(
  context : @adapter.InstructionContext,
  result_types : Array[@machv.ValueType],
) -> (@machv.SemanticCall, Array[@machv.Value]) {
  let source_operands = context.operands()
  let source_types = context.operand_types()
  let parameter_types : Array[@machv.ValueType] = [Ptr64]
  for index in 1..<source_types.length() {
    parameter_types.push(source_types[index])
  }
  let operands : Array[@machv.Value] = [
    untag_callable_reference(context, source_operands[0]),
  ]
  for value in context.environment() {
    operands.push(value)
  }
  for index in 1..<source_operands.length() {
    operands.push(source_operands[index])
  }
  (
    @machv.SemanticCall::new(
      Indirect,
      @machv.Signature::new(parameter_types, result_types),
      Internal,
      @machv.CallBehavior::conservative(),
    ),
    operands,
  )
}

///|
fn lower_call_ref(context : @adapter.InstructionContext) -> Unit {
  let (call, operands) = indirect_reference_call_contract(
    context,
    context.result_types(),
  )
  context.finish_call(call, operands)
}

///|
fn lower_tail_call_ref(context : @adapter.InstructionContext) -> Unit {
  let (call, operands) = indirect_reference_call_contract(
    context,
    context.function_result_types(),
  )
  context.tail_call(call, operands)
}

///|
fn lower_extension(
  context : @adapter.InstructionContext,
  extension : @milkir.ExtOp,
  environment : Environment,
) -> String? {
  let opcode = match @wasm_milkir.decode(extension) {
    Some(opcode) => opcode
    None => return Some("Wasm extension changed after successful validation")
  }
  match opcode {
    WasmCall(function_index) => {
      lower_direct_call(context, function_index, environment)
      None
    }
    ReturnCall(function_index) => {
      lower_direct_tail_call(context, function_index, environment)
      None
    }
    CallRef(_) => {
      lower_call_ref(context)
      None
    }
    ReturnCallRef(_) => {
      lower_tail_call_ref(context)
      None
    }
    _ =>
      Some("semantic Wasm lowering is not implemented for \{to_repr(opcode)}")
  }
}

///|
/// Lower a verified WebAssembly MilkIR function into target-neutral MachV.
///
/// The explicit leading `ptr64` parameter is the embedding execution
/// environment required by the internal WebAssembly call protocol.
pub fn lower_function(
  function : @milkir.Function,
  environment : Environment,
) -> @machv.Function raise @milkir_machv.SemanticLowerError {
  fn lower(
    context : @adapter.InstructionContext,
    extension : @milkir.ExtOp,
  ) -> String? {
    lower_extension(context, extension, environment)
  }
  @milkir_machv.lower_dialect_function(
    function,
    @wasm_milkir.WASM_DIALECT,
    @wasm_milkir.validate_extension,
    [Ptr64],
    lower,
  )
}
