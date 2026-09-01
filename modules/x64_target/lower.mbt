///|
pub suberror X64LowerError {
  UnsupportedOperation(
    block_index~ : Int,
    instruction_index~ : Int,
    operation~ : @lowering.Operation
  )
  UnsupportedAbi(message~ : String)
  BuildFailure(cause~ : @vcode.VCodeBuildError)
  InvalidTarget(cause~ : TargetVCodeVerifyError)
} derive(Debug)

///|
pub impl Show for X64LowerError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
fn align_up(value : Int, alignment : Int) -> Int {
  (value + alignment - 1) / alignment * alignment
}

///|
fn gpr_width(ty : @native.ValueType) -> GprWidth? {
  match ty {
    I32 => Some(W32)
    I64 => Some(W64)
    _ => None
  }
}

///|
fn optional_gpr_width(ty : @native.ValueType?) -> GprWidth? {
  match ty {
    Some(ty) => gpr_width(ty)
    None => None
  }
}

///|
fn scalar_access_width(ty : @native.ValueType) -> @native.AccessWidth? {
  match ty {
    I32 | F32 => Some(W32)
    I64 | Ptr64 | GcRef64 | F64 => Some(W64)
    V128 => None
  }
}

///|
fn lower_binary(operation : @lowering.IntBinaryOp) -> X64IntBinary? {
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
fn lower_condition(comparison : @lowering.IntComparison) -> X64Condition {
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
fn lower_reference_condition(
  comparison : @lowering.ReferenceComparison,
) -> X64Condition {
  match comparison {
    Equal => Eq
    NotEqual => Ne
  }
}

///|
fn lower_float_unary(operation : @lowering.FloatUnaryOp) -> X64FloatUnary? {
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
fn lower_float_binary(operation : @lowering.FloatBinaryOp) -> X64FloatBinary? {
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
fn lower_float_ternary(operation : @lowering.FloatTernaryOp) -> X64FloatTernary {
  match operation {
    FusedMultiplyAdd => Fmadd
    FusedNegatedMultiplyAdd => Fmsub
    FusedMultiplySubtract => Fnmsub
    FusedNegatedMultiplySubtract => Fnmadd
  }
}

///|
fn lower_float_condition(
  comparison : @lowering.FloatComparison,
) -> X64FloatCondition? {
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
fn lower_conversion(conversion : @lowering.ConversionOp) -> X64Conversion? {
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
fn float_value_type(ty : @native.FloatType) -> @native.ValueType {
  match ty {
    F32 => F32
    F64 => F64
  }
}

///|
fn float_to_int_bounds(
  source : @native.FloatType,
  result : @native.IntegerType,
  signedness : @native.Signedness,
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
fn append_body(
  builder : @vcode.CheckedBuilder[X64Inst],
  block : @vcode.Block,
  instruction : X64Inst,
  inputs : Array[@vcode.Input],
  outputs : Array[@vcode.Output],
  metadata : @vcode.InstructionMetadata,
  clobbers? : Array[@vcode.PhysicalReg] = [],
) -> Array[@vcode.Value] raise X64LowerError {
  // The instruction's own encoding constraints are authoritative; a caller may
  // only add to them. See `X64Inst::mandatory_clobbers`.
  let effective_clobbers = clobbers.copy()
  for reg in instruction.mandatory_clobbers() {
    if !effective_clobbers.contains(reg) {
      effective_clobbers.push(reg)
    }
  }
  let (_, results) = builder.append_body(
    block, instruction, inputs, outputs, effective_clobbers, metadata,
  ) catch {
    error => raise BuildFailure(cause=error)
  }
  results
}

///|
fn terminator_call_metadata(
  source : @native.SourceLocation?,
  semantics : @native.OperationSemantics,
) -> @vcode.InstructionMetadata {
  let safepoint : @native.SafepointKind? = match
    (semantics.gc_safepoint, semantics.cancellation_safepoint) {
    (true, true) => Some(GcAndCancellation)
    (true, false) => Some(Gc)
    (false, true) => Some(Cancellation)
    (false, false) => None
  }
  match source {
    Some(source) => @vcode.InstructionMetadata::new(source~, safepoint?)
    None => @vcode.InstructionMetadata::new(safepoint?)
  }
}

///|
fn terminator_trap_metadata(
  source : @native.SourceLocation?,
  reason : @native.TrapReason,
) -> @vcode.InstructionMetadata {
  match source {
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
  ty : @native.ValueType,
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
  builder : @vcode.CheckedBuilder[X64Inst],
  block : @vcode.Block,
  call : @native.NativeCall,
  operands : Array[@vcode.Value],
  result_types : Array[@native.ValueType],
  metadata : @vcode.InstructionMetadata,
) -> Array[@vcode.Value] raise X64LowerError {
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
  builder : @vcode.CheckedBuilder[X64Inst],
  block : @vcode.Block,
  call : @native.NativeCall,
  operands : Array[@vcode.Value],
  result_types : Array[@native.ValueType],
  metadata : @vcode.InstructionMetadata,
) -> Array[@vcode.Value] raise X64LowerError {
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
  (builder.append_body(
    block,
    match target {
      Some(target) => InternalCall(target, call.signature, plan)
      None => InternalCallIndirect(call.signature, plan)
    },
    match target {
      Some(_) => call_argument_inputs(operands, plan.arguments)
      None =>
        [
          @vcode.Input::any_location(operands[0]),
          ..call_argument_inputs(operands[1:].to_owned(), plan.arguments),
        ]
    },
    [],
    internal_call_clobbers(plan),
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
fn set_terminator(
  builder : @vcode.CheckedBuilder[X64Inst],
  block : @vcode.Block,
  instruction : X64Inst,
  inputs : Array[@vcode.Input],
  successors : Array[@vcode.Edge],
  metadata : @vcode.InstructionMetadata,
  clobbers? : Array[@vcode.PhysicalReg] = [],
) -> Unit raise X64LowerError {
  (builder.set_terminator(
    block, instruction, inputs, successors, clobbers, metadata,
  )
  |> ignore) catch {
    error => raise BuildFailure(cause=error)
  }
}

///|
priv struct ConstructedFunction {
  function : @vcode.Function[X64Inst]
}

///|
fn validate_constructed(
  constructed : ConstructedFunction,
  on_event : (@vcode.TargetCompileEvent) -> Unit,
) -> Unit raise X64LowerError {
  on_event(TargetValidationStarted)
  on_event(TargetCommonValidationStarted)
  @vcode.verify_selected(constructed.function) catch {
    error => raise InvalidTarget(cause=CommonFailure(cause=error))
  }
  on_event(TargetIsaValidationStarted)
  verify_target_vcode(constructed.function) catch {
    error => raise InvalidTarget(cause=error)
  }
}

///|
/// Opaque evidence that direct x64 selection and VCode validation completed.
pub struct SelectedFunction {
  priv constructed : ConstructedFunction
}

///|
/// Select and validate x64 VCode for immediate target compilation.
