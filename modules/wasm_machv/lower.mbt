///|
/// Embedding-owned identities required by WebAssembly semantic lowering.
///
/// Symbols remain unresolved and target-neutral. Address resolution belongs to
/// the embedding product after target emission.
struct Environment {
  function_symbol : (Int) -> @machv.CodeSymbol
  memory_base_field : (Int) -> @machv.EnvironmentField
  function_table_field : @machv.EnvironmentField
  table_base_field : (Int) -> @machv.EnvironmentField
  canonical_type_index : (Int) -> Int
  subtype_check_symbol : @machv.ExternalSymbol
}

///|
pub fn Environment::new(
  function_symbol : (Int) -> @machv.CodeSymbol,
  memory_base_field : (Int) -> @machv.EnvironmentField,
  function_table_field : @machv.EnvironmentField,
  table_base_field : (Int) -> @machv.EnvironmentField,
  canonical_type_index : (Int) -> Int,
  subtype_check_symbol : @machv.ExternalSymbol,
) -> Environment {
  {
    function_symbol,
    memory_base_field,
    function_table_field,
    table_base_field,
    canonical_type_index,
    subtype_check_symbol,
  }
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
fn lower_i31_new(context : @adapter.InstructionContext) -> Unit {
  let source = context.operands()[0]
  let extended = context.emit(Convert(I64ExtendI32(Unsigned)), [source], [I64])[0]
  let one = context.emit(I64Const(1UL), [], [I64])[0]
  let shifted = context.emit(IntBinary(ShiftLeft), [extended, one], [I64])[0]
  let tagged = context.emit(IntBinary(Or), [shifted, one], [I64])[0]
  context.finish_operation(GcRefFromBits, [tagged])
}

///|
fn lower_i31_get(context : @adapter.InstructionContext, signed : Bool) -> Unit {
  let source = context.operands()[0]
  let null_reference = context.emit(NullGcRef, [], [GcRef64])[0]
  let is_null = context.emit(
      ReferenceCompare(Equal),
      [source, null_reference],
      [I32],
    )[0]
  let trap_block = context.create_block([])
  let decode_block = context.create_block([])
  context.branch(is_null, trap_block, [], decode_block, [])
  context.switch_to_block(trap_block)
  context.set_trap_terminator(NullReference)
  context.switch_to_block(decode_block)
  let address = context.emit(GcRefAddress, [source], [Ptr64])[0]
  let bits = context.emit(Convert(Bitcast(Ptr64, I64)), [address], [I64])[0]
  let one64 = context.emit(I64Const(1UL), [], [I64])[0]
  let decoded = context.emit(IntBinary(UnsignedShiftRight), [bits, one64], [I64])[0]
  let truncated = context.emit(Convert(I32WrapI64), [decoded], [I32])[0]
  let result = if signed {
    let one32 = context.emit(I32Const(1U), [], [I32])[0]
    let shifted = context.emit(IntBinary(ShiftLeft), [truncated, one32], [I32])[0]
    context.emit(IntBinary(SignedShiftRight), [shifted, one32], [I32])[0]
  } else {
    let mask = context.emit(I32Const(0x7FFFFFFFU), [], [I32])[0]
    context.emit(IntBinary(And), [truncated, mask], [I32])[0]
  }
  context.forward_results([result])
}

///|
fn lower_memory_base(
  context : @adapter.InstructionContext,
  memory_index : Int,
  environment : Environment,
) -> Unit {
  let pointer = context.emit(
      EnvironmentField((environment.memory_base_field)(memory_index)),
      context.operands(),
      [Ptr64],
    )[0]
  context.finish_operation(Convert(Bitcast(Ptr64, I64)), [pointer])
}

///|
fn lower_get_function_reference(
  context : @adapter.InstructionContext,
  function_index : Int,
  environment : Environment,
) -> Unit {
  let execution_environment = context.environment()[0]
  let function_table = context.emit(
      EnvironmentField(environment.function_table_field),
      [execution_environment],
      [Ptr64],
    )[0]
  let offset = context.emit(I64Const((function_index * 8).to_uint64()), [], [
      I64,
    ])[0]
  let entry = context.emit(PointerOffset, [function_table, offset], [Ptr64])[0]
  let function_pointer = context.emit(
      Load(@machv.LoadSpec::new(W64, None, Ptr64, 0UL, Little, None)),
      [entry],
      [Ptr64],
    )[0]
  let bits = context.emit(Convert(Bitcast(Ptr64, I64)), [function_pointer], [
      I64,
    ])[0]
  let tag = context.emit(I64Const(0x2000000000000000UL), [], [I64])[0]
  let tagged = context.emit(IntBinary(Or), [bits, tag], [I64])[0]
  context.finish_operation(GcRefFromBits, [tagged])
}

///|
fn table_entry_address(
  context : @adapter.InstructionContext,
  table_index : Int,
  environment : Environment,
) -> @machv.Value {
  let source_index = context.operands()[0]
  let index = if context.operand_types()[0] == I32 {
    context.emit(Convert(I64ExtendI32(Unsigned)), [source_index], [I64])[0]
  } else {
    source_index
  }
  let shift = context.emit(I64Const(4UL), [], [I64])[0]
  let byte_offset = context.emit(IntBinary(ShiftLeft), [index, shift], [I64])[0]
  let table = context.emit(
      EnvironmentField((environment.table_base_field)(table_index)),
      context.environment(),
      [Ptr64],
    )[0]
  context.emit(PointerOffset, [table, byte_offset], [Ptr64])[0]
}

///|
fn check_indirect_type(
  context : @adapter.InstructionContext,
  entry : @machv.Value,
  type_index : Int,
  environment : Environment,
) -> Unit {
  let actual = context.emit(
      Load(@machv.LoadSpec::new(W32, None, I32, 8UL, Little, None)),
      [entry],
      [I32],
    )[0]
  let expected = context.emit(
      I32Const(
        (environment.canonical_type_index)(type_index).reinterpret_as_uint(),
      ),
      [],
      [I32],
    )[0]
  let exact = context.emit(IntCompare(Equal), [actual, expected], [I32])[0]
  let subtype_block = context.create_block([])
  let continuation = context.create_block([])
  context.branch(exact, continuation, [], subtype_block, [])
  context.switch_to_block(subtype_block)
  context.emit_call_without_roots(
    @machv.SemanticCall::new(
      External(environment.subtype_check_symbol),
      @machv.Signature::new([I32, I32], []),
      Platform,
      @machv.CallBehavior::new(Read, true, false, false, false),
    ),
    [actual, expected],
    [],
  )
  |> ignore
  context.jump(continuation, [])
  context.switch_to_block(continuation)
}

///|
fn lower_indirect_call(
  context : @adapter.InstructionContext,
  type_index : Int,
  table_index : Int,
  environment : Environment,
  tail : Bool,
) -> Unit {
  let entry = table_entry_address(context, table_index, environment)
  let raw_pointer = context.emit(
      Load(@machv.LoadSpec::new(W64, None, Ptr64, 0UL, Little, None)),
      [entry],
      [Ptr64],
    )[0]
  check_indirect_type(context, entry, type_index, environment)
  let bits = context.emit(Convert(Bitcast(Ptr64, I64)), [raw_pointer], [I64])[0]
  let mask = context.emit(I64Const(0xDFFFFFFFFFFFFFFFUL), [], [I64])[0]
  let untagged = context.emit(IntBinary(And), [bits, mask], [I64])[0]
  let function_pointer = context.emit(
      Convert(Bitcast(I64, Ptr64)),
      [untagged],
      [Ptr64],
    )[0]
  let source_operands = context.operands()
  let source_types = context.operand_types()
  let parameter_types : Array[@machv.ValueType] = [Ptr64]
  let call_operands : Array[@machv.Value] = [function_pointer]
  for value in context.environment() {
    call_operands.push(value)
  }
  for index in 1..<source_operands.length() {
    parameter_types.push(source_types[index])
    call_operands.push(source_operands[index])
  }
  let result_types = if tail {
    context.function_result_types()
  } else {
    context.result_types()
  }
  let call = @machv.SemanticCall::new(
    Indirect,
    @machv.Signature::new(parameter_types, result_types),
    Internal,
    @machv.CallBehavior::conservative(),
  )
  if tail {
    context.tail_call(call, call_operands)
  } else {
    context.finish_call(call, call_operands)
  }
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
    LoadMemBase(memory_index) => {
      lower_memory_base(context, memory_index, environment)
      None
    }
    GetFuncRef(function_index) => {
      lower_get_function_reference(context, function_index, environment)
      None
    }
    WasmCall(function_index) => {
      lower_direct_call(context, function_index, environment)
      None
    }
    WasmCallIndirect(type_index, table_index) => {
      lower_indirect_call(context, type_index, table_index, environment, false)
      None
    }
    ReturnCallIndirect(type_index, table_index) => {
      lower_indirect_call(context, type_index, table_index, environment, true)
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
    I31New => {
      lower_i31_new(context)
      None
    }
    I31GetS => {
      lower_i31_get(context, true)
      None
    }
    I31GetU => {
      lower_i31_get(context, false)
      None
    }
    AnyConvertExtern | ExternConvertAny => {
      context.finish_operation(Copy, context.operands())
      None
    }
    RefEq => {
      context.finish_operation(ReferenceCompare(Equal), context.operands())
      None
    }
    _ =>
      Some("semantic Wasm lowering is not implemented for \{to_repr(opcode)}")
  }
}

///|
/// Lower a verified WebAssembly MilkIR function into target-neutral MachV.
///
/// MilkIR parameter zero is the explicit embedding execution environment. Its
/// legacy `i64` carrier is contracted to `ptr64` in semantic MachV.
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
    [(0, Ptr64)],
    lower,
  )
}
