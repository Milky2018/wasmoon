///|
fn lower_direct_operation(
  context : LoweringContext,
  builder : @vcode.CheckedBuilder[AArch64Inst],
  block : @vcode.Block,
  block_index : Int32,
  instruction_index : Int32,
  operation : @lowering.Operation,
  operands : Array[@vcode.Value],
  operand_types : Array[@native.ValueType],
  result_types : Array[@native.ValueType],
  roots : Array[@vcode.Value],
  source_location : @native.SourceLocation?,
  stack_map : @native.StackMapMetadata?,
  stack_object : (@native.StackObject) -> AArch64StackObject,
) -> Array[@vcode.Value] raise AArch64LowerError {
  let site = @vcode.DirectOperationSource::new(
    source_location,
    stack_map,
    roots,
    operation.semantics(),
  )
  if operation is StoreRepeated64(offset, count, bits) {
    append_body(
      builder,
      block,
      StoreRepeated64(offset, count, bits),
      [@vcode.Input::any(operands[0]).with_timing(Late)],
      [
        @vcode.Output::any(Ptr64).with_timing(Early),
        @vcode.Output::any(I64).with_timing(Early),
        @vcode.Output::any(I64).with_timing(Early),
      ],
      site.metadata(),
    )
    |> ignore
    return []
  }
  if operation is (IntMultiplyAdd | IntMultiplySubtract) {
    guard optional_gpr_width(result_types.get(0)) is Some(width) else {
      raise UnsupportedOperation(block_index~, instruction_index~, operation~)
    }
    return append_unconstrained_body(
      builder,
      block,
      if operation is IntMultiplySubtract {
        IntMultiplySubtract(width)
      } else {
        IntMultiplyAdd(width)
      },
      operands,
      result_types,
      site.metadata(),
    )
  }
  if operation is IntExtractBits(start, field_bits) {
    guard optional_gpr_width(result_types.get(0)) is Some(width) else {
      raise UnsupportedOperation(block_index~, instruction_index~, operation~)
    }
    return append_unconstrained_body(
      builder,
      block,
      IntExtractBits(width, start, field_bits),
      operands,
      result_types,
      site.metadata(),
    )
  }
  if operation is IntLowBitsShiftLeft(field_bits, amount) {
    guard optional_gpr_width(result_types.get(0)) is Some(width) else {
      raise UnsupportedOperation(block_index~, instruction_index~, operation~)
    }
    return append_unconstrained_body(
      builder,
      block,
      IntLowBitsShiftLeft(width, field_bits, amount),
      operands,
      result_types,
      site.metadata(),
    )
  }
  if operation is (IntAddShiftedLeft(amount) | IntAddShiftedRight(amount)) {
    guard optional_gpr_width(result_types.get(0)) is Some(width) else {
      raise UnsupportedOperation(block_index~, instruction_index~, operation~)
    }
    return append_unconstrained_body(
      builder,
      block,
      if operation is IntAddShiftedRight(_) {
        IntAddShiftedRight(width, amount)
      } else {
        IntAddShiftedLeft(width, amount)
      },
      operands,
      result_types,
      site.metadata(),
    )
  }
  if operation is IntShiftImmediate(binary, amount) {
    guard optional_gpr_width(result_types.get(0)) is Some(width) else {
      raise UnsupportedOperation(block_index~, instruction_index~, operation~)
    }
    let bit_width = if width == W32 { 32 } else { 64 }
    let selected = match binary {
      RotateLeft =>
        IntShiftImmediate(width, Ror, (bit_width - amount) % bit_width)
      _ =>
        match lower_shift(binary) {
          Some(shift) => IntShiftImmediate(width, shift, amount)
          None =>
            raise UnsupportedOperation(
              block_index~,
              instruction_index~,
              operation~,
            )
        }
    }
    return append_unconstrained_body(
      builder,
      block,
      selected,
      operands,
      result_types,
      site.metadata(),
    )
  }
  if operation is IntCompareImmediate(comparison, bits) {
    guard optional_gpr_width(operand_types.get(0)) is Some(width) else {
      raise UnsupportedOperation(block_index~, instruction_index~, operation~)
    }
    let bits = if width == W32 { bits & 0xFFFFFFFFUL } else { bits }
    if add_sub_immediate_shift(bits) is Some(_) {
      return append_unconstrained_body(
        builder,
        block,
        CompareSetImmediate(width, @vcode.select_condition(comparison), bits),
        operands,
        result_types,
        site.metadata(),
      )
    }
    let constant = append_body(
        builder,
        block,
        LoadConstant(width, bits),
        [],
        [@vcode.Output::any(operand_types[0])],
        @vcode.InstructionMetadata::empty(),
      )[0]
    return append_unconstrained_body(
      builder,
      block,
      CompareSet(width, @vcode.select_condition(comparison)),
      [operands[0], constant],
      result_types,
      site.metadata(),
    )
  }
  if operation is IntBinaryImmediate(binary, bits) {
    guard optional_gpr_width(result_types.get(0)) is Some(width) else {
      raise UnsupportedOperation(block_index~, instruction_index~, operation~)
    }
    let bits = if width == W32 { bits & 0xFFFFFFFFUL } else { bits }
    // Add/sub wrap at the operand width; negate the constant at that width.
    let negated_bits = if width == W32 {
      (0UL - bits) & 0xFFFFFFFFUL
    } else {
      0UL - bits
    }
    let selected : AArch64Inst? = match binary {
      UnsignedRem if bits > 1UL && (bits & (bits - 1UL)) == 0UL =>
        Some(IntBinaryImmediate(width, And, bits - 1UL))
      Mul if bits > 0UL && (bits & (bits - 1UL)) == 0UL =>
        Some(IntShiftImmediate(width, Lsl, bits.ctz()))
      _ =>
        match lower_binary(binary) {
          Some(lowered) if valid_int_binary_immediate(width, lowered, bits) =>
            Some(IntBinaryImmediate(width, lowered, bits))
          Some(Add) if valid_int_binary_immediate(width, Sub, negated_bits) =>
            Some(IntBinaryImmediate(width, Sub, negated_bits))
          Some(Sub) if valid_int_binary_immediate(width, Add, negated_bits) =>
            Some(IntBinaryImmediate(width, Add, negated_bits))
          _ => None
        }
    }
    if selected is None {
      guard lower_binary(binary) is Some(lowered) else {
        raise UnsupportedOperation(block_index~, instruction_index~, operation~)
      }
      let constant = append_body(
          builder,
          block,
          LoadConstant(width, bits),
          [],
          [@vcode.Output::any(result_types[0])],
          @vcode.InstructionMetadata::empty(),
        )[0]
      return append_unconstrained_body(
        builder,
        block,
        IntBinary(width, lowered),
        [operands[0], constant],
        result_types,
        site.metadata(),
      )
    }
    return append_unconstrained_body(
      builder,
      block,
      selected.unwrap(),
      operands,
      result_types,
      site.metadata(),
    )
  }
  if operation is Call(call) {
    let metadata = site.metadata()
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
    return results
  }
  if operation is IntBinary(binary) &&
    binary is (SignedDiv | UnsignedDiv | SignedRem | UnsignedRem) {
    guard optional_gpr_width(result_types.get(0)) is Some(width) else {
      raise UnsupportedOperation(block_index~, instruction_index~, operation~)
    }
    append_body(
      builder,
      block,
      TrapIfZero(width),
      [@vcode.Input::any(operands[1])],
      [],
      site.metadata(trap=IntegerDivisionByZero),
    )
    |> ignore
    if binary == SignedDiv {
      append_unconstrained_body(
        builder,
        block,
        TrapIfSignedDivOverflow(width),
        operands,
        [],
        site.metadata(trap=IntegerOverflow),
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
    let results = append_unconstrained_body(
      builder,
      block,
      selected,
      operands,
      result_types,
      site.metadata(),
    )
    return results
  }
  if operation is Convert(FloatToInt(source, result, signedness, mode)) {
    if mode == Trapping {
      builder.append_float_to_int_checks(
        block,
        operands[0],
        source,
        result,
        signedness,
        site,
        (ty, bits) => LoadFloatConstant(ty, bits),
        ty => TrapIfFloat(ty, Unordered),
        (ty, inclusive) => {
          TrapIfFloat(ty, if inclusive { LessOrEqual } else { LessThan })
        },
        ty => TrapIfFloat(ty, GreaterOrEqual),
      ) catch {
        error => raise BuildFailure(cause=error)
      }
    }
    let results = append_unconstrained_body(
      builder,
      block,
      Convert(FloatToInt(source, result, signedness)),
      operands,
      result_types,
      site.metadata(),
    )
    return results
  }
  if operation is IntUnary(CountTrailingZeros) {
    guard optional_gpr_width(result_types.get(0)) is Some(width) else {
      raise UnsupportedOperation(block_index~, instruction_index~, operation~)
    }
    let reversed = append_unconstrained_body(
        builder,
        block,
        IntUnary(width, Rbit),
        operands,
        result_types,
        @vcode.InstructionMetadata::empty(),
      )[0]
    let results = append_unconstrained_body(
      builder,
      block,
      IntUnary(width, Clz),
      [reversed],
      result_types,
      site.metadata(),
    )
    return results
  }
  if operation is IntBinary(RotateLeft) {
    guard optional_gpr_width(result_types.get(0)) is Some(width) else {
      raise UnsupportedOperation(block_index~, instruction_index~, operation~)
    }
    let negated_shift = append_unconstrained_body(
        builder,
        block,
        IntUnary(width, Neg),
        [operands[1]],
        result_types,
        @vcode.InstructionMetadata::empty(),
      )[0]
    let results = append_unconstrained_body(
      builder,
      block,
      IntShiftRegister(width, Ror),
      [operands[0], negated_shift],
      result_types,
      site.metadata(),
    )
    return results
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
            site.metadata()
          } else {
            @vcode.InstructionMetadata::empty()
          },
        )[0]
    }
    return [current]
  }
  if operation is Vector(ReplaceLane(lane, index)) {
    let results = append_body(
      builder,
      block,
      VectorReplaceLane(lane, index),
      operands.map(@vcode.Input::any),
      [@vcode.Output::tied(V128, 0)],
      site.metadata(),
    )
    return results
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
        site.metadata(),
      )[0]
    return [result]
  }
  if operation is LoadIndexed(spec, shift) {
    if spec.width == W128 {
      let address = append_body(
          builder,
          block,
          AddAddressUxtw(shift),
          [@vcode.Input::any(operands[0]), @vcode.Input::any(operands[1])],
          [@vcode.Output::any(Ptr64)],
          @vcode.InstructionMetadata::empty(),
        )[0]
      return append_unconstrained_body(
        builder,
        block,
        VectorLoad128(spec.offset),
        [address],
        result_types,
        site.metadata(trap?=spec.trap),
      )
    }
    let selected = if spec.offset == 0UL {
      ScalarLoadUxtw(spec.width, spec.extension, spec.result_type, shift)
    } else {
      let address = append_body(
          builder,
          block,
          AddAddressUxtw(shift),
          [@vcode.Input::any(operands[0]), @vcode.Input::any(operands[1])],
          [@vcode.Output::any(Ptr64)],
          @vcode.InstructionMetadata::empty(),
        )[0]
      return append_unconstrained_body(
        builder,
        block,
        ScalarLoad(spec.width, spec.extension, spec.result_type, spec.offset),
        [address],
        result_types,
        site.metadata(trap?=spec.trap),
      )
    }
    return append_unconstrained_body(
      builder,
      block,
      selected,
      operands,
      result_types,
      site.metadata(trap?=spec.trap),
    )
  }
  if operation is StoreIndexed(spec, shift) {
    if spec.width == W128 {
      let address = append_body(
          builder,
          block,
          AddAddressUxtw(shift),
          [@vcode.Input::any(operands[0]), @vcode.Input::any(operands[1])],
          [@vcode.Output::any(Ptr64)],
          @vcode.InstructionMetadata::empty(),
        )[0]
      return append_body(
        builder,
        block,
        VectorStore128(spec.offset),
        [@vcode.Input::any(address), @vcode.Input::any(operands[2])],
        [],
        site.metadata(trap?=spec.trap),
      )
    }
    if spec.offset == 0UL {
      return append_unconstrained_body(
        builder,
        block,
        ScalarStoreUxtw(spec.width, spec.value_type, shift),
        operands,
        [],
        site.metadata(trap?=spec.trap),
      )
    }
    let address = append_body(
        builder,
        block,
        AddAddressUxtw(shift),
        [@vcode.Input::any(operands[0]), @vcode.Input::any(operands[1])],
        [@vcode.Output::any(Ptr64)],
        @vcode.InstructionMetadata::empty(),
      )[0]
    return append_body(
      builder,
      block,
      ScalarStore(spec.width, spec.value_type, spec.offset),
      [@vcode.Input::any(address), @vcode.Input::any(operands[2])],
      [],
      site.metadata(trap?=spec.trap),
    )
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
    StackAddress(object) => Some(StackAddress(stack_object(object)))
    F32Const(bits) => Some(LoadFloatConstant(F32, bits.to_uint64()))
    F64Const(bits) => Some(LoadFloatConstant(F64, bits))
    Copy if result_types.length() == 1 => Some(Move(result_types[0]))
    GcRefAddress => Some(CarrierMove(GcRef64, Ptr64))
    GcRefFromBits => Some(CarrierMove(I64, GcRef64))
    Select if result_types.get(0) is Some(V128) => Some(VectorSelect)
    Select if result_types.get(0) is Some(ty) => Some(Select(ty))
    SpectreGuard => Some(SpectreGuard)
    Vector(Splat(lane)) => Some(VectorSplat(lane))
    Vector(ExtractLane(lane, index, extension)) =>
      Some(VectorExtractLane(lane, index, extension))
    Vector(Shuffle(mask)) => Some(VectorShuffle(mask))
    Vector(Swizzle) => Some(VectorSwizzle)
    Vector(Bitwise(operation)) => Some(VectorBitwise(operation))
    Vector(IntUnary(lane, operation)) => Some(VectorIntUnary(lane, operation))
    Vector(IntBinary(lane, operation)) => Some(VectorIntBinary(lane, operation))
    Vector(IntShift(lane, operation)) => Some(VectorIntShift(lane, operation))
    Vector(IntCompare(lane, comparison)) =>
      Some(VectorIntCompare(lane, comparison))
    Vector(Convert(operation)) =>
      @vcode.select_vector_conversion(operation).map(conversion => {
        VectorConvert(conversion)
      })
    Vector(Predicate(predicate)) => Some(VectorPredicate(predicate))
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
      let operand_type = operand_types.get(0)
      match operand_type {
        Some(Ptr64) =>
          Some(
            ReferenceCompareSet(
              Ptr64,
              @vcode.select_reference_condition(comparison),
            ),
          )
        Some(GcRef64) =>
          Some(
            ReferenceCompareSet(
              GcRef64,
              @vcode.select_reference_condition(comparison),
            ),
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
      match optional_gpr_width(result_types.get(0)) {
        Some(width) =>
          match lower_binary(binary) {
            Some(binary) => Some(IntBinary(width, binary))
            None =>
              match lower_shift(binary) {
                Some(shift) => Some(IntShiftRegister(width, shift))
                None => None
              }
          }
        None => None
      }
    IntCompare(comparison) => {
      let operand_type = operand_types.get(0)
      match optional_gpr_width(operand_type) {
        Some(width) =>
          Some(CompareSet(width, @vcode.select_condition(comparison)))
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
      match result_types.get(0) {
        Some(F32) => Some(FloatUnary(F32, unary))
        Some(F64) => Some(FloatUnary(F64, unary))
        _ => None
      }
    FloatBinary(binary) =>
      match result_types.get(0) {
        Some(F32) => Some(FloatBinary(F32, binary))
        Some(F64) => Some(FloatBinary(F64, binary))
        _ => None
      }
    FloatTernary(ternary) =>
      match result_types.get(0) {
        Some(F32) => Some(FloatTernary(F32, ternary))
        Some(F64) => Some(FloatTernary(F64, ternary))
        _ => None
      }
    FloatCompare(comparison) => {
      let operand_type = operand_types.get(0)
      match operand_type {
        Some(F32) => Some(FloatCompareSet(F32, comparison))
        Some(F64) => Some(FloatCompareSet(F64, comparison))
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
  let selected_operands = builder.materialize_atomic_address(
    block,
    operation,
    operands,
    bits => LoadConstant(W64, bits),
    AddAddress,
  ) catch {
    error => raise BuildFailure(cause=error)
  }
  let metadata = site.selected_metadata(operation)
  let results = match operation {
    AtomicRmw(_, _) | AtomicCompareExchange(_) =>
      append_body(
        builder,
        block,
        selected,
        selected_operands.map(@vcode.Input::any),
        result_types.map(ty => @vcode.Output::any(ty).with_timing(Early)),
        metadata,
      )
    _ =>
      append_unconstrained_body(
        builder, block, selected, selected_operands, result_types, metadata,
      )
  }
  results
}

///|
pub struct DirectLoweringSession {
  priv state : @vcode.DirectLoweringState[AArch64Inst, AArch64LowerError]
}

///|
fn append_placeholder(
  builder : @vcode.CheckedBuilder[AArch64Inst],
  block : @vcode.Block,
  ty : @native.ValueType,
) -> @vcode.Value {
  let instruction = match ty {
    I32 => LoadConstant(W32, 0UL)
    I64 => LoadConstant(W64, 0UL)
    F32 | F64 => LoadFloatConstant(ty, 0UL)
    V128 => LoadVectorConstant(0UL, 0UL)
    Ptr64 | GcRef64 => LoadNull(ty)
  }
  (append_body(
    builder,
    block,
    instruction,
    [],
    [@vcode.Output::any(ty)],
    @vcode.InstructionMetadata::empty(),
  ) catch {
    _ =>
      abort(
        "aarch64 direct lowering could not materialize an error placeholder",
      )
  })[0]
}

///|
fn lower_direct_parameters(
  builder : @vcode.CheckedBuilder[AArch64Inst],
  context : LoweringContext,
  protocol : @native.CallProtocol,
  signature : @native.Signature,
) -> (Array[@vcode.Value], @vcode.Value?) raise AArch64LowerError {
  let (arguments, result_area) = match protocol {
    Platform => (platform_call_layout(signature.params).arguments, None)
    Internal => {
      let abi = context.internal_abi
      let plan = abi.call_plan(signature) catch {
        error => raise UnsupportedAbi(message=error.to_string())
      }
      let result_area = if plan.result_area_size > 0 {
        Some(abi.result_area_argument)
      } else {
        None
      }
      (plan.arguments, result_area)
    }
  }
  @vcode.materialize_entry_arguments(
    builder,
    signature.params,
    arguments,
    result_area,
    (ty, reg) => IncomingReg(ty, reg),
    (ty, offset) => IncomingStack(ty, offset),
    reg => IncomingResultArea(reg),
    is_allocatable,
  ) catch {
    error => raise BuildFailure(cause=error)
  }
}

///|
pub fn DirectLoweringSession::new(
  name : String,
  protocol : @native.CallProtocol,
  parameter_types : Array[@native.ValueType],
  result_types : Array[@native.ValueType],
  context : LoweringContext,
  on_event~ : (@vcode.TargetCompileEvent) -> Unit = fn(_) { () },
) -> DirectLoweringSession raise AArch64LowerError {
  on_event(TargetConstructionStarted)
  let signature = @native.Signature::new(parameter_types, result_types)
  let builder : @vcode.CheckedBuilder[AArch64Inst] = @vcode.CheckedBuilder::new_with_protocol(
    name,
    protocol,
    signature.params,
    signature.results,
  )
  let (values, result_area) = lower_direct_parameters(
    builder, context, protocol, signature,
  )
  {
    state: @vcode.DirectLoweringState::new(
      builder, context, protocol, signature, values, result_area, on_event,
    ),
  }
}

///|
fn DirectLoweringSession::emit(
  self : DirectLoweringSession,
  block_id : Int32,
  operation : @lowering.Operation,
  operand_ids : Array[Int32],
  result_types : Array[@native.ValueType],
  source : @native.SourceLocation?,
  root_ids : Array[Int32],
  stack_map : @native.StackMapMetadata?,
) -> Array[Int32] {
  let block = self.state.block(block_id)
  if operation is Convert(Bitcast(from, to)) &&
    self.state.alias_word_bitcast(operand_ids, result_types, from, to)
    is Some(id) {
    return [id]
  }
  let (operands, operand_types, roots) = self.state.instruction_operands(
    operand_ids, root_ids,
  )
  let results = if self.state.first_error() is Some(_) {
    result_types.map(ty => append_placeholder(self.state.builder, block, ty))
  } else {
    lower_direct_operation(
      self.state.context,
      self.state.builder,
      block,
      block_id,
      self.state.instruction_index(),
      operation,
      operands,
      operand_types,
      result_types,
      roots,
      source,
      stack_map,
      object => {
        let (size, alignment) = self.state.stack_object(object.id)
        AArch64StackObject::new(object.id, size, alignment)
      },
    ) catch {
      error => {
        self.state.record_error(error)
        result_types.map(ty => append_placeholder(self.state.builder, block, ty))
      }
    }
  }
  self.state.record_results(results, result_types)
}

///|
fn DirectLoweringSession::lower_return_values(
  self : DirectLoweringSession,
  block : @vcode.Block,
  values : Array[@vcode.Value],
) -> Unit raise AArch64LowerError {
  self.state.materialize_return_values(
    block,
    values,
    platform_result_registers,
    (ty, reg) => OutgoingReg(ty, reg),
    (ty, offset) => OutgoingAreaResult(ty, offset),
  ) catch {
    UnsupportedAbi(message) => raise UnsupportedAbi(message~)
    BuildFailure(error) => raise BuildFailure(cause=error)
  }
}

///|
fn DirectLoweringSession::edge(
  self : DirectLoweringSession,
  block : @vcode.Block,
  target : Int32,
  ids : Array[Int32],
) -> @vcode.Edge raise AArch64LowerError {
  self.state.edge(block, target, ids, ty => Move(ty)) catch {
    error => raise BuildFailure(cause=error)
  }
}

///|
fn DirectLoweringSession::terminate(
  self : DirectLoweringSession,
  block_id : Int32,
  terminator : @lowering.TargetTerminator,
  metadata : @lowering.TargetTerminatorMetadata,
) -> Unit {
  let block = self.state.block(block_id)
  let ordinary_metadata = self.state.terminator_metadata(
    metadata.source,
    metadata.live_gc_roots,
  )
  let action : () -> Unit raise AArch64LowerError = fn() raise AArch64LowerError {
    match terminator {
      Jump(target, arguments) =>
        set_terminator(
          self.state.builder,
          block,
          Jump,
          [],
          [self.edge(block, target, arguments)],
          ordinary_metadata,
        )
      Branch(
        condition,
        true_target,
        true_arguments,
        false_target,
        false_arguments
      ) =>
        set_terminator(
          self.state.builder,
          block,
          BranchNonZero(W32),
          [@vcode.Input::any(self.state.target_value(condition))],
          [
            self.edge(block, true_target, true_arguments),
            self.edge(block, false_target, false_arguments),
          ],
          ordinary_metadata,
        )
      BranchIntCompare(
        comparison,
        left,
        right,
        true_target,
        true_arguments,
        false_target,
        false_arguments
      ) => {
        let width : GprWidth = if self.state.value_type(left) == I32 {
          W32
        } else {
          W64
        }
        set_terminator(
          self.state.builder,
          block,
          BranchCompare(width, @vcode.select_condition(comparison)),
          [
            @vcode.Input::any(self.state.target_value(left)),
            @vcode.Input::any(self.state.target_value(right)),
          ],
          [
            self.edge(block, true_target, true_arguments),
            self.edge(block, false_target, false_arguments),
          ],
          ordinary_metadata,
        )
      }
      BranchIntCompareImmediate(
        comparison,
        input,
        bits,
        true_target,
        true_arguments,
        false_target,
        false_arguments
      ) => {
        let width : GprWidth = if self.state.value_type(input) == I32 {
          W32
        } else {
          W64
        }
        let bits = if width == W32 { bits & 0xFFFFFFFFUL } else { bits }
        let mut first_target = true_target
        let mut first_arguments = true_arguments
        let mut second_target = false_target
        let mut second_arguments = false_arguments
        let (selected, inputs) = if bits == 0UL &&
          (comparison == Equal || comparison == NotEqual) {
          if comparison == Equal {
            first_target = false_target
            first_arguments = false_arguments
            second_target = true_target
            second_arguments = true_arguments
          }
          (
            BranchNonZero(width),
            [@vcode.Input::any(self.state.target_value(input))],
          )
        } else if add_sub_immediate_shift(bits) is Some(_) {
          (
            BranchCompareImmediate(
              width,
              @vcode.select_condition(comparison),
              bits,
            ),
            [@vcode.Input::any(self.state.target_value(input))],
          )
        } else {
          let constant = append_body(
              self.state.builder,
              block,
              LoadConstant(width, bits),
              [],
              [@vcode.Output::any(self.state.value_type(input))],
              @vcode.InstructionMetadata::empty(),
            )[0]
          (
            BranchCompare(width, @vcode.select_condition(comparison)),
            [
              @vcode.Input::any(self.state.target_value(input)),
              @vcode.Input::any(constant),
            ],
          )
        }
        set_terminator(
          self.state.builder,
          block,
          selected,
          inputs,
          [
            self.edge(block, first_target, first_arguments),
            self.edge(block, second_target, second_arguments),
          ],
          ordinary_metadata,
        )
      }
      Switch(index, cases, default_target, default_arguments) => {
        let width : GprWidth = if self.state.value_type(index) == I32 {
          W32
        } else {
          W64
        }
        let (keys, successors) = self.state.switch_targets(
          block,
          cases,
          default_target,
          default_arguments,
          ty => Move(ty),
        ) catch {
          error => raise BuildFailure(cause=error)
        }
        set_terminator(
          self.state.builder,
          block,
          Switch(width, keys),
          [@vcode.Input::any(self.state.target_value(index))],
          successors,
          ordinary_metadata,
        )
      }
      Return(values) => {
        self.lower_return_values(block, self.state.target_values(values))
        set_terminator(
          self.state.builder,
          block,
          Return,
          [],
          [],
          ordinary_metadata,
        )
      }
      TailCall(call, operands) =>
        self.terminate_tail_call(
          block,
          call,
          self.state.target_values(operands),
          ordinary_metadata,
        )
      NoReturnCall(call, operands) => {
        let operands = self.state.target_values(operands)
        let call_metadata = direct_source_metadata(
          metadata.source,
          None,
          ordinary_metadata.live_gc_roots,
          call.behavior.semantics(),
        )
        match call.protocol {
          Platform =>
            lower_direct_platform_call(
              self.state.builder,
              block,
              call,
              operands,
              [],
              call_metadata,
            )
            |> ignore
          Internal =>
            lower_internal_call(
              self.state.context,
              self.state.builder,
              block,
              call,
              operands,
              [],
              call_metadata,
            )
            |> ignore
        }
        set_terminator(
          self.state.builder,
          block,
          Trap(Unreachable),
          [],
          [],
          @vcode.InstructionMetadata::new(
            source?=metadata.source,
            trap=Unreachable,
          ),
        )
      }
      Trap(reason) =>
        set_terminator(
          self.state.builder,
          block,
          Trap(reason),
          [],
          [],
          @vcode.InstructionMetadata::new(source?=metadata.source, trap=reason),
        )
    }
  }
  action() catch {
    error => {
      self.state.record_error(error)
      set_terminator(
        self.state.builder,
        block,
        Trap(Unreachable),
        [],
        [],
        @vcode.InstructionMetadata::new(
          source?=metadata.source,
          trap=Unreachable,
        ),
      ) catch {
        _ => abort("aarch64 direct lowering could not seal an error block")
      }
    }
  }
}

///|
fn DirectLoweringSession::terminate_tail_call(
  self : DirectLoweringSession,
  block : @vcode.Block,
  call : @native.NativeCall,
  operands : Array[@vcode.Value],
  metadata : @vcode.InstructionMetadata,
) -> Unit raise AArch64LowerError {
  let operands = self.state.builder.materialize_abi_words(
    block,
    operands,
    call.signature.params,
    ty => Move(ty),
    operand_start=if call.callee is Indirect { 1 } else { 0 },
  ) catch {
    error => raise BuildFailure(cause=error)
  }
  let (plan, inputs) = self.state.tail_call_inputs(
    call, operands, is_allocatable,
  ) catch {
    UnsupportedAbi(message) => raise UnsupportedAbi(message~)
    BuildFailure(cause) => raise BuildFailure(cause~)
  }
  let target = match call.callee {
    Internal(symbol) => TailCallDirect(symbol, call.signature, plan)
    Indirect => TailCallIndirect(call.signature, plan)
    External(_) => abort("external tail call rejected above")
  }
  let metadata = direct_source_metadata(
    metadata.source,
    None,
    metadata.live_gc_roots,
    call.behavior.semantics(),
  )
  set_terminator(
    self.state.builder,
    block,
    target,
    inputs,
    [],
    metadata,
    clobbers=platform_call_clobbers(),
  )
}

///|
pub fn DirectLoweringSession::sink(
  self : DirectLoweringSession,
) -> @lowering.TargetSink {
  @lowering.TargetSink::new(
    fn() { Array::makei(self.state.signature.params.length(), index => index) },
    fn() { 0 },
    fn(types) { self.state.create_block(types) },
    fn(size, alignment) { self.state.create_stack_object(size, alignment) },
    fn(block) { self.state.switch_to_block(block) },
    fn(block, operation, operands, results, source, roots, stack_map) {
      self.emit(block, operation, operands, results, source, roots, stack_map)
    },
    fn(block, terminator, metadata) {
      self.terminate(block, terminator, metadata)
    },
    fn() { self.state.finish_construction(error => BuildFailure(cause=error)) },
    folds_unsigned_index_into_memory=true,
    supports_int_binary_immediate=fn(operation, ty, bits) {
      guard optional_gpr_width(Some(ty)) is Some(width) else { return false }
      match operation {
        Mul => bits > 0UL && (bits & (bits - 1UL)) == 0UL
        UnsignedRem => bits > 1UL && (bits & (bits - 1UL)) == 0UL
        _ => {
          guard lower_binary(operation) is Some(binary) else { return false }
          let negated = if width == W32 {
            (0UL - bits) & 0xFFFFFFFFUL
          } else {
            0UL - bits
          }
          valid_int_binary_immediate(width, binary, bits) ||
          (binary == Add && valid_int_binary_immediate(width, Sub, negated)) ||
          (binary == Sub && valid_int_binary_immediate(width, Add, negated))
        }
      }
    },
    supports_int_compare_immediate=fn(ty, bits) {
      (ty == I32 || ty == I64) && add_sub_immediate_shift(bits) is Some(_)
    },
  )
}

///|
/// Finish direct selection and return the VCode consumed by target compilation.
///
/// `verify_selected=false` is reserved for compiler-owned construction paths
/// covered by strict validation in CI. Public callers should keep the default.
pub fn DirectLoweringSession::finish_selected(
  self : DirectLoweringSession,
  verify_selected~ : Bool = true,
) -> SelectedFunction raise AArch64LowerError {
  self.state.finish_construction(error => BuildFailure(cause=error))
  if self.state.first_error() is Some(error) {
    raise error
  }
  guard self.state.constructed_function() is Some(function) else {
    raise UnsupportedAbi(message="direct lowering did not construct VCode")
  }
  let constructed : ConstructedFunction = { function, }
  if verify_selected {
    validate_constructed(constructed, self.state.on_event)
  }
  (self.state.on_event)(TargetSealingStarted)
  (self.state.on_event)(TargetSelectionFinished)
  { constructed, }
}
