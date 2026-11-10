///|
#derive(Debug)
pub suberror X64LowerError {
  UnsupportedOperation(
    block_index~ : Int32,
    instruction_index~ : Int32,
    operation~ : @lowering.Operation
  )
  UnsupportedAbi(message~ : String)
  BuildFailure(cause~ : @vcode.VCodeBuildError)
  InvalidTarget(cause~ : TargetVCodeVerifyError)
}

///|
pub impl Show for X64LowerError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
fn align_up(value : Int32, alignment : Int32) -> Int32 {
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
fn append_body(
  builder : @vcode.CheckedBuilder[X64Inst],
  block : @vcode.Block,
  instruction : X64Inst,
  inputs : Array[@vcode.Input],
  outputs : Array[@vcode.Output],
  metadata : @vcode.InstructionMetadata,
  clobbers~ : Array[@vcode.PhysicalReg] = [],
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
fn lower_call_results(
  builder : @vcode.CheckedBuilder[X64Inst],
  block : @vcode.Block,
  result_types : Array[@native.ValueType],
  locations : ArrayView[CallResultLocation],
  metadata : @vcode.InstructionMetadata,
) -> Array[@vcode.Value] raise X64LowerError {
  @vcode.materialize_call_results(
    builder,
    block,
    result_types,
    locations,
    metadata.live_gc_roots,
    (ty, reg) => IncomingCallResult(ty, reg),
    (ty, offset) => IncomingCallAreaResult(ty, offset),
    KeepAlive(GcRef64),
    is_allocatable,
  ) catch {
    error => raise BuildFailure(cause=error)
  }
}

///|
fn lower_call(
  context : LoweringContext,
  builder : @vcode.CheckedBuilder[X64Inst],
  block : @vcode.Block,
  call : @native.NativeCall,
  operands : Array[@vcode.Value],
  result_types : Array[@native.ValueType],
  metadata : @vcode.InstructionMetadata,
) -> Array[@vcode.Value] raise X64LowerError {
  let (instruction, inputs, clobbers, locations) : (
    X64Inst,
    Array[@vcode.Input],
    Array[@vcode.PhysicalReg],
    ArrayView[CallResultLocation],
  ) = match call.protocol {
    Platform => {
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
      let operands = builder.materialize_abi_words(
        block,
        operands,
        call.signature.params,
        ty => Move(ty),
      ) catch {
        error => raise BuildFailure(cause=error)
      }
      let result_registers = platform_result_registers(call.signature.results)
      let inputs = @vcode.call_argument_inputs(
        operands,
        platform_call_layout(call.signature.params).arguments,
        is_allocatable,
      )
      let instruction = if call.behavior.returns_twice {
        ReturnsTwicePlatformCall(target, call.signature)
      } else {
        PlatformCall(target, call.signature)
      }
      (
        instruction,
        inputs,
        platform_call_clobbers(),
        result_registers.map(reg => CallResultRegister(reg)),
      )
    }
    Internal => {
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
      let operands = builder.materialize_abi_words(
        block,
        operands,
        call.signature.params,
        ty => Move(ty),
        operand_start=if target is None { 1 } else { 0 },
      ) catch {
        error => raise BuildFailure(cause=error)
      }
      let plan = context.internal_abi.call_plan(call.signature) catch {
        error => raise UnsupportedAbi(message=error.to_string())
      }
      let instruction = match target {
        Some(target) => InternalCall(target, call.signature, plan)
        None => InternalCallIndirect(call.signature, plan)
      }
      let inputs = match target {
        Some(_) =>
          @vcode.call_argument_inputs(operands, plan.arguments, is_allocatable)
        None =>
          [
            @vcode.Input::any_location(operands[0]),
            ..@vcode.call_argument_inputs(
              operands[1:].to_owned(),
              plan.arguments,
              is_allocatable,
            ),
          ]
      }
      (instruction, inputs, internal_call_clobbers(plan), plan.results)
    }
  }
  ignore(
    builder.append_body(block, instruction, inputs, [], clobbers, metadata) catch {
      error => raise BuildFailure(cause=error)
    },
  )
  lower_call_results(builder, block, result_types, locations, metadata)
}

///|
fn set_terminator(
  builder : @vcode.CheckedBuilder[X64Inst],
  block : @vcode.Block,
  instruction : X64Inst,
  inputs : Array[@vcode.Input],
  successors : Array[@vcode.Edge],
  metadata : @vcode.InstructionMetadata,
  clobbers~ : Array[@vcode.PhysicalReg] = [],
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
