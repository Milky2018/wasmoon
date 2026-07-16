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
  runtime_symbol : (String) -> @machv.ExternalSymbol
}

///|
pub fn Environment::new(
  function_symbol : (Int) -> @machv.CodeSymbol,
  memory_base_field : (Int) -> @machv.EnvironmentField,
  function_table_field : @machv.EnvironmentField,
  table_base_field : (Int) -> @machv.EnvironmentField,
  canonical_type_index : (Int) -> Int,
  runtime_symbol : (String) -> @machv.ExternalSymbol,
) -> Environment {
  {
    function_symbol,
    memory_base_field,
    function_table_field,
    table_base_field,
    canonical_type_index,
    runtime_symbol,
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
      External((environment.runtime_symbol)("gc.type_check_subtype")),
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
fn finish_runtime_call(
  context : @adapter.InstructionContext,
  environment : Environment,
  capability : String,
  operands : Array[@machv.Value],
  parameter_types : Array[@machv.ValueType],
  behavior : @machv.CallBehavior,
) -> Unit {
  context.finish_call_without_roots(
    @machv.SemanticCall::new(
      External((environment.runtime_symbol)(capability)),
      @machv.Signature::new(parameter_types, context.result_types()),
      Platform,
      behavior,
    ),
    operands,
  )
}

///|
fn i32_immediate(
  context : @adapter.InstructionContext,
  value : Int,
) -> @machv.Value {
  context.emit(I32Const(value.reinterpret_as_uint()), [], [I32])[0]
}

///|
fn bool_immediate(
  context : @adapter.InstructionContext,
  value : Bool,
) -> @machv.Value {
  i32_immediate(context, if value { 1 } else { 0 })
}

///|
fn lower_ref_test(
  context : @adapter.InstructionContext,
  environment : Environment,
  type_index : Int,
  nullable : Bool,
) -> Unit {
  let operands = context.operands()
  operands.push(i32_immediate(context, type_index))
  operands.push(bool_immediate(context, nullable))
  finish_runtime_call(
    context,
    environment,
    "gc.ref_test",
    operands,
    [GcRef64, I32, I32],
    @machv.CallBehavior::new(Read, false, false, false, false),
  )
}

///|
fn lower_ref_cast(
  context : @adapter.InstructionContext,
  environment : Environment,
  type_index : Int,
  nullable : Bool,
) -> Unit {
  let operands = context.operands()
  operands.push(i32_immediate(context, type_index))
  operands.push(bool_immediate(context, nullable))
  finish_runtime_call(
    context,
    environment,
    "gc.ref_cast",
    operands,
    [GcRef64, I32, I32],
    @machv.CallBehavior::new(Read, true, false, false, false),
  )
}

///|
fn lower_array_len(
  context : @adapter.InstructionContext,
  environment : Environment,
) -> Unit {
  finish_runtime_call(
    context,
    environment,
    "gc.array_len",
    context.operands(),
    [GcRef64],
    @machv.CallBehavior::new(Read, true, false, false, false),
  )
}

///|
fn is_runtime_word_type(ty : @machv.ValueType) -> Bool {
  ty != V128
}

///|
fn encode_runtime_word(
  context : @adapter.InstructionContext,
  value : @machv.Value,
  ty : @machv.ValueType,
) -> @machv.Value {
  match ty {
    I32 => context.emit(Convert(I64ExtendI32(Unsigned)), [value], [I64])[0]
    I64 => value
    F32 => {
      let bits = context.emit(Convert(Bitcast(F32, I32)), [value], [I32])[0]
      context.emit(Convert(I64ExtendI32(Unsigned)), [bits], [I64])[0]
    }
    F64 => context.emit(Convert(Bitcast(F64, I64)), [value], [I64])[0]
    Ptr64 => context.emit(Convert(Bitcast(Ptr64, I64)), [value], [I64])[0]
    GcRef64 => {
      let address = context.emit(GcRefAddress, [value], [Ptr64])[0]
      context.emit(Convert(Bitcast(Ptr64, I64)), [address], [I64])[0]
    }
    V128 => abort("v128 is not a 64-bit runtime word")
  }
}

///|
fn finish_runtime_word(
  context : @adapter.InstructionContext,
  word : @machv.Value,
) -> Unit {
  match context.result_types()[0] {
    I32 => context.finish_operation(Convert(I32WrapI64), [word])
    I64 => context.finish_operation(Copy, [word])
    F32 => {
      let bits = context.emit(Convert(I32WrapI64), [word], [I32])[0]
      context.finish_operation(Convert(Bitcast(I32, F32)), [bits])
    }
    F64 => context.finish_operation(Convert(Bitcast(I64, F64)), [word])
    Ptr64 => context.finish_operation(Convert(Bitcast(I64, Ptr64)), [word])
    GcRef64 => context.finish_operation(GcRefFromBits, [word])
    V128 => abort("v128 is not a 64-bit runtime word")
  }
}

///|
fn emit_runtime_word_call(
  context : @adapter.InstructionContext,
  environment : Environment,
  capability : String,
  operands : Array[@machv.Value],
  parameter_types : Array[@machv.ValueType],
  memory : @machv.MemoryEffect,
) -> @machv.Value {
  context.emit_call_without_roots(
    @machv.SemanticCall::new(
      External((environment.runtime_symbol)(capability)),
      @machv.Signature::new(parameter_types, [I64]),
      Platform,
      @machv.CallBehavior::new(memory, true, false, false, false),
    ),
    operands,
    [I64],
  )[0]
}

///|
fn lower_aggregate_get(
  context : @adapter.InstructionContext,
  environment : Environment,
  capability : String,
  type_index : Int,
  field_index : Int?,
) -> String? {
  if !is_runtime_word_type(context.result_types()[0]) {
    return Some(
      "the current Wasm GC runtime ABI cannot return a v128 aggregate value",
    )
  }
  let source_operands = context.operands()
  let operands : Array[@machv.Value] = [source_operands[0]]
  let parameter_types : Array[@machv.ValueType] = [GcRef64, I32, I32]
  operands.push(i32_immediate(context, type_index))
  if field_index is Some(index) {
    operands.push(i32_immediate(context, index))
  } else {
    operands.push(source_operands[1])
  }
  let word = emit_runtime_word_call(
    context,
    environment,
    capability,
    operands,
    parameter_types,
    Read,
  )
  finish_runtime_word(context, word)
  None
}

///|
fn finish_packed_runtime_word(
  context : @adapter.InstructionContext,
  word : @machv.Value,
  byte_width : Int,
  signed : Bool,
) -> Unit {
  let narrowed = context.emit(Convert(I32WrapI64), [word], [I32])[0]
  if signed {
    let width : @machv.AccessWidth = if byte_width == 1 { W8 } else { W16 }
    context.finish_operation(Convert(SignExtend(I32, width)), [narrowed])
  } else {
    let mask = context.emit(
        I32Const(if byte_width == 1 { 0xFFU } else { 0xFFFFU }),
        [],
        [I32],
      )[0]
    context.finish_operation(IntBinary(And), [narrowed, mask])
  }
}

///|
fn lower_packed_aggregate_get(
  context : @adapter.InstructionContext,
  environment : Environment,
  capability : String,
  type_index : Int,
  field_index : Int?,
  byte_width : Int,
  signed : Bool,
) -> Unit {
  let source_operands = context.operands()
  let operands : Array[@machv.Value] = [source_operands[0]]
  let parameter_types : Array[@machv.ValueType] = [GcRef64, I32, I32]
  operands.push(i32_immediate(context, type_index))
  if field_index is Some(index) {
    operands.push(i32_immediate(context, index))
  } else {
    operands.push(source_operands[1])
  }
  let word = emit_runtime_word_call(
    context,
    environment,
    capability,
    operands,
    parameter_types,
    Read,
  )
  finish_packed_runtime_word(context, word, byte_width, signed)
}

///|
fn lower_aggregate_set(
  context : @adapter.InstructionContext,
  environment : Environment,
  capability : String,
  type_index : Int,
  field_index : Int?,
) -> String? {
  let source_operands = context.operands()
  let source_types = context.operand_types()
  let value_index = source_operands.length() - 1
  if !is_runtime_word_type(source_types[value_index]) {
    return Some(
      "the current Wasm GC runtime ABI cannot store a v128 aggregate value",
    )
  }
  let value = encode_runtime_word(
    context,
    source_operands[value_index],
    source_types[value_index],
  )
  let operands : Array[@machv.Value] = [source_operands[0]]
  let parameter_types : Array[@machv.ValueType] = [GcRef64, I32]
  operands.push(i32_immediate(context, type_index))
  if field_index is Some(index) {
    operands.push(i32_immediate(context, index))
    parameter_types.push(I32)
  } else {
    operands.push(source_operands[1])
    parameter_types.push(I32)
  }
  operands.push(value)
  parameter_types.push(I64)
  finish_runtime_call(
    context,
    environment,
    capability,
    operands,
    parameter_types,
    @machv.CallBehavior::new(ReadWrite, true, false, false, false),
  )
  None
}

///|
fn lower_array_fill(
  context : @adapter.InstructionContext,
  environment : Environment,
) -> String? {
  let source_operands = context.operands()
  let source_types = context.operand_types()
  if !is_runtime_word_type(source_types[2]) {
    return Some(
      "the current Wasm GC runtime ABI cannot fill arrays with v128 values",
    )
  }
  let value = encode_runtime_word(context, source_operands[2], source_types[2])
  finish_runtime_call(
    context,
    environment,
    "gc.array_fill",
    [source_operands[0], source_operands[1], value, source_operands[3]],
    [GcRef64, I32, I64, I32],
    @machv.CallBehavior::new(ReadWrite, true, false, false, false),
  )
  None
}

///|
fn lower_array_copy(
  context : @adapter.InstructionContext,
  environment : Environment,
) -> Unit {
  finish_runtime_call(
    context,
    environment,
    "gc.array_copy",
    context.operands(),
    [GcRef64, I32, GcRef64, I32, I32],
    @machv.CallBehavior::new(ReadWrite, true, false, false, false),
  )
}

///|
fn emit_gc_allocation(
  context : @adapter.InstructionContext,
  environment : Environment,
  capability : String,
  operands : Array[@machv.Value],
  parameter_types : Array[@machv.ValueType],
) -> @machv.Value {
  context.emit_call(
    @machv.SemanticCall::new(
      External((environment.runtime_symbol)(capability)),
      @machv.Signature::new(parameter_types, [I64]),
      Platform,
      @machv.CallBehavior::new(ReadWrite, true, false, true, false),
    ),
    operands,
    [I64],
  )[0]
}

///|
fn lower_array_new(
  context : @adapter.InstructionContext,
  environment : Environment,
  type_index : Int,
  use_default : Bool,
) -> String? {
  let source_operands = context.operands()
  let source_types = context.operand_types()
  let initial = if use_default {
    context.emit(I64Const(0UL), [], [I64])[0]
  } else {
    if !is_runtime_word_type(source_types[0]) {
      return Some(
        "the current Wasm GC runtime ABI cannot initialize arrays with v128 values",
      )
    }
    encode_runtime_word(context, source_operands[0], source_types[0])
  }
  let length = if use_default { source_operands[0] } else { source_operands[1] }
  let operands = context.environment()
  operands.push(i32_immediate(context, type_index))
  operands.push(length)
  operands.push(initial)
  let word = emit_gc_allocation(
    context,
    environment,
    "gc.alloc_array_slow",
    operands,
    [Ptr64, I32, I32, I64],
  )
  finish_runtime_word(context, word)
  None
}

///|
fn lower_struct_new_default(
  context : @adapter.InstructionContext,
  environment : Environment,
  type_index : Int,
) -> Unit {
  let operands = context.environment()
  operands.push(i32_immediate(context, type_index))
  operands.push(context.emit(NullPtr, [], [Ptr64])[0])
  operands.push(i32_immediate(context, 0))
  let word = emit_gc_allocation(
    context,
    environment,
    "gc.alloc_struct_slow",
    operands,
    [Ptr64, I32, Ptr64, I32],
  )
  finish_runtime_word(context, word)
}

///|
fn lower_array_segment_new(
  context : @adapter.InstructionContext,
  environment : Environment,
  capability : String,
  type_index : Int,
  segment_index : Int,
) -> Unit {
  let operands = context.environment()
  operands.push(i32_immediate(context, type_index))
  operands.push(i32_immediate(context, segment_index))
  for operand in context.operands() {
    operands.push(operand)
  }
  let word = emit_gc_allocation(context, environment, capability, operands, [
    Ptr64,
    I32,
    I32,
    I32,
    I32,
  ])
  finish_runtime_word(context, word)
}

///|
fn lower_array_segment_init(
  context : @adapter.InstructionContext,
  environment : Environment,
  capability : String,
  type_index : Int,
  segment_index : Int,
) -> Unit {
  let operands = context.environment()
  operands.push(i32_immediate(context, type_index))
  operands.push(i32_immediate(context, segment_index))
  for operand in context.operands() {
    operands.push(operand)
  }
  finish_runtime_call(
    context,
    environment,
    capability,
    operands,
    [Ptr64, I32, I32, GcRef64, I32, I32, I32],
    @machv.CallBehavior::new(ReadWrite, true, false, false, false),
  )
}

///|
fn emit_runtime_word_buffer(
  context : @adapter.InstructionContext,
  values : Array[@machv.Value],
  types : Array[@machv.ValueType],
) -> @machv.Value {
  if values.is_empty() {
    return context.emit(NullPtr, [], [Ptr64])[0]
  }
  let object = context.create_stack_object(values.length() * 8, 16)
  let address = context.emit(StackAddress(object), [], [Ptr64])[0]
  for index, value in values {
    let word = encode_runtime_word(context, value, types[index])
    context.emit(
      Store(
        @machv.StoreSpec::new(W64, I64, (index * 8).to_uint64(), Little, None),
      ),
      [address, word],
      [],
    )
    |> ignore
  }
  address
}

///|
fn lower_fixed_allocation(
  context : @adapter.InstructionContext,
  environment : Environment,
  capability : String,
  type_index : Int,
) -> String? {
  let types = context.operand_types()
  for ty in types {
    if !is_runtime_word_type(ty) {
      return Some(
        "the current Wasm GC runtime ABI cannot allocate v128 aggregate values",
      )
    }
  }
  let values = context.operands()
  let buffer = emit_runtime_word_buffer(context, values, types)
  let operands = context.environment()
  operands.push(i32_immediate(context, type_index))
  operands.push(buffer)
  operands.push(i32_immediate(context, values.length()))
  let word = emit_gc_allocation(context, environment, capability, operands, [
    Ptr64,
    I32,
    Ptr64,
    I32,
  ])
  finish_runtime_word(context, word)
  None
}

///|
fn lower_spill_locals(
  context : @adapter.InstructionContext,
  environment : Environment,
) -> String? {
  let types = context.operand_types()
  for ty in types {
    if !is_runtime_word_type(ty) {
      return Some(
        "the current Wasm exception ABI cannot spill v128 as one runtime word",
      )
    }
  }
  let values = context.operands()
  let buffer = emit_runtime_word_buffer(context, values, types)
  let operands = context.environment()
  operands.push(buffer)
  operands.push(i32_immediate(context, values.length()))
  finish_runtime_call(
    context,
    environment,
    "exception.spill_locals",
    operands,
    [Ptr64, Ptr64, I32],
    @machv.CallBehavior::new(ReadWrite, false, false, false, false),
  )
  None
}

///|
fn finish_noreturn_runtime_call(
  context : @adapter.InstructionContext,
  environment : Environment,
  capability : String,
  operands : Array[@machv.Value],
  parameter_types : Array[@machv.ValueType],
) -> Unit {
  context.noreturn_call(
    @machv.SemanticCall::new(
      External((environment.runtime_symbol)(capability)),
      @machv.Signature::new(parameter_types, []),
      Platform,
      @machv.CallBehavior::new(ReadWrite, true, false, false, false),
    ),
    operands,
  )
}

///|
fn lower_throw(
  context : @adapter.InstructionContext,
  environment : Environment,
  tag_index : Int,
) -> String? {
  let types = context.operand_types()
  for ty in types {
    if !is_runtime_word_type(ty) {
      return Some(
        "the current Wasm exception ABI cannot throw v128 as one runtime word",
      )
    }
  }
  let values = context.operands()
  let operands = context.environment()
  operands.push(i32_immediate(context, tag_index))
  if values.is_empty() {
    finish_noreturn_runtime_call(
      context,
      environment,
      "exception.throw_tag",
      operands,
      [Ptr64, I32],
    )
  } else {
    operands.push(emit_runtime_word_buffer(context, values, types))
    operands.push(i32_immediate(context, values.length()))
    finish_noreturn_runtime_call(
      context,
      environment,
      "exception.throw",
      operands,
      [Ptr64, I32, Ptr64, I32],
    )
  }
  None
}

///|
fn lower_throw_ref(
  context : @adapter.InstructionContext,
  environment : Environment,
) -> Unit {
  let operands = context.environment()
  operands.append(context.operands())
  finish_noreturn_runtime_call(
    context,
    environment,
    "exception.throw_ref",
    operands,
    [Ptr64, GcRef64],
  )
}

///|
fn lower_delegate(
  context : @adapter.InstructionContext,
  environment : Environment,
  depth : Int,
) -> Unit {
  let operands = context.environment()
  operands.push(i32_immediate(context, depth))
  finish_noreturn_runtime_call(
    context,
    environment,
    "exception.delegate",
    operands,
    [Ptr64, I32],
  )
}

///|
fn lower_exception_query(
  context : @adapter.InstructionContext,
  environment : Environment,
  capability : String,
  immediate : Int?,
) -> Unit {
  let operands = context.environment()
  let parameter_types : Array[@machv.ValueType] = [Ptr64]
  if immediate is Some(value) {
    operands.push(
      context.emit(I32Const(value.reinterpret_as_uint()), [], [I32])[0],
    )
    parameter_types.push(I32)
  }
  finish_runtime_call(
    context,
    environment,
    capability,
    operands,
    parameter_types,
    @machv.CallBehavior::new(Read, false, false, false, false),
  )
}

///|
fn lower_try_table_end(
  context : @adapter.InstructionContext,
  environment : Environment,
  handler_id : Int,
) -> Unit {
  let operands = context.environment()
  operands.push(
    context.emit(I32Const(handler_id.reinterpret_as_uint()), [], [I32])[0],
  )
  finish_runtime_call(
    context,
    environment,
    "exception.try_end",
    operands,
    [Ptr64, I32],
    @machv.CallBehavior::new(ReadWrite, false, false, false, false),
  )
}

///|
fn lower_try_table_begin(
  context : @adapter.InstructionContext,
  environment : Environment,
  handler_id : Int,
) -> Unit {
  let operands = context.environment()
  operands.push(i32_immediate(context, handler_id))
  let buffer = context.emit_call_without_roots(
      @machv.SemanticCall::new(
        External((environment.runtime_symbol)("exception.try_begin")),
        @machv.Signature::new([Ptr64, I32], [Ptr64]),
        Platform,
        @machv.CallBehavior::new(ReadWrite, true, false, false, false),
      ),
      operands,
      [Ptr64],
    )[0]
  finish_runtime_call(
    context,
    environment,
    "exception.sigsetjmp",
    [buffer, i32_immediate(context, 0)],
    [Ptr64, I32],
    @machv.CallBehavior::new(
      ReadWrite,
      false,
      false,
      false,
      false,
      returns_twice=true,
    ),
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
    RefTest(type_index, nullable) => {
      lower_ref_test(context, environment, type_index, nullable)
      None
    }
    RefCast(type_index, nullable) => {
      lower_ref_cast(context, environment, type_index, nullable)
      None
    }
    ArrayLen => {
      lower_array_len(context, environment)
      None
    }
    StructGet(type_index, field_index) =>
      lower_aggregate_get(
        context,
        environment,
        "gc.struct_get",
        type_index,
        Some(field_index),
      )
    StructGetS(type_index, field_index, byte_width) => {
      lower_packed_aggregate_get(
        context,
        environment,
        "gc.struct_get",
        type_index,
        Some(field_index),
        byte_width,
        true,
      )
      None
    }
    StructGetU(type_index, field_index, byte_width) => {
      lower_packed_aggregate_get(
        context,
        environment,
        "gc.struct_get",
        type_index,
        Some(field_index),
        byte_width,
        false,
      )
      None
    }
    StructSet(type_index, field_index) =>
      lower_aggregate_set(
        context,
        environment,
        "gc.struct_set",
        type_index,
        Some(field_index),
      )
    ArrayGet(type_index) =>
      lower_aggregate_get(
        context,
        environment,
        "gc.array_get",
        type_index,
        None,
      )
    ArrayGetS(type_index, byte_width) => {
      lower_packed_aggregate_get(
        context,
        environment,
        "gc.array_get",
        type_index,
        None,
        byte_width,
        true,
      )
      None
    }
    ArrayGetU(type_index, byte_width) => {
      lower_packed_aggregate_get(
        context,
        environment,
        "gc.array_get",
        type_index,
        None,
        byte_width,
        false,
      )
      None
    }
    ArraySet(type_index) =>
      lower_aggregate_set(
        context,
        environment,
        "gc.array_set",
        type_index,
        None,
      )
    ArrayFill(_) => lower_array_fill(context, environment)
    ArrayCopy(_, _) => {
      lower_array_copy(context, environment)
      None
    }
    ArrayNew(type_index) =>
      lower_array_new(context, environment, type_index, false)
    ArrayNewDefault(type_index) =>
      lower_array_new(context, environment, type_index, true)
    StructNewDefault(type_index) => {
      lower_struct_new_default(context, environment, type_index)
      None
    }
    StructNew(type_index) =>
      lower_fixed_allocation(
        context, environment, "gc.alloc_struct_slow", type_index,
      )
    ArrayNewFixed(type_index, _) =>
      lower_fixed_allocation(
        context, environment, "gc.alloc_array_from_values_slow", type_index,
      )
    ArrayNewData(type_index, data_index) => {
      lower_array_segment_new(
        context, environment, "gc.array_new_data", type_index, data_index,
      )
      None
    }
    ArrayNewElem(type_index, element_index) => {
      lower_array_segment_new(
        context, environment, "gc.array_new_elem", type_index, element_index,
      )
      None
    }
    ArrayInitData(type_index, data_index) => {
      lower_array_segment_init(
        context, environment, "gc.array_init_data", type_index, data_index,
      )
      None
    }
    ArrayInitElem(type_index, element_index) => {
      lower_array_segment_init(
        context, environment, "gc.array_init_elem", type_index, element_index,
      )
      None
    }
    SpillLocalsForThrow(_) => lower_spill_locals(context, environment)
    Throw(tag_index) => lower_throw(context, environment, tag_index)
    ThrowRef => {
      lower_throw_ref(context, environment)
      None
    }
    Delegate(depth) => {
      lower_delegate(context, environment, depth)
      None
    }
    TryTableBegin(handler_id) => {
      lower_try_table_begin(context, environment, handler_id)
      None
    }
    TryTableEnd(handler_id) => {
      lower_try_table_end(context, environment, handler_id)
      None
    }
    GetExceptionTag => {
      lower_exception_query(context, environment, "exception.get_tag", None)
      None
    }
    GetExceptionValue(index) => {
      lower_exception_query(
        context,
        environment,
        "exception.get_value",
        Some(index),
      )
      None
    }
    GetExceptionValueCount => {
      lower_exception_query(
        context,
        environment,
        "exception.get_value_count",
        None,
      )
      None
    }
    GetSpilledLocal(index) => {
      lower_exception_query(
        context,
        environment,
        "exception.get_spilled_local",
        Some(index),
      )
      None
    }
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
