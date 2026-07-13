// IR Printer - Pretty prints IR in a readable text format
// Textual IR format for debugging

///|
/// Print a type
fn format_type(ty : Type) -> String {
  match ty {
    I32 => "i32"
    I64 => "i64"
    F32 => "f32"
    F64 => "f64"
    V128 => "v128"
    Ptr => "ptr"
    Ref => "ref"
    CallableRef => "callable_ref"
    OpaqueRef => "opaque_ref"
  }
}

///|
/// Print a value reference
fn format_value(v : Value) -> String {
  "v\{v.id}"
}

///|
/// Print an integer comparison code
fn format_intcc(cc : IntCC) -> String {
  match cc {
    Eq => "eq"
    Ne => "ne"
    Slt => "slt"
    Sle => "sle"
    Sgt => "sgt"
    Sge => "sge"
    Ult => "ult"
    Ule => "ule"
    Ugt => "ugt"
    Uge => "uge"
  }
}

///|
/// Print a float comparison code
fn format_floatcc(cc : FloatCC) -> String {
  match cc {
    Eq => "eq"
    Ne => "ne"
    Lt => "lt"
    Le => "le"
    Gt => "gt"
    Ge => "ge"
  }
}

///|
fn format_scalar_opcode(opcode : ScalarOp, operands : Array[Value]) -> String {
  let ops = operands.map(format_value).join(", ")
  match opcode {
    IntConst(value) => "iconst \{value}"
    FloatConst32(bits) => "fconst \{Float::reinterpret_from_uint(bits)}"
    FloatConst64(bits) => "fconst \{bits.reinterpret_as_double()}"
    IntBinary(op) =>
      match op {
        Add => "iadd \{ops}"
        Sub => "isub \{ops}"
        Mul => "imul \{ops}"
        UnsignedMulHigh => "umulh \{ops}"
        SignedMulHigh => "smulh \{ops}"
        SignedDiv => "sdiv \{ops}"
        UnsignedDiv => "udiv \{ops}"
        SignedRem => "srem \{ops}"
        UnsignedRem => "urem \{ops}"
        And => "band \{ops}"
        Or => "bor \{ops}"
        Xor => "bxor \{ops}"
        ShiftLeft => "ishl \{ops}"
        SignedShiftRight => "sshr \{ops}"
        UnsignedShiftRight => "ushr \{ops}"
        RotateLeft => "rotl \{ops}"
        RotateRight => "rotr \{ops}"
      }
    IntUnary(op) =>
      match op {
        Not => "bnot \{ops}"
        CountLeadingZeros => "clz \{ops}"
        CountTrailingZeros => "ctz \{ops}"
        PopulationCount => "popcnt \{ops}"
      }
    IntCompare(cc) => "icmp.\{format_intcc(cc)} \{ops}"
    FloatBinary(op) =>
      match op {
        Add => "fadd \{ops}"
        Sub => "fsub \{ops}"
        Mul => "fmul \{ops}"
        Div => "fdiv \{ops}"
        Min => "fmin \{ops}"
        Max => "fmax \{ops}"
      }
    FloatUnary(op) =>
      match op {
        Neg => "fneg \{ops}"
        Abs => "fabs \{ops}"
        Sqrt => "fsqrt \{ops}"
        Ceil => "fceil \{ops}"
        Floor => "ffloor \{ops}"
        Trunc => "ftrunc \{ops}"
        Nearest => "fnearest \{ops}"
      }
    FloatCompare(cc) => "fcmp.\{format_floatcc(cc)} \{ops}"
    Convert(op) =>
      match op {
        IntReduce => "ireduce \{ops}"
        SignedExtend => "sextend \{ops}"
        UnsignedExtend => "uextend \{ops}"
        FloatPromote => "fpromote \{ops}"
        FloatDemote => "fdemote \{ops}"
        FloatToSignedInt => "fcvt_to_sint \{ops}"
        FloatToUnsignedInt => "fcvt_to_uint \{ops}"
        FloatToSignedIntSaturating => "fcvt_to_sint_sat \{ops}"
        FloatToUnsignedIntSaturating => "fcvt_to_uint_sat \{ops}"
        SignedIntToFloat => "sint_to_fcvt \{ops}"
        UnsignedIntToFloat => "uint_to_fcvt \{ops}"
        Bitcast => "bitcast \{ops}"
      }
    SignExtendFrom(bits) => "sextend\{bits} \{ops}"
    Select => "select \{ops}"
    Copy => "copy \{ops}"
  }
}

///|
fn format_vector_opcode(opcode : VectorOp, operands : Array[Value]) -> String {
  let ops = operands.map(format_value).join(", ")
  match opcode {
    V128Const(_) => "v128.const \{ops}"
    Splat(I8) => "i8x16.splat \{ops}"
    Splat(I16) => "i16x8.splat \{ops}"
    Splat(I32) => "i32x4.splat \{ops}"
    Splat(I64) => "i64x2.splat \{ops}"
    Splat(F32) => "f32x4.splat \{ops}"
    Splat(F64) => "f64x2.splat \{ops}"
    ExtractLane(I8, Signed, lane) => "i8x16.extract_lane_s \{lane} \{ops}"
    ExtractLane(I8, Unsigned, lane) => "i8x16.extract_lane_u \{lane} \{ops}"
    ExtractLane(I16, Signed, lane) => "i16x8.extract_lane_s \{lane} \{ops}"
    ExtractLane(I16, Unsigned, lane) => "i16x8.extract_lane_u \{lane} \{ops}"
    ExtractLane(I32, None, lane) => "i32x4.extract_lane \{lane} \{ops}"
    ExtractLane(I64, None, lane) => "i64x2.extract_lane \{lane} \{ops}"
    ExtractLane(F32, None, lane) => "f32x4.extract_lane \{lane} \{ops}"
    ExtractLane(F64, None, lane) => "f64x2.extract_lane \{lane} \{ops}"
    ExtractLane(_, _, _) => abort("invalid vector extract-lane semantics")
    ReplaceLane(I8, lane) => "i8x16.replace_lane \{lane} \{ops}"
    ReplaceLane(I16, lane) => "i16x8.replace_lane \{lane} \{ops}"
    ReplaceLane(I32, lane) => "i32x4.replace_lane \{lane} \{ops}"
    ReplaceLane(I64, lane) => "i64x2.replace_lane \{lane} \{ops}"
    ReplaceLane(F32, lane) => "f32x4.replace_lane \{lane} \{ops}"
    ReplaceLane(F64, lane) => "f64x2.replace_lane \{lane} \{ops}"
    V128Shuffle(_) => "i8x16.shuffle \{ops}"
    V128Swizzle => "i8x16.swizzle \{ops}"
    V128Not => "v128.not \{ops}"
    V128And => "v128.and \{ops}"
    V128AndNot => "v128.andnot \{ops}"
    V128Or => "v128.or \{ops}"
    V128Xor => "v128.xor \{ops}"
    V128Bitselect => "v128.bitselect \{ops}"
    V128AnyTrue => "v128.any_true \{ops}"
    V128AllTrue8 => "i8x16.all_true \{ops}"
    V128AllTrue16 => "i16x8.all_true \{ops}"
    V128AllTrue32 => "i32x4.all_true \{ops}"
    V128AllTrue64 => "i64x2.all_true \{ops}"
    V128Bitmask8 => "i8x16.bitmask \{ops}"
    V128Bitmask16 => "i16x8.bitmask \{ops}"
    V128Bitmask32 => "i32x4.bitmask \{ops}"
    V128Bitmask64 => "i64x2.bitmask \{ops}"
    V128Add8 => "i8x16.add \{ops}"
    V128Add16 => "i16x8.add \{ops}"
    V128Add32 => "i32x4.add \{ops}"
    V128Add64 => "i64x2.add \{ops}"
    V128Sub8 => "i8x16.sub \{ops}"
    V128Sub16 => "i16x8.sub \{ops}"
    V128Sub32 => "i32x4.sub \{ops}"
    V128Sub64 => "i64x2.sub \{ops}"
    V128Mul16 => "i16x8.mul \{ops}"
    V128Mul32 => "i32x4.mul \{ops}"
    V128Mul64 => "i64x2.mul \{ops}"
    V128AddSat8S => "i8x16.add_sat_s \{ops}"
    V128AddSat8U => "i8x16.add_sat_u \{ops}"
    V128AddSat16S => "i16x8.add_sat_s \{ops}"
    V128AddSat16U => "i16x8.add_sat_u \{ops}"
    V128SubSat8S => "i8x16.sub_sat_s \{ops}"
    V128SubSat8U => "i8x16.sub_sat_u \{ops}"
    V128SubSat16S => "i16x8.sub_sat_s \{ops}"
    V128SubSat16U => "i16x8.sub_sat_u \{ops}"
    V128Min8S => "i8x16.min_s \{ops}"
    V128Min8U => "i8x16.min_u \{ops}"
    V128Min16S => "i16x8.min_s \{ops}"
    V128Min16U => "i16x8.min_u \{ops}"
    V128Min32S => "i32x4.min_s \{ops}"
    V128Min32U => "i32x4.min_u \{ops}"
    V128Max8S => "i8x16.max_s \{ops}"
    V128Max8U => "i8x16.max_u \{ops}"
    V128Max16S => "i16x8.max_s \{ops}"
    V128Max16U => "i16x8.max_u \{ops}"
    V128Max32S => "i32x4.max_s \{ops}"
    V128Max32U => "i32x4.max_u \{ops}"
    V128Avgr8U => "i8x16.avgr_u \{ops}"
    V128Avgr16U => "i16x8.avgr_u \{ops}"
    V128Abs8 => "i8x16.abs \{ops}"
    V128Abs16 => "i16x8.abs \{ops}"
    V128Abs32 => "i32x4.abs \{ops}"
    V128Abs64 => "i64x2.abs \{ops}"
    V128Neg8 => "i8x16.neg \{ops}"
    V128Neg16 => "i16x8.neg \{ops}"
    V128Neg32 => "i32x4.neg \{ops}"
    V128Neg64 => "i64x2.neg \{ops}"
    V128Popcnt8 => "i8x16.popcnt \{ops}"
    V128Shl8 => "i8x16.shl \{ops}"
    V128Shl16 => "i16x8.shl \{ops}"
    V128Shl32 => "i32x4.shl \{ops}"
    V128Shl64 => "i64x2.shl \{ops}"
    V128Shr8S => "i8x16.shr_s \{ops}"
    V128Shr8U => "i8x16.shr_u \{ops}"
    V128Shr16S => "i16x8.shr_s \{ops}"
    V128Shr16U => "i16x8.shr_u \{ops}"
    V128Shr32S => "i32x4.shr_s \{ops}"
    V128Shr32U => "i32x4.shr_u \{ops}"
    V128Shr64S => "i64x2.shr_s \{ops}"
    V128Shr64U => "i64x2.shr_u \{ops}"
    V128Eq8 => "i8x16.eq \{ops}"
    V128Eq16 => "i16x8.eq \{ops}"
    V128Eq32 => "i32x4.eq \{ops}"
    V128Eq64 => "i64x2.eq \{ops}"
    V128Ne8 => "i8x16.ne \{ops}"
    V128Ne16 => "i16x8.ne \{ops}"
    V128Ne32 => "i32x4.ne \{ops}"
    V128Ne64 => "i64x2.ne \{ops}"
    V128Lt8S => "i8x16.lt_s \{ops}"
    V128Lt8U => "i8x16.lt_u \{ops}"
    V128Lt16S => "i16x8.lt_s \{ops}"
    V128Lt16U => "i16x8.lt_u \{ops}"
    V128Lt32S => "i32x4.lt_s \{ops}"
    V128Lt32U => "i32x4.lt_u \{ops}"
    V128Lt64S => "i64x2.lt_s \{ops}"
    V128Gt8S => "i8x16.gt_s \{ops}"
    V128Gt8U => "i8x16.gt_u \{ops}"
    V128Gt16S => "i16x8.gt_s \{ops}"
    V128Gt16U => "i16x8.gt_u \{ops}"
    V128Gt32S => "i32x4.gt_s \{ops}"
    V128Gt32U => "i32x4.gt_u \{ops}"
    V128Gt64S => "i64x2.gt_s \{ops}"
    V128Le8S => "i8x16.le_s \{ops}"
    V128Le8U => "i8x16.le_u \{ops}"
    V128Le16S => "i16x8.le_s \{ops}"
    V128Le16U => "i16x8.le_u \{ops}"
    V128Le32S => "i32x4.le_s \{ops}"
    V128Le32U => "i32x4.le_u \{ops}"
    V128Le64S => "i64x2.le_s \{ops}"
    V128Ge8S => "i8x16.ge_s \{ops}"
    V128Ge8U => "i8x16.ge_u \{ops}"
    V128Ge16S => "i16x8.ge_s \{ops}"
    V128Ge16U => "i16x8.ge_u \{ops}"
    V128Ge32S => "i32x4.ge_s \{ops}"
    V128Ge32U => "i32x4.ge_u \{ops}"
    V128Ge64S => "i64x2.ge_s \{ops}"
    V128Narrow16to8S => "i8x16.narrow_i16x8_s \{ops}"
    V128Narrow16to8U => "i8x16.narrow_i16x8_u \{ops}"
    V128Narrow32to16S => "i16x8.narrow_i32x4_s \{ops}"
    V128Narrow32to16U => "i16x8.narrow_i32x4_u \{ops}"
    V128ExtendLow8to16S => "i16x8.extend_low_i8x16_s \{ops}"
    V128ExtendHigh8to16S => "i16x8.extend_high_i8x16_s \{ops}"
    V128ExtendLow8to16U => "i16x8.extend_low_i8x16_u \{ops}"
    V128ExtendHigh8to16U => "i16x8.extend_high_i8x16_u \{ops}"
    V128ExtendLow16to32S => "i32x4.extend_low_i16x8_s \{ops}"
    V128ExtendHigh16to32S => "i32x4.extend_high_i16x8_s \{ops}"
    V128ExtendLow16to32U => "i32x4.extend_low_i16x8_u \{ops}"
    V128ExtendHigh16to32U => "i32x4.extend_high_i16x8_u \{ops}"
    V128ExtendLow32to64S => "i64x2.extend_low_i32x4_s \{ops}"
    V128ExtendHigh32to64S => "i64x2.extend_high_i32x4_s \{ops}"
    V128ExtendLow32to64U => "i64x2.extend_low_i32x4_u \{ops}"
    V128ExtendHigh32to64U => "i64x2.extend_high_i32x4_u \{ops}"
    V128ExtMulLow8to16S => "i16x8.extmul_low_i8x16_s \{ops}"
    V128ExtMulHigh8to16S => "i16x8.extmul_high_i8x16_s \{ops}"
    V128ExtMulLow8to16U => "i16x8.extmul_low_i8x16_u \{ops}"
    V128ExtMulHigh8to16U => "i16x8.extmul_high_i8x16_u \{ops}"
    V128ExtMulLow16to32S => "i32x4.extmul_low_i16x8_s \{ops}"
    V128ExtMulHigh16to32S => "i32x4.extmul_high_i16x8_s \{ops}"
    V128ExtMulLow16to32U => "i32x4.extmul_low_i16x8_u \{ops}"
    V128ExtMulHigh16to32U => "i32x4.extmul_high_i16x8_u \{ops}"
    V128ExtMulLow32to64S => "i64x2.extmul_low_i32x4_s \{ops}"
    V128ExtMulHigh32to64S => "i64x2.extmul_high_i32x4_s \{ops}"
    V128ExtMulLow32to64U => "i64x2.extmul_low_i32x4_u \{ops}"
    V128ExtMulHigh32to64U => "i64x2.extmul_high_i32x4_u \{ops}"
    V128ExtAddPairwise8to16S => "i16x8.extadd_pairwise_i8x16_s \{ops}"
    V128ExtAddPairwise8to16U => "i16x8.extadd_pairwise_i8x16_u \{ops}"
    V128ExtAddPairwise16to32S => "i32x4.extadd_pairwise_i16x8_s \{ops}"
    V128ExtAddPairwise16to32U => "i32x4.extadd_pairwise_i16x8_u \{ops}"
    V128Dot16to32S => "i32x4.dot_i16x8_s \{ops}"
    V128Q15MulrSat16S => "i16x8.q15mulr_sat_s \{ops}"
    V128AddF32 => "f32x4.add \{ops}"
    V128AddF64 => "f64x2.add \{ops}"
    V128SubF32 => "f32x4.sub \{ops}"
    V128SubF64 => "f64x2.sub \{ops}"
    V128MulF32 => "f32x4.mul \{ops}"
    V128MulF64 => "f64x2.mul \{ops}"
    V128DivF32 => "f32x4.div \{ops}"
    V128DivF64 => "f64x2.div \{ops}"
    V128MinF32 => "f32x4.min \{ops}"
    V128MinF64 => "f64x2.min \{ops}"
    V128MaxF32 => "f32x4.max \{ops}"
    V128MaxF64 => "f64x2.max \{ops}"
    V128PMinF32 => "f32x4.pmin \{ops}"
    V128PMinF64 => "f64x2.pmin \{ops}"
    V128PMaxF32 => "f32x4.pmax \{ops}"
    V128PMaxF64 => "f64x2.pmax \{ops}"
    V128AbsF32 => "f32x4.abs \{ops}"
    V128AbsF64 => "f64x2.abs \{ops}"
    V128NegF32 => "f32x4.neg \{ops}"
    V128NegF64 => "f64x2.neg \{ops}"
    V128SqrtF32 => "f32x4.sqrt \{ops}"
    V128SqrtF64 => "f64x2.sqrt \{ops}"
    V128CeilF32 => "f32x4.ceil \{ops}"
    V128CeilF64 => "f64x2.ceil \{ops}"
    V128FloorF32 => "f32x4.floor \{ops}"
    V128FloorF64 => "f64x2.floor \{ops}"
    V128TruncF32 => "f32x4.trunc \{ops}"
    V128TruncF64 => "f64x2.trunc \{ops}"
    V128NearestF32 => "f32x4.nearest \{ops}"
    V128NearestF64 => "f64x2.nearest \{ops}"
    V128EqF32 => "f32x4.eq \{ops}"
    V128EqF64 => "f64x2.eq \{ops}"
    V128NeF32 => "f32x4.ne \{ops}"
    V128NeF64 => "f64x2.ne \{ops}"
    V128LtF32 => "f32x4.lt \{ops}"
    V128LtF64 => "f64x2.lt \{ops}"
    V128GtF32 => "f32x4.gt \{ops}"
    V128GtF64 => "f64x2.gt \{ops}"
    V128LeF32 => "f32x4.le \{ops}"
    V128LeF64 => "f64x2.le \{ops}"
    V128GeF32 => "f32x4.ge \{ops}"
    V128GeF64 => "f64x2.ge \{ops}"
    V128TruncSatF32toI32S => "i32x4.trunc_sat_f32x4_s \{ops}"
    V128TruncSatF32toI32U => "i32x4.trunc_sat_f32x4_u \{ops}"
    V128TruncSatF64toI32SZero => "i32x4.trunc_sat_f64x2_s_zero \{ops}"
    V128TruncSatF64toI32UZero => "i32x4.trunc_sat_f64x2_u_zero \{ops}"
    V128ConvertI32toF32S => "f32x4.convert_i32x4_s \{ops}"
    V128ConvertI32toF32U => "f32x4.convert_i32x4_u \{ops}"
    V128ConvertLowI32toF64S => "f64x2.convert_low_i32x4_s \{ops}"
    V128ConvertLowI32toF64U => "f64x2.convert_low_i32x4_u \{ops}"
    V128DemoteF64toF32Zero => "f32x4.demote_f64x2_zero \{ops}"
    V128PromoteLowF32toF64 => "f64x2.promote_low_f32x4 \{ops}"
    // Relaxed SIMD instructions
    V128RelaxedSwizzle => "v128.relaxed_swizzle \{ops}"
    V128RelaxedTruncF32toI32S => "v128.relaxed_trunc_f32_to_i32_s \{ops}"
    V128RelaxedTruncF32toI32U => "v128.relaxed_trunc_f32_to_i32_u \{ops}"
    V128RelaxedTruncF64toI32SZero =>
      "v128.relaxed_trunc_f64_to_i32_s_zero \{ops}"
    V128RelaxedTruncF64toI32UZero =>
      "v128.relaxed_trunc_f64_to_i32_u_zero \{ops}"
    V128RelaxedMaddF32 => "v128.relaxed_madd_f32 \{ops}"
    V128RelaxedNmaddF32 => "v128.relaxed_nmadd_f32 \{ops}"
    V128RelaxedMaddF64 => "v128.relaxed_madd_f64 \{ops}"
    V128RelaxedNmaddF64 => "v128.relaxed_nmadd_f64 \{ops}"
    V128RelaxedLaneselect8 => "v128.relaxed_laneselect8 \{ops}"
    V128RelaxedLaneselect16 => "v128.relaxed_laneselect16 \{ops}"
    V128RelaxedLaneselect32 => "v128.relaxed_laneselect32 \{ops}"
    V128RelaxedLaneselect64 => "v128.relaxed_laneselect64 \{ops}"
    V128RelaxedMinF32 => "v128.relaxed_min_f32 \{ops}"
    V128RelaxedMaxF32 => "v128.relaxed_max_f32 \{ops}"
    V128RelaxedMinF64 => "v128.relaxed_min_f64 \{ops}"
    V128RelaxedMaxF64 => "v128.relaxed_max_f64 \{ops}"
    V128RelaxedQ15MulrS => "v128.relaxed_q15mulr_s \{ops}"
    V128RelaxedDot8to16S => "v128.relaxed_dot_8_to_16_s \{ops}"
    V128RelaxedDot8to32AddS => "v128.relaxed_dot_8_to_32_add_s \{ops}"
    LoadExtend(lane, extension) => {
      let lane_name = match lane {
        I8 => "8x8"
        I16 => "16x4"
        I32 => "32x2"
        _ => abort("invalid vector extending-load semantics")
      }
      let extension_name = match extension {
        Signed => "s"
        Unsigned => "u"
        None => abort("invalid vector extending-load semantics")
      }
      "v128.load\{lane_name}_\{extension_name} \{ops}"
    }
    LoadSplat(lane) => {
      let bits = match lane {
        I8 => 8
        I16 => 16
        I32 => 32
        I64 => 64
        _ => abort("invalid vector splat-load semantics")
      }
      "v128.load\{bits}_splat \{ops}"
    }
    LoadZero(lane) => {
      let bits = match lane {
        I32 => 32
        I64 => 64
        _ => abort("invalid vector zero-load semantics")
      }
      "v128.load\{bits}_zero \{ops}"
    }
    LoadLane(lane, index) => {
      let bits = match lane {
        I8 => 8
        I16 => 16
        I32 => 32
        I64 => 64
        _ => abort("invalid vector lane-load semantics")
      }
      "v128.load\{bits}_lane lane=\{index} \{ops}"
    }
    StoreLane(lane, index) => {
      let bits = match lane {
        I8 => 8
        I16 => 16
        I32 => 32
        I64 => 64
        _ => abort("invalid vector lane-store semantics")
      }
      "v128.store\{bits}_lane lane=\{index} \{ops}"
    }
  }
}

///|

///|
/// Print an opcode with its operands.
fn format_opcode(opcode : Opcode, operands : Array[Value]) -> String {
  let ops = operands.map(format_value).join(", ")
  match opcode {
    Scalar(scalar_op) => format_scalar_opcode(scalar_op, operands)
    // Function calls
    Call(call_op) =>
      match call_op {
        CallOp::Direct(symbol, _) => "call \{symbol.name}(\{ops})"
        CallOp::Pointer(num_args, num_results) =>
          "call_ptr(\{num_args}) -> \{num_results} (\{ops})"
      }
    Memory(memory_op) =>
      match memory_op {
        MemoryOp::Load(ty) => "load.\{ty} \{ops}"
        MemoryOp::Store(ty) => "store.\{ty} \{ops}"
        MemoryOp::LoadNarrow(result_ty, bits, signed) => {
          let sign_str = if signed { "s" } else { "u" }
          "load\{bits}_\{sign_str}.\{result_ty} \{ops}"
        }
        MemoryOp::StoreNarrow(bits) => "store\{bits} \{ops}"
      }
    Ext(ext, _) => {
      let imms : Array[String] = []
      for imm in ext.immediates {
        imms.push("\{imm}")
      }
      let imm_str = if imms.length() == 0 {
        ""
      } else {
        " [" + imms.join(", ") + "]"
      }
      "ext.\{ext.dialect}.\{ext.opcode}\{imm_str} \{ops}"
    }
    Vector(vector_op) => format_vector_opcode(vector_op, operands)
  }
}

///|
/// Print an instruction
fn format_inst(inst : Inst) -> String {
  let opcode_str = format_opcode(inst.opcode, inst.operands)
  if inst.results.length() == 0 {
    opcode_str
  } else if inst.results.length() == 1 {
    let r = inst.results[0]
    "\{format_value(r)}:\{format_type(r.ty)} = \{opcode_str}"
  } else {
    // Multi-value returns
    let all_results : Array[String] = []
    for r in inst.results {
      all_results.push(format_value(r) + ":" + format_type(r.ty))
    }
    let results_str = all_results.join(", ")
    "(\{results_str}) = \{opcode_str}"
  }
}

///|
/// Print a terminator
fn format_terminator(term : Terminator) -> String {
  match term {
    Jump(target, args) => {
      let args_str = args.map(format_value).join(", ")
      if args.length() > 0 {
        "jump block\{target}(\{args_str})"
      } else {
        "jump block\{target}"
      }
    }
    Brz(cond, then_block, else_block) =>
      "brz \{format_value(cond)}, block\{then_block}, block\{else_block}"
    Brnz(cond, then_block, else_block) =>
      "brnz \{format_value(cond)}, block\{then_block}, block\{else_block}"
    Branch(cond, true_block, true_args, false_block, false_args) => {
      let true_args_str = true_args.map(format_value).join(", ")
      let false_args_str = false_args.map(format_value).join(", ")
      "branch \{format_value(cond)}, block\{true_block}(\{true_args_str}), block\{false_block}(\{false_args_str})"
    }
    BrTable(index, targets, default_target) => {
      let targets_str = targets.map(fn(t) { "block\{t}" }).join(", ")
      "br_table \{format_value(index)}, [\{targets_str}], block\{default_target}"
    }
    Return(values) => {
      let vals_str = values.map(format_value).join(", ")
      if values.length() > 0 {
        "return \{vals_str}"
      } else {
        "return"
      }
    }
    Trap(reason) => "trap \"\{reason}\""
    TrapExit(reason) => "trap_exit \"\{reason}\""
  }
}

///|
/// Print a basic block
fn format_block(block : Block) -> String {
  let sb = StringBuilder::StringBuilder()
  // Block header with parameters
  if block.params.length() > 0 {
    let params_str = block.params
      .map(fn(p) {
        let (v, ty) = p
        "\{format_value(v)}:\{format_type(ty)}"
      })
      .join(", ")
    sb.write_string("block\{block.id}(\{params_str}):\n")
  } else {
    sb.write_string("block\{block.id}:\n")
  }
  // Instructions
  for inst in block.instructions {
    sb.write_string("    \{format_inst(inst)}\n")
  }
  // Terminator
  match block.terminator {
    Some(term) => sb.write_string("    \{format_terminator(term)}\n")
    None => sb.write_string("    ; (no terminator)\n")
  }
  sb.to_string()
}

///|
/// Print a function
pub fn Function::print(self : Function) -> String {
  let sb = StringBuilder::StringBuilder()
  // Function signature
  let params_str = self.params
    .map(fn(p) {
      let (v, ty) = p
      "\{format_value(v)}:\{format_type(ty)}"
    })
    .join(", ")
  let results_str = self.results.map(format_type).join(", ")
  if self.results.length() > 0 {
    sb.write_string(
      "function \{self.name}(\{params_str}) -> \{results_str} {\n",
    )
  } else {
    sb.write_string("function \{self.name}(\{params_str}) {\n")
  }
  // Blocks
  for block in self.blocks {
    sb.write_string(format_block(block))
  }
  sb.write_string("}\n")
  sb.to_string()
}

///|
/// Print using FunctionBuilder
pub fn FunctionBuilder::print(self : FunctionBuilder) -> String {
  self.func.print()
}
