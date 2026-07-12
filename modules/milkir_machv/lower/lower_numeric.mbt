///|
/// Lower integer constant
fn lower_iconst(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  val : Int64,
) -> Unit {
  if inst.first_result() is Some(result) {
    let vreg = ctx.get_vreg(result)
    let machv_inst = @instr.Inst(LoadConst(val))
    machv_inst.add_def({ reg: Virtual(vreg) })
    block.add_inst(machv_inst)
  }
}

///|
/// Lower float constant
fn lower_fconst(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  val : Double,
) -> Unit {
  if inst.first_result() is Some(result) {
    let vreg = ctx.get_vreg(result)
    // Determine if this is an F32 or F64 constant based on the result type
    let opcode = match result.ty {
      F32 => {
        // F32 bits are packed in the lower 32 bits of the Double's bit representation
        // (see FunctionBuilder::fconst_f32). Extract them directly to preserve NaN payloads.
        let bits = val.reinterpret_as_int64().to_int()
        @instr.LoadConstF32(bits)
      }
      _ => {
        // F64: get 64-bit representation
        let bits = val.reinterpret_as_int64()
        LoadConstF64(bits)
      }
    }
    let machv_inst = @instr.Inst(opcode)
    machv_inst.add_def({ reg: Virtual(vreg) })
    block.add_inst(machv_inst)
  }
}

///|
/// Lower binary integer operation
fn lower_binary_int(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  opcode : @instr.Opcode,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
    let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
    let machv_inst = @instr.Inst(opcode)
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(lhs))
    machv_inst.add_use(Virtual(rhs))
    block.add_inst(machv_inst)
  }
}

///|
/// Get the constant value of an IR value if it's defined by Iconst
fn get_const_value(ctx : LoweringContext, value : @milkir.Value) -> Int64? {
  iconst_value(ctx, value)
}

///|
/// Resolve trivial `Copy` chains to a stable IR value.
fn resolve_copy_value(
  ctx : LoweringContext,
  value0 : @milkir.Value,
) -> @milkir.Value {
  let mut value = value0
  let mut depth = 0
  while depth < 8 {
    depth += 1
    if find_defining_inst(ctx, value) is Some(inst) &&
      inst.opcode is Scalar(Copy) &&
      !inst.operands.is_empty() {
      value = inst.operands[0]
      continue
    }
    break
  }
  value
}

///|
/// Check whether two IR values are equivalent after resolving trivial copies.
fn values_equivalent(
  ctx : LoweringContext,
  lhs : @milkir.Value,
  rhs : @milkir.Value,
) -> Bool {
  let lhs = resolve_copy_value(ctx, lhs)
  let rhs = resolve_copy_value(ctx, rhs)
  lhs.id == rhs.id && lhs.ty == rhs.ty
}

///|
/// Match `(x - y) + y -> x` (and copy-equivalent variants).
fn match_sub_add_cancel_value(
  ctx : LoweringContext,
  maybe_sub : @milkir.Value,
  addend : @milkir.Value,
) -> @milkir.Value? {
  if find_defining_inst(ctx, maybe_sub) is Some(sub_inst) &&
    sub_inst.opcode is Scalar(IntBinary(Sub)) &&
    sub_inst.operands.length() == 2 &&
    values_equivalent(ctx, sub_inst.operands[1], addend) {
    return Some(sub_inst.operands[0])
  }
  None
}

///|
/// Match `(x + y) - y -> x` and `(x + y) - x -> y` (copy-equivalent variants).
fn match_add_sub_cancel_value(
  ctx : LoweringContext,
  maybe_add : @milkir.Value,
  subtrahend : @milkir.Value,
) -> @milkir.Value? {
  if find_defining_inst(ctx, maybe_add) is Some(add_inst) &&
    add_inst.opcode is Scalar(IntBinary(Add)) &&
    add_inst.operands.length() == 2 {
    if values_equivalent(ctx, add_inst.operands[0], subtrahend) {
      return Some(add_inst.operands[1])
    }
    if values_equivalent(ctx, add_inst.operands[1], subtrahend) {
      return Some(add_inst.operands[0])
    }
  }
  None
}

///|
/// Lower unsigned 64-bit magic division
/// q = (n * magic) >> 64 >> shift (with optional add correction)
fn lower_magic_udiv64(
  ctx : LoweringContext,
  block : @block.Block,
  dst : @abi.VReg,
  lhs : @abi.VReg,
  magic : @divmagic.MagicU64,
) -> Unit {
  // Load magic constant
  let magic_reg = ctx.new_vreg(Int)
  let load_magic = @instr.Inst(LoadConst(magic.mul_by.reinterpret_as_int64()))
  load_magic.add_def({ reg: Virtual(magic_reg) })
  block.add_inst(load_magic)

  // q = UMULH(n, magic)
  let q_reg = ctx.new_vreg(Int)
  let umulh = @instr.Inst(Umulh)
  umulh.add_def({ reg: Virtual(q_reg) })
  umulh.add_use(Virtual(lhs))
  umulh.add_use(Virtual(magic_reg))
  block.add_inst(umulh)
  if magic.do_add {
    // t = n - q
    let t1_reg = ctx.new_vreg(Int)
    let sub1 = @instr.Inst(Sub(true))
    sub1.add_def({ reg: Virtual(t1_reg) })
    sub1.add_use(Virtual(lhs))
    sub1.add_use(Virtual(q_reg))
    block.add_inst(sub1)

    // t = t >> 1
    let t2_reg = ctx.new_vreg(Int)
    let shr1 = @instr.Inst(LShr(true))
    shr1.add_def({ reg: Virtual(t2_reg) })
    shr1.add_use(Virtual(t1_reg))
    let one_reg = ctx.new_vreg(Int)
    let load_one = @instr.Inst(LoadConst(1L))
    load_one.add_def({ reg: Virtual(one_reg) })
    block.add_inst(load_one)
    shr1.add_use(Virtual(one_reg))
    block.add_inst(shr1)

    // t = t + q
    let t3_reg = ctx.new_vreg(Int)
    let add1 = @instr.Inst(Add(true))
    add1.add_def({ reg: Virtual(t3_reg) })
    add1.add_use(Virtual(t2_reg))
    add1.add_use(Virtual(q_reg))
    block.add_inst(add1)

    // q = t >> (shift - 1)
    let shift_reg = ctx.new_vreg(Int)
    let load_shift = @instr.Inst(LoadConst((magic.shift_by - 1).to_int64()))
    load_shift.add_def({ reg: Virtual(shift_reg) })
    block.add_inst(load_shift)
    let final_shr = @instr.Inst(LShr(true))
    final_shr.add_def({ reg: Virtual(dst) })
    final_shr.add_use(Virtual(t3_reg))
    final_shr.add_use(Virtual(shift_reg))
    block.add_inst(final_shr)
  } else if magic.shift_by > 0 {
    // q = q >> shift
    let shift_reg = ctx.new_vreg(Int)
    let load_shift = @instr.Inst(LoadConst(magic.shift_by.to_int64()))
    load_shift.add_def({ reg: Virtual(shift_reg) })
    block.add_inst(load_shift)
    let final_shr = @instr.Inst(LShr(true))
    final_shr.add_def({ reg: Virtual(dst) })
    final_shr.add_use(Virtual(q_reg))
    final_shr.add_use(Virtual(shift_reg))
    block.add_inst(final_shr)
  } else {
    // No shift needed, just move
    let mov = @instr.Inst(Move)
    mov.add_def({ reg: Virtual(dst) })
    mov.add_use(Virtual(q_reg))
    block.add_inst(mov)
  }
}

///|
/// Lower signed 64-bit magic division
fn lower_magic_sdiv64(
  ctx : LoweringContext,
  block : @block.Block,
  dst : @abi.VReg,
  lhs : @abi.VReg,
  divisor : Int64,
  magic : @divmagic.MagicS64,
) -> Unit {
  // Load magic constant
  let magic_reg = ctx.new_vreg(Int)
  let load_magic = @instr.Inst(LoadConst(magic.mul_by))
  load_magic.add_def({ reg: Virtual(magic_reg) })
  block.add_inst(load_magic)

  // q = SMULH(n, magic)
  let q_reg = ctx.new_vreg(Int)
  let smulh = @instr.Inst(Smulh)
  smulh.add_def({ reg: Virtual(q_reg) })
  smulh.add_use(Virtual(lhs))
  smulh.add_use(Virtual(magic_reg))
  block.add_inst(smulh)

  // Correction based on signs
  let q2_reg = if divisor > 0L && magic.mul_by < 0L {
    // q = q + n
    let tmp = ctx.new_vreg(Int)
    let add1 = @instr.Inst(Add(true))
    add1.add_def({ reg: Virtual(tmp) })
    add1.add_use(Virtual(q_reg))
    add1.add_use(Virtual(lhs))
    block.add_inst(add1)
    tmp
  } else if divisor < 0L && magic.mul_by > 0L {
    // q = q - n
    let tmp = ctx.new_vreg(Int)
    let sub1 = @instr.Inst(Sub(true))
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
    let shift_reg = ctx.new_vreg(Int)
    let load_shift = @instr.Inst(LoadConst(magic.shift_by.to_int64()))
    load_shift.add_def({ reg: Virtual(shift_reg) })
    block.add_inst(load_shift)
    let tmp = ctx.new_vreg(Int)
    let ashr = @instr.Inst(AShr(true))
    ashr.add_def({ reg: Virtual(tmp) })
    ashr.add_use(Virtual(q2_reg))
    ashr.add_use(Virtual(shift_reg))
    block.add_inst(ashr)
    tmp
  } else {
    q2_reg
  }

  // t = q >> 63 (extract sign bit, logical shift)
  let t_reg = ctx.new_vreg(Int)
  let shift63_reg = ctx.new_vreg(Int)
  let load_63 = @instr.Inst(LoadConst(63L))
  load_63.add_def({ reg: Virtual(shift63_reg) })
  block.add_inst(load_63)
  let lshr63 = @instr.Inst(LShr(true))
  lshr63.add_def({ reg: Virtual(t_reg) })
  lshr63.add_use(Virtual(q3_reg))
  lshr63.add_use(Virtual(shift63_reg))
  block.add_inst(lshr63)

  // q = q + t (add 1 if negative to round toward zero)
  let final_add = @instr.Inst(Add(true))
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
  block : @block.Block,
  dst : @abi.VReg,
  lhs : @abi.VReg,
  magic : @divmagic.MagicU32,
) -> Unit {
  // Load magic constant (32-bit, zero-extended to 64-bit for UMULL)
  let magic_reg = ctx.new_vreg(Int)
  let load_magic = @instr.Inst(
    LoadConst(magic.mul_by.reinterpret_as_int().to_int64() & 0xFFFFFFFFL),
  )
  load_magic.add_def({ reg: Virtual(magic_reg) })
  block.add_inst(load_magic)

  // q = UMULL(n, magic) - produces 64-bit result in X register
  let q64_reg = ctx.new_vreg(Int)
  let umull = @instr.Inst(Umull)
  umull.add_def({ reg: Virtual(q64_reg) })
  umull.add_use(Virtual(lhs))
  umull.add_use(Virtual(magic_reg))
  block.add_inst(umull)

  // Extract high 32 bits: q = q64 >> 32
  let q_reg = ctx.new_vreg(Int)
  let shift32_reg = ctx.new_vreg(Int)
  let load_32 = @instr.Inst(LoadConst(32L))
  load_32.add_def({ reg: Virtual(shift32_reg) })
  block.add_inst(load_32)
  let lsr32 = @instr.Inst(LShr(true)) // Use 64-bit shift
  lsr32.add_def({ reg: Virtual(q_reg) })
  lsr32.add_use(Virtual(q64_reg))
  lsr32.add_use(Virtual(shift32_reg))
  block.add_inst(lsr32)
  if magic.do_add {
    // t = n - q (32-bit)
    let t1_reg = ctx.new_vreg(Int)
    let sub1 = @instr.Inst(Sub(false))
    sub1.add_def({ reg: Virtual(t1_reg) })
    sub1.add_use(Virtual(lhs))
    sub1.add_use(Virtual(q_reg))
    block.add_inst(sub1)

    // t = t >> 1 (32-bit)
    let t2_reg = ctx.new_vreg(Int)
    let shr1 = @instr.Inst(LShr(false))
    shr1.add_def({ reg: Virtual(t2_reg) })
    shr1.add_use(Virtual(t1_reg))
    let one_reg = ctx.new_vreg(Int)
    let load_one = @instr.Inst(LoadConst(1L))
    load_one.add_def({ reg: Virtual(one_reg) })
    block.add_inst(load_one)
    shr1.add_use(Virtual(one_reg))
    block.add_inst(shr1)

    // t = t + q (32-bit)
    let t3_reg = ctx.new_vreg(Int)
    let add1 = @instr.Inst(Add(false))
    add1.add_def({ reg: Virtual(t3_reg) })
    add1.add_use(Virtual(t2_reg))
    add1.add_use(Virtual(q_reg))
    block.add_inst(add1)

    // q = t >> (shift - 1) (32-bit)
    let shift_reg = ctx.new_vreg(Int)
    let load_shift = @instr.Inst(LoadConst((magic.shift_by - 1).to_int64()))
    load_shift.add_def({ reg: Virtual(shift_reg) })
    block.add_inst(load_shift)
    let final_shr = @instr.Inst(LShr(false))
    final_shr.add_def({ reg: Virtual(dst) })
    final_shr.add_use(Virtual(t3_reg))
    final_shr.add_use(Virtual(shift_reg))
    block.add_inst(final_shr)
  } else if magic.shift_by > 0 {
    // q = q >> shift (32-bit)
    let shift_reg = ctx.new_vreg(Int)
    let load_shift = @instr.Inst(LoadConst(magic.shift_by.to_int64()))
    load_shift.add_def({ reg: Virtual(shift_reg) })
    block.add_inst(load_shift)
    let final_shr = @instr.Inst(LShr(false))
    final_shr.add_def({ reg: Virtual(dst) })
    final_shr.add_use(Virtual(q_reg))
    final_shr.add_use(Virtual(shift_reg))
    block.add_inst(final_shr)
  } else {
    // No shift needed, just move
    let mov = @instr.Inst(Move)
    mov.add_def({ reg: Virtual(dst) })
    mov.add_use(Virtual(q_reg))
    block.add_inst(mov)
  }
}

///|
/// Lower signed 32-bit magic division
fn lower_magic_sdiv32(
  ctx : LoweringContext,
  block : @block.Block,
  dst : @abi.VReg,
  lhs : @abi.VReg,
  divisor : Int,
  magic : @divmagic.MagicS32,
) -> Unit {
  // Load magic constant (sign-extended for SMULL)
  let magic_reg = ctx.new_vreg(Int)
  let load_magic = @instr.Inst(LoadConst(magic.mul_by.to_int64()))
  load_magic.add_def({ reg: Virtual(magic_reg) })
  block.add_inst(load_magic)

  // q = SMULL(n, magic) - produces 64-bit signed result
  let q64_reg = ctx.new_vreg(Int)
  let smull = @instr.Inst(Smull)
  smull.add_def({ reg: Virtual(q64_reg) })
  smull.add_use(Virtual(lhs))
  smull.add_use(Virtual(magic_reg))
  block.add_inst(smull)

  // Extract high 32 bits with sign: q = q64 >> 32 (arithmetic)
  let q_reg = ctx.new_vreg(Int)
  let shift32_reg = ctx.new_vreg(Int)
  let load_32 = @instr.Inst(LoadConst(32L))
  load_32.add_def({ reg: Virtual(shift32_reg) })
  block.add_inst(load_32)
  let asr32 = @instr.Inst(AShr(true)) // Arithmetic shift to preserve sign
  asr32.add_def({ reg: Virtual(q_reg) })
  asr32.add_use(Virtual(q64_reg))
  asr32.add_use(Virtual(shift32_reg))
  block.add_inst(asr32)

  // Correction based on signs
  let q2_reg = if divisor > 0 && magic.mul_by < 0 {
    // q = q + n
    let tmp = ctx.new_vreg(Int)
    let add1 = @instr.Inst(Add(false))
    add1.add_def({ reg: Virtual(tmp) })
    add1.add_use(Virtual(q_reg))
    add1.add_use(Virtual(lhs))
    block.add_inst(add1)
    tmp
  } else if divisor < 0 && magic.mul_by > 0 {
    // q = q - n
    let tmp = ctx.new_vreg(Int)
    let sub1 = @instr.Inst(Sub(false))
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
    let shift_reg = ctx.new_vreg(Int)
    let load_shift = @instr.Inst(LoadConst(magic.shift_by.to_int64()))
    load_shift.add_def({ reg: Virtual(shift_reg) })
    block.add_inst(load_shift)
    let tmp = ctx.new_vreg(Int)
    let ashr = @instr.Inst(AShr(false))
    ashr.add_def({ reg: Virtual(tmp) })
    ashr.add_use(Virtual(q2_reg))
    ashr.add_use(Virtual(shift_reg))
    block.add_inst(ashr)
    tmp
  } else {
    q2_reg
  }

  // t = q >> 31 (extract sign bit, logical shift for 32-bit)
  let t_reg = ctx.new_vreg(Int)
  let shift31_reg = ctx.new_vreg(Int)
  let load_31 = @instr.Inst(LoadConst(31L))
  load_31.add_def({ reg: Virtual(shift31_reg) })
  block.add_inst(load_31)
  let lshr31 = @instr.Inst(LShr(false))
  lshr31.add_def({ reg: Virtual(t_reg) })
  lshr31.add_use(Virtual(q3_reg))
  lshr31.add_use(Virtual(shift31_reg))
  block.add_inst(lshr31)

  // q = q + t (add 1 if negative to round toward zero)
  let final_add = @instr.Inst(Add(false))
  final_add.add_def({ reg: Virtual(dst) })
  final_add.add_use(Virtual(q3_reg))
  final_add.add_use(Virtual(t_reg))
  block.add_inst(final_add)
}

///|
/// Lower division with proper 32/64-bit selection and trapping
fn lower_div(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  signed~ : Bool,
) -> Unit {
  let lhs_val = inst.operands[1]
  let is_64 = inst.operands[0].ty is I64

  // x86_64 backend is still incomplete; avoid magic-division lowering which
  // currently relies on AArch64-specific opcodes and patterns.
  let enable_magic_div = !(ctx.isa is AMD64)

  // Check if divisor is a constant suitable for magic division
  if enable_magic_div &&
    inst.first_result() is Some(result) &&
    get_const_value(ctx, lhs_val) is Some(divisor) {
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
          let magic = @divmagic.magic_s64(divisor)
          lower_magic_sdiv64(ctx, block, dst, lhs, divisor, magic)
        } else {
          let magic = @divmagic.magic_u64(divisor.reinterpret_as_uint64())
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
          let magic = @divmagic.magic_s32(divisor32)
          lower_magic_sdiv32(ctx, block, dst, lhs, divisor32, magic)
        } else {
          let magic = @divmagic.magic_u32(divisor32.reinterpret_as_uint())
          lower_magic_udiv32(ctx, block, dst, lhs, magic)
        }
        return
      }
    }
  }

  // Fall back to regular division
  let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
  let rhs = ctx.get_vreg_for_use(inst.operands[1], block)

  // Trap if divisor is zero (trap_code 4 = integer divide by zero)
  // Must always emit even if result is unused (for side effect)
  let trap_zero = @instr.Inst(TrapIfZero(is_64, 4))
  trap_zero.add_use(Virtual(rhs))
  block.add_inst(trap_zero)

  // For signed division, also trap if INT_MIN / -1 (would overflow)
  // Use trap_code 5 = integer overflow
  if signed {
    let trap_overflow = @instr.Inst(TrapIfDivOverflow(is_64, 5))
    trap_overflow.add_use(Virtual(lhs))
    trap_overflow.add_use(Virtual(rhs))
    block.add_inst(trap_overflow)
  }

  // Only emit division if result is used
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let opcode : @instr.Opcode = if signed { SDiv(is_64) } else { UDiv(is_64) }
    let machv_inst = @instr.Inst(opcode)
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(lhs))
    machv_inst.add_use(Virtual(rhs))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower shift/rotate operations with proper 32/64-bit selection
fn lower_shift(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  make_reg_opcode : (Bool) -> @instr.Opcode,
  make_imm_opcode : (Int, Bool) -> @instr.Opcode,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
    let is_64 = result.ty is I64
    let mask = if is_64 { 63 } else { 31 }

    // Cranelift-style: if shift amount is constant, use immediate encoding and
    // mask it by bitwidth-1, matching MilkIR shift semantics.
    if get_const_value(ctx, inst.operands[1]) is Some(amount) {
      let shift = amount.to_int() & mask
      let machv_inst = @instr.Inst(make_imm_opcode(shift, is_64))
      machv_inst.add_def({ reg: Virtual(dst) })
      machv_inst.add_use(Virtual(lhs))
      block.add_inst(machv_inst)
      return
    }
    let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
    let machv_inst = @instr.Inst(make_reg_opcode(is_64))
    if ctx.isa is AMD64 {
      // x86_64 variable shifts/rotates use CL as the implicit count register.
      // Keep the data operand in Scratch1 to avoid clobbering when the count
      // operand is moved into rcx by fixed-reg constraint edits.
      let shift_data : @abi.PReg = {
        index: ctx.isa.scratch_reg_1_index(),
        class: Int,
      }
      machv_inst.add_def_fixed({ reg: Virtual(dst) }, shift_data)
      machv_inst.add_use_fixed(Virtual(lhs), shift_data)
      machv_inst.add_use_fixed(Virtual(rhs), { index: 1, class: Int }) // rcx
    } else {
      machv_inst.add_def({ reg: Virtual(dst) })
      machv_inst.add_use(Virtual(lhs))
      machv_inst.add_use(Virtual(rhs))
    }
    block.add_inst(machv_inst)
  }
}

///|
/// Lower bit counting operations (clz, popcnt) with proper 32/64-bit selection
fn lower_bitcount(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  make_opcode : (Bool) -> @instr.Opcode,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let is_64 = result.ty is I64
    let machv_inst = @instr.Inst(make_opcode(is_64))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(src))
    block.add_inst(machv_inst)
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
/// - add(x, uextend/sextend(i32)) -> AddExtend (i64 only)
fn lower_iadd(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]
  let is_64 = result.ty is I64

  // Cranelift algebraic cancelation: (x - y) + y -> x.
  if match_sub_add_cancel_value(ctx, lhs_val, rhs_val) is Some(base) {
    let src = ctx.get_vreg_for_use(base, block)
    let move_inst = @instr.Inst(Move)
    move_inst.add_def({ reg: Virtual(dst) })
    move_inst.add_use(Virtual(src))
    block.add_inst(move_inst)
    return
  }
  if match_sub_add_cancel_value(ctx, rhs_val, lhs_val) is Some(base) {
    let src = ctx.get_vreg_for_use(base, block)
    let move_inst = @instr.Inst(Move)
    move_inst.add_def({ reg: Virtual(dst) })
    move_inst.add_use(Virtual(src))
    block.add_inst(move_inst)
    return
  }

  // Pattern: add(x, mul(y, z)) -> MADD / MADD32.
  // Match Cranelift's iadd_imul_{right,left} for fits_in_64 (i64 + i32).
  if match_mul_value(ctx, rhs_val) is Some((mul_lhs, mul_rhs)) {
    let acc = ctx.get_vreg_for_use(lhs_val, block)
    let src1 = ctx.get_vreg_for_use(mul_lhs, block)
    let src2 = ctx.get_vreg_for_use(mul_rhs, block)
    let machv_inst = @instr.Inst(if is_64 { Madd } else { Madd32 })
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(acc)) // accumulator
    machv_inst.add_use(Virtual(src1)) // multiplicand
    machv_inst.add_use(Virtual(src2)) // multiplier
    block.add_inst(machv_inst)
    return
  }

  // Pattern: add(mul(x, y), z) -> MADD / MADD32 (commutative).
  if match_mul_value(ctx, lhs_val) is Some((mul_lhs, mul_rhs)) {
    let acc = ctx.get_vreg_for_use(rhs_val, block)
    let src1 = ctx.get_vreg_for_use(mul_lhs, block)
    let src2 = ctx.get_vreg_for_use(mul_rhs, block)
    let machv_inst = @instr.Inst(if is_64 { Madd } else { Madd32 })
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(acc))
    machv_inst.add_use(Virtual(src1))
    machv_inst.add_use(Virtual(src2))
    block.add_inst(machv_inst)
    return
  }

  // Pattern: add(x, shl(y, n)) -> AddShifted/AddShifted32
  if match_shl_const_value(ctx, rhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(lhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let machv_inst = @instr.Inst(
      if is_64 {
        AddShifted(Lsl, amount)
      } else {
        AddShifted32(Lsl, amount)
      },
    )
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rn))
    machv_inst.add_use(Virtual(rm))
    block.add_inst(machv_inst)
    return
  }

  // Pattern: add(shl(x, n), y) -> AddShifted/AddShifted32 (commutative)
  if match_shl_const_value(ctx, lhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(rhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let machv_inst = @instr.Inst(
      if is_64 {
        AddShifted(Lsl, amount)
      } else {
        AddShifted32(Lsl, amount)
      },
    )
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rn))
    machv_inst.add_use(Virtual(rm))
    block.add_inst(machv_inst)
    return
  }

  // Pattern: add(x, uextend/sextend(i32)) -> AddExtend (i64 only).
  if is_64 &&
    match_extend_i32_to_i64(ctx, rhs_val) is Some((inner, ext)) &&
    !(ext is None) {
    let rn = ctx.get_vreg_for_use(lhs_val, block)
    let rm = ctx.get_vreg_for_use(inner, block)
    let machv_inst = @instr.Inst(AddExtend(ext, 0))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rn))
    machv_inst.add_use(Virtual(rm))
    block.add_inst(machv_inst)
    return
  }

  // Pattern: add(uextend/sextend(i32), x) -> AddExtend (commutative, i64 only).
  if is_64 &&
    match_extend_i32_to_i64(ctx, lhs_val) is Some((inner, ext)) &&
    !(ext is None) {
    let rn = ctx.get_vreg_for_use(rhs_val, block)
    let rm = ctx.get_vreg_for_use(inner, block)
    let machv_inst = @instr.Inst(AddExtend(ext, 0))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rn))
    machv_inst.add_use(Virtual(rm))
    block.add_inst(machv_inst)
    return
  }

  // Match Cranelift immediate-negation canonicalization:
  // add(x, -C) -> sub #C, x when C is encodable for current ISA.
  if match_negated_add_imm_value(ctx, rhs_val) is Some(imm_val) {
    let lhs = ctx.get_vreg_for_use(lhs_val, block)
    let machv_inst = @instr.Inst(SubImm(imm_val.to_int(), is_64))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(lhs))
    block.add_inst(machv_inst)
    return
  }

  if match_negated_add_imm_value(ctx, lhs_val) is Some(imm_val) {
    let rhs = ctx.get_vreg_for_use(rhs_val, block)
    let machv_inst = @instr.Inst(SubImm(imm_val.to_int(), is_64))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rhs))
    block.add_inst(machv_inst)
    return
  }

  // Pattern: add(x, const) -> AddImm where const is encodable for current ISA.
  if match_add_imm_value(ctx, rhs_val) is Some(imm_val) {
    let lhs = ctx.get_vreg_for_use(lhs_val, block)
    let machv_inst = @instr.Inst(AddImm(imm_val.to_int(), is_64))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(lhs))
    block.add_inst(machv_inst)
    return
  }

  // Pattern: add(const, x) -> AddImm (commutative)
  if match_add_imm_value(ctx, lhs_val) is Some(imm_val) {
    let rhs = ctx.get_vreg_for_use(rhs_val, block)
    let machv_inst = @instr.Inst(AddImm(imm_val.to_int(), is_64))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rhs))
    block.add_inst(machv_inst)
    return
  }

  // Default: regular add
  let lhs = ctx.get_vreg_for_use(lhs_val, block)
  let rhs = ctx.get_vreg_for_use(rhs_val, block)
  let machv_inst = @instr.Inst(Add(is_64))
  machv_inst.add_def({ reg: Virtual(dst) })
  machv_inst.add_use(Virtual(lhs))
  machv_inst.add_use(Virtual(rhs))
  block.add_inst(machv_inst)
}

///|
/// Lower integer multiply with proper 32/64-bit size
fn lower_imul(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
  let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
  let is_64 = result.ty is I64
  let machv_inst = @instr.Inst(Mul(is_64))
  machv_inst.add_def({ reg: Virtual(dst) })
  machv_inst.add_use(Virtual(lhs))
  machv_inst.add_use(Virtual(rhs))
  block.add_inst(machv_inst)
}

///|
fn lower_umulh(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
  let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
  if ctx.isa is AMD64 {
    // Match Cranelift x64: use MUL with implicit RAX/RDX.
    //
    // Result (high 64 bits) is produced in RDX. Keep both inputs as ordinary
    // uses; the amd64 emitter moves lhs into RAX and preserves rhs if needed.
    let machv_inst = @instr.Inst(Umulh)
    machv_inst.add_def_fixed({ reg: Virtual(dst) }, { index: 2, class: Int }) // rdx
    machv_inst.add_use(Virtual(lhs))
    machv_inst.add_use(Virtual(rhs))
    // Clobbers: rax is the implicit low-half output; rdx is the fixed result.
    machv_inst.add_def({ reg: Physical({ index: 0, class: Int }) })
    block.add_inst(machv_inst)
    return
  }
  lower_binary_int(ctx, inst, block, Umulh)
}

///|
fn lower_smulh(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
  let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
  if ctx.isa is AMD64 {
    // Match Cranelift x64: use one-operand IMUL with implicit RAX/RDX.
    //
    // Result (high 64 bits) is produced in RDX. Keep both inputs as ordinary
    // uses; the amd64 emitter moves lhs into RAX and preserves rhs if needed.
    let machv_inst = @instr.Inst(Smulh)
    machv_inst.add_def_fixed({ reg: Virtual(dst) }, { index: 2, class: Int }) // rdx
    machv_inst.add_use(Virtual(lhs))
    machv_inst.add_use(Virtual(rhs))
    // Clobbers: rax is the implicit low-half output; rdx is the fixed result.
    machv_inst.add_def({ reg: Physical({ index: 0, class: Int }) })
    block.add_inst(machv_inst)
    return
  }
  lower_binary_int(ctx, inst, block, Smulh)
}

///|
/// Lower integer sub with pattern matching for MSUB, MNEG, and shifted operands
/// Patterns:
/// - sub(x, mul(y, z)) -> MSUB: x - y * z
/// - sub(0, mul(x, y)) -> MNEG: -(x * y)
/// - sub(x, shl(y, n)) -> SubShifted: x - (y << n)
/// - sub(x, uextend/sextend(i32)) -> SubExtend (i64 only)
fn lower_isub(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]
  let is_64 = result.ty is I64
  let enable_subextend_fusion = true

  // Cranelift algebraic cancelation: (x + y) - y -> x.
  if match_add_sub_cancel_value(ctx, lhs_val, rhs_val) is Some(base) {
    let src = ctx.get_vreg_for_use(base, block)
    let move_inst = @instr.Inst(Move)
    move_inst.add_def({ reg: Virtual(dst) })
    move_inst.add_use(Virtual(src))
    block.add_inst(move_inst)
    return
  }
  let lhs_reg : @abi.Reg = if ctx.isa is AArch64 &&
    is_const_zero_value(ctx, lhs_val) {
    // Cranelift-style negation path: use xzr/wzr directly for `0 - x`.
    Physical({ index: 31, class: Int })
  } else {
    Virtual(ctx.get_vreg_for_use(lhs_val, block))
  }
  let lhs_is_aarch64_zero_reg = match lhs_reg {
    Physical(preg) => ctx.isa is AArch64 && preg.index == 31
    _ => false
  }

  // Pattern: sub(0, mul(x, y)) -> MNEG / MNEG32.
  // Match Cranelift's ineg(imul()) lowering for fits_in_64.
  if is_const_zero_value(ctx, lhs_val) &&
    match_mul_value(ctx, rhs_val) is Some((mul_lhs, mul_rhs)) {
    let src1 = ctx.get_vreg_for_use(mul_lhs, block)
    let src2 = ctx.get_vreg_for_use(mul_rhs, block)
    let machv_inst = @instr.Inst(if is_64 { Mneg } else { Mneg32 })
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(src1))
    machv_inst.add_use(Virtual(src2))
    block.add_inst(machv_inst)
    return
  }

  // Pattern: sub(x, mul(y, z)) -> MSUB / MSUB32.
  if match_mul_value(ctx, rhs_val) is Some((mul_lhs, mul_rhs)) {
    let acc = ctx.get_vreg_for_use(lhs_val, block)
    let src1 = ctx.get_vreg_for_use(mul_lhs, block)
    let src2 = ctx.get_vreg_for_use(mul_rhs, block)
    let machv_inst = @instr.Inst(if is_64 { Msub } else { Msub32 })
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(acc))
    machv_inst.add_use(Virtual(src1))
    machv_inst.add_use(Virtual(src2))
    block.add_inst(machv_inst)
    return
  }

  // Pattern: sub(x, shl(y, n)) -> SubShifted/SubShifted32
  if match_shl_const_value(ctx, rhs_val) is Some((shifted, amount)) {
    let rm = ctx.get_vreg_for_use(shifted, block)
    let machv_inst = @instr.Inst(
      if is_64 {
        SubShifted(Lsl, amount)
      } else {
        SubShifted32(Lsl, amount)
      },
    )
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(lhs_reg)
    machv_inst.add_use(Virtual(rm))
    block.add_inst(machv_inst)
    return
  }

  // Pattern: sub(x, uextend/sextend(i32)) -> SubExtend (i64 only).
  if enable_subextend_fusion &&
    is_64 &&
    !lhs_is_aarch64_zero_reg &&
    match_extend_i32_to_i64(ctx, rhs_val) is Some((inner, ext)) &&
    !(ext is None) {
    let rm = ctx.get_vreg_for_use(inner, block)
    let machv_inst = @instr.Inst(SubExtend(ext, 0))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(lhs_reg)
    machv_inst.add_use(Virtual(rm))
    block.add_inst(machv_inst)
    return
  }

  // Match Cranelift immediate-negation canonicalization:
  // sub(x, -C) -> add #C, x when C is encodable for current ISA.
  if match_negated_add_imm_value(ctx, rhs_val) is Some(imm_val) {
    let machv_inst = @instr.Inst(AddImm(imm_val.to_int(), is_64))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(lhs_reg)
    block.add_inst(machv_inst)
    return
  }

  // Pattern: sub(x, const) -> SubImm where const is encodable for current ISA.
  if match_add_imm_value(ctx, rhs_val) is Some(imm_val) {
    let machv_inst = @instr.Inst(SubImm(imm_val.to_int(), is_64))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(lhs_reg)
    block.add_inst(machv_inst)
    return
  }

  // Default: regular sub
  let rhs = ctx.get_vreg_for_use(rhs_val, block)
  let machv_inst = @instr.Inst(Sub(is_64))
  machv_inst.add_def({ reg: Virtual(dst) })
  machv_inst.add_use(lhs_reg)
  machv_inst.add_use(Virtual(rhs))
  block.add_inst(machv_inst)
}

///|
/// Lower bitwise AND with pattern matching for shifted operands
fn lower_band(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]
  let is_64 = is_64_bit_word_type(result.ty)
  let isa = ctx.isa

  // Pattern: and(x, const) -> AndImm if const is encodable as a logical immediate.
  if get_const_value(ctx, rhs_val) is Some(imm) &&
    is_valid_logic_imm_for_isa(isa, imm, is_64) {
    let lhs = ctx.get_vreg_for_use(lhs_val, block)
    let machv_inst = @instr.Inst(AndImm(imm, is_64))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(lhs))
    block.add_inst(machv_inst)
    return
  }

  // Pattern: and(const, x) -> AndImm (commutative).
  if get_const_value(ctx, lhs_val) is Some(imm) &&
    is_valid_logic_imm_for_isa(isa, imm, is_64) {
    let rhs = ctx.get_vreg_for_use(rhs_val, block)
    let machv_inst = @instr.Inst(AndImm(imm, is_64))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rhs))
    block.add_inst(machv_inst)
    return
  }

  // Pattern: and(x, bnot(y)) -> AndNot
  if match_bnot_value(ctx, rhs_val) is Some(not_src) {
    let rn = ctx.get_vreg_for_use(lhs_val, block)
    let rm = ctx.get_vreg_for_use(not_src, block)
    let machv_inst = @instr.Inst(AndNot(is_64))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rn))
    machv_inst.add_use(Virtual(rm))
    block.add_inst(machv_inst)
    return
  }

  // Pattern: and(bnot(y), x) -> AndNot
  if match_bnot_value(ctx, lhs_val) is Some(not_src) {
    let rn = ctx.get_vreg_for_use(rhs_val, block)
    let rm = ctx.get_vreg_for_use(not_src, block)
    let machv_inst = @instr.Inst(AndNot(is_64))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rn))
    machv_inst.add_use(Virtual(rm))
    block.add_inst(machv_inst)
    return
  }

  // Pattern: and(x, shl(y, n)) -> AndShifted/AndShifted32
  if match_shl_const_value(ctx, rhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(lhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let machv_inst = @instr.Inst(
      if is_64 {
        AndShifted(Lsl, amount)
      } else {
        AndShifted32(Lsl, amount)
      },
    )
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rn))
    machv_inst.add_use(Virtual(rm))
    block.add_inst(machv_inst)
    return
  }

  // Pattern: and(shl(x, n), y) -> AndShifted/AndShifted32 (commutative)
  if match_shl_const_value(ctx, lhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(rhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let machv_inst = @instr.Inst(
      if is_64 {
        AndShifted(Lsl, amount)
      } else {
        AndShifted32(Lsl, amount)
      },
    )
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rn))
    machv_inst.add_use(Virtual(rm))
    block.add_inst(machv_inst)
    return
  }

  // Default: regular and
  let lhs = ctx.get_vreg_for_use(lhs_val, block)
  let rhs = ctx.get_vreg_for_use(rhs_val, block)
  let machv_inst = @instr.Inst(And(is_64))
  machv_inst.add_def({ reg: Virtual(dst) })
  machv_inst.add_use(Virtual(lhs))
  machv_inst.add_use(Virtual(rhs))
  block.add_inst(machv_inst)
}

///|
/// Lower bitwise OR with pattern matching for shifted operands
fn lower_bor(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]
  let is_64 = is_64_bit_word_type(result.ty)
  let isa = ctx.isa

  // Pattern: or(x, const) -> OrImm if const is encodable as a logical immediate.
  if get_const_value(ctx, rhs_val) is Some(imm) &&
    is_valid_logic_imm_for_isa(isa, imm, is_64) {
    let lhs = ctx.get_vreg_for_use(lhs_val, block)
    let machv_inst = @instr.Inst(OrImm(imm, is_64))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(lhs))
    block.add_inst(machv_inst)
    return
  }

  // Pattern: or(const, x) -> OrImm (commutative).
  if get_const_value(ctx, lhs_val) is Some(imm) &&
    is_valid_logic_imm_for_isa(isa, imm, is_64) {
    let rhs = ctx.get_vreg_for_use(rhs_val, block)
    let machv_inst = @instr.Inst(OrImm(imm, is_64))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rhs))
    block.add_inst(machv_inst)
    return
  }

  // Pattern: or(x, bnot(y)) -> OrNot
  if match_bnot_value(ctx, rhs_val) is Some(not_src) {
    let rn = ctx.get_vreg_for_use(lhs_val, block)
    let rm = ctx.get_vreg_for_use(not_src, block)
    let machv_inst = @instr.Inst(OrNot(is_64))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rn))
    machv_inst.add_use(Virtual(rm))
    block.add_inst(machv_inst)
    return
  }

  // Pattern: or(bnot(y), x) -> OrNot
  if match_bnot_value(ctx, lhs_val) is Some(not_src) {
    let rn = ctx.get_vreg_for_use(rhs_val, block)
    let rm = ctx.get_vreg_for_use(not_src, block)
    let machv_inst = @instr.Inst(OrNot(is_64))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rn))
    machv_inst.add_use(Virtual(rm))
    block.add_inst(machv_inst)
    return
  }

  // Cranelift-style rotate idiom:
  // (x << a) | (x >> b), with a + b == bitwidth  ==>  rotr x, #b
  if match_rotate_or_value(ctx, lhs_val, rhs_val, is_64)
    is Some((src, rotr_amt)) {
    let rn = ctx.get_vreg_for_use(src, block)
    let machv_inst = @instr.Inst(RotrImm(rotr_amt, is_64))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rn))
    block.add_inst(machv_inst)
    return
  }

  // Cranelift-style EXTR idiom:
  // (x << a) | (y >> b), with a + b == bitwidth  ==>  extr x, y, #b
  // Reference: cranelift/codegen/src/isa/aarch64/lower.isle
  //   rule: (bor (ishl x xs) (ushr y ys)) -> a64_extr x y ys
  if match_extr_or_value(ctx, lhs_val, rhs_val, is_64)
    is Some((x_src, y_src, extr_amt)) {
    let rn = ctx.get_vreg_for_use(x_src, block)
    let rm = ctx.get_vreg_for_use(y_src, block)
    let machv_inst = @instr.Inst(ExtrImm(extr_amt, is_64))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rn))
    machv_inst.add_use(Virtual(rm))
    block.add_inst(machv_inst)
    return
  }

  // Pattern: or(x, shl(y, n)) -> OrShifted/OrShifted32
  if match_shl_const_value(ctx, rhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(lhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let machv_inst = @instr.Inst(
      if is_64 {
        OrShifted(Lsl, amount)
      } else {
        OrShifted32(Lsl, amount)
      },
    )
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rn))
    machv_inst.add_use(Virtual(rm))
    block.add_inst(machv_inst)
    return
  }

  // Pattern: or(shl(x, n), y) -> OrShifted/OrShifted32 (commutative)
  if match_shl_const_value(ctx, lhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(rhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let machv_inst = @instr.Inst(
      if is_64 {
        OrShifted(Lsl, amount)
      } else {
        OrShifted32(Lsl, amount)
      },
    )
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rn))
    machv_inst.add_use(Virtual(rm))
    block.add_inst(machv_inst)
    return
  }

  // Default: regular or
  let lhs = ctx.get_vreg_for_use(lhs_val, block)
  let rhs = ctx.get_vreg_for_use(rhs_val, block)
  let machv_inst = @instr.Inst(Or(is_64))
  machv_inst.add_def({ reg: Virtual(dst) })
  machv_inst.add_use(Virtual(lhs))
  machv_inst.add_use(Virtual(rhs))
  block.add_inst(machv_inst)
}

///|
/// Lower bitwise XOR with pattern matching for shifted operands
fn lower_bxor(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let lhs_val = inst.operands[0]
  let rhs_val = inst.operands[1]
  let is_64 = is_64_bit_word_type(result.ty)
  let isa = ctx.isa

  // Pattern: xor(x, const) -> XorImm if const is encodable as a logical immediate.
  if get_const_value(ctx, rhs_val) is Some(imm) &&
    is_valid_logic_imm_for_isa(isa, imm, is_64) {
    let lhs = ctx.get_vreg_for_use(lhs_val, block)
    let machv_inst = @instr.Inst(XorImm(imm, is_64))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(lhs))
    block.add_inst(machv_inst)
    return
  }

  // Pattern: xor(const, x) -> XorImm (commutative).
  if get_const_value(ctx, lhs_val) is Some(imm) &&
    is_valid_logic_imm_for_isa(isa, imm, is_64) {
    let rhs = ctx.get_vreg_for_use(rhs_val, block)
    let machv_inst = @instr.Inst(XorImm(imm, is_64))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rhs))
    block.add_inst(machv_inst)
    return
  }

  // Pattern: xor(x, bnot(y)) -> XorNot
  if match_bnot_value(ctx, rhs_val) is Some(not_src) {
    let rn = ctx.get_vreg_for_use(lhs_val, block)
    let rm = ctx.get_vreg_for_use(not_src, block)
    let machv_inst = @instr.Inst(XorNot(is_64))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rn))
    machv_inst.add_use(Virtual(rm))
    block.add_inst(machv_inst)
    return
  }

  // Pattern: xor(bnot(y), x) -> XorNot
  if match_bnot_value(ctx, lhs_val) is Some(not_src) {
    let rn = ctx.get_vreg_for_use(rhs_val, block)
    let rm = ctx.get_vreg_for_use(not_src, block)
    let machv_inst = @instr.Inst(XorNot(is_64))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rn))
    machv_inst.add_use(Virtual(rm))
    block.add_inst(machv_inst)
    return
  }

  // Pattern: xor(x, shl(y, n)) -> XorShifted/XorShifted32
  if match_shl_const_value(ctx, rhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(lhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let machv_inst = @instr.Inst(
      if is_64 {
        XorShifted(Lsl, amount)
      } else {
        XorShifted32(Lsl, amount)
      },
    )
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rn))
    machv_inst.add_use(Virtual(rm))
    block.add_inst(machv_inst)
    return
  }

  // Pattern: xor(shl(x, n), y) -> XorShifted/XorShifted32 (commutative)
  if match_shl_const_value(ctx, lhs_val) is Some((shifted, amount)) {
    let rn = ctx.get_vreg_for_use(rhs_val, block)
    let rm = ctx.get_vreg_for_use(shifted, block)
    let machv_inst = @instr.Inst(
      if is_64 {
        XorShifted(Lsl, amount)
      } else {
        XorShifted32(Lsl, amount)
      },
    )
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(rn))
    machv_inst.add_use(Virtual(rm))
    block.add_inst(machv_inst)
    return
  }

  // Default: regular xor
  let lhs = ctx.get_vreg_for_use(lhs_val, block)
  let rhs = ctx.get_vreg_for_use(rhs_val, block)
  let machv_inst = @instr.Inst(Xor(is_64))
  machv_inst.add_def({ reg: Virtual(dst) })
  machv_inst.add_use(Virtual(lhs))
  machv_inst.add_use(Virtual(rhs))
  block.add_inst(machv_inst)
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
  inst : @milkir.Inst,
  block : @block.Block,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let src = ctx.get_vreg_for_use(inst.operands[0], block)
  let is_64 = result.ty is I64
  let mask = if is_64 { 63 } else { 31 }

  // Cranelift-style: for constant shift amounts, emit a single rotate-immediate.
  // rotl(x, k) = rotr(x, (bits - k) & mask).
  if get_const_value(ctx, inst.operands[1]) is Some(k_imm) {
    let k = k_imm.to_int() & mask
    if k == 0 {
      let mov = @instr.Inst(Move)
      mov.add_def({ reg: Virtual(dst) })
      mov.add_use(Virtual(src))
      block.add_inst(mov)
      return
    }
    let bits = if is_64 { 64 } else { 32 }
    let rotr_k = (bits - k) & mask
    let ror = @instr.Inst(RotrImm(rotr_k, is_64))
    ror.add_def({ reg: Virtual(dst) })
    ror.add_use(Virtual(src))
    block.add_inst(ror)
    return
  }
  let amount = ctx.get_vreg_for_use(inst.operands[1], block)

  // Step 1: Compute (0 - n) = -n.
  // AArch64 can use the zero register directly (`xzr/wzr`) as the lhs.
  // Keep the previous generic path for other ISAs.
  let neg_n = ctx.machv_func.new_vreg(Int)
  let sub_inst = @instr.Inst(Sub(is_64))
  sub_inst.add_def({ reg: Virtual(neg_n) })
  if ctx.isa is AArch64 {
    sub_inst.add_use(Physical({ index: 31, class: Int }))
  } else {
    let zero = ctx.machv_func.new_vreg(Int)
    let load_zero = @instr.Inst(LoadConst(0L))
    load_zero.add_def({ reg: Virtual(zero) })
    block.add_inst(load_zero)
    sub_inst.add_use(Virtual(zero))
  }
  sub_inst.add_use(Virtual(amount))
  block.add_inst(sub_inst)

  // Step 2: Rotate right by -n (effectively rotl by n)
  let rotr_inst = @instr.Inst(Rotr(is_64))
  if ctx.isa is AMD64 {
    // x86_64 variable shifts/rotates use CL as the implicit count register.
    // Keep rotate source/dest away from rcx (count register).
    let shift_data : @abi.PReg = {
      index: ctx.isa.scratch_reg_1_index(),
      class: Int,
    }
    rotr_inst.add_def_fixed({ reg: Virtual(dst) }, shift_data)
    rotr_inst.add_use_fixed(Virtual(src), shift_data)
    rotr_inst.add_use_fixed(Virtual(neg_n), { index: 1, class: Int }) // rcx
  } else {
    rotr_inst.add_def({ reg: Virtual(dst) })
    rotr_inst.add_use(Virtual(src))
    rotr_inst.add_use(Virtual(neg_n))
  }
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
  inst : @milkir.Inst,
  block : @block.Block,
) -> Unit {
  guard inst.first_result() is Some(result) else { return }
  let dst = ctx.get_vreg(result)
  let src = ctx.get_vreg_for_use(inst.operands[0], block)
  let is_64 = result.ty is I64

  // Step 1: Reverse bits
  let reversed = ctx.machv_func.new_vreg(Int)
  let rbit_inst = @instr.Inst(Rbit(is_64))
  rbit_inst.add_def({ reg: Virtual(reversed) })
  rbit_inst.add_use(Virtual(src))
  block.add_inst(rbit_inst)

  // Step 2: Count leading zeros
  let clz_inst = @instr.Inst(Clz(is_64))
  clz_inst.add_def({ reg: Virtual(dst) })
  clz_inst.add_use(Virtual(reversed))
  block.add_inst(clz_inst)
}

///|
/// Lower binary float operation
fn lower_binary_float(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  scalar_op : @milkir.FloatBinaryOp,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let lhs = ctx.get_vreg_for_use(inst.operands[0], block)
    let rhs = ctx.get_vreg_for_use(inst.operands[1], block)
    // Determine if this is f32 based on result type
    let is_f32 = result.ty is F32
    // Select MachV opcode based on IR opcode
    let opcode : @instr.Opcode = match scalar_op {
      Add => FAdd(is_f32)
      Sub => FSub(is_f32)
      Mul => FMul(is_f32)
      Div => FDiv(is_f32)
      Min => FMin(is_f32)
      Max => FMax(is_f32)
    }
    let machv_inst = @instr.Inst(opcode)
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(lhs))
    machv_inst.add_use(Virtual(rhs))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower floating-point unary operation (sqrt, abs, neg, ceil, floor, trunc, nearest, promote, demote)
fn lower_unary_float(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  scalar_op : @milkir.FloatUnaryOp,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    // Determine if this is f32 based on result type
    let is_f32 = result.ty is F32
    // Select MachV opcode based on IR opcode
    let opcode : @instr.Opcode = match scalar_op {
      Sqrt => FSqrt(is_f32)
      Abs => FAbs(is_f32)
      Neg => FNeg(is_f32)
      Ceil => FCeil(is_f32)
      Floor => FFloor(is_f32)
      Trunc => FTrunc(is_f32)
      Nearest => FNearest(is_f32)
    }
    let machv_inst = @instr.Inst(opcode)
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(src))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower f32 to f64 promotion
fn lower_promote(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let machv_inst = @instr.Inst(FPromote)
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(src))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower f64 to f32 demotion
fn lower_demote(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let machv_inst = @instr.Inst(FDemote)
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(src))
    block.add_inst(machv_inst)
  }
}

///|
/// Lower integer unary operation (not) with proper 32/64-bit selection
fn lower_unary_int(
  ctx : LoweringContext,
  inst : @milkir.Inst,
  block : @block.Block,
  make_opcode : (Bool) -> @instr.Opcode,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let is_64 = result.ty is I64
    let machv_inst = @instr.Inst(make_opcode(is_64))
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(src))
    block.add_inst(machv_inst)
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
  inst : @milkir.Inst,
  block : @block.Block,
  signed : Bool,
) -> Unit {
  let lhs = ctx.get_vreg_for_use(inst.operands[0], block) // a (dividend)
  let rhs = ctx.get_vreg_for_use(inst.operands[1], block) // b (divisor)
  let is_64 = inst.operands[0].ty is I64
  let use_fixed_divisor = ctx.isa is AMD64
  let divisor_preg : @abi.PReg = { index: scratch1_index(ctx), class: Int }

  // Trap if divisor is zero (trap_code 4 = integer divide by zero)
  // Must always emit even if result is unused (for side effect)
  let trap_zero = @instr.Inst(TrapIfZero(is_64, 4))
  if use_fixed_divisor {
    trap_zero.add_use_fixed(Virtual(rhs), divisor_preg)
  } else {
    trap_zero.add_use(Virtual(rhs))
  }
  block.add_inst(trap_zero)

  // Only emit remainder computation if result is used
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    if ctx.isa is AMD64 {
      // Match Cranelift x64: use IDIV/DIV remainder directly.
      //
      // Note: the remainder value is produced in RDX/EDX by the hardware.
      let opcode = if signed { @instr.SRem(is_64) } else { URem(is_64) }
      let rem_inst = @instr.Inst(opcode)
      rem_inst.add_def_fixed({ reg: Virtual(dst) }, { index: 2, class: Int }) // rdx
      rem_inst.add_use_fixed(Virtual(lhs), { index: 0, class: Int }) // rax
      rem_inst.add_use_fixed(Virtual(rhs), divisor_preg)
      // Clobbers: rax/rdx are implicit in div/idiv.
      rem_inst.add_def({ reg: Physical({ index: 0, class: Int }) })
      rem_inst.add_def({ reg: Physical({ index: 2, class: Int }) })
      block.add_inst(rem_inst)
      return
    }

    // Step 1: Compute quotient = a / b
    let quotient = ctx.machv_func.new_vreg(Int)
    let div_opcode = if signed { @instr.SDiv(is_64) } else { UDiv(is_64) }
    let div_inst = @instr.Inst(div_opcode)
    div_inst.add_def({ reg: Virtual(quotient) })
    div_inst.add_use(Virtual(lhs))
    div_inst.add_use(Virtual(rhs))
    block.add_inst(div_inst)

    // Step 2: Compute remainder = a - quotient * b
    // - For i64, use MSUB (single instruction): a - quotient*b
    // - For i32, avoid MSUB because our MSUB opcode is 64-bit (X regs) and
    //   would mis-handle signed values by zero-extending w-reg results.
    if is_64 && !(ctx.isa is AMD64) {
      // MSUB rd, rn, rm, ra computes: ra - rn * rm
      // We want: a - quotient * b, so: ra=a, rn=quotient, rm=b
      let msub_inst = @instr.Inst(Msub)
      msub_inst.add_def({ reg: Virtual(dst) })
      msub_inst.add_use(Virtual(lhs)) // accumulator (a)
      msub_inst.add_use(Virtual(quotient)) // multiplicand
      msub_inst.add_use(Virtual(rhs)) // multiplier (b)
      block.add_inst(msub_inst)
    } else {
      let product = ctx.machv_func.new_vreg(Int)
      let mul_inst = @instr.Inst(Mul(is_64))
      mul_inst.add_def({ reg: Virtual(product) })
      mul_inst.add_use(Virtual(quotient))
      mul_inst.add_use(Virtual(rhs))
      block.add_inst(mul_inst)
      let sub_inst = @instr.Inst(Sub(is_64))
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
  inst : @milkir.Inst,
  block : @block.Block,
) -> Unit {
  if inst.first_result() is Some(result) {
    let dst = ctx.get_vreg(result)
    let src = ctx.get_vreg_for_use(inst.operands[0], block)
    let machv_inst = if dst.class == src.class {
      @instr.Inst(Move)
    } else {
      @instr.Inst(Bitcast)
    }
    machv_inst.add_def({ reg: Virtual(dst) })
    machv_inst.add_use(Virtual(src))
    block.add_inst(machv_inst)
  }
}
