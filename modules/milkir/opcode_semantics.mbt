///|
priv enum MemoryEffect {
  None
  Read
  Write
  Unknown
}

///|
priv struct OpcodeSemantics {
  memory : MemoryEffect
  may_trap : Bool
  other_observable_effect : Bool
}

///|
fn pure_opcode_semantics() -> OpcodeSemantics {
  {
    memory: MemoryEffect::None,
    may_trap: false,
    other_observable_effect: false,
  }
}

///|
fn trapping_opcode_semantics() -> OpcodeSemantics {
  { memory: MemoryEffect::None, may_trap: true, other_observable_effect: false }
}

///|
fn memory_read_opcode_semantics() -> OpcodeSemantics {
  { memory: Read, may_trap: true, other_observable_effect: false }
}

///|
fn memory_write_opcode_semantics() -> OpcodeSemantics {
  { memory: Write, may_trap: true, other_observable_effect: false }
}

///|
fn unknown_opcode_semantics() -> OpcodeSemantics {
  { memory: Unknown, may_trap: true, other_observable_effect: true }
}

///|
fn IntBinaryOp::semantics(self : IntBinaryOp) -> OpcodeSemantics {
  match self {
    SignedDiv | UnsignedDiv | SignedRem | UnsignedRem =>
      trapping_opcode_semantics()
    Add
    | Sub
    | Mul
    | UnsignedMulHigh
    | SignedMulHigh
    | And
    | Or
    | Xor
    | ShiftLeft
    | SignedShiftRight
    | UnsignedShiftRight
    | RotateLeft
    | RotateRight => pure_opcode_semantics()
  }
}

///|
fn IntUnaryOp::semantics(self : IntUnaryOp) -> OpcodeSemantics {
  match self {
    Not | CountLeadingZeros | CountTrailingZeros | PopulationCount =>
      pure_opcode_semantics()
  }
}

///|
fn FloatBinaryOp::semantics(self : FloatBinaryOp) -> OpcodeSemantics {
  match self {
    Add | Sub | Mul | Div | Min | Max => pure_opcode_semantics()
  }
}

///|
fn FloatUnaryOp::semantics(self : FloatUnaryOp) -> OpcodeSemantics {
  match self {
    Neg | Abs | Sqrt | Ceil | Floor | Trunc | Nearest => pure_opcode_semantics()
  }
}

///|
fn ConversionOp::semantics(self : ConversionOp) -> OpcodeSemantics {
  match self {
    FloatToSignedInt | FloatToUnsignedInt => trapping_opcode_semantics()
    IntReduce
    | SignedExtend
    | UnsignedExtend
    | FloatPromote
    | FloatDemote
    | FloatToSignedIntSaturating
    | FloatToUnsignedIntSaturating
    | SignedIntToFloat
    | UnsignedIntToFloat
    | Bitcast => pure_opcode_semantics()
  }
}

///|
fn ScalarOp::semantics(self : ScalarOp) -> OpcodeSemantics {
  match self {
    IntBinary(op) => op.semantics()
    IntUnary(op) => op.semantics()
    FloatBinary(op) => op.semantics()
    FloatUnary(op) => op.semantics()
    Convert(op) => op.semantics()
    IntConst(_)
    | FloatConst32(_)
    | FloatConst64(_)
    | IntCompare(_)
    | FloatCompare(_)
    | SignExtendFrom(_)
    | Select
    | Copy => pure_opcode_semantics()
  }
}

///|
fn MemoryOp::semantics(self : MemoryOp) -> OpcodeSemantics {
  match self {
    Load(_) | LoadNarrow(_, _, _) => memory_read_opcode_semantics()
    Store(_) | StoreNarrow(_) => memory_write_opcode_semantics()
  }
}

///|
fn CallOp::semantics(self : CallOp) -> OpcodeSemantics {
  match self {
    Direct(_, _) | Pointer(_, _) => unknown_opcode_semantics()
  }
}

///|
fn VectorOp::semantics(self : VectorOp) -> OpcodeSemantics {
  match self {
    LoadExtend(_, _) | LoadSplat(_) | LoadZero(_) | LoadLane(_, _) =>
      memory_read_opcode_semantics()
    StoreLane(_, _) => memory_write_opcode_semantics()
    V128Const(_)
    | Splat(_)
    | ExtractLane(_, _, _)
    | ReplaceLane(_, _)
    | V128Shuffle(_)
    | V128Swizzle
    | V128Not
    | V128And
    | V128AndNot
    | V128Or
    | V128Xor
    | V128Bitselect
    | V128AnyTrue
    | V128AllTrue8
    | V128AllTrue16
    | V128AllTrue32
    | V128AllTrue64
    | V128Bitmask8
    | V128Bitmask16
    | V128Bitmask32
    | V128Bitmask64
    | V128Add8
    | V128Add16
    | V128Add32
    | V128Add64
    | V128Sub8
    | V128Sub16
    | V128Sub32
    | V128Sub64
    | V128Mul16
    | V128Mul32
    | V128Mul64
    | V128AddSat8S
    | V128AddSat8U
    | V128AddSat16S
    | V128AddSat16U
    | V128SubSat8S
    | V128SubSat8U
    | V128SubSat16S
    | V128SubSat16U
    | V128Min8S
    | V128Min8U
    | V128Min16S
    | V128Min16U
    | V128Min32S
    | V128Min32U
    | V128Max8S
    | V128Max8U
    | V128Max16S
    | V128Max16U
    | V128Max32S
    | V128Max32U
    | V128Avgr8U
    | V128Avgr16U
    | V128Abs8
    | V128Abs16
    | V128Abs32
    | V128Abs64
    | V128Neg8
    | V128Neg16
    | V128Neg32
    | V128Neg64
    | V128Popcnt8
    | V128Shl8
    | V128Shl16
    | V128Shl32
    | V128Shl64
    | V128Shr8S
    | V128Shr8U
    | V128Shr16S
    | V128Shr16U
    | V128Shr32S
    | V128Shr32U
    | V128Shr64S
    | V128Shr64U
    | V128Eq8
    | V128Eq16
    | V128Eq32
    | V128Eq64
    | V128Ne8
    | V128Ne16
    | V128Ne32
    | V128Ne64
    | V128Lt8S
    | V128Lt8U
    | V128Lt16S
    | V128Lt16U
    | V128Lt32S
    | V128Lt32U
    | V128Lt64S
    | V128Gt8S
    | V128Gt8U
    | V128Gt16S
    | V128Gt16U
    | V128Gt32S
    | V128Gt32U
    | V128Gt64S
    | V128Le8S
    | V128Le8U
    | V128Le16S
    | V128Le16U
    | V128Le32S
    | V128Le32U
    | V128Le64S
    | V128Ge8S
    | V128Ge8U
    | V128Ge16S
    | V128Ge16U
    | V128Ge32S
    | V128Ge32U
    | V128Ge64S
    | V128Narrow16to8S
    | V128Narrow16to8U
    | V128Narrow32to16S
    | V128Narrow32to16U
    | V128ExtendLow8to16S
    | V128ExtendHigh8to16S
    | V128ExtendLow8to16U
    | V128ExtendHigh8to16U
    | V128ExtendLow16to32S
    | V128ExtendHigh16to32S
    | V128ExtendLow16to32U
    | V128ExtendHigh16to32U
    | V128ExtendLow32to64S
    | V128ExtendHigh32to64S
    | V128ExtendLow32to64U
    | V128ExtendHigh32to64U
    | V128ExtMulLow8to16S
    | V128ExtMulHigh8to16S
    | V128ExtMulLow8to16U
    | V128ExtMulHigh8to16U
    | V128ExtMulLow16to32S
    | V128ExtMulHigh16to32S
    | V128ExtMulLow16to32U
    | V128ExtMulHigh16to32U
    | V128ExtMulLow32to64S
    | V128ExtMulHigh32to64S
    | V128ExtMulLow32to64U
    | V128ExtMulHigh32to64U
    | V128ExtAddPairwise8to16S
    | V128ExtAddPairwise8to16U
    | V128ExtAddPairwise16to32S
    | V128ExtAddPairwise16to32U
    | V128Dot16to32S
    | V128Q15MulrSat16S
    | V128AddF32
    | V128AddF64
    | V128SubF32
    | V128SubF64
    | V128MulF32
    | V128MulF64
    | V128DivF32
    | V128DivF64
    | V128MinF32
    | V128MinF64
    | V128MaxF32
    | V128MaxF64
    | V128PMinF32
    | V128PMinF64
    | V128PMaxF32
    | V128PMaxF64
    | V128AbsF32
    | V128AbsF64
    | V128NegF32
    | V128NegF64
    | V128SqrtF32
    | V128SqrtF64
    | V128CeilF32
    | V128CeilF64
    | V128FloorF32
    | V128FloorF64
    | V128TruncF32
    | V128TruncF64
    | V128NearestF32
    | V128NearestF64
    | V128EqF32
    | V128EqF64
    | V128NeF32
    | V128NeF64
    | V128LtF32
    | V128LtF64
    | V128GtF32
    | V128GtF64
    | V128LeF32
    | V128LeF64
    | V128GeF32
    | V128GeF64
    | V128TruncSatF32toI32S
    | V128TruncSatF32toI32U
    | V128TruncSatF64toI32SZero
    | V128TruncSatF64toI32UZero
    | V128ConvertI32toF32S
    | V128ConvertI32toF32U
    | V128ConvertLowI32toF64S
    | V128ConvertLowI32toF64U
    | V128DemoteF64toF32Zero
    | V128PromoteLowF32toF64
    | V128RelaxedSwizzle
    | V128RelaxedTruncF32toI32S
    | V128RelaxedTruncF32toI32U
    | V128RelaxedTruncF64toI32SZero
    | V128RelaxedTruncF64toI32UZero
    | V128RelaxedMaddF32
    | V128RelaxedNmaddF32
    | V128RelaxedMaddF64
    | V128RelaxedNmaddF64
    | V128RelaxedLaneselect8
    | V128RelaxedLaneselect16
    | V128RelaxedLaneselect32
    | V128RelaxedLaneselect64
    | V128RelaxedMinF32
    | V128RelaxedMaxF32
    | V128RelaxedMinF64
    | V128RelaxedMaxF64
    | V128RelaxedQ15MulrS
    | V128RelaxedDot8to16S
    | V128RelaxedDot8to32AddS => pure_opcode_semantics()
  }
}

///|
fn Opcode::semantics(self : Opcode) -> OpcodeSemantics {
  match self {
    Scalar(op) => op.semantics()
    Call(op) => op.semantics()
    Memory(op) => op.semantics()
    Ext(_, _) => unknown_opcode_semantics()
    Vector(op) => op.semantics()
  }
}

///|
fn MemoryEffect::reads_memory(self : MemoryEffect) -> Bool {
  match self {
    Read | Unknown => true
    None | Write => false
  }
}

///|
fn MemoryEffect::may_write_memory(self : MemoryEffect) -> Bool {
  match self {
    Write | Unknown => true
    None | Read => false
  }
}

///|
fn OpcodeSemantics::must_preserve_if_unused(self : OpcodeSemantics) -> Bool {
  self.may_trap ||
  self.other_observable_effect ||
  self.memory.may_write_memory()
}
