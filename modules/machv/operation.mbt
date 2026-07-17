///|
pub(all) enum IntUnaryOp {
  Not
  CountLeadingZeros
  CountTrailingZeros
  PopulationCount
} derive(Debug, Eq, Hash)

///|
pub(all) enum IntBinaryOp {
  Add
  Sub
  Mul
  SignedDiv
  UnsignedDiv
  SignedRem
  UnsignedRem
  And
  Or
  Xor
  ShiftLeft
  SignedShiftRight
  UnsignedShiftRight
  RotateLeft
  RotateRight
} derive(Debug, Eq, Hash)

///|
pub(all) enum IntComparison {
  Equal
  NotEqual
  SignedLessThan
  SignedLessOrEqual
  SignedGreaterThan
  SignedGreaterOrEqual
  UnsignedLessThan
  UnsignedLessOrEqual
  UnsignedGreaterThan
  UnsignedGreaterOrEqual
} derive(Debug, Eq, Hash)

///|
pub(all) enum IntOverflowOp {
  Add(Signedness)
  Sub(Signedness)
  Mul(Signedness)
} derive(Debug, Eq, Hash)

///|
pub(all) enum FloatUnaryOp {
  Negate
  Absolute
  SquareRoot
  Ceil
  Floor
  Truncate
  Nearest
} derive(Debug, Eq, Hash)

///|
pub(all) enum FloatBinaryOp {
  Add
  Sub
  Mul
  Div
  Min
  Max
  CopySign
} derive(Debug, Eq, Hash)

///|
pub(all) enum FloatTernaryOp {
  FusedMultiplyAdd
  FusedNegatedMultiplyAdd
  FusedMultiplySubtract
  FusedNegatedMultiplySubtract
} derive(Debug, Eq, Hash)

///|
pub(all) enum FloatComparison {
  Equal
  NotEqual
  LessThan
  LessOrEqual
  GreaterThan
  GreaterOrEqual
  Ordered
  Unordered
} derive(Debug, Eq, Hash)

///|
pub(all) enum ReferenceComparison {
  Equal
  NotEqual
} derive(Debug, Eq, Hash)

///|
pub(all) enum ConversionOp {
  I32WrapI64
  I64ExtendI32(Signedness)
  F32DemoteF64
  F64PromoteF32
  FloatToInt(FloatType, IntegerType, Signedness, ConversionMode)
  IntToFloat(IntegerType, FloatType, Signedness)
  SignExtend(IntegerType, AccessWidth)
  Bitcast(ValueType, ValueType)
} derive(Debug, Eq, Hash)

///|
pub struct LoadSpec {
  width : AccessWidth
  extension : LoadExtension
  result_type : ValueType
  offset : UInt64
  endianness : Endianness
  trap : TrapReason?
} derive(Debug, Eq, Hash)

///|
pub fn LoadSpec::new(
  width : AccessWidth,
  extension : LoadExtension,
  result_type : ValueType,
  offset : UInt64,
  endianness : Endianness,
  trap : TrapReason?,
) -> LoadSpec {
  { width, extension, result_type, offset, endianness, trap }
}

///|
pub struct StoreSpec {
  width : AccessWidth
  value_type : ValueType
  offset : UInt64
  endianness : Endianness
  trap : TrapReason?
} derive(Debug, Eq, Hash)

///|
pub fn StoreSpec::new(
  width : AccessWidth,
  value_type : ValueType,
  offset : UInt64,
  endianness : Endianness,
  trap : TrapReason?,
) -> StoreSpec {
  { width, value_type, offset, endianness, trap }
}

///|
pub(all) enum AtomicRmwOp {
  Add
  Sub
  And
  Or
  Xor
  Exchange
} derive(Debug, Eq, Hash)

///|
/// A sequentially consistent atomic memory access. Weaker memory orders are
/// not part of the current semantic MachV contract.
pub struct AtomicSpec {
  width : AccessWidth
  value_type : ValueType
  offset : UInt64
  endianness : Endianness
  trap : TrapReason?
} derive(Debug, Eq, Hash)

///|
pub fn AtomicSpec::new(
  width : AccessWidth,
  value_type : ValueType,
  offset : UInt64,
  endianness : Endianness,
  trap : TrapReason?,
) -> AtomicSpec {
  { width, value_type, offset, endianness, trap }
}

///|
pub(all) enum VectorLane {
  I8x16
  I16x8
  I32x4
  I64x2
  F32x4
  F64x2
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorBitwiseOp {
  Not
  And
  Or
  Xor
  AndNot
  BitSelect
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorIntUnaryOp {
  Absolute
  Negate
  PopulationCount
  ExtendAddPairwise(Signedness)
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorHalf {
  Low
  High
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorIntBinaryOp {
  Add
  Sub
  Mul
  Min(Signedness)
  Max(Signedness)
  AverageUnsigned
  SaturatingAdd(Signedness)
  SaturatingSub(Signedness)
  ExtendMultiply(VectorHalf, Signedness)
  Dot16To32Signed
  Q15MultiplyRoundedSaturating
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorIntShiftOp {
  Left
  Right(Signedness)
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorIntComparison {
  Equal
  NotEqual
  LessThan(Signedness)
  LessOrEqual(Signedness)
  GreaterThan(Signedness)
  GreaterOrEqual(Signedness)
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorFloatUnaryOp {
  Absolute
  Negate
  SquareRoot
  Ceil
  Floor
  Truncate
  Nearest
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorFloatBinaryOp {
  Add
  Sub
  Mul
  Div
  Min
  Max
  PseudoMin
  PseudoMax
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorFloatComparison {
  Equal
  NotEqual
  LessThan
  LessOrEqual
  GreaterThan
  GreaterOrEqual
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorPredicateOp {
  AnyTrue
  AllTrue(VectorLane)
  BitMask(VectorLane)
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorConversionOp {
  ExtendLow(VectorLane, Signedness)
  ExtendHigh(VectorLane, Signedness)
  Narrow(VectorLane, Signedness)
  FloatToInt(VectorLane, VectorLane, Signedness, ConversionMode)
  IntToFloat(VectorLane, VectorLane, Signedness)
  PromoteLowF32x4
  DemoteZeroF64x2
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorRelaxedOp {
  Swizzle
  FloatToInt(VectorLane, VectorLane, Signedness)
  FusedMultiplyAdd(VectorLane, FloatTernaryOp)
  LaneSelect(VectorLane)
  Min(VectorLane)
  Max(VectorLane)
  Q15MultiplyRoundedSigned
  Dot8To16Signed
  Dot8To32AddSigned
} derive(Debug, Eq, Hash)

///|
pub(all) enum VectorLoadKind {
  Splat(VectorLane)
  Extend(VectorLane, Signedness)
  Zero(AccessWidth)
  Lane(VectorLane, Int)
} derive(Debug, Eq, Hash)

///|
pub struct VectorLoadSpec {
  kind : VectorLoadKind
  offset : UInt64
  endianness : Endianness
  trap : TrapReason?
} derive(Debug, Eq, Hash)

///|
pub fn VectorLoadSpec::new(
  kind : VectorLoadKind,
  offset : UInt64,
  endianness : Endianness,
  trap : TrapReason?,
) -> VectorLoadSpec {
  { kind, offset, endianness, trap }
}

///|
pub struct VectorStoreLaneSpec {
  lane : VectorLane
  lane_index : Int
  offset : UInt64
  endianness : Endianness
  trap : TrapReason?
} derive(Debug, Eq, Hash)

///|
pub fn VectorStoreLaneSpec::new(
  lane : VectorLane,
  lane_index : Int,
  offset : UInt64,
  endianness : Endianness,
  trap : TrapReason?,
) -> VectorStoreLaneSpec {
  { lane, lane_index, offset, endianness, trap }
}

///|
pub(all) enum VectorOp {
  Splat(VectorLane)
  ExtractLane(VectorLane, Int, Signedness?)
  ReplaceLane(VectorLane, Int)
  Shuffle(FixedArray[Int])
  Swizzle
  Bitwise(VectorBitwiseOp)
  IntUnary(VectorLane, VectorIntUnaryOp)
  IntBinary(VectorLane, VectorIntBinaryOp)
  IntShift(VectorLane, VectorIntShiftOp)
  IntCompare(VectorLane, VectorIntComparison)
  FloatUnary(VectorLane, VectorFloatUnaryOp)
  FloatBinary(VectorLane, VectorFloatBinaryOp)
  FloatTernary(VectorLane, FloatTernaryOp)
  FloatCompare(VectorLane, VectorFloatComparison)
  Predicate(VectorPredicateOp)
  Convert(VectorConversionOp)
  Relaxed(VectorRelaxedOp)
} derive(Debug, Eq)

///|
pub(all) enum Callee {
  Internal(CodeSymbol)
  External(ExternalSymbol)
  Indirect
} derive(Debug, Eq, Hash)

///|
pub struct SemanticCall {
  callee : Callee
  signature : Signature
  protocol : CallProtocol
  behavior : CallBehavior
} derive(Debug, Eq, Hash)

///|
pub fn SemanticCall::new(
  callee : Callee,
  signature : Signature,
  protocol : CallProtocol,
  behavior : CallBehavior,
) -> SemanticCall {
  {
    callee,
    signature: Signature::new(signature.params, signature.results),
    protocol,
    behavior,
  }
}

///|
fn SemanticCall::copy(self : SemanticCall) -> SemanticCall {
  SemanticCall::new(self.callee, self.signature, self.protocol, self.behavior)
}

///|
pub(all) enum Operation {
  I32Const(UInt)
  I64Const(UInt64)
  F32Const(UInt)
  F64Const(UInt64)
  V128Const(UInt64, UInt64)
  NullPtr
  NullGcRef
  CodeAddress(CodeSymbol)
  ExternalAddress(ExternalSymbol)
  DataAddress(DataSymbol)
  EnvironmentField(EnvironmentField)
  StackAddress(StackObject)
  Copy
  Select
  GcRefAddress
  GcRefFromBits
  PointerOffset
  ReferenceCompare(ReferenceComparison)
  IntUnary(IntUnaryOp)
  IntBinary(IntBinaryOp)
  IntHighMultiply(Signedness)
  IntWithOverflow(IntOverflowOp)
  IntCompare(IntComparison)
  FloatUnary(FloatUnaryOp)
  FloatBinary(FloatBinaryOp)
  FloatTernary(FloatTernaryOp)
  FloatCompare(FloatComparison)
  Convert(ConversionOp)
  Load(LoadSpec)
  Store(StoreSpec)
  AtomicLoad(AtomicSpec)
  AtomicStore(AtomicSpec)
  AtomicRmw(AtomicSpec, AtomicRmwOp)
  AtomicCompareExchange(AtomicSpec)
  AtomicFence
  Vector(VectorOp)
  VectorLoad(VectorLoadSpec)
  VectorStoreLane(VectorStoreLaneSpec)
  Call(SemanticCall)
  Safepoint(SafepointKind)
} derive(Debug, Eq)

///|
fn VectorOp::copy(self : VectorOp) -> VectorOp {
  match self {
    Shuffle(mask) =>
      Shuffle(FixedArray::makei(mask.length(), index => mask[index]))
    Splat(_)
    | ExtractLane(_, _, _)
    | ReplaceLane(_, _)
    | Swizzle
    | Bitwise(_)
    | IntUnary(_, _)
    | IntBinary(_, _)
    | IntShift(_, _)
    | IntCompare(_, _)
    | FloatUnary(_, _)
    | FloatBinary(_, _)
    | FloatTernary(_, _)
    | FloatCompare(_, _)
    | Predicate(_)
    | Convert(_)
    | Relaxed(_) => self
  }
}

///|
fn Operation::copy(self : Operation) -> Operation {
  match self {
    Vector(operation) => Vector(operation.copy())
    Call(call) => Call(call.copy())
    I32Const(_)
    | I64Const(_)
    | F32Const(_)
    | F64Const(_)
    | V128Const(_, _)
    | NullPtr
    | NullGcRef
    | CodeAddress(_)
    | ExternalAddress(_)
    | DataAddress(_)
    | EnvironmentField(_)
    | StackAddress(_)
    | Copy
    | Select
    | GcRefAddress
    | GcRefFromBits
    | PointerOffset
    | ReferenceCompare(_)
    | IntUnary(_)
    | IntBinary(_)
    | IntHighMultiply(_)
    | IntWithOverflow(_)
    | IntCompare(_)
    | FloatUnary(_)
    | FloatBinary(_)
    | FloatTernary(_)
    | FloatCompare(_)
    | Convert(_)
    | Load(_)
    | Store(_)
    | AtomicLoad(_)
    | AtomicStore(_)
    | AtomicRmw(_, _)
    | AtomicCompareExchange(_)
    | AtomicFence
    | VectorLoad(_)
    | VectorStoreLane(_)
    | Safepoint(_) => self
  }
}

///|
fn integer_value_type(ty : IntegerType) -> ValueType {
  match ty {
    I32 => I32
    I64 => I64
  }
}

///|
fn float_value_type(ty : FloatType) -> ValueType {
  match ty {
    F32 => F32
    F64 => F64
  }
}

///|
fn is_integer_type(ty : ValueType) -> Bool {
  ty == I32 || ty == I64
}

///|
fn is_float_type(ty : ValueType) -> Bool {
  ty == F32 || ty == F64
}

///|
fn scalar_type_for_lane(lane : VectorLane) -> ValueType {
  match lane {
    I8x16 | I16x8 | I32x4 => I32
    I64x2 => I64
    F32x4 => F32
    F64x2 => F64
  }
}

///|
fn is_integer_lane(lane : VectorLane) -> Bool {
  match lane {
    I8x16 | I16x8 | I32x4 | I64x2 => true
    F32x4 | F64x2 => false
  }
}

///|
fn is_float_lane(lane : VectorLane) -> Bool {
  !is_integer_lane(lane)
}

///|
fn lane_count(lane : VectorLane) -> Int {
  match lane {
    I8x16 => 16
    I16x8 => 8
    I32x4 | F32x4 => 4
    I64x2 | F64x2 => 2
  }
}

///|
fn is_widened_integer_lane(lane : VectorLane) -> Bool {
  lane == I16x8 || lane == I32x4 || lane == I64x2
}

///|
fn verify_vector_conversion(op : VectorConversionOp) -> String? {
  match op {
    ExtendLow(lane, _) | ExtendHigh(lane, _) =>
      if is_widened_integer_lane(lane) {
        None
      } else {
        operation_error(
          "vector extension destination must be i16x8, i32x4, or i64x2",
        )
      }
    Narrow(lane, _) =>
      if lane == I8x16 || lane == I16x8 {
        None
      } else {
        operation_error("vector narrowing destination must be i8x16 or i16x8")
      }
    FloatToInt(source, result, _, _) =>
      if (source == F32x4 && result == I32x4) ||
        (source == F64x2 && result == I32x4) {
        None
      } else {
        operation_error(
          "vector float-to-int conversion requires f32x4 or f64x2 source and i32x4 result",
        )
      }
    IntToFloat(source, result, _) =>
      if source == I32x4 && (result == F32x4 || result == F64x2) {
        None
      } else {
        operation_error(
          "vector int-to-float conversion requires i32x4 source and f32x4 or f64x2 result",
        )
      }
    PromoteLowF32x4 | DemoteZeroF64x2 => None
  }
}

///|
fn verify_relaxed_vector_operation(
  op : VectorRelaxedOp,
  operands : Array[ValueType],
  results : Array[ValueType],
) -> String? {
  match op {
    Swizzle =>
      require_shape(
        operands,
        results,
        [V128, V128],
        [V128],
        "vector.relaxed_swizzle",
      )
    FloatToInt(source, result, _) =>
      match
        verify_vector_conversion(FloatToInt(source, result, Signed, Saturating)) {
        Some(error) => Some(error)
        None =>
          require_shape(
            operands,
            results,
            [V128],
            [V128],
            "vector.relaxed_float_to_int",
          )
      }
    FusedMultiplyAdd(lane, _) => {
      if !is_float_lane(lane) {
        return operation_error(
          "relaxed fused multiply-add requires floating lanes",
        )
      }
      require_shape(
        operands,
        results,
        [V128, V128, V128],
        [V128],
        "vector.relaxed_fma",
      )
    }
    LaneSelect(lane) => {
      if !is_integer_lane(lane) {
        return operation_error("relaxed lane select requires integer lanes")
      }
      require_shape(
        operands,
        results,
        [V128, V128, V128],
        [V128],
        "vector.relaxed_lane_select",
      )
    }
    Min(lane) | Max(lane) => {
      if !is_float_lane(lane) {
        return operation_error("relaxed min/max requires floating lanes")
      }
      require_shape(
        operands,
        results,
        [V128, V128],
        [V128],
        "vector.relaxed_minmax",
      )
    }
    Q15MultiplyRoundedSigned =>
      require_shape(
        operands,
        results,
        [V128, V128],
        [V128],
        "vector.relaxed_q15mulr",
      )
    Dot8To16Signed =>
      require_shape(
        operands,
        results,
        [V128, V128],
        [V128],
        "vector.relaxed_dot8_to16",
      )
    Dot8To32AddSigned =>
      require_shape(
        operands,
        results,
        [V128, V128, V128],
        [V128],
        "vector.relaxed_dot8_to32_add",
      )
  }
}

///|
fn width_bits(width : AccessWidth) -> Int {
  match width {
    W8 => 8
    W16 => 16
    W32 => 32
    W64 => 64
    W128 => 128
  }
}

///|
fn value_type_bits(ty : ValueType) -> Int {
  match ty {
    I32 | F32 => 32
    I64 | F64 | Ptr64 | GcRef64 => 64
    V128 => 128
  }
}

///|
fn operation_error(message : String) -> String? {
  Some(message)
}

///|
fn require_shape(
  operands : Array[ValueType],
  results : Array[ValueType],
  expected_operands : Array[ValueType],
  expected_results : Array[ValueType],
  name : String,
) -> String? {
  if operands != expected_operands {
    return operation_error(
      "\{name} expects operands \{to_repr(expected_operands)}, got \{to_repr(operands)}",
    )
  }
  if results != expected_results {
    return operation_error(
      "\{name} expects results \{to_repr(expected_results)}, got \{to_repr(results)}",
    )
  }
  None
}

///|
fn verify_load_spec(spec : LoadSpec) -> String? {
  let result_bits = value_type_bits(spec.result_type)
  let access_bits = width_bits(spec.width)
  if spec.result_type == V128 {
    if spec.width != W128 || spec.extension != None {
      return operation_error("v128 load requires width 128 without extension")
    }
  } else if spec.result_type == Ptr64 || spec.result_type == GcRef64 {
    if spec.width != W64 || spec.extension != None {
      return operation_error(
        "pointer and GC-reference loads require width 64 without extension",
      )
    }
  } else if is_float_type(spec.result_type) {
    if result_bits != access_bits || spec.extension != None {
      return operation_error(
        "floating loads require an equal-width access without extension",
      )
    }
  } else if access_bits > result_bits {
    return operation_error("load width exceeds its result width")
  } else if access_bits == result_bits && spec.extension != None {
    return operation_error("equal-width integer load cannot extend")
  } else if access_bits < result_bits && spec.extension == None {
    return operation_error("narrow integer load requires signedness")
  }
  None
}

///|
fn verify_store_spec(spec : StoreSpec) -> String? {
  let access_bits = width_bits(spec.width)
  let value_bits = value_type_bits(spec.value_type)
  if spec.value_type == V128 {
    if spec.width != W128 {
      return operation_error("v128 store requires width 128")
    }
  } else if spec.value_type == Ptr64 || spec.value_type == GcRef64 {
    if spec.width != W64 {
      return operation_error("pointer and GC-reference stores require width 64")
    }
  } else if is_float_type(spec.value_type) && access_bits != value_bits {
    return operation_error("floating stores require an equal-width access")
  } else if access_bits > value_bits {
    return operation_error("store width exceeds its value width")
  }
  None
}

///|
fn verify_atomic_spec(spec : AtomicSpec) -> String? {
  if !is_integer_type(spec.value_type) {
    return operation_error("atomic values must be i32 or i64")
  }
  let bits = width_bits(spec.width)
  if bits > value_type_bits(spec.value_type) || bits == 128 {
    return operation_error("atomic width exceeds its integer value type")
  }
  None
}

///|
fn verify_vector_operation(
  op : VectorOp,
  operands : Array[ValueType],
  results : Array[ValueType],
) -> String? {
  match op {
    Splat(lane) =>
      require_shape(
        operands,
        results,
        [scalar_type_for_lane(lane)],
        [V128],
        "vector.splat",
      )
    ExtractLane(lane, index, extension) => {
      if index < 0 || index >= lane_count(lane) {
        return operation_error("vector.extract_lane index is out of range")
      }
      if is_float_lane(lane) || lane == I32x4 || lane == I64x2 {
        if extension is Some(_) {
          return operation_error(
            "full-width and floating lane extraction cannot extend",
          )
        }
      } else if extension is None {
        return operation_error(
          "narrow integer lane extraction requires signedness",
        )
      }
      require_shape(
        operands,
        results,
        [V128],
        [scalar_type_for_lane(lane)],
        "vector.extract_lane",
      )
    }
    ReplaceLane(lane, index) => {
      if index < 0 || index >= lane_count(lane) {
        return operation_error("vector.replace_lane index is out of range")
      }
      require_shape(
        operands,
        results,
        [V128, scalar_type_for_lane(lane)],
        [V128],
        "vector.replace_lane",
      )
    }
    Shuffle(mask) => {
      if mask.length() != 16 {
        return operation_error(
          "vector.shuffle requires exactly 16 lane indices",
        )
      }
      for lane in mask {
        if lane < 0 || lane >= 32 {
          return operation_error("vector.shuffle lane index is out of range")
        }
      }
      require_shape(operands, results, [V128, V128], [V128], "vector.shuffle")
    }
    Swizzle =>
      require_shape(operands, results, [V128, V128], [V128], "vector.swizzle")
    Bitwise(kind) => {
      let arity = match kind {
        Not => 1
        And | Or | Xor | AndNot => 2
        BitSelect => 3
      }
      require_shape(
        operands,
        results,
        Array::make(arity, V128),
        [V128],
        "vector.bitwise",
      )
    }
    IntUnary(lane, operation) => {
      if !is_integer_lane(lane) {
        return operation_error(
          "vector integer unary operation requires integer lanes",
        )
      }
      if operation is ExtendAddPairwise(_) && !is_widened_integer_lane(lane) {
        return operation_error(
          "pairwise extending add destination must be i16x8, i32x4, or i64x2",
        )
      }
      require_shape(operands, results, [V128], [V128], "vector.int_unary")
    }
    IntBinary(lane, operation) => {
      if !is_integer_lane(lane) {
        return operation_error(
          "vector integer operation requires integer lanes",
        )
      }
      match operation {
        ExtendMultiply(_, _) =>
          if !is_widened_integer_lane(lane) {
            return operation_error(
              "extending multiply destination must be i16x8, i32x4, or i64x2",
            )
          }
        Dot16To32Signed =>
          if lane != I32x4 {
            return operation_error(
              "dot16-to32 requires i32x4 destination lanes",
            )
          }
        Q15MultiplyRoundedSaturating =>
          if lane != I16x8 {
            return operation_error(
              "q15 rounded saturating multiply requires i16x8 lanes",
            )
          }
        Add
        | Sub
        | Mul
        | Min(_)
        | Max(_)
        | AverageUnsigned
        | SaturatingAdd(_)
        | SaturatingSub(_) => ()
      }
      require_shape(
        operands,
        results,
        [V128, V128],
        [V128],
        "vector.int_binary",
      )
    }
    IntCompare(lane, _) => {
      if !is_integer_lane(lane) {
        return operation_error(
          "vector integer comparison requires integer lanes",
        )
      }
      require_shape(
        operands,
        results,
        [V128, V128],
        [V128],
        "vector.int_compare",
      )
    }
    IntShift(lane, _) => {
      if !is_integer_lane(lane) {
        return operation_error("vector integer shift requires integer lanes")
      }
      require_shape(operands, results, [V128, I32], [V128], "vector.int_shift")
    }
    FloatUnary(lane, _) => {
      if !is_float_lane(lane) {
        return operation_error(
          "vector float unary operation requires float lanes",
        )
      }
      require_shape(operands, results, [V128], [V128], "vector.float_unary")
    }
    FloatBinary(lane, _) | FloatCompare(lane, _) => {
      if !is_float_lane(lane) {
        return operation_error("vector float operation requires float lanes")
      }
      require_shape(
        operands,
        results,
        [V128, V128],
        [V128],
        "vector.float_binary",
      )
    }
    FloatTernary(lane, _) => {
      if !is_float_lane(lane) {
        return operation_error("vector float operation requires float lanes")
      }
      require_shape(
        operands,
        results,
        [V128, V128, V128],
        [V128],
        "vector.float_ternary",
      )
    }
    Predicate(_) =>
      require_shape(operands, results, [V128], [I32], "vector.predicate")
    Convert(conversion) =>
      match verify_vector_conversion(conversion) {
        Some(error) => Some(error)
        None => {
          let operand_types = match conversion {
            Narrow(_, _) => [V128, V128]
            _ => [V128]
          }
          require_shape(
            operands,
            results,
            operand_types,
            [V128],
            "vector.convert",
          )
        }
      }
    Relaxed(operation) =>
      verify_relaxed_vector_operation(operation, operands, results)
  }
}

///|
fn verify_vector_load_spec(spec : VectorLoadSpec) -> String? {
  match spec.kind {
    Splat(_) => None
    Extend(lane, _) =>
      match lane {
        I16x8 | I32x4 | I64x2 => None
        I8x16 | F32x4 | F64x2 =>
          operation_error(
            "vector load-extend requires i16x8, i32x4, or i64x2 destination lanes",
          )
      }
    Zero(width) =>
      if width == W32 || width == W64 {
        None
      } else {
        operation_error("vector load-zero requires width 32 or 64")
      }
    Lane(lane, lane_index) =>
      if lane_index < 0 || lane_index >= lane_count(lane) {
        operation_error("vector load-lane index is out of range")
      } else {
        None
      }
  }
}

///|
fn verify_vector_store_lane_spec(spec : VectorStoreLaneSpec) -> String? {
  if spec.lane_index < 0 || spec.lane_index >= lane_count(spec.lane) {
    operation_error("vector store-lane index is out of range")
  } else {
    None
  }
}

///|
fn call_operand_types(call : SemanticCall) -> Array[ValueType] {
  let types = call.signature.params.copy()
  if call.callee is Indirect {
    types.insert(0, Ptr64)
  }
  types
}

///|
fn verify_call_operands(
  call : SemanticCall,
  operands : Array[ValueType],
  context : String,
) -> String? {
  match call.callee {
    Internal(symbol) =>
      if symbol.name.is_empty() {
        return operation_error("\{context} internal symbol must not be empty")
      }
    External(symbol) =>
      if symbol.name.is_empty() {
        return operation_error("\{context} external symbol must not be empty")
      }
    Indirect => ()
  }
  let expected = call_operand_types(call)
  if operands != expected {
    return operation_error(
      "\{context} expects operands \{to_repr(expected)}, got \{to_repr(operands)}",
    )
  }
  None
}

///|
fn verify_operation_contract(
  op : Operation,
  operands : Array[ValueType],
  results : Array[ValueType],
) -> String? {
  match op {
    I32Const(_) => require_shape(operands, results, [], [I32], "i32.const")
    I64Const(_) => require_shape(operands, results, [], [I64], "i64.const")
    F32Const(_) => require_shape(operands, results, [], [F32], "f32.const")
    F64Const(_) => require_shape(operands, results, [], [F64], "f64.const")
    V128Const(_, _) =>
      require_shape(operands, results, [], [V128], "v128.const")
    NullPtr => require_shape(operands, results, [], [Ptr64], "ptr.null")
    NullGcRef => require_shape(operands, results, [], [GcRef64], "gcref.null")
    CodeAddress(symbol) =>
      if symbol.name.is_empty() {
        operation_error("code symbol must not be empty")
      } else {
        require_shape(operands, results, [], [Ptr64], "code.address")
      }
    ExternalAddress(symbol) =>
      if symbol.name.is_empty() {
        operation_error("external symbol must not be empty")
      } else {
        require_shape(operands, results, [], [Ptr64], "external.address")
      }
    DataAddress(symbol) =>
      if symbol.name.is_empty() {
        operation_error("data symbol must not be empty")
      } else {
        require_shape(operands, results, [], [Ptr64], "data.address")
      }
    EnvironmentField(field) =>
      if field.name.is_empty() {
        operation_error("environment field identity must not be empty")
      } else {
        require_shape(
          operands,
          results,
          [Ptr64],
          [field.value_type],
          "environment.field",
        )
      }
    StackAddress(_) =>
      require_shape(operands, results, [], [Ptr64], "stack.address")
    Copy => {
      if operands.length() != 1 || results.length() != 1 {
        return operation_error("copy expects one operand and one result")
      }
      if operands[0] != results[0] {
        return operation_error("copy operand and result types must match")
      }
      None
    }
    Select => {
      if operands.length() != 3 || results.length() != 1 {
        return operation_error("select expects three operands and one result")
      }
      if operands[0] != I32 ||
        operands[1] != operands[2] ||
        operands[1] != results[0] {
        return operation_error(
          "select expects i32 condition and matching value/result types",
        )
      }
      None
    }
    GcRefAddress =>
      require_shape(operands, results, [GcRef64], [Ptr64], "gcref.address")
    GcRefFromBits =>
      require_shape(operands, results, [I64], [GcRef64], "gcref.from_bits")
    PointerOffset =>
      require_shape(operands, results, [Ptr64, I64], [Ptr64], "pointer.offset")
    ReferenceCompare(_) => {
      if operands.length() != 2 ||
        results != [I32] ||
        operands[0] != operands[1] ||
        (operands[0] != Ptr64 && operands[0] != GcRef64) {
        return operation_error(
          "reference comparison expects matching ptr64 or gcref64 operands and i32 result",
        )
      }
      None
    }
    IntUnary(_) => {
      if operands.length() != 1 ||
        results.length() != 1 ||
        !is_integer_type(operands[0]) ||
        operands[0] != results[0] {
        return operation_error(
          "integer unary operation expects one matching i32 or i64 result",
        )
      }
      None
    }
    IntBinary(_) => {
      if operands.length() != 2 ||
        results.length() != 1 ||
        !is_integer_type(operands[0]) ||
        operands[0] != operands[1] ||
        operands[0] != results[0] {
        return operation_error(
          "integer binary operation expects matching i32 or i64 values",
        )
      }
      None
    }
    IntHighMultiply(_) => {
      if operands.length() != 2 ||
        results.length() != 1 ||
        !is_integer_type(operands[0]) ||
        operands[0] != operands[1] ||
        operands[0] != results[0] {
        return operation_error(
          "high-half multiply expects matching i32 or i64 values",
        )
      }
      None
    }
    IntWithOverflow(_) => {
      if operands.length() != 2 ||
        results.length() != 2 ||
        !is_integer_type(operands[0]) ||
        operands[0] != operands[1] ||
        results[0] != operands[0] ||
        results[1] != I32 {
        return operation_error(
          "integer overflow operation expects matching integer operands and [integer, i32] results",
        )
      }
      None
    }
    IntCompare(_) => {
      if operands.length() != 2 ||
        results != [I32] ||
        !is_integer_type(operands[0]) ||
        operands[0] != operands[1] {
        return operation_error(
          "integer comparison expects matching i32 or i64 operands and i32 result",
        )
      }
      None
    }
    FloatUnary(_) => {
      if operands.length() != 1 ||
        results.length() != 1 ||
        !is_float_type(operands[0]) ||
        operands[0] != results[0] {
        return operation_error(
          "float unary operation expects one matching f32 or f64 result",
        )
      }
      None
    }
    FloatBinary(_) => {
      if operands.length() != 2 ||
        results.length() != 1 ||
        !is_float_type(operands[0]) ||
        operands[0] != operands[1] ||
        operands[0] != results[0] {
        return operation_error(
          "float binary operation expects matching f32 or f64 values",
        )
      }
      None
    }
    FloatTernary(_) => {
      if operands.length() != 3 ||
        results.length() != 1 ||
        !is_float_type(operands[0]) ||
        operands[0] != operands[1] ||
        operands[0] != operands[2] ||
        operands[0] != results[0] {
        return operation_error(
          "float ternary operation expects matching f32 or f64 values",
        )
      }
      None
    }
    FloatCompare(_) => {
      if operands.length() != 2 ||
        results != [I32] ||
        !is_float_type(operands[0]) ||
        operands[0] != operands[1] {
        return operation_error(
          "float comparison expects matching f32 or f64 operands and i32 result",
        )
      }
      None
    }
    Convert(conversion) => {
      let expected : (Array[ValueType], Array[ValueType]) = match conversion {
        I32WrapI64 => ([I64], [I32])
        I64ExtendI32(_) => ([I32], [I64])
        F32DemoteF64 => ([F64], [F32])
        F64PromoteF32 => ([F32], [F64])
        FloatToInt(from, to, _, _) =>
          ([float_value_type(from)], [integer_value_type(to)])
        IntToFloat(from, to, _) =>
          ([integer_value_type(from)], [float_value_type(to)])
        SignExtend(integer_type, width) => {
          let ty = integer_value_type(integer_type)
          if width_bits(width) >= value_type_bits(ty) || width == W128 {
            return operation_error(
              "sign extension source width must be narrower than its integer value type",
            )
          }
          ([ty], [ty])
        }
        Bitcast(from, to) => {
          if value_type_bits(from) != value_type_bits(to) ||
            from == GcRef64 ||
            to == GcRef64 {
            return operation_error(
              "bitcast requires equal-width non-GC value types",
            )
          }
          ([from], [to])
        }
      }
      require_shape(operands, results, expected.0, expected.1, "conversion")
    }
    Load(spec) =>
      match verify_load_spec(spec) {
        Some(error) => Some(error)
        None =>
          require_shape(operands, results, [Ptr64], [spec.result_type], "load")
      }
    Store(spec) =>
      match verify_store_spec(spec) {
        Some(error) => Some(error)
        None =>
          require_shape(
            operands,
            results,
            [Ptr64, spec.value_type],
            [],
            "store",
          )
      }
    AtomicLoad(spec) =>
      match verify_atomic_spec(spec) {
        Some(error) => Some(error)
        None =>
          require_shape(
            operands,
            results,
            [Ptr64],
            [spec.value_type],
            "atomic.load",
          )
      }
    AtomicStore(spec) =>
      match verify_atomic_spec(spec) {
        Some(error) => Some(error)
        None =>
          require_shape(
            operands,
            results,
            [Ptr64, spec.value_type],
            [],
            "atomic.store",
          )
      }
    AtomicRmw(spec, _) =>
      match verify_atomic_spec(spec) {
        Some(error) => Some(error)
        None =>
          require_shape(
            operands,
            results,
            [Ptr64, spec.value_type],
            [spec.value_type],
            "atomic.rmw",
          )
      }
    AtomicCompareExchange(spec) =>
      match verify_atomic_spec(spec) {
        Some(error) => Some(error)
        None =>
          require_shape(
            operands,
            results,
            [Ptr64, spec.value_type, spec.value_type],
            [spec.value_type],
            "atomic.compare_exchange",
          )
      }
    AtomicFence => require_shape(operands, results, [], [], "atomic.fence")
    Vector(vector_op) => verify_vector_operation(vector_op, operands, results)
    VectorLoad(spec) =>
      match verify_vector_load_spec(spec) {
        Some(error) => Some(error)
        None => {
          let expected_operands = match spec.kind {
            Lane(_, _) => [Ptr64, V128]
            Splat(_) | Extend(_, _) | Zero(_) => [Ptr64]
          }
          require_shape(
            operands,
            results,
            expected_operands,
            [V128],
            "vector.load",
          )
        }
      }
    VectorStoreLane(spec) =>
      match verify_vector_store_lane_spec(spec) {
        Some(error) => Some(error)
        None =>
          require_shape(
            operands,
            results,
            [Ptr64, V128],
            [],
            "vector.store_lane",
          )
      }
    Call(call) =>
      match verify_call_operands(call, operands, "call") {
        Some(error) => Some(error)
        None =>
          if results != call.signature.results {
            operation_error(
              "call expects results \{to_repr(call.signature.results)}, got \{to_repr(results)}",
            )
          } else {
            None
          }
      }
    Safepoint(_) => require_shape(operands, results, [], [], "safepoint")
  }
}

///|
pub fn Operation::semantics(self : Operation) -> OperationSemantics {
  match self {
    IntBinary(SignedDiv | UnsignedDiv | SignedRem | UnsignedRem) =>
      { ..OperationSemantics::pure(), may_trap: true }
    Convert(FloatToInt(_, _, _, Trapping)) =>
      { ..OperationSemantics::pure(), may_trap: true }
    Load(spec) =>
      {
        ..OperationSemantics::pure(),
        memory: Read,
        may_trap: spec.trap is Some(_),
      }
    Store(spec) =>
      {
        ..OperationSemantics::pure(),
        memory: Write,
        may_trap: spec.trap is Some(_),
      }
    AtomicLoad(spec) =>
      {
        ..OperationSemantics::pure(),
        memory: Read,
        may_trap: spec.trap is Some(_),
      }
    AtomicStore(spec) =>
      {
        ..OperationSemantics::pure(),
        memory: Write,
        may_trap: spec.trap is Some(_),
      }
    AtomicRmw(spec, _) | AtomicCompareExchange(spec) =>
      {
        ..OperationSemantics::pure(),
        memory: ReadWrite,
        may_trap: spec.trap is Some(_),
      }
    AtomicFence => { ..OperationSemantics::pure(), memory: ReadWrite }
    VectorLoad(spec) =>
      {
        ..OperationSemantics::pure(),
        memory: Read,
        may_trap: spec.trap is Some(_),
      }
    VectorStoreLane(spec) =>
      {
        ..OperationSemantics::pure(),
        memory: Write,
        may_trap: spec.trap is Some(_),
      }
    EnvironmentField(_) => { ..OperationSemantics::pure(), memory: Read }
    Call(call) => call.behavior.semantics()
    Safepoint(Gc) => { ..OperationSemantics::pure(), gc_safepoint: true }
    Safepoint(Cancellation) =>
      { ..OperationSemantics::pure(), cancellation_safepoint: true }
    Safepoint(GcAndCancellation) =>
      {
        ..OperationSemantics::pure(),
        gc_safepoint: true,
        cancellation_safepoint: true,
      }
    I32Const(_)
    | I64Const(_)
    | F32Const(_)
    | F64Const(_)
    | V128Const(_, _)
    | NullPtr
    | NullGcRef
    | CodeAddress(_)
    | ExternalAddress(_)
    | DataAddress(_)
    | StackAddress(_)
    | Copy
    | Select
    | GcRefAddress
    | GcRefFromBits
    | PointerOffset
    | ReferenceCompare(_)
    | IntUnary(_)
    | IntBinary(_)
    | IntHighMultiply(_)
    | IntWithOverflow(_)
    | IntCompare(_)
    | FloatUnary(_)
    | FloatBinary(_)
    | FloatTernary(_)
    | FloatCompare(_)
    | Convert(_)
    | Vector(_) => OperationSemantics::pure()
  }
}
