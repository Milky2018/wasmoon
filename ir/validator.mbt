// IR Validator
// Validates that IR is well-formed and type-correct

///|
/// Result of IR validation
pub struct ValidationResult {
  mut valid : Bool
  errors : Array[String]
}

///|
pub fn ValidationResult::new() -> ValidationResult {
  { valid: true, errors: [] }
}

///|
fn ValidationResult::add_error(self : ValidationResult, error : String) -> Unit {
  self.valid = false
  self.errors.push(error)
}

///|
/// Validate a function's IR
pub fn validate_function(func : Function) -> ValidationResult {
  let result = ValidationResult::new()
  // Track all defined values
  let defined_values : @hashmap.HashMap[Int, Type] = @hashmap.new()
  // Add function parameters as defined
  for param in func.params {
    let (v, ty) = param
    defined_values.set(v.id, ty)
  }
  // Validate each block
  for block in func.blocks {
    // Add block parameters as defined
    for param in block.params {
      let (v, ty) = param
      defined_values.set(v.id, ty)
    }
    // Validate instructions
    for inst in block.instructions {
      validate_instruction(inst, defined_values, result)
      // Add result to defined values
      if inst.first_result() is Some(v) {
        defined_values.set(v.id, v.ty)
      }
    }
    // Validate terminator
    match block.terminator {
      Some(term) => validate_terminator(term, defined_values, func, result)
      None => result.add_error("Block \{block.id} has no terminator")
    }
  }
  // Check that entry block exists
  if func.blocks.length() == 0 {
    result.add_error("Function has no blocks")
  }
  result
}

///|
/// Validate an instruction
fn validate_instruction(
  inst : Inst,
  defined : @hashmap.HashMap[Int, Type],
  result : ValidationResult,
) -> Unit {
  // Check that all operands are defined
  for op in inst.operands {
    if !defined.contains(op.id) {
      result.add_error("Operand v\{op.id} is not defined")
    }
  }
  // Type-check based on opcode
  match inst.opcode {
    // Binary integer operations
    Iadd
    | Isub
    | Imul
    | Umulh
    | Smulh
    | Sdiv
    | Udiv
    | Srem
    | Urem
    | Band
    | Bor
    | Bxor
    | Ishl
    | Sshr
    | Ushr
    | Rotl
    | Rotr =>
      if inst.operands.length() != 2 {
        result.add_error(
          "Binary operation expects 2 operands, got \{inst.operands.length()}",
        )
      } else {
        let a = inst.operands[0]
        let b = inst.operands[1]
        // Operands should have matching integer types
        if !is_integer_type(a.ty) {
          result.add_error(
            "Binary integer op expects integer operand, got \{a.ty}",
          )
        }
        if !types_match(a.ty, b.ty) {
          result.add_error(
            "Binary op operands have mismatched types: \{a.ty} vs \{b.ty}",
          )
        }

        // mulhi ops are only defined for i64
        if inst.opcode is Umulh || inst.opcode is Smulh {
          if !types_match(a.ty, Type::I64) {
            result.add_error("mulhi expects i64 operands, got \{a.ty}")
          }
        }
      }

    // Bitwise not (unary)
    Bnot =>
      if inst.operands.length() != 1 {
        result.add_error(
          "Bnot expects 1 operand, got \{inst.operands.length()}",
        )
      }

    // Bit counting operations (unary)
    Clz | Ctz | Popcnt =>
      if inst.operands.length() != 1 {
        result.add_error(
          "Bit counting op expects 1 operand, got \{inst.operands.length()}",
        )
      }

    // Integer comparisons
    Icmp(_) => {
      if inst.operands.length() != 2 {
        result.add_error(
          "Icmp expects 2 operands, got \{inst.operands.length()}",
        )
      }
      // Result should be i32
      match inst.first_result() {
        Some(r) =>
          if !types_match(r.ty, Type::I32) {
            result.add_error("Icmp result should be i32, got \{r.ty}")
          }
        None => ()
      }
    }

    // Binary float operations
    Fadd | Fsub | Fmul | Fdiv | Fmin | Fmax =>
      if inst.operands.length() != 2 {
        result.add_error(
          "Binary float operation expects 2 operands, got \{inst.operands.length()}",
        )
      } else {
        let a = inst.operands[0]
        let b = inst.operands[1]
        if !is_float_type(a.ty) {
          result.add_error("Binary float op expects float operand, got \{a.ty}")
        }
        if !types_match(a.ty, b.ty) {
          result.add_error(
            "Binary op operands have mismatched types: \{a.ty} vs \{b.ty}",
          )
        }
      }

    // Float comparisons
    Fcmp(_) => {
      if inst.operands.length() != 2 {
        result.add_error(
          "Fcmp expects 2 operands, got \{inst.operands.length()}",
        )
      }
      // Result should be i32
      match inst.first_result() {
        Some(r) =>
          if !types_match(r.ty, Type::I32) {
            result.add_error("Fcmp result should be i32, got \{r.ty}")
          }
        None => ()
      }
    }

    // Unary float operations
    Fneg | Fabs | Fsqrt | Fceil | Ffloor | Ftrunc | Fnearest =>
      if inst.operands.length() != 1 {
        result.add_error(
          "Unary float op expects 1 operand, got \{inst.operands.length()}",
        )
      }

    // Constants don't have operands
    Iconst(_) | Fconst(_) =>
      if inst.operands.length() != 0 {
        result.add_error(
          "Constant expects 0 operands, got \{inst.operands.length()}",
        )
      }

    // Select needs 3 operands (cond, true_val, false_val)
    Select =>
      if inst.operands.length() != 3 {
        result.add_error(
          "Select expects 3 operands, got \{inst.operands.length()}",
        )
      }

    // Note: Load/Store opcodes removed - now use LoadPtr/StorePtr

    // Conversions need 1 operand
    Ireduce
    | Sextend
    | Uextend
    | Sextend8
    | Sextend16
    | Sextend32
    | Fpromote
    | Fdemote
    | FcvtToSint
    | FcvtToUint
    | FcvtToSintSat
    | FcvtToUintSat
    | SintToFcvt
    | UintToFcvt
    | Bitcast =>
      if inst.operands.length() != 1 {
        result.add_error(
          "Conversion expects 1 operand, got \{inst.operands.length()}",
        )
      }

    // Copy needs 1 operand
    Copy =>
      if inst.operands.length() != 1 {
        result.add_error(
          "Copy expects 1 operand, got \{inst.operands.length()}",
        )
      }

    // Memory management (with memidx for multi-memory support)
    LoadMemBase(_) =>
      if inst.operands.length() != 1 {
        result.add_error(
          "LoadMemBase expects 1 operand (vmctx), got \{inst.operands.length()}",
        )
      }
    MemoryGrow(_, _) =>
      if inst.operands.length() != 1 {
        result.add_error(
          "MemoryGrow expects 1 operand (delta), got \{inst.operands.length()}",
        )
      }
    MemorySize(_) =>
      if inst.operands.length() != 0 {
        result.add_error(
          "MemorySize expects 0 operands, got \{inst.operands.length()}",
        )
      }
    MemoryFill(_) =>
      if inst.operands.length() != 3 {
        result.add_error(
          "MemoryFill expects 3 operands (dst, val, size), got \{inst.operands.length()}",
        )
      }
    MemoryCopy(_, _) =>
      if inst.operands.length() != 3 {
        result.add_error(
          "MemoryCopy expects 3 operands (dst, src, size), got \{inst.operands.length()}",
        )
      }
    MemoryInit(_, _) =>
      if inst.operands.length() != 3 {
        result.add_error(
          "MemoryInit expects 3 operands (dst, src, size), got \{inst.operands.length()}",
        )
      }
    DataDrop(_) =>
      if inst.operands.length() != 0 {
        result.add_error(
          "DataDrop expects 0 operands, got \{inst.operands.length()}",
        )
      }

    // Table operations
    // NOTE: TableGet, TableSet, TableSize are desugared via FuncEnvironment at IR level
    TableGrow(_) =>
      if inst.operands.length() != 2 {
        result.add_error(
          "TableGrow expects 2 operands (delta, init_value), got \{inst.operands.length()}",
        )
      }
    TableFill(_) =>
      if inst.operands.length() != 3 {
        result.add_error(
          "TableFill expects 3 operands (dst, val, size), got \{inst.operands.length()}",
        )
      }
    TableCopy(_, _) =>
      if inst.operands.length() != 3 {
        result.add_error(
          "TableCopy expects 3 operands (dst, src, size), got \{inst.operands.length()}",
        )
      }
    TableInit(_, _) =>
      if inst.operands.length() != 3 {
        result.add_error(
          "TableInit expects 3 operands (dst, src, size), got \{inst.operands.length()}",
        )
      }
    ElemDrop(_) =>
      if inst.operands.length() != 0 {
        result.add_error(
          "ElemDrop expects 0 operands, got \{inst.operands.length()}",
        )
      }

    // NOTE: GlobalGet, GlobalSet are desugared via FuncEnvironment at IR level

    // Calls can have any number of operands
    Call(_)
    | CallIndirect(_)
    | CallRef(_)
    | ReturnCall(_)
    | ReturnCallIndirect(_, _)
    | ReturnCallRef(_)
    | CallPtr(_, _) => ()

    // GetFuncRef has no operands
    GetFuncRef(_) => ()

    // Raw pointer operations (for trampolines)
    LoadPtr(_) =>
      if inst.operands.length() < 1 {
        result.add_error(
          "LoadPtr expects at least 1 operand (base), got \{inst.operands.length()}",
        )
      }
    StorePtr(_) =>
      if inst.operands.length() < 2 {
        result.add_error(
          "StorePtr expects at least 2 operands (base, value), got \{inst.operands.length()}",
        )
      }
    LoadPtrNarrow(_, _, _) =>
      if inst.operands.length() < 1 {
        result.add_error(
          "LoadPtrNarrow expects at least 1 operand (base), got \{inst.operands.length()}",
        )
      }
    StorePtrNarrow(_) =>
      if inst.operands.length() < 2 {
        result.add_error(
          "StorePtrNarrow expects at least 2 operands (base, value), got \{inst.operands.length()}",
        )
      }

    // GC operations - struct
    StructNew(_) => () // Can have any number of operands (field values)
    StructNewDefault(_) =>
      if inst.operands.length() != 0 {
        result.add_error(
          "StructNewDefault expects 0 operands, got \{inst.operands.length()}",
        )
      }
    StructGet(_, _) | StructGetS(_, _, _) | StructGetU(_, _, _) =>
      if inst.operands.length() != 1 {
        result.add_error(
          "StructGet expects 1 operand (structref), got \{inst.operands.length()}",
        )
      }
    StructSet(_, _) =>
      if inst.operands.length() != 2 {
        result.add_error(
          "StructSet expects 2 operands (structref, value), got \{inst.operands.length()}",
        )
      }

    // GC operations - array
    ArrayNew(_) =>
      if inst.operands.length() != 2 {
        result.add_error(
          "ArrayNew expects 2 operands (init_value, length), got \{inst.operands.length()}",
        )
      }
    ArrayNewDefault(_) =>
      if inst.operands.length() != 1 {
        result.add_error(
          "ArrayNewDefault expects 1 operand (length), got \{inst.operands.length()}",
        )
      }
    ArrayNewFixed(_, _) => () // Can have any number of operands (element values)
    ArrayGet(_) | ArrayGetS(_, _) | ArrayGetU(_, _) =>
      if inst.operands.length() != 2 {
        result.add_error(
          "ArrayGet expects 2 operands (arrayref, index), got \{inst.operands.length()}",
        )
      }
    ArraySet(_) =>
      if inst.operands.length() != 3 {
        result.add_error(
          "ArraySet expects 3 operands (arrayref, index, value), got \{inst.operands.length()}",
        )
      }
    ArrayLen =>
      if inst.operands.length() != 1 {
        result.add_error(
          "ArrayLen expects 1 operand (arrayref), got \{inst.operands.length()}",
        )
      }
    ArrayFill(_) =>
      if inst.operands.length() != 4 {
        result.add_error(
          "ArrayFill expects 4 operands (arrayref, offset, value, count), got \{inst.operands.length()}",
        )
      }
    ArrayCopy(_, _) =>
      if inst.operands.length() != 5 {
        result.add_error(
          "ArrayCopy expects 5 operands (dst, dst_offset, src, src_offset, count), got \{inst.operands.length()}",
        )
      }
    ArrayNewData(_, _) =>
      if inst.operands.length() != 2 {
        result.add_error(
          "ArrayNewData expects 2 operands (data_offset, length), got \{inst.operands.length()}",
        )
      }
    ArrayNewElem(_, _) =>
      if inst.operands.length() != 2 {
        result.add_error(
          "ArrayNewElem expects 2 operands (elem_offset, length), got \{inst.operands.length()}",
        )
      }
    ArrayInitData(_, _) =>
      if inst.operands.length() != 4 {
        result.add_error(
          "ArrayInitData expects 4 operands (arrayref, arr_offset, data_offset, length), got \{inst.operands.length()}",
        )
      }
    ArrayInitElem(_, _) =>
      if inst.operands.length() != 4 {
        result.add_error(
          "ArrayInitElem expects 4 operands (arrayref, arr_offset, elem_offset, length), got \{inst.operands.length()}",
        )
      }

    // GC operations - i31
    I31New =>
      if inst.operands.length() != 1 {
        result.add_error(
          "I31New expects 1 operand (i32 value), got \{inst.operands.length()}",
        )
      }
    I31GetS | I31GetU =>
      if inst.operands.length() != 1 {
        result.add_error(
          "I31Get expects 1 operand (i31ref), got \{inst.operands.length()}",
        )
      }

    // GC operations - type checking/casting
    RefTest(_, _) | RefCast(_, _) =>
      if inst.operands.length() != 1 {
        result.add_error(
          "RefTest/RefCast expects 1 operand (ref), got \{inst.operands.length()}",
        )
      }

    // GC operations - type conversions
    AnyConvertExtern | ExternConvertAny =>
      if inst.operands.length() != 1 {
        result.add_error(
          "Type conversion expects 1 operand, got \{inst.operands.length()}",
        )
      }

    // GC operations - reference equality
    RefEq =>
      if inst.operands.length() != 2 {
        result.add_error(
          "RefEq expects 2 operands (refs), got \{inst.operands.length()}",
        )
      }

    // Exception handling operations
    Throw(_tag_idx) => ()
    ThrowRef =>
      if inst.operands.length() != 1 {
        result.add_error(
          "ThrowRef expects 1 operand (exnref), got \{inst.operands.length()}",
        )
      }
    TryTableBegin(_handler_id) =>
      if inst.first_result() is None {
        result.add_error(
          "TryTableBegin must have a result (setjmp return value)",
        )
      }
    TryTableEnd(_handler_id) => ()
    GetExceptionTag =>
      if inst.first_result() is None {
        result.add_error("GetExceptionTag must have a result")
      }
    GetExceptionValue(_idx) =>
      if inst.first_result() is None {
        result.add_error("GetExceptionValue must have a result")
      }
    GetExceptionValueCount =>
      if inst.first_result() is None {
        result.add_error("GetExceptionValueCount must have a result")
      }
    Delegate(_depth) => ()
    SpillLocalsForThrow(_count) => () // Void instruction, no result
    GetSpilledLocal(_idx) =>
      if inst.first_result() is None {
        result.add_error("GetSpilledLocal must have a result")
      }
    // SIMD operations - basic validation (TODO: add detailed type checking)
    V128Const(_)
    | V128Splat8
    | V128Splat16
    | V128Splat32
    | V128Splat64
    | V128SplatF32
    | V128SplatF64
    | V128ExtractLane8S(_)
    | V128ExtractLane8U(_)
    | V128ExtractLane16S(_)
    | V128ExtractLane16U(_)
    | V128ExtractLane32(_)
    | V128ExtractLane64(_)
    | V128ExtractLaneF32(_)
    | V128ExtractLaneF64(_)
    | V128ReplaceLane8(_)
    | V128ReplaceLane16(_)
    | V128ReplaceLane32(_)
    | V128ReplaceLane64(_)
    | V128ReplaceLaneF32(_)
    | V128ReplaceLaneF64(_)
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
    | V128Load8x8S(_, _, _)
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
    | V128Load64Zero(_, _, _)
    | V128Load8Lane(_, _, _, _)
    | V128Load16Lane(_, _, _, _)
    | V128Load32Lane(_, _, _, _)
    | V128Load64Lane(_, _, _, _)
    | V128Store8Lane(_, _, _, _)
    | V128Store16Lane(_, _, _, _)
    | V128Store32Lane(_, _, _, _)
    | V128Store64Lane(_, _, _, _)
    // Relaxed SIMD instructions
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
    | V128RelaxedDot8to32AddS => ()
  }
}

///|
/// Validate a terminator
fn validate_terminator(
  term : Terminator,
  defined : @hashmap.HashMap[Int, Type],
  func : Function,
  result : ValidationResult,
) -> Unit {
  match term {
    Jump(target, args) => {
      // Check target block exists
      if target >= func.blocks.length() {
        result.add_error("Jump target block\{target} does not exist")
      } else {
        let target_block = func.blocks[target]
        // Check argument count matches
        if args.length() != target_block.params.length() {
          result.add_error(
            "Jump to block\{target} expects \{target_block.params.length()} args, got \{args.length()}",
          )
        }
      }
      // Check all args are defined
      for arg in args {
        if !defined.contains(arg.id) {
          result.add_error("Jump argument v\{arg.id} is not defined")
        }
      }
    }
    Brz(cond, then_target, else_target)
    | Brnz(cond, then_target, else_target) => {
      // Check condition is defined
      if !defined.contains(cond.id) {
        result.add_error("Branch condition v\{cond.id} is not defined")
      }
      // Check targets exist
      if then_target >= func.blocks.length() {
        result.add_error(
          "Branch then target block\{then_target} does not exist",
        )
      }
      if else_target >= func.blocks.length() {
        result.add_error(
          "Branch else target block\{else_target} does not exist",
        )
      }
    }
    BrTable(index, targets, default_target) => {
      // Check index is defined
      if !defined.contains(index.id) {
        result.add_error("BrTable index v\{index.id} is not defined")
      }
      // Check all targets exist
      for t in targets {
        if t >= func.blocks.length() {
          result.add_error("BrTable target block\{t} does not exist")
        }
      }
      if default_target >= func.blocks.length() {
        result.add_error(
          "BrTable default target block\{default_target} does not exist",
        )
      }
    }
    Return(values) => {
      // Check return value count matches function signature
      if values.length() != func.results.length() {
        result.add_error(
          "Return expects \{func.results.length()} values, got \{values.length()}",
        )
      }
      // Check all values are defined
      for v in values {
        if !defined.contains(v.id) {
          result.add_error("Return value v\{v.id} is not defined")
        }
      }
    }
    Trap(_) => () // Always valid
  }
}

///|
/// Check if a type is an integer type
fn is_integer_type(ty : Type) -> Bool {
  match ty {
    I32 | I64 => true
    _ => false
  }
}

///|
/// Check if a type is a float type
fn is_float_type(ty : Type) -> Bool {
  match ty {
    F32 | F64 => true
    _ => false
  }
}

///|
/// Check if two types match
fn types_match(a : Type, b : Type) -> Bool {
  match (a, b) {
    (I32, I32)
    | (I64, I64)
    | (F32, F32)
    | (F64, F64)
    | (FuncRef, FuncRef)
    | (ExternRef, ExternRef) => true
    _ => false
  }
}
