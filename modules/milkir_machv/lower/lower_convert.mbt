///|
/// Lower extend operation (sign or zero extend)
fn lower_extend(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  signed~ : Bool,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    // Determine the extend kind based on source and destination types
    let src_ty = inst.operands[0].ty
    let dst_ty = result.ty
    let kind = get_extend_kind(src_ty, dst_ty, signed)
    let machv_inst = @instr.Inst(Extend(kind))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(src))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower in-place sign extension (Sextend8, Sextend16, Sextend32)
/// These operations sign-extend the low N bits to fill the full register
fn lower_sextend_inplace(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  from_bits~ : Int,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let dst_ty = result.ty
    let is_i64 = dst_ty is I64
    // Determine extend kind based on source bits and destination type
    let kind : @instr.ExtendKind = match (from_bits, is_i64) {
      (8, false) => Signed8To32
      (8, true) => Signed8To64
      (16, false) => Signed16To32
      (16, true) => Signed16To64
      (32, _) => Signed32To64 // 32-bit extend is always to 64-bit
      _ => Signed8To32 // fallback
    }
    let machv_inst = @instr.Inst(Extend(kind))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(src))
    block.add_inst(machv_inst)
  }
}

///|
/// Determine the extend kind based on source and destination types
fn get_extend_kind(
  src_ty : @milkir.Type,
  dst_ty : @milkir.Type,
  signed : Bool,
) -> @instr.ExtendKind {
  match (src_ty, dst_ty, signed) {
    (I32, I64, true) => Signed32To64
    (I32, I64, false) => Unsigned32To64
    // Default to 32->64 extend
    _ => if signed { Signed32To64 } else { Unsigned32To64 }
  }
}

///|
/// Lower truncate operation
fn lower_truncate(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let machv_inst = @instr.Inst(Truncate)
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(src))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower float to int conversion (trapping version)
/// Standard lowering: expand to multiple primitive instructions
///
/// Generated sequence:
/// 1. FpuCmp(src, src) - compare with self to check for NaN
/// 2. TrapIf(Vs, 3) - trap if NaN (V flag set for unordered)
/// 3. tmp_min = LoadConstF32/F64(min_bound)
/// 4. FpuCmp(src, tmp_min) - compare with minimum
/// 5. TrapIf(Le/Lt, 3) - trap if underflow
/// 6. tmp_max = LoadConstF32/F64(max_bound)
/// 7. FpuCmp(src, tmp_max) - compare with maximum
/// 8. TrapIf(Ge, 3) - trap if overflow
/// 9. dst = FcvtToInt(src) - raw conversion
fn lower_float_to_int(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  signed~ : Bool,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let src = ctx.get_vreg_for_use(inst.operands[0], block)
  let src_ty = inst.operands[0].ty
  let dst_ty = result.ty
  let is_f32 = src_ty is F32
  let is_i64 = dst_ty is I64
  let float_class : @abi.RegClass = if is_f32 { Float32 } else { Float64 }

  // Step 1: NaN check - FpuCmp(src, src)
  // NaN != NaN sets V flag (unordered)
  let nan_check = @instr.Inst(FpuCmp(is_f32))
  nan_check.add_use(Virtual(src))
  nan_check.add_use(Virtual(src))
  block.add_inst(nan_check)

  // Step 2: TrapIf(Vs) - trap if NaN
  let trap_nan_cond = ctx.isa.unordered_float_condition()
  let trap_nan = @instr.Inst(TrapIf(trap_nan_cond, 3))
  block.add_inst(trap_nan)

  // Get bounds based on conversion type
  let (min_bits, max_bits, use_le_for_min) = get_float_to_int_bounds(
    is_f32, is_i64, signed,
  )

  // Step 3: Load minimum bound
  let tmp_min = ctx.machv_func.new_vreg(float_class)
  let load_min = if is_f32 {
    @instr.Inst(LoadConstF32(min_bits.to_int()))
  } else {
    Inst(LoadConstF64(min_bits))
  }
  load_min.add_def({ reg: Virtual(tmp_min) })
  block.add_inst(load_min)

  // Step 4: FpuCmp(src, tmp_min)
  let cmp_min = @instr.Inst(FpuCmp(is_f32))
  cmp_min.add_use(Virtual(src))
  cmp_min.add_use(Virtual(tmp_min))
  block.add_inst(cmp_min)

  // Step 5: TrapIf for underflow
  // For signed: trap if src < min (Lt)
  // For unsigned: trap if src <= -1.0 (Le)
  let trap_min_cond = if ctx.isa is AMD64 {
    // After x86 UCOMIS* (src, min), use CF/ZF based conditions.
    if use_le_for_min {
      @instr.Cond::Ls
    } else {
      Lo
    }
  } else if use_le_for_min {
    Le
  } else {
    Lt
  }
  let trap_min = @instr.Inst(TrapIf(trap_min_cond, 3))
  block.add_inst(trap_min)

  // Step 6: Load maximum bound
  let tmp_max = ctx.machv_func.new_vreg(float_class)
  let load_max = if is_f32 {
    @instr.Inst(LoadConstF32(max_bits.to_int()))
  } else {
    Inst(LoadConstF64(max_bits))
  }
  load_max.add_def({ reg: Virtual(tmp_max) })
  block.add_inst(load_max)

  // Step 7: FpuCmp(src, tmp_max)
  let cmp_max = @instr.Inst(FpuCmp(is_f32))
  cmp_max.add_use(Virtual(src))
  cmp_max.add_use(Virtual(tmp_max))
  block.add_inst(cmp_max)

  // Step 8: TrapIf(Ge) for overflow - trap if src >= max
  let trap_max_cond = if ctx.isa is AMD64 {
    // After x86 UCOMIS* (src, max), src >= max iff CF=0.
    @instr.Cond::Hs
  } else {
    Ge
  }
  let trap_max = @instr.Inst(TrapIf(trap_max_cond, 3))
  block.add_inst(trap_max)

  // Step 9: FcvtToInt - raw conversion (no checks)
  let fcvt = @instr.Inst(FcvtToInt(is_f32, is_i64, signed))
  fcvt.add_def({ reg: Virtual(dst) })
  fcvt.add_use(Virtual(src))
  block.add_inst(fcvt)
}

///|
/// Get bounds for float-to-int conversion
/// Returns (min_bits, max_bits, use_le_for_min)
/// - min_bits: bit representation of minimum bound
/// - max_bits: bit representation of maximum bound
/// - use_le_for_min: true if should use Le (<=) for underflow check, false for Lt (<)
fn get_float_to_int_bounds(
  is_f32 : Bool,
  is_i64 : Bool,
  signed : Bool,
) -> (Int64, Int64, Bool) {
  match (is_f32, is_i64, signed) {
    // F32 conversions
    (true, false, true) =>
      // F32ToI32S: min = -2^31 = 0xCF000000, max = 2^31 = 0x4F000000
      (0xCF000000L, 0x4F000000L, false)
    (true, false, false) =>
      // F32ToI32U: min = -1.0 = 0xBF800000 (trap if <= -1), max = 2^32 = 0x4F800000
      (0xBF800000L, 0x4F800000L, true)
    (true, true, true) =>
      // F32ToI64S: min = -2^63 = 0xDF000000, max = 2^63 = 0x5F000000
      (0xDF000000L, 0x5F000000L, false)
    (true, true, false) =>
      // F32ToI64U: min = -1.0 = 0xBF800000 (trap if <= -1), max = 2^64 = 0x5F800000
      (0xBF800000L, 0x5F800000L, true)
    // F64 conversions
    (false, false, true) =>
      // F64ToI32S: min = -2^31-1 = 0xC1E0000000200000, max = 2^31 = 0x41E0000000000000
      (0xC1E0000000200000L, 0x41E0000000000000L, true)
    (false, false, false) =>
      // F64ToI32U: min = -1.0 = 0xBFF0000000000000 (trap if <= -1), max = 2^32 = 0x41F0000000000000
      (0xBFF0000000000000L, 0x41F0000000000000L, true)
    (false, true, true) =>
      // F64ToI64S: min = -2^63 = 0xC3E0000000000000, max = 2^63 = 0x43E0000000000000
      (0xC3E0000000000000L, 0x43E0000000000000L, false)
    (false, true, false) =>
      // F64ToI64U: min = -1.0 = 0xBFF0000000000000 (trap if <= -1), max = 2^64 = 0x43F0000000000000
      (0xBFF0000000000000L, 0x43F0000000000000L, true)
  }
}

///|
/// Lower saturating float to int conversion
/// AArch64 FCVTZS/FCVTZU already handles saturation correctly:
/// - NaN → 0
/// - Overflow → clamp to min/max
/// So we just emit a single FcvtToInt instruction.
fn lower_float_to_int_sat(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  signed~ : Bool,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let src = ctx.get_vreg_for_use(inst.operands[0], block)
  let src_ty = inst.operands[0].ty
  let dst_ty = result.ty
  let is_f32 = src_ty is F32
  let is_i64 = dst_ty is I64

  // AArch64 FCVTZS/FCVTZU already implements MilkIR saturating conversion semantics.
  let fcvt = @instr.Inst(FcvtToInt(is_f32, is_i64, signed))
  fcvt.add_def({ reg: Virtual(dst) })
  fcvt.add_use(Virtual(src))
  block.add_inst(fcvt)
}

///|
/// Lower int to float conversion
fn lower_int_to_float(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  signed~ : Bool,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    // Determine conversion kind based on source/dest types and signedness
    let src_ty = inst.operands[0].ty
    let dst_ty = result.ty
    let kind : @instr.IntToFloatKind = match (src_ty, dst_ty, signed) {
      (I32, F32, true) => I32SToF32
      (I32, F32, false) => I32UToF32
      (I64, F32, true) => I64SToF32
      (I64, F32, false) => I64UToF32
      (I32, F64, true) => I32SToF64
      (I32, F64, false) => I32UToF64
      (I64, F64, true) => I64SToF64
      (I64, F64, false) => I64UToF64
      _ => I64SToF64 // Default fallback
    }
    let machv_inst = @instr.Inst(IntToFloat(kind))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(src))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower copy instruction
fn lower_copy(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let machv_inst = @instr.Inst(Move)
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(src))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower select instruction (cond ? true_val : false_val)
/// Uses AArch64 CSEL instruction: if cond != 0, select true_val, else false_val
/// Optimizes to SelectCmp when condition comes from an Icmp instruction
fn lower_select(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let true_val = ctx.get_vreg_for_use(inst.operands[1], block)
    let false_val = ctx.get_vreg_for_use(inst.operands[2], block)
    let cond_ir = inst.operands[0]

    // Try to fuse with Icmp: Select(Icmp(cc, a, b), x, y) -> SelectCmp(cc, a, b, x, y)
    if match_icmp_value(ctx, cond_ir) is Some((lhs, rhs, cc)) {
      // Use SelectCmp to fuse the comparison with the select
      let lhs_vreg = ctx.get_vreg_for_use(lhs, block)
      let kind = ir_intcc_to_cmp_kind(cc)
      // Determine is_64 from comparison operand type
      let is_64 = is_64_bit_word_type(lhs.ty)
      let machv_inst = @instr.Inst(SelectCmp(kind, is_64))
      machv_inst.add_def({ reg: Virtual(dst) })
      machv_inst.add_use(Virtual(lhs_vreg))
      if ctx.isa is AArch64 && is_const_zero_value(ctx, rhs) {
        // Cranelift-style zero-compare fast path for fused cmp+select.
        machv_inst.add_use(Physical({ index: 31, class: Int }))
      } else {
        let rhs_vreg = ctx.get_vreg_for_use(rhs, block)
        machv_inst.add_use(Virtual(rhs_vreg))
      }
      machv_inst.add_use(Virtual(true_val))
      machv_inst.add_use(Virtual(false_val))
      block.add_inst(machv_inst)
    } else {
      // Fall back to regular Select
      let cond = ctx.get_vreg_for_use(cond_ir, block)
      let machv_inst = @instr.Inst(Select)
      machv_inst.add_def({ reg: Virtual(dst) })
      machv_inst.add_use(Virtual(cond))
      machv_inst.add_use(Virtual(true_val))
      machv_inst.add_use(Virtual(false_val))
      block.add_inst(machv_inst)
    }
  }
}
