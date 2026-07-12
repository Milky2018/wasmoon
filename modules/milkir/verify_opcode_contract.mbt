///|
fn require_result_arity(
  inst : Inst,
  expected : Int,
  context : String,
) -> Unit raise VerifyError {
  if inst.results.length() != expected {
    raise ArityMismatch(
      message="\{context} expects \{expected} results, got \{inst.results.length()}",
    )
  }
}

///|
fn require_operand_type(
  inst : Inst,
  index : Int,
  expected : Type,
  context : String,
) -> Unit raise VerifyError {
  if inst.args[index].ty != expected {
    raise TypeMismatch(
      message="\{context} operand \{index} has type \{inst.args[index].ty}, expected \{expected}",
    )
  }
}

///|
fn require_result_type(
  inst : Inst,
  index : Int,
  expected : Type,
  context : String,
) -> Unit raise VerifyError {
  if inst.results[index].ty != expected {
    raise TypeMismatch(
      message="\{context} result \{index} has type \{inst.results[index].ty}, expected \{expected}",
    )
  }
}

///|
fn require_operand_types(
  inst : Inst,
  expected : Array[Type],
  context : String,
) -> Unit raise VerifyError {
  require_arity(inst.args.length(), expected.length(), context)
  for i, ty in expected {
    require_operand_type(inst, i, ty, context)
  }
}

///|
fn require_result_types(
  inst : Inst,
  expected : Array[Type],
  context : String,
) -> Unit raise VerifyError {
  require_result_arity(inst, expected.length(), context)
  for i, ty in expected {
    require_result_type(inst, i, ty, context)
  }
}

///|
fn require_single_result(
  inst : Inst,
  expected : Type,
  context : String,
) -> Unit raise VerifyError {
  require_result_arity(inst, 1, context)
  require_result_type(inst, 0, expected, context)
}

///|
fn require_no_results(inst : Inst, context : String) -> Unit raise VerifyError {
  require_result_arity(inst, 0, context)
}

///|
fn require_word_value(ty : Type, context : String) -> Unit raise VerifyError {
  if !(ty is (I32 | I64 | Ptr | Ref | CallableRef | OpaqueRef)) {
    raise TypeMismatch(
      message="\{context} requires an integer or reference representation, got \{ty}",
    )
  }
}

///|
fn same_representation_width(a : Type, b : Type) -> Bool {
  a == b ||
  (a is (I32 | F32) && b is (I32 | F32)) ||
  (
    a is (I64 | F64 | Ptr | Ref | CallableRef | OpaqueRef) &&
    b is (I64 | F64 | Ptr | Ref | CallableRef | OpaqueRef)
  )
}

///|
fn require_pointer_value(ty : Type, context : String) -> Unit raise VerifyError {
  if !(ty is (Ptr | I64)) {
    raise TypeMismatch(message="\{context} requires ptr or i64, got \{ty}")
  }
}

///|
fn require_integer(ty : Type, context : String) -> Unit raise VerifyError {
  if !(ty is (I32 | I64)) {
    raise TypeMismatch(message="\{context} requires i32 or i64, got \{ty}")
  }
}

///|
fn require_equality_comparable(
  ty : Type,
  context : String,
) -> Unit raise VerifyError {
  if !(ty is (I32 | I64 | Ptr | Ref | CallableRef | OpaqueRef)) {
    raise TypeMismatch(message="\{context} cannot compare values of type \{ty}")
  }
}

///|
fn require_float(ty : Type, context : String) -> Unit raise VerifyError {
  if !(ty is (F32 | F64)) {
    raise TypeMismatch(message="\{context} requires f32 or f64, got \{ty}")
  }
}

///|
fn verify_same_type_unary(
  inst : Inst,
  context : String,
) -> Unit raise VerifyError {
  require_arity(inst.args.length(), 1, context)
  require_result_arity(inst, 1, context)
  require_result_type(inst, 0, inst.args[0].ty, context)
}

///|
fn verify_same_type_binary(
  inst : Inst,
  context : String,
) -> Unit raise VerifyError {
  require_arity(inst.args.length(), 2, context)
  require_result_arity(inst, 1, context)
  require_same_type(inst.args[0], inst.args[1], context)
  require_result_type(inst, 0, inst.args[0].ty, context)
}

///|
fn verify_bitwise_binary(inst : Inst) -> Unit raise VerifyError {
  require_arity(inst.args.length(), 2, "bitwise binary")
  require_result_arity(inst, 1, "bitwise binary")
  require_same_type(inst.args[0], inst.args[1], "bitwise binary")
  require_word_value(inst.args[0].ty, "bitwise binary")
  require_word_value(inst.results[0].ty, "bitwise binary")
  if !same_representation_width(inst.args[0].ty, inst.results[0].ty) {
    raise TypeMismatch(
      message="bitwise binary operand type \{inst.args[0].ty} and result type \{inst.results[0].ty} have incompatible representations",
    )
  }
}

///|
fn verify_signature(
  inst : Inst,
  signature : Signature,
  prefix_operands : Int,
  context : String,
) -> Unit raise VerifyError {
  require_arity(
    inst.args.length(),
    prefix_operands + signature.params.length(),
    context,
  )
  require_result_arity(inst, signature.results.length(), context)
  for i, ty in signature.params {
    require_operand_type(inst, prefix_operands + i, ty, context)
  }
  for i, ty in signature.results {
    require_result_type(inst, i, ty, context)
  }
}

///|
fn require_lane(
  lane : Int,
  lane_count : Int,
  context : String,
) -> Unit raise VerifyError {
  if lane < 0 || lane >= lane_count {
    raise TypeMismatch(
      message="\{context} lane \{lane} is outside 0..<\{lane_count}",
    )
  }
}

///|
fn verify_v128_unary(inst : Inst, context : String) -> Unit raise VerifyError {
  require_operand_types(inst, [V128], context)
  require_result_types(inst, [V128], context)
}

///|
fn verify_v128_binary(inst : Inst, context : String) -> Unit raise VerifyError {
  require_operand_types(inst, [V128, V128], context)
  require_result_types(inst, [V128], context)
}

///|
fn verify_v128_ternary(inst : Inst, context : String) -> Unit raise VerifyError {
  require_operand_types(inst, [V128, V128, V128], context)
  require_result_types(inst, [V128], context)
}

///|
fn verify_v128_extract(
  inst : Inst,
  result_type : Type,
  lane : Int,
  lane_count : Int,
  context : String,
) -> Unit raise VerifyError {
  require_operand_types(inst, [V128], context)
  require_result_types(inst, [result_type], context)
  require_lane(lane, lane_count, context)
}

///|
fn verify_v128_replace(
  inst : Inst,
  scalar_type : Type,
  lane : Int,
  lane_count : Int,
  context : String,
) -> Unit raise VerifyError {
  require_operand_types(inst, [V128, scalar_type], context)
  require_result_types(inst, [V128], context)
  require_lane(lane, lane_count, context)
}

///|
fn verify_v128_load_lane(
  inst : Inst,
  lane : Int,
  lane_count : Int,
) -> Unit raise VerifyError {
  require_arity(inst.args.length(), 2, "v128 load lane")
  require_pointer_value(inst.args[0].ty, "v128 load lane")
  require_operand_type(inst, 1, V128, "v128 load lane")
  require_result_types(inst, [V128], "v128 load lane")
  require_lane(lane, lane_count, "v128 load lane")
}

///|
fn verify_v128_store_lane(
  inst : Inst,
  lane : Int,
  lane_count : Int,
) -> Unit raise VerifyError {
  require_arity(inst.args.length(), 2, "v128 store lane")
  require_pointer_value(inst.args[0].ty, "v128 store lane")
  require_operand_type(inst, 1, V128, "v128 store lane")
  require_no_results(inst, "v128 store lane")
  require_lane(lane, lane_count, "v128 store lane")
}

///|
fn verify_scalar_contract(
  inst : Inst,
  opcode : ScalarOp,
) -> Unit raise VerifyError {
  match opcode {
    IntConst(_) => {
      require_arity(inst.args.length(), 0, "iconst")
      require_result_arity(inst, 1, "iconst")
      require_word_value(inst.results[0].ty, "iconst")
    }
    FloatConst(_) => {
      require_arity(inst.args.length(), 0, "fconst")
      require_result_arity(inst, 1, "fconst")
      require_float(inst.results[0].ty, "fconst")
    }
    IntBinary(op) =>
      match op {
        And | Or | Xor => verify_bitwise_binary(inst)
        UnsignedMulHigh | SignedMulHigh => {
          require_operand_types(inst, [I64, I64], "multiply high")
          require_result_types(inst, [I64], "multiply high")
        }
        _ => {
          require_arity(inst.args.length(), 2, "integer binary")
          require_result_arity(inst, 1, "integer binary")
          require_same_type(inst.args[0], inst.args[1], "integer binary")
          require_integer(inst.args[0].ty, "integer binary")
          require_result_type(inst, 0, inst.args[0].ty, "integer binary")
        }
      }
    IntUnary(_) => {
      verify_same_type_unary(inst, "integer unary")
      require_integer(inst.args[0].ty, "integer unary")
    }
    IntCompare(condition) => {
      require_arity(inst.args.length(), 2, "integer compare")
      require_same_type(inst.args[0], inst.args[1], "integer compare")
      if condition is (Eq | Ne) {
        require_equality_comparable(inst.args[0].ty, "integer compare")
      } else {
        require_integer(inst.args[0].ty, "integer compare")
      }
      require_single_result(inst, I32, "integer compare")
    }
    FloatBinary(_) => {
      verify_same_type_binary(inst, "float binary")
      require_float(inst.args[0].ty, "float binary")
    }
    FloatCompare(_) => {
      require_arity(inst.args.length(), 2, "float compare")
      require_same_type(inst.args[0], inst.args[1], "float compare")
      require_float(inst.args[0].ty, "float compare")
      require_single_result(inst, I32, "float compare")
    }
    FloatUnary(_) => {
      verify_same_type_unary(inst, "float unary")
      require_float(inst.args[0].ty, "float unary")
    }
    Convert(conversion) =>
      match conversion {
        IntReduce => {
          require_arity(inst.args.length(), 1, "ireduce")
          require_integer(inst.args[0].ty, "ireduce")
          require_result_types(inst, [I32], "ireduce")
        }
        SignedExtend | UnsignedExtend => {
          require_operand_types(inst, [I32], "integer extend")
          require_result_types(inst, [I64], "integer extend")
        }
        FloatPromote => {
          require_operand_types(inst, [F32], "fpromote")
          require_result_types(inst, [F64], "fpromote")
        }
        FloatDemote => {
          require_operand_types(inst, [F64], "fdemote")
          require_result_types(inst, [F32], "fdemote")
        }
        FloatToSignedInt
        | FloatToUnsignedInt
        | FloatToSignedIntSaturating
        | FloatToUnsignedIntSaturating => {
          require_arity(inst.args.length(), 1, "float-to-int conversion")
          require_result_arity(inst, 1, "float-to-int conversion")
          require_float(inst.args[0].ty, "float-to-int conversion")
          require_integer(inst.results[0].ty, "float-to-int conversion")
        }
        SignedIntToFloat | UnsignedIntToFloat => {
          require_arity(inst.args.length(), 1, "int-to-float conversion")
          require_result_arity(inst, 1, "int-to-float conversion")
          require_integer(inst.args[0].ty, "int-to-float conversion")
          require_float(inst.results[0].ty, "int-to-float conversion")
        }
        Bitcast => {
          require_arity(inst.args.length(), 1, "bitcast")
          require_result_arity(inst, 1, "bitcast")
          let source = inst.args[0].ty
          let target = inst.results[0].ty
          if !same_representation_width(source, target) {
            raise TypeMismatch(
              message="bitcast cannot convert \{source} to \{target}",
            )
          }
        }
      }
    SignExtendFrom(bits) =>
      if bits == 8 || bits == 16 {
        verify_same_type_unary(inst, "in-place sign extension")
        require_integer(inst.args[0].ty, "in-place sign extension")
      } else if bits == 32 {
        require_operand_types(inst, [I64], "sextend32")
        require_result_types(inst, [I64], "sextend32")
      } else {
        raise TypeMismatch(
          message="in-place sign extension has invalid width \{bits}",
        )
      }
    Select => {
      require_arity(inst.args.length(), 3, "select")
      require_result_arity(inst, 1, "select")
      require_operand_type(inst, 0, I32, "select")
      require_same_type(inst.args[1], inst.args[2], "select")
      require_result_type(inst, 0, inst.args[1].ty, "select")
    }
    Copy => verify_same_type_unary(inst, "copy")
  }
}

///|
fn verify_opcode_contract(inst : Inst) -> Unit raise VerifyError {
  match inst.opcode {
    Call(call_op) =>
      match call_op {
        CallOp::Direct(_, signature) =>
          verify_signature(inst, signature, 0, "direct call")
        CallOp::Pointer(num_args, num_results) => {
          if num_args < 0 || num_results < 0 {
            raise ArityMismatch(
              message="pointer call argument and result counts must be non-negative",
            )
          }
          if inst.args.length() != num_args + 1 {
            raise ArityMismatch(
              message="pointer call expects \{num_args + 1} operands, got \{inst.args.length()}",
            )
          }
          require_result_arity(inst, num_results, "pointer call")
          require_pointer_value(inst.args[0].ty, "pointer call callee")
        }
      }
    LoadPtr(result_type) => {
      require_arity(inst.args.length(), 2, "load_ptr")
      require_pointer_value(inst.args[0].ty, "load_ptr")
      require_operand_type(inst, 1, I64, "load_ptr")
      require_result_types(inst, [result_type], "load_ptr")
    }
    StorePtr(value_type) => {
      require_arity(inst.args.length(), 3, "store_ptr")
      require_pointer_value(inst.args[0].ty, "store_ptr")
      require_operand_type(inst, 1, value_type, "store_ptr")
      require_operand_type(inst, 2, I64, "store_ptr")
      require_no_results(inst, "store_ptr")
    }
    LoadPtrNarrow(result_type, bits, _) => {
      require_arity(inst.args.length(), 2, "load_ptr_narrow")
      require_pointer_value(inst.args[0].ty, "load_ptr_narrow")
      require_operand_type(inst, 1, I64, "load_ptr_narrow")
      require_result_types(inst, [result_type], "load_ptr_narrow")
      require_integer(result_type, "load_ptr_narrow")
      if bits != 8 && bits != 16 && bits != 32 {
        raise TypeMismatch(message="load_ptr_narrow has invalid width \{bits}")
      }
    }
    StorePtrNarrow(bits) => {
      require_arity(inst.args.length(), 3, "store_ptr_narrow")
      require_pointer_value(inst.args[0].ty, "store_ptr_narrow")
      require_integer(inst.args[1].ty, "store_ptr_narrow")
      require_operand_type(inst, 2, I64, "store_ptr_narrow")
      require_no_results(inst, "store_ptr_narrow")
      if bits != 8 && bits != 16 && bits != 32 {
        raise TypeMismatch(message="store_ptr_narrow has invalid width \{bits}")
      }
    }
    Memory(memory_op) =>
      match memory_op {
        MemoryOp::Load(result_type) => {
          require_arity(inst.args.length(), 2, "memory load")
          require_pointer_value(inst.args[0].ty, "memory load")
          require_operand_type(inst, 1, I64, "memory load")
          require_result_types(inst, [result_type], "memory load")
        }
        MemoryOp::Store(value_type) => {
          require_arity(inst.args.length(), 3, "memory store")
          require_pointer_value(inst.args[0].ty, "memory store")
          require_operand_type(inst, 1, value_type, "memory store")
          require_operand_type(inst, 2, I64, "memory store")
          require_no_results(inst, "memory store")
        }
        MemoryOp::LoadNarrow(result_type, bits, _) => {
          require_arity(inst.args.length(), 2, "narrow memory load")
          require_pointer_value(inst.args[0].ty, "narrow memory load")
          require_operand_type(inst, 1, I64, "narrow memory load")
          require_result_types(inst, [result_type], "narrow memory load")
          require_integer(result_type, "narrow memory load")
          if bits != 8 && bits != 16 && bits != 32 {
            raise TypeMismatch(
              message="narrow memory load has invalid width \{bits}",
            )
          }
        }
        MemoryOp::StoreNarrow(bits) => {
          require_arity(inst.args.length(), 3, "narrow memory store")
          require_pointer_value(inst.args[0].ty, "narrow memory store")
          require_integer(inst.args[1].ty, "narrow memory store")
          require_operand_type(inst, 2, I64, "narrow memory store")
          require_no_results(inst, "narrow memory store")
          if bits != 8 && bits != 16 && bits != 32 {
            raise TypeMismatch(
              message="narrow memory store has invalid width \{bits}",
            )
          }
        }
      }
    Ext(ext, signature) => {
      if ext.dialect == "" || ext.opcode == "" {
        raise UnverifiableInstruction(
          message="extension instructions require a dialect and opcode name",
        )
      }
      verify_signature(inst, signature, 0, "extension instruction")
    }
    Scalar(scalar_op) => verify_scalar_contract(inst, scalar_op)
    Vector(vector_op) => {
      let original = inst.opcode
      inst.opcode = vector_op.to_legacy_opcode()
      verify_opcode_contract(inst)
      inst.opcode = original
    }
    V128Const(bytes) => {
      require_arity(inst.args.length(), 0, "v128.const")
      require_result_types(inst, [V128], "v128.const")
      if bytes.length() != 16 {
        raise TypeMismatch(message="v128.const expects 16 bytes")
      }
    }
    V128Splat8 | V128Splat16 | V128Splat32 => {
      require_operand_types(inst, [I32], "v128 splat")
      require_result_types(inst, [V128], "v128 splat")
    }
    V128Splat64 => {
      require_operand_types(inst, [I64], "v128 splat")
      require_result_types(inst, [V128], "v128 splat")
    }
    V128SplatF32 => {
      require_operand_types(inst, [F32], "v128 splat")
      require_result_types(inst, [V128], "v128 splat")
    }
    V128SplatF64 => {
      require_operand_types(inst, [F64], "v128 splat")
      require_result_types(inst, [V128], "v128 splat")
    }
    V128ExtractLane8S(lane) | V128ExtractLane8U(lane) =>
      verify_v128_extract(inst, I32, lane, 16, "v128 extract lane")
    V128ExtractLane16S(lane) | V128ExtractLane16U(lane) =>
      verify_v128_extract(inst, I32, lane, 8, "v128 extract lane")
    V128ExtractLane32(lane) =>
      verify_v128_extract(inst, I32, lane, 4, "v128 extract lane")
    V128ExtractLane64(lane) =>
      verify_v128_extract(inst, I64, lane, 2, "v128 extract lane")
    V128ExtractLaneF32(lane) =>
      verify_v128_extract(inst, F32, lane, 4, "v128 extract lane")
    V128ExtractLaneF64(lane) =>
      verify_v128_extract(inst, F64, lane, 2, "v128 extract lane")
    V128ReplaceLane8(lane) =>
      verify_v128_replace(inst, I32, lane, 16, "v128 replace lane")
    V128ReplaceLane16(lane) =>
      verify_v128_replace(inst, I32, lane, 8, "v128 replace lane")
    V128ReplaceLane32(lane) =>
      verify_v128_replace(inst, I32, lane, 4, "v128 replace lane")
    V128ReplaceLane64(lane) =>
      verify_v128_replace(inst, I64, lane, 2, "v128 replace lane")
    V128ReplaceLaneF32(lane) =>
      verify_v128_replace(inst, F32, lane, 4, "v128 replace lane")
    V128ReplaceLaneF64(lane) =>
      verify_v128_replace(inst, F64, lane, 2, "v128 replace lane")
    V128Shuffle(lanes) => {
      verify_v128_binary(inst, "v128 shuffle")
      if lanes.length() != 16 {
        raise ArityMismatch(message="v128 shuffle expects 16 lane indices")
      }
      for lane in lanes {
        require_lane(lane, 32, "v128 shuffle")
      }
    }
    V128AnyTrue
    | V128AllTrue8
    | V128AllTrue16
    | V128AllTrue32
    | V128AllTrue64
    | V128Bitmask8
    | V128Bitmask16
    | V128Bitmask32
    | V128Bitmask64 => {
      require_operand_types(inst, [V128], "v128 predicate")
      require_result_types(inst, [I32], "v128 predicate")
    }
    V128Not
    | V128Abs8
    | V128Abs16
    | V128Abs32
    | V128Abs64
    | V128Neg8
    | V128Neg16
    | V128Neg32
    | V128Neg64
    | V128Popcnt8
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
    | V128ExtAddPairwise8to16S
    | V128ExtAddPairwise8to16U
    | V128ExtAddPairwise16to32S
    | V128ExtAddPairwise16to32U
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
    | V128RelaxedTruncF32toI32S
    | V128RelaxedTruncF32toI32U
    | V128RelaxedTruncF64toI32SZero
    | V128RelaxedTruncF64toI32UZero => verify_v128_unary(inst, "v128 unary")
    V128Swizzle
    | V128And
    | V128AndNot
    | V128Or
    | V128Xor
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
    | V128RelaxedSwizzle
    | V128RelaxedMinF32
    | V128RelaxedMaxF32
    | V128RelaxedMinF64
    | V128RelaxedMaxF64
    | V128RelaxedQ15MulrS
    | V128RelaxedDot8to16S => verify_v128_binary(inst, "v128 binary")
    V128Bitselect
    | V128RelaxedMaddF32
    | V128RelaxedNmaddF32
    | V128RelaxedMaddF64
    | V128RelaxedNmaddF64
    | V128RelaxedLaneselect8
    | V128RelaxedLaneselect16
    | V128RelaxedLaneselect32
    | V128RelaxedLaneselect64
    | V128RelaxedDot8to32AddS => verify_v128_ternary(inst, "v128 ternary")
    V128Shl8
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
    | V128Shr64U => {
      require_operand_types(inst, [V128, I32], "v128 shift")
      require_result_types(inst, [V128], "v128 shift")
    }
    V128Load8x8S(_, _, _)
    | V128Load8x8U(_, _, _)
    | V128Load16x4S(_, _, _)
    | V128Load16x4U(_, _, _)
    | V128Load32x2S(_, _, _)
    | V128Load32x2U(_, _, _)
    | V128Load8Splat(_, _, _)
    | V128Load16Splat(_, _, _)
    | V128Load32Splat(_, _, _)
    | V128Load64Splat(_, _, _)
    | V128Load32Zero(_, _, _)
    | V128Load64Zero(_, _, _) => {
      require_arity(inst.args.length(), 1, "v128 load")
      require_pointer_value(inst.args[0].ty, "v128 load")
      require_result_types(inst, [V128], "v128 load")
    }
    V128Load8Lane(_, _, _, lane) => verify_v128_load_lane(inst, lane, 16)
    V128Load16Lane(_, _, _, lane) => verify_v128_load_lane(inst, lane, 8)
    V128Load32Lane(_, _, _, lane) => verify_v128_load_lane(inst, lane, 4)
    V128Load64Lane(_, _, _, lane) => verify_v128_load_lane(inst, lane, 2)
    V128Store8Lane(_, _, _, lane) => verify_v128_store_lane(inst, lane, 16)
    V128Store16Lane(_, _, _, lane) => verify_v128_store_lane(inst, lane, 8)
    V128Store32Lane(_, _, _, lane) => verify_v128_store_lane(inst, lane, 4)
    V128Store64Lane(_, _, _, lane) => verify_v128_store_lane(inst, lane, 2)
  }
}
