///|
/// Lower integer constant
fn lower_iconst(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  val : Int64,
) -> Unit {
  if inst.first_result() is Some(result) {
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
  if inst.first_result() is Some(result) {
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
  if inst.first_result() is Some(result) {
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
/// Get the constant value of an IR value if it's defined by Iconst
fn get_const_value(ctx : LoweringContext, value : @ir.Value) -> Int64? {
  if find_defining_inst(ctx, value) is Some(inst) &&
    inst.opcode is @ir.Opcode::Iconst(c) {
    return Some(c)
  }
  None
}

///|
/// Lower unsigned 64-bit magic division
/// q = (n * magic) >> 64 >> shift (with optional add correction)
fn lower_magic_udiv64(
  ctx : LoweringContext,
  block : @block.VCodeBlock,
  dst : @abi.VReg,
  lhs : @abi.VReg,
  magic : MagicU64,
) -> Unit {
  // Load magic constant
  let magic_reg = ctx.new_vreg(@abi.Int)
  let load_magic = @instr.VCodeInst::new(
    LoadConst(magic.mul_by.reinterpret_as_int64()),
  )
  load_magic.add_def({ reg: Virtual(magic_reg) })
  block.add_inst(load_magic)

  // q = UMULH(n, magic)
  let q_reg = ctx.new_vreg(@abi.Int)
  let umulh = @instr.VCodeInst::new(Umulh)
  umulh.add_def({ reg: Virtual(q_reg) })
  umulh.add_use(Virtual(lhs))
  umulh.add_use(Virtual(magic_reg))
  block.add_inst(umulh)
  if magic.do_add {
    // t = n - q
    let t1_reg = ctx.new_vreg(@abi.Int)
    let sub1 = @instr.VCodeInst::new(Sub(true))
    sub1.add_def({ reg: Virtual(t1_reg) })
    sub1.add_use(Virtual(lhs))
    sub1.add_use(Virtual(q_reg))
    block.add_inst(sub1)

    // t = t >> 1
    let t2_reg = ctx.new_vreg(@abi.Int)
    let shr1 = @instr.VCodeInst::new(LShr(true))
    shr1.add_def({ reg: Virtual(t2_reg) })
    shr1.add_use(Virtual(t1_reg))
    let one_reg = ctx.new_vreg(@abi.Int)
    let load_one = @instr.VCodeInst::new(LoadConst(1L))
    load_one.add_def({ reg: Virtual(one_reg) })
    block.add_inst(load_one)
    shr1.add_use(Virtual(one_reg))
    block.add_inst(shr1)

    // t = t + q
    let t3_reg = ctx.new_vreg(@abi.Int)
    let add1 = @instr.VCodeInst::new(Add(true))
    add1.add_def({ reg: Virtual(t3_reg) })
    add1.add_use(Virtual(t2_reg))
    add1.add_use(Virtual(q_reg))
    block.add_inst(add1)

    // q = t >> (shift - 1)
    let shift_reg = ctx.new_vreg(@abi.Int)
    let load_shift = @instr.VCodeInst::new(
      LoadConst((magic.shift_by - 1).to_int64()),
    )
    load_shift.add_def({ reg: Virtual(shift_reg) })
    block.add_inst(load_shift)
    let final_shr = @instr.VCodeInst::new(LShr(true))
    final_shr.add_def({ reg: Virtual(dst) })
    final_shr.add_use(Virtual(t3_reg))
    final_shr.add_use(Virtual(shift_reg))
    block.add_inst(final_shr)
  } else if magic.shift_by > 0 {
    // q = q >> shift
    let shift_reg = ctx.new_vreg(@abi.Int)
    let load_shift = @instr.VCodeInst::new(LoadConst(magic.shift_by.to_int64()))
    load_shift.add_def({ reg: Virtual(shift_reg) })
    block.add_inst(load_shift)
    let final_shr = @instr.VCodeInst::new(LShr(true))
    final_shr.add_def({ reg: Virtual(dst) })
    final_shr.add_use(Virtual(q_reg))
    final_shr.add_use(Virtual(shift_reg))
    block.add_inst(final_shr)
  } else {
    // No shift needed, just move
    let mov = @instr.VCodeInst::new(Move)
    mov.add_def({ reg: Virtual(dst) })
    mov.add_use(Virtual(q_reg))
    block.add_inst(mov)
  }
}

///|
/// Lower signed 64-bit magic division
fn lower_magic_sdiv64(
  ctx : LoweringContext,
  block : @block.VCodeBlock,
  dst : @abi.VReg,
  lhs : @abi.VReg,
  divisor : Int64,
  magic : MagicS64,
) -> Unit {
  // Load magic constant
  let magic_reg = ctx.new_vreg(@abi.Int)
  let load_magic = @instr.VCodeInst::new(LoadConst(magic.mul_by))
  load_magic.add_def({ reg: Virtual(magic_reg) })
  block.add_inst(load_magic)

  // q = SMULH(n, magic)
  let q_reg = ctx.new_vreg(@abi.Int)
  let smulh = @instr.VCodeInst::new(Smulh)
  smulh.add_def({ reg: Virtual(q_reg) })
  smulh.add_use(Virtual(lhs))
  smulh.add_use(Virtual(magic_reg))
  block.add_inst(smulh)

  // Correction based on signs
  let q2_reg = if divisor > 0L && magic.mul_by < 0L {
    // q = q + n
    let tmp = ctx.new_vreg(@abi.Int)
    let add1 = @instr.VCodeInst::new(Add(true))
    add1.add_def({ reg: Virtual(tmp) })
    add1.add_use(Virtual(q_reg))
    add1.add_use(Virtual(lhs))
    block.add_inst(add1)
    tmp
  } else if divisor < 0L && magic.mul_by > 0L {
    // q = q - n
    let tmp = ctx.new_vreg(@abi.Int)
    let sub1 = @instr.VCodeInst::new(Sub(true))
    sub1.add_def({ reg: Virtual(tmp) })
    sub1.add_use(Virtual(q_reg))
    sub1.add_use(Virtual(lhs))
    block.add_inst(sub1)
    tmp
  } else {
    q_reg
  }

  // q = q >> shift (arithmetic)
  let q3_reg = if magic.shift_by > 0 {
    let shift_reg = ctx.new_vreg(@abi.Int)
    let load_shift = @instr.VCodeInst::new(LoadConst(magic.shift_by.to_int64()))
    load_shift.add_def({ reg: Virtual(shift_reg) })
    block.add_inst(load_shift)
    let tmp = ctx.new_vreg(@abi.Int)
    let ashr = @instr.VCodeInst::new(AShr(true))
    ashr.add_def({ reg: Virtual(tmp) })
    ashr.add_use(Virtual(q2_reg))
    ashr.add_use(Virtual(shift_reg))
    block.add_inst(ashr)
    tmp
  } else {
    q2_reg
  }

  // t = q >> 63 (extract sign bit, logical shift)
  let t_reg = ctx.new_vreg(@abi.Int)
  let shift63_reg = ctx.new_vreg(@abi.Int)
  let load_63 = @instr.VCodeInst::new(LoadConst(63L))
  load_63.add_def({ reg: Virtual(shift63_reg) })
  block.add_inst(load_63)
  let lshr63 = @instr.VCodeInst::new(LShr(true))
  lshr63.add_def({ reg: Virtual(t_reg) })
  lshr63.add_use(Virtual(q3_reg))
  lshr63.add_use(Virtual(shift63_reg))
  block.add_inst(lshr63)

  // q = q + t (add 1 if negative to round toward zero)
  let final_add = @instr.VCodeInst::new(Add(true))
  final_add.add_def({ reg: Virtual(dst) })
  final_add.add_use(Virtual(q3_reg))
  final_add.add_use(Virtual(t_reg))
  block.add_inst(final_add)
}

///|
/// Lower unsigned 32-bit magic division
/// q = (n * magic) >> 32 >> shift (with optional add correction)
fn lower_magic_udiv32(
  ctx : LoweringContext,
  block : @block.VCodeBlock,
  dst : @abi.VReg,
  lhs : @abi.VReg,
  magic : MagicU32,
) -> Unit {
  // Load magic constant (32-bit, zero-extended to 64-bit for UMULL)
  let magic_reg = ctx.new_vreg(@abi.Int)
  let load_magic = @instr.VCodeInst::new(
    LoadConst(magic.mul_by.reinterpret_as_int().to_int64() & 0xFFFFFFFFL),
  )
  load_magic.add_def({ reg: Virtual(magic_reg) })
  block.add_inst(load_magic)

  // q = UMULL(n, magic) - produces 64-bit result in X register
  let q64_reg = ctx.new_vreg(@abi.Int)
  let umull = @instr.VCodeInst::new(Umull)
  umull.add_def({ reg: Virtual(q64_reg) })
  umull.add_use(Virtual(lhs))
  umull.add_use(Virtual(magic_reg))
  block.add_inst(umull)

  // Extract high 32 bits: q = q64 >> 32
  let q_reg = ctx.new_vreg(@abi.Int)
  let shift32_reg = ctx.new_vreg(@abi.Int)
  let load_32 = @instr.VCodeInst::new(LoadConst(32L))
  load_32.add_def({ reg: Virtual(shift32_reg) })
  block.add_inst(load_32)
  let lsr32 = @instr.VCodeInst::new(LShr(true)) // Use 64-bit shift
  lsr32.add_def({ reg: Virtual(q_reg) })
  lsr32.add_use(Virtual(q64_reg))
  lsr32.add_use(Virtual(shift32_reg))
  block.add_inst(lsr32)
  if magic.do_add {
    // t = n - q (32-bit)
    let t1_reg = ctx.new_vreg(@abi.Int)
    let sub1 = @instr.VCodeInst::new(Sub(false))
    sub1.add_def({ reg: Virtual(t1_reg) })
    sub1.add_use(Virtual(lhs))
    sub1.add_use(Virtual(q_reg))
    block.add_inst(sub1)

    // t = t >> 1 (32-bit)
    let t2_reg = ctx.new_vreg(@abi.Int)
    let shr1 = @instr.VCodeInst::new(LShr(false))
    shr1.add_def({ reg: Virtual(t2_reg) })
    shr1.add_use(Virtual(t1_reg))
    let one_reg = ctx.new_vreg(@abi.Int)
    let load_one = @instr.VCodeInst::new(LoadConst(1L))
    load_one.add_def({ reg: Virtual(one_reg) })
    block.add_inst(load_one)
    shr1.add_use(Virtual(one_reg))
    block.add_inst(shr1)

    // t = t + q (32-bit)
    let t3_reg = ctx.new_vreg(@abi.Int)
    let add1 = @instr.VCodeInst::new(Add(false))
    add1.add_def({ reg: Virtual(t3_reg) })
    add1.add_use(Virtual(t2_reg))
    add1.add_use(Virtual(q_reg))
    block.add_inst(add1)

    // q = t >> (shift - 1) (32-bit)
    let shift_reg = ctx.new_vreg(@abi.Int)
    let load_shift = @instr.VCodeInst::new(
      LoadConst((magic.shift_by - 1).to_int64()),
    )
    load_shift.add_def({ reg: Virtual(shift_reg) })
    block.add_inst(load_shift)
    let final_shr = @instr.VCodeInst::new(LShr(false))
    final_shr.add_def({ reg: Virtual(dst) })
    final_shr.add_use(Virtual(t3_reg))
    final_shr.add_use(Virtual(shift_reg))
    block.add_inst(final_shr)
  } else if magic.shift_by > 0 {
    // q = q >> shift (32-bit)
    let shift_reg = ctx.new_vreg(@abi.Int)
    let load_shift = @instr.VCodeInst::new(LoadConst(magic.shift_by.to_int64()))
    load_shift.add_def({ reg: Virtual(shift_reg) })
    block.add_inst(load_shift)
    let final_shr = @instr.VCodeInst::new(LShr(false))
    final_shr.add_def({ reg: Virtual(dst) })
    final_shr.add_use(Virtual(q_reg))
    final_shr.add_use(Virtual(shift_reg))
    block.add_inst(final_shr)
  } else {
    // No shift needed, just move
    let mov = @instr.VCodeInst::new(Move)
    mov.add_def({ reg: Virtual(dst) })
    mov.add_use(Virtual(q_reg))
    block.add_inst(mov)
  }
}

///|
/// Lower signed 32-bit magic division
fn lower_magic_sdiv32(
  ctx : LoweringContext,
  block : @block.VCodeBlock,
  dst : @abi.VReg,
  lhs : @abi.VReg,
  divisor : Int,
  magic : MagicS32,
) -> Unit {
  // Load magic constant (sign-extended for SMULL)
  let magic_reg = ctx.new_vreg(@abi.Int)
  let load_magic = @instr.VCodeInst::new(LoadConst(magic.mul_by.to_int64()))
  load_magic.add_def({ reg: Virtual(magic_reg) })
  block.add_inst(load_magic)

  // q = SMULL(n, magic) - produces 64-bit signed result
  let q64_reg = ctx.new_vreg(@abi.Int)
  let smull = @instr.VCodeInst::new(Smull)
  smull.add_def({ reg: Virtual(q64_reg) })
  smull.add_use(Virtual(lhs))
  smull.add_use(Virtual(magic_reg))
  block.add_inst(smull)

  // Extract high 32 bits with sign: q = q64 >> 32 (arithmetic)
  let q_reg = ctx.new_vreg(@abi.Int)
  let shift32_reg = ctx.new_vreg(@abi.Int)
  let load_32 = @instr.VCodeInst::new(LoadConst(32L))
  load_32.add_def({ reg: Virtual(shift32_reg) })
  block.add_inst(load_32)
  let asr32 = @instr.VCodeInst::new(AShr(true)) // Arithmetic shift to preserve sign
  asr32.add_def({ reg: Virtual(q_reg) })
  asr32.add_use(Virtual(q64_reg))
  asr32.add_use(Virtual(shift32_reg))
  block.add_inst(asr32)

  // Correction based on signs
  let q2_reg = if divisor > 0 && magic.mul_by < 0 {
    // q = q + n
    let tmp = ctx.new_vreg(@abi.Int)
    let add1 = @instr.VCodeInst::new(Add(false))
    add1.add_def({ reg: Virtual(tmp) })
    add1.add_use(Virtual(q_reg))
    add1.add_use(Virtual(lhs))
    block.add_inst(add1)
    tmp
  } else if divisor < 0 && magic.mul_by > 0 {
    // q = q - n
    let tmp = ctx.new_vreg(@abi.Int)
    let sub1 = @instr.VCodeInst::new(Sub(false))
    sub1.add_def({ reg: Virtual(tmp) })
    sub1.add_use(Virtual(q_reg))
    sub1.add_use(Virtual(lhs))
    block.add_inst(sub1)
    tmp
  } else {
    q_reg
  }

  // q = q >> shift (arithmetic, 32-bit)
  let q3_reg = if magic.shift_by > 0 {
    let shift_reg = ctx.new_vreg(@abi.Int)
    let load_shift = @instr.VCodeInst::new(LoadConst(magic.shift_by.to_int64()))
    load_shift.add_def({ reg: Virtual(shift_reg) })
    block.add_inst(load_shift)
    let tmp = ctx.new_vreg(@abi.Int)
    let ashr = @instr.VCodeInst::new(AShr(false))
    ashr.add_def({ reg: Virtual(tmp) })
    ashr.add_use(Virtual(q2_reg))
    ashr.add_use(Virtual(shift_reg))
    block.add_inst(ashr)
    tmp
  } else {
    q2_reg
  }

  // t = q >> 31 (extract sign bit, logical shift for 32-bit)
  let t_reg = ctx.new_vreg(@abi.Int)
  let shift31_reg = ctx.new_vreg(@abi.Int)
  let load_31 = @instr.VCodeInst::new(LoadConst(31L))
  load_31.add_def({ reg: Virtual(shift31_reg) })
  block.add_inst(load_31)
  let lshr31 = @instr.VCodeInst::new(LShr(false))
  lshr31.add_def({ reg: Virtual(t_reg) })
  lshr31.add_use(Virtual(q3_reg))
  lshr31.add_use(Virtual(shift31_reg))
  block.add_inst(lshr31)

  // q = q + t (add 1 if negative to round toward zero)
  let final_add = @instr.VCodeInst::new(Add(false))
  final_add.add_def({ reg: Virtual(dst) })
  final_add.add_use(Virtual(q3_reg))
  final_add.add_use(Virtual(t_reg))
  block.add_inst(final_add)
}

///|
/// Lower division with proper 32/64-bit selection and trapping
fn lower_div(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  signed~ : Bool,
) -> Unit {
  let lhs_val = inst.operands[1]
  let is_64 = inst.operands[0].ty is @ir.Type::I64

  // Check if divisor is a constant suitable for magic division
  if inst.first_result() is Some(result) {
    if get_const_value(ctx, lhs_val) is Some(divisor) {
      if is_64 {
        // 64-bit magic division
        let use_magic = if signed {
          // For signed: |d| > 1 and d != -1
          divisor > 1L || divisor < -1L
        } else {
          // For unsigned: d > 1
          divisor > 1L
        }
        if use_magic {
          let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
          let dst = ctx.get_vreg(result)
          if signed {
            let magic = magic_s64(divisor)
            lower_magic_sdiv64(ctx, block, dst, lhs, divisor, magic)
          } else {
            let magic = magic_u64(divisor.reinterpret_as_uint64())
            lower_magic_udiv64(ctx, block, dst, lhs, magic)
          }
          return
        }
      } else {
        // 32-bit magic division
        let divisor32 = divisor.to_int()
        let use_magic = if signed {
          // For signed: |d| > 1 and d != -1
          divisor32 > 1 || divisor32 < -1
        } else {
          // For unsigned: d > 1
          divisor32 > 1
        }
        if use_magic {
          let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
          let dst = ctx.get_vreg(result)
          if signed {
            let magic = magic_s32(divisor32)
            lower_magic_sdiv32(ctx, block, dst, lhs, divisor32, magic)
          } else {
            let magic = magic_u32(divisor32.reinterpret_as_uint())
            lower_magic_udiv32(ctx, block, dst, lhs, magic)
          }
          return
        }
      }
    }
  }

  // Fall back to regular division
  let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
  let rhs = ctx.get_vreg_for_use(inst.operands[1], block)

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
  if inst.first_result() is Some(result) {
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
  if inst.first_result() is Some(result) {
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
  if inst.first_result() is Some(result) {
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
  guard inst.first_result() is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]

  // Pattern: add(x, mul(y, z)) -> MADD (i64 only; 32-bit would pollute upper bits)
  if result.ty is @ir.Type::I64 &&
    match_mul_value(ctx, rhs_val) is Some((mul_lhs, mul_rhs)) {
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

  // Pattern: add(mul(x, y), z) -> MADD (commutative, i64 only)
  if result.ty is @ir.Type::I64 &&
    match_mul_value(ctx, lhs_val) is Some((mul_lhs, mul_rhs)) {
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

  // Pattern: add(x, shl(y, n)) -> AddShifted (i64 only to avoid upper 32-bit pollution)
  if result.ty is @ir.Type::I64 &&
    match_shl_const_value(ctx, rhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(lhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let vcode_inst = @instr.VCodeInst::new(AddShifted(Lsl, amount))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rn))
    vcode_inst.add_use(Virtual(rm))
    block.add_inst(vcode_inst)
    return
  }

  // Pattern: add(shl(x, n), y) -> AddShifted (commutative, i64 only)
  if result.ty is @ir.Type::I64 &&
    match_shl_const_value(ctx, lhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(rhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let vcode_inst = @instr.VCodeInst::new(AddShifted(Lsl, amount))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rn))
    vcode_inst.add_use(Virtual(rm))
    block.add_inst(vcode_inst)
    return
  }

  // Pattern: add(x, const) -> AddImm where const is valid 12-bit immediate
  if match_add_imm_value(ctx, rhs_val) is Some(imm_val) {
    let lhs = ctx.get_vreg_for_use(lhs_val, block)
    let is_64 = result.ty is @ir.Type::I64
    let vcode_inst = @instr.VCodeInst::new(AddImm(imm_val.to_int(), is_64))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(lhs))
    block.add_inst(vcode_inst)
    return
  }

  // Pattern: add(const, x) -> AddImm (commutative)
  if match_add_imm_value(ctx, lhs_val) is Some(imm_val) {
    let rhs = ctx.get_vreg_for_use(rhs_val, block)
    let is_64 = result.ty is @ir.Type::I64
    let vcode_inst = @instr.VCodeInst::new(AddImm(imm_val.to_int(), is_64))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rhs))
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
  guard inst.first_result() is Some(result) else { return }
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
fn lower_umulh(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  lower_binary_int(ctx, inst, block, Umulh)
}

///|
fn lower_smulh(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  lower_binary_int(ctx, inst, block, Smulh)
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
  guard inst.first_result() is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]

  // Pattern: sub(0, mul(x, y)) -> MNEG (i64 only; 32-bit would pollute upper bits)
  if result.ty is @ir.Type::I64 &&
    is_const_zero_value(ctx, lhs_val) &&
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

  // Pattern: sub(x, mul(y, z)) -> MSUB (i64 only; 32-bit would pollute upper bits)
  if result.ty is @ir.Type::I64 &&
    match_mul_value(ctx, rhs_val) is Some((mul_lhs, mul_rhs)) {
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

  // Pattern: sub(x, shl(y, n)) -> SubShifted (i64 only to avoid upper 32-bit pollution)
  if result.ty is @ir.Type::I64 &&
    match_shl_const_value(ctx, rhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(lhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let vcode_inst = @instr.VCodeInst::new(SubShifted(Lsl, amount))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rn))
    vcode_inst.add_use(Virtual(rm))
    block.add_inst(vcode_inst)
    return
  }

  // Pattern: sub(x, const) -> SubImm where const is valid 12-bit immediate
  if match_add_imm_value(ctx, rhs_val) is Some(imm_val) {
    let lhs = ctx.get_vreg_for_use(lhs_val, block)
    let is_64 = result.ty is @ir.Type::I64
    let vcode_inst = @instr.VCodeInst::new(SubImm(imm_val.to_int(), is_64))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(lhs))
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
  guard inst.first_result() is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]

  // Pattern: and(x, shl(y, n)) -> AndShifted (i64 only)
  if result.ty is @ir.Type::I64 &&
    match_shl_const_value(ctx, rhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(lhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let vcode_inst = @instr.VCodeInst::new(AndShifted(Lsl, amount))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rn))
    vcode_inst.add_use(Virtual(rm))
    block.add_inst(vcode_inst)
    return
  }

  // Pattern: and(shl(x, n), y) -> AndShifted (commutative, i64 only)
  if result.ty is @ir.Type::I64 &&
    match_shl_const_value(ctx, lhs_val) is Some((shifted, amount)) {
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
  guard inst.first_result() is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]

  // Pattern: or(x, shl(y, n)) -> OrShifted (i64 only)
  if result.ty is @ir.Type::I64 &&
    match_shl_const_value(ctx, rhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(lhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let vcode_inst = @instr.VCodeInst::new(OrShifted(Lsl, amount))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rn))
    vcode_inst.add_use(Virtual(rm))
    block.add_inst(vcode_inst)
    return
  }

  // Pattern: or(shl(x, n), y) -> OrShifted (commutative, i64 only)
  if result.ty is @ir.Type::I64 &&
    match_shl_const_value(ctx, lhs_val) is Some((shifted, amount)) {
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
  guard inst.first_result() is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]

  // Pattern: xor(x, shl(y, n)) -> XorShifted (i64 only)
  if result.ty is @ir.Type::I64 &&
    match_shl_const_value(ctx, rhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(lhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let vcode_inst = @instr.VCodeInst::new(XorShifted(Lsl, amount))
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(rn))
    vcode_inst.add_use(Virtual(rm))
    block.add_inst(vcode_inst)
    return
  }

  // Pattern: xor(shl(x, n), y) -> XorShifted (commutative, i64 only)
  if result.ty is @ir.Type::I64 &&
    match_shl_const_value(ctx, lhs_val) is Some((shifted, amount)) {
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
  guard inst.first_result() is Some(result) else { return }
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
  guard inst.first_result() is Some(result) else { return }
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
  if inst.first_result() is Some(result) {
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
  if inst.first_result() is Some(result) {
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
  if inst.first_result() is Some(result) {
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
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let vcode_inst = @instr.VCodeInst::new(FDemote)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
  }
}

///|
/// Lower integer unary operation (not) with proper 32/64-bit selection
fn lower_unary_int(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
  make_opcode : (Bool) -> @instr.VCodeOpcode,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let is_64 = result.ty is @ir.Type::I64
    let vcode_inst = @instr.VCodeInst::new(make_opcode(is_64))
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
  if inst.first_result() is Some(result) {
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

    // Step 2: Compute remainder = a - quotient * b
    // - For i64, use MSUB (single instruction): a - quotient*b
    // - For i32, avoid MSUB because our MSUB opcode is 64-bit (X regs) and
    //   would mis-handle signed values by zero-extending w-reg results.
    if is_64 {
      // MSUB rd, rn, rm, ra computes: ra - rn * rm
      // We want: a - quotient * b, so: ra=a, rn=quotient, rm=b
      let msub_inst = @instr.VCodeInst::new(Msub)
      msub_inst.add_def({ reg: Virtual(dst) })
      msub_inst.add_use(Virtual(lhs)) // accumulator (a)
      msub_inst.add_use(Virtual(quotient)) // multiplicand
      msub_inst.add_use(Virtual(rhs)) // multiplier (b)
      block.add_inst(msub_inst)
    } else {
      let product = ctx.vcode_func.new_vreg(Int)
      let mul_inst = @instr.VCodeInst::new(Mul(false))
      mul_inst.add_def({ reg: Virtual(product) })
      mul_inst.add_use(Virtual(quotient))
      mul_inst.add_use(Virtual(rhs))
      block.add_inst(mul_inst)
      let sub_inst = @instr.VCodeInst::new(Sub(false))
      sub_inst.add_def({ reg: Virtual(dst) })
      sub_inst.add_use(Virtual(lhs))
      sub_inst.add_use(Virtual(product))
      block.add_inst(sub_inst)
    }
  }
}

///|
/// Lower bitcast (reinterpret bits between int and float)
fn lower_bitcast(
  ctx : LoweringContext,
  inst : @ir.Inst,
  block : @block.VCodeBlock,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let vcode_inst = @instr.VCodeInst::new(Bitcast)
    vcode_inst.add_def({ reg: Virtual(dst) })
    vcode_inst.add_use(Virtual(src))
    block.add_inst(vcode_inst)
  }
}
