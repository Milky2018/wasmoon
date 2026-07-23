///|
pub suberror AArch64LowerError {
  InvalidSemantic(cause~ : @semantic.MachVVerifyError)
  MissingMappedValue(value_index~ : Int)
  UnsupportedOperation(
    block_index~ : Int,
    instruction_index~ : Int,
    operation~ : @semantic.Operation
  )
  UnsupportedAbi(message~ : String)
  BuildFailure(cause~ : @vcode.VCodeBuildError)
  InvalidTarget(cause~ : TargetVCodeVerifyError)
} derive(Debug)

///|
pub impl Show for AArch64LowerError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
fn align_up(value : Int, alignment : Int) -> Int {
  (value + alignment - 1) / alignment * alignment
}

///|
fn gpr_width(ty : @semantic.ValueType) -> GprWidth? {
  match ty {
    I32 => Some(W32)
    I64 => Some(W64)
    _ => None
  }
}

///|
fn optional_gpr_width(ty : @semantic.ValueType?) -> GprWidth? {
  match ty {
    Some(ty) => gpr_width(ty)
    None => None
  }
}

///|
fn scalar_access_width(ty : @semantic.ValueType) -> @semantic.AccessWidth? {
  match ty {
    I32 | F32 => Some(W32)
    I64 | Ptr64 | GcRef64 | F64 => Some(W64)
    V128 => None
  }
}

///|
fn lower_stack_object(
  function : @semantic.Function,
  requested : @semantic.StackObject,
) -> AArch64StackObject raise AArch64LowerError {
  let objects = function.stack_objects()
  let offsets : Array[Int] = []
  let mut cursor = 0
  let mut area_alignment = 1
  for object in objects {
    let alignment = function.stack_object_alignment(object).unwrap()
    let size = function.stack_object_size(object).unwrap()
    cursor = align_up(cursor, alignment)
    offsets.push(cursor)
    cursor += size
    if alignment > area_alignment {
      area_alignment = alignment
    }
  }
  let area_size = align_up(cursor, area_alignment)
  for index, object in objects {
    if object == requested {
      return AArch64StackObject::new(
        offsets[index],
        function.stack_object_size(object).unwrap(),
        function.stack_object_alignment(object).unwrap(),
        area_size,
        area_alignment,
      )
    }
  }
  raise UnsupportedAbi(message="stack object is not function-owned")
}

///|
fn lower_binary(operation : @semantic.IntBinaryOp) -> AArch64IntBinary? {
  match operation {
    Add => Some(Add)
    Sub => Some(Sub)
    Mul => Some(Mul)
    And => Some(And)
    Or => Some(Orr)
    Xor => Some(Eor)
    ShiftLeft => Some(Lsl)
    SignedShiftRight => Some(Asr)
    UnsignedShiftRight => Some(Lsr)
    RotateRight => Some(Ror)
    SignedDiv | UnsignedDiv | SignedRem | UnsignedRem | RotateLeft => None
  }
}

///|
fn lower_condition(comparison : @semantic.IntComparison) -> AArch64Condition {
  match comparison {
    Equal => Eq
    NotEqual => Ne
    SignedLessThan => Lt
    SignedLessOrEqual => Le
    SignedGreaterThan => Gt
    SignedGreaterOrEqual => Ge
    UnsignedLessThan => Lo
    UnsignedLessOrEqual => Ls
    UnsignedGreaterThan => Hi
    UnsignedGreaterOrEqual => Hs
  }
}

///|
fn swapped_condition(condition : AArch64Condition) -> AArch64Condition {
  match condition {
    Eq => Eq
    Ne => Ne
    Lt => Gt
    Le => Ge
    Gt => Lt
    Ge => Le
    Lo => Hi
    Ls => Hs
    Hi => Lo
    Hs => Ls
  }
}

///|
fn lower_reference_condition(
  comparison : @semantic.ReferenceComparison,
) -> AArch64Condition {
  match comparison {
    Equal => Eq
    NotEqual => Ne
  }
}

///|
fn lower_float_unary(operation : @semantic.FloatUnaryOp) -> AArch64FloatUnary? {
  match operation {
    Negate => Some(Negate)
    Absolute => Some(Absolute)
    SquareRoot => Some(SquareRoot)
    Ceil => Some(Ceil)
    Floor => Some(Floor)
    Truncate => Some(Truncate)
    Nearest => Some(Nearest)
  }
}

///|
fn lower_float_binary(
  operation : @semantic.FloatBinaryOp,
) -> AArch64FloatBinary? {
  match operation {
    Add => Some(Add)
    Sub => Some(Sub)
    Mul => Some(Mul)
    Div => Some(Div)
    Min => Some(Min)
    Max => Some(Max)
    CopySign => Some(CopySign)
  }
}

///|
fn lower_float_ternary(
  operation : @semantic.FloatTernaryOp,
) -> AArch64FloatTernary {
  match operation {
    FusedMultiplyAdd => Fmadd
    FusedNegatedMultiplyAdd => Fmsub
    FusedMultiplySubtract => Fnmsub
    FusedNegatedMultiplySubtract => Fnmadd
  }
}

///|
fn lower_float_condition(
  comparison : @semantic.FloatComparison,
) -> AArch64FloatCondition? {
  match comparison {
    Equal => Some(Equal)
    NotEqual => Some(NotEqual)
    LessThan => Some(LessThan)
    LessOrEqual => Some(LessOrEqual)
    GreaterThan => Some(GreaterThan)
    GreaterOrEqual => Some(GreaterOrEqual)
    Ordered => Some(Ordered)
    Unordered => Some(Unordered)
  }
}

///|
fn lower_conversion(conversion : @semantic.ConversionOp) -> AArch64Conversion? {
  match conversion {
    I32WrapI64 => Some(WrapI64ToI32)
    I64ExtendI32(signedness) => Some(ExtendI32ToI64(signedness))
    SignExtend(I32, W8) => Some(SignExtend(I32, W8))
    SignExtend(I32, W16) => Some(SignExtend(I32, W16))
    SignExtend(I64, W8) => Some(SignExtend(I64, W8))
    SignExtend(I64, W16) => Some(SignExtend(I64, W16))
    SignExtend(I64, W32) => Some(SignExtend(I64, W32))
    F32DemoteF64 => Some(DemoteF64ToF32)
    F64PromoteF32 => Some(PromoteF32ToF64)
    Bitcast(from, to) => Some(Bitcast(from, to))
    IntToFloat(from, to, signedness) => Some(IntToFloat(from, to, signedness))
    FloatToInt(_, _, _, _) | SignExtend(_, _) => None
  }
}

///|
fn float_value_type(ty : @semantic.FloatType) -> @semantic.ValueType {
  match ty {
    F32 => F32
    F64 => F64
  }
}

///|
fn float_to_int_bounds(
  source : @semantic.FloatType,
  result : @semantic.IntegerType,
  signedness : @semantic.Signedness,
) -> (UInt64, UInt64, Bool) {
  match (source, result, signedness) {
    (F32, I32, Signed) => (0xCF000000UL, 0x4F000000UL, false)
    (F32, I32, Unsigned) => (0xBF800000UL, 0x4F800000UL, true)
    (F32, I64, Signed) => (0xDF000000UL, 0x5F000000UL, false)
    (F32, I64, Unsigned) => (0xBF800000UL, 0x5F800000UL, true)
    (F64, I32, Signed) => (0xC1E0000000200000UL, 0x41E0000000000000UL, true)
    (F64, I32, Unsigned) => (0xBFF0000000000000UL, 0x41F0000000000000UL, true)
    (F64, I64, Signed) => (0xC3E0000000000000UL, 0x43E0000000000000UL, false)
    (F64, I64, Unsigned) => (0xBFF0000000000000UL, 0x43F0000000000000UL, true)
  }
}

///|
fn map_value(
  function : @semantic.Function,
  values : Array[@vcode.Value?],
  value : @semantic.Value,
) -> @vcode.Value raise AArch64LowerError {
  let index = function.value_index(value).unwrap()
  match values[index] {
    Some(mapped) => mapped
    None => raise MissingMappedValue(value_index=index)
  }
}

///|
fn map_values(
  function : @semantic.Function,
  values : Array[@vcode.Value?],
  source : Array[@semantic.Value],
) -> Array[@vcode.Value] raise AArch64LowerError {
  source.map(value => map_value(function, values, value))
}

///|
fn append_body(
  builder : @vcode.Builder[AArch64Inst],
  block : @vcode.Block,
  instruction : AArch64Inst,
  inputs : Array[@vcode.Input],
  outputs : Array[@vcode.Output],
  metadata : @vcode.InstructionMetadata,
) -> Array[@vcode.Value] raise AArch64LowerError {
  let (_, results) = builder.append_body(
    block,
    instruction,
    inputs,
    outputs,
    [],
    metadata,
  ) catch {
    error => raise BuildFailure(cause=error)
  }
  results
}

///|
fn source_metadata(
  metadata : @semantic.InstructionMetadata,
  values : Array[@vcode.Value],
  semantics : @semantic.OperationSemantics,
  trap? : @semantic.TrapReason,
) -> @vcode.InstructionMetadata {
  let safepoint : @semantic.SafepointKind? = match
    (semantics.gc_safepoint, semantics.cancellation_safepoint) {
    (true, true) => Some(GcAndCancellation)
    (true, false) => Some(Gc)
    (false, true) => Some(Cancellation)
    (false, false) => None
  }
  match metadata.source {
    Some(source) =>
      @vcode.InstructionMetadata::new(
        source~,
        trap?,
        safepoint?,
        live_gc_roots=values,
        stack_map?=metadata.stack_map,
      )
    None =>
      @vcode.InstructionMetadata::new(
        trap?,
        safepoint?,
        live_gc_roots=values,
        stack_map?=metadata.stack_map,
      )
  }
}

///|
fn terminator_call_metadata(
  metadata : @semantic.TerminatorMetadata,
  semantics : @semantic.OperationSemantics,
) -> @vcode.InstructionMetadata {
  let safepoint : @semantic.SafepointKind? = match
    (semantics.gc_safepoint, semantics.cancellation_safepoint) {
    (true, true) => Some(GcAndCancellation)
    (true, false) => Some(Gc)
    (false, true) => Some(Cancellation)
    (false, false) => None
  }
  match metadata.source {
    Some(source) => @vcode.InstructionMetadata::new(source~, safepoint?)
    None => @vcode.InstructionMetadata::new(safepoint?)
  }
}

///|
fn terminator_trap_metadata(
  metadata : @semantic.TerminatorMetadata,
  reason : @semantic.TrapReason,
) -> @vcode.InstructionMetadata {
  match metadata.source {
    Some(source) => @vcode.InstructionMetadata::new(source~, trap=reason)
    None => @vcode.InstructionMetadata::new(trap=reason)
  }
}

///|
fn call_argument_inputs(
  operands : Array[@vcode.Value],
  locations : Array[CallArgumentLocation],
) -> Array[@vcode.Input] {
  operands.mapi((index, operand) => {
    let input = @vcode.Input::any_location(operand)
    match locations[index] {
      CallRegister(reg) if is_allocatable(reg) => input.with_preference(reg)
      CallRegister(_) | CallStack(_) => input
    }
  })
}

///|
fn abi_home_output(
  ty : @semantic.ValueType,
  incoming : @vcode.PhysicalReg,
) -> @vcode.Output {
  let output = @vcode.Output::any_location(ty)
  if is_allocatable(incoming) {
    output.with_preference(incoming)
  } else {
    output
  }
}

///|
fn lower_direct_platform_call(
  builder : @vcode.Builder[AArch64Inst],
  block : @vcode.Block,
  call : @semantic.SemanticCall,
  operands : Array[@vcode.Value],
  result_types : Array[@semantic.ValueType],
  metadata : @vcode.InstructionMetadata,
) -> Array[@vcode.Value] raise AArch64LowerError {
  if call.protocol != Platform {
    raise UnsupportedAbi(message="direct internal call ABI is not selected yet")
  }
  if result_types.length() > 1 {
    raise UnsupportedAbi(
      message="platform calls support at most one direct result",
    )
  }
  let target = match call.callee {
    External(symbol) => symbol
    _ =>
      raise UnsupportedAbi(
        message="platform calls require a direct external symbol",
      )
  }
  let result_registers = platform_result_registers(call.signature.results)
  let inputs = call_argument_inputs(
    operands,
    platform_call_layout(call.signature.params).arguments,
  )
  let outputs = Array::makei(result_types.length(), index => {
    abi_home_output(result_types[index], result_registers[index])
  })
  (builder.append_body(
    block,
    if call.behavior.returns_twice {
      ReturnsTwicePlatformCall(target, call.signature)
    } else {
      PlatformCall(target, call.signature)
    },
    inputs,
    [],
    platform_call_clobbers(),
    metadata,
  ) catch {
    error => raise BuildFailure(cause=error)
  })
  |> ignore
  let results : Array[@vcode.Value] = []
  for index, ty in result_types {
    let (_, materialized) = builder.append_body(
      block,
      IncomingCallResult(ty, result_registers[index]),
      [],
      [outputs[index]],
      [],
      @vcode.InstructionMetadata::empty(),
    ) catch {
      error => raise BuildFailure(cause=error)
    }
    results.push(materialized[0])
  }
  for root in metadata.live_gc_roots {
    (builder.append_body(
      block,
      KeepAlive(GcRef64),
      [@vcode.Input::any(root)],
      [],
      [],
      @vcode.InstructionMetadata::empty(),
    ) catch {
      error => raise BuildFailure(cause=error)
    })
    |> ignore
  }
  results
}

///|
fn lower_internal_call(
  context : LoweringContext,
  builder : @vcode.Builder[AArch64Inst],
  block : @vcode.Block,
  call : @semantic.SemanticCall,
  operands : Array[@vcode.Value],
  result_types : Array[@semantic.ValueType],
  metadata : @vcode.InstructionMetadata,
) -> Array[@vcode.Value] raise AArch64LowerError {
  if call.protocol != Internal {
    raise UnsupportedAbi(message="internal call requires the internal protocol")
  }
  if call.behavior.returns_twice {
    raise UnsupportedAbi(
      message="returns-twice internal calls are not supported",
    )
  }
  let target = match call.callee {
    Internal(symbol) => Some(symbol)
    Indirect => None
    External(_) =>
      raise UnsupportedAbi(
        message="internal calls require a code symbol or function pointer",
      )
  }
  let plan = context.internal_abi.call_plan(call.signature) catch {
    error => raise UnsupportedAbi(message=error.to_string())
  }
  let inputs = match target {
    Some(_) => call_argument_inputs(operands, plan.arguments)
    None =>
      [
        @vcode.Input::any_location(operands[0]),
        ..call_argument_inputs(operands[1:].to_owned(), plan.arguments),
      ]
  }
  (builder.append_body(
    block,
    match target {
      Some(target) => InternalCall(target, call.signature, plan)
      None => InternalCallIndirect(call.signature, plan)
    },
    inputs,
    [],
    platform_call_clobbers(),
    metadata,
  ) catch {
    error => raise BuildFailure(cause=error)
  })
  |> ignore
  let results : Array[@vcode.Value] = []
  for index, ty in result_types {
    let (operation, output) = match plan.results[index] {
      CallResultRegister(reg) =>
        (IncomingCallResult(ty, reg), abi_home_output(ty, reg))
      CallResultArea(offset, _) =>
        (IncomingCallAreaResult(ty, offset), @vcode.Output::any_location(ty))
    }
    let (_, materialized) = builder.append_body(
      block,
      operation,
      [],
      [output],
      [],
      @vcode.InstructionMetadata::empty(),
    ) catch {
      error => raise BuildFailure(cause=error)
    }
    results.push(materialized[0])
  }
  for root in metadata.live_gc_roots {
    (builder.append_body(
      block,
      KeepAlive(GcRef64),
      [@vcode.Input::any(root)],
      [],
      [],
      @vcode.InstructionMetadata::empty(),
    ) catch {
      error => raise BuildFailure(cause=error)
    })
    |> ignore
  }
  results
}

///|
priv struct ImmediateSelection {
  width : GprWidth
  operation : AArch64IntBinary
  bits : UInt64
  input : @semantic.Value
}

///|
priv struct MultiplyAddSelection {
  width : GprWidth
  accumulator : @semantic.Value
  left : @semantic.Value
  right : @semantic.Value
}

///|
priv struct ShiftImmediateSelection {
  width : GprWidth
  amount : Int
  input : @semantic.Value
  constant : @semantic.Value
}

///|
priv struct MemoryAddressSelection {
  base : @semantic.Value
  index : @semantic.Value
  shift : Int
  offset : UInt64
}

///|
priv struct EnvironmentReuseKey {
  field : @semantic.EnvironmentField
  context : @semantic.Value
} derive(Eq, Hash)

///|
priv struct EnvironmentReuseEntry {
  value : @semantic.Value
  definition_index : Int
}

///|
/// Bound reuse to nearby instructions so eliminating a context load does not
/// turn its result into a long-lived register-allocation constraint.
const ENVIRONMENT_REUSE_DISTANCE : Int = 8

///|
priv struct BranchSelection {
  width : GprWidth
  input : @semantic.Value
  other : @semantic.Value?
  immediate : UInt64?
  condition : AArch64Condition?
  swap_edges : Bool
}

///|
priv struct LoweringAnalysis {
  uses : Array[Int]
  immediates : Array[ImmediateSelection?]
  multiply_adds : Array[MultiplyAddSelection?]
  shift_immediates : Array[ShiftImmediateSelection?]
  memory_addresses : Array[MemoryAddressSelection?]
  environment_aliases : Array[@semantic.Value?]
  branches : Array[BranchSelection?]
  skip_results : Array[Bool]
}

///|
fn count_value_use(
  function : @semantic.Function,
  uses : Array[Int],
  value : @semantic.Value,
) -> Unit {
  uses[function.value_index(value).unwrap()] += 1
}

///|
fn foldable_definition(
  function : @semantic.Function,
  definitions : Array[@semantic.Instruction?],
  uses : Array[Int],
  value : @semantic.Value,
) -> @semantic.Instruction? {
  let index = function.value_index(value).unwrap()
  if uses[index] != 1 {
    return None
  }
  guard definitions[index] is Some(instruction) else { return None }
  let metadata = function.instruction_metadata(instruction).unwrap()
  if !metadata.live_gc_roots.is_empty() {
    return None
  }
  Some(instruction)
}

///|
fn reusable_definition(
  function : @semantic.Function,
  definitions : Array[@semantic.Instruction?],
  value : @semantic.Value,
) -> @semantic.Instruction? {
  let index = function.value_index(value).unwrap()
  guard definitions[index] is Some(instruction) else { return None }
  let metadata = function.instruction_metadata(instruction).unwrap()
  if !metadata.live_gc_roots.is_empty() {
    return None
  }
  Some(instruction)
}

///|
fn multiply_add_selection(
  function : @semantic.Function,
  definitions : Array[@semantic.Instruction?],
  uses : Array[Int],
  accumulator : @semantic.Value,
  product : @semantic.Value,
  width : GprWidth,
) -> MultiplyAddSelection? {
  guard foldable_definition(function, definitions, uses, product)
    is Some(instruction) else {
    return None
  }
  guard function.instruction_operation(instruction) is Some(IntBinary(Mul)) else {
    return None
  }
  guard function.instruction_operands(instruction) is [left, right] else {
    return None
  }
  Some({ width, accumulator, left, right })
}

///|
fn natural_register_shift(width : @semantic.AccessWidth) -> Int {
  match width {
    W8 => 0
    W16 => 1
    W32 => 2
    W64 => 3
    W128 => 4
  }
}

///|
fn select_scaled_index(
  function : @semantic.Function,
  definitions : Array[@semantic.Instruction?],
  uses : Array[Int],
  constants : Array[UInt64?],
  index : @semantic.Value,
  width : @semantic.AccessWidth,
) -> (@semantic.Value, Int, @semantic.Value?, @semantic.Value?) {
  let shift = natural_register_shift(width)
  if shift == 0 {
    return (index, 0, None, None)
  }
  guard foldable_definition(function, definitions, uses, index)
    is Some(instruction) else {
    return (index, 0, None, None)
  }
  guard function.instruction_operation(instruction) is Some(IntBinary(Mul)) else {
    return (index, 0, None, None)
  }
  guard function.instruction_operands(instruction) is [left, right] else {
    return (index, 0, None, None)
  }
  let scale = 1UL << shift
  if constants[function.value_index(right).unwrap()] == Some(scale) {
    (left, shift, Some(index), Some(right))
  } else if constants[function.value_index(left).unwrap()] == Some(scale) {
    (right, shift, Some(index), Some(left))
  } else {
    (index, 0, None, None)
  }
}

///|
fn uxtw_memory_address_selection(
  function : @semantic.Function,
  definitions : Array[@semantic.Instruction?],
  uses : Array[Int],
  constants : Array[UInt64?],
  address : @semantic.Value,
  width : @semantic.AccessWidth,
) -> (MemoryAddressSelection, Array[@semantic.Value], Array[@semantic.Value])? {
  guard foldable_definition(function, definitions, uses, address)
    is Some(offset_instruction) else {
    return None
  }
  guard function.instruction_operation(offset_instruction)
    is Some(PointerOffset) else {
    return None
  }
  guard function.instruction_operands(offset_instruction) is [pointer, zero] else {
    return None
  }
  if constants[function.value_index(zero).unwrap()] != Some(0UL) {
    return None
  }
  guard foldable_definition(function, definitions, uses, pointer)
    is Some(pointer_instruction) else {
    return None
  }
  guard function.instruction_operation(pointer_instruction)
    is Some(Convert(Bitcast(I64, Ptr64))) else {
    return None
  }
  guard function.instruction_operands(pointer_instruction) is [sum] else {
    return None
  }
  guard foldable_definition(function, definitions, uses, sum)
    is Some(add_instruction) else {
    return None
  }
  guard function.instruction_operation(add_instruction) is Some(IntBinary(Add)) else {
    return None
  }
  guard function.instruction_operands(add_instruction) is [left, right] else {
    return None
  }
  let match_parts = fn(
    base_bits : @semantic.Value,
    index_bits : @semantic.Value,
  ) -> (
    @semantic.Value,
    @semantic.Value,
    UInt64,
    Array[@semantic.Value],
    Array[@semantic.Value],
  )? {
    guard reusable_definition(function, definitions, base_bits)
      is Some(base_instruction) else {
      return None
    }
    guard function.instruction_operation(base_instruction)
      is Some(Convert(Bitcast(Ptr64, I64))) else {
      return None
    }
    guard function.instruction_operands(base_instruction) is [base] else {
      return None
    }
    let match_extended_index = fn(
      extended : @semantic.Value,
    ) -> @semantic.Value? {
      let extended_index = function.value_index(extended).unwrap()
      guard definitions[extended_index] is Some(index_instruction) else {
        return None
      }
      guard function.instruction_metadata(index_instruction) is Some(metadata) &&
        metadata.live_gc_roots.is_empty() else {
        return None
      }
      guard function.instruction_operation(index_instruction)
        is Some(Convert(I64ExtendI32(Unsigned))) else {
        return None
      }
      guard function.instruction_operands(index_instruction) is [index] else {
        return None
      }
      Some(index)
    }
    if match_extended_index(index_bits) is Some(index) {
      return Some((base, index, 0UL, [], [base_bits, index_bits]))
    }
    guard foldable_definition(function, definitions, uses, index_bits)
      is Some(offset_instruction) else {
      return None
    }
    guard function.instruction_operation(offset_instruction)
      is Some(IntBinary(Add)) else {
      return None
    }
    guard function.instruction_operands(offset_instruction)
      is [offset_left, offset_right] else {
      return None
    }
    let extended_and_constant = match
      constants[function.value_index(offset_right).unwrap()] {
      Some(bits) => Some((offset_left, offset_right, bits))
      None =>
        match constants[function.value_index(offset_left).unwrap()] {
          Some(bits) => Some((offset_right, offset_left, bits))
          None => None
        }
    }
    guard extended_and_constant is Some((extended, _, offset)) else {
      return None
    }
    let scale = natural_register_shift(width)
    let byte_scale = 1UL << scale
    if offset % byte_scale != 0UL || offset / byte_scale > 4095UL {
      return None
    }
    if !valid_int_binary_immediate(W64, Add, offset) {
      return None
    }
    guard match_extended_index(extended) is Some(index) else { return None }
    Some((base, index, offset, [index_bits], [base_bits, extended]))
  }
  let parts = match match_parts(left, right) {
    Some(parts) => Some(parts)
    None => match_parts(right, left)
  }
  guard parts is Some((base, index, offset, extra_skipped, folded_constants)) else {
    return None
  }
  let (selected_index, shift, skipped_index, folded_constant) = select_scaled_index(
    function, definitions, uses, constants, index, width,
  )
  let skipped = [address, pointer, sum]
  for value in extra_skipped {
    skipped.push(value)
  }
  if skipped_index is Some(value) {
    skipped.push(value)
  }
  if folded_constant is Some(value) {
    folded_constants.push(value)
  }
  Some(
    ({ base, index: selected_index, shift, offset }, skipped, folded_constants),
  )
}

///|
fn analyze_lowering(function : @semantic.Function) -> LoweringAnalysis {
  let value_count = function.value_count()
  let constants : Array[UInt64?] = Array::make(value_count, None)
  let definitions : Array[@semantic.Instruction?] = Array::make(
    value_count,
    None,
  )
  let uses = Array::make(value_count, 0)
  let folded_uses = Array::make(value_count, 0)
  let immediates : Array[ImmediateSelection?] = Array::make(value_count, None)
  let multiply_adds : Array[MultiplyAddSelection?] = Array::make(
    value_count,
    None,
  )
  let shift_immediates : Array[ShiftImmediateSelection?] = Array::make(
    value_count,
    None,
  )
  let mut instruction_slots = 0
  for block in function.blocks() {
    for instruction in function.block_instructions(block) {
      let slot = function.instruction_index(instruction).unwrap() + 1
      if slot > instruction_slots {
        instruction_slots = slot
      }
    }
  }
  let memory_addresses : Array[MemoryAddressSelection?] = Array::make(
    instruction_slots,
    None,
  )
  let environment_aliases : Array[@semantic.Value?] = Array::make(
    value_count,
    None,
  )
  let branches : Array[BranchSelection?] = Array::make(
    function.block_count(),
    None,
  )
  let skip_results = Array::make(value_count, false)
  for block in function.blocks() {
    for instruction in function.block_instructions(block) {
      let results = function.instruction_results(instruction)
      for result in results {
        definitions[function.value_index(result).unwrap()] = Some(instruction)
      }
      match (function.instruction_operation(instruction), results.get(0)) {
        (Some(I32Const(bits)), Some(result)) =>
          constants[function.value_index(result).unwrap()] = Some(
            bits.to_uint64(),
          )
        (Some(I64Const(bits)), Some(result)) =>
          constants[function.value_index(result).unwrap()] = Some(bits)
        _ => ()
      }
      for operand in function.instruction_operands(instruction) {
        count_value_use(function, uses, operand)
      }
    }
    let record = function.block_terminator(block).unwrap()
    match record.kind {
      Jump(edge) =>
        for argument in edge.arguments {
          count_value_use(function, uses, argument)
        }
      Branch(condition, when_true, when_false) => {
        count_value_use(function, uses, condition)
        for argument in when_true.arguments {
          count_value_use(function, uses, argument)
        }
        for argument in when_false.arguments {
          count_value_use(function, uses, argument)
        }
      }
      Switch(index, cases, default_edge) => {
        count_value_use(function, uses, index)
        for case in cases {
          for argument in case.edge.arguments {
            count_value_use(function, uses, argument)
          }
        }
        for argument in default_edge.arguments {
          count_value_use(function, uses, argument)
        }
      }
      Return(values) | TailCall(_, values) | NoReturnCall(_, values) =>
        for value in values {
          count_value_use(function, uses, value)
        }
      Trap(_) => ()
    }
  }
  for block in function.blocks() {
    let available : Map[EnvironmentReuseKey, EnvironmentReuseEntry] = Map([])
    let mut definition_index = 0
    for instruction in function.block_instructions(block) {
      let operation = function.instruction_operation(instruction).unwrap()
      if operation is Call(_) {
        available.clear()
      }
      if operation is EnvironmentField(field, Stable) &&
        function.instruction_operands(instruction) is [context] &&
        function.instruction_results(instruction) is [result] {
        let key = { field, context }
        match available.get(key) {
          Some(entry) if definition_index - entry.definition_index <=
            ENVIRONMENT_REUSE_DISTANCE =>
            environment_aliases[function.value_index(result).unwrap()] = Some(
              entry.value,
            )
          _ => available.set(key, { value: result, definition_index })
        }
      }
      definition_index += 1
    }
  }
  for block in function.blocks() {
    for instruction in function.block_instructions(block) {
      let operation = function.instruction_operation(instruction).unwrap()
      let results = function.instruction_results(instruction)
      if operation is IntBinary(Add) &&
        results is [result] &&
        optional_gpr_width(function.value_type(result)) is Some(width) &&
        function.instruction_operands(instruction) is [left, right] {
        let selected = match
          multiply_add_selection(
            function, definitions, uses, left, right, width,
          ) {
          Some(selected) => Some((selected, right))
          None =>
            match
              multiply_add_selection(
                function, definitions, uses, right, left, width,
              ) {
              Some(selected) => Some((selected, left))
              None => None
            }
        }
        if selected is Some((selected, product)) {
          multiply_adds[function.value_index(result).unwrap()] = Some(selected)
          let product_index = function.value_index(product).unwrap()
          skip_results[product_index] = true
          if shift_immediates[product_index] is Some(selected_shift) {
            folded_uses[function.value_index(selected_shift.constant).unwrap()] -= 1
            shift_immediates[product_index] = None
          }
        }
      }
      match operation {
        Load(spec) if spec.endianness == Little &&
          spec.offset == 0UL &&
          spec.width != W128 => {
          guard function.instruction_operands(instruction) is [address] else {
            continue
          }
          if uxtw_memory_address_selection(
              function,
              definitions,
              uses,
              constants,
              address,
              spec.width,
            )
            is Some((selection, skipped, folded_constants)) {
            memory_addresses[function.instruction_index(instruction).unwrap()] = Some(
              selection,
            )
            for value in skipped {
              let value_index = function.value_index(value).unwrap()
              skip_results[value_index] = true
              if shift_immediates[value_index] is Some(selected_shift) {
                folded_uses[function
                .value_index(selected_shift.constant)
                .unwrap()] -= 1
                shift_immediates[value_index] = None
              }
            }
            for value in folded_constants {
              folded_uses[function.value_index(value).unwrap()] += 1
            }
            folded_uses[function
            .value_index(
              function.instruction_operands(
                definitions[function.value_index(address).unwrap()].unwrap(),
              )[1],
            )
            .unwrap()] += 1
          }
        }
        Store(spec) if spec.endianness == Little &&
          spec.offset == 0UL &&
          spec.width != W128 => {
          guard function.instruction_operands(instruction) is [address, _] else {
            continue
          }
          if uxtw_memory_address_selection(
              function,
              definitions,
              uses,
              constants,
              address,
              spec.width,
            )
            is Some((selection, skipped, folded_constants)) {
            memory_addresses[function.instruction_index(instruction).unwrap()] = Some(
              selection,
            )
            for value in skipped {
              let value_index = function.value_index(value).unwrap()
              skip_results[value_index] = true
              if shift_immediates[value_index] is Some(selected_shift) {
                folded_uses[function
                .value_index(selected_shift.constant)
                .unwrap()] -= 1
                shift_immediates[value_index] = None
              }
            }
            for value in folded_constants {
              folded_uses[function.value_index(value).unwrap()] += 1
            }
            folded_uses[function
            .value_index(
              function.instruction_operands(
                definitions[function.value_index(address).unwrap()].unwrap(),
              )[1],
            )
            .unwrap()] += 1
          }
        }
        _ => ()
      }
      guard operation is IntBinary(binary) else { continue }
      let binary_operation = match lower_binary(binary) {
        Some(operation) => operation
        None if binary == UnsignedRem => And
        None => continue
      }
      guard results is [result] else { continue }
      if multiply_adds[function.value_index(result).unwrap()] is Some(_) {
        continue
      }
      guard optional_gpr_width(function.value_type(result)) is Some(width) else {
        continue
      }
      guard function.instruction_operands(instruction) is [left, right] else {
        continue
      }
      if binary == Mul && !skip_results[function.value_index(result).unwrap()] {
        let selected : (@semantic.Value, @semantic.Value, UInt64)? = match
          constants[function.value_index(right).unwrap()] {
          Some(bits) => Some((left, right, bits))
          None =>
            match constants[function.value_index(left).unwrap()] {
              Some(bits) => Some((right, left, bits))
              None => None
            }
        }
        if selected is Some((input, constant, bits)) &&
          bits != 0UL &&
          (bits & (bits - 1UL)) == 0UL {
          let amount = bits.ctz()
          let bit_width = if width == W32 { 32 } else { 64 }
          if amount < bit_width {
            shift_immediates[function.value_index(result).unwrap()] = Some({
              width,
              amount,
              input,
              constant,
            })
            folded_uses[function.value_index(constant).unwrap()] += 1
          }
        }
      }
      let selected : (UInt64, @semantic.Value, @semantic.Value)? = match
        constants[function.value_index(right).unwrap()] {
        Some(bits) if binary == UnsignedRem &&
          bits > 1UL &&
          (bits & (bits - 1UL)) == 0UL &&
          valid_int_binary_immediate(width, And, bits - 1UL) =>
          Some((bits - 1UL, left, right))
        Some(bits) if binary is (Add | Sub | And | Or | Xor) &&
          valid_int_binary_immediate(width, binary_operation, bits) =>
          Some((bits, left, right))
        _ =>
          match constants[function.value_index(left).unwrap()] {
            Some(bits) if binary is (Add | And | Or | Xor) &&
              valid_int_binary_immediate(width, binary_operation, bits) =>
              Some((bits, right, left))
            _ => None
          }
      }
      if selected is Some((bits, input, constant)) {
        immediates[function.value_index(result).unwrap()] = Some({
          width,
          operation: binary_operation,
          bits,
          input,
        })
        folded_uses[function.value_index(constant).unwrap()] += 1
      }
    }
    guard function.block_terminator(block).unwrap().kind
      is Branch(condition, _, _) else {
      continue
    }
    let condition_index = function.value_index(condition).unwrap()
    if uses[condition_index] != 1 {
      continue
    }
    guard definitions[condition_index] is Some(instruction) else { continue }
    guard function.instruction_operation(instruction)
      is Some(IntCompare(comparison)) else {
      continue
    }
    guard function.instruction_operands(instruction) is [left, right] else {
      continue
    }
    guard optional_gpr_width(function.value_type(left)) is Some(width) else {
      continue
    }
    skip_results[condition_index] = true
    let zero_selected : (@semantic.Value, @semantic.Value)? = if comparison
      is (Equal | NotEqual) &&
      constants[function.value_index(right).unwrap()] == Some(0UL) {
      Some((left, right))
    } else if comparison is (Equal | NotEqual) &&
      constants[function.value_index(left).unwrap()] == Some(0UL) {
      Some((right, left))
    } else {
      None
    }
    match zero_selected {
      Some((input, zero)) => {
        branches[function.block_index(block).unwrap()] = Some({
          width,
          input,
          other: None,
          immediate: None,
          condition: None,
          swap_edges: comparison == Equal,
        })
        folded_uses[function.value_index(zero).unwrap()] += 1
      }
      None => {
        let lowered_condition = lower_condition(comparison)
        let immediate_selected : (
          @semantic.Value,
          @semantic.Value,
          UInt64,
          AArch64Condition,
        )? = match constants[function.value_index(right).unwrap()] {
          Some(bits) if add_sub_immediate_shift(bits) is Some(_) =>
            Some((left, right, bits, lowered_condition))
          _ =>
            match constants[function.value_index(left).unwrap()] {
              Some(bits) if add_sub_immediate_shift(bits) is Some(_) =>
                Some((right, left, bits, swapped_condition(lowered_condition)))
              _ => None
            }
        }
        match immediate_selected {
          Some((input, constant, bits, condition)) => {
            branches[function.block_index(block).unwrap()] = Some({
              width,
              input,
              other: None,
              immediate: Some(bits),
              condition: Some(condition),
              swap_edges: false,
            })
            folded_uses[function.value_index(constant).unwrap()] += 1
          }
          None =>
            branches[function.block_index(block).unwrap()] = Some({
              width,
              input: left,
              other: Some(right),
              immediate: None,
              condition: Some(lowered_condition),
              swap_edges: false,
            })
        }
      }
    }
  }
  for value_index in 0..<value_count {
    if uses[value_index] > 0 && folded_uses[value_index] == uses[value_index] {
      skip_results[value_index] = true
    }
  }
  {
    uses,
    immediates,
    multiply_adds,
    shift_immediates,
    memory_addresses,
    environment_aliases,
    branches,
    skip_results,
  }
}

///|
fn lower_instruction(
  function : @semantic.Function,
  context : LoweringContext,
  builder : @vcode.Builder[AArch64Inst],
  block : @vcode.Block,
  block_index : Int,
  instruction : @semantic.Instruction,
  values : Array[@vcode.Value?],
  analysis : LoweringAnalysis,
) -> Unit raise AArch64LowerError {
  let instruction_index = function.instruction_index(instruction).unwrap()
  let operation = function.instruction_operation(instruction).unwrap()
  let semantic_operands = function.instruction_operands(instruction)
  let semantic_results = function.instruction_results(instruction)
  let result_index = semantic_results
    .get(0)
    .map(result => function.value_index(result).unwrap())
  if result_index is Some(index) &&
    analysis.environment_aliases[index] is Some(alias_value) {
    values[index] = Some(map_value(function, values, alias_value))
    return
  }
  if result_index is Some(index) && analysis.skip_results[index] {
    return
  }
  let immediate = match result_index {
    Some(index) => analysis.immediates[index]
    None => None
  }
  let multiply_add = match result_index {
    Some(index) => analysis.multiply_adds[index]
    None => None
  }
  let shift_immediate = match result_index {
    Some(index) => analysis.shift_immediates[index]
    None => None
  }
  let memory_address = analysis.memory_addresses[instruction_index]
  let operands = match
    (multiply_add, shift_immediate, memory_address, immediate) {
    (Some(selected), _, _, _) =>
      map_values(function, values, [
        selected.accumulator,
        selected.left,
        selected.right,
      ])
    (_, Some(selected), _, _) => [map_value(function, values, selected.input)]
    (_, _, Some(selected), _) => {
      let selected_operands = [
        map_value(function, values, selected.base),
        map_value(function, values, selected.index),
      ]
      if operation is Store(_) {
        selected_operands.push(
          map_value(function, values, semantic_operands[1]),
        )
      }
      selected_operands
    }
    (_, _, _, Some(selected)) => [map_value(function, values, selected.input)]
    _ => map_values(function, values, semantic_operands)
  }
  let result_types = semantic_results.map(value => {
    function.value_type(value).unwrap()
  })
  let roots = map_values(
    function,
    values,
    function.instruction_metadata(instruction).unwrap().live_gc_roots,
  )
  if multiply_add is Some(selected) {
    let results = append_body(
      builder,
      block,
      IntMultiplyAdd(selected.width),
      operands.map(@vcode.Input::any),
      result_types.map(@vcode.Output::any),
      source_metadata(
        function.instruction_metadata(instruction).unwrap(),
        roots,
        operation.semantics(),
      ),
    )
    for index, result in semantic_results {
      values[function.value_index(result).unwrap()] = Some(results[index])
    }
    return
  }
  if shift_immediate is Some(selected) {
    let results = append_body(
      builder,
      block,
      IntShiftLeftImmediate(selected.width, selected.amount),
      operands.map(@vcode.Input::any),
      result_types.map(@vcode.Output::any),
      source_metadata(
        function.instruction_metadata(instruction).unwrap(),
        roots,
        operation.semantics(),
      ),
    )
    for index, result in semantic_results {
      values[function.value_index(result).unwrap()] = Some(results[index])
    }
    return
  }
  if memory_address is Some(selected) {
    if selected.offset != 0UL {
      let address = append_body(
          builder,
          block,
          AddAddressUxtw(selected.shift),
          [@vcode.Input::any(operands[0]), @vcode.Input::any(operands[1])],
          [@vcode.Output::any(Ptr64)],
          @vcode.InstructionMetadata::empty(),
        )[0]
      let selected_operands = [address]
      if operation is Store(_) {
        selected_operands.push(operands[2])
      }
      let selected_operation = match operation {
        Load(spec) =>
          ScalarLoad(
            spec.width,
            spec.extension,
            spec.result_type,
            selected.offset,
          )
        Store(spec) => ScalarStore(spec.width, spec.value_type, selected.offset)
        _ => abort("register-offset selection requires scalar memory operation")
      }
      let results = append_body(
        builder,
        block,
        selected_operation,
        selected_operands.map(@vcode.Input::any),
        result_types.map(@vcode.Output::any),
        source_metadata(
          function.instruction_metadata(instruction).unwrap(),
          roots,
          operation.semantics(),
        ),
      )
      for index, result in semantic_results {
        values[function.value_index(result).unwrap()] = Some(results[index])
      }
      return
    }
    let selected_operation = match operation {
      Load(spec) =>
        ScalarLoadUxtw(
          spec.width,
          spec.extension,
          spec.result_type,
          selected.shift,
        )
      Store(spec) =>
        ScalarStoreUxtw(spec.width, spec.value_type, selected.shift)
      _ => abort("register-offset selection requires scalar memory operation")
    }
    let results = append_body(
      builder,
      block,
      selected_operation,
      operands.map(@vcode.Input::any),
      result_types.map(@vcode.Output::any),
      source_metadata(
        function.instruction_metadata(instruction).unwrap(),
        roots,
        operation.semantics(),
      ),
    )
    for index, result in semantic_results {
      values[function.value_index(result).unwrap()] = Some(results[index])
    }
    return
  }
  if immediate is Some(selected) {
    let results = append_body(
      builder,
      block,
      IntBinaryImmediate(selected.width, selected.operation, selected.bits),
      operands.map(@vcode.Input::any),
      result_types.map(@vcode.Output::any),
      source_metadata(
        function.instruction_metadata(instruction).unwrap(),
        roots,
        operation.semantics(),
      ),
    )
    for index, result in semantic_results {
      values[function.value_index(result).unwrap()] = Some(results[index])
    }
    return
  }
  if operation is Call(call) {
    let metadata = source_metadata(
      function.instruction_metadata(instruction).unwrap(),
      roots,
      operation.semantics(),
    )
    let results = match call.protocol {
      Platform =>
        lower_direct_platform_call(
          builder, block, call, operands, result_types, metadata,
        )
      Internal =>
        lower_internal_call(
          context, builder, block, call, operands, result_types, metadata,
        )
    }
    for index, result in semantic_results {
      values[function.value_index(result).unwrap()] = Some(results[index])
    }
    return
  }
  if operation is IntBinary(binary) &&
    binary is (SignedDiv | UnsignedDiv | SignedRem | UnsignedRem) {
    guard optional_gpr_width(result_types.get(0)) is Some(width) else {
      raise UnsupportedOperation(block_index~, instruction_index~, operation~)
    }
    let semantic_metadata = function.instruction_metadata(instruction).unwrap()
    append_body(
      builder,
      block,
      TrapIfZero(width),
      [@vcode.Input::any(operands[1])],
      [],
      source_metadata(
        semantic_metadata,
        roots,
        operation.semantics(),
        trap=IntegerDivisionByZero,
      ),
    )
    |> ignore
    if binary == SignedDiv {
      append_body(
        builder,
        block,
        TrapIfSignedDivOverflow(width),
        operands.map(@vcode.Input::any),
        [],
        source_metadata(
          semantic_metadata,
          roots,
          operation.semantics(),
          trap=IntegerOverflow,
        ),
      )
      |> ignore
    }
    let selected = match binary {
      SignedDiv => IntBinary(width, Sdiv)
      UnsignedDiv => IntBinary(width, Udiv)
      SignedRem => IntRemainder(width, Signed)
      UnsignedRem => IntRemainder(width, Unsigned)
      _ => abort("matched checked integer arithmetic above")
    }
    let results = append_body(
      builder,
      block,
      selected,
      operands.map(@vcode.Input::any),
      result_types.map(@vcode.Output::any),
      source_metadata(semantic_metadata, roots, operation.semantics()),
    )
    for index, result in semantic_results {
      values[function.value_index(result).unwrap()] = Some(results[index])
    }
    return
  }
  if operation is Convert(FloatToInt(source, result, signedness, mode)) {
    let source_type = float_value_type(source)
    let semantic_metadata = function.instruction_metadata(instruction).unwrap()
    if mode == Trapping {
      append_body(
        builder,
        block,
        TrapIfFloat(source_type, Unordered),
        [@vcode.Input::any(operands[0])],
        [],
        source_metadata(
          semantic_metadata,
          roots,
          operation.semantics(),
          trap=InvalidConversionToInteger,
        ),
      )
      |> ignore
      let (minimum_bits, maximum_bits, inclusive_minimum) = float_to_int_bounds(
        source, result, signedness,
      )
      let minimum = append_body(
          builder,
          block,
          LoadFloatConstant(source_type, minimum_bits),
          [],
          [@vcode.Output::any(source_type)],
          @vcode.InstructionMetadata::empty(),
        )[0]
      let lower_condition : AArch64FloatTrapCondition = if inclusive_minimum {
        LessOrEqual
      } else {
        LessThan
      }
      append_body(
        builder,
        block,
        TrapIfFloat(source_type, lower_condition),
        [@vcode.Input::any(operands[0]), @vcode.Input::any(minimum)],
        [],
        source_metadata(
          semantic_metadata,
          roots,
          operation.semantics(),
          trap=InvalidConversionToInteger,
        ),
      )
      |> ignore
      let maximum = append_body(
          builder,
          block,
          LoadFloatConstant(source_type, maximum_bits),
          [],
          [@vcode.Output::any(source_type)],
          @vcode.InstructionMetadata::empty(),
        )[0]
      append_body(
        builder,
        block,
        TrapIfFloat(source_type, GreaterOrEqual),
        [@vcode.Input::any(operands[0]), @vcode.Input::any(maximum)],
        [],
        source_metadata(
          semantic_metadata,
          roots,
          operation.semantics(),
          trap=InvalidConversionToInteger,
        ),
      )
      |> ignore
    }
    let results = append_body(
      builder,
      block,
      Convert(FloatToInt(source, result, signedness)),
      operands.map(@vcode.Input::any),
      result_types.map(@vcode.Output::any),
      source_metadata(semantic_metadata, roots, operation.semantics()),
    )
    for index, semantic_result in semantic_results {
      values[function.value_index(semantic_result).unwrap()] = Some(
        results[index],
      )
    }
    return
  }
  if operation is IntUnary(CountTrailingZeros) {
    guard optional_gpr_width(result_types.get(0)) is Some(width) else {
      raise UnsupportedOperation(block_index~, instruction_index~, operation~)
    }
    let reversed = append_body(
        builder,
        block,
        IntUnary(width, Rbit),
        operands.map(@vcode.Input::any),
        result_types.map(@vcode.Output::any),
        @vcode.InstructionMetadata::empty(),
      )[0]
    let results = append_body(
      builder,
      block,
      IntUnary(width, Clz),
      [@vcode.Input::any(reversed)],
      result_types.map(@vcode.Output::any),
      source_metadata(
        function.instruction_metadata(instruction).unwrap(),
        roots,
        operation.semantics(),
      ),
    )
    for index, semantic_result in semantic_results {
      values[function.value_index(semantic_result).unwrap()] = Some(
        results[index],
      )
    }
    return
  }
  if operation is IntBinary(RotateLeft) {
    guard optional_gpr_width(result_types.get(0)) is Some(width) else {
      raise UnsupportedOperation(block_index~, instruction_index~, operation~)
    }
    let negated_shift = append_body(
        builder,
        block,
        IntUnary(width, Neg),
        [@vcode.Input::any(operands[1])],
        result_types.map(@vcode.Output::any),
        @vcode.InstructionMetadata::empty(),
      )[0]
    let results = append_body(
      builder,
      block,
      IntBinary(width, Ror),
      [@vcode.Input::any(operands[0]), @vcode.Input::any(negated_shift)],
      result_types.map(@vcode.Output::any),
      source_metadata(
        function.instruction_metadata(instruction).unwrap(),
        roots,
        operation.semantics(),
      ),
    )
    for index, semantic_result in semantic_results {
      values[function.value_index(semantic_result).unwrap()] = Some(
        results[index],
      )
    }
    return
  }
  if operation is EnvironmentField(field, _) {
    let offsets = match context.environment_field_offsets(field) {
      Some(offsets) if !offsets.is_empty() => offsets
      _ =>
        raise UnsupportedAbi(
          message="embedding did not bind environment field '{field.name}'",
        )
    }
    let mut current = operands[0]
    for index, offset in offsets {
      if offset < 0 {
        raise UnsupportedAbi(
          message="environment field '{field.name}' has a negative offset",
        )
      }
      let last = index == offsets.length() - 1
      let ty = if last { result_types[0] } else { Ptr64 }
      guard scalar_access_width(ty) is Some(width) else {
        raise UnsupportedOperation(block_index~, instruction_index~, operation~)
      }
      current = append_body(
          builder,
          block,
          ScalarLoad(width, None, ty, offset.to_uint64()),
          [@vcode.Input::any(current)],
          [@vcode.Output::any(ty)],
          if last {
            source_metadata(
              function.instruction_metadata(instruction).unwrap(),
              roots,
              operation.semantics(),
            )
          } else {
            @vcode.InstructionMetadata::empty()
          },
        )[0]
    }
    values[function.value_index(semantic_results[0]).unwrap()] = Some(current)
    return
  }
  if operation is Vector(ReplaceLane(lane, index)) {
    let results = append_body(
      builder,
      block,
      VectorReplaceLane(lane, index),
      operands.map(@vcode.Input::any),
      [@vcode.Output::tied(V128, 0)],
      source_metadata(
        function.instruction_metadata(instruction).unwrap(),
        roots,
        operation.semantics(),
      ),
    )
    values[function.value_index(semantic_results[0]).unwrap()] = Some(
      results[0],
    )
    return
  }
  if operation is Vector(Relaxed(Dot8To32AddSigned)) {
    let low_products = append_body(
        builder,
        block,
        VectorIntBinary(I16x8, ExtendMultiply(Low, Signed)),
        [@vcode.Input::any(operands[0]), @vcode.Input::any(operands[1])],
        [@vcode.Output::any(V128)],
        @vcode.InstructionMetadata::empty(),
      )[0]
    let high_products = append_body(
        builder,
        block,
        VectorIntBinary(I16x8, ExtendMultiply(High, Signed)),
        [@vcode.Input::any(operands[0]), @vcode.Input::any(operands[1])],
        [@vcode.Output::any(V128)],
        @vcode.InstructionMetadata::empty(),
      )[0]
    let paired_products = append_body(
        builder,
        block,
        VectorPairwiseAddI16x8,
        [@vcode.Input::any(low_products), @vcode.Input::any(high_products)],
        [@vcode.Output::any(V128)],
        @vcode.InstructionMetadata::empty(),
      )[0]
    let dot_products = append_body(
        builder,
        block,
        VectorIntUnary(I32x4, ExtendAddPairwise(Signed)),
        [@vcode.Input::any(paired_products)],
        [@vcode.Output::any(V128)],
        @vcode.InstructionMetadata::empty(),
      )[0]
    let result = append_body(
        builder,
        block,
        VectorIntBinary(I32x4, Add),
        [@vcode.Input::any(dot_products), @vcode.Input::any(operands[2])],
        [@vcode.Output::any(V128)],
        source_metadata(
          function.instruction_metadata(instruction).unwrap(),
          roots,
          operation.semantics(),
        ),
      )[0]
    values[function.value_index(semantic_results[0]).unwrap()] = Some(result)
    return
  }
  let selected = match operation {
    I32Const(bits) => Some(LoadConstant(W32, bits.to_uint64()))
    I64Const(bits) => Some(LoadConstant(W64, bits))
    V128Const(low, high) => Some(LoadVectorConstant(low, high))
    NullPtr => Some(LoadNull(Ptr64))
    NullGcRef => Some(LoadNull(GcRef64))
    CodeAddress(symbol) => Some(LoadAddress(Code(symbol)))
    ExternalAddress(symbol) => Some(LoadAddress(External(symbol)))
    DataAddress(symbol) => Some(LoadAddress(Data(symbol)))
    StackAddress(object) =>
      Some(StackAddress(lower_stack_object(function, object)))
    F32Const(bits) => Some(LoadFloatConstant(F32, bits.to_uint64()))
    F64Const(bits) => Some(LoadFloatConstant(F64, bits))
    Copy if result_types.length() == 1 => Some(Move(result_types[0]))
    GcRefAddress => Some(CarrierMove(GcRef64, Ptr64))
    GcRefFromBits => Some(CarrierMove(I64, GcRef64))
    Select if result_types.get(0) is Some(V128) => Some(VectorSelect)
    Select if result_types.get(0) is Some(ty) => Some(Select(ty))
    Vector(Splat(lane)) => Some(VectorSplat(lane))
    Vector(ExtractLane(lane, index, extension)) =>
      Some(VectorExtractLane(lane, index, extension))
    Vector(Shuffle(mask)) => Some(VectorShuffle(mask))
    Vector(Swizzle) => Some(VectorSwizzle)
    Vector(Bitwise(operation)) => Some(VectorBitwise(operation))
    Vector(IntUnary(lane, Absolute)) => Some(VectorIntUnary(lane, Absolute))
    Vector(IntUnary(lane, Negate)) => Some(VectorIntUnary(lane, Negate))
    Vector(IntUnary(lane, PopulationCount)) =>
      Some(VectorIntUnary(lane, PopulationCount))
    Vector(IntUnary(lane, ExtendAddPairwise(signedness))) =>
      Some(VectorIntUnary(lane, ExtendAddPairwise(signedness)))
    Vector(IntBinary(lane, Add)) => Some(VectorIntBinary(lane, Add))
    Vector(IntBinary(lane, Sub)) => Some(VectorIntBinary(lane, Sub))
    Vector(IntBinary(lane, Mul)) => Some(VectorIntBinary(lane, Mul))
    Vector(IntBinary(lane, AverageUnsigned)) =>
      Some(VectorIntBinary(lane, AverageUnsigned))
    Vector(IntBinary(lane, Min(signedness))) =>
      Some(VectorIntBinary(lane, Min(signedness)))
    Vector(IntBinary(lane, Max(signedness))) =>
      Some(VectorIntBinary(lane, Max(signedness)))
    Vector(IntBinary(lane, SaturatingAdd(signedness))) =>
      Some(VectorIntBinary(lane, SaturatingAdd(signedness)))
    Vector(IntBinary(lane, SaturatingSub(signedness))) =>
      Some(VectorIntBinary(lane, SaturatingSub(signedness)))
    Vector(IntBinary(lane, ExtendMultiply(half, signedness))) =>
      Some(VectorIntBinary(lane, ExtendMultiply(half, signedness)))
    Vector(IntBinary(lane, Dot16To32Signed)) =>
      Some(VectorIntBinary(lane, Dot16To32Signed))
    Vector(IntBinary(lane, Q15MultiplyRoundedSaturating)) =>
      Some(VectorIntBinary(lane, Q15MultiplyRoundedSaturating))
    Vector(IntShift(lane, operation)) => Some(VectorIntShift(lane, operation))
    Vector(IntCompare(lane, comparison)) =>
      Some(VectorIntCompare(lane, comparison))
    Vector(Convert(ExtendLow(lane, signedness))) =>
      Some(VectorConvert(ExtendLow(lane, signedness)))
    Vector(Convert(ExtendHigh(lane, signedness))) =>
      Some(VectorConvert(ExtendHigh(lane, signedness)))
    Vector(Convert(Narrow(lane, signedness))) =>
      Some(VectorConvert(Narrow(lane, signedness)))
    Vector(Convert(FloatToInt(source, I32x4, signedness, Saturating))) =>
      Some(VectorConvert(FloatToInt(source, signedness)))
    Vector(Convert(IntToFloat(I32x4, result, signedness))) =>
      Some(VectorConvert(IntToFloat(result, signedness)))
    Vector(Convert(PromoteLowF32x4)) => Some(VectorConvert(PromoteLowF32x4))
    Vector(Convert(DemoteZeroF64x2)) => Some(VectorConvert(DemoteZeroF64x2))
    Vector(Predicate(AnyTrue)) => Some(VectorPredicate(AnyTrue))
    Vector(Predicate(AllTrue(lane))) => Some(VectorPredicate(AllTrue(lane)))
    Vector(Predicate(BitMask(lane))) => Some(VectorPredicate(BitMask(lane)))
    Vector(FloatUnary(lane, operation)) =>
      Some(VectorFloatUnary(lane, operation))
    Vector(FloatBinary(lane, operation)) =>
      Some(VectorFloatBinary(lane, operation))
    Vector(FloatTernary(lane, operation)) =>
      Some(VectorFloatTernary(lane, operation))
    Vector(FloatCompare(lane, comparison)) =>
      Some(VectorFloatCompare(lane, comparison))
    Vector(Relaxed(FusedMultiplyAdd(lane, operation))) =>
      Some(VectorFloatTernary(lane, operation))
    Vector(Relaxed(FloatToInt(source, I32x4, signedness))) =>
      Some(VectorConvert(FloatToInt(source, signedness)))
    Vector(Relaxed(Swizzle)) => Some(VectorSwizzle)
    Vector(Relaxed(LaneSelect(_))) => Some(VectorBitwise(BitSelect))
    Vector(Relaxed(Min(lane))) => Some(VectorFloatBinary(lane, Min))
    Vector(Relaxed(Max(lane))) => Some(VectorFloatBinary(lane, Max))
    Vector(Relaxed(Q15MultiplyRoundedSigned)) =>
      Some(VectorIntBinary(I16x8, Q15MultiplyRoundedSaturating))
    Vector(Relaxed(Dot8To16Signed)) => Some(VectorRelaxedDot8To16)
    ReferenceCompare(comparison) => {
      let operand_type = match semantic_operands.get(0) {
        Some(value) => function.value_type(value)
        None => None
      }
      match operand_type {
        Some(Ptr64) =>
          Some(
            ReferenceCompareSet(Ptr64, lower_reference_condition(comparison)),
          )
        Some(GcRef64) =>
          Some(
            ReferenceCompareSet(GcRef64, lower_reference_condition(comparison)),
          )
        _ => None
      }
    }
    IntUnary(Not) =>
      match optional_gpr_width(result_types.get(0)) {
        Some(width) => Some(IntUnary(width, Mvn))
        None => None
      }
    IntUnary(CountLeadingZeros) =>
      match optional_gpr_width(result_types.get(0)) {
        Some(width) => Some(IntUnary(width, Clz))
        None => None
      }
    IntUnary(PopulationCount) =>
      match optional_gpr_width(result_types.get(0)) {
        Some(width) => Some(PopulationCount(width))
        None => None
      }
    IntBinary(binary) =>
      match (optional_gpr_width(result_types.get(0)), lower_binary(binary)) {
        (Some(width), Some(binary)) => Some(IntBinary(width, binary))
        _ => None
      }
    IntCompare(comparison) => {
      let operand_type = match semantic_operands.get(0) {
        Some(value) => function.value_type(value)
        None => None
      }
      match optional_gpr_width(operand_type) {
        Some(width) => Some(CompareSet(width, lower_condition(comparison)))
        None => None
      }
    }
    IntHighMultiply(signedness) =>
      match optional_gpr_width(result_types.get(0)) {
        Some(width) => Some(IntHighMultiply(width, signedness))
        None => None
      }
    IntWithOverflow(operation) =>
      match optional_gpr_width(result_types.get(0)) {
        Some(width) => Some(IntWithOverflow(width, operation))
        None => None
      }
    FloatUnary(unary) =>
      match (result_types.get(0), lower_float_unary(unary)) {
        (Some(F32), Some(unary)) => Some(FloatUnary(F32, unary))
        (Some(F64), Some(unary)) => Some(FloatUnary(F64, unary))
        _ => None
      }
    FloatBinary(binary) =>
      match (result_types.get(0), lower_float_binary(binary)) {
        (Some(F32), Some(binary)) => Some(FloatBinary(F32, binary))
        (Some(F64), Some(binary)) => Some(FloatBinary(F64, binary))
        _ => None
      }
    FloatTernary(ternary) =>
      match result_types.get(0) {
        Some(F32) => Some(FloatTernary(F32, lower_float_ternary(ternary)))
        Some(F64) => Some(FloatTernary(F64, lower_float_ternary(ternary)))
        _ => None
      }
    FloatCompare(comparison) => {
      let operand_type = match semantic_operands.get(0) {
        Some(value) => function.value_type(value)
        None => None
      }
      match (operand_type, lower_float_condition(comparison)) {
        (Some(F32), Some(condition)) => Some(FloatCompareSet(F32, condition))
        (Some(F64), Some(condition)) => Some(FloatCompareSet(F64, condition))
        _ => None
      }
    }
    Convert(conversion) =>
      match lower_conversion(conversion) {
        Some(conversion) => Some(Convert(conversion))
        None => None
      }
    PointerOffset => Some(AddAddress)
    Load(spec) if spec.endianness == Little && spec.width == W128 =>
      Some(VectorLoad128(spec.offset))
    Load(spec) if spec.endianness == Little =>
      Some(
        ScalarLoad(spec.width, spec.extension, spec.result_type, spec.offset),
      )
    Store(spec) if spec.endianness == Little && spec.width == W128 =>
      Some(VectorStore128(spec.offset))
    Store(spec) if spec.endianness == Little =>
      Some(ScalarStore(spec.width, spec.value_type, spec.offset))
    VectorLoad(spec) if spec.endianness == Little =>
      match spec.kind {
        Splat(lane) => Some(VectorLoadSplat(lane, spec.offset))
        Extend(lane, signedness) =>
          Some(VectorLoadExtend(lane, signedness, spec.offset))
        Zero(width) => Some(VectorLoadZero(width, spec.offset))
        Lane(lane, index) => Some(VectorLoadLane(lane, index, spec.offset))
      }
    VectorStoreLane(spec) if spec.endianness == Little =>
      Some(VectorStoreLane(spec.lane, spec.lane_index, spec.offset))
    AtomicLoad(spec) if spec.endianness == Little =>
      Some(AtomicLoad(spec.width, spec.value_type))
    AtomicStore(spec) if spec.endianness == Little =>
      Some(AtomicStore(spec.width, spec.value_type))
    AtomicRmw(spec, rmw_operation) if spec.endianness == Little =>
      Some(AtomicRmw(spec.width, spec.value_type, rmw_operation))
    AtomicCompareExchange(spec) if spec.endianness == Little =>
      Some(AtomicCompareExchange(spec.width, spec.value_type))
    AtomicFence => Some(AtomicFence)
    Safepoint(_) => Some(SafepointMarker)
    _ => None
  }
  let selected = match selected {
    Some(selected) => selected
    None =>
      raise UnsupportedOperation(block_index~, instruction_index~, operation~)
  }
  let selected_operands = match operation {
    AtomicLoad(spec)
    | AtomicStore(spec)
    | AtomicRmw(spec, _)
    | AtomicCompareExchange(spec) =>
      if spec.offset == 0UL {
        operands
      } else {
        let offset = append_body(
            builder,
            block,
            LoadConstant(W64, spec.offset),
            [],
            [@vcode.Output::any(I64)],
            @vcode.InstructionMetadata::empty(),
          )[0]
        let address = append_body(
            builder,
            block,
            AddAddress,
            [@vcode.Input::any(operands[0]), @vcode.Input::any(offset)],
            [@vcode.Output::any(Ptr64)],
            @vcode.InstructionMetadata::empty(),
          )[0]
        let selected_operands = operands.copy()
        selected_operands[0] = address
        selected_operands
      }
    _ => operands
  }
  let outputs = match operation {
    AtomicRmw(_, _) | AtomicCompareExchange(_) =>
      result_types.map(ty => @vcode.Output::any(ty).with_timing(Early))
    _ => result_types.map(@vcode.Output::any)
  }
  let results = append_body(
    builder,
    block,
    selected,
    selected_operands.map(@vcode.Input::any),
    outputs,
    source_metadata(
      function.instruction_metadata(instruction).unwrap(),
      roots,
      operation.semantics(),
      trap?=match operation {
        Load(spec) => spec.trap
        Store(spec) => spec.trap
        VectorLoad(spec) => spec.trap
        VectorStoreLane(spec) => spec.trap
        AtomicLoad(spec) => spec.trap
        AtomicStore(spec) => spec.trap
        AtomicRmw(spec, _) => spec.trap
        AtomicCompareExchange(spec) => spec.trap
        _ => None
      },
    ),
  )
  for index, result in semantic_results {
    values[function.value_index(result).unwrap()] = Some(results[index])
  }
}

///|
fn lower_parameters(
  function : @semantic.Function,
  context : LoweringContext,
  builder : @vcode.Builder[AArch64Inst],
  values : Array[@vcode.Value?],
  analysis : LoweringAnalysis,
) -> @vcode.Value? raise AArch64LowerError {
  let entry = builder.entry_block()
  let signature = function.signature()
  let layout = match function.protocol() {
    Platform => platform_call_layout(signature.params)
    Internal =>
      context.internal_abi.call_layout(signature) catch {
        error => raise UnsupportedAbi(message=error.to_string())
      }
  }
  for index, parameter in function.parameters() {
    let ty = function.value_type(parameter).unwrap()
    let parameter_index = function.value_index(parameter).unwrap()
    if layout.arguments[index] is CallStack(_) &&
      analysis.uses[parameter_index] == 0 {
      continue
    }
    let raw = builder.parameter(index) catch {
      error => raise BuildFailure(cause=error)
    }
    let selected = match layout.arguments[index] {
      CallRegister(reg) =>
        append_body(
          builder,
          entry,
          IncomingReg(ty, reg),
          [@vcode.Input::fixed(raw, reg)],
          [abi_home_output(ty, reg)],
          @vcode.InstructionMetadata::empty(),
        )[0]
      CallStack(offset) =>
        append_body(
          builder,
          entry,
          IncomingStack(ty, offset),
          [],
          [@vcode.Output::any_location(ty)],
          @vcode.InstructionMetadata::empty(),
        )[0]
    }
    values[parameter_index] = Some(selected)
  }
  if function.protocol() == Internal {
    let plan = context.internal_abi.call_plan(signature) catch {
      error => raise UnsupportedAbi(message=error.to_string())
    }
    if plan.result_area_size > 0 {
      return Some(
        append_body(
          builder,
          entry,
          IncomingResultArea(context.internal_abi.result_area_argument),
          [],
          [@vcode.Output::any_location(Ptr64)],
          @vcode.InstructionMetadata::empty(),
        )[0],
      )
    }
  }
  None
}

///|
fn lower_return_values(
  function : @semantic.Function,
  context : LoweringContext,
  builder : @vcode.Builder[AArch64Inst],
  block : @vcode.Block,
  values : Array[@vcode.Value],
  result_types : Array[@semantic.ValueType],
  result_area : @vcode.Value?,
) -> Unit raise AArch64LowerError {
  let locations : Array[CallResultLocation] = match function.protocol() {
    Platform => {
      if result_types.length() > 1 {
        raise UnsupportedAbi(
          message="platform functions support at most one direct result",
        )
      }
      platform_result_registers(result_types).map(reg => CallResultRegister(reg))
    }
    Internal => context.internal_abi.result_layout(result_types).0
  }
  for index, value in values {
    let ty = result_types[index]
    match locations[index] {
      CallResultRegister(reg) =>
        append_body(
          builder,
          block,
          OutgoingReg(ty, reg),
          [@vcode.Input::any(value)],
          [],
          @vcode.InstructionMetadata::empty(),
        )
        |> ignore
      CallResultArea(offset, _) => {
        guard result_area is Some(address) else {
          raise UnsupportedAbi(message="internal result area is unavailable")
        }
        append_body(
          builder,
          block,
          OutgoingAreaResult(ty, offset),
          [@vcode.Input::any(address), @vcode.Input::any(value)],
          [],
          @vcode.InstructionMetadata::empty(),
        )
        |> ignore
      }
    }
  }
}

///|
fn set_terminator(
  builder : @vcode.Builder[AArch64Inst],
  block : @vcode.Block,
  instruction : AArch64Inst,
  inputs : Array[@vcode.Input],
  successors : Array[@vcode.Edge],
  metadata : @vcode.InstructionMetadata,
  clobbers? : Array[@vcode.PhysicalReg] = [],
) -> Unit raise AArch64LowerError {
  (builder.set_terminator(
    block, instruction, inputs, successors, clobbers, metadata,
  )
  |> ignore) catch {
    error => raise BuildFailure(cause=error)
  }
}

///|
pub fn lower(
  function : @semantic.Function,
  context : LoweringContext,
) -> @vcode.Function[AArch64Inst] raise AArch64LowerError {
  function.verify() catch {
    error => raise InvalidSemantic(cause=error)
  }
  let signature = function.signature()
  let builder : @vcode.Builder[AArch64Inst] = @vcode.Builder::new_with_protocol(
    function.name(),
    function.protocol(),
    signature.params,
    signature.results,
  )
  let values : Array[@vcode.Value?] = Array::make(function.value_count(), None)
  let analysis = analyze_lowering(function)
  let result_area = lower_parameters(
    function, context, builder, values, analysis,
  )
  let semantic_blocks = function.blocks()
  let blocks : Array[@vcode.Block] = []
  for index, semantic_block in semantic_blocks {
    let block = if index == 0 {
      builder.entry_block()
    } else {
      builder.create_block(
        function
        .block_parameters(semantic_block)
        .map(value => function.value_type(value).unwrap()),
      )
    }
    blocks.push(block)
    for parameter_index, parameter in function.block_parameters(semantic_block) {
      values[function.value_index(parameter).unwrap()] = Some(
        builder.block_parameter(block, parameter_index) catch {
          error => raise BuildFailure(cause=error)
        },
      )
    }
  }
  for semantic_block in function.blocks_in_cfg_order() {
    let block_index = function.block_index(semantic_block).unwrap()
    let block = blocks[block_index]
    for instruction in function.block_instructions(semantic_block) {
      lower_instruction(
        function, context, builder, block, block_index, instruction, values, analysis,
      )
    }
    let record = function.block_terminator(semantic_block).unwrap()
    let metadata = match record.metadata.source {
      Some(source) => @vcode.InstructionMetadata::new(source~)
      None => @vcode.InstructionMetadata::empty()
    }
    match record.kind {
      Jump(edge) =>
        set_terminator(
          builder,
          block,
          Jump,
          [],
          [
            @vcode.Edge::new(
              blocks[function.block_index(edge.target).unwrap()],
              map_values(function, values, edge.arguments),
            ),
          ],
          metadata,
        )
      Branch(condition, true_edge, false_edge) => {
        let selected = analysis.branches[block_index]
        let (terminator, inputs, first_edge, second_edge) = match selected {
          Some(selected) if selected.other is Some(other) &&
            selected.condition is Some(compare_condition) =>
            (
              BranchCompare(selected.width, compare_condition),
              [
                @vcode.Input::any(map_value(function, values, selected.input)),
                @vcode.Input::any(map_value(function, values, other)),
              ],
              true_edge,
              false_edge,
            )
          Some(selected) if selected.immediate is Some(bits) &&
            selected.condition is Some(compare_condition) =>
            (
              BranchCompareImmediate(selected.width, compare_condition, bits),
              [@vcode.Input::any(map_value(function, values, selected.input))],
              true_edge,
              false_edge,
            )
          Some(selected) if selected.swap_edges =>
            (
              BranchNonZero(selected.width),
              [@vcode.Input::any(map_value(function, values, selected.input))],
              false_edge,
              true_edge,
            )
          Some(selected) =>
            (
              BranchNonZero(selected.width),
              [@vcode.Input::any(map_value(function, values, selected.input))],
              true_edge,
              false_edge,
            )
          None =>
            (
              BranchNonZero(W32),
              [@vcode.Input::any(map_value(function, values, condition))],
              true_edge,
              false_edge,
            )
        }
        set_terminator(
          builder,
          block,
          terminator,
          inputs,
          [
            @vcode.Edge::new(
              blocks[function.block_index(first_edge.target).unwrap()],
              map_values(function, values, first_edge.arguments),
            ),
            @vcode.Edge::new(
              blocks[function.block_index(second_edge.target).unwrap()],
              map_values(function, values, second_edge.arguments),
            ),
          ],
          metadata,
        )
      }
      Switch(index, cases, default_edge) => {
        let index_type = function.value_type(index).unwrap()
        let width = if index_type == I32 { W32 } else { W64 }
        let successors : Array[@vcode.Edge] = cases.map(case => {
          @vcode.Edge::new(
            blocks[function.block_index(case.edge.target).unwrap()],
            map_values(function, values, case.edge.arguments),
          )
        })
        successors.push(
          @vcode.Edge::new(
            blocks[function.block_index(default_edge.target).unwrap()],
            map_values(function, values, default_edge.arguments),
          ),
        )
        set_terminator(
          builder,
          block,
          Switch(width, cases.map(case => case.bits)),
          [@vcode.Input::any(map_value(function, values, index))],
          successors,
          metadata,
        )
      }
      Return(return_values) => {
        let mapped = map_values(function, values, return_values)
        lower_return_values(
          function,
          context,
          builder,
          block,
          mapped,
          signature.results,
          result_area,
        )
        set_terminator(builder, block, Return, [], [], metadata)
      }
      TailCall(call, semantic_operands) => {
        if function.protocol() != Internal || call.protocol != Internal {
          raise UnsupportedAbi(
            message="true tail calls require Internal caller and callee protocols",
          )
        }
        let plan = context.internal_abi.call_plan(call.signature) catch {
          error => raise UnsupportedAbi(message=error.to_string())
        }
        let operands = map_values(function, values, semantic_operands)
        if plan.result_area_size > 0 {
          guard result_area is Some(address) else {
            raise UnsupportedAbi(message="tail-call result area is unavailable")
          }
          operands.push(address)
        }
        let target = match call.callee {
          Internal(symbol) => TailCallDirect(symbol, call.signature, plan)
          Indirect => TailCallIndirect(call.signature, plan)
          External(_) =>
            raise UnsupportedAbi(
              message="internal tail calls cannot target an external symbol",
            )
        }
        let inputs = match call.callee {
          Internal(_) =>
            call_argument_inputs(
              operands[:call.signature.params.length()].to_owned(),
              plan.arguments,
            )
          Indirect =>
            [
              @vcode.Input::any_location(operands[0]),
              ..call_argument_inputs(
                operands[1:call.signature.params.length() + 1].to_owned(),
                plan.arguments,
              ),
            ]
          External(_) => abort("external tail call rejected above")
        }
        if plan.result_area_size > 0 {
          let index = inputs.length()
          let input = @vcode.Input::any_location(operands[index])
          inputs.push(
            match result_area_register(plan) {
              Some(reg) if is_allocatable(reg) => input.with_preference(reg)
              _ => input
            },
          )
        }
        set_terminator(
          builder,
          block,
          target,
          inputs,
          [],
          metadata,
          clobbers=platform_call_clobbers(),
        )
      }
      NoReturnCall(call, semantic_operands) => {
        let operands = map_values(function, values, semantic_operands)
        let roots = map_values(function, values, record.metadata.live_gc_roots)
        let call_metadata = terminator_call_metadata(
          record.metadata,
          call.behavior.semantics(),
        )
        let call_metadata = @vcode.InstructionMetadata::new(
          source?=call_metadata.source,
          safepoint?=call_metadata.safepoint,
          live_gc_roots=roots,
        )
        match call.protocol {
          Platform =>
            lower_direct_platform_call(
              builder,
              block,
              call,
              operands,
              [],
              call_metadata,
            )
            |> ignore
          Internal =>
            lower_internal_call(
              context,
              builder,
              block,
              call,
              operands,
              [],
              call_metadata,
            )
            |> ignore
        }
        set_terminator(
          builder,
          block,
          Trap(Unreachable),
          [],
          [],
          terminator_trap_metadata(record.metadata, Unreachable),
        )
      }
      Trap(reason) =>
        set_terminator(
          builder,
          block,
          Trap(reason),
          [],
          [],
          terminator_trap_metadata(record.metadata, reason),
        )
    }
  }
  let lowered = builder.finish()
  verify_vcode(lowered) catch {
    error => raise InvalidTarget(cause=error)
  }
  lowered
}
