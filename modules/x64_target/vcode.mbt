///|
pub type GprWidth = @vcode.RegisterWidth

///|
pub type X64IntUnary = @vcode.ScalarIntUnary

///|
#derive(Eq, Debug)
pub(all) enum X64IntBinary {
  Add
  Sub
  Mul
  And
  Orr
  Eor
  Lsl
  Asr
  Lsr
  Ror
  Sdiv
  Udiv
}

///|
pub type X64Condition = @vcode.IntegerCondition

///|
pub type X64FloatUnary = @lowering.FloatUnaryOp

///|
pub type X64FloatBinary = @lowering.FloatBinaryOp

///|
pub type X64FloatTernary = @lowering.FloatTernaryOp

///|
pub type X64VectorIntUnary = @lowering.VectorIntUnaryOp

///|
pub type X64VectorIntBinary = @lowering.VectorIntBinaryOp

///|
pub type X64VectorPredicate = @lowering.VectorPredicateOp

///|
pub type X64VectorConversion = @vcode.VectorConversion

///|
pub type X64FloatCondition = @lowering.FloatComparison

///|
pub type X64FloatTrapCondition = @vcode.FloatTrapCondition

///|
pub type X64Address = @vcode.SymbolicAddress

///|
#derive(Eq, Debug)
pub(all) enum X64Conversion {
  WrapI64ToI32
  ExtendI32ToI64(@native.Signedness)
  SignExtend(@native.IntegerType, @native.AccessWidth)
  DemoteF64ToF32
  PromoteF32ToF64
  Bitcast(@native.ValueType, @native.ValueType)
  IntToFloat(@native.IntegerType, @native.FloatType, @native.Signedness)
  FloatToInt(@native.FloatType, @native.IntegerType, @native.Signedness)
  FloatToIntSaturating(
    @native.FloatType,
    @native.IntegerType,
    @native.Signedness
  )
}

///|
pub type X64StackObject = @vcode.SizedStackObject

///|
#derive(Eq, Debug)
pub(all) enum X64Inst {
  IncomingReg(@native.ValueType, @vcode.PhysicalReg)
  IncomingStack(@native.ValueType, Int32)
  IncomingResultArea(@vcode.PhysicalReg)
  IncomingCallResult(@native.ValueType, @vcode.PhysicalReg)
  IncomingCallAreaResult(@native.ValueType, Int32)
  OutgoingReg(@native.ValueType, @vcode.PhysicalReg)
  OutgoingAreaResult(@native.ValueType, Int32)
  KeepAlive(@native.ValueType)
  LoadConstant(GprWidth, UInt64)
  LoadVectorConstant(UInt64, UInt64)
  LoadNull(@native.ValueType)
  LoadAddress(X64Address)
  StackAddress(X64StackObject)
  LoadFloatConstant(@native.ValueType, UInt64)
  Move(@native.ValueType)
  CarrierMove(@native.ValueType, @native.ValueType)
  Select(@native.ValueType)
  SpectreGuard
  VectorSelect
  VectorSplat(@lowering.VectorLane)
  VectorExtractLane(@lowering.VectorLane, Int32, @native.Signedness?)
  VectorReplaceLane(@lowering.VectorLane, Int32)
  VectorShuffle(FixedArray[Int32])
  VectorSwizzle
  VectorBitwise(@lowering.VectorBitwiseOp)
  VectorIntUnary(@lowering.VectorLane, X64VectorIntUnary)
  VectorIntBinary(@lowering.VectorLane, X64VectorIntBinary)
  VectorIntShift(@lowering.VectorLane, @lowering.VectorIntShiftOp)
  VectorIntCompare(@lowering.VectorLane, @lowering.VectorIntComparison)
  VectorConvert(X64VectorConversion)
  VectorPredicate(X64VectorPredicate)
  VectorFloatUnary(@lowering.VectorLane, @lowering.VectorFloatUnaryOp)
  VectorFloatBinary(@lowering.VectorLane, @lowering.VectorFloatBinaryOp)
  VectorFloatTernary(@lowering.VectorLane, @lowering.FloatTernaryOp)
  VectorFloatCompare(@lowering.VectorLane, @lowering.VectorFloatComparison)
  VectorPairwiseAddI16x8
  VectorRelaxedDot8To16
  IntUnary(GprWidth, X64IntUnary)
  IntBinary(GprWidth, X64IntBinary)
  PopulationCount(GprWidth)
  IntHighMultiply(GprWidth, @native.Signedness)
  IntWithOverflow(GprWidth, @lowering.IntOverflowOp)
  IntRemainder(GprWidth, @native.Signedness)
  TrapIfZero(GprWidth)
  TrapIfSignedDivOverflow(GprWidth)
  CompareSet(GprWidth, X64Condition)
  ReferenceCompareSet(@native.ValueType, X64Condition)
  FloatUnary(@native.ValueType, X64FloatUnary)
  FloatBinary(@native.ValueType, X64FloatBinary)
  FloatTernary(@native.ValueType, X64FloatTernary)
  FloatCompareSet(@native.ValueType, X64FloatCondition)
  TrapIfFloat(@native.ValueType, X64FloatTrapCondition)
  Convert(X64Conversion)
  AddAddress
  ScalarLoad(
    @native.AccessWidth,
    @native.LoadExtension,
    @native.ValueType,
    UInt64
  )
  ScalarStore(@native.AccessWidth, @native.ValueType, UInt64)
  StoreRepeated64(UInt64, UInt32, UInt64)
  VectorLoad128(UInt64)
  VectorStore128(UInt64)
  VectorLoadSplat(@lowering.VectorLane, UInt64)
  VectorLoadExtend(@lowering.VectorLane, @native.Signedness, UInt64)
  VectorLoadZero(@native.AccessWidth, UInt64)
  VectorLoadLane(@lowering.VectorLane, Int32, UInt64)
  VectorStoreLane(@lowering.VectorLane, Int32, UInt64)
  AtomicLoad(@native.AccessWidth, @native.ValueType)
  AtomicStore(@native.AccessWidth, @native.ValueType)
  AtomicRmw(@native.AccessWidth, @native.ValueType, @lowering.AtomicRmwOp)
  AtomicCompareExchange(@native.AccessWidth, @native.ValueType)
  AtomicFence
  SafepointMarker
  PlatformCall(@native.ExternalSymbol, @native.Signature)
  ReturnsTwicePlatformCall(@native.ExternalSymbol, @native.Signature)
  InternalCall(@native.CodeSymbol, @native.Signature, InternalCallPlan)
  InternalCallIndirect(@native.Signature, InternalCallPlan)
  TailCallDirect(@native.CodeSymbol, @native.Signature, InternalCallPlan)
  TailCallIndirect(@native.Signature, InternalCallPlan)
  Jump
  BranchNonZero32
  BranchCompare(GprWidth, X64Condition)
  Switch(GprWidth, Array[UInt64])
  Trap(@native.TrapReason)
  Return
}

///|
let platform_integer_arguments : Array[Int32] = [7, 6, 2, 1, 8, 9]

///|
fn platform_call_layout(types : Array[@native.ValueType]) -> CallLayout {
  @vcode.platform_call_layout(types, platform_integer_arguments[:])
}

///|
fn platform_result_registers(
  types : Array[@native.ValueType],
) -> Array[@vcode.PhysicalReg] {
  @vcode.platform_result_registers(types, integer_registers=[0, 2])
}

///|
fn platform_call_clobbers() -> Array[@vcode.PhysicalReg] {
  let clobbers : Array[@vcode.PhysicalReg] = []
  for index in [0, 1, 2, 6, 7, 8, 9, 10, 11] {
    clobbers.push(@vcode.PhysicalReg::new(index, Int))
  }
  for index in 0..<16 {
    clobbers.push(@vcode.PhysicalReg::new(index, FpVector))
  }
  clobbers
}

///|
fn internal_call_clobbers(plan : InternalCallPlan) -> Array[@vcode.PhysicalReg] {
  let clobbers = platform_call_clobbers()
  if plan.result_area_register() is Some(reg) && !clobbers.contains(reg) {
    clobbers.push(reg)
  }
  clobbers
}

///|
fn integer_type(width : GprWidth) -> @native.ValueType {
  match width {
    W32 => I32
    W64 => I64
  }
}

///|
/// Physical registers an x64 instruction always overwrites beyond its declared
/// outputs.
///
/// These are properties of the instruction encoding itself, not of any
/// particular lowering path:
///
/// - Variable shifts and rotates take their count in `cl`, so the emitter
///   always materializes the count into `rcx`.
/// - `imul`/`idiv`/`div` and the `rax`-based atomic read-modify-write loops
///   write both `rax` and `rdx`.
///
/// Lowering must not be trusted to remember them. The `append_body` helper in
/// `lower.mbt` unions this set into every appended instruction, so a clobber
/// cannot be lost by a special-case lowering path that bypasses the generic
/// instruction-selection code.
fn X64Inst::mandatory_clobbers(self : X64Inst) -> Array[@vcode.PhysicalReg] {
  let rax = @vcode.PhysicalReg::new(0, Int)
  let rcx = @vcode.PhysicalReg::new(1, Int)
  let rdx = @vcode.PhysicalReg::new(2, Int)
  match self {
    IntBinary(_, Lsl | Asr | Lsr | Ror) => [rcx]
    IntBinary(_, Sdiv | Udiv) => [rdx]
    IntRemainder(_, _) => [rax]
    IntHighMultiply(_, _) => [rax]
    IntWithOverflow(_, Mul(_)) => [rdx]
    AtomicRmw(_, _, And | Or | Xor) => [rdx]
    _ => []
  }
}

///|
/// Reject VCode that omits an instruction's mandatory clobbers.
///
/// Register allocation trusts the declared clobber set: a missing entry lets it
/// keep a live value in a register the emitter is going to overwrite. Checking
/// it here makes the invariant hold for any VCode reaching the verifier, not
/// only VCode built through this module's `append_body` helper.
fn require_mandatory_clobbers(
  function : @vcode.Function[X64Inst],
  instruction : @vcode.Instruction,
) -> Unit raise TargetVCodeVerifyError {
  let inst = function.instruction(instruction).unwrap()
  let required = inst.mandatory_clobbers()
  if required.is_empty() {
    return
  }
  let declared = function.instruction_clobbers(instruction)
  for reg in required {
    if !declared.contains(reg) {
      raise InvalidInstruction(
        instruction~,
        message="instruction must declare its mandatory clobber of physical register \{reg.id}",
      )
    }
  }
}

///|
fn conversion_shape(
  conversion : X64Conversion,
) -> (@native.ValueType, @native.ValueType)? {
  match conversion {
    WrapI64ToI32 => Some((I64, I32))
    ExtendI32ToI64(_) => Some((I32, I64))
    SignExtend(I32, W8 | W16) => Some((I32, I32))
    SignExtend(I64, W8 | W16 | W32) => Some((I64, I64))
    DemoteF64ToF32 => Some((F64, F32))
    PromoteF32ToF64 => Some((F32, F64))
    Bitcast(from, to) =>
      if @native.valid_scalar_bitcast(from, to) {
        Some((from, to))
      } else {
        None
      }
    IntToFloat(I32, F32, _) => Some((I32, F32))
    IntToFloat(I32, F64, _) => Some((I32, F64))
    IntToFloat(I64, F32, _) => Some((I64, F32))
    IntToFloat(I64, F64, _) => Some((I64, F64))
    FloatToInt(F32, I32, _) | FloatToIntSaturating(F32, I32, _) =>
      Some((F32, I32))
    FloatToInt(F32, I64, _) | FloatToIntSaturating(F32, I64, _) =>
      Some((F32, I64))
    FloatToInt(F64, I32, _) | FloatToIntSaturating(F64, I32, _) =>
      Some((F64, I32))
    FloatToInt(F64, I64, _) | FloatToIntSaturating(F64, I64, _) =>
      Some((F64, I64))
    _ => None
  }
}

///|
pub fn verify_vcode(
  function : @vcode.Function[X64Inst],
) -> Unit raise TargetVCodeVerifyError {
  @vcode.verify_selected(function) catch {
    error => raise CommonFailure(cause=error)
  }
  verify_target_vcode(function)
}

///|
fn verify_target_vcode(
  function : @vcode.Function[X64Inst],
) -> Unit raise TargetVCodeVerifyError {
  for index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(index).unwrap()
    require_mandatory_clobbers(function, instruction)
    let check = @vcode.TargetInstructionVerifier::new(function, instruction)
    match function.instruction(instruction).unwrap() {
      IncomingReg(ty, reg) => check.incoming_reg(ty, reg)
      IncomingStack(ty, offset) => check.incoming_stack(ty, offset)
      IncomingResultArea(reg) => check.incoming_result_area(reg)
      IncomingCallResult(ty, reg) => check.incoming_call_result(ty, reg)
      IncomingCallAreaResult(ty, offset) =>
        check.incoming_call_area_result(ty, offset)
      LoadConstant(width, bits) =>
        check.load_constant(integer_type(width), bits)
      LoadVectorConstant(_, _) => check.shape([], [V128])
      LoadNull(ty) => check.load_null(ty)
      LoadAddress(_) => check.shape([], [Ptr64])
      StackAddress(object) => check.stack_address(object.is_valid())
      LoadFloatConstant(ty, bits) => check.load_float_constant(ty, bits)
      OutgoingReg(ty, reg) => check.outgoing_reg(ty, reg)
      OutgoingAreaResult(ty, offset) => check.outgoing_area_result(ty, offset)
      KeepAlive(ty) => check.shape([ty], [])
      Move(ty) => check.shape([ty], [ty])
      CarrierMove(from, to) => check.carrier_move(from, to)
      Select(ty) => check.scalar_select(ty)
      SpectreGuard => check.shape([I32, Ptr64, Ptr64], [Ptr64])
      VectorSelect => check.shape([I32, V128, V128], [V128])
      VectorSplat(lane) => check.shape([lane.scalar_type()], [V128])
      VectorExtractLane(lane, index, extension) =>
        check.vector_extract_lane(lane, index, extension is Some(_))
      VectorReplaceLane(lane, index) => check.vector_replace_lane(lane, index)
      VectorShuffle(mask) => check.vector_shuffle(mask)
      VectorSwizzle | VectorRelaxedDot8To16 | VectorPairwiseAddI16x8 =>
        check.shape([V128, V128], [V128])
      VectorIntUnary(lane, operation) => check.vector_int_unary(lane, operation)
      VectorIntBinary(lane, operation) =>
        check.vector_int_binary(lane, operation)
      VectorIntShift(lane, _) => check.vector_int_shift(lane)
      VectorIntCompare(lane, _) => check.vector_int_compare(lane)
      VectorConvert(conversion) => check.vector_conversion(conversion)
      VectorPredicate(predicate) => check.vector_predicate(predicate)
      VectorFloatUnary(lane, _) => check.vector_float_unary(lane)
      VectorFloatBinary(lane, _) | VectorFloatCompare(lane, _) =>
        check.vector_float_binary(lane)
      VectorFloatTernary(lane, _) => check.vector_float_ternary(lane)
      VectorBitwise(operation) => check.vector_bitwise(operation)
      IntUnary(width, _) | PopulationCount(width) =>
        check.shape([integer_type(width)], [integer_type(width)])
      IntBinary(width, _)
      | IntHighMultiply(width, _)
      | IntRemainder(width, _) =>
        check.shape([integer_type(width), integer_type(width)], [
          integer_type(width),
        ])
      IntWithOverflow(width, _) =>
        check.shape([integer_type(width), integer_type(width)], [
          integer_type(width),
          I32,
        ])
      TrapIfZero(width) => check.trap_if_zero(integer_type(width))
      TrapIfSignedDivOverflow(width) =>
        check.trap_if_signed_div_overflow(integer_type(width))
      CompareSet(width, _) =>
        check.shape([integer_type(width), integer_type(width)], [I32])
      ReferenceCompareSet(ty, _) => check.reference_compare(ty)
      FloatUnary(ty, _) => check.float_unary(ty)
      FloatBinary(ty, _) => check.float_binary(ty)
      FloatTernary(ty, _) => check.float_ternary(ty)
      FloatCompareSet(ty, _) => check.float_compare(ty)
      TrapIfFloat(ty, condition) =>
        check.trap_if_float(ty, condition == Unordered)
      Convert(conversion) =>
        check.conversion(
          conversion_shape(conversion),
          conversion is (Bitcast(I64, Ptr64) | Bitcast(Ptr64, I64)),
          target="x64",
        )
      AddAddress => check.shape([Ptr64, I64], [Ptr64])
      ScalarLoad(width, extension, result_type, _) =>
        check.scalar_load(width, extension, result_type, target="x64")
      StoreRepeated64(offset, count, _) => check.store_repeated64(offset, count)
      ScalarStore(width, value_type, _) =>
        check.scalar_store(width, value_type, target="x64")
      VectorLoad128(_) | VectorLoadSplat(_, _) => check.shape([Ptr64], [V128])
      VectorStore128(_) => check.shape([Ptr64, V128], [])
      VectorLoadZero(width, _) => check.vector_load_zero(width)
      VectorLoadExtend(lane, _, _) => check.vector_load_extend(lane)
      VectorLoadLane(lane, index, _) => check.vector_load_lane(lane, index)
      VectorStoreLane(lane, index, _) => check.vector_store_lane(lane, index)
      AtomicLoad(width, ty) => check.atomic_load(width, ty, target="x64")
      AtomicStore(width, ty) => check.atomic_store(width, ty, target="x64")
      AtomicRmw(width, ty, operation) => {
        check.atomic_rmw(width, ty, target="x64")
        if operation is (And | Or | Xor) {
          check.atomic_early_def(
            "compare-exchange atomic RMW result must be an early definition",
          )
        }
      }
      AtomicCompareExchange(width, ty) => {
        check.atomic_compare_exchange(width, ty, target="x64")
        for index, register in [11, 0, 10, 0] {
          let operand = function
            .instruction_operand_at(instruction, index)
            .unwrap()
          if operand.constraint != FixedReg(int_physical(register)) {
            raise InvalidInstruction(
              instruction~,
              message="atomic compare-exchange must reserve its address, accumulator, and replacement registers",
            )
          }
        }
      }
      AtomicFence => check.shape([], [])
      SafepointMarker => check.safepoint_marker()
      PlatformCall(_, signature) | ReturnsTwicePlatformCall(_, signature) =>
        check.platform_call(
          signature, platform_call_layout, is_allocatable, platform_call_clobbers,
        )
      InternalCall(_, signature, plan) =>
        check.internal_call(
          signature,
          plan,
          indirect=false,
          is_allocatable,
          internal_call_clobbers,
        )
      InternalCallIndirect(signature, plan) =>
        check.internal_call(
          signature,
          plan,
          indirect=true,
          is_allocatable,
          internal_call_clobbers,
        )
      TailCallDirect(_, signature, plan) =>
        require_tail_call_plan(
          function,
          instruction,
          signature,
          plan,
          false,
          is_allocatable,
          internal_call_clobbers(plan),
        )
      TailCallIndirect(signature, plan) =>
        require_tail_call_plan(
          function,
          instruction,
          signature,
          plan,
          true,
          is_allocatable,
          internal_call_clobbers(plan),
        )
      Jump => check.shape([], [], successors=1)
      BranchNonZero32 => check.shape([I32], [], successors=2)
      BranchCompare(width, _) =>
        check.shape(
          [integer_type(width), integer_type(width)],
          [],
          successors=2,
        )
      Switch(width, cases) => check.switch_shape(integer_type(width), cases)
      Trap(reason) => check.trap(reason)
      Return => check.return_shape()
    }
  }
  @vcode.verify_abi_materialization(
    function, abi_materialization, platform_result_registers,
  )
}

///|
fn abi_materialization(inst : X64Inst) -> @vcode.AbiMaterialization {
  match inst {
    PlatformCall(_, signature) | ReturnsTwicePlatformCall(_, signature) =>
      PlatformResults(signature)
    InternalCall(_, signature, plan) | InternalCallIndirect(signature, plan) =>
      InternalResults(signature, plan)
    TailCallDirect(_, signature, plan) if plan.result_area_size > 0 =>
      ForwardResultArea(signature.params.length(), indirect=false)
    TailCallIndirect(signature, plan) if plan.result_area_size > 0 =>
      ForwardResultArea(signature.params.length() + 1, indirect=true)
    IncomingResultArea(_) => ReceiveResultArea
    IncomingCallResult(ty, reg) => ReceiveRegisterResult(ty, reg)
    IncomingCallAreaResult(ty, offset) => ReceiveAreaResult(ty, offset)
    OutgoingReg(ty, _) => ReturnRegisterResult(ty)
    OutgoingAreaResult(ty, _) => ReturnAreaResult(ty)
    Return => Return
    _ => Ordinary
  }
}
