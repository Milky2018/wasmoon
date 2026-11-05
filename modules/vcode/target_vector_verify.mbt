///|
#derive(Eq, Debug)
pub(all) enum VectorConversion {
  ExtendLow(@lowering.VectorLane, @native.Signedness)
  ExtendHigh(@lowering.VectorLane, @native.Signedness)
  Narrow(@lowering.VectorLane, @native.Signedness)
  FloatToInt(@lowering.VectorLane, @native.Signedness)
  IntToFloat(@lowering.VectorLane, @native.Signedness)
  PromoteLowF32x4
  DemoteZeroF64x2
}

///|
pub extend VectorConversion with Debug::{to_repr}

///|
pub extend VectorConversion with Eq::{not_equal, equal}

///|
pub fn select_vector_conversion(
  operation : @lowering.VectorConversionOp,
) -> VectorConversion? {
  match operation {
    ExtendLow(lane, signedness) => Some(ExtendLow(lane, signedness))
    ExtendHigh(lane, signedness) => Some(ExtendHigh(lane, signedness))
    Narrow(lane, signedness) => Some(Narrow(lane, signedness))
    FloatToInt(source, I32x4, signedness, Saturating) =>
      Some(FloatToInt(source, signedness))
    IntToFloat(I32x4, result, signedness) =>
      Some(IntToFloat(result, signedness))
    PromoteLowF32x4 => Some(PromoteLowF32x4)
    DemoteZeroF64x2 => Some(DemoteZeroF64x2)
    _ => None
  }
}

///|
pub fn[Inst] TargetInstructionVerifier::vector_extract_lane(
  self : TargetInstructionVerifier[Inst],
  lane : @lowering.VectorLane,
  index : Int32,
  has_extension : Bool,
) -> Unit raise TargetVCodeVerifyError {
  let requires_extension = lane == I8x16 || lane == I16x8
  if index < 0 ||
    index >= lane.lane_count() ||
    requires_extension != has_extension {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="invalid vector lane extraction contract",
    )
  }
  self.shape([V128], [lane.scalar_type()])
}

///|
pub fn[Inst] TargetInstructionVerifier::vector_replace_lane(
  self : TargetInstructionVerifier[Inst],
  lane : @lowering.VectorLane,
  index : Int32,
) -> Unit raise TargetVCodeVerifyError {
  if index < 0 || index >= lane.lane_count() {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="invalid vector lane replacement index",
    )
  }
  self.shape([V128, lane.scalar_type()], [V128])
}

///|
pub fn[Inst] TargetInstructionVerifier::vector_shuffle(
  self : TargetInstructionVerifier[Inst],
  mask : FixedArray[Int32],
) -> Unit raise TargetVCodeVerifyError {
  if mask.length() != 16 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="vector shuffle requires exactly 16 lane indices",
    )
  }
  for lane in mask {
    if lane < 0 || lane >= 32 {
      raise InvalidInstruction(
        instruction=self.instruction,
        message="vector shuffle lane index is out of range",
      )
    }
  }
  self.shape([V128, V128], [V128])
}

///|
pub fn[Inst] TargetInstructionVerifier::vector_int_unary(
  self : TargetInstructionVerifier[Inst],
  lane : @lowering.VectorLane,
  operation : @lowering.VectorIntUnaryOp,
) -> Unit raise TargetVCodeVerifyError {
  if !lane.is_integer() {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="vector integer unary operation requires integer lanes",
    )
  }
  if operation is PopulationCount && lane != I8x16 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="vector population count requires i8x16 lanes",
    )
  }
  if operation is ExtendAddPairwise(_) &&
    lane != I16x8 &&
    lane != I32x4 &&
    lane != I64x2 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="pairwise extending add requires widened integer lanes",
    )
  }
  self.shape([V128], [V128])
}

///|
pub fn[Inst] TargetInstructionVerifier::vector_int_binary(
  self : TargetInstructionVerifier[Inst],
  lane : @lowering.VectorLane,
  operation : @lowering.VectorIntBinaryOp,
) -> Unit raise TargetVCodeVerifyError {
  if !lane.is_integer() {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="vector integer binary operation requires integer lanes",
    )
  }
  if operation is AverageUnsigned && lane != I8x16 && lane != I16x8 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="vector unsigned average requires i8x16 or i16x8 lanes",
    )
  }
  if operation is ExtendMultiply(_, _) &&
    lane != I16x8 &&
    lane != I32x4 &&
    lane != I64x2 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="extending multiply requires widened integer lanes",
    )
  }
  if operation is Dot16To32Signed && lane != I32x4 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="dot16-to32 requires i32x4 destination lanes",
    )
  }
  if operation is Q15MultiplyRoundedSaturating && lane != I16x8 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="q15 rounded saturating multiply requires i16x8 lanes",
    )
  }
  self.shape([V128, V128], [V128])
}

///|
pub fn[Inst] TargetInstructionVerifier::vector_int_shift(
  self : TargetInstructionVerifier[Inst],
  lane : @lowering.VectorLane,
) -> Unit raise TargetVCodeVerifyError {
  if !lane.is_integer() {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="vector integer shift requires integer lanes",
    )
  }
  self.shape([V128, I32], [V128])
}

///|
pub fn[Inst] TargetInstructionVerifier::vector_int_compare(
  self : TargetInstructionVerifier[Inst],
  lane : @lowering.VectorLane,
) -> Unit raise TargetVCodeVerifyError {
  if !lane.is_integer() {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="vector integer comparison requires integer lanes",
    )
  }
  self.shape([V128, V128], [V128])
}

///|
pub fn[Inst] TargetInstructionVerifier::vector_float_unary(
  self : TargetInstructionVerifier[Inst],
  lane : @lowering.VectorLane,
) -> Unit raise TargetVCodeVerifyError {
  if lane != F32x4 && lane != F64x2 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="vector float unary operation requires floating lanes",
    )
  }
  self.shape([V128], [V128])
}

///|
pub fn[Inst] TargetInstructionVerifier::vector_float_binary(
  self : TargetInstructionVerifier[Inst],
  lane : @lowering.VectorLane,
) -> Unit raise TargetVCodeVerifyError {
  if lane != F32x4 && lane != F64x2 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="vector float operation requires floating lanes",
    )
  }
  self.shape([V128, V128], [V128])
}

///|
pub fn[Inst] TargetInstructionVerifier::vector_float_ternary(
  self : TargetInstructionVerifier[Inst],
  lane : @lowering.VectorLane,
) -> Unit raise TargetVCodeVerifyError {
  if lane != F32x4 && lane != F64x2 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="vector float ternary operation requires floating lanes",
    )
  }
  self.shape([V128, V128, V128], [V128])
}

///|
pub fn[Inst] TargetInstructionVerifier::vector_bitwise(
  self : TargetInstructionVerifier[Inst],
  operation : @lowering.VectorBitwiseOp,
) -> Unit raise TargetVCodeVerifyError {
  let arity = match operation {
    Not => 1
    And | Or | Xor | AndNot => 2
    BitSelect => 3
  }
  self.shape(Array::make(arity, V128), [V128])
}

///|
pub fn[Inst] TargetInstructionVerifier::vector_load_zero(
  self : TargetInstructionVerifier[Inst],
  width : @native.AccessWidth,
) -> Unit raise TargetVCodeVerifyError {
  if width != W32 && width != W64 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="vector load-zero requires width 32 or 64",
    )
  }
  self.shape([Ptr64], [V128])
}

///|
pub fn[Inst] TargetInstructionVerifier::vector_load_extend(
  self : TargetInstructionVerifier[Inst],
  lane : @lowering.VectorLane,
) -> Unit raise TargetVCodeVerifyError {
  if lane != I16x8 && lane != I32x4 && lane != I64x2 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="vector load-extend requires widened integer lanes",
    )
  }
  self.shape([Ptr64], [V128])
}

///|
pub fn[Inst] TargetInstructionVerifier::vector_load_lane(
  self : TargetInstructionVerifier[Inst],
  lane : @lowering.VectorLane,
  index : Int32,
) -> Unit raise TargetVCodeVerifyError {
  if index < 0 || index >= lane.lane_count() {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="vector load-lane index is out of range",
    )
  }
  self.shape([Ptr64, V128], [V128])
}

///|
pub fn[Inst] TargetInstructionVerifier::vector_store_lane(
  self : TargetInstructionVerifier[Inst],
  lane : @lowering.VectorLane,
  index : Int32,
) -> Unit raise TargetVCodeVerifyError {
  if index < 0 || index >= lane.lane_count() {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="vector store-lane index is out of range",
    )
  }
  self.shape([Ptr64, V128], [])
}

///|
pub fn[Inst] TargetInstructionVerifier::vector_conversion(
  self : TargetInstructionVerifier[Inst],
  conversion : VectorConversion,
) -> Unit raise TargetVCodeVerifyError {
  match conversion {
    ExtendLow(lane, _) | ExtendHigh(lane, _) => self.vector_extend(lane)
    Narrow(lane, _) => self.vector_narrow(lane)
    FloatToInt(source, _) => self.vector_float_to_int(source)
    IntToFloat(result, _) => self.vector_int_to_float(result)
    PromoteLowF32x4 | DemoteZeroF64x2 => self.shape([V128], [V128])
  }
}

///|
fn[Inst] TargetInstructionVerifier::vector_extend(
  self : TargetInstructionVerifier[Inst],
  lane : @lowering.VectorLane,
) -> Unit raise TargetVCodeVerifyError {
  if lane != I16x8 && lane != I32x4 && lane != I64x2 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="vector extension requires widened integer lanes",
    )
  }
  self.shape([V128], [V128])
}

///|
fn[Inst] TargetInstructionVerifier::vector_narrow(
  self : TargetInstructionVerifier[Inst],
  lane : @lowering.VectorLane,
) -> Unit raise TargetVCodeVerifyError {
  if lane != I8x16 && lane != I16x8 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="vector narrowing requires i8x16 or i16x8 lanes",
    )
  }
  self.shape([V128, V128], [V128])
}

///|
fn[Inst] TargetInstructionVerifier::vector_float_to_int(
  self : TargetInstructionVerifier[Inst],
  source : @lowering.VectorLane,
) -> Unit raise TargetVCodeVerifyError {
  if source != F32x4 && source != F64x2 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="vector float-to-int requires f32x4 or f64x2 source lanes",
    )
  }
  self.shape([V128], [V128])
}

///|
fn[Inst] TargetInstructionVerifier::vector_int_to_float(
  self : TargetInstructionVerifier[Inst],
  result : @lowering.VectorLane,
) -> Unit raise TargetVCodeVerifyError {
  if result != F32x4 && result != F64x2 {
    raise InvalidInstruction(
      instruction=self.instruction,
      message="vector int-to-float requires f32x4 or f64x2 result lanes",
    )
  }
  self.shape([V128], [V128])
}

///|
pub fn[Inst] TargetInstructionVerifier::vector_predicate(
  self : TargetInstructionVerifier[Inst],
  predicate : @lowering.VectorPredicateOp,
) -> Unit raise TargetVCodeVerifyError {
  match predicate {
    AllTrue(lane) if !lane.is_integer() =>
      raise InvalidInstruction(
        instruction=self.instruction,
        message="vector all-true predicate requires integer lanes",
      )
    BitMask(lane) if !lane.is_integer() =>
      raise InvalidInstruction(
        instruction=self.instruction,
        message="vector bitmask predicate requires integer lanes",
      )
    _ => self.shape([V128], [I32])
  }
}
