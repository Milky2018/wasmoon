///|
/// Validate SIMD (V128) instructions
fn validate_instr_simd(
  ctx : ValidationContext,
  stack : OperandStack,
  instr : @types.Instruction,
) -> Unit raise ValidationError {
  match instr {
    // SIMD instructions
    V128Const(_) => stack.push(V128)

    // SIMD load/store - natural alignments:
    // v128.load: 16 bytes = 4, load8x8/16x4/32x2: 8 bytes = 3
    // load8_splat: 0, load16_splat: 1, load32_splat/zero: 2, load64_splat/zero: 3
    V128Load(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 4 {
        raise InvalidAlignment(
          "v128.load alignment \{align} exceeds natural alignment 4",
        )
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(mem.addr_type())
      stack.push(V128)
    }
    V128Load8x8S(memidx, align, offset)
    | V128Load8x8U(memidx, align, offset)
    | V128Load16x4S(memidx, align, offset)
    | V128Load16x4U(memidx, align, offset)
    | V128Load32x2S(memidx, align, offset)
    | V128Load32x2U(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 3 {
        raise InvalidAlignment(
          "v128.load_extend alignment \{align} exceeds natural alignment 3",
        )
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(mem.addr_type())
      stack.push(V128)
    }
    V128Load8Splat(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 0 {
        raise InvalidAlignment(
          "v128.load8_splat alignment \{align} exceeds natural alignment 0",
        )
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(mem.addr_type())
      stack.push(V128)
    }
    V128Load16Splat(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 1 {
        raise InvalidAlignment(
          "v128.load16_splat alignment \{align} exceeds natural alignment 1",
        )
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(mem.addr_type())
      stack.push(V128)
    }
    V128Load32Splat(memidx, align, offset)
    | V128Load32Zero(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 2 {
        raise InvalidAlignment(
          "v128.load32 alignment \{align} exceeds natural alignment 2",
        )
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(mem.addr_type())
      stack.push(V128)
    }
    V128Load64Splat(memidx, align, offset)
    | V128Load64Zero(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 3 {
        raise InvalidAlignment(
          "v128.load64 alignment \{align} exceeds natural alignment 3",
        )
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(mem.addr_type())
      stack.push(V128)
    }
    V128Store(memidx, align, offset) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 4 {
        raise InvalidAlignment(
          "v128.store alignment \{align} exceeds natural alignment 4",
        )
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(V128)
      stack.pop(mem.addr_type())
    }
    V128Load8Lane(memidx, align, offset, lane) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 0 {
        raise InvalidAlignment(
          "v128.load8_lane alignment \{align} exceeds natural alignment 0",
        )
      }
      if lane >= 16 {
        raise InvalidLaneIndex(lane, 16)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(V128)
      stack.pop(mem.addr_type())
      stack.push(V128)
    }
    V128Load16Lane(memidx, align, offset, lane) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 1 {
        raise InvalidAlignment(
          "v128.load16_lane alignment \{align} exceeds natural alignment 1",
        )
      }
      if lane >= 8 {
        raise InvalidLaneIndex(lane, 8)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(V128)
      stack.pop(mem.addr_type())
      stack.push(V128)
    }
    V128Load32Lane(memidx, align, offset, lane) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 2 {
        raise InvalidAlignment(
          "v128.load32_lane alignment \{align} exceeds natural alignment 2",
        )
      }
      if lane >= 4 {
        raise InvalidLaneIndex(lane, 4)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(V128)
      stack.pop(mem.addr_type())
      stack.push(V128)
    }
    V128Load64Lane(memidx, align, offset, lane) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 3 {
        raise InvalidAlignment(
          "v128.load64_lane alignment \{align} exceeds natural alignment 3",
        )
      }
      if lane >= 2 {
        raise InvalidLaneIndex(lane, 2)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(V128)
      stack.pop(mem.addr_type())
      stack.push(V128)
    }
    V128Store8Lane(memidx, align, offset, lane) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 0 {
        raise InvalidAlignment(
          "v128.store8_lane alignment \{align} exceeds natural alignment 0",
        )
      }
      if lane >= 16 {
        raise InvalidLaneIndex(lane, 16)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(V128)
      stack.pop(mem.addr_type())
    }
    V128Store16Lane(memidx, align, offset, lane) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 1 {
        raise InvalidAlignment(
          "v128.store16_lane alignment \{align} exceeds natural alignment 1",
        )
      }
      if lane >= 8 {
        raise InvalidLaneIndex(lane, 8)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(V128)
      stack.pop(mem.addr_type())
    }
    V128Store32Lane(memidx, align, offset, lane) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 2 {
        raise InvalidAlignment(
          "v128.store32_lane alignment \{align} exceeds natural alignment 2",
        )
      }
      if lane >= 4 {
        raise InvalidLaneIndex(lane, 4)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(V128)
      stack.pop(mem.addr_type())
    }
    V128Store64Lane(memidx, align, offset, lane) => {
      if memidx >= ctx.mems.length() {
        raise InvalidMemoryIndex(memidx)
      }
      if align > 3 {
        raise InvalidAlignment(
          "v128.store64_lane alignment \{align} exceeds natural alignment 3",
        )
      }
      if lane >= 2 {
        raise InvalidLaneIndex(lane, 2)
      }
      validate_mem_offset(ctx.mems[memidx], offset)
      let mem = ctx.mems[memidx]
      stack.pop(V128)
      stack.pop(mem.addr_type())
    }

    // Shuffle/Swizzle - lane indices must be 0-31 (selecting from two concatenated v128s)
    I8x16Shuffle(lanes) => {
      for i = 0; i < 16; i = i + 1 {
        if lanes[i] >= 32 {
          raise InvalidLaneIndex(lanes[i], 32)
        }
      }
      stack.pop(V128)
      stack.pop(V128)
      stack.push(V128)
    }
    I8x16Swizzle => {
      stack.pop(V128)
      stack.pop(V128)
      stack.push(V128)
    }

    // Splat (scalar -> vector)
    I8x16Splat | I16x8Splat | I32x4Splat => {
      stack.pop(I32)
      stack.push(V128)
    }
    I64x2Splat => {
      stack.pop(I64)
      stack.push(V128)
    }
    F32x4Splat => {
      stack.pop(F32)
      stack.push(V128)
    }
    F64x2Splat => {
      stack.pop(F64)
      stack.push(V128)
    }

    // Extract lane (vector -> scalar) with lane validation
    I8x16ExtractLaneS(lane) | I8x16ExtractLaneU(lane) => {
      if lane >= 16 {
        raise InvalidLaneIndex(lane, 16)
      }
      stack.pop(V128)
      stack.push(I32)
    }
    I16x8ExtractLaneS(lane) | I16x8ExtractLaneU(lane) => {
      if lane >= 8 {
        raise InvalidLaneIndex(lane, 8)
      }
      stack.pop(V128)
      stack.push(I32)
    }
    I32x4ExtractLane(lane) => {
      if lane >= 4 {
        raise InvalidLaneIndex(lane, 4)
      }
      stack.pop(V128)
      stack.push(I32)
    }
    I64x2ExtractLane(lane) => {
      if lane >= 2 {
        raise InvalidLaneIndex(lane, 2)
      }
      stack.pop(V128)
      stack.push(I64)
    }
    F32x4ExtractLane(lane) => {
      if lane >= 4 {
        raise InvalidLaneIndex(lane, 4)
      }
      stack.pop(V128)
      stack.push(F32)
    }
    F64x2ExtractLane(lane) => {
      if lane >= 2 {
        raise InvalidLaneIndex(lane, 2)
      }
      stack.pop(V128)
      stack.push(F64)
    }

    // Replace lane (vector, scalar -> vector) with lane validation
    I8x16ReplaceLane(lane) => {
      if lane >= 16 {
        raise InvalidLaneIndex(lane, 16)
      }
      stack.pop(I32)
      stack.pop(V128)
      stack.push(V128)
    }
    I16x8ReplaceLane(lane) => {
      if lane >= 8 {
        raise InvalidLaneIndex(lane, 8)
      }
      stack.pop(I32)
      stack.pop(V128)
      stack.push(V128)
    }
    I32x4ReplaceLane(lane) => {
      if lane >= 4 {
        raise InvalidLaneIndex(lane, 4)
      }
      stack.pop(I32)
      stack.pop(V128)
      stack.push(V128)
    }
    I64x2ReplaceLane(lane) => {
      if lane >= 2 {
        raise InvalidLaneIndex(lane, 2)
      }
      stack.pop(I64)
      stack.pop(V128)
      stack.push(V128)
    }
    F32x4ReplaceLane(lane) => {
      if lane >= 4 {
        raise InvalidLaneIndex(lane, 4)
      }
      stack.pop(F32)
      stack.pop(V128)
      stack.push(V128)
    }
    F64x2ReplaceLane(lane) => {
      if lane >= 2 {
        raise InvalidLaneIndex(lane, 2)
      }
      stack.pop(F64)
      stack.pop(V128)
      stack.push(V128)
    }

    // Comparison operations: v128 v128 -> v128
    I8x16Eq
    | I8x16Ne
    | I8x16LtS
    | I8x16LtU
    | I8x16GtS
    | I8x16GtU
    | I8x16LeS
    | I8x16LeU
    | I8x16GeS
    | I8x16GeU
    | I16x8Eq
    | I16x8Ne
    | I16x8LtS
    | I16x8LtU
    | I16x8GtS
    | I16x8GtU
    | I16x8LeS
    | I16x8LeU
    | I16x8GeS
    | I16x8GeU
    | I32x4Eq
    | I32x4Ne
    | I32x4LtS
    | I32x4LtU
    | I32x4GtS
    | I32x4GtU
    | I32x4LeS
    | I32x4LeU
    | I32x4GeS
    | I32x4GeU
    | I64x2Eq
    | I64x2Ne
    | I64x2LtS
    | I64x2GtS
    | I64x2LeS
    | I64x2GeS
    | F32x4Eq
    | F32x4Ne
    | F32x4Lt
    | F32x4Gt
    | F32x4Le
    | F32x4Ge
    | F64x2Eq
    | F64x2Ne
    | F64x2Lt
    | F64x2Gt
    | F64x2Le
    | F64x2Ge => {
      stack.pop(V128)
      stack.pop(V128)
      stack.push(V128)
    }

    // Unary v128 -> v128
    V128Not
    | I8x16Abs
    | I8x16Neg
    | I8x16Popcnt
    | I16x8Abs
    | I16x8Neg
    | I16x8ExtAddPairwiseI8x16S
    | I16x8ExtAddPairwiseI8x16U
    | I32x4Abs
    | I32x4Neg
    | I32x4ExtAddPairwiseI16x8S
    | I32x4ExtAddPairwiseI16x8U
    | I64x2Abs
    | I64x2Neg
    | F32x4Abs
    | F32x4Neg
    | F32x4Sqrt
    | F32x4Ceil
    | F32x4Floor
    | F32x4Trunc
    | F32x4Nearest
    | F64x2Abs
    | F64x2Neg
    | F64x2Sqrt
    | F64x2Ceil
    | F64x2Floor
    | F64x2Trunc
    | F64x2Nearest
    | I16x8ExtendLowI8x16S
    | I16x8ExtendHighI8x16S
    | I16x8ExtendLowI8x16U
    | I16x8ExtendHighI8x16U
    | I32x4ExtendLowI16x8S
    | I32x4ExtendHighI16x8S
    | I32x4ExtendLowI16x8U
    | I32x4ExtendHighI16x8U
    | I64x2ExtendLowI32x4S
    | I64x2ExtendHighI32x4S
    | I64x2ExtendLowI32x4U
    | I64x2ExtendHighI32x4U
    | I32x4TruncSatF32x4S
    | I32x4TruncSatF32x4U
    | F32x4ConvertI32x4S
    | F32x4ConvertI32x4U
    | I32x4TruncSatF64x2SZero
    | I32x4TruncSatF64x2UZero
    | F64x2ConvertLowI32x4S
    | F64x2ConvertLowI32x4U
    | F32x4DemoteF64x2Zero
    | F64x2PromoteLowF32x4
    // Relaxed SIMD: v128 -> v128
    | I32x4RelaxedTruncF32x4S
    | I32x4RelaxedTruncF32x4U
    | I32x4RelaxedTruncF64x2SZero
    | I32x4RelaxedTruncF64x2UZero => {
      stack.pop(V128)
      stack.push(V128)
    }

    // v128 -> i32 (boolean/bitmask)
    V128AnyTrue
    | I8x16AllTrue
    | I8x16Bitmask
    | I16x8AllTrue
    | I16x8Bitmask
    | I32x4AllTrue
    | I32x4Bitmask
    | I64x2AllTrue
    | I64x2Bitmask => {
      stack.pop(V128)
      stack.push(I32)
    }

    // Binary v128 v128 -> v128
    V128And
    | V128AndNot
    | V128Or
    | V128Xor
    | I8x16Add
    | I8x16AddSatS
    | I8x16AddSatU
    | I8x16Sub
    | I8x16SubSatS
    | I8x16SubSatU
    | I8x16MinS
    | I8x16MinU
    | I8x16MaxS
    | I8x16MaxU
    | I8x16AvgrU
    | I8x16NarrowI16x8S
    | I8x16NarrowI16x8U
    | I16x8Add
    | I16x8AddSatS
    | I16x8AddSatU
    | I16x8Sub
    | I16x8SubSatS
    | I16x8SubSatU
    | I16x8Mul
    | I16x8MinS
    | I16x8MinU
    | I16x8MaxS
    | I16x8MaxU
    | I16x8AvgrU
    | I16x8Q15MulrSatS
    | I16x8NarrowI32x4S
    | I16x8NarrowI32x4U
    | I16x8ExtMulLowI8x16S
    | I16x8ExtMulHighI8x16S
    | I16x8ExtMulLowI8x16U
    | I16x8ExtMulHighI8x16U
    | I32x4Add
    | I32x4Sub
    | I32x4Mul
    | I32x4MinS
    | I32x4MinU
    | I32x4MaxS
    | I32x4MaxU
    | I32x4DotI16x8S
    | I32x4ExtMulLowI16x8S
    | I32x4ExtMulHighI16x8S
    | I32x4ExtMulLowI16x8U
    | I32x4ExtMulHighI16x8U
    | I64x2Add
    | I64x2Sub
    | I64x2Mul
    | I64x2ExtMulLowI32x4S
    | I64x2ExtMulHighI32x4S
    | I64x2ExtMulLowI32x4U
    | I64x2ExtMulHighI32x4U
    | F32x4Add
    | F32x4Sub
    | F32x4Mul
    | F32x4Div
    | F32x4Min
    | F32x4Max
    | F32x4Pmin
    | F32x4Pmax
    | F64x2Add
    | F64x2Sub
    | F64x2Mul
    | F64x2Div
    | F64x2Min
    | F64x2Max
    | F64x2Pmin
    | F64x2Pmax
    // Relaxed SIMD: v128 v128 -> v128
    | I8x16RelaxedSwizzle
    | F32x4RelaxedMin
    | F32x4RelaxedMax
    | F64x2RelaxedMin
    | F64x2RelaxedMax
    | I16x8RelaxedQ15mulrS
    | I16x8RelaxedDotI8x16I7x16S => {
      stack.pop(V128)
      stack.pop(V128)
      stack.push(V128)
    }

    // Shift operations: v128 i32 -> v128
    I8x16Shl
    | I8x16ShrS
    | I8x16ShrU
    | I16x8Shl
    | I16x8ShrS
    | I16x8ShrU
    | I32x4Shl
    | I32x4ShrS
    | I32x4ShrU
    | I64x2Shl
    | I64x2ShrS
    | I64x2ShrU => {
      stack.pop(I32)
      stack.pop(V128)
      stack.push(V128)
    }

    // Bitselect: v128 v128 v128 -> v128
    V128Bitselect
    // Relaxed SIMD: v128 v128 v128 -> v128
    | F32x4RelaxedMadd
    | F32x4RelaxedNmadd
    | F64x2RelaxedMadd
    | F64x2RelaxedNmadd
    | I8x16RelaxedLaneselect
    | I16x8RelaxedLaneselect
    | I32x4RelaxedLaneselect
    | I64x2RelaxedLaneselect
    | I32x4RelaxedDotI8x16I7x16AddS => {
      stack.pop(V128)
      stack.pop(V128)
      stack.pop(V128)
      stack.push(V128)
    }
    _ => abort("non-SIMD instruction routed to SIMD validator: \{instr}")
  }
}
