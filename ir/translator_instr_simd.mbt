// SIMD instruction translation (V128 / SIMD / relaxed SIMD)
// Split from translator_instr.mbt for maintainability

///|
/// Translate SIMD instructions
fn Translator::translate_instruction_simd(
  self : Translator,
  instr : @types.Instruction,
) -> Unit {
  match instr {
    // ============ SIMD Instructions ============

    // V128 constant
    V128Const(bytes) => {
      let v = self.builder.v128_const(bytes)
      self.push(v)
    }

    // Splat operations (scalar -> vector)
    I8x16Splat => {
      let val = self.pop()
      let result = self.builder.v128_splat8(val)
      self.push(result)
    }
    I16x8Splat => {
      let val = self.pop()
      let result = self.builder.v128_splat16(val)
      self.push(result)
    }
    I32x4Splat => {
      let val = self.pop()
      let result = self.builder.v128_splat32(val)
      self.push(result)
    }
    I64x2Splat => {
      let val = self.pop()
      let result = self.builder.v128_splat64(val)
      self.push(result)
    }
    F32x4Splat => {
      let val = self.pop()
      let result = self.builder.v128_splat_f32(val)
      self.push(result)
    }
    F64x2Splat => {
      let val = self.pop()
      let result = self.builder.v128_splat_f64(val)
      self.push(result)
    }

    // Extract lane operations (vector -> scalar)
    I8x16ExtractLaneS(lane) => {
      let vec = self.pop()
      let result = self.builder.v128_extract8s(vec, lane)
      self.push(result)
    }
    I8x16ExtractLaneU(lane) => {
      let vec = self.pop()
      let result = self.builder.v128_extract8u(vec, lane)
      self.push(result)
    }
    I16x8ExtractLaneS(lane) => {
      let vec = self.pop()
      let result = self.builder.v128_extract16s(vec, lane)
      self.push(result)
    }
    I16x8ExtractLaneU(lane) => {
      let vec = self.pop()
      let result = self.builder.v128_extract16u(vec, lane)
      self.push(result)
    }
    I32x4ExtractLane(lane) => {
      let vec = self.pop()
      let result = self.builder.v128_extract32(vec, lane)
      self.push(result)
    }
    I64x2ExtractLane(lane) => {
      let vec = self.pop()
      let result = self.builder.v128_extract64(vec, lane)
      self.push(result)
    }
    F32x4ExtractLane(lane) => {
      let vec = self.pop()
      let result = self.builder.v128_extract_f32(vec, lane)
      self.push(result)
    }
    F64x2ExtractLane(lane) => {
      let vec = self.pop()
      let result = self.builder.v128_extract_f64(vec, lane)
      self.push(result)
    }

    // Replace lane operations (vector, scalar -> vector)
    I8x16ReplaceLane(lane) => {
      let val = self.pop()
      let vec = self.pop()
      let result = self.builder.v128_replace8(vec, val, lane)
      self.push(result)
    }
    I16x8ReplaceLane(lane) => {
      let val = self.pop()
      let vec = self.pop()
      let result = self.builder.v128_replace16(vec, val, lane)
      self.push(result)
    }
    I32x4ReplaceLane(lane) => {
      let val = self.pop()
      let vec = self.pop()
      let result = self.builder.v128_replace32(vec, val, lane)
      self.push(result)
    }
    I64x2ReplaceLane(lane) => {
      let val = self.pop()
      let vec = self.pop()
      let result = self.builder.v128_replace64(vec, val, lane)
      self.push(result)
    }
    F32x4ReplaceLane(lane) => {
      let val = self.pop()
      let vec = self.pop()
      let result = self.builder.v128_replace_f32(vec, val, lane)
      self.push(result)
    }
    F64x2ReplaceLane(lane) => {
      let val = self.pop()
      let vec = self.pop()
      let result = self.builder.v128_replace_f64(vec, val, lane)
      self.push(result)
    }

    // Shuffle and swizzle
    I8x16Shuffle(lanes) => {
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.v128_shuffle(a, b, lanes)
      self.push(result)
    }
    I8x16Swizzle => {
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.v128_swizzle(a, b)
      self.push(result)
    }

    // Bitwise operations
    V128Not => {
      let a = self.pop()
      let result = self.builder.v128_not(a)
      self.push(result)
    }
    V128And => {
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.v128_and(a, b)
      self.push(result)
    }
    V128AndNot => {
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.v128_andnot(a, b)
      self.push(result)
    }
    V128Or => {
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.v128_or(a, b)
      self.push(result)
    }
    V128Xor => {
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.v128_xor(a, b)
      self.push(result)
    }
    V128Bitselect => {
      let c = self.pop() // mask
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.v128_bitselect(a, b, c)
      self.push(result)
    }
    V128AnyTrue => {
      let a = self.pop()
      let result = self.builder.v128_anytrue(a)
      self.push(result)
    }

    // i8x16 operations
    I8x16Eq => self.translate_simd_binary(Opcode::V128Eq8)
    I8x16Ne => self.translate_simd_binary(Opcode::V128Ne8)
    I8x16LtS => self.translate_simd_binary(Opcode::V128Lt8S)
    I8x16LtU => self.translate_simd_binary(Opcode::V128Lt8U)
    I8x16GtS => self.translate_simd_binary(Opcode::V128Gt8S)
    I8x16GtU => self.translate_simd_binary(Opcode::V128Gt8U)
    I8x16LeS => self.translate_simd_binary(Opcode::V128Le8S)
    I8x16LeU => self.translate_simd_binary(Opcode::V128Le8U)
    I8x16GeS => self.translate_simd_binary(Opcode::V128Ge8S)
    I8x16GeU => self.translate_simd_binary(Opcode::V128Ge8U)
    I8x16Abs => self.translate_simd_unary(Opcode::V128Abs8)
    I8x16Neg => self.translate_simd_unary(Opcode::V128Neg8)
    I8x16Popcnt => self.translate_simd_unary(Opcode::V128Popcnt8)
    I8x16AllTrue => self.translate_simd_to_i32(Opcode::V128AllTrue8)
    I8x16Bitmask => self.translate_simd_to_i32(Opcode::V128Bitmask8)
    I8x16NarrowI16x8S => self.translate_simd_binary(Opcode::V128Narrow16to8S)
    I8x16NarrowI16x8U => self.translate_simd_binary(Opcode::V128Narrow16to8U)
    I8x16Shl => self.translate_simd_shift(Opcode::V128Shl8)
    I8x16ShrS => self.translate_simd_shift(Opcode::V128Shr8S)
    I8x16ShrU => self.translate_simd_shift(Opcode::V128Shr8U)
    I8x16Add => self.translate_simd_binary(Opcode::V128Add8)
    I8x16AddSatS => self.translate_simd_binary(Opcode::V128AddSat8S)
    I8x16AddSatU => self.translate_simd_binary(Opcode::V128AddSat8U)
    I8x16Sub => self.translate_simd_binary(Opcode::V128Sub8)
    I8x16SubSatS => self.translate_simd_binary(Opcode::V128SubSat8S)
    I8x16SubSatU => self.translate_simd_binary(Opcode::V128SubSat8U)
    I8x16MinS => self.translate_simd_binary(Opcode::V128Min8S)
    I8x16MinU => self.translate_simd_binary(Opcode::V128Min8U)
    I8x16MaxS => self.translate_simd_binary(Opcode::V128Max8S)
    I8x16MaxU => self.translate_simd_binary(Opcode::V128Max8U)
    I8x16AvgrU => self.translate_simd_binary(Opcode::V128Avgr8U)

    // i16x8 operations
    I16x8ExtAddPairwiseI8x16S =>
      self.translate_simd_unary(Opcode::V128ExtAddPairwise8to16S)
    I16x8ExtAddPairwiseI8x16U =>
      self.translate_simd_unary(Opcode::V128ExtAddPairwise8to16U)
    I16x8Eq => self.translate_simd_binary(Opcode::V128Eq16)
    I16x8Ne => self.translate_simd_binary(Opcode::V128Ne16)
    I16x8LtS => self.translate_simd_binary(Opcode::V128Lt16S)
    I16x8LtU => self.translate_simd_binary(Opcode::V128Lt16U)
    I16x8GtS => self.translate_simd_binary(Opcode::V128Gt16S)
    I16x8GtU => self.translate_simd_binary(Opcode::V128Gt16U)
    I16x8LeS => self.translate_simd_binary(Opcode::V128Le16S)
    I16x8LeU => self.translate_simd_binary(Opcode::V128Le16U)
    I16x8GeS => self.translate_simd_binary(Opcode::V128Ge16S)
    I16x8GeU => self.translate_simd_binary(Opcode::V128Ge16U)
    I16x8Abs => self.translate_simd_unary(Opcode::V128Abs16)
    I16x8Neg => self.translate_simd_unary(Opcode::V128Neg16)
    I16x8Q15MulrSatS => self.translate_simd_binary(Opcode::V128Q15MulrSat16S)
    I16x8AllTrue => self.translate_simd_to_i32(Opcode::V128AllTrue16)
    I16x8Bitmask => self.translate_simd_to_i32(Opcode::V128Bitmask16)
    I16x8NarrowI32x4S => self.translate_simd_binary(Opcode::V128Narrow32to16S)
    I16x8NarrowI32x4U => self.translate_simd_binary(Opcode::V128Narrow32to16U)
    I16x8ExtendLowI8x16S =>
      self.translate_simd_unary(Opcode::V128ExtendLow8to16S)
    I16x8ExtendHighI8x16S =>
      self.translate_simd_unary(Opcode::V128ExtendHigh8to16S)
    I16x8ExtendLowI8x16U =>
      self.translate_simd_unary(Opcode::V128ExtendLow8to16U)
    I16x8ExtendHighI8x16U =>
      self.translate_simd_unary(Opcode::V128ExtendHigh8to16U)
    I16x8Shl => self.translate_simd_shift(Opcode::V128Shl16)
    I16x8ShrS => self.translate_simd_shift(Opcode::V128Shr16S)
    I16x8ShrU => self.translate_simd_shift(Opcode::V128Shr16U)
    I16x8Add => self.translate_simd_binary(Opcode::V128Add16)
    I16x8AddSatS => self.translate_simd_binary(Opcode::V128AddSat16S)
    I16x8AddSatU => self.translate_simd_binary(Opcode::V128AddSat16U)
    I16x8Sub => self.translate_simd_binary(Opcode::V128Sub16)
    I16x8SubSatS => self.translate_simd_binary(Opcode::V128SubSat16S)
    I16x8SubSatU => self.translate_simd_binary(Opcode::V128SubSat16U)
    I16x8Mul => self.translate_simd_binary(Opcode::V128Mul16)
    I16x8MinS => self.translate_simd_binary(Opcode::V128Min16S)
    I16x8MinU => self.translate_simd_binary(Opcode::V128Min16U)
    I16x8MaxS => self.translate_simd_binary(Opcode::V128Max16S)
    I16x8MaxU => self.translate_simd_binary(Opcode::V128Max16U)
    I16x8AvgrU => self.translate_simd_binary(Opcode::V128Avgr16U)
    I16x8ExtMulLowI8x16S =>
      self.translate_simd_binary(Opcode::V128ExtMulLow8to16S)
    I16x8ExtMulHighI8x16S =>
      self.translate_simd_binary(Opcode::V128ExtMulHigh8to16S)
    I16x8ExtMulLowI8x16U =>
      self.translate_simd_binary(Opcode::V128ExtMulLow8to16U)
    I16x8ExtMulHighI8x16U =>
      self.translate_simd_binary(Opcode::V128ExtMulHigh8to16U)

    // i32x4 operations
    I32x4ExtAddPairwiseI16x8S =>
      self.translate_simd_unary(Opcode::V128ExtAddPairwise16to32S)
    I32x4ExtAddPairwiseI16x8U =>
      self.translate_simd_unary(Opcode::V128ExtAddPairwise16to32U)
    I32x4Eq => self.translate_simd_binary(Opcode::V128Eq32)
    I32x4Ne => self.translate_simd_binary(Opcode::V128Ne32)
    I32x4LtS => self.translate_simd_binary(Opcode::V128Lt32S)
    I32x4LtU => self.translate_simd_binary(Opcode::V128Lt32U)
    I32x4GtS => self.translate_simd_binary(Opcode::V128Gt32S)
    I32x4GtU => self.translate_simd_binary(Opcode::V128Gt32U)
    I32x4LeS => self.translate_simd_binary(Opcode::V128Le32S)
    I32x4LeU => self.translate_simd_binary(Opcode::V128Le32U)
    I32x4GeS => self.translate_simd_binary(Opcode::V128Ge32S)
    I32x4GeU => self.translate_simd_binary(Opcode::V128Ge32U)
    I32x4Abs => self.translate_simd_unary(Opcode::V128Abs32)
    I32x4Neg => self.translate_simd_unary(Opcode::V128Neg32)
    I32x4AllTrue => self.translate_simd_to_i32(Opcode::V128AllTrue32)
    I32x4Bitmask => self.translate_simd_to_i32(Opcode::V128Bitmask32)
    I32x4ExtendLowI16x8S =>
      self.translate_simd_unary(Opcode::V128ExtendLow16to32S)
    I32x4ExtendHighI16x8S =>
      self.translate_simd_unary(Opcode::V128ExtendHigh16to32S)
    I32x4ExtendLowI16x8U =>
      self.translate_simd_unary(Opcode::V128ExtendLow16to32U)
    I32x4ExtendHighI16x8U =>
      self.translate_simd_unary(Opcode::V128ExtendHigh16to32U)
    I32x4Shl => self.translate_simd_shift(Opcode::V128Shl32)
    I32x4ShrS => self.translate_simd_shift(Opcode::V128Shr32S)
    I32x4ShrU => self.translate_simd_shift(Opcode::V128Shr32U)
    I32x4Add => self.translate_simd_binary(Opcode::V128Add32)
    I32x4Sub => self.translate_simd_binary(Opcode::V128Sub32)
    I32x4Mul => self.translate_simd_binary(Opcode::V128Mul32)
    I32x4MinS => self.translate_simd_binary(Opcode::V128Min32S)
    I32x4MinU => self.translate_simd_binary(Opcode::V128Min32U)
    I32x4MaxS => self.translate_simd_binary(Opcode::V128Max32S)
    I32x4MaxU => self.translate_simd_binary(Opcode::V128Max32U)
    I32x4DotI16x8S => self.translate_simd_binary(Opcode::V128Dot16to32S)
    I32x4ExtMulLowI16x8S =>
      self.translate_simd_binary(Opcode::V128ExtMulLow16to32S)
    I32x4ExtMulHighI16x8S =>
      self.translate_simd_binary(Opcode::V128ExtMulHigh16to32S)
    I32x4ExtMulLowI16x8U =>
      self.translate_simd_binary(Opcode::V128ExtMulLow16to32U)
    I32x4ExtMulHighI16x8U =>
      self.translate_simd_binary(Opcode::V128ExtMulHigh16to32U)

    // i64x2 operations
    I64x2Eq => self.translate_simd_binary(Opcode::V128Eq64)
    I64x2Ne => self.translate_simd_binary(Opcode::V128Ne64)
    I64x2LtS => self.translate_simd_binary(Opcode::V128Lt64S)
    I64x2GtS => self.translate_simd_binary(Opcode::V128Gt64S)
    I64x2LeS => self.translate_simd_binary(Opcode::V128Le64S)
    I64x2GeS => self.translate_simd_binary(Opcode::V128Ge64S)
    I64x2Abs => self.translate_simd_unary(Opcode::V128Abs64)
    I64x2Neg => self.translate_simd_unary(Opcode::V128Neg64)
    I64x2AllTrue => self.translate_simd_to_i32(Opcode::V128AllTrue64)
    I64x2Bitmask => self.translate_simd_to_i32(Opcode::V128Bitmask64)
    I64x2ExtendLowI32x4S =>
      self.translate_simd_unary(Opcode::V128ExtendLow32to64S)
    I64x2ExtendHighI32x4S =>
      self.translate_simd_unary(Opcode::V128ExtendHigh32to64S)
    I64x2ExtendLowI32x4U =>
      self.translate_simd_unary(Opcode::V128ExtendLow32to64U)
    I64x2ExtendHighI32x4U =>
      self.translate_simd_unary(Opcode::V128ExtendHigh32to64U)
    I64x2Shl => self.translate_simd_shift(Opcode::V128Shl64)
    I64x2ShrS => self.translate_simd_shift(Opcode::V128Shr64S)
    I64x2ShrU => self.translate_simd_shift(Opcode::V128Shr64U)
    I64x2Add => self.translate_simd_binary(Opcode::V128Add64)
    I64x2Sub => self.translate_simd_binary(Opcode::V128Sub64)
    I64x2Mul => self.translate_simd_binary(Opcode::V128Mul64)
    I64x2ExtMulLowI32x4S =>
      self.translate_simd_binary(Opcode::V128ExtMulLow32to64S)
    I64x2ExtMulHighI32x4S =>
      self.translate_simd_binary(Opcode::V128ExtMulHigh32to64S)
    I64x2ExtMulLowI32x4U =>
      self.translate_simd_binary(Opcode::V128ExtMulLow32to64U)
    I64x2ExtMulHighI32x4U =>
      self.translate_simd_binary(Opcode::V128ExtMulHigh32to64U)

    // f32x4 operations
    F32x4Eq => self.translate_simd_binary(Opcode::V128EqF32)
    F32x4Ne => self.translate_simd_binary(Opcode::V128NeF32)
    F32x4Lt => self.translate_simd_binary(Opcode::V128LtF32)
    F32x4Gt => self.translate_simd_binary(Opcode::V128GtF32)
    F32x4Le => self.translate_simd_binary(Opcode::V128LeF32)
    F32x4Ge => self.translate_simd_binary(Opcode::V128GeF32)
    F32x4Ceil => self.translate_simd_unary(Opcode::V128CeilF32)
    F32x4Floor => self.translate_simd_unary(Opcode::V128FloorF32)
    F32x4Trunc => self.translate_simd_unary(Opcode::V128TruncF32)
    F32x4Nearest => self.translate_simd_unary(Opcode::V128NearestF32)
    F32x4Abs => self.translate_simd_unary(Opcode::V128AbsF32)
    F32x4Neg => self.translate_simd_unary(Opcode::V128NegF32)
    F32x4Sqrt => self.translate_simd_unary(Opcode::V128SqrtF32)
    F32x4Add => self.translate_simd_binary(Opcode::V128AddF32)
    F32x4Sub => self.translate_simd_binary(Opcode::V128SubF32)
    F32x4Mul => self.translate_simd_binary(Opcode::V128MulF32)
    F32x4Div => self.translate_simd_binary(Opcode::V128DivF32)
    F32x4Min => self.translate_simd_binary(Opcode::V128MinF32)
    F32x4Max => self.translate_simd_binary(Opcode::V128MaxF32)
    F32x4Pmin => self.translate_simd_binary(Opcode::V128PMinF32)
    F32x4Pmax => self.translate_simd_binary(Opcode::V128PMaxF32)

    // f64x2 operations
    F64x2Eq => self.translate_simd_binary(Opcode::V128EqF64)
    F64x2Ne => self.translate_simd_binary(Opcode::V128NeF64)
    F64x2Lt => self.translate_simd_binary(Opcode::V128LtF64)
    F64x2Gt => self.translate_simd_binary(Opcode::V128GtF64)
    F64x2Le => self.translate_simd_binary(Opcode::V128LeF64)
    F64x2Ge => self.translate_simd_binary(Opcode::V128GeF64)
    F64x2Ceil => self.translate_simd_unary(Opcode::V128CeilF64)
    F64x2Floor => self.translate_simd_unary(Opcode::V128FloorF64)
    F64x2Trunc => self.translate_simd_unary(Opcode::V128TruncF64)
    F64x2Nearest => self.translate_simd_unary(Opcode::V128NearestF64)
    F64x2Abs => self.translate_simd_unary(Opcode::V128AbsF64)
    F64x2Neg => self.translate_simd_unary(Opcode::V128NegF64)
    F64x2Sqrt => self.translate_simd_unary(Opcode::V128SqrtF64)
    F64x2Add => self.translate_simd_binary(Opcode::V128AddF64)
    F64x2Sub => self.translate_simd_binary(Opcode::V128SubF64)
    F64x2Mul => self.translate_simd_binary(Opcode::V128MulF64)
    F64x2Div => self.translate_simd_binary(Opcode::V128DivF64)
    F64x2Min => self.translate_simd_binary(Opcode::V128MinF64)
    F64x2Max => self.translate_simd_binary(Opcode::V128MaxF64)
    F64x2Pmin => self.translate_simd_binary(Opcode::V128PMinF64)
    F64x2Pmax => self.translate_simd_binary(Opcode::V128PMaxF64)

    // SIMD conversions
    I32x4TruncSatF32x4S =>
      self.translate_simd_unary(Opcode::V128TruncSatF32toI32S)
    I32x4TruncSatF32x4U =>
      self.translate_simd_unary(Opcode::V128TruncSatF32toI32U)
    F32x4ConvertI32x4S =>
      self.translate_simd_unary(Opcode::V128ConvertI32toF32S)
    F32x4ConvertI32x4U =>
      self.translate_simd_unary(Opcode::V128ConvertI32toF32U)
    I32x4TruncSatF64x2SZero =>
      self.translate_simd_unary(Opcode::V128TruncSatF64toI32SZero)
    I32x4TruncSatF64x2UZero =>
      self.translate_simd_unary(Opcode::V128TruncSatF64toI32UZero)
    F64x2ConvertLowI32x4S =>
      self.translate_simd_unary(Opcode::V128ConvertLowI32toF64S)
    F64x2ConvertLowI32x4U =>
      self.translate_simd_unary(Opcode::V128ConvertLowI32toF64U)
    F32x4DemoteF64x2Zero =>
      self.translate_simd_unary(Opcode::V128DemoteF64toF32Zero)
    F64x2PromoteLowF32x4 =>
      self.translate_simd_unary(Opcode::V128PromoteLowF32toF64)

    // V128 load/store operations
    V128Load(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load(
        self.builder,
        self.vmctx,
        memidx,
        Type::V128,
        addr,
        offset,
      )
      self.push(result)
    }
    V128Store(memidx, _, offset) => {
      let value = self.pop()
      let addr = self.pop()
      self.func_env.translate_memory_store(
        self.builder,
        self.vmctx,
        memidx,
        Type::V128,
        addr,
        value,
        offset,
      )
    }
    V128Load8x8S(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load8x8S(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load8x8U(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load8x8U(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load16x4S(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load16x4S(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load16x4U(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load16x4U(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load32x2S(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load32x2S(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load32x2U(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load32x2U(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load8Splat(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load8Splat(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load16Splat(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load16Splat(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load32Splat(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load32Splat(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load64Splat(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load64Splat(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load32Zero(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load32Zero(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load64Zero(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        Opcode::V128Load64Zero(memidx, 0, offset),
      )
      self.push(result)
    }
    V128Load8Lane(memidx, _, offset, lane) => {
      let vec = self.pop()
      let addr = self.pop()
      let result = self.translate_simd_load_lane(
        memidx,
        offset,
        addr,
        vec,
        Opcode::V128Load8Lane(memidx, 0, offset, lane),
      )
      self.push(result)
    }
    V128Load16Lane(memidx, _, offset, lane) => {
      let vec = self.pop()
      let addr = self.pop()
      let result = self.translate_simd_load_lane(
        memidx,
        offset,
        addr,
        vec,
        Opcode::V128Load16Lane(memidx, 0, offset, lane),
      )
      self.push(result)
    }
    V128Load32Lane(memidx, _, offset, lane) => {
      let vec = self.pop()
      let addr = self.pop()
      let result = self.translate_simd_load_lane(
        memidx,
        offset,
        addr,
        vec,
        Opcode::V128Load32Lane(memidx, 0, offset, lane),
      )
      self.push(result)
    }
    V128Load64Lane(memidx, _, offset, lane) => {
      let vec = self.pop()
      let addr = self.pop()
      let result = self.translate_simd_load_lane(
        memidx,
        offset,
        addr,
        vec,
        Opcode::V128Load64Lane(memidx, 0, offset, lane),
      )
      self.push(result)
    }
    V128Store8Lane(memidx, _, offset, lane) => {
      let vec = self.pop()
      let addr = self.pop()
      self.translate_simd_store_lane(
        memidx,
        offset,
        addr,
        vec,
        Opcode::V128Store8Lane(memidx, 0, offset, lane),
      )
    }
    V128Store16Lane(memidx, _, offset, lane) => {
      let vec = self.pop()
      let addr = self.pop()
      self.translate_simd_store_lane(
        memidx,
        offset,
        addr,
        vec,
        Opcode::V128Store16Lane(memidx, 0, offset, lane),
      )
    }
    V128Store32Lane(memidx, _, offset, lane) => {
      let vec = self.pop()
      let addr = self.pop()
      self.translate_simd_store_lane(
        memidx,
        offset,
        addr,
        vec,
        Opcode::V128Store32Lane(memidx, 0, offset, lane),
      )
    }
    V128Store64Lane(memidx, _, offset, lane) => {
      let vec = self.pop()
      let addr = self.pop()
      self.translate_simd_store_lane(
        memidx,
        offset,
        addr,
        vec,
        Opcode::V128Store64Lane(memidx, 0, offset, lane),
      )
    }

    // Relaxed SIMD instructions
    I8x16RelaxedSwizzle => {
      // Same as regular swizzle on ARM
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedSwizzle,
        [a, b],
      )
      self.push(result)
    }
    I32x4RelaxedTruncF32x4S =>
      self.translate_simd_unary(Opcode::V128RelaxedTruncF32toI32S)
    I32x4RelaxedTruncF32x4U =>
      self.translate_simd_unary(Opcode::V128RelaxedTruncF32toI32U)
    I32x4RelaxedTruncF64x2SZero =>
      self.translate_simd_unary(Opcode::V128RelaxedTruncF64toI32SZero)
    I32x4RelaxedTruncF64x2UZero =>
      self.translate_simd_unary(Opcode::V128RelaxedTruncF64toI32UZero)
    F32x4RelaxedMadd => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedMaddF32,
        [a, b, c],
      )
      self.push(result)
    }
    F32x4RelaxedNmadd => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedNmaddF32,
        [a, b, c],
      )
      self.push(result)
    }
    F64x2RelaxedMadd => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedMaddF64,
        [a, b, c],
      )
      self.push(result)
    }
    F64x2RelaxedNmadd => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedNmaddF64,
        [a, b, c],
      )
      self.push(result)
    }
    I8x16RelaxedLaneselect => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedLaneselect8,
        [a, b, c],
      )
      self.push(result)
    }
    I16x8RelaxedLaneselect => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedLaneselect16,
        [a, b, c],
      )
      self.push(result)
    }
    I32x4RelaxedLaneselect => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedLaneselect32,
        [a, b, c],
      )
      self.push(result)
    }
    I64x2RelaxedLaneselect => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedLaneselect64,
        [a, b, c],
      )
      self.push(result)
    }
    F32x4RelaxedMin => self.translate_simd_binary(Opcode::V128RelaxedMinF32)
    F32x4RelaxedMax => self.translate_simd_binary(Opcode::V128RelaxedMaxF32)
    F64x2RelaxedMin => self.translate_simd_binary(Opcode::V128RelaxedMinF64)
    F64x2RelaxedMax => self.translate_simd_binary(Opcode::V128RelaxedMaxF64)
    I16x8RelaxedQ15mulrS =>
      self.translate_simd_binary(Opcode::V128RelaxedQ15MulrS)
    I16x8RelaxedDotI8x16I7x16S =>
      self.translate_simd_binary(Opcode::V128RelaxedDot8to16S)
    I32x4RelaxedDotI8x16I7x16AddS => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        Type::V128,
        Opcode::V128RelaxedDot8to32AddS,
        [a, b, c],
      )
      self.push(result)
    }
    _ => abort("non-SIMD instruction routed to SIMD translator: \{instr}")
  }
}
