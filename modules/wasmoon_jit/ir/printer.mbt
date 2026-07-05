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
    FuncRef => "funcref"
    ExternRef => "externref"
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
/// Print an opcode with its operands
/// result_ty is needed for Fconst to correctly decode F32 bit-packed constants
fn format_opcode(
  opcode : Opcode,
  operands : Array[Value],
  result_ty : Type?,
) -> String {
  let ops = operands.map(format_value).join(", ")
  match opcode {
    // Constants
    Iconst(n) => "iconst \{n}"
    Fconst(n) =>
      // For F32, the bits are packed in the lower 32 bits of the Double
      if result_ty is Some(F32) {
        let f32_bits = n.reinterpret_as_int64().to_int()
        let f32_val = Float::reinterpret_from_int(f32_bits)
        "fconst \{f32_val}"
      } else {
        "fconst \{n}"
      }

    // Integer arithmetic
    Iadd => "iadd \{ops}"
    Isub => "isub \{ops}"
    Imul => "imul \{ops}"
    Umulh => "umulh \{ops}"
    Smulh => "smulh \{ops}"
    Sdiv => "sdiv \{ops}"
    Udiv => "udiv \{ops}"
    Srem => "srem \{ops}"
    Urem => "urem \{ops}"

    // Bitwise operations
    Band => "band \{ops}"
    Bor => "bor \{ops}"
    Bxor => "bxor \{ops}"
    Bnot => "bnot \{ops}"
    Ishl => "ishl \{ops}"
    Sshr => "sshr \{ops}"
    Ushr => "ushr \{ops}"
    Rotl => "rotl \{ops}"
    Rotr => "rotr \{ops}"

    // Bit counting
    Clz => "clz \{ops}"
    Ctz => "ctz \{ops}"
    Popcnt => "popcnt \{ops}"

    // Comparisons
    Icmp(cc) => "icmp.\{format_intcc(cc)} \{ops}"

    // Floating point arithmetic
    Fadd => "fadd \{ops}"
    Fsub => "fsub \{ops}"
    Fmul => "fmul \{ops}"
    Fdiv => "fdiv \{ops}"
    Fmin => "fmin \{ops}"
    Fmax => "fmax \{ops}"

    // Floating point comparisons
    Fcmp(cc) => "fcmp.\{format_floatcc(cc)} \{ops}"

    // Floating point unary
    Fneg => "fneg \{ops}"
    Fabs => "fabs \{ops}"
    Fsqrt => "fsqrt \{ops}"
    Fceil => "fceil \{ops}"
    Ffloor => "ffloor \{ops}"
    Ftrunc => "ftrunc \{ops}"
    Fnearest => "fnearest \{ops}"

    // Conversions
    Ireduce => "ireduce \{ops}"
    Sextend => "sextend \{ops}"
    Uextend => "uextend \{ops}"
    Fpromote => "fpromote \{ops}"
    Fdemote => "fdemote \{ops}"
    FcvtToSint => "fcvt_to_sint \{ops}"
    FcvtToUint => "fcvt_to_uint \{ops}"
    FcvtToSintSat => "fcvt_to_sint_sat \{ops}"
    FcvtToUintSat => "fcvt_to_uint_sat \{ops}"
    SintToFcvt => "sint_to_fcvt \{ops}"
    UintToFcvt => "uint_to_fcvt \{ops}"
    Bitcast => "bitcast \{ops}"

    // In-place sign extension
    Sextend8 => "sextend8 \{ops}"
    Sextend16 => "sextend16 \{ops}"
    Sextend32 => "sextend32 \{ops}"

    // Memory management (with memidx for multi-memory support)
    // Note: Load/Store opcodes removed - now use LoadPtr/StorePtr
    LoadMemBase(memidx) => "load_mem_base mem=\{memidx} \{ops}"
    MemoryGrow(memidx, max_pages) =>
      match max_pages {
        Some(max) => "memory_grow mem=\{memidx} \{ops} max=\{max}"
        None => "memory_grow mem=\{memidx} \{ops}"
      }
    MemorySize(memidx) => "memory_size mem=\{memidx}"
    MemoryFill(memidx) => "memory_fill mem=\{memidx} \{ops}"
    MemoryCopy(dst_memidx, src_memidx) =>
      "memory_copy dst=\{dst_memidx} src=\{src_memidx} \{ops}"
    MemoryInit(memidx, data_idx) =>
      "memory_init mem=\{memidx} data=\{data_idx} \{ops}"
    DataDrop(data_idx) => "data_drop data=\{data_idx}"

    // Misc
    Select => "select \{ops}"
    Copy => "copy \{ops}"

    // Table operations
    // NOTE: TableGet, TableSet, TableSize are desugared via FuncEnvironment
    TableGrow(idx) => "table_grow \{idx} \{ops}"
    TableFill(idx) => "table_fill \{idx} \{ops}"
    TableCopy(dst_idx, src_idx) =>
      "table_copy dst=\{dst_idx} src=\{src_idx} \{ops}"
    TableInit(table_idx, elem_idx) =>
      "table_init table=\{table_idx} elem=\{elem_idx} \{ops}"
    ElemDrop(elem_idx) => "elem_drop elem=\{elem_idx}"

    // NOTE: GlobalGet, GlobalSet are desugared via FuncEnvironment

    // Function calls
    Call(idx) => "call \{idx}(\{ops})"
    CallIndirect(type_idx, table_idx) =>
      "call_indirect type=\{type_idx} table=\{table_idx}(\{ops})"
    CallRef(type_idx) => "call_ref type=\{type_idx}(\{ops})"
    ReturnCall(idx) => "return_call \{idx}(\{ops})"
    ReturnCallIndirect(type_idx, table_idx) =>
      "return_call_indirect type=\{type_idx} table=\{table_idx}(\{ops})"
    ReturnCallRef(type_idx) => "return_call_ref type=\{type_idx}(\{ops})"
    GetFuncRef(func_idx) => "get_func_ref \{func_idx}"

    // Raw pointer operations (for trampolines)
    LoadPtr(ty) => "load_ptr.\{ty} \{ops}"
    StorePtr(ty) => "store_ptr.\{ty} \{ops}"
    LoadPtrNarrow(result_ty, bits, signed) => {
      let sign_str = if signed { "s" } else { "u" }
      "load_ptr\{bits}_\{sign_str}.\{result_ty} \{ops}"
    }
    StorePtrNarrow(bits) => "store_ptr\{bits} \{ops}"
    CallPtr(num_args, num_results) =>
      "call_ptr(\{num_args}) -> \{num_results} (\{ops})"

    // GC operations - struct
    StructNew(type_idx) => "struct.new \{type_idx}(\{ops})"
    StructNewDefault(type_idx) => "struct.new_default \{type_idx}"
    StructGet(type_idx, field_idx) =>
      "struct.get \{type_idx} \{field_idx} \{ops}"
    StructGetS(type_idx, field_idx, byte_width) =>
      "struct.get_s \{type_idx} \{field_idx} bw=\{byte_width} \{ops}"
    StructGetU(type_idx, field_idx, byte_width) =>
      "struct.get_u \{type_idx} \{field_idx} bw=\{byte_width} \{ops}"
    StructSet(type_idx, field_idx) =>
      "struct.set \{type_idx} \{field_idx} \{ops}"

    // GC operations - array
    ArrayNew(type_idx) => "array.new \{type_idx}(\{ops})"
    ArrayNewDefault(type_idx) => "array.new_default \{type_idx}(\{ops})"
    ArrayNewFixed(type_idx, len) => "array.new_fixed \{type_idx} \{len}(\{ops})"
    ArrayGet(type_idx) => "array.get \{type_idx} \{ops}"
    ArrayGetS(type_idx, byte_width) =>
      "array.get_s \{type_idx} bw=\{byte_width} \{ops}"
    ArrayGetU(type_idx, byte_width) =>
      "array.get_u \{type_idx} bw=\{byte_width} \{ops}"
    ArraySet(type_idx) => "array.set \{type_idx} \{ops}"
    ArrayLen => "array.len \{ops}"
    ArrayFill(type_idx) => "array.fill \{type_idx} \{ops}"
    ArrayCopy(dst_type_idx, src_type_idx) =>
      "array.copy \{dst_type_idx} \{src_type_idx} \{ops}"
    ArrayNewData(type_idx, data_idx) =>
      "array.new_data \{type_idx} \{data_idx} \{ops}"
    ArrayNewElem(type_idx, elem_idx) =>
      "array.new_elem \{type_idx} \{elem_idx} \{ops}"
    ArrayInitData(type_idx, data_idx) =>
      "array.init_data \{type_idx} \{data_idx} \{ops}"
    ArrayInitElem(type_idx, elem_idx) =>
      "array.init_elem \{type_idx} \{elem_idx} \{ops}"

    // GC operations - i31
    I31New => "ref.i31 \{ops}"
    I31GetS => "i31.get_s \{ops}"
    I31GetU => "i31.get_u \{ops}"

    // GC operations - type checking/casting
    RefTest(type_idx, nullable) =>
      if nullable {
        "ref.test_null \{type_idx} \{ops}"
      } else {
        "ref.test \{type_idx} \{ops}"
      }
    RefCast(type_idx, nullable) =>
      if nullable {
        "ref.cast_null \{type_idx} \{ops}"
      } else {
        "ref.cast \{type_idx} \{ops}"
      }

    // GC operations - type conversions
    AnyConvertExtern => "any.convert_extern \{ops}"
    ExternConvertAny => "extern.convert_any \{ops}"

    // GC operations - reference equality
    RefEq => "ref.eq \{ops}"

    // Exception handling
    Throw(tag_idx) => "throw \{tag_idx} \{ops}"
    ThrowRef => "throw_ref \{ops}"
    TryTableBegin(handler_id) => "try_table_begin \{handler_id}"
    TryTableEnd(handler_id) => "try_table_end \{handler_id}"
    GetExceptionTag => "get_exception_tag"
    GetExceptionValue(idx) => "get_exception_value \{idx}"
    GetExceptionValueCount => "get_exception_value_count"
    Delegate(depth) => "delegate \{depth}"
    SpillLocalsForThrow(count) => "spill_locals_for_throw \{count}"
    GetSpilledLocal(idx) => "get_spilled_local \{idx}"

    // SIMD operations
    V128Const(_) => "v128.const \{ops}"
    V128Splat8 => "i8x16.splat \{ops}"
    V128Splat16 => "i16x8.splat \{ops}"
    V128Splat32 => "i32x4.splat \{ops}"
    V128Splat64 => "i64x2.splat \{ops}"
    V128SplatF32 => "f32x4.splat \{ops}"
    V128SplatF64 => "f64x2.splat \{ops}"
    V128ExtractLane8S(lane) => "i8x16.extract_lane_s \{lane} \{ops}"
    V128ExtractLane8U(lane) => "i8x16.extract_lane_u \{lane} \{ops}"
    V128ExtractLane16S(lane) => "i16x8.extract_lane_s \{lane} \{ops}"
    V128ExtractLane16U(lane) => "i16x8.extract_lane_u \{lane} \{ops}"
    V128ExtractLane32(lane) => "i32x4.extract_lane \{lane} \{ops}"
    V128ExtractLane64(lane) => "i64x2.extract_lane \{lane} \{ops}"
    V128ExtractLaneF32(lane) => "f32x4.extract_lane \{lane} \{ops}"
    V128ExtractLaneF64(lane) => "f64x2.extract_lane \{lane} \{ops}"
    V128ReplaceLane8(lane) => "i8x16.replace_lane \{lane} \{ops}"
    V128ReplaceLane16(lane) => "i16x8.replace_lane \{lane} \{ops}"
    V128ReplaceLane32(lane) => "i32x4.replace_lane \{lane} \{ops}"
    V128ReplaceLane64(lane) => "i64x2.replace_lane \{lane} \{ops}"
    V128ReplaceLaneF32(lane) => "f32x4.replace_lane \{lane} \{ops}"
    V128ReplaceLaneF64(lane) => "f64x2.replace_lane \{lane} \{ops}"
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
    V128Load8x8S(memidx, align, offset) =>
      "v128.load8x8_s mem=\{memidx} align=\{align} offset=\{offset} \{ops}"
    V128Load8x8U(memidx, align, offset) =>
      "v128.load8x8_u mem=\{memidx} align=\{align} offset=\{offset} \{ops}"
    V128Load16x4S(memidx, align, offset) =>
      "v128.load16x4_s mem=\{memidx} align=\{align} offset=\{offset} \{ops}"
    V128Load16x4U(memidx, align, offset) =>
      "v128.load16x4_u mem=\{memidx} align=\{align} offset=\{offset} \{ops}"
    V128Load32x2S(memidx, align, offset) =>
      "v128.load32x2_s mem=\{memidx} align=\{align} offset=\{offset} \{ops}"
    V128Load32x2U(memidx, align, offset) =>
      "v128.load32x2_u mem=\{memidx} align=\{align} offset=\{offset} \{ops}"
    V128Load8Splat(memidx, align, offset) =>
      "v128.load8_splat mem=\{memidx} align=\{align} offset=\{offset} \{ops}"
    V128Load16Splat(memidx, align, offset) =>
      "v128.load16_splat mem=\{memidx} align=\{align} offset=\{offset} \{ops}"
    V128Load32Splat(memidx, align, offset) =>
      "v128.load32_splat mem=\{memidx} align=\{align} offset=\{offset} \{ops}"
    V128Load64Splat(memidx, align, offset) =>
      "v128.load64_splat mem=\{memidx} align=\{align} offset=\{offset} \{ops}"
    V128Load32Zero(memidx, align, offset) =>
      "v128.load32_zero mem=\{memidx} align=\{align} offset=\{offset} \{ops}"
    V128Load64Zero(memidx, align, offset) =>
      "v128.load64_zero mem=\{memidx} align=\{align} offset=\{offset} \{ops}"
    V128Load8Lane(memidx, align, offset, lane) =>
      "v128.load8_lane mem=\{memidx} align=\{align} offset=\{offset} lane=\{lane} \{ops}"
    V128Load16Lane(memidx, align, offset, lane) =>
      "v128.load16_lane mem=\{memidx} align=\{align} offset=\{offset} lane=\{lane} \{ops}"
    V128Load32Lane(memidx, align, offset, lane) =>
      "v128.load32_lane mem=\{memidx} align=\{align} offset=\{offset} lane=\{lane} \{ops}"
    V128Load64Lane(memidx, align, offset, lane) =>
      "v128.load64_lane mem=\{memidx} align=\{align} offset=\{offset} lane=\{lane} \{ops}"
    V128Store8Lane(memidx, align, offset, lane) =>
      "v128.store8_lane mem=\{memidx} align=\{align} offset=\{offset} lane=\{lane} \{ops}"
    V128Store16Lane(memidx, align, offset, lane) =>
      "v128.store16_lane mem=\{memidx} align=\{align} offset=\{offset} lane=\{lane} \{ops}"
    V128Store32Lane(memidx, align, offset, lane) =>
      "v128.store32_lane mem=\{memidx} align=\{align} offset=\{offset} lane=\{lane} \{ops}"
    V128Store64Lane(memidx, align, offset, lane) =>
      "v128.store64_lane mem=\{memidx} align=\{align} offset=\{offset} lane=\{lane} \{ops}"
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
  }
}

///|
/// Print an instruction
fn format_inst(inst : Inst) -> String {
  let result_ty = inst.first_result().map(fn(v) { v.ty })
  let opcode_str = format_opcode(inst.opcode, inst.operands, result_ty)
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
  }
}

///|
/// Print a basic block
fn format_block(block : Block) -> String {
  let sb = StringBuilder::new()
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
  let sb = StringBuilder::new()
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
/// Print using IRBuilder
pub fn IRBuilder::print(self : IRBuilder) -> String {
  self.func.print()
}
