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
    FloatConst32(_) => {
      require_arity(inst.args.length(), 0, "fconst32")
      require_result_types(inst, [F32], "fconst32")
    }
    FloatConst64(_) => {
      require_arity(inst.args.length(), 0, "fconst64")
      require_result_types(inst, [F64], "fconst64")
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
fn vector_int_unary_supported(
  opcode : VectorIntUnaryOp,
  lane : VectorIntLane,
) -> Bool {
  match (opcode, lane) {
    (Abs | Neg, _) => true
    (Popcnt, I8) => true
    (Extend(_, _), I16 | I32 | I64) => true
    (ExtAddPairwise(_), I16 | I32) => true
    _ => false
  }
}

///|
fn vector_int_binary_supported(
  opcode : VectorIntBinaryOp,
  lane : VectorIntLane,
) -> Bool {
  match (opcode, lane) {
    (Add | Sub, _) => true
    (Mul, I16 | I32 | I64) => true
    (AddSaturating(_) | SubSaturating(_), I8 | I16) => true
    (Min(_) | Max(_), I8 | I16 | I32) => true
    (AverageUnsigned, I8 | I16) => true
    (ExtMul(_, _), I16 | I32 | I64) => true
    (Dot16To32Signed, I32) => true
    (Q15MulrSaturating, I16) => true
    _ => false
  }
}

///|
fn vector_int_compare_supported(
  opcode : VectorIntCompareOp,
  lane : VectorIntLane,
) -> Bool {
  match (opcode, lane) {
    (Eq | Ne, _) => true
    (Lt(Signed) | Gt(Signed) | Le(Signed) | Ge(Signed), _) => true
    (Lt(Unsigned) | Gt(Unsigned) | Le(Unsigned) | Ge(Unsigned), I8 | I16 | I32) =>
      true
    _ => false
  }
}

///|
fn verify_vector_memory_contract(
  inst : Inst,
  opcode : VectorMemoryOp,
) -> Unit raise VerifyError {
  match opcode {
    LoadExtend(I8 | I16 | I32, _) | LoadSplat(_) | LoadZero(I32 | I64) => {
      require_arity(inst.args.length(), 1, "v128 load")
      require_pointer_value(inst.args[0].ty, "v128 load")
      require_result_types(inst, [V128], "v128 load")
    }
    LoadExtend(I64, _) =>
      raise TypeMismatch(message="invalid vector extending-load semantics")
    LoadZero(I8 | I16) =>
      raise TypeMismatch(message="invalid vector zero-load semantics")
    LoadLane(I8, lane) => verify_v128_load_lane(inst, lane, 16)
    LoadLane(I16, lane) => verify_v128_load_lane(inst, lane, 8)
    LoadLane(I32, lane) => verify_v128_load_lane(inst, lane, 4)
    LoadLane(I64, lane) => verify_v128_load_lane(inst, lane, 2)
    StoreLane(I8, lane) => verify_v128_store_lane(inst, lane, 16)
    StoreLane(I16, lane) => verify_v128_store_lane(inst, lane, 8)
    StoreLane(I32, lane) => verify_v128_store_lane(inst, lane, 4)
    StoreLane(I64, lane) => verify_v128_store_lane(inst, lane, 2)
  }
}

///|
fn verify_vector_contract(
  inst : Inst,
  opcode : VectorOp,
) -> Unit raise VerifyError {
  match opcode {
    Const(bytes) => {
      require_arity(inst.args.length(), 0, "v128.const")
      require_result_types(inst, [V128], "v128.const")
      if bytes.length() != 16 {
        raise TypeMismatch(message="v128.const expects 16 bytes")
      }
    }
    Splat(I8 | I16 | I32) => {
      require_operand_types(inst, [I32], "v128 splat")
      require_result_types(inst, [V128], "v128 splat")
    }
    Splat(I64) => {
      require_operand_types(inst, [I64], "v128 splat")
      require_result_types(inst, [V128], "v128 splat")
    }
    Splat(F32) => {
      require_operand_types(inst, [F32], "v128 splat")
      require_result_types(inst, [V128], "v128 splat")
    }
    Splat(F64) => {
      require_operand_types(inst, [F64], "v128 splat")
      require_result_types(inst, [V128], "v128 splat")
    }
    ExtractLane(I8, Signed | Unsigned, lane) =>
      verify_v128_extract(inst, I32, lane, 16, "v128 extract lane")
    ExtractLane(I16, Signed | Unsigned, lane) =>
      verify_v128_extract(inst, I32, lane, 8, "v128 extract lane")
    ExtractLane(I32, None, lane) =>
      verify_v128_extract(inst, I32, lane, 4, "v128 extract lane")
    ExtractLane(I64, None, lane) =>
      verify_v128_extract(inst, I64, lane, 2, "v128 extract lane")
    ExtractLane(F32, None, lane) =>
      verify_v128_extract(inst, F32, lane, 4, "v128 extract lane")
    ExtractLane(F64, None, lane) =>
      verify_v128_extract(inst, F64, lane, 2, "v128 extract lane")
    ExtractLane(_, _, _) =>
      raise TypeMismatch(message="invalid vector extract-lane semantics")
    ReplaceLane(I8, lane) =>
      verify_v128_replace(inst, I32, lane, 16, "v128 replace lane")
    ReplaceLane(I16, lane) =>
      verify_v128_replace(inst, I32, lane, 8, "v128 replace lane")
    ReplaceLane(I32, lane) =>
      verify_v128_replace(inst, I32, lane, 4, "v128 replace lane")
    ReplaceLane(I64, lane) =>
      verify_v128_replace(inst, I64, lane, 2, "v128 replace lane")
    ReplaceLane(F32, lane) =>
      verify_v128_replace(inst, F32, lane, 4, "v128 replace lane")
    ReplaceLane(F64, lane) =>
      verify_v128_replace(inst, F64, lane, 2, "v128 replace lane")
    Shuffle(lanes) => {
      verify_v128_binary(inst, "v128 shuffle")
      if lanes.length() != 16 {
        raise ArityMismatch(message="v128 shuffle expects 16 lane indices")
      }
      for lane in lanes {
        require_lane(lane, 32, "v128 shuffle")
      }
    }
    Predicate(_) => {
      require_operand_types(inst, [V128], "v128 predicate")
      require_result_types(inst, [I32], "v128 predicate")
    }
    Bitwise(Not) => verify_v128_unary(inst, "v128 bitwise unary")
    Bitwise(And | AndNot | Or | Xor) | Swizzle =>
      verify_v128_binary(inst, "v128 binary")
    Bitwise(Bitselect) => verify_v128_ternary(inst, "v128 bitselect")
    IntUnary(op, lane) => {
      if !vector_int_unary_supported(op, lane) {
        raise TypeMismatch(message="unsupported integer vector unary operation")
      }
      verify_v128_unary(inst, "v128 integer unary")
    }
    IntBinary(op, lane) => {
      if !vector_int_binary_supported(op, lane) {
        raise TypeMismatch(
          message="unsupported integer vector binary operation",
        )
      }
      verify_v128_binary(inst, "v128 integer binary")
    }
    IntShift(_, _) => {
      require_operand_types(inst, [V128, I32], "v128 shift")
      require_result_types(inst, [V128], "v128 shift")
    }
    IntCompare(op, lane) => {
      if !vector_int_compare_supported(op, lane) {
        raise TypeMismatch(message="unsupported integer vector comparison")
      }
      verify_v128_binary(inst, "v128 integer comparison")
    }
    Narrow(I8 | I16, _) => verify_v128_binary(inst, "v128 narrow")
    Narrow(I32 | I64, _) =>
      raise TypeMismatch(message="unsupported vector narrowing operation")
    FloatUnary(_, _) | Convert(_) => verify_v128_unary(inst, "v128 unary")
    FloatBinary(_, _) | FloatCompare(_, _) =>
      verify_v128_binary(inst, "v128 binary")
    Relaxed(TruncF32ToI32(_) | TruncF64ToI32Zero(_)) =>
      verify_v128_unary(inst, "relaxed v128 unary")
    Relaxed(Swizzle | Min(_) | Max(_) | Q15MulrSigned | Dot8To16Signed) =>
      verify_v128_binary(inst, "relaxed v128 binary")
    Relaxed(Fma(_, _) | LaneSelect(_) | Dot8To32AddSigned) =>
      verify_v128_ternary(inst, "relaxed v128 ternary")
  }
}

///|
fn verify_opcode_contract(inst : Inst) -> Unit raise VerifyError {
  match inst.opcode {
    Call(call_op) =>
      match call_op {
        Direct(_, signature) =>
          verify_signature(inst, signature, 0, "direct call")
        Pointer(num_args, num_results) => {
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
    Memory(memory_op) =>
      match memory_op {
        Load(result_type) => {
          require_arity(inst.args.length(), 2, "memory load")
          require_pointer_value(inst.args[0].ty, "memory load")
          require_operand_type(inst, 1, I64, "memory load")
          require_result_types(inst, [result_type], "memory load")
        }
        Store(value_type) => {
          require_arity(inst.args.length(), 3, "memory store")
          require_pointer_value(inst.args[0].ty, "memory store")
          require_operand_type(inst, 1, value_type, "memory store")
          require_operand_type(inst, 2, I64, "memory store")
          require_no_results(inst, "memory store")
        }
        LoadNarrow(result_type, bits, _) => {
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
        StoreNarrow(bits) => {
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
        Vector(opcode) => verify_vector_memory_contract(inst, opcode)
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
    Vector(vector_op) => verify_vector_contract(inst, vector_op)
  }
}
