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
    I8x16Eq => self.translate_simd_binary(IntCompare(Eq, I8))
    I8x16Ne => self.translate_simd_binary(IntCompare(Ne, I8))
    I8x16LtS => self.translate_simd_binary(IntCompare(Lt(Signed), I8))
    I8x16LtU => self.translate_simd_binary(IntCompare(Lt(Unsigned), I8))
    I8x16GtS => self.translate_simd_binary(IntCompare(Gt(Signed), I8))
    I8x16GtU => self.translate_simd_binary(IntCompare(Gt(Unsigned), I8))
    I8x16LeS => self.translate_simd_binary(IntCompare(Le(Signed), I8))
    I8x16LeU => self.translate_simd_binary(IntCompare(Le(Unsigned), I8))
    I8x16GeS => self.translate_simd_binary(IntCompare(Ge(Signed), I8))
    I8x16GeU => self.translate_simd_binary(IntCompare(Ge(Unsigned), I8))
    I8x16Abs => self.translate_simd_unary(IntUnary(Abs, I8))
    I8x16Neg => self.translate_simd_unary(IntUnary(Neg, I8))
    I8x16Popcnt => self.translate_simd_unary(IntUnary(Popcnt, I8))
    I8x16AllTrue => self.translate_simd_to_i32(Predicate(AllTrue(I8)))
    I8x16Bitmask => self.translate_simd_to_i32(Predicate(Bitmask(I8)))
    I8x16NarrowI16x8S => self.translate_simd_binary(Narrow(I8, Signed))
    I8x16NarrowI16x8U => self.translate_simd_binary(Narrow(I8, Unsigned))
    I8x16Shl => self.translate_simd_shift(IntShift(Left, I8))
    I8x16ShrS => self.translate_simd_shift(IntShift(Right(Signed), I8))
    I8x16ShrU => self.translate_simd_shift(IntShift(Right(Unsigned), I8))
    I8x16Add => self.translate_simd_binary(IntBinary(Add, I8))
    I8x16AddSatS =>
      self.translate_simd_binary(IntBinary(AddSaturating(Signed), I8))
    I8x16AddSatU =>
      self.translate_simd_binary(IntBinary(AddSaturating(Unsigned), I8))
    I8x16Sub => self.translate_simd_binary(IntBinary(Sub, I8))
    I8x16SubSatS =>
      self.translate_simd_binary(IntBinary(SubSaturating(Signed), I8))
    I8x16SubSatU =>
      self.translate_simd_binary(IntBinary(SubSaturating(Unsigned), I8))
    I8x16MinS => self.translate_simd_binary(IntBinary(Min(Signed), I8))
    I8x16MinU => self.translate_simd_binary(IntBinary(Min(Unsigned), I8))
    I8x16MaxS => self.translate_simd_binary(IntBinary(Max(Signed), I8))
    I8x16MaxU => self.translate_simd_binary(IntBinary(Max(Unsigned), I8))
    I8x16AvgrU => self.translate_simd_binary(IntBinary(AverageUnsigned, I8))

    // i16x8 operations
    I16x8ExtAddPairwiseI8x16S =>
      self.translate_simd_unary(IntUnary(ExtAddPairwise(Signed), I16))
    I16x8ExtAddPairwiseI8x16U =>
      self.translate_simd_unary(IntUnary(ExtAddPairwise(Unsigned), I16))
    I16x8Eq => self.translate_simd_binary(IntCompare(Eq, I16))
    I16x8Ne => self.translate_simd_binary(IntCompare(Ne, I16))
    I16x8LtS => self.translate_simd_binary(IntCompare(Lt(Signed), I16))
    I16x8LtU => self.translate_simd_binary(IntCompare(Lt(Unsigned), I16))
    I16x8GtS => self.translate_simd_binary(IntCompare(Gt(Signed), I16))
    I16x8GtU => self.translate_simd_binary(IntCompare(Gt(Unsigned), I16))
    I16x8LeS => self.translate_simd_binary(IntCompare(Le(Signed), I16))
    I16x8LeU => self.translate_simd_binary(IntCompare(Le(Unsigned), I16))
    I16x8GeS => self.translate_simd_binary(IntCompare(Ge(Signed), I16))
    I16x8GeU => self.translate_simd_binary(IntCompare(Ge(Unsigned), I16))
    I16x8Abs => self.translate_simd_unary(IntUnary(Abs, I16))
    I16x8Neg => self.translate_simd_unary(IntUnary(Neg, I16))
    I16x8Q15MulrSatS =>
      self.translate_simd_binary(IntBinary(Q15MulrSaturating, I16))
    I16x8AllTrue => self.translate_simd_to_i32(Predicate(AllTrue(I16)))
    I16x8Bitmask => self.translate_simd_to_i32(Predicate(Bitmask(I16)))
    I16x8NarrowI32x4S => self.translate_simd_binary(Narrow(I16, Signed))
    I16x8NarrowI32x4U => self.translate_simd_binary(Narrow(I16, Unsigned))
    I16x8ExtendLowI8x16S =>
      self.translate_simd_unary(IntUnary(Extend(Low, Signed), I16))
    I16x8ExtendHighI8x16S =>
      self.translate_simd_unary(IntUnary(Extend(High, Signed), I16))
    I16x8ExtendLowI8x16U =>
      self.translate_simd_unary(IntUnary(Extend(Low, Unsigned), I16))
    I16x8ExtendHighI8x16U =>
      self.translate_simd_unary(IntUnary(Extend(High, Unsigned), I16))
    I16x8Shl => self.translate_simd_shift(IntShift(Left, I16))
    I16x8ShrS => self.translate_simd_shift(IntShift(Right(Signed), I16))
    I16x8ShrU => self.translate_simd_shift(IntShift(Right(Unsigned), I16))
    I16x8Add => self.translate_simd_binary(IntBinary(Add, I16))
    I16x8AddSatS =>
      self.translate_simd_binary(IntBinary(AddSaturating(Signed), I16))
    I16x8AddSatU =>
      self.translate_simd_binary(IntBinary(AddSaturating(Unsigned), I16))
    I16x8Sub => self.translate_simd_binary(IntBinary(Sub, I16))
    I16x8SubSatS =>
      self.translate_simd_binary(IntBinary(SubSaturating(Signed), I16))
    I16x8SubSatU =>
      self.translate_simd_binary(IntBinary(SubSaturating(Unsigned), I16))
    I16x8Mul => self.translate_simd_binary(IntBinary(Mul, I16))
    I16x8MinS => self.translate_simd_binary(IntBinary(Min(Signed), I16))
    I16x8MinU => self.translate_simd_binary(IntBinary(Min(Unsigned), I16))
    I16x8MaxS => self.translate_simd_binary(IntBinary(Max(Signed), I16))
    I16x8MaxU => self.translate_simd_binary(IntBinary(Max(Unsigned), I16))
    I16x8AvgrU => self.translate_simd_binary(IntBinary(AverageUnsigned, I16))
    I16x8ExtMulLowI8x16S =>
      self.translate_simd_binary(IntBinary(ExtMul(Low, Signed), I16))
    I16x8ExtMulHighI8x16S =>
      self.translate_simd_binary(IntBinary(ExtMul(High, Signed), I16))
    I16x8ExtMulLowI8x16U =>
      self.translate_simd_binary(IntBinary(ExtMul(Low, Unsigned), I16))
    I16x8ExtMulHighI8x16U =>
      self.translate_simd_binary(IntBinary(ExtMul(High, Unsigned), I16))

    // i32x4 operations
    I32x4ExtAddPairwiseI16x8S =>
      self.translate_simd_unary(IntUnary(ExtAddPairwise(Signed), I32))
    I32x4ExtAddPairwiseI16x8U =>
      self.translate_simd_unary(IntUnary(ExtAddPairwise(Unsigned), I32))
    I32x4Eq => self.translate_simd_binary(IntCompare(Eq, I32))
    I32x4Ne => self.translate_simd_binary(IntCompare(Ne, I32))
    I32x4LtS => self.translate_simd_binary(IntCompare(Lt(Signed), I32))
    I32x4LtU => self.translate_simd_binary(IntCompare(Lt(Unsigned), I32))
    I32x4GtS => self.translate_simd_binary(IntCompare(Gt(Signed), I32))
    I32x4GtU => self.translate_simd_binary(IntCompare(Gt(Unsigned), I32))
    I32x4LeS => self.translate_simd_binary(IntCompare(Le(Signed), I32))
    I32x4LeU => self.translate_simd_binary(IntCompare(Le(Unsigned), I32))
    I32x4GeS => self.translate_simd_binary(IntCompare(Ge(Signed), I32))
    I32x4GeU => self.translate_simd_binary(IntCompare(Ge(Unsigned), I32))
    I32x4Abs => self.translate_simd_unary(IntUnary(Abs, I32))
    I32x4Neg => self.translate_simd_unary(IntUnary(Neg, I32))
    I32x4AllTrue => self.translate_simd_to_i32(Predicate(AllTrue(I32)))
    I32x4Bitmask => self.translate_simd_to_i32(Predicate(Bitmask(I32)))
    I32x4ExtendLowI16x8S =>
      self.translate_simd_unary(IntUnary(Extend(Low, Signed), I32))
    I32x4ExtendHighI16x8S =>
      self.translate_simd_unary(IntUnary(Extend(High, Signed), I32))
    I32x4ExtendLowI16x8U =>
      self.translate_simd_unary(IntUnary(Extend(Low, Unsigned), I32))
    I32x4ExtendHighI16x8U =>
      self.translate_simd_unary(IntUnary(Extend(High, Unsigned), I32))
    I32x4Shl => self.translate_simd_shift(IntShift(Left, I32))
    I32x4ShrS => self.translate_simd_shift(IntShift(Right(Signed), I32))
    I32x4ShrU => self.translate_simd_shift(IntShift(Right(Unsigned), I32))
    I32x4Add => self.translate_simd_binary(IntBinary(Add, I32))
    I32x4Sub => self.translate_simd_binary(IntBinary(Sub, I32))
    I32x4Mul => self.translate_simd_binary(IntBinary(Mul, I32))
    I32x4MinS => self.translate_simd_binary(IntBinary(Min(Signed), I32))
    I32x4MinU => self.translate_simd_binary(IntBinary(Min(Unsigned), I32))
    I32x4MaxS => self.translate_simd_binary(IntBinary(Max(Signed), I32))
    I32x4MaxU => self.translate_simd_binary(IntBinary(Max(Unsigned), I32))
    I32x4DotI16x8S =>
      self.translate_simd_binary(IntBinary(Dot16To32Signed, I32))
    I32x4ExtMulLowI16x8S =>
      self.translate_simd_binary(IntBinary(ExtMul(Low, Signed), I32))
    I32x4ExtMulHighI16x8S =>
      self.translate_simd_binary(IntBinary(ExtMul(High, Signed), I32))
    I32x4ExtMulLowI16x8U =>
      self.translate_simd_binary(IntBinary(ExtMul(Low, Unsigned), I32))
    I32x4ExtMulHighI16x8U =>
      self.translate_simd_binary(IntBinary(ExtMul(High, Unsigned), I32))

    // i64x2 operations
    I64x2Eq => self.translate_simd_binary(IntCompare(Eq, I64))
    I64x2Ne => self.translate_simd_binary(IntCompare(Ne, I64))
    I64x2LtS => self.translate_simd_binary(IntCompare(Lt(Signed), I64))
    I64x2GtS => self.translate_simd_binary(IntCompare(Gt(Signed), I64))
    I64x2LeS => self.translate_simd_binary(IntCompare(Le(Signed), I64))
    I64x2GeS => self.translate_simd_binary(IntCompare(Ge(Signed), I64))
    I64x2Abs => self.translate_simd_unary(IntUnary(Abs, I64))
    I64x2Neg => self.translate_simd_unary(IntUnary(Neg, I64))
    I64x2AllTrue => self.translate_simd_to_i32(Predicate(AllTrue(I64)))
    I64x2Bitmask => self.translate_simd_to_i32(Predicate(Bitmask(I64)))
    I64x2ExtendLowI32x4S =>
      self.translate_simd_unary(IntUnary(Extend(Low, Signed), I64))
    I64x2ExtendHighI32x4S =>
      self.translate_simd_unary(IntUnary(Extend(High, Signed), I64))
    I64x2ExtendLowI32x4U =>
      self.translate_simd_unary(IntUnary(Extend(Low, Unsigned), I64))
    I64x2ExtendHighI32x4U =>
      self.translate_simd_unary(IntUnary(Extend(High, Unsigned), I64))
    I64x2Shl => self.translate_simd_shift(IntShift(Left, I64))
    I64x2ShrS => self.translate_simd_shift(IntShift(Right(Signed), I64))
    I64x2ShrU => self.translate_simd_shift(IntShift(Right(Unsigned), I64))
    I64x2Add => self.translate_simd_binary(IntBinary(Add, I64))
    I64x2Sub => self.translate_simd_binary(IntBinary(Sub, I64))
    I64x2Mul => self.translate_simd_binary(IntBinary(Mul, I64))
    I64x2ExtMulLowI32x4S =>
      self.translate_simd_binary(IntBinary(ExtMul(Low, Signed), I64))
    I64x2ExtMulHighI32x4S =>
      self.translate_simd_binary(IntBinary(ExtMul(High, Signed), I64))
    I64x2ExtMulLowI32x4U =>
      self.translate_simd_binary(IntBinary(ExtMul(Low, Unsigned), I64))
    I64x2ExtMulHighI32x4U =>
      self.translate_simd_binary(IntBinary(ExtMul(High, Unsigned), I64))

    // f32x4 operations
    F32x4Eq => self.translate_simd_binary(FloatCompare(Eq, F32))
    F32x4Ne => self.translate_simd_binary(FloatCompare(Ne, F32))
    F32x4Lt => self.translate_simd_binary(FloatCompare(Lt, F32))
    F32x4Gt => self.translate_simd_binary(FloatCompare(Gt, F32))
    F32x4Le => self.translate_simd_binary(FloatCompare(Le, F32))
    F32x4Ge => self.translate_simd_binary(FloatCompare(Ge, F32))
    F32x4Ceil => self.translate_simd_unary(FloatUnary(Ceil, F32))
    F32x4Floor => self.translate_simd_unary(FloatUnary(Floor, F32))
    F32x4Trunc => self.translate_simd_unary(FloatUnary(Trunc, F32))
    F32x4Nearest => self.translate_simd_unary(FloatUnary(Nearest, F32))
    F32x4Abs => self.translate_simd_unary(FloatUnary(Abs, F32))
    F32x4Neg => self.translate_simd_unary(FloatUnary(Neg, F32))
    F32x4Sqrt => self.translate_simd_unary(FloatUnary(Sqrt, F32))
    F32x4Add => self.translate_simd_binary(FloatBinary(Add, F32))
    F32x4Sub => self.translate_simd_binary(FloatBinary(Sub, F32))
    F32x4Mul => self.translate_simd_binary(FloatBinary(Mul, F32))
    F32x4Div => self.translate_simd_binary(FloatBinary(Div, F32))
    F32x4Min => self.translate_simd_binary(FloatBinary(Min, F32))
    F32x4Max => self.translate_simd_binary(FloatBinary(Max, F32))
    F32x4Pmin => self.translate_simd_binary(FloatBinary(PseudoMin, F32))
    F32x4Pmax => self.translate_simd_binary(FloatBinary(PseudoMax, F32))

    // f64x2 operations
    F64x2Eq => self.translate_simd_binary(FloatCompare(Eq, F64))
    F64x2Ne => self.translate_simd_binary(FloatCompare(Ne, F64))
    F64x2Lt => self.translate_simd_binary(FloatCompare(Lt, F64))
    F64x2Gt => self.translate_simd_binary(FloatCompare(Gt, F64))
    F64x2Le => self.translate_simd_binary(FloatCompare(Le, F64))
    F64x2Ge => self.translate_simd_binary(FloatCompare(Ge, F64))
    F64x2Ceil => self.translate_simd_unary(FloatUnary(Ceil, F64))
    F64x2Floor => self.translate_simd_unary(FloatUnary(Floor, F64))
    F64x2Trunc => self.translate_simd_unary(FloatUnary(Trunc, F64))
    F64x2Nearest => self.translate_simd_unary(FloatUnary(Nearest, F64))
    F64x2Abs => self.translate_simd_unary(FloatUnary(Abs, F64))
    F64x2Neg => self.translate_simd_unary(FloatUnary(Neg, F64))
    F64x2Sqrt => self.translate_simd_unary(FloatUnary(Sqrt, F64))
    F64x2Add => self.translate_simd_binary(FloatBinary(Add, F64))
    F64x2Sub => self.translate_simd_binary(FloatBinary(Sub, F64))
    F64x2Mul => self.translate_simd_binary(FloatBinary(Mul, F64))
    F64x2Div => self.translate_simd_binary(FloatBinary(Div, F64))
    F64x2Min => self.translate_simd_binary(FloatBinary(Min, F64))
    F64x2Max => self.translate_simd_binary(FloatBinary(Max, F64))
    F64x2Pmin => self.translate_simd_binary(FloatBinary(PseudoMin, F64))
    F64x2Pmax => self.translate_simd_binary(FloatBinary(PseudoMax, F64))

    // SIMD conversions
    I32x4TruncSatF32x4S =>
      self.translate_simd_unary(Convert(TruncSatF32ToI32(Signed)))
    I32x4TruncSatF32x4U =>
      self.translate_simd_unary(Convert(TruncSatF32ToI32(Unsigned)))
    F32x4ConvertI32x4S =>
      self.translate_simd_unary(Convert(ConvertI32ToF32(Signed)))
    F32x4ConvertI32x4U =>
      self.translate_simd_unary(Convert(ConvertI32ToF32(Unsigned)))
    I32x4TruncSatF64x2SZero =>
      self.translate_simd_unary(Convert(TruncSatF64ToI32Zero(Signed)))
    I32x4TruncSatF64x2UZero =>
      self.translate_simd_unary(Convert(TruncSatF64ToI32Zero(Unsigned)))
    F64x2ConvertLowI32x4S =>
      self.translate_simd_unary(Convert(ConvertLowI32ToF64(Signed)))
    F64x2ConvertLowI32x4U =>
      self.translate_simd_unary(Convert(ConvertLowI32ToF64(Unsigned)))
    F32x4DemoteF64x2Zero =>
      self.translate_simd_unary(Convert(DemoteF64ToF32Zero))
    F64x2PromoteLowF32x4 =>
      self.translate_simd_unary(Convert(PromoteLowF32ToF64))

    // V128 load/store operations
    V128Load(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.func_env.translate_memory_load(
        self.builder,
        self.vmctx,
        memidx,
        V128,
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
        V128,
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
        LoadExtend(I8, Signed),
      )
      self.push(result)
    }
    V128Load8x8U(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        LoadExtend(I8, Unsigned),
      )
      self.push(result)
    }
    V128Load16x4S(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        LoadExtend(I16, Signed),
      )
      self.push(result)
    }
    V128Load16x4U(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        LoadExtend(I16, Unsigned),
      )
      self.push(result)
    }
    V128Load32x2S(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        LoadExtend(I32, Signed),
      )
      self.push(result)
    }
    V128Load32x2U(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        LoadExtend(I32, Unsigned),
      )
      self.push(result)
    }
    V128Load8Splat(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(memidx, offset, addr, LoadSplat(I8))
      self.push(result)
    }
    V128Load16Splat(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        LoadSplat(I16),
      )
      self.push(result)
    }
    V128Load32Splat(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        LoadSplat(I32),
      )
      self.push(result)
    }
    V128Load64Splat(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(
        memidx,
        offset,
        addr,
        LoadSplat(I64),
      )
      self.push(result)
    }
    V128Load32Zero(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(memidx, offset, addr, LoadZero(I32))
      self.push(result)
    }
    V128Load64Zero(memidx, _, offset) => {
      let addr = self.pop()
      let result = self.translate_simd_load(memidx, offset, addr, LoadZero(I64))
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
        LoadLane(I8, lane),
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
        LoadLane(I16, lane),
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
        LoadLane(I32, lane),
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
        LoadLane(I64, lane),
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
        StoreLane(I8, lane),
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
        StoreLane(I16, lane),
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
        StoreLane(I32, lane),
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
        StoreLane(I64, lane),
      )
    }

    // Relaxed SIMD instructions
    I8x16RelaxedSwizzle => {
      // Same as regular swizzle on ARM
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(V128, Vector(Relaxed(Swizzle)), [a, b])
      self.push(result)
    }
    I32x4RelaxedTruncF32x4S =>
      self.translate_simd_unary(Relaxed(TruncF32ToI32(Signed)))
    I32x4RelaxedTruncF32x4U =>
      self.translate_simd_unary(Relaxed(TruncF32ToI32(Unsigned)))
    I32x4RelaxedTruncF64x2SZero =>
      self.translate_simd_unary(Relaxed(TruncF64ToI32Zero(Signed)))
    I32x4RelaxedTruncF64x2UZero =>
      self.translate_simd_unary(Relaxed(TruncF64ToI32Zero(Unsigned)))
    F32x4RelaxedMadd => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        V128,
        Vector(Relaxed(Fma(F32, Add))),
        [a, b, c],
      )
      self.push(result)
    }
    F32x4RelaxedNmadd => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        V128,
        Vector(Relaxed(Fma(F32, NegatedAdd))),
        [a, b, c],
      )
      self.push(result)
    }
    F64x2RelaxedMadd => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        V128,
        Vector(Relaxed(Fma(F64, Add))),
        [a, b, c],
      )
      self.push(result)
    }
    F64x2RelaxedNmadd => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        V128,
        Vector(Relaxed(Fma(F64, NegatedAdd))),
        [a, b, c],
      )
      self.push(result)
    }
    I8x16RelaxedLaneselect => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        V128,
        Vector(Relaxed(LaneSelect(I8))),
        [a, b, c],
      )
      self.push(result)
    }
    I16x8RelaxedLaneselect => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        V128,
        Vector(Relaxed(LaneSelect(I16))),
        [a, b, c],
      )
      self.push(result)
    }
    I32x4RelaxedLaneselect => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        V128,
        Vector(Relaxed(LaneSelect(I32))),
        [a, b, c],
      )
      self.push(result)
    }
    I64x2RelaxedLaneselect => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        V128,
        Vector(Relaxed(LaneSelect(I64))),
        [a, b, c],
      )
      self.push(result)
    }
    F32x4RelaxedMin => self.translate_simd_binary(Relaxed(Min(F32)))
    F32x4RelaxedMax => self.translate_simd_binary(Relaxed(Max(F32)))
    F64x2RelaxedMin => self.translate_simd_binary(Relaxed(Min(F64)))
    F64x2RelaxedMax => self.translate_simd_binary(Relaxed(Max(F64)))
    I16x8RelaxedQ15mulrS => self.translate_simd_binary(Relaxed(Q15MulrSigned))
    I16x8RelaxedDotI8x16I7x16S =>
      self.translate_simd_binary(Relaxed(Dot8To16Signed))
    I32x4RelaxedDotI8x16I7x16AddS => {
      let c = self.pop()
      let b = self.pop()
      let a = self.pop()
      let result = self.builder.emit_inst(
        V128,
        Vector(Relaxed(Dot8To32AddSigned)),
        [a, b, c],
      )
      self.push(result)
    }
    _ => abort("non-SIMD instruction routed to SIMD translator: \{instr}")
  }
}
