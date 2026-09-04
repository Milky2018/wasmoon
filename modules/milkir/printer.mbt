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
fn VectorIntLane::ir_name(self : VectorIntLane) -> String {
  match self {
    I8 => "i8x16"
    I16 => "i16x8"
    I32 => "i32x4"
    I64 => "i64x2"
  }
}

///|
fn VectorIntLane::bits(self : VectorIntLane) -> Int {
  match self {
    I8 => 8
    I16 => 16
    I32 => 32
    I64 => 64
  }
}

///|
fn VectorIntLane::narrower_name(self : VectorIntLane) -> String {
  match self {
    I8 => abort("i8 has no narrower vector lane")
    I16 => "i8x16"
    I32 => "i16x8"
    I64 => "i32x4"
  }
}

///|
fn VectorIntLane::wider_name(self : VectorIntLane) -> String {
  match self {
    I8 => "i16x8"
    I16 => "i32x4"
    I32 => "i64x2"
    I64 => abort("i64 has no wider vector lane")
  }
}

///|
fn VectorFloatLane::ir_name(self : VectorFloatLane) -> String {
  match self {
    F32 => "f32x4"
    F64 => "f64x2"
  }
}

///|
fn VectorFloatLane::bits(self : VectorFloatLane) -> Int {
  match self {
    F32 => 32
    F64 => 64
  }
}

///|
fn VectorLane::ir_name(self : VectorLane) -> String {
  match self {
    I8 => "i8x16"
    I16 => "i16x8"
    I32 => "i32x4"
    I64 => "i64x2"
    F32 => "f32x4"
    F64 => "f64x2"
  }
}

///|
fn VectorSignedness::suffix(self : VectorSignedness) -> String {
  match self {
    Signed => "s"
    Unsigned => "u"
  }
}

///|
fn VectorHalf::suffix(self : VectorHalf) -> String {
  match self {
    Low => "low"
    High => "high"
  }
}

///|
fn format_vector_int_unary(
  opcode : VectorIntUnaryOp,
  lane : VectorIntLane,
) -> String {
  let prefix = lane.ir_name()
  match opcode {
    Abs => "\{prefix}.abs"
    Neg => "\{prefix}.neg"
    Popcnt => "\{prefix}.popcnt"
    Extend(half, signedness) =>
      "\{prefix}.extend_\{half.suffix()}_\{lane.narrower_name()}_\{signedness.suffix()}"
    ExtAddPairwise(signedness) =>
      "\{prefix}.extadd_pairwise_\{lane.narrower_name()}_\{signedness.suffix()}"
  }
}

///|
fn format_vector_int_binary(
  opcode : VectorIntBinaryOp,
  lane : VectorIntLane,
) -> String {
  let prefix = lane.ir_name()
  match opcode {
    Add => "\{prefix}.add"
    Sub => "\{prefix}.sub"
    Mul => "\{prefix}.mul"
    AddSaturating(signedness) => "\{prefix}.add_sat_\{signedness.suffix()}"
    SubSaturating(signedness) => "\{prefix}.sub_sat_\{signedness.suffix()}"
    Min(signedness) => "\{prefix}.min_\{signedness.suffix()}"
    Max(signedness) => "\{prefix}.max_\{signedness.suffix()}"
    AverageUnsigned => "\{prefix}.avgr_u"
    ExtMul(half, signedness) =>
      "\{prefix}.extmul_\{half.suffix()}_\{lane.narrower_name()}_\{signedness.suffix()}"
    Dot16To32Signed => "i32x4.dot_i16x8_s"
    Q15MulrSaturating => "i16x8.q15mulr_sat_s"
  }
}

///|
fn format_vector_int_shift(
  opcode : VectorIntShiftOp,
  lane : VectorIntLane,
) -> String {
  match opcode {
    Left => "\{lane.ir_name()}.shl"
    Right(signedness) => "\{lane.ir_name()}.shr_\{signedness.suffix()}"
  }
}

///|
fn format_vector_int_compare(
  opcode : VectorIntCompareOp,
  lane : VectorIntLane,
) -> String {
  let name = match opcode {
    Eq => "eq"
    Ne => "ne"
    Lt(signedness) => "lt_\{signedness.suffix()}"
    Gt(signedness) => "gt_\{signedness.suffix()}"
    Le(signedness) => "le_\{signedness.suffix()}"
    Ge(signedness) => "ge_\{signedness.suffix()}"
  }
  "\{lane.ir_name()}.\{name}"
}

///|
fn format_vector_float_unary(
  opcode : VectorFloatUnaryOp,
  lane : VectorFloatLane,
) -> String {
  let name = match opcode {
    Abs => "abs"
    Neg => "neg"
    Sqrt => "sqrt"
    Ceil => "ceil"
    Floor => "floor"
    Trunc => "trunc"
    Nearest => "nearest"
  }
  "\{lane.ir_name()}.\{name}"
}

///|
fn format_vector_float_binary(
  opcode : VectorFloatBinaryOp,
  lane : VectorFloatLane,
) -> String {
  let name = match opcode {
    Add => "add"
    Sub => "sub"
    Mul => "mul"
    Div => "div"
    Min => "min"
    Max => "max"
    PseudoMin => "pmin"
    PseudoMax => "pmax"
  }
  "\{lane.ir_name()}.\{name}"
}

///|
fn format_vector_float_compare(
  opcode : VectorFloatCompareOp,
  lane : VectorFloatLane,
) -> String {
  let name = match opcode {
    Eq => "eq"
    Ne => "ne"
    Lt => "lt"
    Gt => "gt"
    Le => "le"
    Ge => "ge"
  }
  "\{lane.ir_name()}.\{name}"
}

///|
fn format_vector_conversion(opcode : VectorConversionOp) -> String {
  match opcode {
    TruncSatF32ToI32(signedness) =>
      "i32x4.trunc_sat_f32x4_\{signedness.suffix()}"
    TruncSatF64ToI32Zero(signedness) =>
      "i32x4.trunc_sat_f64x2_\{signedness.suffix()}_zero"
    ConvertI32ToF32(signedness) => "f32x4.convert_i32x4_\{signedness.suffix()}"
    ConvertLowI32ToF64(signedness) =>
      "f64x2.convert_low_i32x4_\{signedness.suffix()}"
    DemoteF64ToF32Zero => "f32x4.demote_f64x2_zero"
    PromoteLowF32ToF64 => "f64x2.promote_low_f32x4"
  }
}

///|
fn format_vector_relaxed(opcode : VectorRelaxedOp) -> String {
  match opcode {
    Swizzle => "v128.relaxed_swizzle"
    TruncF32ToI32(signedness) =>
      "v128.relaxed_trunc_f32_to_i32_\{signedness.suffix()}"
    TruncF64ToI32Zero(signedness) =>
      "v128.relaxed_trunc_f64_to_i32_\{signedness.suffix()}_zero"
    Fma(lane, Add) => "v128.relaxed_madd_f\{lane.bits()}"
    Fma(lane, NegatedAdd) => "v128.relaxed_nmadd_f\{lane.bits()}"
    LaneSelect(lane) => "v128.relaxed_laneselect\{lane.bits()}"
    Min(lane) => "v128.relaxed_min_f\{lane.bits()}"
    Max(lane) => "v128.relaxed_max_f\{lane.bits()}"
    Q15MulrSigned => "v128.relaxed_q15mulr_s"
    Dot8To16Signed => "v128.relaxed_dot_8_to_16_s"
    Dot8To32AddSigned => "v128.relaxed_dot_8_to_32_add_s"
  }
}

///|
fn format_vector_memory_opcode(
  opcode : VectorMemoryOp,
  operands : Array[Value],
) -> String {
  let ops = operands.map(format_value).join(", ")
  match opcode {
    LoadExtend(lane, signedness) => {
      let lane_name = match lane {
        I8 => "8x8"
        I16 => "16x4"
        I32 => "32x2"
        I64 => abort("invalid vector extending-load semantics")
      }
      "v128.load\{lane_name}_\{signedness.suffix()} \{ops}"
    }
    LoadSplat(lane) => "v128.load\{lane.bits()}_splat \{ops}"
    LoadZero(lane) => "v128.load\{lane.bits()}_zero \{ops}"
    LoadLane(lane, index) => "v128.load\{lane.bits()}_lane lane=\{index} \{ops}"
    StoreLane(lane, index) =>
      "v128.store\{lane.bits()}_lane lane=\{index} \{ops}"
  }
}

///|
fn format_vector_opcode(opcode : VectorOp, operands : Array[Value]) -> String {
  let ops = operands.map(format_value).join(", ")
  let name = match opcode {
    Const(_) => "v128.const"
    Splat(lane) => "\{lane.ir_name()}.splat"
    ExtractLane(lane, extension, index) => {
      let suffix = match (lane, extension) {
        (I8 | I16, Signed) => "_s"
        (I8 | I16, Unsigned) => "_u"
        (I32 | I64 | F32 | F64, None) => ""
        _ => abort("invalid vector extract-lane semantics")
      }
      "\{lane.ir_name()}.extract_lane\{suffix} \{index}"
    }
    ReplaceLane(lane, index) => "\{lane.ir_name()}.replace_lane \{index}"
    Shuffle(_) => "i8x16.shuffle"
    Swizzle => "i8x16.swizzle"
    Bitwise(bitwise) =>
      match bitwise {
        Not => "v128.not"
        And => "v128.and"
        AndNot => "v128.andnot"
        Or => "v128.or"
        Xor => "v128.xor"
        Bitselect => "v128.bitselect"
      }
    Predicate(predicate) =>
      match predicate {
        AnyTrue => "v128.any_true"
        AllTrue(lane) => "\{lane.ir_name()}.all_true"
        Bitmask(lane) => "\{lane.ir_name()}.bitmask"
      }
    IntUnary(op, lane) => format_vector_int_unary(op, lane)
    IntBinary(op, lane) => format_vector_int_binary(op, lane)
    IntShift(op, lane) => format_vector_int_shift(op, lane)
    IntCompare(op, lane) => format_vector_int_compare(op, lane)
    Narrow(lane, signedness) =>
      "\{lane.ir_name()}.narrow_\{lane.wider_name()}_\{signedness.suffix()}"
    FloatUnary(op, lane) => format_vector_float_unary(op, lane)
    FloatBinary(op, lane) => format_vector_float_binary(op, lane)
    FloatCompare(op, lane) => format_vector_float_compare(op, lane)
    Convert(op) => format_vector_conversion(op)
    Relaxed(op) => format_vector_relaxed(op)
  }
  "\{name} \{ops}"
}

///|
/// Print an opcode with its operands.
fn format_opcode(opcode : Opcode, operands : Array[Value]) -> String {
  let ops = operands.map(format_value).join(", ")
  match opcode {
    Scalar(scalar_op) => format_scalar_opcode(scalar_op, operands)
    // Function calls
    Call(call_op) =>
      match call_op {
        Direct(symbol, _) => "call \{symbol.name}(\{ops})"
        Pointer(num_args, num_results) =>
          "call_ptr(\{num_args}) -> \{num_results} (\{ops})"
      }
    Memory(memory_op) =>
      match memory_op {
        Load(ty) => "load.\{ty} \{ops}"
        Store(ty) => "store.\{ty} \{ops}"
        LoadNarrow(result_ty, bits, signed) => {
          let sign_str = if signed { "s" } else { "u" }
          "load\{bits}_\{sign_str}.\{result_ty} \{ops}"
        }
        StoreNarrow(bits) => "store\{bits} \{ops}"
        Vector(opcode) => format_vector_memory_opcode(opcode, operands)
      }
    GlobalValue(global_value) => "global_value gv\{global_value.id} \{ops}"
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
fn format_global_value(
  global_value : GlobalValue,
  data : GlobalValueData,
) -> String {
  match data {
    ContextField(field, stability, region) => {
      let parameters = [ for parameter in field.parameters => "\{parameter}" ]
      let stability_text = match stability {
        Stable => "stable"
        Mutable => "mutable"
      }
      let region_text = match region {
        Heap(index) => "heap[\{index}]"
        Table(index) => "table[\{index}]"
        Context => "context"
        Other => "other"
      }
      "gv\{global_value.id} = context_field \{field.dialect}:\{field.key}[\{parameters.join(", ")}] : \{format_type(field.ty)} \{stability_text} -> \{region_text}"
    }
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
fn format_block(func : Function, block : Block) -> String {
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
  for inst_id in block.instructions {
    let inst = func.instructions[inst_id]
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
  for global_value in self.global_values {
    sb.write_string(
      "    \{format_global_value(global_value.0, global_value.1)}\n",
    )
  }
  // Blocks
  for block in self.blocks {
    sb.write_string(format_block(self, block))
  }
  sb.write_string("}\n")
  sb.to_string()
}

///|
/// Print using FunctionBuilder
pub fn FunctionBuilder::print(self : FunctionBuilder) -> String {
  self.func.print()
}
