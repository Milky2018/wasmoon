///|
fn direct_source_metadata(
  source_location : @native.SourceLocation?,
  stack_map : @native.StackMapMetadata?,
  values : Array[@vcode.Value],
  semantics : @native.OperationSemantics,
  trap? : @native.TrapReason,
) -> @vcode.InstructionMetadata {
  let safepoint : @native.SafepointKind? = match
    (semantics.gc_safepoint, semantics.cancellation_safepoint) {
    (true, true) => Some(GcAndCancellation)
    (true, false) => Some(Gc)
    (false, true) => Some(Cancellation)
    (false, false) => None
  }
  match source_location {
    Some(location) =>
      @vcode.InstructionMetadata::new(
        source=location,
        trap?,
        safepoint?,
        live_gc_roots=values,
        stack_map?,
      )
    None =>
      @vcode.InstructionMetadata::new(
        trap?,
        safepoint?,
        live_gc_roots=values,
        stack_map?,
      )
  }
}

///|
fn lower_direct_operation(
  context : LoweringContext,
  builder : @vcode.CheckedBuilder[X64Inst],
  block : @vcode.Block,
  block_index : Int,
  instruction_index : Int,
  operation : @lowering.Operation,
  operands : Array[@vcode.Value],
  operand_types : Array[@native.ValueType],
  result_types : Array[@native.ValueType],
  roots : Array[@vcode.Value],
  source_location : @native.SourceLocation?,
  stack_map : @native.StackMapMetadata?,
  stack_object : (@native.StackObject) -> X64StackObject,
) -> Array[@vcode.Value] raise X64LowerError {
  if operation is IntMultiplyAdd {
    guard optional_gpr_width(result_types.get(0)) is Some(width) else {
      raise UnsupportedOperation(block_index~, instruction_index~, operation~)
    }
    let product = append_body(
        builder,
        block,
        IntBinary(width, Mul),
        [@vcode.Input::any(operands[1]), @vcode.Input::any(operands[2])],
        result_types.map(@vcode.Output::any),
        @vcode.InstructionMetadata::empty(),
      )[0]
    return append_body(
      builder,
      block,
      IntBinary(width, Add),
      [@vcode.Input::any(operands[0]), @vcode.Input::any(product)],
      result_types.map(@vcode.Output::any),
      direct_source_metadata(
        source_location,
        stack_map,
        roots,
        operation.semantics(),
      ),
    )
  }
  if operation is IntAddShiftedLeft(amount) {
    guard optional_gpr_width(result_types.get(0)) is Some(width) else {
      raise UnsupportedOperation(block_index~, instruction_index~, operation~)
    }
    let constant = append_body(
        builder,
        block,
        LoadConstant(width, amount.to_uint64()),
        [],
        [@vcode.Output::any(result_types[0])],
        @vcode.InstructionMetadata::empty(),
      )[0]
    let shifted = append_body(
        builder,
        block,
        IntBinary(width, Lsl),
        [@vcode.Input::any(operands[1]), @vcode.Input::any(constant)],
        result_types.map(@vcode.Output::any),
        @vcode.InstructionMetadata::empty(),
      )[0]
    return append_body(
      builder,
      block,
      IntBinary(width, Add),
      [@vcode.Input::any(operands[0]), @vcode.Input::any(shifted)],
      result_types.map(@vcode.Output::any),
      direct_source_metadata(
        source_location,
        stack_map,
        roots,
        operation.semantics(),
      ),
    )
  }
  if operation is IntShiftImmediate(binary, amount) {
    guard optional_gpr_width(result_types.get(0)) is Some(width) else {
      raise UnsupportedOperation(block_index~, instruction_index~, operation~)
    }
    let bit_width = if width == W32 { 32 } else { 64 }
    let (selected, selected_amount) = match binary {
      RotateLeft => (Ror, (bit_width - amount) % bit_width)
      _ =>
        match lower_binary(binary) {
          Some(selected) => (selected, amount)
          None =>
            raise UnsupportedOperation(
              block_index~,
              instruction_index~,
              operation~,
            )
        }
    }
    let constant = append_body(
        builder,
        block,
        LoadConstant(width, selected_amount.to_uint64()),
        [],
        [@vcode.Output::any(result_types[0])],
        @vcode.InstructionMetadata::empty(),
      )[0]
    return append_body(
      builder,
      block,
      IntBinary(width, selected),
      [@vcode.Input::any(operands[0]), @vcode.Input::any(constant)],
      result_types.map(@vcode.Output::any),
      direct_source_metadata(
        source_location,
        stack_map,
        roots,
        operation.semantics(),
      ),
    )
  }
  if operation is IntBinaryImmediate(binary, bits) {
    guard optional_gpr_width(result_types.get(0)) is Some(width) else {
      raise UnsupportedOperation(block_index~, instruction_index~, operation~)
    }
    let (selected, selected_bits) = match binary {
      UnsignedRem if bits > 1UL && (bits & (bits - 1UL)) == 0UL =>
        (And, bits - 1UL)
      _ =>
        match lower_binary(binary) {
          Some(selected) => (selected, bits)
          None =>
            raise UnsupportedOperation(
              block_index~,
              instruction_index~,
              operation~,
            )
        }
    }
    let constant = append_body(
        builder,
        block,
        LoadConstant(width, selected_bits),
        [],
        [@vcode.Output::any(result_types[0])],
        @vcode.InstructionMetadata::empty(),
      )[0]
    return append_body(
      builder,
      block,
      IntBinary(width, selected),
      [@vcode.Input::any(operands[0]), @vcode.Input::any(constant)],
      result_types.map(@vcode.Output::any),
      direct_source_metadata(
        source_location,
        stack_map,
        roots,
        operation.semantics(),
      ),
    )
  }
  if operation is Call(call) {
    let metadata = direct_source_metadata(
      source_location,
      stack_map,
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
      direct_source_metadata(
        source_location,
        stack_map,
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
        direct_source_metadata(
          source_location,
          stack_map,
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
    let accumulator = @vcode.PhysicalReg::new(0, Int)
    let high = @vcode.PhysicalReg::new(2, Int)
    let divisor = @vcode.PhysicalReg::new(11, Int)
    let inputs = [
      @vcode.Input::fixed(operands[0], accumulator),
      @vcode.Input::fixed(operands[1], divisor),
    ]
    // Clobbers come from `X64Inst::mandatory_clobbers`; only the result
    // placement differs between division and remainder.
    let outputs = match selected {
      IntBinary(_, Sdiv | Udiv) =>
        [@vcode.Output::fixed(result_types[0], accumulator)]
      IntRemainder(_, _) => [@vcode.Output::fixed(result_types[0], high)]
      _ => abort("selected checked integer operation is not division")
    }
    let results = append_body(
      builder,
      block,
      selected,
      inputs,
      outputs,
      direct_source_metadata(
        source_location,
        stack_map,
        roots,
        operation.semantics(),
      ),
    )
    return results
  }
  if operation is Convert(FloatToInt(source, result, signedness, mode)) {
    let source_type = float_value_type(source)
    if mode == Trapping {
      append_body(
        builder,
        block,
        TrapIfFloat(source_type, Unordered),
        [@vcode.Input::any(operands[0])],
        [],
        direct_source_metadata(
          source_location,
          stack_map,
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
      let lower_condition : X64FloatTrapCondition = if inclusive_minimum {
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
        direct_source_metadata(
          source_location,
          stack_map,
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
        direct_source_metadata(
          source_location,
          stack_map,
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
      Convert(
        if mode == Saturating {
          FloatToIntSaturating(source, result, signedness)
        } else {
          FloatToInt(source, result, signedness)
        },
      ),
      operands.map(@vcode.Input::any),
      result_types.map(@vcode.Output::any),
      direct_source_metadata(
        source_location,
        stack_map,
        roots,
        operation.semantics(),
      ),
    )
    return results
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
      direct_source_metadata(
        source_location,
        stack_map,
        roots,
        operation.semantics(),
      ),
    )
    return results
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
      direct_source_metadata(
        source_location,
        stack_map,
        roots,
        operation.semantics(),
      ),
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
            direct_source_metadata(
              source_location,
              stack_map,
              roots,
              operation.semantics(),
            )
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
      [@vcode.Output::any(V128)],
      direct_source_metadata(
        source_location,
        stack_map,
        roots,
        operation.semantics(),
      ),
    )
    return [results[0]]
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
        direct_source_metadata(
          source_location,
          stack_map,
          roots,
          operation.semantics(),
        ),
      )[0]
    return [result]
  }
  if operation is LoadIndexed(spec, shift) {
    let widened = append_body(
        builder,
        block,
        Convert(ExtendI32ToI64(Unsigned)),
        [@vcode.Input::any(operands[1])],
        [@vcode.Output::any(I64)],
        @vcode.InstructionMetadata::empty(),
      )[0]
    let scaled = if shift == 0 {
      widened
    } else {
      let amount = append_body(
          builder,
          block,
          LoadConstant(W64, shift.to_uint64()),
          [],
          [@vcode.Output::any(I64)],
          @vcode.InstructionMetadata::empty(),
        )[0]
      append_body(
        builder,
        block,
        IntBinary(W64, Lsl),
        [@vcode.Input::any(widened), @vcode.Input::any(amount)],
        [@vcode.Output::any(I64)],
        @vcode.InstructionMetadata::empty(),
      )[0]
    }
    let address = append_body(
        builder,
        block,
        AddAddress,
        [@vcode.Input::any(operands[0]), @vcode.Input::any(scaled)],
        [@vcode.Output::any(Ptr64)],
        @vcode.InstructionMetadata::empty(),
      )[0]
    return append_body(
      builder,
      block,
      if spec.width == W128 {
        VectorLoad128(spec.offset)
      } else {
        ScalarLoad(spec.width, spec.extension, spec.result_type, spec.offset)
      },
      [@vcode.Input::any(address)],
      result_types.map(@vcode.Output::any),
      direct_source_metadata(
        source_location,
        stack_map,
        roots,
        operation.semantics(),
        trap?=spec.trap,
      ),
    )
  }
  if operation is StoreIndexed(spec, shift) {
    let widened = append_body(
        builder,
        block,
        Convert(ExtendI32ToI64(Unsigned)),
        [@vcode.Input::any(operands[1])],
        [@vcode.Output::any(I64)],
        @vcode.InstructionMetadata::empty(),
      )[0]
    let scaled = if shift == 0 {
      widened
    } else {
      let amount = append_body(
          builder,
          block,
          LoadConstant(W64, shift.to_uint64()),
          [],
          [@vcode.Output::any(I64)],
          @vcode.InstructionMetadata::empty(),
        )[0]
      append_body(
        builder,
        block,
        IntBinary(W64, Lsl),
        [@vcode.Input::any(widened), @vcode.Input::any(amount)],
        [@vcode.Output::any(I64)],
        @vcode.InstructionMetadata::empty(),
      )[0]
    }
    let address = append_body(
        builder,
        block,
        AddAddress,
        [@vcode.Input::any(operands[0]), @vcode.Input::any(scaled)],
        [@vcode.Output::any(Ptr64)],
        @vcode.InstructionMetadata::empty(),
      )[0]
    return append_body(
      builder,
      block,
      if spec.width == W128 {
        VectorStore128(spec.offset)
      } else {
        ScalarStore(spec.width, spec.value_type, spec.offset)
      },
      [@vcode.Input::any(address), @vcode.Input::any(operands[2])],
      [],
      direct_source_metadata(
        source_location,
        stack_map,
        roots,
        operation.semantics(),
        trap?=spec.trap,
      ),
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
      let operand_type = operand_types.get(0)
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
      let operand_type = operand_types.get(0)
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
      let operand_type = operand_types.get(0)
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
  let accumulator = @vcode.PhysicalReg::new(0, Int)
  let high = @vcode.PhysicalReg::new(2, Int)
  let scratch = @vcode.PhysicalReg::new(11, Int)
  let inputs = match selected {
    IntHighMultiply(_, _) =>
      [
        @vcode.Input::fixed(selected_operands[0], accumulator),
        @vcode.Input::fixed(selected_operands[1], scratch),
      ]
    IntWithOverflow(_, Mul(_)) =>
      [
        @vcode.Input::fixed(selected_operands[0], accumulator),
        @vcode.Input::fixed(selected_operands[1], scratch),
      ]
    AtomicCompareExchange(_, _) =>
      [
        @vcode.Input::any(selected_operands[0]),
        @vcode.Input::fixed(selected_operands[1], accumulator),
        @vcode.Input::any(selected_operands[2]),
      ]
    AtomicRmw(_, _, And | Or | Xor) =>
      [
        @vcode.Input::fixed(selected_operands[0], scratch),
        @vcode.Input::fixed(
          selected_operands[1],
          @vcode.PhysicalReg::new(10, Int),
        ),
      ]
    AtomicStore(_, _) =>
      [
        @vcode.Input::any(selected_operands[0]),
        @vcode.Input::fixed(
          selected_operands[1],
          @vcode.PhysicalReg::new(10, Int),
        ),
      ]
    _ => selected_operands.map(@vcode.Input::any)
  }
  let outputs = match selected {
    IntHighMultiply(_, _) => [@vcode.Output::fixed(result_types[0], high)]
    IntWithOverflow(_, Mul(_)) =>
      [
        @vcode.Output::fixed(result_types[0], accumulator),
        @vcode.Output::any(result_types[1]),
      ]
    AtomicRmw(_, _, Add | Sub | Exchange) =>
      [@vcode.Output::any(result_types[0])]
    AtomicRmw(_, _, And | Or | Xor) =>
      [@vcode.Output::fixed(result_types[0], accumulator).with_timing(Early)]
    AtomicCompareExchange(_, _) =>
      [@vcode.Output::fixed(result_types[0], accumulator).with_timing(Early)]
    _ => result_types.map(@vcode.Output::any)
  }
  // Clobbers come from `X64Inst::mandatory_clobbers`.
  let results = append_body(
    builder,
    block,
    selected,
    inputs,
    outputs,
    direct_source_metadata(
      source_location,
      stack_map,
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
  results
}

///|
priv struct DirectStackObjectRequest {
  size : Int
  alignment : Int
}

///|
pub struct DirectLoweringSession {
  priv builder : @vcode.CheckedBuilder[X64Inst]
  priv context : LoweringContext
  priv protocol : @native.CallProtocol
  priv signature : @native.Signature
  priv values : Array[@vcode.Value]
  priv value_types : Array[@native.ValueType]
  priv blocks : Array[@vcode.Block]
  priv layout : Array[@vcode.Block]
  priv stack_objects : Array[DirectStackObjectRequest]
  priv result_area : @vcode.Value?
  priv mut instruction_index : Int
  priv mut first_error : X64LowerError?
  priv mut constructed : ConstructedFunction?
  priv on_event : (@vcode.TargetCompileEvent) -> Unit
}

///|
fn append_placeholder(
  builder : @vcode.CheckedBuilder[X64Inst],
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
    _ => abort("x64 direct lowering could not materialize an error placeholder")
  })[0]
}

///|
fn lower_direct_parameters(
  builder : @vcode.CheckedBuilder[X64Inst],
  context : LoweringContext,
  protocol : @native.CallProtocol,
  signature : @native.Signature,
) -> (Array[@vcode.Value], @vcode.Value?) raise X64LowerError {
  let entry = builder.entry_block()
  let layout = match protocol {
    Platform => platform_call_layout(signature.params)
    Internal =>
      context.internal_abi.call_layout(signature) catch {
        error => raise UnsupportedAbi(message=error.to_string())
      }
  }
  let values : Array[@vcode.Value] = []
  for index, ty in signature.params {
    let raw = builder.parameter(index) catch {
      error => raise BuildFailure(cause=error)
    }
    values.push(
      match layout.arguments[index] {
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
      },
    )
  }
  let result_area = if protocol == Internal {
    let plan = context.internal_abi.call_plan(signature) catch {
      error => raise UnsupportedAbi(message=error.to_string())
    }
    if plan.result_area_size > 0 {
      Some(
        append_body(
          builder,
          entry,
          IncomingResultArea(context.internal_abi.result_area_argument),
          [],
          [@vcode.Output::any_location(Ptr64)],
          @vcode.InstructionMetadata::empty(),
        )[0],
      )
    } else {
      None
    }
  } else {
    None
  }
  (values, result_area)
}

///|
pub fn DirectLoweringSession::new(
  name : String,
  protocol : @native.CallProtocol,
  parameter_types : Array[@native.ValueType],
  result_types : Array[@native.ValueType],
  context : LoweringContext,
  on_event? : (@vcode.TargetCompileEvent) -> Unit = fn(_) { () },
) -> DirectLoweringSession raise X64LowerError {
  on_event(TargetConstructionStarted)
  let signature = @native.Signature::new(parameter_types, result_types)
  let builder : @vcode.CheckedBuilder[X64Inst] = @vcode.CheckedBuilder::new_with_protocol(
    name,
    protocol,
    signature.params,
    signature.results,
  )
  let (values, result_area) = lower_direct_parameters(
    builder, context, protocol, signature,
  )
  let entry = builder.entry_block()
  {
    builder,
    context,
    protocol,
    signature,
    values,
    value_types: signature.params.copy(),
    blocks: [entry],
    layout: [entry],
    stack_objects: [],
    result_area,
    instruction_index: 0,
    first_error: None,
    constructed: None,
    on_event,
  }
}

///|
fn DirectLoweringSession::record_error(
  self : DirectLoweringSession,
  error : X64LowerError,
) -> Unit {
  if self.first_error is None {
    self.first_error = Some(error)
  }
}

///|
fn DirectLoweringSession::target_value(
  self : DirectLoweringSession,
  id : Int,
) -> @vcode.Value {
  self.values[id]
}

///|
fn DirectLoweringSession::target_values(
  self : DirectLoweringSession,
  ids : Array[Int],
) -> Array[@vcode.Value] {
  ids.map(id => self.target_value(id))
}

///|
fn DirectLoweringSession::create_block(
  self : DirectLoweringSession,
  parameter_types : Array[@native.ValueType],
) -> (Int, Array[Int]) {
  let block = self.builder.create_block(parameter_types)
  let block_id = self.blocks.length()
  self.blocks.push(block)
  let parameters : Array[Int] = []
  for index, ty in parameter_types {
    let value = self.builder.block_parameter(block, index) catch {
      _ => abort("x64 direct lowering could not read a new block parameter")
    }
    parameters.push(self.values.length())
    self.values.push(value)
    self.value_types.push(ty)
  }
  (block_id, parameters)
}

///|
fn DirectLoweringSession::create_stack_object(
  self : DirectLoweringSession,
  size : Int,
  alignment : Int,
) -> Int {
  let id = self.stack_objects.length()
  self.stack_objects.push({ size, alignment, })
  id
}

///|
fn DirectLoweringSession::switch_to_block(
  self : DirectLoweringSession,
  block_id : Int,
) -> Unit {
  let block = self.blocks[block_id]
  self.layout.push(block)
}

///|
fn DirectLoweringSession::emit(
  self : DirectLoweringSession,
  block_id : Int,
  operation : @lowering.Operation,
  operand_ids : Array[Int],
  result_types : Array[@native.ValueType],
  source : @native.SourceLocation?,
  root_ids : Array[Int],
  stack_map : @native.StackMapMetadata?,
) -> Array[Int] {
  let block = self.blocks[block_id]
  let results = if self.first_error is Some(_) {
    result_types.map(ty => append_placeholder(self.builder, block, ty))
  } else {
    lower_direct_operation(
      self.context,
      self.builder,
      block,
      block_id,
      self.instruction_index,
      operation,
      self.target_values(operand_ids),
      operand_ids.map(id => self.value_types[id]),
      result_types,
      self.target_values(root_ids),
      source,
      stack_map,
      object => {
        let request = self.stack_objects[object.id]
        X64StackObject::new(object.id, request.size, request.alignment)
      },
    ) catch {
      error => {
        self.record_error(error)
        result_types.map(ty => append_placeholder(self.builder, block, ty))
      }
    }
  }
  self.instruction_index += 1
  let ids : Array[Int] = []
  for index, value in results {
    ids.push(self.values.length())
    self.values.push(value)
    self.value_types.push(result_types[index])
  }
  ids
}

///|
fn DirectLoweringSession::terminator_metadata(
  self : DirectLoweringSession,
  metadata : @lowering.TargetTerminatorMetadata,
) -> @vcode.InstructionMetadata {
  match metadata.source {
    Some(source) =>
      @vcode.InstructionMetadata::new(
        source~,
        live_gc_roots=self.target_values(metadata.live_gc_roots),
      )
    None =>
      @vcode.InstructionMetadata::new(
        live_gc_roots=self.target_values(metadata.live_gc_roots),
      )
  }
}

///|
fn DirectLoweringSession::lower_return_values(
  self : DirectLoweringSession,
  block : @vcode.Block,
  values : Array[@vcode.Value],
) -> Unit raise X64LowerError {
  let locations : Array[CallResultLocation] = match self.protocol {
    Platform => {
      if self.signature.results.length() > 1 {
        raise UnsupportedAbi(
          message="platform functions support at most one direct result",
        )
      }
      platform_result_registers(self.signature.results).map(reg => {
        CallResultRegister(reg)
      })
    }
    Internal =>
      self.context.internal_abi.result_layout(self.signature.results).0
  }
  for index, value in values {
    let ty = self.signature.results[index]
    match locations[index] {
      CallResultRegister(reg) =>
        append_body(
          self.builder,
          block,
          OutgoingReg(ty, reg),
          [@vcode.Input::any(value)],
          [],
          @vcode.InstructionMetadata::empty(),
        )
        |> ignore
      CallResultArea(offset, _) => {
        guard self.result_area is Some(address) else {
          raise UnsupportedAbi(message="internal result area is unavailable")
        }
        append_body(
          self.builder,
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
fn DirectLoweringSession::terminate(
  self : DirectLoweringSession,
  block_id : Int,
  terminator : @lowering.TargetTerminator,
  metadata : @lowering.TargetTerminatorMetadata,
) -> Unit {
  let block = self.blocks[block_id]
  let ordinary_metadata = self.terminator_metadata(metadata)
  let action : () -> Unit raise X64LowerError = fn() raise X64LowerError {
    match terminator {
      Jump(target, arguments) =>
        set_terminator(
          self.builder,
          block,
          Jump,
          [],
          [@vcode.Edge::new(self.blocks[target], self.target_values(arguments))],
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
          self.builder,
          block,
          BranchNonZero32,
          [@vcode.Input::any(self.target_value(condition))],
          [
            @vcode.Edge::new(
              self.blocks[true_target],
              self.target_values(true_arguments),
            ),
            @vcode.Edge::new(
              self.blocks[false_target],
              self.target_values(false_arguments),
            ),
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
        let width = if self.value_types[left] == I32 { W32 } else { W64 }
        let condition = append_body(
            self.builder,
            block,
            CompareSet(width, lower_condition(comparison)),
            [
              @vcode.Input::any(self.target_value(left)),
              @vcode.Input::any(self.target_value(right)),
            ],
            [@vcode.Output::any(I32)],
            @vcode.InstructionMetadata::empty(),
          )[0]
        set_terminator(
          self.builder,
          block,
          BranchNonZero32,
          [@vcode.Input::any(condition)],
          [
            @vcode.Edge::new(
              self.blocks[true_target],
              self.target_values(true_arguments),
            ),
            @vcode.Edge::new(
              self.blocks[false_target],
              self.target_values(false_arguments),
            ),
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
        let width = if self.value_types[input] == I32 { W32 } else { W64 }
        let constant = append_body(
            self.builder,
            block,
            LoadConstant(width, bits),
            [],
            [@vcode.Output::any(self.value_types[input])],
            @vcode.InstructionMetadata::empty(),
          )[0]
        let condition = append_body(
            self.builder,
            block,
            CompareSet(width, lower_condition(comparison)),
            [
              @vcode.Input::any(self.target_value(input)),
              @vcode.Input::any(constant),
            ],
            [@vcode.Output::any(I32)],
            @vcode.InstructionMetadata::empty(),
          )[0]
        set_terminator(
          self.builder,
          block,
          BranchNonZero32,
          [@vcode.Input::any(condition)],
          [
            @vcode.Edge::new(
              self.blocks[true_target],
              self.target_values(true_arguments),
            ),
            @vcode.Edge::new(
              self.blocks[false_target],
              self.target_values(false_arguments),
            ),
          ],
          ordinary_metadata,
        )
      }
      Switch(index, cases, default_target, default_arguments) => {
        let width = if self.value_types[index] == I32 { W32 } else { W64 }
        let successors = cases.map(case => {
          @vcode.Edge::new(
            self.blocks[case.target],
            self.target_values(case.arguments),
          )
        })
        successors.push(
          @vcode.Edge::new(
            self.blocks[default_target],
            self.target_values(default_arguments),
          ),
        )
        set_terminator(
          self.builder,
          block,
          Switch(width, cases.map(case => case.bits)),
          [@vcode.Input::any(self.target_value(index))],
          successors,
          ordinary_metadata,
        )
      }
      Return(values) => {
        self.lower_return_values(block, self.target_values(values))
        set_terminator(self.builder, block, Return, [], [], ordinary_metadata)
      }
      TailCall(call, operands) =>
        self.terminate_tail_call(
          block,
          call,
          self.target_values(operands),
          ordinary_metadata,
        )
      NoReturnCall(call, operands) => {
        let roots = self.target_values(metadata.live_gc_roots)
        let call_metadata = terminator_call_metadata(
          metadata.source,
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
              self.builder,
              block,
              call,
              self.target_values(operands),
              [],
              call_metadata,
            )
            |> ignore
          Internal =>
            lower_internal_call(
              self.context,
              self.builder,
              block,
              call,
              self.target_values(operands),
              [],
              call_metadata,
            )
            |> ignore
        }
        set_terminator(
          self.builder,
          block,
          Trap(Unreachable),
          [],
          [],
          terminator_trap_metadata(metadata.source, Unreachable),
        )
      }
      Trap(reason) =>
        set_terminator(
          self.builder,
          block,
          Trap(reason),
          [],
          [],
          terminator_trap_metadata(metadata.source, reason),
        )
    }
  }
  action() catch {
    error => {
      self.record_error(error)
      set_terminator(
        self.builder,
        block,
        Trap(Unreachable),
        [],
        [],
        terminator_trap_metadata(metadata.source, Unreachable),
      ) catch {
        _ => abort("x64 direct lowering could not seal an error block")
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
) -> Unit raise X64LowerError {
  if self.protocol != Internal || call.protocol != Internal {
    raise UnsupportedAbi(
      message="true tail calls require Internal caller and callee protocols",
    )
  }
  let plan = self.context.internal_abi.call_plan(call.signature) catch {
    error => raise UnsupportedAbi(message=error.to_string())
  }
  let operands = operands.copy()
  if plan.result_area_size > 0 {
    guard self.result_area is Some(address) else {
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
  let call_metadata = terminator_call_metadata(
    metadata.source,
    call.behavior.semantics(),
  )
  let metadata = @vcode.InstructionMetadata::new(
    source?=call_metadata.source,
    safepoint?=call_metadata.safepoint,
    live_gc_roots=metadata.live_gc_roots,
  )
  set_terminator(
    self.builder,
    block,
    target,
    inputs,
    [],
    metadata,
    clobbers=platform_call_clobbers(),
  )
}

///|
fn DirectLoweringSession::finish_construction(
  self : DirectLoweringSession,
) -> Unit {
  if self.constructed is Some(_) {
    return
  }
  let lowered = self.builder.finish() catch {
    error => {
      self.record_error(BuildFailure(cause=error))
      return
    }
  }
  lowered.set_layout(self.layout) catch {
    error => {
      self.record_error(BuildFailure(cause=error))
      return
    }
  }
  self.constructed = Some({ function: lowered, })
}

///|
pub fn DirectLoweringSession::sink(
  self : DirectLoweringSession,
) -> @lowering.TargetSink {
  @lowering.TargetSink::new(
    fn() { Array::makei(self.signature.params.length(), index => index) },
    fn() { 0 },
    fn(types) { self.create_block(types) },
    fn(size, alignment) { self.create_stack_object(size, alignment) },
    fn(block) { self.switch_to_block(block) },
    fn(block, operation, operands, results, source, roots, stack_map) {
      self.emit(block, operation, operands, results, source, roots, stack_map)
    },
    fn(block, terminator, metadata) {
      self.terminate(block, terminator, metadata)
    },
    fn() { self.finish_construction() },
  )
}

///|
/// Finish direct selection and return the VCode consumed by target compilation.
///
/// `verify_selected=false` is reserved for compiler-owned construction paths
/// covered by strict validation in CI. Public callers should keep the default.
pub fn DirectLoweringSession::finish_selected(
  self : DirectLoweringSession,
  verify_selected? : Bool = true,
) -> SelectedFunction raise X64LowerError {
  if self.constructed is None {
    self.finish_construction()
  }
  if self.first_error is Some(error) {
    raise error
  }
  guard self.constructed is Some(constructed) else {
    raise UnsupportedAbi(message="direct lowering did not construct VCode")
  }
  if verify_selected {
    validate_constructed(constructed, self.on_event)
  }
  (self.on_event)(TargetSealingStarted)
  (self.on_event)(TargetSelectionFinished)
  { constructed, }
}
