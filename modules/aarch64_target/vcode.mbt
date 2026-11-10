///|
pub type GprWidth = @vcode.RegisterWidth

///|
pub type AArch64IntUnary = @vcode.ScalarIntUnary

///|
#derive(Eq, Debug)
pub(all) enum AArch64IntBinary {
  Add
  Sub
  Mul
  And
  Orr
  Eor
  Sdiv
  Udiv
}

///|
#derive(Eq, Debug)
pub(all) enum AArch64Shift {
  Lsl
  Asr
  Lsr
  Ror
}

///|
pub type AArch64Condition = @vcode.IntegerCondition

///|
pub type AArch64FloatUnary = @lowering.FloatUnaryOp

///|
pub type AArch64FloatBinary = @lowering.FloatBinaryOp

///|
pub type AArch64FloatTernary = @lowering.FloatTernaryOp

///|
pub type AArch64VectorIntUnary = @lowering.VectorIntUnaryOp

///|
pub type AArch64VectorIntBinary = @lowering.VectorIntBinaryOp

///|
pub type AArch64VectorPredicate = @lowering.VectorPredicateOp

///|
pub type AArch64VectorConversion = @vcode.VectorConversion

///|
pub type AArch64FloatCondition = @lowering.FloatComparison

///|
pub type AArch64FloatTrapCondition = @vcode.FloatTrapCondition

///|
pub type AArch64Address = @vcode.SymbolicAddress

///|
#derive(Eq, Debug)
pub(all) enum AArch64Conversion {
  WrapI64ToI32
  ExtendI32ToI64(@native.Signedness)
  SignExtend(@native.IntegerType, @native.AccessWidth)
  DemoteF64ToF32
  PromoteF32ToF64
  Bitcast(@native.ValueType, @native.ValueType)
  IntToFloat(@native.IntegerType, @native.FloatType, @native.Signedness)
  FloatToInt(@native.FloatType, @native.IntegerType, @native.Signedness)
}

///|
pub type AArch64StackObject = @vcode.SizedStackObject

///|
#derive(Eq, Debug)
pub(all) enum AArch64Inst {
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
  LoadAddress(AArch64Address)
  StackAddress(AArch64StackObject)
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
  VectorIntUnary(@lowering.VectorLane, AArch64VectorIntUnary)
  VectorIntBinary(@lowering.VectorLane, AArch64VectorIntBinary)
  VectorIntShift(@lowering.VectorLane, @lowering.VectorIntShiftOp)
  VectorIntCompare(@lowering.VectorLane, @lowering.VectorIntComparison)
  VectorConvert(AArch64VectorConversion)
  VectorPredicate(AArch64VectorPredicate)
  VectorFloatUnary(@lowering.VectorLane, @lowering.VectorFloatUnaryOp)
  VectorFloatBinary(@lowering.VectorLane, @lowering.VectorFloatBinaryOp)
  VectorFloatTernary(@lowering.VectorLane, @lowering.FloatTernaryOp)
  VectorFloatCompare(@lowering.VectorLane, @lowering.VectorFloatComparison)
  VectorPairwiseAddI16x8
  VectorRelaxedDot8To16
  IntUnary(GprWidth, AArch64IntUnary)
  IntBinary(GprWidth, AArch64IntBinary)
  IntBinaryImmediate(GprWidth, AArch64IntBinary, UInt64)
  IntMultiplyAdd(GprWidth)
  IntMultiplySubtract(GprWidth)
  IntShiftRegister(GprWidth, AArch64Shift)
  IntShiftImmediate(GprWidth, AArch64Shift, Int32)
  IntAddShiftedLeft(GprWidth, Int32)
  IntAddShiftedRight(GprWidth, Int32)
  IntLowBitsShiftLeft(GprWidth, Int32, Int32)
  IntExtractBits(GprWidth, Int32, Int32)
  PopulationCount(GprWidth)
  IntHighMultiply(GprWidth, @native.Signedness)
  IntWithOverflow(GprWidth, @lowering.IntOverflowOp)
  IntRemainder(GprWidth, @native.Signedness)
  TrapIfZero(GprWidth)
  TrapIfSignedDivOverflow(GprWidth)
  CompareSet(GprWidth, AArch64Condition)
  CompareSetImmediate(GprWidth, AArch64Condition, UInt64)
  ReferenceCompareSet(@native.ValueType, AArch64Condition)
  FloatUnary(@native.ValueType, AArch64FloatUnary)
  FloatBinary(@native.ValueType, AArch64FloatBinary)
  FloatTernary(@native.ValueType, AArch64FloatTernary)
  FloatCompareSet(@native.ValueType, AArch64FloatCondition)
  TrapIfFloat(@native.ValueType, AArch64FloatTrapCondition)
  Convert(AArch64Conversion)
  AddAddress
  AddAddressImmediate(UInt64)
  AddAddressUxtw(Int32)
  ScalarLoad(
    @native.AccessWidth,
    @native.LoadExtension,
    @native.ValueType,
    UInt64
  )
  ScalarLoadUxtw(
    @native.AccessWidth,
    @native.LoadExtension,
    @native.ValueType,
    Int32
  )
  ScalarStore(@native.AccessWidth, @native.ValueType, UInt64)
  StoreRepeated64(UInt64, UInt32, UInt64)
  ScalarStoreUxtw(@native.AccessWidth, @native.ValueType, Int32)
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
  BranchNonZero(GprWidth)
  BranchCompare(GprWidth, AArch64Condition)
  BranchCompareImmediate(GprWidth, AArch64Condition, UInt64)
  Switch(GprWidth, Array[UInt64])
  Trap(@native.TrapReason)
  Return
}

///|
let platform_integer_arguments : Array[Int32] = [0, 1, 2, 3, 4, 5, 6, 7]

///|
fn platform_call_layout(types : Array[@native.ValueType]) -> CallLayout {
  @vcode.platform_call_layout(types, platform_integer_arguments[:])
}

///|
fn platform_result_registers(
  types : Array[@native.ValueType],
) -> Array[@vcode.PhysicalReg] {
  @vcode.platform_result_registers(types)
}

///|
fn platform_call_clobbers() -> Array[@vcode.PhysicalReg] {
  let clobbers : Array[@vcode.PhysicalReg] = []
  for index in 0..<18 {
    clobbers.push(@vcode.PhysicalReg::new(index, Int))
  }
  // The unified FP/vector bank must conservatively treat v8-v15 as clobbered:
  // AAPCS64 preserves only their low 64 bits, not a complete V128 value.
  for index in 0..<32 {
    clobbers.push(@vcode.PhysicalReg::new(index, FpVector))
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
fn valid_scalar_register_shift(
  width : @native.AccessWidth,
  shift : Int32,
) -> Bool {
  let natural_shift = match width {
    W8 => 0
    W16 => 1
    W32 => 2
    W64 => 3
    W128 => 4
  }
  shift == 0 || shift == natural_shift
}

///|
fn conversion_shape(
  conversion : AArch64Conversion,
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
    FloatToInt(F32, I32, _) => Some((F32, I32))
    FloatToInt(F32, I64, _) => Some((F32, I64))
    FloatToInt(F64, I32, _) => Some((F64, I32))
    FloatToInt(F64, I64, _) => Some((F64, I64))
    _ => None
  }
}

///|
pub fn verify_vcode(
  function : @vcode.Function[AArch64Inst],
) -> Unit raise TargetVCodeVerifyError {
  @vcode.verify_selected(function) catch {
    error => raise CommonFailure(cause=error)
  }
  verify_target_vcode(function)
}

///|
fn verify_target_vcode(
  function : @vcode.Function[AArch64Inst],
) -> Unit raise TargetVCodeVerifyError {
  for index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(index).unwrap()
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
      VectorReplaceLane(lane, index) => {
        check.vector_replace_lane(lane, index)
        let source = function.instruction_operand_at(instruction, 0).unwrap()
        let result = function.instruction_operand_at(instruction, 2).unwrap()
        if result.tie_id < 0 || result.tie_id != source.tie_id {
          raise InvalidInstruction(
            instruction~,
            message="vector lane replacement result must be tied to its source vector",
          )
        }
      }
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
      | IntShiftRegister(width, _)
      | IntHighMultiply(width, _)
      | IntRemainder(width, _) =>
        check.shape([integer_type(width), integer_type(width)], [
          integer_type(width),
        ])
      IntBinaryImmediate(width, operation, bits) => {
        let ty = integer_type(width)
        if !valid_int_binary_immediate(width, operation, bits) {
          raise InvalidInstruction(
            instruction~,
            message="integer immediate cannot be encoded",
          )
        }
        check.shape([ty], [ty])
      }
      IntMultiplyAdd(width) | IntMultiplySubtract(width) =>
        check.shape(
          [integer_type(width), integer_type(width), integer_type(width)],
          [integer_type(width)],
        )
      IntShiftImmediate(width, _, amount) => {
        let ty = integer_type(width)
        let bit_width = if width == W32 { 32 } else { 64 }
        if amount < 0 || amount >= bit_width {
          raise InvalidInstruction(
            instruction~,
            message="integer shift amount is out of range",
          )
        }
        check.shape([ty], [ty])
      }
      IntExtractBits(width, start, field_bits) => {
        let bits = if width == W32 { 32 } else { 64 }
        if start < 0 ||
          start >= bits ||
          field_bits <= 0 ||
          field_bits > bits - start {
          raise InvalidInstruction(
            instruction~,
            message="integer bit extract is out of range",
          )
        }
        let ty = integer_type(width)
        check.shape([ty], [ty])
      }
      IntLowBitsShiftLeft(width, field_bits, amount) => {
        let ty = integer_type(width)
        let bits = if width == W32 { 32 } else { 64 }
        if field_bits <= 0 ||
          field_bits > bits ||
          amount < 0 ||
          amount > bits - field_bits {
          raise InvalidInstruction(
            instruction~,
            message="low-bit shift field or amount is out of range",
          )
        }
        check.shape([ty], [ty])
      }
      IntAddShiftedLeft(width, amount) | IntAddShiftedRight(width, amount) => {
        let ty = integer_type(width)
        let bit_width = if width == W32 { 32 } else { 64 }
        if amount < 0 || amount >= bit_width {
          raise InvalidInstruction(
            instruction~,
            message="integer shift amount is out of range",
          )
        }
        check.shape([ty, ty], [ty])
      }
      IntWithOverflow(width, _) =>
        check.shape([integer_type(width), integer_type(width)], [
          integer_type(width),
          I32,
        ])
      TrapIfZero(width) => check.trap_if_zero(integer_type(width))
      TrapIfSignedDivOverflow(width) =>
        check.trap_if_signed_div_overflow(integer_type(width))
      CompareSetImmediate(width, _, bits) => {
        if add_sub_immediate_shift(bits) is None {
          raise InvalidInstruction(
            instruction~,
            message="comparison immediate cannot be encoded",
          )
        }
        check.shape([integer_type(width)], [I32])
      }
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
          target="AArch64",
        )
      AddAddress => check.shape([Ptr64, I64], [Ptr64])
      AddAddressImmediate(bits) => {
        if add_sub_immediate_shift(bits) is None {
          raise InvalidInstruction(
            instruction~,
            message="address immediate cannot be encoded",
          )
        }
        check.shape([Ptr64], [Ptr64])
      }
      AddAddressUxtw(shift) => {
        if shift < 0 || shift > 4 {
          raise InvalidInstruction(
            instruction~,
            message="invalid AArch64 extended address shift",
          )
        }
        check.shape([Ptr64, I32], [Ptr64])
      }
      ScalarLoad(width, extension, result_type, _) =>
        check.scalar_load(width, extension, result_type, target="AArch64")
      ScalarLoadUxtw(width, extension, result_type, shift) => {
        if !@native.valid_scalar_load(width, extension, result_type) ||
          !valid_scalar_register_shift(width, shift) {
          raise InvalidInstruction(
            instruction~,
            message="invalid AArch64 scalar register-offset load",
          )
        }
        check.shape([Ptr64, I32], [result_type])
      }
      StoreRepeated64(offset, count, _) => check.store_repeated64(offset, count)
      ScalarStore(width, value_type, _) =>
        check.scalar_store(width, value_type, target="AArch64")
      ScalarStoreUxtw(width, value_type, shift) => {
        if !@native.valid_scalar_store(width, value_type) ||
          !valid_scalar_register_shift(width, shift) {
          raise InvalidInstruction(
            instruction~,
            message="invalid AArch64 scalar register-offset store",
          )
        }
        check.shape([Ptr64, I32, value_type], [])
      }
      VectorLoad128(_) | VectorLoadSplat(_, _) => check.shape([Ptr64], [V128])
      VectorStore128(_) => check.shape([Ptr64, V128], [])
      VectorLoadZero(width, _) => check.vector_load_zero(width)
      VectorLoadExtend(lane, _, _) => check.vector_load_extend(lane)
      VectorLoadLane(lane, index, _) => check.vector_load_lane(lane, index)
      VectorStoreLane(lane, index, _) => check.vector_store_lane(lane, index)
      AtomicLoad(width, ty) => check.atomic_load(width, ty, target="AArch64")
      AtomicStore(width, ty) => check.atomic_store(width, ty, target="AArch64")
      AtomicRmw(width, ty, _) => {
        check.atomic_rmw(width, ty, target="AArch64")
        check.atomic_early_def("atomic RMW result must be an early definition")
      }
      AtomicCompareExchange(width, ty) =>
        check.atomic_compare_exchange(width, ty, target="AArch64")
      AtomicFence => check.shape([], [])
      SafepointMarker => check.safepoint_marker()
      PlatformCall(_, signature) | ReturnsTwicePlatformCall(_, signature) =>
        check.platform_call(
          signature, platform_call_layout, is_allocatable, platform_call_clobbers,
        )
      InternalCall(_, signature, plan) =>
        check.internal_call(signature, plan, indirect=false, is_allocatable, _ => {
          platform_call_clobbers()
        })
      InternalCallIndirect(signature, plan) =>
        check.internal_call(signature, plan, indirect=true, is_allocatable, _ => {
          platform_call_clobbers()
        })
      TailCallDirect(_, signature, plan) =>
        require_tail_call_plan(
          function,
          instruction,
          signature,
          plan,
          false,
          is_allocatable,
          platform_call_clobbers(),
        )
      TailCallIndirect(signature, plan) =>
        require_tail_call_plan(
          function,
          instruction,
          signature,
          plan,
          true,
          is_allocatable,
          platform_call_clobbers(),
        )
      Jump => check.shape([], [], successors=1)
      BranchNonZero(width) =>
        check.shape([integer_type(width)], [], successors=2)
      BranchCompare(width, _) =>
        check.shape(
          [integer_type(width), integer_type(width)],
          [],
          successors=2,
        )
      BranchCompareImmediate(width, _, bits) => {
        let ty = integer_type(width)
        if add_sub_immediate_shift(bits) is None {
          raise InvalidInstruction(
            instruction~,
            message="branch comparison immediate cannot be encoded",
          )
        }
        check.shape([ty], [], successors=2)
      }
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
fn abi_materialization(inst : AArch64Inst) -> @vcode.AbiMaterialization {
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
