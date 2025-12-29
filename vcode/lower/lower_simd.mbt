// SIMD IR to VCode Lowering
// Converts SIMD IR opcodes to AArch64 NEON VCode instructions

///|
/// Lower V128Const - load 128-bit constant
fn lower_v128_const(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  bytes : Bytes,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let vcode_inst = @instr.VCodeInst::new(LoadConstV128(bytes))
    vcode_inst.add_def({ reg: Virtual(dst) })
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower V128 splat operations (i8x16.splat, i16x8.splat, etc.)
fn lower_v128_splat(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  lane_size : @instr.LaneSize,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let vcode_inst = @instr.VCodeInst::new(SIMDSplat(lane_size))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower V128 splat from float (f32x4.splat, f64x2.splat)
fn lower_v128_splat_f(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  is_f32 : Bool,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let vcode_inst = @instr.VCodeInst::new(SIMDSplatF(is_f32))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower V128 extract lane (unsigned)
fn lower_v128_extract_u(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  lane_size : @instr.LaneSize,
  lane : Int,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let vcode_inst = @instr.VCodeInst::new(SIMDExtractU(lane_size, lane))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower V128 extract lane (signed)
fn lower_v128_extract_s(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  lane_size : @instr.LaneSize,
  lane : Int,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let vcode_inst = @instr.VCodeInst::new(SIMDExtractS(lane_size, lane))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower V128 extract lane to float
fn lower_v128_extract_f(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  is_f32 : Bool,
  lane : Int,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let vcode_inst = @instr.VCodeInst::new(SIMDExtractF(is_f32, lane))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower V128 replace lane from GPR
fn lower_v128_replace(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  lane_size : @instr.LaneSize,
  lane : Int,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let vec = ctx.get_vreg_for_use(inst.operands[0], block)
    let val = ctx.get_vreg_for_use(inst.operands[1], block)
    let vcode_inst = @instr.VCodeInst::new(SIMDInsert(lane_size, lane))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(vec))
    vcode_inst.add_use(Virtual(val))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower V128 replace lane from FPR
fn lower_v128_replace_f(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  is_f32 : Bool,
  lane : Int,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let vec = ctx.get_vreg_for_use(inst.operands[0], block)
    let val = ctx.get_vreg_for_use(inst.operands[1], block)
    let vcode_inst = @instr.VCodeInst::new(SIMDInsertF(is_f32, lane))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(vec))
    vcode_inst.add_use(Virtual(val))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower V128 shuffle
fn lower_v128_shuffle(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  lanes : FixedArray[Int],
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let v1 = ctx.get_vreg_for_use(inst.operands[0], block)
    let v2 = ctx.get_vreg_for_use(inst.operands[1], block)
    let vcode_inst = @instr.VCodeInst::new(SIMDShuffle(lanes))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(v1))
    vcode_inst.add_use(Virtual(v2))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower V128 swizzle
fn lower_v128_swizzle(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let values = ctx.get_vreg_for_use(inst.operands[0], block)
    let indices = ctx.get_vreg_for_use(inst.operands[1], block)
    let vcode_inst = @instr.VCodeInst::new(SIMDSwizzle)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(values))
    vcode_inst.add_use(Virtual(indices))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower V128 unary operation (e.g., not, abs, neg)
fn lower_v128_unary(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  opcode : @instr.VCodeOpcode,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let vcode_inst = @instr.VCodeInst::new(opcode)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower V128 binary operation (e.g., and, or, xor, add, sub)
fn lower_v128_binary(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  opcode : @instr.VCodeOpcode,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
    let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
    let vcode_inst = @instr.VCodeInst::new(opcode)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(lhs))
    vcode_inst.add_use(Virtual(rhs))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower V128 binary operation with swapped operands (for lt/le comparisons)
/// Used for implementing lt(a,b) as gt(b,a) and le(a,b) as ge(b,a)
fn lower_v128_binary_swap(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  opcode : @instr.VCodeOpcode,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
    let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
    let vcode_inst = @instr.VCodeInst::new(opcode)
    vcode_inst.add_def({ reg: Virtual(dst) })
    // Swap: use rhs first, then lhs
    vcode_inst.add_use(Virtual(rhs))
    vcode_inst.add_use(Virtual(lhs))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower V128 ternary operation (e.g., bitselect)
fn lower_v128_ternary(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  opcode : @instr.VCodeOpcode,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let a = ctx.get_vreg_for_use(inst.operands[0], block)
    let b = ctx.get_vreg_for_use(inst.operands[1], block)
    let c = ctx.get_vreg_for_use(inst.operands[2], block)
    let vcode_inst = @instr.VCodeInst::new(opcode)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(a))
    vcode_inst.add_use(Virtual(b))
    vcode_inst.add_use(Virtual(c))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower V128 shift operation (takes v128 and i32 shift amount)
fn lower_v128_shift(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  opcode : @instr.VCodeOpcode,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let vec = ctx.get_vreg_for_use(inst.operands[0], block)
    let shift = ctx.get_vreg_for_use(inst.operands[1], block)
    let vcode_inst = @instr.VCodeInst::new(opcode)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(vec))
    vcode_inst.add_use(Virtual(shift))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower V128 to i32 operation (any_true, all_true, bitmask)
fn lower_v128_to_i32(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  opcode : @instr.VCodeOpcode,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let vcode_inst = @instr.VCodeInst::new(opcode)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower V128 load
/// Note: offset is ignored as the effective address already includes it from emit_bounds_check
fn lower_v128_load(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  _offset : Int,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let base = ctx.get_vreg_for_use(inst.operands[0], block)
    // offset=0 since effective_addr already includes the offset
    let vcode_inst = @instr.VCodeInst::new(SIMDLoad(0))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(base))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower V128 store
/// Note: offset is ignored as the effective address already includes it from emit_bounds_check
fn lower_v128_store(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  _offset : Int,
) -> Unit {
  let base = ctx.get_vreg_for_use(inst.operands[0], block)
  let value = ctx.get_vreg_for_use(inst.operands[1], block)
  // offset=0 since effective_addr already includes the offset
  let vcode_inst = @instr.VCodeInst::new(SIMDStore(0))
  vcode_inst.add_use(Virtual(base))
  vcode_inst.add_use(Virtual(value))
  block.add_inst(vcode_inst)
}

///|
/// Lower V128 load splat
/// Note: offset is ignored as the effective address already includes it from emit_bounds_check
fn lower_v128_load_splat(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  lane_size : @instr.LaneSize,
  _offset : Int,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let base = ctx.get_vreg_for_use(inst.operands[0], block)
    // offset=0 since effective_addr already includes the offset
    let vcode_inst = @instr.VCodeInst::new(SIMDLoadSplat(lane_size, 0))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(base))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower V128 load extend (8x8, 16x4, 32x2)
/// Note: offset is ignored as the effective address already includes it from emit_bounds_check
fn lower_v128_load_extend(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  src_bits : Int,
  signed : Bool,
  _offset : Int,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let base = ctx.get_vreg_for_use(inst.operands[0], block)
    // offset=0 since effective_addr already includes the offset
    let vcode_inst = @instr.VCodeInst::new(SIMDLoadExtend(src_bits, signed, 0))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(base))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower V128 load zero (32 or 64 bits, zero extend to v128)
/// Note: offset is ignored as the effective address already includes it from emit_bounds_check
fn lower_v128_load_zero(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  is_64 : Bool,
  _offset : Int,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let base = ctx.get_vreg_for_use(inst.operands[0], block)
    // offset=0 since effective_addr already includes the offset
    let vcode_inst = @instr.VCodeInst::new(SIMDLoadZero(is_64, 0))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(base))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower V128 load lane
/// Note: offset is ignored as the effective address already includes it from emit_bounds_check
fn lower_v128_load_lane(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  lane_size : @instr.LaneSize,
  lane : Int,
  _offset : Int,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let base = ctx.get_vreg_for_use(inst.operands[0], block)
    let vec = ctx.get_vreg_for_use(inst.operands[1], block)
    // offset=0 since effective_addr already includes the offset
    let vcode_inst = @instr.VCodeInst::new(SIMDLoadLane(lane_size, lane, 0))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(base))
    vcode_inst.add_use(Virtual(vec))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower V128 store lane
/// Note: offset is ignored as the effective address already includes it from emit_bounds_check
fn lower_v128_store_lane(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  lane_size : @instr.LaneSize,
  lane : Int,
  _offset : Int,
) -> Unit {
  let base = ctx.get_vreg_for_use(inst.operands[0], block)
  let vec = ctx.get_vreg_for_use(inst.operands[1], block)
  // offset=0 since effective_addr already includes the offset
  let vcode_inst = @instr.VCodeInst::new(SIMDStoreLane(lane_size, lane, 0))
  vcode_inst.add_use(Virtual(base))
  vcode_inst.add_use(Virtual(vec))
  block.add_inst(vcode_inst)
}

///|
/// Lower V128 not-equal comparison (CMEQ + NOT)
fn lower_v128_cmp_ne(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  lane_size : @instr.LaneSize,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
    let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
    // First do CMEQ
    let tmp = ctx.new_vreg(Vector)
    let eq_inst = @instr.VCodeInst::new(SIMDCmp(lane_size, Eq))
    eq_inst.add_def({ reg: Virtual(tmp) })
    eq_inst.add_use(Virtual(lhs))
    eq_inst.add_use(Virtual(rhs))
    block.add_inst(eq_inst)
    // Then NOT to get NE
    let not_inst = @instr.VCodeInst::new(SIMDNot)
    not_inst.add_def({ reg: Virtual(dst) })
    not_inst.add_use(Virtual(tmp))
    block.add_inst(not_inst)
  }
}

///|
/// Lower V128 less-than comparison (swap operands, use GT)
fn lower_v128_cmp_lt(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  lane_size : @instr.LaneSize,
  signed : Bool,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
    let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
    // a < b is equivalent to b > a - swap operands
    let kind : @instr.SIMDCmpKind = if signed { GtS } else { GtU }
    let vcode_inst = @instr.VCodeInst::new(SIMDCmp(lane_size, kind))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rhs)) // swapped!
    vcode_inst.add_use(Virtual(lhs)) // swapped!
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower V128 less-or-equal comparison (swap operands, use GE)
fn lower_v128_cmp_le(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  lane_size : @instr.LaneSize,
  signed : Bool,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
    let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
    // a <= b is equivalent to b >= a - swap operands
    let kind : @instr.SIMDCmpKind = if signed { GeS } else { GeU }
    let vcode_inst = @instr.VCodeInst::new(SIMDCmp(lane_size, kind))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rhs)) // swapped!
    vcode_inst.add_use(Virtual(lhs)) // swapped!
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower V128 float not-equal comparison (FCMEQ + NOT)
fn lower_v128_fcmp_ne(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  is_f32 : Bool,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
    let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
    // First do FCMEQ
    let tmp = ctx.new_vreg(Vector)
    let eq_inst = @instr.VCodeInst::new(
      SIMDFCmp(is_f32, @instr.SIMDFCmpKind::Eq),
    )
    eq_inst.add_def({ reg: Virtual(tmp) })
    eq_inst.add_use(Virtual(lhs))
    eq_inst.add_use(Virtual(rhs))
    block.add_inst(eq_inst)
    // Then NOT to get NE
    let not_inst = @instr.VCodeInst::new(SIMDNot)
    not_inst.add_def({ reg: Virtual(dst) })
    not_inst.add_use(Virtual(tmp))
    block.add_inst(not_inst)
  }
}
