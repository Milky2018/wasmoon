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
fn lower_direct_call(
  context : @adapter.InstructionContext,
  function_index : Int,
  environment : Environment,
) -> Unit {
  let parameter_types : Array[@machv.ValueType] = [Ptr64]
  for ty in context.operand_types() {
    parameter_types.push(ty)
  }
  let operands = context.environment()
  for operand in context.operands() {
    operands.push(operand)
  }
  context.finish_call(
    @machv.SemanticCall::new(
      Internal((environment.function_symbol)(function_index)),
      @machv.Signature::new(parameter_types, context.result_types()),
      Internal,
      @machv.CallBehavior::conservative(),
    ),
    operands,
  )
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
