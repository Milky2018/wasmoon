// SIMD IR to MachV Lowering
// Converts SIMD IR opcodes to AArch64 NEON MachV instructions

///|
/// Lower V128Const - load 128-bit constant
fn lower_v128_const(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  bytes : Bytes,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let machv_inst = @instr.MachVInst::MachVInst(LoadConstV128(bytes))
    machv_inst.add_def({ reg: Virtual(dst) })
    block.add_inst(machv_inst)
  }
}

///|
/// Lower V128 splat operations (i8x16.splat, i16x8.splat, etc.)
fn lower_v128_splat(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  lane_size : @instr.LaneSize,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let machv_inst = @instr.MachVInst::MachVInst(SIMDSplat(lane_size))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(src))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower V128 splat from float (f32x4.splat, f64x2.splat)
fn lower_v128_splat_f(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  is_f32 : Bool,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let machv_inst = @instr.MachVInst::MachVInst(SIMDSplatF(is_f32))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(src))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower V128 extract lane (unsigned)
fn lower_v128_extract_u(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  lane_size : @instr.LaneSize,
  lane : Int,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let machv_inst = @instr.MachVInst::MachVInst(SIMDExtractU(lane_size, lane))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(src))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower V128 extract lane (signed)
fn lower_v128_extract_s(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  lane_size : @instr.LaneSize,
  lane : Int,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let machv_inst = @instr.MachVInst::MachVInst(SIMDExtractS(lane_size, lane))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(src))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower V128 extract lane to float
fn lower_v128_extract_f(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  is_f32 : Bool,
  lane : Int,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let machv_inst = @instr.MachVInst::MachVInst(SIMDExtractF(is_f32, lane))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(src))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower V128 replace lane from GPR
fn lower_v128_replace(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  lane_size : @instr.LaneSize,
  lane : Int,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let vec = ctx.get_vreg_for_use(inst.operands[0], block)
    let val = ctx.get_vreg_for_use(inst.operands[1], block)
    let machv_inst = @instr.MachVInst::MachVInst(SIMDInsert(lane_size, lane))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(vec))
    machv_inst.add_use(Virtual(val))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower V128 replace lane from FPR
fn lower_v128_replace_f(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  is_f32 : Bool,
  lane : Int,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let vec = ctx.get_vreg_for_use(inst.operands[0], block)
    let val = ctx.get_vreg_for_use(inst.operands[1], block)
    let machv_inst = @instr.MachVInst::MachVInst(SIMDInsertF(is_f32, lane))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(vec))
    machv_inst.add_use(Virtual(val))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower V128 shuffle
fn lower_v128_shuffle(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  lanes : FixedArray[Int],
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let v1 = ctx.get_vreg_for_use(inst.operands[0], block)
    let v2 = ctx.get_vreg_for_use(inst.operands[1], block)
    let machv_inst = @instr.MachVInst::MachVInst(SIMDShuffle(lanes))
    machv_inst.add_def({ reg: Virtual(dst) })
    // Add 2 temp vector defs for the expansion in the emitter.
    let temp1 = ctx.machv_func.new_vreg(Vector)
    let temp2 = ctx.machv_func.new_vreg(Vector)
    machv_inst.add_def({ reg: Virtual(temp1) })
    machv_inst.add_def({ reg: Virtual(temp2) })
    machv_inst.add_use(Virtual(v1))
    machv_inst.add_use(Virtual(v2))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower V128 swizzle
fn lower_v128_swizzle(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let values = ctx.get_vreg_for_use(inst.operands[0], block)
    let indices = ctx.get_vreg_for_use(inst.operands[1], block)
    let machv_inst = @instr.MachVInst::MachVInst(SIMDSwizzle)
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(values))
    machv_inst.add_use(Virtual(indices))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower V128 unary operation (e.g., not, abs, neg)
fn lower_v128_unary(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  opcode : @instr.MachVOpcode,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let machv_inst = @instr.MachVInst::MachVInst(opcode)
    machv_inst.add_def({ reg: Virtual(dst) })
    // Some opcode expansions in the emitter require an extra temporary vector
    // register. Model it as an extra def so regalloc accounts for it.
    if opcode is SIMDTruncSatF64ToI32SZero ||
      opcode is SIMDTruncSatF64ToI32UZero ||
      opcode is SIMDConvertLowI32ToF64S ||
      opcode is SIMDConvertLowI32ToF64U {
      let tmp = ctx.machv_func.new_vreg(Vector)
      machv_inst.add_def({ reg: Virtual(tmp) })
    }
    machv_inst.add_use(Virtual(src))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower V128 binary operation (e.g., and, or, xor, add, sub)
fn lower_v128_binary(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  opcode : @instr.MachVOpcode,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
    let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
    let machv_inst = @instr.MachVInst::MachVInst(opcode)
    machv_inst.add_def({ reg: Virtual(dst) })
    match opcode {
      SIMDMul(D64) => {
        let t0 = ctx.machv_func.new_vreg(Vector)
        let t1 = ctx.machv_func.new_vreg(Vector)
        let t2 = ctx.machv_func.new_vreg(Vector)
        let t3 = ctx.machv_func.new_vreg(Vector)
        let t4 = ctx.machv_func.new_vreg(Vector)
        machv_inst.add_def({ reg: Virtual(t0) })
        machv_inst.add_def({ reg: Virtual(t1) })
        machv_inst.add_def({ reg: Virtual(t2) })
        machv_inst.add_def({ reg: Virtual(t3) })
        machv_inst.add_def({ reg: Virtual(t4) })
      }
      SIMDRelaxedDot8to16 => {
        // Expanded into multiple AArch64 instructions in the emitter.
        // Provide a temp vector so regalloc accounts for it.
        let tmp = ctx.machv_func.new_vreg(Vector)
        machv_inst.add_def({ reg: Virtual(tmp) })
      }
      _ => ()
    }
    machv_inst.add_use(Virtual(lhs))
    machv_inst.add_use(Virtual(rhs))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower V128 binary operation with swapped operands (for lt/le comparisons)
/// Used for implementing lt(a,b) as gt(b,a) and le(a,b) as ge(b,a)
fn lower_v128_binary_swap(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  opcode : @instr.MachVOpcode,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
    let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
    let machv_inst = @instr.MachVInst::MachVInst(opcode)
    machv_inst.add_def({ reg: Virtual(dst) })
    // Swap: use rhs first, then lhs
    machv_inst.add_use(Virtual(rhs))
    machv_inst.add_use(Virtual(lhs))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower V128 ternary operation (e.g., bitselect)
fn lower_v128_ternary(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  opcode : @instr.MachVOpcode,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let a = ctx.get_vreg_for_use(inst.operands[0], block)
    let b = ctx.get_vreg_for_use(inst.operands[1], block)
    let c = ctx.get_vreg_for_use(inst.operands[2], block)
    let machv_inst = @instr.MachVInst::MachVInst(opcode)
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(a))
    machv_inst.add_use(Virtual(b))
    machv_inst.add_use(Virtual(c))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower V128 shift operation (takes v128 and i32 shift amount)
/// Allocates a temp FPR vreg for the shift broadcast vector.
/// Instruction layout:
/// Lower V128 shift operations using split instructions:
/// 1. SIMDBroadcastShift: mask scalar, optionally negate, broadcast to vector
/// 2. SIMDShiftByVec: vector shift using SSHL or USHL
///
/// This split approach allows regalloc to properly allocate all registers
/// without needing hardcoded scratch registers.
///
/// Parameters:
/// - lane_size: the SIMD lane size
/// - negate: true for right shifts (shift amount needs to be negated)
/// - use_ushl: true for unsigned right shift (USHL), false for SSHL
fn lower_v128_shift(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  lane_size : @instr.LaneSize,
  negate : Bool,
  use_ushl : Bool,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let vec = ctx.get_vreg_for_use(inst.operands[0], block)
    let shift = ctx.get_vreg_for_use(inst.operands[1], block)

    // Allocate temp registers for broadcast shift
    let temp_gpr = ctx.machv_func.new_vreg(Int) // GPR for masked shift
    let shift_vec = ctx.machv_func.new_vreg(Vector) // FPR for broadcast

    // Instruction 1: SIMDBroadcastShift
    // Uses: [shift_scalar], Defs: [temp_gpr, shift_vec]
    let broadcast_inst = @instr.MachVInst::MachVInst(
      SIMDBroadcastShift(lane_size, negate),
    )
    broadcast_inst.add_def({ reg: Virtual(temp_gpr) }) // defs[0] = temp GPR
    broadcast_inst.add_def({ reg: Virtual(shift_vec) }) // defs[1] = shift vector
    broadcast_inst.add_use(Virtual(shift)) // uses[0] = scalar shift amount
    block.add_inst(broadcast_inst)

    // Instruction 2: SIMDShiftByVec
    // Uses: [input_vec, shift_vec], Defs: [result]
    let shift_inst = @instr.MachVInst::MachVInst(
      SIMDShiftByVec(lane_size, use_ushl),
    )
    shift_inst.add_def({ reg: Virtual(dst) }) // defs[0] = result
    shift_inst.add_use(Virtual(vec)) // uses[0] = input vector
    shift_inst.add_use(Virtual(shift_vec)) // uses[1] = shift vector
    block.add_inst(shift_inst)
  }
}

///|
/// Lower V128 to i32 operation (any_true, all_true, bitmask)
/// For SIMDBitmask(B8), we need 3 temp FPR defs for intermediate calculations.
fn lower_v128_to_i32(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  opcode : @instr.MachVOpcode,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let machv_inst = @instr.MachVInst::MachVInst(opcode)
    machv_inst.add_def({ reg: Virtual(dst) })
    match opcode {
      // These expand to a reduction + move and need a temp vector for the scalar result.
      SIMDAnyTrue => {
        let tmp = ctx.machv_func.new_vreg(Vector)
        machv_inst.add_def({ reg: Virtual(tmp) })
      }
      SIMDAllTrue(lane_size) =>
        match lane_size {
          D64 => ()
          _ => {
            let tmp = ctx.machv_func.new_vreg(Vector)
            machv_inst.add_def({ reg: Virtual(tmp) })
          }
        }
      SIMDBitmask(B8) => {
        let temp_weights = ctx.machv_func.new_vreg(Vector)
        let temp_shift = ctx.machv_func.new_vreg(Vector)
        let temp_work = ctx.machv_func.new_vreg(Vector)
        machv_inst.add_def({ reg: Virtual(temp_weights) })
        machv_inst.add_def({ reg: Virtual(temp_shift) })
        machv_inst.add_def({ reg: Virtual(temp_work) })
      }
      _ => ()
    }
    machv_inst.add_use(Virtual(src))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower V128 load splat
/// Note: offset is ignored as the effective address already includes it from emit_bounds_check
fn lower_v128_load_splat(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  lane_size : @instr.LaneSize,
  _offset : Int,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let base = ctx.get_vreg_for_use(inst.operands[0], block)
    // offset=0 since effective_addr already includes the offset
    let machv_inst = @instr.MachVInst::MachVInst(SIMDLoadSplat(lane_size, 0))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(base))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower V128 load extend (8x8, 16x4, 32x2)
/// Note: offset is ignored as the effective address already includes it from emit_bounds_check
fn lower_v128_load_extend(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  src_bits : Int,
  signed : Bool,
  _offset : Int,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let base = ctx.get_vreg_for_use(inst.operands[0], block)
    // offset=0 since effective_addr already includes the offset
    let machv_inst = @instr.MachVInst::MachVInst(
      SIMDLoadExtend(src_bits, signed, 0),
    )
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(base))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower V128 load zero (32 or 64 bits, zero extend to v128)
/// Note: offset is ignored as the effective address already includes it from emit_bounds_check
fn lower_v128_load_zero(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  is_64 : Bool,
  _offset : Int,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let base = ctx.get_vreg_for_use(inst.operands[0], block)
    // offset=0 since effective_addr already includes the offset
    let machv_inst = @instr.MachVInst::MachVInst(SIMDLoadZero(is_64, 0))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(base))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower V128 load lane
/// Note: offset is ignored as the effective address already includes it from emit_bounds_check
fn lower_v128_load_lane(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  lane_size : @instr.LaneSize,
  lane : Int,
  _offset : Int,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let base = ctx.get_vreg_for_use(inst.operands[0], block)
    let vec = ctx.get_vreg_for_use(inst.operands[1], block)
    // offset=0 since effective_addr already includes the offset
    let machv_inst = @instr.MachVInst::MachVInst(
      SIMDLoadLane(lane_size, lane, 0),
    )
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(base))
    machv_inst.add_use(Virtual(vec))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower V128 store lane
/// Note: offset is ignored as the effective address already includes it from emit_bounds_check
fn lower_v128_store_lane(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  lane_size : @instr.LaneSize,
  lane : Int,
  _offset : Int,
) -> Unit {
  let base = ctx.get_vreg_for_use(inst.operands[0], block)
  let vec = ctx.get_vreg_for_use(inst.operands[1], block)
  // offset=0 since effective_addr already includes the offset
  let machv_inst = @instr.MachVInst::MachVInst(
    SIMDStoreLane(lane_size, lane, 0),
  )
  machv_inst.add_use(Virtual(base))
  machv_inst.add_use(Virtual(vec))
  block.add_inst(machv_inst)
}

///|
/// Lower V128 not-equal comparison (CMEQ + NOT)
fn lower_v128_cmp_ne(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  lane_size : @instr.LaneSize,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
    let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
    // First do CMEQ
    let tmp = ctx.new_vreg(Vector)
    let eq_inst = @instr.MachVInst::MachVInst(SIMDCmp(lane_size, Eq))
    eq_inst.add_def({ reg: Virtual(tmp) })
    eq_inst.add_use(Virtual(lhs))
    eq_inst.add_use(Virtual(rhs))
    block.add_inst(eq_inst)
    // Then NOT to get NE
    let not_inst = @instr.MachVInst::MachVInst(SIMDNot)
    not_inst.add_def({ reg: Virtual(dst) })
    not_inst.add_use(Virtual(tmp))
    block.add_inst(not_inst)
  }
}

///|
/// Lower V128 less-than comparison (swap operands, use GT)
fn lower_v128_cmp_lt(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  lane_size : @instr.LaneSize,
  signed : Bool,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
    let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
    // a < b is equivalent to b > a - swap operands
    let kind : @instr.SIMDCmpKind = if signed { GtS } else { GtU }
    let machv_inst = @instr.MachVInst::MachVInst(SIMDCmp(lane_size, kind))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rhs)) // swapped!
    machv_inst.add_use(Virtual(lhs)) // swapped!
    block.add_inst(machv_inst)
  }
}

///|
/// Lower V128 less-or-equal comparison (swap operands, use GE)
fn lower_v128_cmp_le(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  lane_size : @instr.LaneSize,
  signed : Bool,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
    let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
    // a <= b is equivalent to b >= a - swap operands
    let kind : @instr.SIMDCmpKind = if signed { GeS } else { GeU }
    let machv_inst = @instr.MachVInst::MachVInst(SIMDCmp(lane_size, kind))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rhs)) // swapped!
    machv_inst.add_use(Virtual(lhs)) // swapped!
    block.add_inst(machv_inst)
  }
}

///|
/// Lower V128 float not-equal comparison (FCMEQ + NOT)
fn lower_v128_fcmp_ne(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  is_f32 : Bool,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
    let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
    // First do FCMEQ
    let tmp = ctx.new_vreg(Vector)
    let eq_inst = @instr.MachVInst::MachVInst(SIMDFCmp(is_f32, Eq))
    eq_inst.add_def({ reg: Virtual(tmp) })
    eq_inst.add_use(Virtual(lhs))
    eq_inst.add_use(Virtual(rhs))
    block.add_inst(eq_inst)
    // Then NOT to get NE
    let not_inst = @instr.MachVInst::MachVInst(SIMDNot)
    not_inst.add_def({ reg: Virtual(dst) })
    not_inst.add_use(Virtual(tmp))
    block.add_inst(not_inst)
  }
}

///|
/// Lower V128 fused multiply-add (relaxed_madd) or fused multiply-subtract (relaxed_nmadd)
/// MilkIR relaxed SIMD semantics:
///   relaxed_madd(a, b, c) = a * b + c
///   relaxed_nmadd(a, b, c) = -(a * b) + c = c - a * b
fn lower_v128_fma(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
  is_f32 : Bool,
  is_sub : Bool,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    // relaxed_madd: (a, b, c) -> a * b + c
    // relaxed_nmadd: (a, b, c) -> -(a * b) + c = c - a * b
    // AArch64 FMLA: Vd = Vd + Vn * Vm (accumulator is first operand AND destination)
    // AArch64 FMLS: Vd = Vd - Vn * Vm
    // For madd: dst = a * b + c = c + a * b, use FMLA with Vd=c, Vn=a, Vm=b
    // For nmadd: dst = c - a * b, use FMLS with Vd=c, Vn=a, Vm=b
    let a = ctx.get_vreg_for_use(inst.operands[0], block)
    let b = ctx.get_vreg_for_use(inst.operands[1], block)
    let c = ctx.get_vreg_for_use(inst.operands[2], block)
    // Both madd and nmadd use: acc=c, v1=a, v2=b
    // madd: c + a * b = a * b + c
    // nmadd: c - a * b = -(a * b) + c
    let opcode = if is_sub { @instr.SIMDFMls(is_f32) } else { SIMDFMla(is_f32) }
    let machv_inst = @instr.MachVInst::MachVInst(opcode)
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(c)) // accumulator
    machv_inst.add_use(Virtual(a)) // multiplicand 1
    machv_inst.add_use(Virtual(b)) // multiplicand 2
    block.add_inst(machv_inst)
  }
}

///|
/// Lower V128 relaxed dot product with accumulator: result = c + dot(a, b)
fn lower_v128_relaxed_dot_add(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.MachVBlock,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let a = ctx.get_vreg_for_use(inst.operands[0], block)
    let b = ctx.get_vreg_for_use(inst.operands[1], block)
    let c = ctx.get_vreg_for_use(inst.operands[2], block)
    let machv_inst = @instr.MachVInst::MachVInst(SIMDRelaxedDot8to32Add)
    machv_inst.add_def({ reg: Virtual(dst) })
    let tmp = ctx.machv_func.new_vreg(Vector)
    machv_inst.add_def({ reg: Virtual(tmp) })
    machv_inst.add_use(Virtual(a))
    machv_inst.add_use(Virtual(b))
    machv_inst.add_use(Virtual(c))
    block.add_inst(machv_inst)
  }
}
