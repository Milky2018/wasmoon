///|
fn semantic_vector_lane_size(
  lane : @semantic_machv.VectorLane,
) -> @instr.LaneSize {
  match lane {
    I8x16 => B8
    I16x8 => H16
    I32x4 | F32x4 => S32
    I64x2 | F64x2 => D64
  }
}

///|
fn semantic_vector_float_is_f32(
  lane : @semantic_machv.VectorLane,
) -> Bool raise SemanticLegacyAdapterError {
  match lane {
    F32x4 => true
    F64x2 => false
    _ =>
      raise UnsupportedOperation(
        message="floating vector operation requires floating lanes",
      )
  }
}

///|
fn semantic_v128_bytes(low : UInt64, high : UInt64) -> Bytes {
  Bytes::makei(16, fn(index) {
    let word = if index < 8 { low } else { high }
    ((word >> ((index & 7) * 8)) & 0xFFUL).to_byte()
  })
}

///|
fn require_semantic_vector_shape(
  operands : Array[@abi.Reg],
  definitions : Array[@abi.Writable],
  operand_count : Int,
  definition_count : Int,
  operation : String,
) -> Unit raise SemanticLegacyAdapterError {
  if operands.length() != operand_count ||
    definitions.length() != definition_count {
    raise UnsupportedOperation(
      message="\{operation} requires \{operand_count} operands and \{definition_count} results",
    )
  }
}

///|
fn append_semantic_vector_opcode(
  legacy_function : @machv.Function,
  block : @block.Block,
  opcode : @instr.Opcode,
  operands : Array[@abi.Reg],
  definitions : Array[@abi.Writable],
  temporary_vectors : Int,
) -> Unit {
  let instruction = @instr.Inst(opcode)
  for definition in definitions {
    instruction.add_def(definition)
  }
  for _ in 0..<temporary_vectors {
    instruction.add_def(legacy_def(legacy_function.new_vreg(Vector)))
  }
  for operand in operands {
    instruction.add_use(operand)
  }
  block.add_inst(instruction)
}

///|
fn append_semantic_vector_unary(
  legacy_function : @machv.Function,
  block : @block.Block,
  opcode : @instr.Opcode,
  operands : Array[@abi.Reg],
  definitions : Array[@abi.Writable],
) -> Unit raise SemanticLegacyAdapterError {
  require_semantic_vector_shape(operands, definitions, 1, 1, "vector unary")
  let temporary_vectors = match opcode {
    SIMDTruncSatF64ToI32SZero
    | SIMDTruncSatF64ToI32UZero
    | SIMDConvertLowI32ToF64S
    | SIMDConvertLowI32ToF64U => 1
    _ => 0
  }
  append_semantic_vector_opcode(
    legacy_function, block, opcode, operands, definitions, temporary_vectors,
  )
}

///|
fn append_semantic_vector_binary(
  legacy_function : @machv.Function,
  block : @block.Block,
  opcode : @instr.Opcode,
  operands : Array[@abi.Reg],
  definitions : Array[@abi.Writable],
) -> Unit raise SemanticLegacyAdapterError {
  require_semantic_vector_shape(operands, definitions, 2, 1, "vector binary")
  let temporary_vectors = match opcode {
    SIMDMul(D64) => 5
    SIMDRelaxedDot8to16 => 1
    _ => 0
  }
  append_semantic_vector_opcode(
    legacy_function, block, opcode, operands, definitions, temporary_vectors,
  )
}

///|
fn append_semantic_vector_binary_swapped(
  legacy_function : @machv.Function,
  block : @block.Block,
  opcode : @instr.Opcode,
  operands : Array[@abi.Reg],
  definitions : Array[@abi.Writable],
) -> Unit raise SemanticLegacyAdapterError {
  require_semantic_vector_shape(
    operands, definitions, 2, 1, "swapped vector binary",
  )
  append_semantic_vector_opcode(
    legacy_function,
    block,
    opcode,
    [operands[1], operands[0]],
    definitions,
    0,
  )
}

///|
fn append_semantic_vector_ternary(
  legacy_function : @machv.Function,
  block : @block.Block,
  opcode : @instr.Opcode,
  operands : Array[@abi.Reg],
  definitions : Array[@abi.Writable],
  temporary_vectors? : Int = 0,
) -> Unit raise SemanticLegacyAdapterError {
  require_semantic_vector_shape(operands, definitions, 3, 1, "vector ternary")
  append_semantic_vector_opcode(
    legacy_function, block, opcode, operands, definitions, temporary_vectors,
  )
}

///|
fn append_semantic_vector_not_equal(
  legacy_function : @machv.Function,
  block : @block.Block,
  equal_opcode : @instr.Opcode,
  operands : Array[@abi.Reg],
  definitions : Array[@abi.Writable],
) -> Unit raise SemanticLegacyAdapterError {
  require_semantic_vector_shape(
    operands, definitions, 2, 1, "vector not-equal comparison",
  )
  let equal = legacy_function.new_vreg(Vector)
  append_semantic_vector_opcode(
    legacy_function,
    block,
    equal_opcode,
    operands,
    [legacy_def(equal)],
    0,
  )
  append_semantic_vector_opcode(
    legacy_function,
    block,
    SIMDNot,
    [Virtual(equal)],
    definitions,
    0,
  )
}

///|
fn append_semantic_vector_shift(
  legacy_function : @machv.Function,
  block : @block.Block,
  lane : @semantic_machv.VectorLane,
  operation : @semantic_machv.VectorIntShiftOp,
  operands : Array[@abi.Reg],
  definitions : Array[@abi.Writable],
) -> Unit raise SemanticLegacyAdapterError {
  require_semantic_vector_shape(operands, definitions, 2, 1, "vector shift")
  let lane_size = semantic_vector_lane_size(lane)
  let (negate, use_unsigned_shift) = match operation {
    Left => (false, false)
    Right(Signed) => (true, false)
    Right(Unsigned) => (true, true)
  }
  let masked_shift = legacy_function.new_vreg(Int)
  let shift_vector = legacy_function.new_vreg(Vector)
  let broadcast = @instr.Inst(SIMDBroadcastShift(lane_size, negate))
  broadcast.add_def(legacy_def(masked_shift))
  broadcast.add_def(legacy_def(shift_vector))
  broadcast.add_use(operands[1])
  block.add_inst(broadcast)
  append_semantic_vector_opcode(
    legacy_function,
    block,
    SIMDShiftByVec(lane_size, use_unsigned_shift),
    [operands[0], Virtual(shift_vector)],
    definitions,
    0,
  )
}

///|
fn append_semantic_vector_predicate(
  legacy_function : @machv.Function,
  block : @block.Block,
  opcode : @instr.Opcode,
  operands : Array[@abi.Reg],
  definitions : Array[@abi.Writable],
) -> Unit raise SemanticLegacyAdapterError {
  require_semantic_vector_shape(operands, definitions, 1, 1, "vector predicate")
  let temporary_vectors = match opcode {
    SIMDAnyTrue => 1
    SIMDAllTrue(D64) => 0
    SIMDAllTrue(_) => 1
    SIMDBitmask(B8) => 3
    SIMDBitmask(_) => 0
    _ => 0
  }
  append_semantic_vector_opcode(
    legacy_function, block, opcode, operands, definitions, temporary_vectors,
  )
}

///|
fn append_semantic_vector_float_ternary(
  legacy_function : @machv.Function,
  block : @block.Block,
  lane : @semantic_machv.VectorLane,
  operation : @semantic_machv.FloatTernaryOp,
  operands : Array[@abi.Reg],
  definitions : Array[@abi.Writable],
) -> Unit raise SemanticLegacyAdapterError {
  require_semantic_vector_shape(
    operands, definitions, 3, 1, "vector float ternary",
  )
  let is_f32 = semantic_vector_float_is_f32(lane)
  let (opcode, accumulator) : (@instr.Opcode, @abi.Reg) = match operation {
    FusedMultiplyAdd => (SIMDFMla(is_f32), operands[2])
    FusedNegatedMultiplyAdd => (SIMDFMls(is_f32), operands[2])
    FusedMultiplySubtract | FusedNegatedMultiplySubtract => {
      let negated = legacy_function.new_vreg(Vector)
      append_semantic_vector_opcode(
        legacy_function,
        block,
        SIMDFNeg(is_f32),
        [operands[2]],
        [legacy_def(negated)],
        0,
      )
      (
        if operation is FusedMultiplySubtract {
          SIMDFMla(is_f32)
        } else {
          SIMDFMls(is_f32)
        },
        Virtual(negated),
      )
    }
  }
  append_semantic_vector_opcode(
    legacy_function,
    block,
    opcode,
    [accumulator, operands[0], operands[1]],
    definitions,
    0,
  )
}

///|
fn append_semantic_vector_operation(
  legacy_function : @machv.Function,
  block : @block.Block,
  operation : @semantic_machv.VectorOp,
  operands : Array[@abi.Reg],
  definitions : Array[@abi.Writable],
) -> Unit raise SemanticLegacyAdapterError {
  match operation {
    Splat(lane) => {
      let opcode : @instr.Opcode = match lane {
        F32x4 => SIMDSplatF(true)
        F64x2 => SIMDSplatF(false)
        _ => SIMDSplat(semantic_vector_lane_size(lane))
      }
      append_semantic_vector_unary(
        legacy_function, block, opcode, operands, definitions,
      )
    }
    ExtractLane(lane, index, extension) => {
      let opcode : @instr.Opcode = match lane {
        F32x4 => SIMDExtractF(true, index)
        F64x2 => SIMDExtractF(false, index)
        I8x16 | I16x8 =>
          match extension {
            Some(Signed) => SIMDExtractS(semantic_vector_lane_size(lane), index)
            Some(Unsigned) =>
              SIMDExtractU(semantic_vector_lane_size(lane), index)
            None =>
              raise UnsupportedOperation(
                message="narrow vector extraction requires signedness",
              )
          }
        I32x4 | I64x2 => SIMDExtractU(semantic_vector_lane_size(lane), index)
      }
      append_semantic_vector_unary(
        legacy_function, block, opcode, operands, definitions,
      )
    }
    ReplaceLane(lane, index) => {
      let opcode : @instr.Opcode = match lane {
        F32x4 => SIMDInsertF(true, index)
        F64x2 => SIMDInsertF(false, index)
        _ => SIMDInsert(semantic_vector_lane_size(lane), index)
      }
      append_semantic_vector_binary(
        legacy_function, block, opcode, operands, definitions,
      )
    }
    Shuffle(mask) => {
      require_semantic_vector_shape(
        operands, definitions, 2, 1, "vector shuffle",
      )
      append_semantic_vector_opcode(
        legacy_function,
        block,
        SIMDShuffle(mask),
        operands,
        definitions,
        2,
      )
    }
    Swizzle =>
      append_semantic_vector_binary(
        legacy_function,
        block,
        SIMDSwizzle,
        operands,
        definitions,
      )
    Bitwise(Not) =>
      append_semantic_vector_unary(
        legacy_function,
        block,
        SIMDNot,
        operands,
        definitions,
      )
    Bitwise(And) =>
      append_semantic_vector_binary(
        legacy_function,
        block,
        SIMDAnd,
        operands,
        definitions,
      )
    Bitwise(Or) =>
      append_semantic_vector_binary(
        legacy_function,
        block,
        SIMDOr,
        operands,
        definitions,
      )
    Bitwise(Xor) =>
      append_semantic_vector_binary(
        legacy_function,
        block,
        SIMDXor,
        operands,
        definitions,
      )
    Bitwise(AndNot) =>
      append_semantic_vector_binary(
        legacy_function,
        block,
        SIMDBic,
        operands,
        definitions,
      )
    Bitwise(BitSelect) =>
      append_semantic_vector_ternary(
        legacy_function,
        block,
        SIMDBsl,
        operands,
        definitions,
      )
    IntUnary(lane, operation) => {
      let lane_size = semantic_vector_lane_size(lane)
      let opcode : @instr.Opcode = match operation {
        Absolute => SIMDAbs(lane_size)
        Negate => SIMDNeg(lane_size)
        PopulationCount => SIMDCnt
        ExtendAddPairwise(signedness) =>
          SIMDExtAddPairwise(lane_size, signedness is Signed)
      }
      append_semantic_vector_unary(
        legacy_function, block, opcode, operands, definitions,
      )
    }
    IntBinary(lane, operation) => {
      let lane_size = semantic_vector_lane_size(lane)
      let opcode : @instr.Opcode = match operation {
        Add => SIMDAdd(lane_size)
        Sub => SIMDSub(lane_size)
        Mul =>
          if lane is I8x16 {
            raise UnsupportedOperation(
              message="i8x16 multiply has no legacy target lowering",
            )
          } else {
            SIMDMul(lane_size)
          }
        Min(signedness) =>
          if signedness is Signed {
            SIMDSmin(lane_size)
          } else {
            SIMDUmin(lane_size)
          }
        Max(signedness) =>
          if signedness is Signed {
            SIMDSmax(lane_size)
          } else {
            SIMDUmax(lane_size)
          }
        AverageUnsigned => SIMDUrhadd(lane_size)
        SaturatingAdd(signedness) =>
          if signedness is Signed {
            SIMDSqadd(lane_size)
          } else {
            SIMDUqadd(lane_size)
          }
        SaturatingSub(signedness) =>
          if signedness is Signed {
            SIMDSqsub(lane_size)
          } else {
            SIMDUqsub(lane_size)
          }
        ExtendMultiply(half, signedness) =>
          if half is Low {
            SIMDExtMulLow(lane_size, signedness is Signed)
          } else {
            SIMDExtMulHigh(lane_size, signedness is Signed)
          }
        Dot16To32Signed => SIMDDot
        Q15MultiplyRoundedSaturating => SIMDQ15MulrSat
      }
      append_semantic_vector_binary(
        legacy_function, block, opcode, operands, definitions,
      )
    }
    IntShift(lane, operation) =>
      append_semantic_vector_shift(
        legacy_function, block, lane, operation, operands, definitions,
      )
    IntCompare(lane, operation) => {
      let lane_size = semantic_vector_lane_size(lane)
      match operation {
        Equal =>
          append_semantic_vector_binary(
            legacy_function,
            block,
            SIMDCmp(lane_size, Eq),
            operands,
            definitions,
          )
        NotEqual =>
          append_semantic_vector_not_equal(
            legacy_function,
            block,
            SIMDCmp(lane_size, Eq),
            operands,
            definitions,
          )
        LessThan(signedness) =>
          append_semantic_vector_binary_swapped(
            legacy_function,
            block,
            SIMDCmp(lane_size, if signedness is Signed { GtS } else { GtU }),
            operands,
            definitions,
          )
        LessOrEqual(signedness) =>
          append_semantic_vector_binary_swapped(
            legacy_function,
            block,
            SIMDCmp(lane_size, if signedness is Signed { GeS } else { GeU }),
            operands,
            definitions,
          )
        GreaterThan(signedness) =>
          append_semantic_vector_binary(
            legacy_function,
            block,
            SIMDCmp(lane_size, if signedness is Signed { GtS } else { GtU }),
            operands,
            definitions,
          )
        GreaterOrEqual(signedness) =>
          append_semantic_vector_binary(
            legacy_function,
            block,
            SIMDCmp(lane_size, if signedness is Signed { GeS } else { GeU }),
            operands,
            definitions,
          )
      }
    }
    FloatUnary(lane, operation) => {
      let is_f32 = semantic_vector_float_is_f32(lane)
      let opcode : @instr.Opcode = match operation {
        Absolute => SIMDFAbs(is_f32)
        Negate => SIMDFNeg(is_f32)
        SquareRoot => SIMDFSqrt(is_f32)
        Ceil => SIMDFCeil(is_f32)
        Floor => SIMDFFloor(is_f32)
        Truncate => SIMDFTrunc(is_f32)
        Nearest => SIMDFNearest(is_f32)
      }
      append_semantic_vector_unary(
        legacy_function, block, opcode, operands, definitions,
      )
    }
    FloatBinary(lane, operation) => {
      let is_f32 = semantic_vector_float_is_f32(lane)
      let opcode : @instr.Opcode = match operation {
        Add => SIMDFAdd(is_f32)
        Sub => SIMDFSub(is_f32)
        Mul => SIMDFMul(is_f32)
        Div => SIMDFDiv(is_f32)
        Min => SIMDFMin(is_f32)
        Max => SIMDFMax(is_f32)
        PseudoMin => SIMDFPMin(is_f32)
        PseudoMax => SIMDFPMax(is_f32)
      }
      append_semantic_vector_binary(
        legacy_function, block, opcode, operands, definitions,
      )
    }
    FloatTernary(lane, operation) =>
      append_semantic_vector_float_ternary(
        legacy_function, block, lane, operation, operands, definitions,
      )
    FloatCompare(lane, operation) => {
      let is_f32 = semantic_vector_float_is_f32(lane)
      match operation {
        Equal =>
          append_semantic_vector_binary(
            legacy_function,
            block,
            SIMDFCmp(is_f32, Eq),
            operands,
            definitions,
          )
        NotEqual =>
          append_semantic_vector_not_equal(
            legacy_function,
            block,
            SIMDFCmp(is_f32, Eq),
            operands,
            definitions,
          )
        LessThan =>
          append_semantic_vector_binary_swapped(
            legacy_function,
            block,
            SIMDFCmp(is_f32, Gt),
            operands,
            definitions,
          )
        LessOrEqual =>
          append_semantic_vector_binary_swapped(
            legacy_function,
            block,
            SIMDFCmp(is_f32, Ge),
            operands,
            definitions,
          )
        GreaterThan =>
          append_semantic_vector_binary(
            legacy_function,
            block,
            SIMDFCmp(is_f32, Gt),
            operands,
            definitions,
          )
        GreaterOrEqual =>
          append_semantic_vector_binary(
            legacy_function,
            block,
            SIMDFCmp(is_f32, Ge),
            operands,
            definitions,
          )
      }
    }
    Predicate(operation) => {
      let opcode : @instr.Opcode = match operation {
        AnyTrue => SIMDAnyTrue
        AllTrue(lane) => SIMDAllTrue(semantic_vector_lane_size(lane))
        BitMask(lane) => SIMDBitmask(semantic_vector_lane_size(lane))
      }
      append_semantic_vector_predicate(
        legacy_function, block, opcode, operands, definitions,
      )
    }
    Convert(operation) => {
      let opcode : @instr.Opcode = match operation {
        ExtendLow(lane, signedness) =>
          SIMDExtendLow(semantic_vector_lane_size(lane), signedness is Signed)
        ExtendHigh(lane, signedness) =>
          SIMDExtendHigh(semantic_vector_lane_size(lane), signedness is Signed)
        Narrow(lane, signedness) =>
          SIMDNarrow(semantic_vector_lane_size(lane), signedness is Signed)
        FloatToInt(F32x4, I32x4, Signed, _) => SIMDFCvtToIntS(true)
        FloatToInt(F32x4, I32x4, Unsigned, _) => SIMDFCvtToIntU(true)
        FloatToInt(F64x2, I32x4, Signed, _) => SIMDTruncSatF64ToI32SZero
        FloatToInt(F64x2, I32x4, Unsigned, _) => SIMDTruncSatF64ToI32UZero
        IntToFloat(I32x4, F32x4, Signed) => SIMDIntToFloatS(true)
        IntToFloat(I32x4, F32x4, Unsigned) => SIMDIntToFloatU(true)
        IntToFloat(I32x4, F64x2, Signed) => SIMDConvertLowI32ToF64S
        IntToFloat(I32x4, F64x2, Unsigned) => SIMDConvertLowI32ToF64U
        PromoteLowF32x4 => SIMDPromoteLowF32ToF64
        DemoteZeroF64x2 => SIMDDemoteF64ToF32Zero
        _ =>
          raise UnsupportedOperation(
            message="unsupported vector conversion \{to_repr(operation)}",
          )
      }
      match operation {
        Narrow(_, _) =>
          append_semantic_vector_binary(
            legacy_function, block, opcode, operands, definitions,
          )
        _ =>
          append_semantic_vector_unary(
            legacy_function, block, opcode, operands, definitions,
          )
      }
    }
    Relaxed(operation) =>
      match operation {
        Swizzle =>
          append_semantic_vector_binary(
            legacy_function,
            block,
            SIMDSwizzle,
            operands,
            definitions,
          )
        FloatToInt(F32x4, I32x4, Signed) =>
          append_semantic_vector_unary(
            legacy_function,
            block,
            SIMDFCvtToIntS(true),
            operands,
            definitions,
          )
        FloatToInt(F32x4, I32x4, Unsigned) =>
          append_semantic_vector_unary(
            legacy_function,
            block,
            SIMDFCvtToIntU(true),
            operands,
            definitions,
          )
        FloatToInt(F64x2, I32x4, Signed) =>
          append_semantic_vector_unary(
            legacy_function,
            block,
            SIMDTruncSatF64ToI32SZero,
            operands,
            definitions,
          )
        FloatToInt(F64x2, I32x4, Unsigned) =>
          append_semantic_vector_unary(
            legacy_function,
            block,
            SIMDTruncSatF64ToI32UZero,
            operands,
            definitions,
          )
        FloatToInt(_, _, _) =>
          raise UnsupportedOperation(
            message="unsupported relaxed vector conversion",
          )
        FusedMultiplyAdd(lane, operation) =>
          append_semantic_vector_float_ternary(
            legacy_function, block, lane, operation, operands, definitions,
          )
        LaneSelect(_) =>
          append_semantic_vector_ternary(
            legacy_function,
            block,
            SIMDBsl,
            operands,
            definitions,
          )
        Min(lane) =>
          append_semantic_vector_binary(
            legacy_function,
            block,
            SIMDFMin(semantic_vector_float_is_f32(lane)),
            operands,
            definitions,
          )
        Max(lane) =>
          append_semantic_vector_binary(
            legacy_function,
            block,
            SIMDFMax(semantic_vector_float_is_f32(lane)),
            operands,
            definitions,
          )
        Q15MultiplyRoundedSigned =>
          append_semantic_vector_binary(
            legacy_function,
            block,
            SIMDQ15MulrSat,
            operands,
            definitions,
          )
        Dot8To16Signed =>
          append_semantic_vector_binary(
            legacy_function,
            block,
            SIMDRelaxedDot8to16,
            operands,
            definitions,
          )
        Dot8To32AddSigned =>
          append_semantic_vector_ternary(
            legacy_function,
            block,
            SIMDRelaxedDot8to32Add,
            operands,
            definitions,
            temporary_vectors=1,
          )
      }
  }
}

///|
fn require_native_vector_memory(
  endianness : @semantic_machv.Endianness,
  trap : @semantic_machv.TrapReason?,
) -> Unit raise SemanticLegacyAdapterError {
  if endianness != Little || trap is Some(_) {
    raise UnsupportedOperation(
      message="non-native-endian or trapping vector memory requires legalization",
    )
  }
}

///|
fn append_semantic_vector_load(
  legacy_function : @machv.Function,
  block : @block.Block,
  spec : @semantic_machv.VectorLoadSpec,
  operands : Array[@abi.Reg],
  definitions : Array[@abi.Writable],
) -> Unit raise SemanticLegacyAdapterError {
  require_native_vector_memory(spec.endianness, spec.trap)
  require_semantic_vector_shape(
    operands,
    definitions,
    if spec.kind is Lane(_, _) {
      2
    } else {
      1
    },
    1,
    "vector load",
  )
  let offset = spec.offset.to_int()
  let opcode : @instr.Opcode = match spec.kind {
    Splat(lane) => SIMDLoadSplat(semantic_vector_lane_size(lane), offset)
    Extend(I16x8, signedness) => SIMDLoadExtend(8, signedness is Signed, offset)
    Extend(I32x4, signedness) =>
      SIMDLoadExtend(16, signedness is Signed, offset)
    Extend(I64x2, signedness) =>
      SIMDLoadExtend(32, signedness is Signed, offset)
    Extend(_, _) =>
      raise UnsupportedOperation(message="invalid vector extending-load lane")
    Zero(W32) => SIMDLoadZero(false, offset)
    Zero(W64) => SIMDLoadZero(true, offset)
    Zero(_) =>
      raise UnsupportedOperation(message="invalid vector zero-load width")
    Lane(lane, index) =>
      SIMDLoadLane(semantic_vector_lane_size(lane), index, offset)
  }
  append_semantic_vector_opcode(
    legacy_function, block, opcode, operands, definitions, 0,
  )
}

///|
fn append_semantic_vector_store_lane(
  legacy_function : @machv.Function,
  block : @block.Block,
  spec : @semantic_machv.VectorStoreLaneSpec,
  operands : Array[@abi.Reg],
  definitions : Array[@abi.Writable],
) -> Unit raise SemanticLegacyAdapterError {
  require_native_vector_memory(spec.endianness, spec.trap)
  require_semantic_vector_shape(
    operands, definitions, 2, 0, "vector store lane",
  )
  append_semantic_vector_opcode(
    legacy_function,
    block,
    SIMDStoreLane(
      semantic_vector_lane_size(spec.lane),
      spec.lane_index,
      spec.offset.to_int(),
    ),
    operands,
    definitions,
    0,
  )
}

///|
test "semantic-to-legacy adapter lowers vector integer families" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_vector_integer",
    Internal,
    [I32, V128, V128],
    [V128, V128, I32, I32, I32],
  )
  let parameters = builder.parameters()
  let constant = builder.emit(
      V128Const(0x0706050403020100UL, 0x0F0E0D0C0B0A0908UL),
      [],
      [V128],
    )[0]
  let splat = builder.emit(Vector(Splat(I32x4)), [parameters[0]], [V128])[0]
  let replaced = builder.emit(
      Vector(ReplaceLane(I32x4, 1)),
      [splat, parameters[0]],
      [V128],
    )[0]
  let shuffled = builder.emit(
      Vector(Shuffle(FixedArray::makei(16, index => 15 - index))),
      [constant, replaced],
      [V128],
    )[0]
  let multiplied = builder.emit(
      Vector(IntBinary(I64x2, Mul)),
      [shuffled, parameters[2]],
      [V128],
    )[0]
  let shifted = builder.emit(
      Vector(IntShift(I64x2, Right(Unsigned))),
      [multiplied, parameters[0]],
      [V128],
    )[0]
  let compared = builder.emit(
      Vector(IntCompare(I32x4, NotEqual)),
      [shifted, parameters[1]],
      [V128],
    )[0]
  let any_true = builder.emit(Vector(Predicate(AnyTrue)), [compared], [I32])[0]
  let bitmask = builder.emit(Vector(Predicate(BitMask(I8x16))), [compared], [
      I32,
    ])[0]
  let extracted = builder.emit(
      Vector(ExtractLane(I16x8, 3, Some(Signed))),
      [compared],
      [I32],
    )[0]
  builder.return_([shifted, compared, any_true, bitmask, extracted])
  inspect(
    adapt_semantic_to_legacy(builder.finish(), AMD64),
    content=(
      #|machv semantic_adapter_vector_integer(v0:int, vec1:vector, vec2:vector) -> (vector, vector, int, int, int) {
      #|block0:
      #|    vec3 = ldi.v128
      #|    vec4 = dup.4s v0
      #|    vec5 = ins.4s[1] vec4, v0
      #|    vec6, vec13, vec14 = tbl1x2.16b vec3, vec5
      #|    vec7, vec15, vec16, vec17, vec18, vec19 = mul.2d vec6, vec2
      #|    v20, vec21 = dup_shift.neg.2d v0
      #|    vec8 = ushl.2d vec7, vec21
      #|    vec22 = cmp.eq.4s vec8, vec1
      #|    vec9 = not.16b vec22
      #|    v10, vec23 = v128.any_true vec9
      #|    v11, vec24, vec25, vec26 = bitmask.8b vec9
      #|    v12 = smov.8h[3] vec9
      #|    ret vec8, vec9, v10, v11, v12
      #|}
      #|
    ),
  )
}

///|
test "semantic-to-legacy adapter lowers vector float and relaxed families" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_vector_float",
    Internal,
    [V128, V128, V128],
    [V128, V128, V128, V128, V128, V128],
  )
  let parameters = builder.parameters()
  let sum = builder.emit(
      Vector(FloatBinary(F32x4, Add)),
      [parameters[0], parameters[1]],
      [V128],
    )[0]
  let compared = builder.emit(
      Vector(FloatCompare(F64x2, NotEqual)),
      [parameters[0], parameters[1]],
      [V128],
    )[0]
  let truncated = builder.emit(
      Vector(Convert(FloatToInt(F64x2, I32x4, Signed, Saturating))),
      [parameters[0]],
      [V128],
    )[0]
  let converted = builder.emit(
      Vector(Convert(IntToFloat(I32x4, F64x2, Unsigned))),
      [truncated],
      [V128],
    )[0]
  let fused = builder.emit(
      Vector(Relaxed(FusedMultiplyAdd(F32x4, FusedNegatedMultiplyAdd))),
      [sum, parameters[1], parameters[2]],
      [V128],
    )[0]
  let dotted = builder.emit(
      Vector(Relaxed(Dot8To16Signed)),
      [parameters[0], parameters[1]],
      [V128],
    )[0]
  let accumulated = builder.emit(
      Vector(Relaxed(Dot8To32AddSigned)),
      [parameters[0], parameters[1], parameters[2]],
      [V128],
    )[0]
  builder.return_([compared, truncated, converted, fused, dotted, accumulated])
  inspect(
    adapt_semantic_to_legacy(builder.finish(), AMD64),
    content=(
      #|machv semantic_adapter_vector_float(vec0:vector, vec1:vector, vec2:vector) -> (vector, vector, vector, vector, vector, vector) {
      #|block0:
      #|    vec3 = fadd.4s vec0, vec1
      #|    vec10 = fcmp.eq.2d vec0, vec1
      #|    vec4 = not.16b vec10
      #|    vec5, vec11 = fcvtzs.f64_i32_zero vec0
      #|    vec6, vec12 = ucvtf.i32_f64_low vec5
      #|    vec7 = fmls.4s vec2, vec3, vec1
      #|    vec8, vec13 = relaxed_dot.8to16 vec0, vec1
      #|    vec9, vec14 = relaxed_dot.8to32_add vec0, vec1, vec2
      #|    ret vec4, vec5, vec6, vec7, vec8, vec9
      #|}
      #|
    ),
  )
}

///|
test "semantic-to-legacy adapter lowers vector memory families" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_vector_memory",
    Internal,
    [Ptr64, V128],
    [V128, V128, V128, V128],
  )
  let parameters = builder.parameters()
  let splat = builder.emit(
      VectorLoad(
        @semantic_machv.VectorLoadSpec::new(Splat(I16x8), 4UL, Little, None),
      ),
      [parameters[0]],
      [V128],
    )[0]
  let extended = builder.emit(
      VectorLoad(
        @semantic_machv.VectorLoadSpec::new(
          Extend(I32x4, Signed),
          8UL,
          Little,
          None,
        ),
      ),
      [parameters[0]],
      [V128],
    )[0]
  let zeroed = builder.emit(
      VectorLoad(
        @semantic_machv.VectorLoadSpec::new(Zero(W64), 16UL, Little, None),
      ),
      [parameters[0]],
      [V128],
    )[0]
  let lane = builder.emit(
      VectorLoad(
        @semantic_machv.VectorLoadSpec::new(Lane(I8x16, 3), 20UL, Little, None),
      ),
      [parameters[0], parameters[1]],
      [V128],
    )[0]
  builder.emit(
    VectorStoreLane(
      @semantic_machv.VectorStoreLaneSpec::new(I16x8, 2, 24UL, Little, None),
    ),
    [parameters[0], lane],
    [],
  )
  |> ignore
  builder.return_([splat, extended, zeroed, lane])
  inspect(
    adapt_semantic_to_legacy(builder.finish(), AMD64),
    content=(
      #|machv semantic_adapter_vector_memory(v0:int, vec1:vector) -> (vector, vector, vector, vector) {
      #|block0:
      #|    vec2 = ld1r.8h +4 v0
      #|    vec3 = ldext.16s +8 v0
      #|    vec4 = ldr.d_zero +16 v0
      #|    vec5 = ld1.8b[3] +20 v0, vec1
      #|    st1.8h[2] +24 v0, vec5
      #|    ret vec2, vec3, vec4, vec5
      #|}
      #|
    ),
  )
}
