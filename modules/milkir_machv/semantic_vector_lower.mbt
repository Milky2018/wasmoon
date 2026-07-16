///|
fn lower_signedness(
  signedness : @milkir.VectorSignedness,
) -> @semantic.Signedness {
  match signedness {
    Signed => Signed
    Unsigned => Unsigned
  }
}

///|
fn lower_vector_half(half : @milkir.VectorHalf) -> @semantic.VectorHalf {
  match half {
    Low => Low
    High => High
  }
}

///|
fn lower_integer_lane(lane : @milkir.VectorIntLane) -> @semantic.VectorLane {
  match lane {
    I8 => I8x16
    I16 => I16x8
    I32 => I32x4
    I64 => I64x2
  }
}

///|
fn lower_float_lane(lane : @milkir.VectorFloatLane) -> @semantic.VectorLane {
  match lane {
    F32 => F32x4
    F64 => F64x2
  }
}

///|
fn lower_lane(lane : @milkir.VectorLane) -> @semantic.VectorLane {
  match lane {
    I8 => I8x16
    I16 => I16x8
    I32 => I32x4
    I64 => I64x2
    F32 => F32x4
    F64 => F64x2
  }
}

///|
fn lower_extension(
  extension : @milkir.VectorExtension,
) -> @semantic.Signedness? {
  match extension {
    None => None
    Signed => Some(Signed)
    Unsigned => Some(Unsigned)
  }
}

///|
fn bytes_word(bytes : Bytes, offset : Int) -> UInt64 {
  let mut word = 0UL
  for index in 0..<8 {
    word = word | (bytes[offset + index].to_int().to_uint64() << (index * 8))
  }
  word
}

///|
fn lower_int_unary_vector(
  operation : @milkir.VectorIntUnaryOp,
  lane : @milkir.VectorIntLane,
) -> @semantic.VectorOp {
  let lane = lower_integer_lane(lane)
  match operation {
    Abs => IntUnary(lane, Absolute)
    Neg => IntUnary(lane, Negate)
    Popcnt => IntUnary(lane, PopulationCount)
    Extend(half, signedness) =>
      Convert(
        match half {
          Low => ExtendLow(lane, lower_signedness(signedness))
          High => ExtendHigh(lane, lower_signedness(signedness))
        },
      )
    ExtAddPairwise(signedness) =>
      IntUnary(lane, ExtendAddPairwise(lower_signedness(signedness)))
  }
}

///|
fn lower_int_binary_vector(
  operation : @milkir.VectorIntBinaryOp,
  lane : @milkir.VectorIntLane,
) -> @semantic.VectorOp {
  let lane = lower_integer_lane(lane)
  let operation : @semantic.VectorIntBinaryOp = match operation {
    Add => Add
    Sub => Sub
    Mul => Mul
    AddSaturating(signedness) => SaturatingAdd(lower_signedness(signedness))
    SubSaturating(signedness) => SaturatingSub(lower_signedness(signedness))
    Min(signedness) => Min(lower_signedness(signedness))
    Max(signedness) => Max(lower_signedness(signedness))
    AverageUnsigned => AverageUnsigned
    ExtMul(half, signedness) =>
      ExtendMultiply(lower_vector_half(half), lower_signedness(signedness))
    Dot16To32Signed => Dot16To32Signed
    Q15MulrSaturating => Q15MultiplyRoundedSaturating
  }
  IntBinary(lane, operation)
}

///|
fn lower_int_shift_vector(
  operation : @milkir.VectorIntShiftOp,
  lane : @milkir.VectorIntLane,
) -> @semantic.VectorOp {
  let operation : @semantic.VectorIntShiftOp = match operation {
    Left => Left
    Right(signedness) => Right(lower_signedness(signedness))
  }
  IntShift(lower_integer_lane(lane), operation)
}

///|
fn lower_int_compare_vector(
  operation : @milkir.VectorIntCompareOp,
  lane : @milkir.VectorIntLane,
) -> @semantic.VectorOp {
  let operation : @semantic.VectorIntComparison = match operation {
    Eq => Equal
    Ne => NotEqual
    Lt(signedness) => LessThan(lower_signedness(signedness))
    Le(signedness) => LessOrEqual(lower_signedness(signedness))
    Gt(signedness) => GreaterThan(lower_signedness(signedness))
    Ge(signedness) => GreaterOrEqual(lower_signedness(signedness))
  }
  IntCompare(lower_integer_lane(lane), operation)
}

///|
fn lower_float_unary_vector(
  operation : @milkir.VectorFloatUnaryOp,
  lane : @milkir.VectorFloatLane,
) -> @semantic.VectorOp {
  let operation : @semantic.VectorFloatUnaryOp = match operation {
    Abs => Absolute
    Neg => Negate
    Sqrt => SquareRoot
    Ceil => Ceil
    Floor => Floor
    Trunc => Truncate
    Nearest => Nearest
  }
  FloatUnary(lower_float_lane(lane), operation)
}

///|
fn lower_float_binary_vector(
  operation : @milkir.VectorFloatBinaryOp,
  lane : @milkir.VectorFloatLane,
) -> @semantic.VectorOp {
  let operation : @semantic.VectorFloatBinaryOp = match operation {
    Add => Add
    Sub => Sub
    Mul => Mul
    Div => Div
    Min => Min
    Max => Max
    PseudoMin => PseudoMin
    PseudoMax => PseudoMax
  }
  FloatBinary(lower_float_lane(lane), operation)
}

///|
fn lower_float_compare_vector(
  operation : @milkir.VectorFloatCompareOp,
  lane : @milkir.VectorFloatLane,
) -> @semantic.VectorOp {
  let operation : @semantic.VectorFloatComparison = match operation {
    Eq => Equal
    Ne => NotEqual
    Lt => LessThan
    Le => LessOrEqual
    Gt => GreaterThan
    Ge => GreaterOrEqual
  }
  FloatCompare(lower_float_lane(lane), operation)
}

///|
fn lower_vector_conversion(
  operation : @milkir.VectorConversionOp,
) -> @semantic.VectorOp {
  Convert(
    match operation {
      TruncSatF32ToI32(signedness) =>
        FloatToInt(F32x4, I32x4, lower_signedness(signedness), Saturating)
      TruncSatF64ToI32Zero(signedness) =>
        FloatToInt(F64x2, I32x4, lower_signedness(signedness), Saturating)
      ConvertI32ToF32(signedness) =>
        IntToFloat(I32x4, F32x4, lower_signedness(signedness))
      ConvertLowI32ToF64(signedness) =>
        IntToFloat(I32x4, F64x2, lower_signedness(signedness))
      DemoteF64ToF32Zero => DemoteZeroF64x2
      PromoteLowF32ToF64 => PromoteLowF32x4
    },
  )
}

///|
fn lower_relaxed_vector(
  operation : @milkir.VectorRelaxedOp,
) -> @semantic.VectorOp {
  Relaxed(
    match operation {
      Swizzle => Swizzle
      TruncF32ToI32(signedness) =>
        FloatToInt(F32x4, I32x4, lower_signedness(signedness))
      TruncF64ToI32Zero(signedness) =>
        FloatToInt(F64x2, I32x4, lower_signedness(signedness))
      Fma(lane, operation) =>
        FusedMultiplyAdd(
          lower_float_lane(lane),
          match operation {
            Add => FusedMultiplyAdd
            NegatedAdd => FusedNegatedMultiplyAdd
          },
        )
      LaneSelect(lane) => LaneSelect(lower_integer_lane(lane))
      Min(lane) => Min(lower_float_lane(lane))
      Max(lane) => Max(lower_float_lane(lane))
      Q15MulrSigned => Q15MultiplyRoundedSigned
      Dot8To16Signed => Dot8To16Signed
      Dot8To32AddSigned => Dot8To32AddSigned
    },
  )
}

///|
fn lower_vector_operation(operation : @milkir.VectorOp) -> @semantic.Operation {
  match operation {
    Const(bytes) => V128Const(bytes_word(bytes, 0), bytes_word(bytes, 8))
    Splat(lane) => Vector(Splat(lower_lane(lane)))
    ExtractLane(lane, extension, index) =>
      Vector(ExtractLane(lower_lane(lane), index, lower_extension(extension)))
    ReplaceLane(lane, index) => Vector(ReplaceLane(lower_lane(lane), index))
    Shuffle(mask) => Vector(Shuffle(mask))
    Swizzle => Vector(Swizzle)
    Bitwise(operation) =>
      Vector(
        Bitwise(
          match operation {
            Not => Not
            And => And
            AndNot => AndNot
            Or => Or
            Xor => Xor
            Bitselect => BitSelect
          },
        ),
      )
    Predicate(operation) =>
      Vector(
        Predicate(
          match operation {
            AnyTrue => AnyTrue
            AllTrue(lane) => AllTrue(lower_integer_lane(lane))
            Bitmask(lane) => BitMask(lower_integer_lane(lane))
          },
        ),
      )
    IntUnary(operation, lane) => Vector(lower_int_unary_vector(operation, lane))
    IntBinary(operation, lane) =>
      Vector(lower_int_binary_vector(operation, lane))
    IntShift(operation, lane) => Vector(lower_int_shift_vector(operation, lane))
    IntCompare(operation, lane) =>
      Vector(lower_int_compare_vector(operation, lane))
    Narrow(lane, signedness) =>
      Vector(
        Convert(Narrow(lower_integer_lane(lane), lower_signedness(signedness))),
      )
    FloatUnary(operation, lane) =>
      Vector(lower_float_unary_vector(operation, lane))
    FloatBinary(operation, lane) =>
      Vector(lower_float_binary_vector(operation, lane))
    FloatCompare(operation, lane) =>
      Vector(lower_float_compare_vector(operation, lane))
    Convert(operation) => Vector(lower_vector_conversion(operation))
    Relaxed(operation) => Vector(lower_relaxed_vector(operation))
  }
}

///|
fn lower_vector_instruction(
  builder : @semantic.FunctionBuilder,
  values : Array[@semantic.Value?],
  instruction : @milkir.Inst,
  operation : @milkir.VectorOp,
) -> Unit raise SemanticLowerError {
  let lowered_results = builder.emit_with_metadata(
    lower_vector_operation(operation),
    mapped_values(values, instruction.args),
    instruction.results.map(value => lower_type(value.ty)),
    instruction_metadata(instruction, []),
  )
  assign_instruction_results(values, instruction, lowered_results)
}

///|
fn widened_lane(lane : @milkir.VectorIntLane) -> @semantic.VectorLane {
  match lane {
    I8 => I16x8
    I16 => I32x4
    I32 => I64x2
    I64 => I64x2
  }
}

///|
fn lower_vector_memory_instruction(
  builder : @semantic.FunctionBuilder,
  values : Array[@semantic.Value?],
  instruction : @milkir.Inst,
  operation : @milkir.VectorMemoryOp,
) -> Unit raise SemanticLowerError {
  let address = lower_pointer_value(
    builder,
    values,
    instruction.args[0],
    instruction_source(instruction),
    instruction.id,
  )
  let (operation, operands, result_types) : (
    @semantic.Operation,
    Array[@semantic.Value],
    Array[@semantic.ValueType],
  ) = match operation {
    LoadExtend(lane, signedness) =>
      (
        VectorLoad(
          @semantic.VectorLoadSpec::new(
            Extend(widened_lane(lane), lower_signedness(signedness)),
            0UL,
            Little,
            None,
          ),
        ),
        [address],
        [V128],
      )
    LoadSplat(lane) =>
      (
        VectorLoad(
          @semantic.VectorLoadSpec::new(
            Splat(lower_integer_lane(lane)),
            0UL,
            Little,
            None,
          ),
        ),
        [address],
        [V128],
      )
    LoadZero(lane) =>
      (
        VectorLoad(
          @semantic.VectorLoadSpec::new(
            Zero(if lane is I32 { W32 } else { W64 }),
            0UL,
            Little,
            None,
          ),
        ),
        [address],
        [V128],
      )
    LoadLane(lane, index) =>
      (
        VectorLoad(
          @semantic.VectorLoadSpec::new(
            Lane(lower_integer_lane(lane), index),
            0UL,
            Little,
            None,
          ),
        ),
        [address, mapped_value(values, instruction.args[1])],
        [V128],
      )
    StoreLane(lane, index) =>
      (
        VectorStoreLane(
          @semantic.VectorStoreLaneSpec::new(
            lower_integer_lane(lane),
            index,
            0UL,
            Little,
            None,
          ),
        ),
        [address, mapped_value(values, instruction.args[1])],
        [],
      )
  }
  let lowered_results = builder.emit_with_metadata(
    operation,
    operands,
    result_types,
    instruction_metadata(instruction, []),
  )
  assign_instruction_results(values, instruction, lowered_results)
}
