///|
fn mem_type_class(ty : @instr.MemType) -> @abi.RegClass {
  match ty {
    I32 | I64 => Int
    F32 => Float32
    F64 => Float64
    V128 => Vector
  }
}

///|
fn float_class(is_f32 : Bool) -> @abi.RegClass {
  if is_f32 {
    Float32
  } else {
    Float64
  }
}

///|
fn require_inst_arity(
  inst : @instr.Inst,
  uses : Int,
  defs : Int,
  block_id : Int,
  inst_index : Int,
) -> Unit raise VerifyError {
  if inst.uses.length() != uses || inst.defs.length() != defs {
    raise InvalidInstruction(
      message="instruction \{inst_index} in block \{block_id} (\{inst.opcode}) has \{inst.uses.length()} uses and \{inst.defs.length()} defs, expected \{uses} uses and \{defs} defs",
    )
  }
}

///|
fn require_use_class(
  inst : @instr.Inst,
  index : Int,
  expected : @abi.RegClass,
  block_id : Int,
  inst_index : Int,
) -> Unit raise VerifyError {
  require_same_class(
    reg_class(inst.uses[index]),
    expected,
    "use \{index} of instruction \{inst_index} in block \{block_id}",
  )
}

///|
fn require_def_class(
  inst : @instr.Inst,
  index : Int,
  expected : @abi.RegClass,
  block_id : Int,
  inst_index : Int,
) -> Unit raise VerifyError {
  require_same_class(
    writable_reg_class(inst.defs[index]),
    expected,
    "def \{index} of instruction \{inst_index} in block \{block_id}",
  )
}

///|
fn require_all_uses(
  inst : @instr.Inst,
  expected : @abi.RegClass,
  block_id : Int,
  inst_index : Int,
) -> Unit raise VerifyError {
  for i in 0..<inst.uses.length() {
    require_use_class(inst, i, expected, block_id, inst_index)
  }
}

///|
fn require_all_defs(
  inst : @instr.Inst,
  expected : @abi.RegClass,
  block_id : Int,
  inst_index : Int,
) -> Unit raise VerifyError {
  for i in 0..<inst.defs.length() {
    require_def_class(inst, i, expected, block_id, inst_index)
  }
}

///|
fn verify_fixed_contract(
  inst : @instr.Inst,
  uses : Int,
  defs : Int,
  use_class : @abi.RegClass,
  def_class : @abi.RegClass,
  block_id : Int,
  inst_index : Int,
) -> Unit raise VerifyError {
  require_inst_arity(inst, uses, defs, block_id, inst_index)
  require_all_uses(inst, use_class, block_id, inst_index)
  require_all_defs(inst, def_class, block_id, inst_index)
}

///|
fn verify_same_class_contract(
  inst : @instr.Inst,
  uses : Int,
  defs : Int,
  block_id : Int,
  inst_index : Int,
) -> Unit raise VerifyError {
  require_inst_arity(inst, uses, defs, block_id, inst_index)
  if uses > 0 {
    let expected = reg_class(inst.uses[0])
    require_all_uses(inst, expected, block_id, inst_index)
    require_all_defs(inst, expected, block_id, inst_index)
  }
}

///|
fn verify_call_contract(
  inst : @instr.Inst,
  result_classes : Array[@abi.RegClass],
  has_pointer_use : Bool,
  block_id : Int,
  inst_index : Int,
) -> Unit raise VerifyError {
  if has_pointer_use && inst.uses.is_empty() {
    raise InvalidInstruction(
      message="pointer call instruction \{inst_index} in block \{block_id} has no callee operand",
    )
  }
  if has_pointer_use {
    require_use_class(inst, 0, Int, block_id, inst_index)
  }
  if inst.defs.length() < result_classes.length() {
    raise InvalidInstruction(
      message="call instruction \{inst_index} in block \{block_id} has \{inst.defs.length()} defs for \{result_classes.length()} results",
    )
  }
  for i, class in result_classes {
    require_def_class(inst, i, class, block_id, inst_index)
  }
  for i in result_classes.length()..<inst.defs.length() {
    if inst.defs[i].reg is Virtual(_) {
      raise InvalidInstruction(
        message="call instruction \{inst_index} in block \{block_id} has a virtual clobber def at index \{i}",
      )
    }
  }
}

///|
fn verify_result_with_clobbers(
  inst : @instr.Inst,
  uses : Int,
  use_class : @abi.RegClass,
  result_class : @abi.RegClass,
  block_id : Int,
  inst_index : Int,
) -> Unit raise VerifyError {
  if inst.uses.length() != uses || inst.defs.is_empty() {
    raise InvalidInstruction(
      message="instruction \{inst_index} in block \{block_id} (\{inst.opcode}) must have \{uses} uses and at least one def",
    )
  }
  require_all_uses(inst, use_class, block_id, inst_index)
  require_def_class(inst, 0, result_class, block_id, inst_index)
  for i in 1..<inst.defs.length() {
    if inst.defs[i].reg is Virtual(_) {
      raise InvalidInstruction(
        message="instruction \{inst_index} in block \{block_id} has a virtual clobber def at index \{i}",
      )
    }
  }
}

///|
fn verify_opcode_contract(
  inst : @instr.Inst,
  block_id : Int,
  inst_index : Int,
) -> Unit raise VerifyError {
  match inst.opcode {
    Add(_)
    | Sub(_)
    | Mul(_)
    | SDiv(_)
    | UDiv(_)
    | And(_)
    | Or(_)
    | Xor(_)
    | Shl(_)
    | AShr(_)
    | LShr(_)
    | Rotr(_)
    | AndNot(_)
    | OrNot(_)
    | XorNot(_)
    | ExtrImm(_, _) =>
      verify_fixed_contract(inst, 2, 1, Int, Int, block_id, inst_index)
    AMD64(SRem(_)) | AMD64(URem(_)) | Umulh | Smulh =>
      verify_result_with_clobbers(inst, 2, Int, Int, block_id, inst_index)
    AddImm(_, _)
    | SubImm(_, _)
    | AndImm(_, _)
    | OrImm(_, _)
    | XorImm(_, _)
    | ShlImm(_, _)
    | AShrImm(_, _)
    | LShrImm(_, _)
    | RotrImm(_, _)
    | Not(_)
    | Clz(_)
    | Popcnt(_)
    | Rbit(_)
    | Extend(_)
    | Truncate =>
      verify_fixed_contract(inst, 1, 1, Int, Int, block_id, inst_index)
    FAdd(is_f32)
    | FSub(is_f32)
    | FMul(is_f32)
    | FDiv(is_f32)
    | FMin(is_f32)
    | FMax(is_f32)
    | FpuMaxnm(is_f32)
    | FpuMinnm(is_f32) => {
      let class = float_class(is_f32)
      verify_fixed_contract(inst, 2, 1, class, class, block_id, inst_index)
    }
    FSqrt(is_f32)
    | FAbs(is_f32)
    | FNeg(is_f32)
    | FCeil(is_f32)
    | FFloor(is_f32)
    | FTrunc(is_f32)
    | FNearest(is_f32) => {
      let class = float_class(is_f32)
      verify_fixed_contract(inst, 1, 1, class, class, block_id, inst_index)
    }
    Load(ty, _) | LoadPtr(ty, _) => {
      require_inst_arity(inst, 1, 1, block_id, inst_index)
      require_use_class(inst, 0, Int, block_id, inst_index)
      require_def_class(inst, 0, mem_type_class(ty), block_id, inst_index)
    }
    Store(ty, _) | StorePtr(ty, _) => {
      require_inst_arity(inst, 2, 0, block_id, inst_index)
      require_use_class(inst, 0, Int, block_id, inst_index)
      require_use_class(inst, 1, mem_type_class(ty), block_id, inst_index)
    }
    Load8S(_)
    | Load8U(_)
    | Load16S(_)
    | Load16U(_)
    | Load32S(_)
    | Load32U(_)
    | LoadPtrNarrow(_, _, _) =>
      verify_fixed_contract(inst, 1, 1, Int, Int, block_id, inst_index)
    Move => verify_same_class_contract(inst, 1, 1, block_id, inst_index)
    LoadConst(_) =>
      verify_fixed_contract(inst, 0, 1, Int, Int, block_id, inst_index)
    LoadConstF32(_) =>
      verify_fixed_contract(inst, 0, 1, Float32, Float32, block_id, inst_index)
    LoadConstF64(_) =>
      verify_fixed_contract(inst, 0, 1, Float64, Float64, block_id, inst_index)
    Cmp(_, _) =>
      verify_fixed_contract(inst, 2, 1, Int, Int, block_id, inst_index)
    IntCmp(_) =>
      verify_fixed_contract(inst, 2, 0, Int, Int, block_id, inst_index)
    FCmp(_) => {
      require_inst_arity(inst, 2, 1, block_id, inst_index)
      let class = reg_class(inst.uses[0])
      if class is Int || class is Vector {
        raise RegisterClassMismatch(
          message="float comparison in block \{block_id} has non-float operands",
        )
      }
      require_use_class(inst, 1, class, block_id, inst_index)
      require_def_class(inst, 0, Int, block_id, inst_index)
    }
    IntToFloat(kind) => {
      let result_class : @abi.RegClass = match kind {
        I32SToF32 | I32UToF32 | I64SToF32 | I64UToF32 => Float32
        I32SToF64 | I32UToF64 | I64SToF64 | I64UToF64 => Float64
      }
      verify_fixed_contract(inst, 1, 1, Int, result_class, block_id, inst_index)
    }
    FPromote =>
      verify_fixed_contract(inst, 1, 1, Float32, Float64, block_id, inst_index)
    FDemote =>
      verify_fixed_contract(inst, 1, 1, Float64, Float32, block_id, inst_index)
    Bitcast => {
      require_inst_arity(inst, 1, 1, block_id, inst_index)
      let source = reg_class(inst.uses[0])
      let result = writable_reg_class(inst.defs[0])
      if source is Vector || result is Vector {
        require_same_class(result, source, "vector bitcast result")
      }
    }
    Select => {
      require_inst_arity(inst, 3, 1, block_id, inst_index)
      require_use_class(inst, 0, Int, block_id, inst_index)
      let class = reg_class(inst.uses[1])
      require_use_class(inst, 2, class, block_id, inst_index)
      require_def_class(inst, 0, class, block_id, inst_index)
    }
    SelectCmp(_, _) => {
      require_inst_arity(inst, 4, 1, block_id, inst_index)
      require_use_class(inst, 0, Int, block_id, inst_index)
      require_use_class(inst, 1, Int, block_id, inst_index)
      let class = reg_class(inst.uses[2])
      require_use_class(inst, 3, class, block_id, inst_index)
      require_def_class(inst, 0, class, block_id, inst_index)
    }
    Nop | TrapIf(_, _) | AdjustSP(_) =>
      require_inst_arity(inst, 0, 0, block_id, inst_index)
    TrapIfUgt(_) | TrapIfUge(_) | TrapIfDivOverflow(_, _) =>
      verify_fixed_contract(inst, 2, 0, Int, Int, block_id, inst_index)
    FpuCmp(is_f32) => {
      let class = float_class(is_f32)
      verify_fixed_contract(inst, 2, 0, class, class, block_id, inst_index)
    }
    TrapIfZero(_, _) =>
      verify_fixed_contract(inst, 1, 0, Int, Int, block_id, inst_index)
    FcvtToInt(is_f32, _, _) =>
      verify_fixed_contract(
        inst,
        1,
        1,
        float_class(is_f32),
        Int,
        block_id,
        inst_index,
      )
    FpuSel(is_f32, _) => {
      let class = float_class(is_f32)
      verify_fixed_contract(inst, 2, 1, class, class, block_id, inst_index)
    }
    AddShifted(_, _)
    | AddExtend(_, _)
    | SubExtend(_, _)
    | SubShifted(_, _)
    | AndShifted(_, _)
    | OrShifted(_, _)
    | XorShifted(_, _)
    | AddShifted32(_, _)
    | SubShifted32(_, _)
    | AndShifted32(_, _)
    | OrShifted32(_, _)
    | XorShifted32(_, _)
    | Umull
    | Smull => verify_fixed_contract(inst, 2, 1, Int, Int, block_id, inst_index)
    Madd | Msub | Madd32 | Msub32 =>
      verify_fixed_contract(inst, 3, 1, Int, Int, block_id, inst_index)
    Mneg | Mneg32 =>
      verify_fixed_contract(inst, 2, 1, Int, Int, block_id, inst_index)
    ReturnCallIndirect(stack_arg_bytes, num_results) => {
      if stack_arg_bytes < 0 || num_results < 0 {
        raise InvalidInstruction(
          message="indirect tail call in block \{block_id} has negative call metadata",
        )
      }
      if inst.uses.is_empty() {
        raise InvalidInstruction(
          message="indirect tail call in block \{block_id} has no callee operand",
        )
      }
      require_use_class(inst, 0, Int, block_id, inst_index)
    }
    CallExternalIfI32NeImm(_, _) => {
      if inst.uses.length() != 1 {
        raise InvalidInstruction(
          message="conditional external call in block \{block_id} must have one operand",
        )
      }
      require_use_class(inst, 0, Int, block_id, inst_index)
      for writable in inst.defs {
        if writable.reg is Virtual(_) {
          raise InvalidInstruction(
            message="conditional external call in block \{block_id} has a virtual clobber",
          )
        }
      }
    }
    StackLoad(_) => require_inst_arity(inst, 0, 1, block_id, inst_index)
    StackStore(_) | StoreToStack(_) =>
      require_inst_arity(inst, 1, 0, block_id, inst_index)
    LoadStackParam(_, class) =>
      verify_fixed_contract(inst, 0, 1, class, class, block_id, inst_index)
    LoadPtrRegOffset(ty, _, _, _) => {
      require_inst_arity(inst, 2, 1, block_id, inst_index)
      require_all_uses(inst, Int, block_id, inst_index)
      require_def_class(inst, 0, mem_type_class(ty), block_id, inst_index)
    }
    LoadPtrNarrowRegOffset(bits, _, _, _, _) => {
      if bits != 8 && bits != 16 && bits != 32 {
        raise InvalidInstruction(
          message="narrow pointer load has invalid width \{bits}",
        )
      }
      verify_fixed_contract(inst, 2, 1, Int, Int, block_id, inst_index)
    }
    StorePtrRegOffset(ty, _, _, _) => {
      require_inst_arity(inst, 3, 0, block_id, inst_index)
      require_use_class(inst, 0, Int, block_id, inst_index)
      require_use_class(inst, 1, Int, block_id, inst_index)
      require_use_class(inst, 2, mem_type_class(ty), block_id, inst_index)
    }
    StorePtrNarrowRegOffset(bits, _, _, _) => {
      if bits != 8 && bits != 16 && bits != 32 {
        raise InvalidInstruction(
          message="narrow pointer store has invalid width \{bits}",
        )
      }
      verify_fixed_contract(inst, 3, 0, Int, Int, block_id, inst_index)
    }
    StorePtrNarrow(bits, _) => {
      if bits != 8 && bits != 16 && bits != 32 {
        raise InvalidInstruction(
          message="narrow pointer store has invalid width \{bits}",
        )
      }
      verify_fixed_contract(inst, 2, 0, Int, Int, block_id, inst_index)
    }
    LoadExternalFuncAddr(_) | LoadCodeAddr(_) | LoadSP =>
      verify_fixed_contract(inst, 0, 1, Int, Int, block_id, inst_index)
    LoadSafepointId(root_count) => {
      if root_count < 0 {
        raise InvalidInstruction(
          message="safepoint root count cannot be negative",
        )
      }
      verify_fixed_contract(inst, 0, 1, Int, Int, block_id, inst_index)
    }
    CallPtr(num_args, result_classes, clobber_class) => {
      if num_args < 0 {
        raise InvalidInstruction(
          message="pointer call argument count cannot be negative",
        )
      }
      let extra_uses = if clobber_class is Internal { 2 } else { 1 }
      if inst.uses.length() > num_args + extra_uses {
        raise InvalidInstruction(
          message="pointer call in block \{block_id} has \{inst.uses.length()} uses for \{num_args} arguments",
        )
      }
      verify_call_contract(inst, result_classes, true, block_id, inst_index)
    }
    CallDirect(_, num_args, result_classes, clobber_class)
    | CallExternal(_, num_args, result_classes, clobber_class) => {
      if num_args < 0 {
        raise InvalidInstruction(
          message="direct call argument count cannot be negative",
        )
      }
      let extra_uses = if clobber_class is Internal { 1 } else { 0 }
      if inst.uses.length() > num_args + extra_uses {
        raise InvalidInstruction(
          message="direct call in block \{block_id} has \{inst.uses.length()} uses for \{num_args} arguments",
        )
      }
      verify_call_contract(inst, result_classes, false, block_id, inst_index)
    }
    LoadConstV128(_) =>
      verify_fixed_contract(inst, 0, 1, Vector, Vector, block_id, inst_index)
    SIMDSplat(_) => {
      require_inst_arity(inst, 1, 1, block_id, inst_index)
      require_use_class(inst, 0, Int, block_id, inst_index)
      require_def_class(inst, 0, Vector, block_id, inst_index)
    }
    SIMDSplatF(is_f32) =>
      verify_fixed_contract(
        inst,
        1,
        1,
        float_class(is_f32),
        Vector,
        block_id,
        inst_index,
      )
    SIMDExtractU(_, _) | SIMDExtractS(_, _) =>
      verify_fixed_contract(inst, 1, 1, Vector, Int, block_id, inst_index)
    SIMDExtractF(is_f32, _) =>
      verify_fixed_contract(
        inst,
        1,
        1,
        Vector,
        float_class(is_f32),
        block_id,
        inst_index,
      )
    SIMDInsert(_, _) => {
      require_inst_arity(inst, 2, 1, block_id, inst_index)
      require_use_class(inst, 0, Vector, block_id, inst_index)
      require_use_class(inst, 1, Int, block_id, inst_index)
      require_def_class(inst, 0, Vector, block_id, inst_index)
    }
    SIMDInsertF(is_f32, _) => {
      require_inst_arity(inst, 2, 1, block_id, inst_index)
      require_use_class(inst, 0, Vector, block_id, inst_index)
      require_use_class(inst, 1, float_class(is_f32), block_id, inst_index)
      require_def_class(inst, 0, Vector, block_id, inst_index)
    }
    SIMDShuffle(_) =>
      verify_fixed_contract(inst, 2, 3, Vector, Vector, block_id, inst_index)
    SIMDSwizzle
    | SIMDAnd
    | SIMDBic
    | SIMDOr
    | SIMDXor
    | SIMDAdd(_)
    | SIMDSub(_)
    | SIMDMul(_)
    | SIMDSqadd(_)
    | SIMDUqadd(_)
    | SIMDSqsub(_)
    | SIMDUqsub(_)
    | SIMDSmin(_)
    | SIMDUmin(_)
    | SIMDSmax(_)
    | SIMDUmax(_)
    | SIMDUrhadd(_)
    | SIMDShiftByVec(_, _)
    | SIMDCmp(_, _)
    | SIMDNarrow(_, _)
    | SIMDExtMulLow(_, _)
    | SIMDExtMulHigh(_, _)
    | SIMDDot
    | SIMDQ15MulrSat
    | SIMDFAdd(_)
    | SIMDFSub(_)
    | SIMDFMul(_)
    | SIMDFDiv(_)
    | SIMDFMin(_)
    | SIMDFMax(_)
    | SIMDFPMin(_)
    | SIMDFPMax(_)
    | SIMDFCmp(_, _) =>
      verify_fixed_contract(inst, 2, 1, Vector, Vector, block_id, inst_index)
    SIMDNot
    | SIMDAbs(_)
    | SIMDNeg(_)
    | SIMDCnt
    | SIMDExtendLow(_, _)
    | SIMDExtendHigh(_, _)
    | SIMDExtAddPairwise(_, _)
    | SIMDFAbs(_)
    | SIMDFNeg(_)
    | SIMDFSqrt(_)
    | SIMDFCeil(_)
    | SIMDFFloor(_)
    | SIMDFTrunc(_)
    | SIMDFNearest(_)
    | SIMDFCvtToIntS(_)
    | SIMDFCvtToIntU(_)
    | SIMDIntToFloatS(_)
    | SIMDIntToFloatU(_)
    | SIMDTruncSatF64ToI32SZero
    | SIMDTruncSatF64ToI32UZero
    | SIMDConvertLowI32ToF64S
    | SIMDConvertLowI32ToF64U
    | SIMDDemoteF64ToF32Zero
    | SIMDPromoteLowF32ToF64 =>
      verify_fixed_contract(inst, 1, 1, Vector, Vector, block_id, inst_index)
    SIMDBsl | SIMDFMla(_) | SIMDFMls(_) =>
      verify_fixed_contract(inst, 3, 1, Vector, Vector, block_id, inst_index)
    SIMDAnyTrue => {
      require_inst_arity(inst, 1, 2, block_id, inst_index)
      require_use_class(inst, 0, Vector, block_id, inst_index)
      require_def_class(inst, 0, Int, block_id, inst_index)
      require_def_class(inst, 1, Vector, block_id, inst_index)
    }
    SIMDAllTrue(lane) => {
      let defs = if lane is D64 { 1 } else { 2 }
      require_inst_arity(inst, 1, defs, block_id, inst_index)
      require_use_class(inst, 0, Vector, block_id, inst_index)
      require_def_class(inst, 0, Int, block_id, inst_index)
      if defs == 2 {
        require_def_class(inst, 1, Vector, block_id, inst_index)
      }
    }
    SIMDBitmask(lane) => {
      let defs = if lane is B8 { 4 } else { 1 }
      require_inst_arity(inst, 1, defs, block_id, inst_index)
      require_use_class(inst, 0, Vector, block_id, inst_index)
      require_def_class(inst, 0, Int, block_id, inst_index)
      for i in 1..<defs {
        require_def_class(inst, i, Vector, block_id, inst_index)
      }
    }
    SIMDBroadcastShift(_, _) => {
      require_inst_arity(inst, 1, 2, block_id, inst_index)
      require_use_class(inst, 0, Int, block_id, inst_index)
      require_def_class(inst, 0, Int, block_id, inst_index)
      require_def_class(inst, 1, Vector, block_id, inst_index)
    }
    SIMDLoad(_)
    | SIMDLoadSplat(_, _)
    | SIMDLoadExtend(_, _, _)
    | SIMDLoadZero(_, _) =>
      verify_fixed_contract(inst, 1, 1, Int, Vector, block_id, inst_index)
    SIMDStore(_) | SIMDStoreLane(_, _, _) => {
      require_inst_arity(inst, 2, 0, block_id, inst_index)
      require_use_class(inst, 0, Int, block_id, inst_index)
      require_use_class(inst, 1, Vector, block_id, inst_index)
    }
    SIMDLoadLane(_, _, _) => {
      require_inst_arity(inst, 2, 1, block_id, inst_index)
      require_use_class(inst, 0, Int, block_id, inst_index)
      require_use_class(inst, 1, Vector, block_id, inst_index)
      require_def_class(inst, 0, Vector, block_id, inst_index)
    }
    SIMDRelaxedDot8to16 =>
      verify_fixed_contract(inst, 2, 2, Vector, Vector, block_id, inst_index)
    SIMDRelaxedDot8to32Add =>
      verify_fixed_contract(inst, 3, 2, Vector, Vector, block_id, inst_index)
  }
}
