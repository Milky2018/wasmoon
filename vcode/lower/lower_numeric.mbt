///|
/// Lower integer constant
fn lower_iconst(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  val : Int64,
) -> Unit {
  if inst.result is Some(result) {
    let vreg = ctx.get_vreg(result)
    let vcode_inst = @instr.VCodeInst::new(LoadConst(val))
    vcode_inst.add_def({ reg: Virtual(vreg) })
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower float constant
fn lower_fconst(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  val : Double,
) -> Unit {
  if inst.result is Some(result) {
    let vreg = ctx.get_vreg(result)
    // Determine if this is an F32 or F64 constant based on the result type
    let opcode = match result.ty {
      @ir.Type::F32 => {
        // F32 bits are packed in the lower 32 bits of the Double's bit representation
        // (see IRBuilder::fconst_f32). Extract them directly to preserve NaN payloads.
        let bits = val.reinterpret_as_int64().to_int()
        @instr.LoadConstF32(bits)
      }
      _ => {
        // F64: get 64-bit representation
        let bits = val.reinterpret_as_int64()
        LoadConstF64(bits)
      }
    }
    let vcode_inst = @instr.VCodeInst::new(opcode)
    vcode_inst.add_def({ reg: Virtual(vreg) })
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower binary integer operation
fn lower_binary_int(
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
/// Lower division with proper 32/64-bit selection and trapping
fn lower_div(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  signed~ : Bool,
) -> Unit {
  let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
  let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
  let is_64 = inst.operands[0].ty is @ir.Type::I64

  // Trap if divisor is zero (trap_code 4 = integer divide by zero)
  // Must always emit even if result is unused (for side effect)
  let trap_zero = @instr.VCodeInst::new(TrapIfZero(is_64, 4))
  trap_zero.add_use(Virtual(rhs))
  block.add_inst(trap_zero)

  // For signed division, also trap if INT_MIN / -1 (would overflow)
  // Use trap_code 5 = integer overflow
  if signed {
    let trap_overflow = @instr.VCodeInst::new(TrapIfDivOverflow(is_64, 5))
    trap_overflow.add_use(Virtual(lhs))
    trap_overflow.add_use(Virtual(rhs))
    block.add_inst(trap_overflow)
  }

  // Only emit division if result is used
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let opcode : @instr.VCodeOpcode = if signed {
      @instr.VCodeOpcode::SDiv(is_64)
    } else {
      @instr.VCodeOpcode::UDiv(is_64)
    }
    let vcode_inst = @instr.VCodeInst::new(opcode)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(lhs))
    vcode_inst.add_use(Virtual(rhs))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower shift/rotate operations with proper 32/64-bit selection
fn lower_shift(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  make_opcode : (Bool) -> @instr.VCodeOpcode,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
    let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
    let is_64 = result.ty is @ir.Type::I64
    let vcode_inst = @instr.VCodeInst::new(make_opcode(is_64))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(lhs))
    vcode_inst.add_use(Virtual(rhs))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower bit counting operations (clz, popcnt) with proper 32/64-bit selection
fn lower_bitcount(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  make_opcode : (Bool) -> @instr.VCodeOpcode,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let is_64 = result.ty is @ir.Type::I64
    let vcode_inst = @instr.VCodeInst::new(make_opcode(is_64))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
  }
}

// ============ AArch64-Specific Lowering with Pattern Matching ============

///|
/// Lower integer add with pattern matching for MADD and shifted operands
/// Patterns:
/// - add(x, mul(y, z)) -> MADD: x + y * z
/// - add(mul(x, y), z) -> MADD: z + x * y (commutative)
/// - add(x, shl(y, n)) -> AddShifted: x + (y << n)
/// - add(shl(x, n), y) -> AddShifted: y + (x << n) (commutative)
fn lower_iadd(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]

  // Pattern: add(x, mul(y, z)) -> MADD
  if match_mul_value(ctx, rhs_val) is Some((mul_lhs, mul_rhs)) {
    let acc = ctx.get_vreg_for_use(lhs_val, block)
    let src1 = ctx.get_vreg_for_use(mul_lhs, block)
    let src2 = ctx.get_vreg_for_use(mul_rhs, block)
    let vcode_inst = @instr.VCodeInst::new(Madd)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(acc)) // accumulator
    vcode_inst.add_use(Virtual(src1)) // multiplicand
    vcode_inst.add_use(Virtual(src2)) // multiplier
    block.add_inst(vcode_inst)
    return
  }

  // Pattern: add(mul(x, y), z) -> MADD (commutative)
  if match_mul_value(ctx, lhs_val) is Some((mul_lhs, mul_rhs)) {
    let acc = ctx.get_vreg_for_use(rhs_val, block)
    let src1 = ctx.get_vreg_for_use(mul_lhs, block)
    let src2 = ctx.get_vreg_for_use(mul_rhs, block)
    let vcode_inst = @instr.VCodeInst::new(Madd)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(acc))
    vcode_inst.add_use(Virtual(src1))
    vcode_inst.add_use(Virtual(src2))
    block.add_inst(vcode_inst)
    return
  }

  // Pattern: add(x, shl(y, n)) -> AddShifted
  if match_shl_const_value(ctx, rhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(lhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let vcode_inst = @instr.VCodeInst::new(AddShifted(Lsl, amount))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rn))
    vcode_inst.add_use(Virtual(rm))
    block.add_inst(vcode_inst)
    return
  }

  // Pattern: add(shl(x, n), y) -> AddShifted (commutative)
  if match_shl_const_value(ctx, lhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(rhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let vcode_inst = @instr.VCodeInst::new(AddShifted(Lsl, amount))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rn))
    vcode_inst.add_use(Virtual(rm))
    block.add_inst(vcode_inst)
    return
  }

  // Default: regular add
  let lhs = ctx.get_vreg_for_use(lhs_val, block)
  let rhs = ctx.get_vreg_for_use(rhs_val, block)
  let is_64 = result.ty is @ir.Type::I64
  let vcode_inst = @instr.VCodeInst::new(Add(is_64))
  vcode_inst.add_def({ reg: Virtual(dst) })
  vcode_inst.add_use(Virtual(lhs))
  vcode_inst.add_use(Virtual(rhs))
  block.add_inst(vcode_inst)
}

///|
/// Lower integer multiply with proper 32/64-bit size
fn lower_imul(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
  let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
  let is_64 = result.ty is @ir.Type::I64
  let vcode_inst = @instr.VCodeInst::new(Mul(is_64))
  vcode_inst.add_def({ reg: Virtual(dst) })
  vcode_inst.add_use(Virtual(lhs))
  vcode_inst.add_use(Virtual(rhs))
  block.add_inst(vcode_inst)
}

///|
/// Lower integer sub with pattern matching for MSUB, MNEG, and shifted operands
/// Patterns:
/// - sub(x, mul(y, z)) -> MSUB: x - y * z
/// - sub(0, mul(x, y)) -> MNEG: -(x * y)
/// - sub(x, shl(y, n)) -> SubShifted: x - (y << n)
fn lower_isub(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]

  // Pattern: sub(0, mul(x, y)) -> MNEG
  if is_const_zero_value(ctx, lhs_val) &&
    match_mul_value(ctx, rhs_val) is Some((mul_lhs, mul_rhs)) {
    let src1 = ctx.get_vreg_for_use(mul_lhs, block)
    let src2 = ctx.get_vreg_for_use(mul_rhs, block)
    let vcode_inst = @instr.VCodeInst::new(Mneg)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src1))
    vcode_inst.add_use(Virtual(src2))
    block.add_inst(vcode_inst)
    return
  }

  // Pattern: sub(x, mul(y, z)) -> MSUB
  if match_mul_value(ctx, rhs_val) is Some((mul_lhs, mul_rhs)) {
    let acc = ctx.get_vreg_for_use(lhs_val, block)
    let src1 = ctx.get_vreg_for_use(mul_lhs, block)
    let src2 = ctx.get_vreg_for_use(mul_rhs, block)
    let vcode_inst = @instr.VCodeInst::new(Msub)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(acc))
    vcode_inst.add_use(Virtual(src1))
    vcode_inst.add_use(Virtual(src2))
    block.add_inst(vcode_inst)
    return
  }

  // Pattern: sub(x, shl(y, n)) -> SubShifted
  if match_shl_const_value(ctx, rhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(lhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let vcode_inst = @instr.VCodeInst::new(SubShifted(Lsl, amount))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rn))
    vcode_inst.add_use(Virtual(rm))
    block.add_inst(vcode_inst)
    return
  }

  // Default: regular sub
  let lhs = ctx.get_vreg_for_use(lhs_val, block)
  let rhs = ctx.get_vreg_for_use(rhs_val, block)
  let is_64 = result.ty is @ir.Type::I64
  let vcode_inst = @instr.VCodeInst::new(Sub(is_64))
  vcode_inst.add_def({ reg: Virtual(dst) })
  vcode_inst.add_use(Virtual(lhs))
  vcode_inst.add_use(Virtual(rhs))
  block.add_inst(vcode_inst)
}

///|
/// Lower bitwise AND with pattern matching for shifted operands
fn lower_band(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]

  // Pattern: and(x, shl(y, n)) -> AndShifted
  if match_shl_const_value(ctx, rhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(lhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let vcode_inst = @instr.VCodeInst::new(AndShifted(Lsl, amount))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rn))
    vcode_inst.add_use(Virtual(rm))
    block.add_inst(vcode_inst)
    return
  }

  // Pattern: and(shl(x, n), y) -> AndShifted (commutative)
  if match_shl_const_value(ctx, lhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(rhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let vcode_inst = @instr.VCodeInst::new(AndShifted(Lsl, amount))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rn))
    vcode_inst.add_use(Virtual(rm))
    block.add_inst(vcode_inst)
    return
  }

  // Default: regular and
  let lhs = ctx.get_vreg_for_use(lhs_val, block)
  let rhs = ctx.get_vreg_for_use(rhs_val, block)
  let vcode_inst = @instr.VCodeInst::new(And)
  vcode_inst.add_def({ reg: Virtual(dst) })
  vcode_inst.add_use(Virtual(lhs))
  vcode_inst.add_use(Virtual(rhs))
  block.add_inst(vcode_inst)
}

///|
/// Lower bitwise OR with pattern matching for shifted operands
fn lower_bor(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]

  // Pattern: or(x, shl(y, n)) -> OrShifted
  if match_shl_const_value(ctx, rhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(lhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let vcode_inst = @instr.VCodeInst::new(OrShifted(Lsl, amount))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rn))
    vcode_inst.add_use(Virtual(rm))
    block.add_inst(vcode_inst)
    return
  }

  // Pattern: or(shl(x, n), y) -> OrShifted (commutative)
  if match_shl_const_value(ctx, lhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(rhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let vcode_inst = @instr.VCodeInst::new(OrShifted(Lsl, amount))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rn))
    vcode_inst.add_use(Virtual(rm))
    block.add_inst(vcode_inst)
    return
  }

  // Default: regular or
  let lhs = ctx.get_vreg_for_use(lhs_val, block)
  let rhs = ctx.get_vreg_for_use(rhs_val, block)
  let vcode_inst = @instr.VCodeInst::new(Or)
  vcode_inst.add_def({ reg: Virtual(dst) })
  vcode_inst.add_use(Virtual(lhs))
  vcode_inst.add_use(Virtual(rhs))
  block.add_inst(vcode_inst)
}

///|
/// Lower bitwise XOR with pattern matching for shifted operands
fn lower_bxor(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]

  // Pattern: xor(x, shl(y, n)) -> XorShifted
  if match_shl_const_value(ctx, rhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(lhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let vcode_inst = @instr.VCodeInst::new(XorShifted(Lsl, amount))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rn))
    vcode_inst.add_use(Virtual(rm))
    block.add_inst(vcode_inst)
    return
  }

  // Pattern: xor(shl(x, n), y) -> XorShifted (commutative)
  if match_shl_const_value(ctx, lhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(rhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let vcode_inst = @instr.VCodeInst::new(XorShifted(Lsl, amount))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rn))
    vcode_inst.add_use(Virtual(rm))
    block.add_inst(vcode_inst)
    return
  }

  // Default: regular xor
  let lhs = ctx.get_vreg_for_use(lhs_val, block)
  let rhs = ctx.get_vreg_for_use(rhs_val, block)
  let vcode_inst = @instr.VCodeInst::new(Xor)
  vcode_inst.add_def({ reg: Virtual(dst) })
  vcode_inst.add_use(Virtual(lhs))
  vcode_inst.add_use(Virtual(rhs))
  block.add_inst(vcode_inst)
}

///|
/// Lower rotate left instruction
/// Standard lowering: expand to primitive instructions here
/// rotl(x, n) = rotr(x, 0 - n)
///
/// AArch64 ROR only looks at lower bits of shift amount, so negating
/// via two's complement effectively gives us (size - n) mod size.
///
/// Generated sequence:
/// 1. zero = LoadConst(0)
/// 2. neg_n = Sub(zero, n)
/// 3. result = Rotr(x, neg_n)
fn lower_rotl(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let src = ctx.get_vreg_for_use(inst.operands[0], block)
  let amount = ctx.get_vreg_for_use(inst.operands[1], block)
  let is_64 = result.ty is @ir.Type::I64

  // Step 1: Load constant 0 into temp
  let zero = ctx.vcode_func.new_vreg(Int)
  let load_zero = @instr.VCodeInst::new(LoadConst(0L))
  load_zero.add_def({ reg: Virtual(zero) })
  block.add_inst(load_zero)

  // Step 2: Compute (0 - n) = -n
  let neg_n = ctx.vcode_func.new_vreg(Int)
  let sub_inst = @instr.VCodeInst::new(Sub(is_64))
  sub_inst.add_def({ reg: Virtual(neg_n) })
  sub_inst.add_use(Virtual(zero))
  sub_inst.add_use(Virtual(amount))
  block.add_inst(sub_inst)

  // Step 3: Rotate right by -n (effectively rotl by n)
  let rotr_inst = @instr.VCodeInst::new(Rotr(is_64))
  rotr_inst.add_def({ reg: Virtual(dst) })
  rotr_inst.add_use(Virtual(src))
  rotr_inst.add_use(Virtual(neg_n))
  block.add_inst(rotr_inst)
}

///|
/// Lower count trailing zeros instruction
/// Standard lowering: expand to primitive instructions here
/// ctz(x) = clz(rbit(x))
///
/// Generated sequence:
/// 1. temp = Rbit(x)
/// 2. result = Clz(temp)
fn lower_ctz(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  guard inst.result is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let src = ctx.get_vreg_for_use(inst.operands[0], block)
  let is_64 = result.ty is @ir.Type::I64

  // Step 1: Reverse bits
  let reversed = ctx.vcode_func.new_vreg(Int)
  let rbit_inst = @instr.VCodeInst::new(Rbit(is_64))
  rbit_inst.add_def({ reg: Virtual(reversed) })
  rbit_inst.add_use(Virtual(src))
  block.add_inst(rbit_inst)

  // Step 2: Count leading zeros
  let clz_inst = @instr.VCodeInst::new(Clz(is_64))
  clz_inst.add_def({ reg: Virtual(dst) })
  clz_inst.add_use(Virtual(reversed))
  block.add_inst(clz_inst)
}

///|
/// Lower binary float operation
fn lower_binary_float(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
    let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
    // Determine if this is f32 based on result type
    let is_f32 = result.ty is @ir.Type::F32
    // Select VCode opcode based on IR opcode
    let opcode : @instr.VCodeOpcode = match inst.opcode {
      @ir.Opcode::Fadd => FAdd(is_f32)
      @ir.Opcode::Fsub => FSub(is_f32)
      @ir.Opcode::Fmul => FMul(is_f32)
      @ir.Opcode::Fdiv => FDiv(is_f32)
      @ir.Opcode::Fmin => FMin(is_f32)
      @ir.Opcode::Fmax => FMax(is_f32)
      _ => FAdd(is_f32) // Fallback, should not happen
    }
    let vcode_inst = @instr.VCodeInst::new(opcode)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(lhs))
    vcode_inst.add_use(Virtual(rhs))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower floating-point unary operation (sqrt, abs, neg, ceil, floor, trunc, nearest, promote, demote)
fn lower_unary_float(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    // Determine if this is f32 based on result type
    let is_f32 = result.ty is @ir.Type::F32
    // Select VCode opcode based on IR opcode
    let opcode : @instr.VCodeOpcode = match inst.opcode {
      @ir.Opcode::Fsqrt => FSqrt(is_f32)
      @ir.Opcode::Fabs => FAbs(is_f32)
      @ir.Opcode::Fneg => FNeg(is_f32)
      @ir.Opcode::Fceil => FCeil(is_f32)
      @ir.Opcode::Ffloor => FFloor(is_f32)
      @ir.Opcode::Ftrunc => FTrunc(is_f32)
      @ir.Opcode::Fnearest => FNearest(is_f32)
      _ => FSqrt(is_f32) // Fallback, should not happen
    }
    let vcode_inst = @instr.VCodeInst::new(opcode)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower f32 to f64 promotion
fn lower_promote(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let vcode_inst = @instr.VCodeInst::new(FPromote)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower f64 to f32 demotion
fn lower_demote(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let vcode_inst = @instr.VCodeInst::new(FDemote)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower integer unary operation (not)
fn lower_unary_int(
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
/// Lower integer remainder: rem = a - (a / b) * b
/// Standard lowering: expand to primitive instructions here
///
/// AArch64 doesn't have a direct remainder instruction, so we expand:
///   div = a / b  (SDIV or UDIV)
///   result = msub(div, b, a) = a - div * b
///
/// Generated sequence:
/// 1. div = SDiv/UDiv(a, b)
/// 2. result = Msub(div, b, a)
fn lower_rem(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  signed : Bool,
) -> Unit {
  let lhs = ctx.get_vreg_for_use(inst.operands[0], block) // a (dividend)
  let rhs = ctx.get_vreg_for_use(inst.operands[1], block) // b (divisor)
  let is_64 = inst.operands[0].ty is @ir.Type::I64

  // Trap if divisor is zero (trap_code 4 = integer divide by zero)
  // Must always emit even if result is unused (for side effect)
  let trap_zero = @instr.VCodeInst::new(TrapIfZero(is_64, 4))
  trap_zero.add_use(Virtual(rhs))
  block.add_inst(trap_zero)

  // Only emit remainder computation if result is used
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)

    // Step 1: Compute quotient = a / b
    let quotient = ctx.vcode_func.new_vreg(Int)
    let div_opcode = if signed {
      @instr.SDiv(is_64)
    } else {
      @instr.UDiv(is_64)
    }
    let div_inst = @instr.VCodeInst::new(div_opcode)
    div_inst.add_def({ reg: Virtual(quotient) })
    div_inst.add_use(Virtual(lhs))
    div_inst.add_use(Virtual(rhs))
    block.add_inst(div_inst)

    // Step 2: Compute remainder = a - quotient * b using MSUB
    // MSUB rd, rn, rm, ra computes: ra - rn * rm
    // We want: a - quotient * b, so: ra=a, rn=quotient, rm=b
    let msub_inst = @instr.VCodeInst::new(Msub)
    msub_inst.add_def({ reg: Virtual(dst) })
    msub_inst.add_use(Virtual(lhs)) // accumulator (a)
    msub_inst.add_use(Virtual(quotient)) // multiplicand
    msub_inst.add_use(Virtual(rhs)) // multiplier (b)
    block.add_inst(msub_inst)
  }
}

///|
/// Lower bitcast (reinterpret bits between int and float)
fn lower_bitcast(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  if inst.result is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let vcode_inst = @instr.VCodeInst::new(Bitcast)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
  }
}
