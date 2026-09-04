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
  { memory: None, may_trap: false, other_observable_effect: false, }
}

///|
fn trapping_opcode_semantics() -> OpcodeSemantics {
  { memory: None, may_trap: true, other_observable_effect: false, }
}

///|
fn memory_read_opcode_semantics() -> OpcodeSemantics {
  { memory: Read, may_trap: true, other_observable_effect: false, }
}

///|
fn memory_write_opcode_semantics() -> OpcodeSemantics {
  { memory: Write, may_trap: true, other_observable_effect: false, }
}

///|
fn unknown_opcode_semantics() -> OpcodeSemantics {
  { memory: Unknown, may_trap: true, other_observable_effect: true, }
}

///|
fn @milkir.IntBinaryOp::semantics(
  self : @milkir.IntBinaryOp,
) -> OpcodeSemantics {
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
fn @milkir.IntUnaryOp::semantics(self : @milkir.IntUnaryOp) -> OpcodeSemantics {
  match self {
    Not | CountLeadingZeros | CountTrailingZeros | PopulationCount =>
      pure_opcode_semantics()
  }
}

///|
fn @milkir.FloatBinaryOp::semantics(
  self : @milkir.FloatBinaryOp,
) -> OpcodeSemantics {
  match self {
    Add | Sub | Mul | Div | Min | Max => pure_opcode_semantics()
  }
}

///|
fn @milkir.FloatUnaryOp::semantics(
  self : @milkir.FloatUnaryOp,
) -> OpcodeSemantics {
  match self {
    Neg | Abs | Sqrt | Ceil | Floor | Trunc | Nearest => pure_opcode_semantics()
  }
}

///|
fn @milkir.ConversionOp::semantics(
  self : @milkir.ConversionOp,
) -> OpcodeSemantics {
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
fn @milkir.ScalarOp::semantics(self : @milkir.ScalarOp) -> OpcodeSemantics {
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
fn @milkir.MemoryOp::semantics(self : @milkir.MemoryOp) -> OpcodeSemantics {
  match self {
    Load(_) | LoadNarrow(_, _, _) => memory_read_opcode_semantics()
    Store(_) | StoreNarrow(_) => memory_write_opcode_semantics()
    Vector(LoadExtend(_, _) | LoadSplat(_) | LoadZero(_) | LoadLane(_, _)) =>
      memory_read_opcode_semantics()
    Vector(StoreLane(_, _)) => memory_write_opcode_semantics()
  }
}

///|
fn @milkir.CallOp::semantics(self : @milkir.CallOp) -> OpcodeSemantics {
  match self {
    Direct(_, _) | Pointer(_, _) => unknown_opcode_semantics()
  }
}

///|
fn @milkir.VectorOp::semantics(self : @milkir.VectorOp) -> OpcodeSemantics {
  match self {
    Const(_)
    | Splat(_)
    | ExtractLane(_, _, _)
    | ReplaceLane(_, _)
    | Shuffle(_)
    | Swizzle
    | Bitwise(_)
    | Predicate(_)
    | IntUnary(_, _)
    | IntBinary(_, _)
    | IntShift(_, _)
    | IntCompare(_, _)
    | Narrow(_, _)
    | FloatUnary(_, _)
    | FloatBinary(_, _)
    | FloatCompare(_, _)
    | Convert(_)
    | Relaxed(_) => pure_opcode_semantics()
  }
}

///|
fn @milkir.Opcode::semantics(self : @milkir.Opcode) -> OpcodeSemantics {
  match self {
    Scalar(op) => op.semantics()
    Call(op) => op.semantics()
    Memory(op) => op.semantics()
    GlobalValue(_) => pure_opcode_semantics()
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

///|
fn OpcodeSemantics::can_stage_as_pure_candidate(self : OpcodeSemantics) -> Bool {
  !self.may_trap && !self.other_observable_effect && self.memory is None
}
