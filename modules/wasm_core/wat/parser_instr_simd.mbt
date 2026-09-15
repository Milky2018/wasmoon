// Dispatch by instruction family keeps generated C functions within native compiler limits.

///|
fn Parser::parse_v128_instruction(
  self : Parser,
  kw : String,
) -> @types.Instruction raise WatError {
  match kw {
    // SIMD instructions
    "v128.const" => {
      let bytes = self.parse_v128_const()
      V128Const(bytes)
    }

    // SIMD memory operations
    "v128.load" => parse_mem_arg(self, fn(m, a, o) { V128Load(m, a, o) })
    "v128.store" => parse_mem_arg(self, fn(m, a, o) { V128Store(m, a, o) })
    "v128.load8x8_s" =>
      parse_mem_arg(self, fn(m, a, o) { V128Load8x8S(m, a, o) })
    "v128.load8x8_u" =>
      parse_mem_arg(self, fn(m, a, o) { V128Load8x8U(m, a, o) })
    "v128.load16x4_s" =>
      parse_mem_arg(self, fn(m, a, o) { V128Load16x4S(m, a, o) })
    "v128.load16x4_u" =>
      parse_mem_arg(self, fn(m, a, o) { V128Load16x4U(m, a, o) })
    "v128.load32x2_s" =>
      parse_mem_arg(self, fn(m, a, o) { V128Load32x2S(m, a, o) })
    "v128.load32x2_u" =>
      parse_mem_arg(self, fn(m, a, o) { V128Load32x2U(m, a, o) })
    "v128.load8_splat" =>
      parse_mem_arg(self, fn(m, a, o) { V128Load8Splat(m, a, o) })
    "v128.load16_splat" =>
      parse_mem_arg(self, fn(m, a, o) { V128Load16Splat(m, a, o) })
    "v128.load32_splat" =>
      parse_mem_arg(self, fn(m, a, o) { V128Load32Splat(m, a, o) })
    "v128.load64_splat" =>
      parse_mem_arg(self, fn(m, a, o) { V128Load64Splat(m, a, o) })
    "v128.load32_zero" =>
      parse_mem_arg(self, fn(m, a, o) { V128Load32Zero(m, a, o) })
    "v128.load64_zero" =>
      parse_mem_arg(self, fn(m, a, o) { V128Load64Zero(m, a, o) })
    "v128.load8_lane" => {
      let (memidx, align, offset) = parse_mem_arg_tuple(self)
      let lane = self.parse_u32()
      V128Load8Lane(memidx, align, offset, lane)
    }
    "v128.load16_lane" => {
      let (memidx, align, offset) = parse_mem_arg_tuple(self)
      let lane = self.parse_u32()
      V128Load16Lane(memidx, align, offset, lane)
    }
    "v128.load32_lane" => {
      let (memidx, align, offset) = parse_mem_arg_tuple(self)
      let lane = self.parse_u32()
      V128Load32Lane(memidx, align, offset, lane)
    }
    "v128.load64_lane" => {
      let (memidx, align, offset) = parse_mem_arg_tuple(self)
      let lane = self.parse_u32()
      V128Load64Lane(memidx, align, offset, lane)
    }
    "v128.store8_lane" => {
      let (memidx, align, offset) = parse_mem_arg_tuple(self)
      let lane = self.parse_u32()
      V128Store8Lane(memidx, align, offset, lane)
    }
    "v128.store16_lane" => {
      let (memidx, align, offset) = parse_mem_arg_tuple(self)
      let lane = self.parse_u32()
      V128Store16Lane(memidx, align, offset, lane)
    }
    "v128.store32_lane" => {
      let (memidx, align, offset) = parse_mem_arg_tuple(self)
      let lane = self.parse_u32()
      V128Store32Lane(memidx, align, offset, lane)
    }
    "v128.store64_lane" => {
      let (memidx, align, offset) = parse_mem_arg_tuple(self)
      let lane = self.parse_u32()
      V128Store64Lane(memidx, align, offset, lane)
    }

    // SIMD bitwise
    "v128.not" => V128Not
    "v128.and" => V128And
    "v128.andnot" => V128AndNot
    "v128.or" => V128Or
    "v128.xor" => V128Xor
    "v128.bitselect" => V128Bitselect
    "v128.any_true" => V128AnyTrue
    _ => self.parse_atomic_instruction(kw)
  }
}

///|
fn Parser::parse_i8x16_instruction(
  self : Parser,
  kw : String,
) -> @types.Instruction raise WatError {
  match kw {

    // SIMD shuffle and swizzle
    "i8x16.shuffle" => {
      // Parse 16 lane indices
      let lanes : FixedArray[Int] = FixedArray::make(16, 0)
      for i in 0..<16 {
        lanes[i] = self.parse_u32()
      }
      I8x16Shuffle(lanes)
    }
    "i8x16.swizzle" => I8x16Swizzle

    // SIMD splat
    "i8x16.splat" => I8x16Splat

    // SIMD extract lane
    "i8x16.extract_lane_s" => I8x16ExtractLaneS(self.parse_u32())
    "i8x16.extract_lane_u" => I8x16ExtractLaneU(self.parse_u32())

    // SIMD replace lane
    "i8x16.replace_lane" => I8x16ReplaceLane(self.parse_u32())

    // SIMD comparisons - i8x16
    "i8x16.eq" => I8x16Eq
    "i8x16.ne" => I8x16Ne
    "i8x16.lt_s" => I8x16LtS
    "i8x16.lt_u" => I8x16LtU
    "i8x16.gt_s" => I8x16GtS
    "i8x16.gt_u" => I8x16GtU
    "i8x16.le_s" => I8x16LeS
    "i8x16.le_u" => I8x16LeU
    "i8x16.ge_s" => I8x16GeS
    "i8x16.ge_u" => I8x16GeU

    // i8x16 operations
    "i8x16.abs" => I8x16Abs
    "i8x16.neg" => I8x16Neg
    "i8x16.popcnt" => I8x16Popcnt
    "i8x16.all_true" => I8x16AllTrue
    "i8x16.bitmask" => I8x16Bitmask
    "i8x16.narrow_i16x8_s" => I8x16NarrowI16x8S
    "i8x16.narrow_i16x8_u" => I8x16NarrowI16x8U
    "i8x16.shl" => I8x16Shl
    "i8x16.shr_s" => I8x16ShrS
    "i8x16.shr_u" => I8x16ShrU
    "i8x16.add" => I8x16Add
    "i8x16.add_sat_s" => I8x16AddSatS
    "i8x16.add_sat_u" => I8x16AddSatU
    "i8x16.sub" => I8x16Sub
    "i8x16.sub_sat_s" => I8x16SubSatS
    "i8x16.sub_sat_u" => I8x16SubSatU
    "i8x16.min_s" => I8x16MinS
    "i8x16.min_u" => I8x16MinU
    "i8x16.max_s" => I8x16MaxS
    "i8x16.max_u" => I8x16MaxU
    "i8x16.avgr_u" => I8x16AvgrU

    // Relaxed SIMD instructions
    "i8x16.relaxed_swizzle" => I8x16RelaxedSwizzle
    "i8x16.relaxed_laneselect" => I8x16RelaxedLaneselect
    _ => self.parse_atomic_instruction(kw)
  }
}

///|
fn Parser::parse_i16x8_instruction(
  self : Parser,
  kw : String,
) -> @types.Instruction raise WatError {
  match kw {
    "i16x8.splat" => I16x8Splat
    "i16x8.extract_lane_s" => I16x8ExtractLaneS(self.parse_u32())
    "i16x8.extract_lane_u" => I16x8ExtractLaneU(self.parse_u32())
    "i16x8.replace_lane" => I16x8ReplaceLane(self.parse_u32())

    // SIMD comparisons - i16x8
    "i16x8.eq" => I16x8Eq
    "i16x8.ne" => I16x8Ne
    "i16x8.lt_s" => I16x8LtS
    "i16x8.lt_u" => I16x8LtU
    "i16x8.gt_s" => I16x8GtS
    "i16x8.gt_u" => I16x8GtU
    "i16x8.le_s" => I16x8LeS
    "i16x8.le_u" => I16x8LeU
    "i16x8.ge_s" => I16x8GeS
    "i16x8.ge_u" => I16x8GeU

    // i16x8 operations
    "i16x8.abs" => I16x8Abs
    "i16x8.neg" => I16x8Neg
    "i16x8.all_true" => I16x8AllTrue
    "i16x8.bitmask" => I16x8Bitmask
    "i16x8.narrow_i32x4_s" => I16x8NarrowI32x4S
    "i16x8.narrow_i32x4_u" => I16x8NarrowI32x4U
    "i16x8.extend_low_i8x16_s" => I16x8ExtendLowI8x16S
    "i16x8.extend_high_i8x16_s" => I16x8ExtendHighI8x16S
    "i16x8.extend_low_i8x16_u" => I16x8ExtendLowI8x16U
    "i16x8.extend_high_i8x16_u" => I16x8ExtendHighI8x16U
    "i16x8.shl" => I16x8Shl
    "i16x8.shr_s" => I16x8ShrS
    "i16x8.shr_u" => I16x8ShrU
    "i16x8.add" => I16x8Add
    "i16x8.add_sat_s" => I16x8AddSatS
    "i16x8.add_sat_u" => I16x8AddSatU
    "i16x8.sub" => I16x8Sub
    "i16x8.sub_sat_s" => I16x8SubSatS
    "i16x8.sub_sat_u" => I16x8SubSatU
    "i16x8.mul" => I16x8Mul
    "i16x8.min_s" => I16x8MinS
    "i16x8.min_u" => I16x8MinU
    "i16x8.max_s" => I16x8MaxS
    "i16x8.max_u" => I16x8MaxU
    "i16x8.avgr_u" => I16x8AvgrU
    "i16x8.extmul_low_i8x16_s" => I16x8ExtMulLowI8x16S
    "i16x8.extmul_high_i8x16_s" => I16x8ExtMulHighI8x16S
    "i16x8.extmul_low_i8x16_u" => I16x8ExtMulLowI8x16U
    "i16x8.extmul_high_i8x16_u" => I16x8ExtMulHighI8x16U
    "i16x8.q15mulr_sat_s" => I16x8Q15MulrSatS
    "i16x8.extadd_pairwise_i8x16_s" => I16x8ExtAddPairwiseI8x16S
    "i16x8.extadd_pairwise_i8x16_u" => I16x8ExtAddPairwiseI8x16U
    "i16x8.relaxed_laneselect" => I16x8RelaxedLaneselect
    "i16x8.relaxed_q15mulr_s" => I16x8RelaxedQ15mulrS
    "i16x8.relaxed_dot_i8x16_i7x16_s" => I16x8RelaxedDotI8x16I7x16S
    _ => self.parse_atomic_instruction(kw)
  }
}

///|
fn Parser::parse_i32x4_instruction(
  self : Parser,
  kw : String,
) -> @types.Instruction raise WatError {
  match kw {
    "i32x4.splat" => I32x4Splat
    "i32x4.extract_lane" => I32x4ExtractLane(self.parse_u32())
    "i32x4.replace_lane" => I32x4ReplaceLane(self.parse_u32())

    // SIMD comparisons - i32x4
    "i32x4.eq" => I32x4Eq
    "i32x4.ne" => I32x4Ne
    "i32x4.lt_s" => I32x4LtS
    "i32x4.lt_u" => I32x4LtU
    "i32x4.gt_s" => I32x4GtS
    "i32x4.gt_u" => I32x4GtU
    "i32x4.le_s" => I32x4LeS
    "i32x4.le_u" => I32x4LeU
    "i32x4.ge_s" => I32x4GeS
    "i32x4.ge_u" => I32x4GeU

    // i32x4 operations
    "i32x4.abs" => I32x4Abs
    "i32x4.neg" => I32x4Neg
    "i32x4.all_true" => I32x4AllTrue
    "i32x4.bitmask" => I32x4Bitmask
    "i32x4.extend_low_i16x8_s" => I32x4ExtendLowI16x8S
    "i32x4.extend_high_i16x8_s" => I32x4ExtendHighI16x8S
    "i32x4.extend_low_i16x8_u" => I32x4ExtendLowI16x8U
    "i32x4.extend_high_i16x8_u" => I32x4ExtendHighI16x8U
    "i32x4.shl" => I32x4Shl
    "i32x4.shr_s" => I32x4ShrS
    "i32x4.shr_u" => I32x4ShrU
    "i32x4.add" => I32x4Add
    "i32x4.sub" => I32x4Sub
    "i32x4.mul" => I32x4Mul
    "i32x4.min_s" => I32x4MinS
    "i32x4.min_u" => I32x4MinU
    "i32x4.max_s" => I32x4MaxS
    "i32x4.max_u" => I32x4MaxU
    "i32x4.dot_i16x8_s" => I32x4DotI16x8S
    "i32x4.extmul_low_i16x8_s" => I32x4ExtMulLowI16x8S
    "i32x4.extmul_high_i16x8_s" => I32x4ExtMulHighI16x8S
    "i32x4.extmul_low_i16x8_u" => I32x4ExtMulLowI16x8U
    "i32x4.extmul_high_i16x8_u" => I32x4ExtMulHighI16x8U
    "i32x4.extadd_pairwise_i16x8_s" => I32x4ExtAddPairwiseI16x8S
    "i32x4.extadd_pairwise_i16x8_u" => I32x4ExtAddPairwiseI16x8U
    "i32x4.trunc_sat_f32x4_s" => I32x4TruncSatF32x4S
    "i32x4.trunc_sat_f32x4_u" => I32x4TruncSatF32x4U
    "i32x4.trunc_sat_f64x2_s_zero" => I32x4TruncSatF64x2SZero
    "i32x4.trunc_sat_f64x2_u_zero" => I32x4TruncSatF64x2UZero
    "i32x4.relaxed_trunc_f32x4_s" => I32x4RelaxedTruncF32x4S
    "i32x4.relaxed_trunc_f32x4_u" => I32x4RelaxedTruncF32x4U
    "i32x4.relaxed_trunc_f64x2_s_zero" => I32x4RelaxedTruncF64x2SZero
    "i32x4.relaxed_trunc_f64x2_u_zero" => I32x4RelaxedTruncF64x2UZero
    "i32x4.relaxed_laneselect" => I32x4RelaxedLaneselect
    "i32x4.relaxed_dot_i8x16_i7x16_add_s" => I32x4RelaxedDotI8x16I7x16AddS
    _ => self.parse_atomic_instruction(kw)
  }
}

///|
fn Parser::parse_i64x2_instruction(
  self : Parser,
  kw : String,
) -> @types.Instruction raise WatError {
  match kw {
    "i64x2.splat" => I64x2Splat
    "i64x2.extract_lane" => I64x2ExtractLane(self.parse_u32())
    "i64x2.replace_lane" => I64x2ReplaceLane(self.parse_u32())

    // SIMD comparisons - i64x2
    "i64x2.eq" => I64x2Eq
    "i64x2.ne" => I64x2Ne
    "i64x2.lt_s" => I64x2LtS
    "i64x2.gt_s" => I64x2GtS
    "i64x2.le_s" => I64x2LeS
    "i64x2.ge_s" => I64x2GeS

    // i64x2 operations
    "i64x2.abs" => I64x2Abs
    "i64x2.neg" => I64x2Neg
    "i64x2.all_true" => I64x2AllTrue
    "i64x2.bitmask" => I64x2Bitmask
    "i64x2.extend_low_i32x4_s" => I64x2ExtendLowI32x4S
    "i64x2.extend_high_i32x4_s" => I64x2ExtendHighI32x4S
    "i64x2.extend_low_i32x4_u" => I64x2ExtendLowI32x4U
    "i64x2.extend_high_i32x4_u" => I64x2ExtendHighI32x4U
    "i64x2.shl" => I64x2Shl
    "i64x2.shr_s" => I64x2ShrS
    "i64x2.shr_u" => I64x2ShrU
    "i64x2.add" => I64x2Add
    "i64x2.sub" => I64x2Sub
    "i64x2.mul" => I64x2Mul
    "i64x2.extmul_low_i32x4_s" => I64x2ExtMulLowI32x4S
    "i64x2.extmul_high_i32x4_s" => I64x2ExtMulHighI32x4S
    "i64x2.extmul_low_i32x4_u" => I64x2ExtMulLowI32x4U
    "i64x2.extmul_high_i32x4_u" => I64x2ExtMulHighI32x4U
    "i64x2.relaxed_laneselect" => I64x2RelaxedLaneselect
    _ => self.parse_atomic_instruction(kw)
  }
}

///|
fn Parser::parse_f32x4_instruction(
  self : Parser,
  kw : String,
) -> @types.Instruction raise WatError {
  match kw {
    "f32x4.splat" => F32x4Splat
    "f32x4.extract_lane" => F32x4ExtractLane(self.parse_u32())
    "f32x4.replace_lane" => F32x4ReplaceLane(self.parse_u32())

    // SIMD comparisons - f32x4
    "f32x4.eq" => F32x4Eq
    "f32x4.ne" => F32x4Ne
    "f32x4.lt" => F32x4Lt
    "f32x4.gt" => F32x4Gt
    "f32x4.le" => F32x4Le
    "f32x4.ge" => F32x4Ge

    // f32x4 operations
    "f32x4.abs" => F32x4Abs
    "f32x4.neg" => F32x4Neg
    "f32x4.sqrt" => F32x4Sqrt
    "f32x4.add" => F32x4Add
    "f32x4.sub" => F32x4Sub
    "f32x4.mul" => F32x4Mul
    "f32x4.div" => F32x4Div
    "f32x4.min" => F32x4Min
    "f32x4.max" => F32x4Max
    "f32x4.pmin" => F32x4Pmin
    "f32x4.pmax" => F32x4Pmax
    "f32x4.ceil" => F32x4Ceil
    "f32x4.floor" => F32x4Floor
    "f32x4.trunc" => F32x4Trunc
    "f32x4.nearest" => F32x4Nearest
    "f32x4.convert_i32x4_s" => F32x4ConvertI32x4S
    "f32x4.convert_i32x4_u" => F32x4ConvertI32x4U
    "f32x4.demote_f64x2_zero" => F32x4DemoteF64x2Zero
    "f32x4.relaxed_madd" => F32x4RelaxedMadd
    "f32x4.relaxed_nmadd" => F32x4RelaxedNmadd
    "f32x4.relaxed_min" => F32x4RelaxedMin
    "f32x4.relaxed_max" => F32x4RelaxedMax
    _ => self.parse_atomic_instruction(kw)
  }
}

///|
fn Parser::parse_f64x2_instruction(
  self : Parser,
  kw : String,
) -> @types.Instruction raise WatError {
  match kw {
    "f64x2.splat" => F64x2Splat
    "f64x2.extract_lane" => F64x2ExtractLane(self.parse_u32())
    "f64x2.replace_lane" => F64x2ReplaceLane(self.parse_u32())

    // SIMD comparisons - f64x2
    "f64x2.eq" => F64x2Eq
    "f64x2.ne" => F64x2Ne
    "f64x2.lt" => F64x2Lt
    "f64x2.gt" => F64x2Gt
    "f64x2.le" => F64x2Le
    "f64x2.ge" => F64x2Ge

    // f64x2 operations
    "f64x2.abs" => F64x2Abs
    "f64x2.neg" => F64x2Neg
    "f64x2.sqrt" => F64x2Sqrt
    "f64x2.add" => F64x2Add
    "f64x2.sub" => F64x2Sub
    "f64x2.mul" => F64x2Mul
    "f64x2.div" => F64x2Div
    "f64x2.min" => F64x2Min
    "f64x2.max" => F64x2Max
    "f64x2.pmin" => F64x2Pmin
    "f64x2.pmax" => F64x2Pmax
    "f64x2.ceil" => F64x2Ceil
    "f64x2.floor" => F64x2Floor
    "f64x2.trunc" => F64x2Trunc
    "f64x2.nearest" => F64x2Nearest
    "f64x2.convert_low_i32x4_s" => F64x2ConvertLowI32x4S
    "f64x2.convert_low_i32x4_u" => F64x2ConvertLowI32x4U
    "f64x2.promote_low_f32x4" => F64x2PromoteLowF32x4
    "f64x2.relaxed_madd" => F64x2RelaxedMadd
    "f64x2.relaxed_nmadd" => F64x2RelaxedNmadd
    "f64x2.relaxed_min" => F64x2RelaxedMin
    "f64x2.relaxed_max" => F64x2RelaxedMax
    _ => self.parse_atomic_instruction(kw)
  }
}
