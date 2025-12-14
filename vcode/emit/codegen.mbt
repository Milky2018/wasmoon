// Code Generation
// Translates VCode to machine code

///|
fn collect_used_callee_saved(
  func : @lower.VCodeFunction,
  needs_extra_results : Bool,
) -> Array[Int] {
  let used : @hashset.HashSet[Int] = @hashset.new()
  let mut has_calls = false

  // Check param_pregs: parameters that cross calls are moved to callee-saved registers
  // These are defined in the prologue via `mov xN, x(3+i)`
  for preg in func.param_pregs {
    match preg {
      Some(p) =>
        if is_callee_saved_alloc(p.index) {
          // X23 is reserved for extra_buffer when needs_extra_results
          if needs_extra_results && p.index == 23 {
            continue
          }
          used.add(p.index)
        }
      None => ()
    }
  }
  for block in func.blocks {
    for inst in block.insts {
      // Check if this instruction is a function call
      // MemoryGrow and MemorySize also use BLR internally to call C functions
      if inst.opcode is (CallIndirect(_, _) | MemoryGrow(_) | MemorySize) {
        has_calls = true
      }
      for def in inst.defs {
        match def.reg {
          Physical(preg) =>
            if preg.class is Int && is_callee_saved_alloc(preg.index) {
              // X23 is reserved for extra_buffer when needs_extra_results
              if needs_extra_results && preg.index == 23 {
                continue
              }
              used.add(preg.index)
            }
          Virtual(_) => ()
        }
      }
    }
  }
  // If the function makes any calls, we must save LR (X30)
  if has_calls {
    used.add(30)
  }
  // Sort the registers for consistent ordering
  let result : Array[Int] = []
  for reg in used {
    result.push(reg)
  }
  result.sort()
  result
}

///|
/// Collect all callee-saved FPRs (D8-D15) that are defined in the function
fn collect_used_callee_saved_fprs(func : @lower.VCodeFunction) -> Array[Int] {
  let used : @hashset.HashSet[Int] = @hashset.new()
  // Check param_pregs: float parameters that cross calls are moved to callee-saved FPRs
  // These are defined in the prologue via `fmov sN, wM` or `fmov dN, xM`
  for preg in func.param_pregs {
    match preg {
      Some(p) =>
        if (p.class is Float32 || p.class is Float64) &&
          is_callee_saved_fpr(p.index) {
          used.add(p.index)
        }
      None => ()
    }
  }
  for block in func.blocks {
    for inst in block.insts {
      for def in inst.defs {
        match def.reg {
          Physical(preg) =>
            if (preg.class is Float32 || preg.class is Float64) &&
              is_callee_saved_fpr(preg.index) {
              used.add(preg.index)
            }
          Virtual(_) => ()
        }
      }
    }
  }
  // Sort the registers for consistent ordering
  let result : Array[Int] = []
  for reg in used {
    result.push(reg)
  }
  result.sort()
  result
}

///|
/// Emit prologue to save callee-saved registers and set up parameters (v2 using JITStackFrame)
fn MachineCode::emit_prologue_v2(
  self : MachineCode,
  stack_frame : JITStackFrame,
  params : Array[@abi.VReg],
  param_pregs : Array[@abi.PReg?],
) -> Unit {
  // Use pre-calculated values from stack_frame
  let saved_gprs = stack_frame.saved_gprs
  let saved_fprs = stack_frame.saved_fprs
  let frame_size = stack_frame.total_size
  let fpr_save_offset = stack_frame.fpr_save_offset
  let needs_extra_results = stack_frame.needs_extra_results
  let calls_multi_value = stack_frame.calls_multi_value

  // Allocate stack frame first using SUB
  self.emit_sub_imm(31, 31, frame_size)

  // Save GPRs using STP with signed offset
  let num_regs = saved_gprs.length()
  let mut i = 0
  let mut pair_idx = 0
  while i < num_regs {
    let reg1 = saved_gprs[i]
    let reg2 = if i + 1 < num_regs { saved_gprs[i + 1] } else { 31 } // XZR as padding
    let offset = pair_idx * 16
    self.emit_stp_offset(reg1, reg2, 31, offset)
    i = i + 2
    pair_idx = pair_idx + 1
  }

  // Save FPRs (D8-D15) after GPRs
  let num_fprs = saved_fprs.length()
  let mut fi = 0
  let mut fpr_pair_idx = 0
  while fi + 1 < num_fprs {
    let reg1 = saved_fprs[fi]
    let reg2 = saved_fprs[fi + 1]
    let offset = fpr_save_offset + fpr_pair_idx * 16
    self.emit_stp_d_offset(reg1, reg2, 31, offset)
    fi = fi + 2
    fpr_pair_idx = fpr_pair_idx + 1
  }
  // Handle last register if odd count
  if fi < num_fprs {
    let reg = saved_fprs[fi]
    let offset = fpr_save_offset + fpr_pair_idx * 16
    self.emit_str_d_imm(reg, 31, offset)
  }

  // Now move parameters to reserved registers
  if @abi.ABI_VERSION == 2 {
    // v2 ABI: Load from context structure pointed by X19
    self.emit_ldr_imm(20, 19, @abi.CTX_FUNC_TABLE_OFFSET)
    self.emit_ldr_imm(21, 19, @abi.CTX_MEMORY_BASE_OFFSET)
    self.emit_ldr_imm(22, 19, @abi.CTX_MEMORY_SIZE_OFFSET)
    self.emit_ldr_imm(24, 19, @abi.CTX_INDIRECT_TABLE_OFFSET)
  } else {
    // v1 ABI
    self.emit_mov_reg(20, 0)
    self.emit_mov_reg(21, 1)
    self.emit_mov_reg(22, 2)
    self.emit_ldr_imm_signed(24, 20, -8)
  }

  // Set up X23 for extra results buffer
  if needs_extra_results {
    self.emit_mov_reg(23, 7)
  } else if calls_multi_value {
    let buffer_offset = stack_frame.call_buffer_offset
    self.emit_add_imm(23, 31, buffer_offset)
  }

  // Move user arguments from registers to their allocated registers
  let actual_param_base = if @abi.ABI_VERSION == 2 {
    @abi.PARAM_BASE_REG
  } else {
    @abi.LEGACY_PARAM_BASE_REG
  }
  let actual_max_reg_params = if @abi.ABI_VERSION == 2 {
    @abi.MAX_REG_PARAMS
  } else {
    @abi.LEGACY_MAX_REG_PARAMS
  }
  let mut int_idx = 0
  let mut float_idx = 0
  for param_idx, param in params {
    let dest_preg = if param_idx < param_pregs.length() {
      param_pregs[param_idx]
    } else {
      None
    }
    match param.class {
      Float32 | Float64 =>
        if float_idx < actual_max_reg_params {
          let x_src = actual_param_base + param_idx
          match param.class {
            Float32 => {
              let s_dest = match dest_preg {
                Some(preg) => preg.index
                None => float_idx
              }
              self.emit_fmov_w_to_s(s_dest, x_src)
            }
            _ => {
              let d_dest = match dest_preg {
                Some(preg) => preg.index
                None => float_idx
              }
              self.emit_fmov_x_to_d(d_dest, x_src)
            }
          }
          float_idx = float_idx + 1
        }
      Int =>
        if int_idx < actual_max_reg_params {
          let x_src = actual_param_base + param_idx
          match dest_preg {
            Some(preg) => self.emit_mov_reg(preg.index, x_src)
            None => ()
          }
          int_idx = int_idx + 1
        }
    }
  }
}

///|
/// Emit machine code for a VCode function
pub fn emit_function(func : @lower.VCodeFunction) -> MachineCode {
  let mc = MachineCode::new()
  // Check if we need extra results buffer (>2 int or >2 float returns)
  let needs_extra_results = func.needs_extra_results_ptr()
  // Check if we call functions that return more than 2 values
  // In that case, we need to allocate a local buffer and use X23 to point to it
  let calls_multi_value = func.calls_multi_value_function()
  // We need X23 if either we return multi-value OR we call multi-value functions
  let uses_x23 = needs_extra_results || calls_multi_value
  // Collect callee-saved GPRs that this function clobbers
  let clobbered = collect_used_callee_saved(func, uses_x23)
  // Collect callee-saved FPRs (D8-D15) that this function clobbers
  let clobbered_fprs = collect_used_callee_saved_fprs(func)

  // Build stack frame layout using JITStackFrame
  let stack_frame = JITStackFrame::build(
    clobbered,
    clobbered_fprs,
    func.num_spill_slots,
    needs_extra_results~,
    calls_multi_value~,
  )

  // Emit prologue: save callee-saved registers, set up X20/X21/X22, and move params
  mc.emit_prologue_v2(stack_frame, func.params, func.param_pregs)

  // Emit function body
  for block in func.blocks {
    mc.define_label(block.id)
    for inst in block.insts {
      mc.emit_instruction(inst, stack_frame)
    }
    match block.terminator {
      Some(term) =>
        mc.emit_terminator_with_epilogue_v2(
          term,
          stack_frame,
          func.result_types,
        )
      None => ()
    }
  }
  mc.resolve_fixups()
  mc
}

///|
fn MachineCode::emit_instruction(
  self : MachineCode,
  inst : @instr.VCodeInst,
  stack_frame : JITStackFrame,
) -> Unit {
  // Extract offsets from stack frame for backward compatibility
  let spill_base_offset = stack_frame.spill_offset
  let frame_size = stack_frame.total_size
  match inst.opcode {
    Add => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_add_reg(rd, rn, rm)
    }
    AddImm(imm) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.emit_add_imm(rd, rn, imm)
    }
    Sub => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_sub_reg(rd, rn, rm)
    }
    Mul => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_mul(rd, rn, rm)
    }
    SDiv => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_sdiv(rd, rn, rm)
    }
    UDiv => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_udiv(rd, rn, rm)
    }
    And => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_and_reg(rd, rn, rm)
    }
    Or => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_orr_reg(rd, rn, rm)
    }
    Xor => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_eor_reg(rd, rn, rm)
    }
    Shl => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_lsl_reg(rd, rn, rm)
    }
    AShr => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_asr_reg(rd, rn, rm)
    }
    LShr => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_lsr_reg(rd, rn, rm)
    }
    Rotr => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_ror_reg(rd, rn, rm)
    }
    Rotl => {
      // Rotate left by n is rotate right by (64 - n)
      // rotl(x, n) = rotr(x, 64 - n)
      // We need to compute 64 - rm, then rotate right
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      // Use scratch register x16 to compute (64 - rm)
      self.emit_movz(16, 64, 0) // x16 = 64
      self.emit_sub_reg(16, 16, rm) // x16 = 64 - rm
      self.emit_ror_reg(rd, rn, 16) // rd = rotr(rn, x16)
    }
    Not => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.emit_mvn(rd, rn)
    }
    SRem => {
      // Signed remainder: rem = a - (a / b) * b
      // Using MSUB: rd = ra - rn * rm
      // 1. Compute quotient: x16 = a / b (SDIV)
      // 2. Compute remainder: rd = a - x16 * b (MSUB)
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0]) // dividend (a)
      let rm = reg_num(inst.uses[1]) // divisor (b)
      self.emit_sdiv(16, rn, rm) // x16 = a / b
      self.emit_msub(rd, 16, rm, rn) // rd = a - x16 * b
    }
    URem => {
      // Unsigned remainder: rem = a - (a / b) * b
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0]) // dividend (a)
      let rm = reg_num(inst.uses[1]) // divisor (b)
      self.emit_udiv(16, rn, rm) // x16 = a / b (unsigned)
      self.emit_msub(rd, 16, rm, rn) // rd = a - x16 * b
    }
    Bitcast => {
      // Reinterpret bits between int and float
      // IMPORTANT: For f32 bitcast, we must preserve exact bits (including NaN payloads)
      // We store f32 as raw 32-bit pattern in lower bits of D register, NOT as promoted f64
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // Determine direction and size based on register classes
      let dest_class = match inst.defs[0].reg {
        Physical(preg) => preg.class
        Virtual(vreg) => vreg.class
      }
      let src_class = match inst.uses[0] {
        Physical(preg) => preg.class
        Virtual(vreg) => vreg.class
      }
      match (src_class, dest_class) {
        (Int, Float64) =>
          // i64 -> f64: FMOV Dd, Xn (bit-exact transfer)
          self.emit_fmov_x_to_d(rd, rn)
        (Float64, Int) =>
          // f64 -> i64: FMOV Xd, Dn (bit-exact transfer)
          self.emit_fmov_d_to_x(rd, rn)
        (Int, Float32) =>
          // i32 -> f32: Store raw f32 bits in D register
          // Use FMOV S, W which moves bits to lower 32 bits of D register
          // The upper 32 bits are zeroed, which is fine for our purposes
          // This preserves exact bit patterns including signaling NaNs
          self.emit_fmov_w_to_s(rd, rn) // FMOV Sd, Wn (bit-exact, no conversion)
        (Float32, Int) =>
          // f32 -> i32: Extract raw f32 bits from D register
          // Use FMOV W, S which extracts lower 32 bits
          // This preserves exact bit patterns including signaling NaNs
          self.emit_fmov_s_to_w(rd, rn) // FMOV Wd, Sn (bit-exact, no conversion)
        _ =>
          // Fallback for other cases (shouldn't happen with valid WASM)
          self.emit_fmov_x_to_d(rd, rn)
      }
    }
    FAdd(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        // For f32: operate directly on S registers (raw f32 bits)
        self.emit_fadd_s(rd, rn, rm)
      } else {
        self.emit_fadd_d(rd, rn, rm)
      }
    }
    FSub(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        self.emit_fsub_s(rd, rn, rm)
      } else {
        self.emit_fsub_d(rd, rn, rm)
      }
    }
    FMul(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        self.emit_fmul_s(rd, rn, rm)
      } else {
        self.emit_fmul_d(rd, rn, rm)
      }
    }
    FDiv(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        self.emit_fdiv_s(rd, rn, rm)
      } else {
        self.emit_fdiv_d(rd, rn, rm)
      }
    }
    FMin(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        self.emit_fmin_s(rd, rn, rm)
      } else {
        self.emit_fmin_d(rd, rn, rm)
      }
    }
    FMax(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        self.emit_fmax_s(rd, rn, rm)
      } else {
        self.emit_fmax_d(rd, rn, rm)
      }
    }
    // Floating-point unary operations
    FSqrt(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        self.emit_fsqrt_s(rd, rn)
      } else {
        self.emit_fsqrt_d(rd, rn)
      }
    }
    FAbs(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        self.emit_fabs_s(rd, rn)
      } else {
        self.emit_fabs_d(rd, rn)
      }
    }
    FNeg(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        // For f32: Use FNEG S directly to preserve exact bit patterns
        // Our f32 values are stored as raw bits in S registers (lower 32 bits of D)
        // FNEG S only flips the sign bit without changing NaN payloads
        self.emit_fneg_s(rd, rn)
      } else {
        self.emit_fneg_d(rd, rn)
      }
    }
    FCeil(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        self.emit_frintp_s(rd, rn)
      } else {
        self.emit_frintp_d(rd, rn)
      }
    }
    FFloor(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        self.emit_frintm_s(rd, rn)
      } else {
        self.emit_frintm_d(rd, rn)
      }
    }
    FTrunc(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        self.emit_frintz_s(rd, rn)
      } else {
        self.emit_frintz_d(rd, rn)
      }
    }
    FNearest(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        // For f32: operate directly on S registers (raw f32 bits)
        self.emit_frintn_s(rd, rn)
      } else {
        self.emit_frintn_d(rd, rn)
      }
    }
    // Floating-point conversions
    FPromote => {
      // f32 -> f64: Convert from S register (raw f32 bits) to D register (f64)
      // This is a real conversion using FCVT
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.emit_fcvt_d_s(rd, rn)
    }
    FDemote => {
      // f64 -> f32: Convert from D register (f64) to S register (raw f32 bits)
      // This is a real conversion using FCVT
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.emit_fcvt_s_d(rd, rn)
    }
    Load(ty, offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // F32 loads directly into S register (raw f32 bits preserved)
      self.emit_load(ty, rt, rn, offset)
    }
    Store(ty, offset) => {
      // uses[0] = address (Rn), uses[1] = value (Rt)
      let rn = reg_num(inst.uses[0]) // base address
      let rt = reg_num(inst.uses[1]) // value to store
      // F32 stores directly from S register (raw f32 bits preserved)
      self.emit_store(ty, rt, rn, offset)
    }
    // Narrow load operations (8/16/32-bit with sign/zero extension)
    Load8S(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // Sign-extend to 64-bit (use LDRSB Xt form)
      self.emit_ldrsb_x_imm(rt, rn, offset)
    }
    Load8U(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // Zero-extend (LDRB already zero-extends)
      self.emit_ldrb_imm(rt, rn, offset)
    }
    Load16S(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // Sign-extend to 64-bit (use LDRSH Xt form)
      self.emit_ldrsh_x_imm(rt, rn, offset)
    }
    Load16U(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // Zero-extend (LDRH already zero-extends)
      self.emit_ldrh_imm(rt, rn, offset)
    }
    Load32S(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // Sign-extend 32-bit to 64-bit
      self.emit_ldrsw_imm(rt, rn, offset)
    }
    Load32U(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // Zero-extend (LDR W already zero-extends to 64-bit)
      self.emit_ldr_w_imm(rt, rn, offset)
    }
    Move => {
      let rd = wreg_num(inst.defs[0])
      let rm = reg_num(inst.uses[0])
      // Check register class to use appropriate move instruction
      let reg_class = match inst.defs[0].reg {
        Physical(preg) => preg.class
        Virtual(_) => Int // Should not happen at emit time
      }
      match reg_class {
        Float32 => self.emit_fmov_s(rd, rm)
        Float64 => self.emit_fmov_d(rd, rm)
        Int => self.emit_mov_reg(rd, rm)
      }
    }
    LoadConst(v) => {
      let rd = wreg_num(inst.defs[0])
      self.emit_load_imm64(rd, v)
    }
    LoadConstF32(bits) => {
      // Load 32-bit float constant as raw bits into S register
      // 1. Load the 32-bit representation into a scratch W register (W16)
      // 2. FMOV from W16 to destination S register (bit-exact, no conversion)
      let rd = wreg_num(inst.defs[0])
      // Use X16 as scratch register, load the 32-bit value as unsigned
      self.emit_movz(16, bits & 0xFFFF, 0)
      let high = (bits >> 16) & 0xFFFF
      if high != 0 {
        self.emit_movk(16, high, 16)
      }
      // FMOV Sd, W16 (move 32-bit value to S register - bit-exact)
      self.emit_fmov_w_to_s(rd, 16)
    }
    LoadConstF64(bits) => {
      // Load 64-bit float constant:
      // 1. Load the 64-bit representation into a scratch X register (X16)
      // 2. FMOV from X16 to the destination D register
      let rd = wreg_num(inst.defs[0])
      // Use X16 as scratch register
      self.emit_load_imm64(16, bits)
      // FMOV Dd, Xn
      self.emit_fmov_x_to_d(rd, 16)
    }
    Cmp(kind) => {
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_cmp_reg(rn, rm)
      let rd = wreg_num(inst.defs[0])
      let cond = cmp_kind_to_cond(kind)
      self.emit_cset(rd, cond)
    }
    FCmp(kind) => {
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      // Check register class to use appropriate compare instruction
      let reg_class = match inst.uses[0] {
        Physical(preg) => preg.class
        Virtual(vreg) => vreg.class
      }
      match reg_class {
        Float32 => self.emit_fcmp_s(rn, rm)
        _ => self.emit_fcmp_d(rn, rm)
      }
      let rd = wreg_num(inst.defs[0])
      let cond = fcmp_kind_to_cond(kind)
      self.emit_cset(rd, cond)
    }
    Select => {
      // Select: dst = cond != 0 ? true_val : false_val
      // Uses: [cond, true_val, false_val]
      let rd = wreg_num(inst.defs[0])
      let cond_reg = reg_num(inst.uses[0])
      let true_val = reg_num(inst.uses[1])
      let false_val = reg_num(inst.uses[2])
      // Compare cond with 0: CMP cond, #0
      self.emit_cmp_imm(cond_reg, 0)
      // Check register class to use appropriate select instruction
      let reg_class = match inst.defs[0].reg {
        Physical(preg) => preg.class
        Virtual(_) => Int // Should not happen at emit time
      }
      match reg_class {
        Float32 =>
          // Use FCSEL S for single-precision
          self.emit_fcsel_s(rd, true_val, false_val, NE.to_int())
        Float64 =>
          // Use FCSEL D for double-precision
          self.emit_fcsel_d(rd, true_val, false_val, NE.to_int())
        Int =>
          // Use CSEL for integer registers
          self.emit_csel(rd, true_val, false_val, NE.to_int())
      }
    }
    Clz => {
      // Count leading zeros
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.emit_clz(rd, rn)
    }
    Ctz => {
      // Count trailing zeros: CTZ(x) = CLZ(RBIT(x))
      // First reverse the bits, then count leading zeros
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // Use X16 as scratch register
      self.emit_rbit(16, rn) // X16 = RBIT(rn)
      self.emit_clz(rd, 16) // rd = CLZ(X16)
    }
    Popcnt => {
      // Population count (count number of 1 bits)
      // AArch64 doesn't have a direct POPCNT for GPRs, we use SIMD:
      // 1. FMOV D16, Xn (move to vector register)
      // 2. CNT V16.8B, V16.8B (count bits in each byte)
      // 3. ADDV B17, V16.8B (sum all byte counts)
      // 4. FMOV Xd, D17 (move back to GPR)
      // For simplicity, we'll use a software fallback sequence
      // TODO: Implement proper SIMD version for better performance
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // For now, emit NOP and move the input to output (placeholder)
      // This needs proper implementation
      self.emit_mov_reg(rd, rn)
      self.emit_nop()
    }
    Extend(kind) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match kind {
        Signed8To32 => self.emit_sxtb_w(rd, rn)
        Signed8To64 => self.emit_sxtb_x(rd, rn)
        Signed16To32 => self.emit_sxth_w(rd, rn)
        Signed16To64 => self.emit_sxth_x(rd, rn)
        Signed32To64 => self.emit_sxtw(rd, rn)
        Unsigned8To32 => self.emit_uxtb_w(rd, rn)
        Unsigned8To64 => self.emit_uxtb_x(rd, rn)
        Unsigned16To32 => self.emit_uxth_w(rd, rn)
        Unsigned16To64 => self.emit_uxth_x(rd, rn)
        Unsigned32To64 =>
          // Zero-extend 32-bit to 64-bit: MOV Wd, Wn (W-write zero-extends to X)
          self.emit_mov_reg32(rd, rn)
      }
    }
    Truncate => {
      // Truncate from 64-bit to 32-bit: just use MOV Wd, Wn
      // The upper 32 bits are automatically zeroed
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.emit_mov_reg32(rd, rn)
    }
    FloatToInt(kind) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // f32 values are stored as raw bits in S registers
      // f64 values are stored in D registers
      match kind {
        F32ToI32S =>
          // S register contains f32, convert directly
          self.emit_fcvtzs(rd, rn, int64=false, double=false) // FCVTZS Wd, Sn
        F32ToI32U => self.emit_fcvtzu(rd, rn, int64=false, double=false)
        F32ToI64S => self.emit_fcvtzs(rd, rn, int64=true, double=false)
        F32ToI64U => self.emit_fcvtzu(rd, rn, int64=true, double=false)
        F64ToI32S => self.emit_fcvtzs(rd, rn, int64=false, double=true)
        F64ToI32U => self.emit_fcvtzu(rd, rn, int64=false, double=true)
        F64ToI64S => self.emit_fcvtzs(rd, rn, int64=true, double=true)
        F64ToI64U => self.emit_fcvtzu(rd, rn, int64=true, double=true)
      }
    }
    IntToFloat(kind) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // f32 results go directly to S registers
      // f64 results go directly to D registers
      match kind {
        I32SToF32 =>
          // Convert to S register directly
          self.emit_scvtf(rd, rn, int64=false, double=false) // SCVTF Sd, Wn
        I32UToF32 => self.emit_ucvtf(rd, rn, int64=false, double=false)
        I64SToF32 => self.emit_scvtf(rd, rn, int64=true, double=false)
        I64UToF32 => self.emit_ucvtf(rd, rn, int64=true, double=false)
        I32SToF64 => self.emit_scvtf(rd, rn, int64=false, double=true)
        I32UToF64 => self.emit_ucvtf(rd, rn, int64=false, double=true)
        I64SToF64 => self.emit_scvtf(rd, rn, int64=true, double=true)
        I64UToF64 => self.emit_ucvtf(rd, rn, int64=true, double=true)
      }
    }
    Nop => self.emit_nop()
    BoundsCheck(offset, access_size) => {
      // Memory bounds check: trap if wasm_addr + offset + access_size > memory_size
      // Uses: [wasm_addr]
      // X22 = memory_size (stored in prologue)
      // We use X16 as a temporary register for calculation (platform scratch, not allocatable)
      //
      // IMPORTANT: WASM addresses are 32-bit unsigned. We must zero-extend to 64-bit
      // to avoid overflow issues when the 32-bit value is negative (like 0xFFFFFFFF).
      let wasm_addr = reg_num(inst.uses[0])
      // First zero-extend the 32-bit wasm_addr to X16 (clear upper 32 bits)
      self.emit_mov_reg32(16, wasm_addr)
      // Compute end_addr = X16 + offset + access_size
      // Handle offset as unsigned 32-bit, then add access_size
      let offset_u64 = offset
        .reinterpret_as_uint()
        .to_uint64()
        .reinterpret_as_int64()
      let end_offset = offset_u64 + access_size.to_int64()
      if end_offset > 0L {
        // Compute end_addr = X16 + (offset + access_size)
        if end_offset <= 4095L {
          // Use ADD immediate for small offsets: X16 = X16 + end_offset
          self.emit_add_imm(16, 16, end_offset.to_int())
        } else {
          // For large offsets, load the offset into X17 first, then ADD register
          self.emit_load_imm64(17, end_offset)
          // ADD X16, X16, X17
          self.emit_add_reg(16, 16, 17)
        }
      }
      // CMP X16, X22 (compare end_addr with memory_size)
      self.emit_cmp_reg(16, 22)
      // B.HI trap (branch if unsigned higher, meaning out of bounds)
      // We need to emit: B.HI +8 (skip the BRK if in bounds)
      // B.LS is condition code 9 (LS = lower or same, unsigned <=)
      // So we use B.LS to skip the trap
      // B.cond encoding: imm19 in bits [23:5], cond in bits [3:0]
      // We want to jump +2 instructions (8 bytes) to skip the BRK
      let skip_imm19 = 2 // Skip 2 instructions = 8 bytes
      let b_ls_cond = 9 // LS condition
      let b0 = b_ls_cond | ((skip_imm19 & 7) << 5)
      let b1 = (skip_imm19 >> 3) & 0xFF
      let b2 = (skip_imm19 >> 11) & 0xFF
      let b3 = 0x54 // B.cond opcode
      self.emit_inst(b0, b1, b2, b3)
      // BRK #1 - trap with code 1 for out of bounds memory access
      // BRK encoding: 0xD4200000 + (imm16 << 5)
      // BRK #1 = 0xD4200020
      self.emit_inst(0x20, 0x00, 0x20, 0xD4)
    }
    // AArch64-specific: shifted operand instructions
    AddShifted(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_add_shifted(rd, rn, rm, shift, amount)
    }
    SubShifted(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_sub_shifted(rd, rn, rm, shift, amount)
    }
    AndShifted(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_and_shifted(rd, rn, rm, shift, amount)
    }
    OrShifted(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_orr_shifted(rd, rn, rm, shift, amount)
    }
    XorShifted(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_eor_shifted(rd, rn, rm, shift, amount)
    }
    // AArch64-specific: multiply-accumulate instructions
    Madd => {
      // Xd = Xa + Xn * Xm, uses: [acc, src1, src2]
      let rd = wreg_num(inst.defs[0])
      let ra = reg_num(inst.uses[0]) // accumulator
      let rn = reg_num(inst.uses[1]) // multiplicand
      let rm = reg_num(inst.uses[2]) // multiplier
      self.emit_madd(rd, rn, rm, ra)
    }
    Msub => {
      // Xd = Xa - Xn * Xm, uses: [acc, src1, src2]
      let rd = wreg_num(inst.defs[0])
      let ra = reg_num(inst.uses[0]) // accumulator
      let rn = reg_num(inst.uses[1]) // multiplicand
      let rm = reg_num(inst.uses[2]) // multiplier
      self.emit_msub(rd, rn, rm, ra)
    }
    Mneg => {
      // Xd = -(Xn * Xm), uses: [src1, src2]
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_mneg(rd, rn, rm)
    }
    CallIndirect(num_args, num_results) => {
      // Call through a function pointer in a register
      // ABI v1: X0=func_table, X1=memory_base, X2=memory_size, args in X3-X10
      // ABI v2: args in X0-X7 (AAPCS64 compatible), context via X20 (callee-saved)
      // Return values: X0, X1 for first two int results, extra results via buffer pointed by X7/X23
      // Uses: [func_ptr, arg0, arg1, ...]
      let func_ptr = reg_num(inst.uses[0])
      // Save function pointer to X17 (intra-procedure call scratch register)
      // Note: X18 is reserved on Apple platforms, must NOT use it
      self.emit_mov_reg(17, func_ptr) // MOV X17, func_ptr
      // Calculate how many args go on stack (args beyond the first 8)
      let actual_param_base_call = if @abi.ABI_VERSION == 2 {
        @abi.PARAM_BASE_REG
      } else {
        @abi.LEGACY_PARAM_BASE_REG
      }
      let call_max_reg_args = 8
      let stack_args = if num_args > call_max_reg_args {
        num_args - call_max_reg_args
      } else {
        0
      }
      let reg_args_count = @cmp.minimum(num_args, call_max_reg_args)
      // Allocate stack space for:
      // 1. Overflow args (args 8+)
      // 2. Temp space for register args (to avoid register clobbering during parallel copy)
      let overflow_space = stack_args * 8
      let temp_space = reg_args_count * 8
      let total_stack_space = (overflow_space + temp_space + 15) / 16 * 16
      if total_stack_space > 0 {
        self.emit_sub_imm(31, 31, total_stack_space) // SUB SP, SP, #total_stack_space
      }
      // Move arguments using stack-based parallel copy to avoid register conflicts
      // This approach doesn't require reserving any GPRs (like X11-X15)
      //
      // Layout on stack after SUB SP:
      // [SP + 0 ... overflow_space-1]: overflow args (args 8+)
      // [SP + overflow_space ... overflow_space + temp_space - 1]: temp space for register args
      if num_args > 0 {
        // Phase 1: Store all register args to temp space on stack
        // This saves their values before we load to destination registers
        for i in 0..<reg_args_count {
          let src = reg_num(inst.uses[i + 1])
          let temp_offset = overflow_space + i * 8
          let arg_class = match inst.uses[i + 1] {
            Physical(preg) => preg.class
            Virtual(vreg) => vreg.class
          }
          if src >= @abi.spill_slot_base {
            // Already spilled - we'll load directly from spill slot in Phase 3
            // Store a marker value (we won't actually read this)
            ()
          } else {
            match arg_class {
              Int => self.emit_str_imm(src, 31, temp_offset)
              Float32 => {
                self.emit_fmov_s_to_w(16, src)
                self.emit_str_imm(16, 31, temp_offset)
              }
              Float64 => {
                self.emit_fmov_d_to_x(16, src)
                self.emit_str_imm(16, 31, temp_offset)
              }
            }
          }
        }
        // Phase 2: Store overflow args (args 8+) to call stack area
        for i in call_max_reg_args..<num_args {
          let src = reg_num(inst.uses[i + 1])
          let stack_offset = (i - call_max_reg_args) * 8
          let arg_class = match inst.uses[i + 1] {
            Physical(preg) => preg.class
            Virtual(vreg) => vreg.class
          }
          if src >= @abi.spill_slot_base {
            // Spilled: load from spill slot to X16, then store to call stack
            let spill_slot = src - @abi.spill_slot_base
            let spill_offset = spill_base_offset +
              total_stack_space +
              spill_slot * 8
            match arg_class {
              Int => {
                self.emit_ldr_imm(16, 31, spill_offset)
                self.emit_str_imm(16, 31, stack_offset)
              }
              Float32 => {
                self.emit_ldr_d_imm(16, 31, spill_offset)
                self.emit_fmov_s_to_w(16, 16)
                self.emit_str_imm(16, 31, stack_offset)
              }
              Float64 => {
                self.emit_ldr_d_imm(16, 31, spill_offset)
                self.emit_fmov_d_to_x(16, 16)
                self.emit_str_imm(16, 31, stack_offset)
              }
            }
          } else {
            match arg_class {
              Int => self.emit_str_imm(src, 31, stack_offset)
              Float32 => {
                self.emit_fmov_s_to_w(16, src)
                self.emit_str_imm(16, 31, stack_offset)
              }
              Float64 => {
                self.emit_fmov_d_to_x(16, src)
                self.emit_str_imm(16, 31, stack_offset)
              }
            }
          }
        }
        // Phase 3: Load from temp space (or spill slot) to destination registers
        for i in 0..<reg_args_count {
          let src = reg_num(inst.uses[i + 1])
          let dst = i + actual_param_base_call
          let temp_offset = overflow_space + i * 8
          let arg_class = match inst.uses[i + 1] {
            Physical(preg) => preg.class
            Virtual(vreg) => vreg.class
          }
          if src >= @abi.spill_slot_base {
            // Spilled: load directly from spill slot
            let spill_slot = src - @abi.spill_slot_base
            let spill_offset = spill_base_offset +
              total_stack_space +
              spill_slot * 8
            match arg_class {
              Int => self.emit_ldr_imm(dst, 31, spill_offset)
              Float32 => {
                self.emit_ldr_d_imm(16, 31, spill_offset)
                self.emit_fmov_s_to_w(dst, 16)
              }
              Float64 => {
                self.emit_ldr_d_imm(16, 31, spill_offset)
                self.emit_fmov_d_to_x(dst, 16)
              }
            }
          } else {
            // Load from temp space on stack
            self.emit_ldr_imm(dst, 31, temp_offset)
          }
        }
      }
      // If callee returns more than 2 values, it needs a buffer pointer in X7
      // Note: This overwrites arg4 if it was set, so multi-return functions
      // can only have up to 4 user args when using the buffer
      if num_results > 2 {
        self.emit_mov_reg(7, 23) // MOV X7, X23
      }
      // Set up context for callee
      if @abi.ABI_VERSION == 2 {
        // v2: X19 already contains context_ptr (callee-saved)
        // The callee's prologue will load from X19, no setup needed
        ()
      } else {
        // v1: Set up X0 = func_table (X20), X1 = memory_base (X21), X2 = memory_size (X22)
        self.emit_mov_reg(0, 20) // MOV X0, X20
        self.emit_mov_reg(1, 21) // MOV X1, X21
        self.emit_mov_reg(2, 22) // MOV X2, X22
      }
      // Call the function (from saved X17)
      self.emit_blr(17)
      // Restore X20 (func_table) after call for v2 ABI
      // X19 is callee-saved, so it still contains our context_ptr
      // We need to reload func_table from X19
      if @abi.ABI_VERSION == 2 {
        self.emit_ldr_imm(20, 19, @abi.CTX_FUNC_TABLE_OFFSET) // X20 = [X19 + 0]
      }
      // Move results to destination registers
      // JIT ABI: integer returns in X0, X1; float returns in D0/S0, D1/S1
      // Two-phase is only needed when there's potential conflict:
      // - For ints: if dest is X0/X1 and we have multiple int results
      // - For floats: if mixing f32 and f64 types

      // Collect result info
      let int_results : Array[(Int, Int)] = [] // (dest_reg, abi_idx)
      let float_results : Array[(@abi.RegClass, Int, Int)] = [] // (class, dest_reg, abi_idx)
      let mut int_abi_idx = 0
      let mut float_abi_idx = 0
      for i in 0..<num_results {
        if i >= inst.defs.length() {
          break
        }
        let rd = wreg_num(inst.defs[i])
        let def_class = match inst.defs[i].reg {
          Physical(preg) => preg.class
          Virtual(vreg) => vreg.class
        }
        match def_class {
          Int => {
            int_results.push((rd, int_abi_idx))
            int_abi_idx = int_abi_idx + 1
          }
          Float32 | Float64 => {
            float_results.push((def_class, rd, float_abi_idx))
            float_abi_idx = float_abi_idx + 1
          }
        }
      }

      // Handle integer results
      // Need two-phase if: multiple results AND any dest is X0 or X1 (would conflict)
      let int_need_two_phase = int_results.length() >= 2 &&
        {
          let mut has_conflict = false
          for entry in int_results {
            let (rd, _) = entry
            if rd == 0 || rd == 1 {
              has_conflict = true
              break
            }
          }
          has_conflict
        }
      if int_need_two_phase {
        // Two-phase: save to temps first
        let temp_int_base = 10
        for entry in int_results {
          let (_, abi_idx) = entry
          if abi_idx < 2 {
            self.emit_mov_reg(temp_int_base + abi_idx, abi_idx)
          }
        }
        for entry in int_results {
          let (rd, abi_idx) = entry
          if abi_idx < 2 {
            let temp = temp_int_base + abi_idx
            if rd != temp {
              self.emit_mov_reg(rd, temp)
            }
          } else {
            let offset = (abi_idx - 2) * 8
            self.emit_ldr_imm(rd, 23, offset)
          }
        }
      } else {
        // Direct move: no conflict
        for entry in int_results {
          let (rd, abi_idx) = entry
          if abi_idx < 2 {
            if rd != abi_idx {
              self.emit_mov_reg(rd, abi_idx)
            }
          } else {
            let offset = (abi_idx - 2) * 8
            self.emit_ldr_imm(rd, 23, offset)
          }
        }
      }

      // Handle float results
      // Need two-phase only when mixing f32 and f64 (D/S register aliasing)
      let mut has_f32 = false
      let mut has_f64 = false
      for entry in float_results {
        let (class, _, _) = entry
        match class {
          Float32 => has_f32 = true
          _ => has_f64 = true
        }
      }
      let float_need_two_phase = has_f32 &&
        has_f64 &&
        float_results.length() >= 2
      if float_need_two_phase {
        // Two-phase: save to temps first
        let temp_float_base = 24
        for entry in float_results {
          let (_, _, abi_idx) = entry
          if abi_idx < 2 {
            self.emit_fmov_d(temp_float_base + abi_idx, abi_idx)
          }
        }
        for entry in float_results {
          let (class, rd, abi_idx) = entry
          if abi_idx < 2 {
            let temp = temp_float_base + abi_idx
            if rd != temp {
              match class {
                Float32 => self.emit_fmov_s(rd, temp)
                _ => self.emit_fmov_d(rd, temp)
              }
            }
          } else {
            let offset = (abi_idx - 2) * 8
            match class {
              Float32 => self.emit_ldr_s_imm(rd, 23, offset)
              _ => self.emit_ldr_d_imm(rd, 23, offset)
            }
          }
        }
      } else {
        // Direct move: no conflict
        for entry in float_results {
          let (class, rd, abi_idx) = entry
          if abi_idx < 2 {
            if rd != abi_idx {
              match class {
                Float32 => self.emit_fmov_s(rd, abi_idx)
                _ => self.emit_fmov_d(rd, abi_idx)
              }
            }
          } else {
            let offset = (abi_idx - 2) * 8
            match class {
              Float32 => self.emit_ldr_s_imm(rd, 23, offset)
              _ => self.emit_ldr_d_imm(rd, 23, offset)
            }
          }
        }
      }
      // Restore stack pointer if we allocated space for stack args
      if total_stack_space > 0 {
        self.emit_add_imm(31, 31, total_stack_space) // ADD SP, SP, #total_stack_space
      }
    }
    TypeCheckIndirect(expected_type) => {
      // Check if actual_type == expected_type, trap if not
      // Uses: [actual_type_vreg]
      // Emits: CMP actual, expected; B.EQ +8; BRK #2
      let actual_type_reg = reg_num(inst.uses[0])
      // CMP immediate can only handle 12-bit values (0-4095)
      // For larger values, load into scratch register and use CMP register
      if expected_type <= 4095 {
        self.emit_cmp_imm(actual_type_reg, expected_type)
      } else {
        // Load expected_type into x17 and compare
        self.emit_load_imm64(17, expected_type.to_int64())
        self.emit_cmp_reg(actual_type_reg, 17)
      }
      // B.EQ +8: skip BRK (4 bytes) if types match
      self.emit_b_cond_offset(0, 8) // cond=0 is EQ
      // BRK #2: trap with code 2 for type mismatch
      self.emit_brk(2)
    }
    StackLoad(offset) => {
      // Load from [SP + spill_base_offset + offset] into the def register
      // Uses SP (X31) as base
      // spill_base_offset accounts for saved registers area
      let rd = wreg_num(inst.defs[0])
      // Check if this is a float or int register
      let def_class = match inst.defs[0].reg {
        Physical(preg) => preg.class
        Virtual(vreg) => vreg.class
      }
      match def_class {
        Int => self.emit_ldr_imm(rd, 31, spill_base_offset + offset) // LDR Xd, [SP, #offset]
        // Always use 64-bit load for floats to avoid S/D register aliasing issues
        Float32 | Float64 =>
          self.emit_ldr_d_imm(rd, 31, spill_base_offset + offset) // LDR Dd, [SP, #offset]
      }
    }
    StackStore(offset) => {
      // Store the use register to [SP + spill_base_offset + offset]
      // Uses SP (X31) as base
      // spill_base_offset accounts for saved registers area
      let rt = reg_num(inst.uses[0])
      // Check if this is a float or int register
      let use_class = match inst.uses[0] {
        Physical(preg) => preg.class
        Virtual(vreg) => vreg.class
      }
      match use_class {
        Int => self.emit_str_imm(rt, 31, spill_base_offset + offset) // STR Xt, [SP, #offset]
        // Always use 64-bit store for floats to avoid S/D register aliasing issues
        Float32 | Float64 =>
          self.emit_str_d_imm(rt, 31, spill_base_offset + offset) // STR Dt, [SP, #offset]
      }
    }
    LoadStackParam(param_idx, class) => {
      // Load stack parameter from [SP + frame_size + (param_idx - 8) * 8]
      // Stack parameters are located above the current frame
      let max_reg_params = 8
      let stack_offset = frame_size + (param_idx - max_reg_params) * 8
      let rd = wreg_num(inst.defs[0])
      match class {
        Int => self.emit_ldr_imm(rd, 31, stack_offset) // LDR Xd, [SP, #offset]
        Float32 => {
          // Load 32-bit value to scratch, then move to S register
          self.emit_ldr_w_imm(16, 31, stack_offset) // LDR W16, [SP, #offset]
          self.emit_fmov_w_to_s(rd, 16) // FMOV Sd, W16
        }
        Float64 => {
          // Load 64-bit value to scratch, then move to D register
          self.emit_ldr_imm(16, 31, stack_offset) // LDR X16, [SP, #offset]
          self.emit_fmov_x_to_d(rd, 16) // FMOV Dd, X16
        }
      }
    }
    MemoryGrow(max_pages) => {
      // Call wasmoon_jit_memory_grow(delta, max_pages)
      // Uses: [delta], Defs: [result]
      // Get the delta from the use register
      let delta_reg = reg_num(inst.uses[0])
      let result_reg = wreg_num(inst.defs[0])

      // Move delta to X0 (first argument)
      self.emit_mov_reg(0, delta_reg) // MOV X0, delta

      // Set X1 = max_pages
      self.emit_movz(1, max_pages & 0xFFFF, 0) // MOVZ X1, #(max_pages & 0xFFFF)
      if max_pages > 0xFFFF {
        self.emit_movk(1, (max_pages >> 16) & 0xFFFF, 16) // MOVK X1, #((max_pages >> 16) & 0xFFFF), LSL #16
      }

      // Load memory_grow function pointer into X16
      let grow_ptr = @jit_ffi.c_jit_get_memory_grow_v2_ptr()
      self.emit_load_imm64(16, grow_ptr)

      // Call the function
      self.annotate("blr x16  // memory_grow")
      self.emit_blr(16)

      // Save result to stack temporarily (at spill_base_offset, which is scratch space)
      // The subsequent BLR calls will clobber X0-X17, so we save to stack
      // We use spill_base_offset which points to the spill slot area
      self.emit_str_imm(0, 31, spill_base_offset) // STR X0, [SP, #spill_base_offset]

      // After memory.grow, reload memory base and size into X21/X22
      // since realloc may have moved the memory

      // Call get_memory_base() and store to X21
      let base_ptr = @jit_ffi.c_jit_get_memory_base_v2_ptr()
      self.emit_load_imm64(16, base_ptr)
      self.annotate("blr x16  // get_memory_base")
      self.emit_blr(16)
      self.emit_mov_reg(21, 0) // MOV X21, X0

      // Call get_memory_size_bytes() and store to X22
      let size_ptr = @jit_ffi.c_jit_get_memory_size_bytes_v2_ptr()
      self.emit_load_imm64(16, size_ptr)
      self.annotate("blr x16  // get_memory_size_bytes")
      self.emit_blr(16)
      self.emit_mov_reg(22, 0) // MOV X22, X0

      // Load result from stack to the destination register
      self.emit_ldr_imm(result_reg, 31, spill_base_offset) // LDR Xd, [SP, #spill_base_offset]
    }
    MemorySize => {
      // Call wasmoon_jit_memory_size()
      // Uses: [], Defs: [result]
      let result_reg = wreg_num(inst.defs[0])

      // Load memory_size function pointer into X16
      let size_ptr = @jit_ffi.c_jit_get_memory_size_v2_ptr()
      self.emit_load_imm64(16, size_ptr)

      // Call the function
      self.annotate("blr x16  // memory_size")
      self.emit_blr(16)

      // Move result from X0 to destination
      if result_reg != 0 {
        self.emit_mov_reg(result_reg, 0) // MOV result, X0
      }
    }
    TableGet(_table_idx) => {
      // Load function reference from indirect table
      // Uses: [elem_idx], Defs: [result]
      // X24 = indirect_table base pointer
      // result = indirect_table[elem_idx] = [X24 + elem_idx * 8]
      let result_reg = wreg_num(inst.defs[0])
      let elem_idx_reg = reg_num(inst.uses[0])
      // Use LDR Xd, [Xn, Xm, LSL #3] - scaled register offset
      // This automatically multiplies elem_idx by 8 (LSL #3)
      self.emit_ldr_reg_scaled(result_reg, 24, elem_idx_reg, 3)
    }
    TableSet(_table_idx) => {
      // Store function reference to indirect table
      // Uses: [elem_idx, value], Defs: []
      // X24 = indirect_table base pointer
      // indirect_table[elem_idx] = value => [X24 + elem_idx * 8] = value
      let elem_idx_reg = reg_num(inst.uses[0])
      let value_reg = reg_num(inst.uses[1])
      // Use STR Xd, [Xn, Xm, LSL #3] - scaled register offset
      // This automatically multiplies elem_idx by 8 (LSL #3)
      self.emit_str_reg_scaled(value_reg, 24, elem_idx_reg, 3)
    }
  }
}

///|
fn MachineCode::emit_load(
  self : MachineCode,
  ty : @instr.MemType,
  rt : Int,
  rn : Int,
  offset : Int,
) -> Unit {
  match ty {
    I8 => self.emit_ldrb_imm(rt, rn, offset)
    I16 => self.emit_ldrh_imm(rt, rn, offset)
    I32 => self.emit_ldr_w_imm(rt, rn, offset)
    I64 => self.emit_ldr_imm(rt, rn, offset)
    F32 => self.emit_ldr_s_imm(rt, rn, offset)
    F64 => self.emit_ldr_d_imm(rt, rn, offset)
  }
}

///|
fn MachineCode::emit_store(
  self : MachineCode,
  ty : @instr.MemType,
  rt : Int,
  rn : Int,
  offset : Int,
) -> Unit {
  match ty {
    I8 => self.emit_strb_imm(rt, rn, offset)
    I16 => self.emit_strh_imm(rt, rn, offset)
    I32 => self.emit_str_w_imm(rt, rn, offset)
    I64 => self.emit_str_imm(rt, rn, offset)
    F32 => self.emit_str_s_imm(rt, rn, offset)
    F64 => self.emit_str_d_imm(rt, rn, offset)
  }
}

///|
fn cmp_kind_to_cond(kind : @instr.CmpKind) -> Int {
  match kind {
    Eq => EQ.to_int()
    Ne => NE.to_int()
    Slt => LT.to_int()
    Sle => LE.to_int()
    Sgt => GT.to_int()
    Sge => GE.to_int()
    Ult => LO.to_int()
    Ule => LS.to_int()
    Ugt => HI.to_int()
    Uge => HS.to_int()
  }
}

///|
/// Map floating-point comparison kind to AArch64 condition code.
///
/// For floating-point comparisons, we need "ordered" semantics where
/// any comparison involving NaN returns false (0).
///
/// After FCMP, the NZCV flags are set as:
/// - Ordered less than:    N=1, Z=0, C=0, V=0
/// - Ordered equal:        N=0, Z=1, C=1, V=0
/// - Ordered greater than: N=0, Z=0, C=1, V=0
/// - Unordered (NaN):      N=0, Z=0, C=1, V=1
///
/// Condition codes for ordered floating-point comparisons:
/// - Lt: MI (N=1) - true only when N is set (ordered less than)
/// - Le: LS (C=0|Z=1) - true when C is clear OR Z is set
/// - Gt: GT (Z=0 & N=V) - works correctly for floats
/// - Ge: GE (N=V) - works correctly for floats
/// - Eq: EQ (Z=1) - works correctly
/// - Ne: NE (Z=0) - but need VC for ordered ne, using NE gives unordered ne
///
/// Note: For NaN, NZCV=0011, so:
/// - MI: N=0, false ✓
/// - LS: C=1, Z=0, so C=0|Z=1 = false ✓
/// - GT: Z=0 & N=V = 0 & (0=1) = false ✓
/// - GE: N=V = 0=1 = false ✓
fn fcmp_kind_to_cond(kind : @instr.FCmpKind) -> Int {
  match kind {
    Eq => EQ.to_int()
    Ne => NE.to_int()
    Lt => MI.to_int() // Use MI for ordered less-than
    Le => LS.to_int() // Use LS for ordered less-or-equal
    Gt => GT.to_int()
    Ge => GE.to_int()
  }
}

///|
/// Emit epilogue to restore callee-saved registers (v2 using JITStackFrame)
fn MachineCode::emit_epilogue_v2(
  self : MachineCode,
  stack_frame : JITStackFrame,
) -> Unit {
  let saved_gprs = stack_frame.saved_gprs
  let saved_fprs = stack_frame.saved_fprs
  let fpr_save_offset = stack_frame.fpr_save_offset
  let frame_size = stack_frame.total_size

  // Restore FPRs first (before GPRs)
  let num_fprs = saved_fprs.length()
  let mut fi = 0
  let mut fpr_pair_idx = 0
  while fi + 1 < num_fprs {
    let reg1 = saved_fprs[fi]
    let reg2 = saved_fprs[fi + 1]
    let offset = fpr_save_offset + fpr_pair_idx * 16
    self.emit_ldp_d_offset(reg1, reg2, 31, offset)
    fi = fi + 2
    fpr_pair_idx = fpr_pair_idx + 1
  }
  // Handle last register if odd count
  if fi < num_fprs {
    let reg = saved_fprs[fi]
    let offset = fpr_save_offset + fpr_pair_idx * 16
    self.emit_ldr_d_imm(reg, 31, offset)
  }

  // Restore GPRs using LDP
  let num_regs = saved_gprs.length()
  let num_pairs = (num_regs + 1) / 2
  let mut i = 0
  let mut pair_idx = 0
  while i < num_regs {
    let reg1 = saved_gprs[i]
    let has_reg2 = i + 1 < num_regs
    let reg2 = if has_reg2 { saved_gprs[i + 1] } else { 31 }
    let offset = pair_idx * 16
    if pair_idx == num_pairs - 1 {
      // Last load
      if !has_reg2 {
        // Odd number of registers: use single LDR for the last one
        self.emit_ldr_imm(reg1, 31, offset)
        self.emit_add_imm(31, 31, frame_size)
      } else if pair_idx == 0 {
        // Only one pair, use post-indexed directly
        self.emit_ldp_post(reg1, reg2, 31, frame_size)
      } else {
        // Multiple pairs: load from offset, then add to SP
        self.emit_ldp_offset(reg1, reg2, 31, offset)
        self.emit_add_imm(31, 31, frame_size)
      }
    } else {
      self.emit_ldp_offset(reg1, reg2, 31, offset)
    }
    i = i + 2
    pair_idx = pair_idx + 1
  }
}

///|
/// Emit terminator with epilogue for Return (v2 using JITStackFrame)
fn MachineCode::emit_terminator_with_epilogue_v2(
  self : MachineCode,
  term : @instr.VCodeTerminator,
  stack_frame : JITStackFrame,
  result_types : Array[@ir.Type],
) -> Unit {
  match term {
    Jump(target) => self.emit_b(target)
    Branch(cond, then_b, else_b) => {
      let rt = reg_num(cond)
      self.emit_cbnz(rt, then_b)
      self.emit_b(else_b)
    }
    Return(values) => {
      // For multi-value returns, we need to carefully place each value
      // Two-phase approach is ONLY needed when there's potential for D/S clobbering:
      // - D_n and S_n share the same V_n register
      // - So mixing f32 and f64 returns can cause issues if source overlaps dest

      // First pass: collect sources for each return type
      let int_sources : Array[(Int, Int)] = [] // (src_reg, value_index)
      let float_sources : Array[(@ir.Type, Int, Int)] = [] // (type, src_reg, value_index)
      for i, value in values {
        let src = reg_num(value)
        let ty = if i < result_types.length() {
          result_types[i]
        } else {
          @ir.Type::I64
        }
        match ty {
          F32 | F64 => float_sources.push((ty, src, i))
          _ => int_sources.push((src, i))
        }
      }

      // Handle integer returns - need two-phase if sources conflict with destinations
      let int_need_two_phase = {
        let mut need = false
        for idx, entry in int_sources {
          let (src, _) = entry
          if idx < 2 {
            // Check if src will be overwritten by an earlier return
            for j in 0..<idx {
              if j == src {
                need = true
                break
              }
            }
          }
          if need {
            break
          }
        }
        need
      }
      let mut extra_offset = 0
      if int_need_two_phase {
        // Two-phase: save sources to temp registers first
        let temp_int_base = 10 // X10, X11 as temps
        for idx, entry in int_sources {
          let (src, _) = entry
          if idx < 2 {
            self.emit_mov_reg(temp_int_base + idx, src)
          }
        }
        // Then move from temps to destinations
        for idx, entry in int_sources {
          let (_, _) = entry
          if idx < 2 {
            self.emit_mov_reg(idx, temp_int_base + idx)
          } else {
            // For extra results, load from the temp if it was a register return
            let src = int_sources[idx].0
            self.emit_str_offset(src, 23, extra_offset)
            extra_offset = extra_offset + 8
          }
        }
      } else {
        // Direct move: no conflict
        for idx, entry in int_sources {
          let (src, _) = entry
          if idx < 2 {
            if src != idx {
              self.emit_mov_reg(idx, src)
            }
          } else {
            self.emit_str_offset(src, 23, extra_offset)
            extra_offset = extra_offset + 8
          }
        }
      }

      // Check if we need two-phase for floats (only when mixing f32 and f64)
      let mut has_f32 = false
      let mut has_f64 = false
      for entry in float_sources {
        let (ty, _, _) = entry
        match ty {
          F32 => has_f32 = true
          _ => has_f64 = true
        }
      }
      let need_two_phase = has_f32 && has_f64 && float_sources.length() >= 2
      if need_two_phase {
        // Two-phase: copy to temps first, then to final registers
        let temp_float_base = 28
        for idx, entry in float_sources {
          let (ty, src, _) = entry
          let temp = temp_float_base + idx
          if src != temp {
            match ty {
              F32 => self.emit_fmov_s(temp, src)
              _ => self.emit_fmov_d(temp, src)
            }
          }
        }
        for idx, entry in float_sources {
          let (ty, _, _) = entry
          let temp = temp_float_base + idx
          if idx < 2 {
            if temp != idx {
              match ty {
                F32 => self.emit_fmov_s(idx, temp)
                _ => self.emit_fmov_d(idx, temp)
              }
            }
          } else {
            self.emit_str_d_offset(temp, 23, extra_offset)
            extra_offset = extra_offset + 8
          }
        }
      } else {
        // Direct move: no conflict possible
        for idx, entry in float_sources {
          let (ty, src, _) = entry
          if idx < 2 {
            if src != idx {
              match ty {
                F32 => self.emit_fmov_s(idx, src)
                _ => self.emit_fmov_d(idx, src)
              }
            }
          } else {
            self.emit_str_d_offset(src, 23, extra_offset)
            extra_offset = extra_offset + 8
          }
        }
      }
      // Emit epilogue to restore callee-saved registers before return
      self.emit_epilogue_v2(stack_frame)
      self.emit_ret(30)
    }
    Trap(_) => self.emit_inst(0, 0, 32, 212) // BRK #0 = 0xD4200000
    BrTable(index, targets, default) => {
      // Jump table implementation for br_table
      let index_reg = reg_num(index)
      let num_targets = targets.length()
      // Use x16 and x17 as scratch registers (IP0 and IP1)
      // First, bounds check: CMP index, num_targets
      if num_targets <= 4095 {
        self.emit_cmp_imm(index_reg, num_targets)
      } else {
        // Load num_targets into x17 and compare
        self.emit_load_imm64(17, num_targets.to_int64())
        self.emit_cmp_reg(index_reg, 17)
      }
      // B.HS default (condition code 2 = HS/CS = unsigned >=)
      self.emit_b_cond(2, default)
      // Layout after this point:
      //   ADR  at offset X    -> x16 = X + 12 (pointing to jump table)
      //   ADD  at offset X+4
      //   BR   at offset X+8
      //   B target[0] at offset X+12  <- jump table starts here
      self.emit_adr(16, 12)
      // ADD x16, x16, index, LSL #2 (each entry is 4 bytes)
      self.emit_add_shifted(16, 16, index_reg, Lsl, 2)
      // BR x16
      self.emit_br(16)
      // Emit jump table: sequence of B instructions
      for target in targets {
        self.emit_b(target)
      }
    }
  }
}
