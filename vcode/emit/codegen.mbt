// Code Generation
// Translates VCode to machine code

///|
fn collect_used_callee_saved(
  func : @lower.VCodeFunction,
  _needs_sret : Bool,
) -> Array[Int] {
  // v3 ABI: SRET uses X8 which is caller-saved, so no special exclusion needed
  let used : @hashset.HashSet[Int] = @hashset.new()
  let mut has_calls = false

  // Check param_pregs: parameters that cross calls are moved to callee-saved registers
  // These are defined in the prologue via `mov xN, x(3+i)`
  for preg in func.get_param_pregs() {
    if preg is Some(p) && is_callee_saved_alloc(p.index) {
      used.add(p.index)
    }
  }
  for block in func.get_blocks() {
    for inst in block.insts {
      // Check if this instruction is a function call
      // Following Cranelift's design: use call_type() to determine if an instruction
      // behaves like a call (clobbers caller-saved registers)
      if inst.opcode.call_type() is @instr.Regular {
        has_calls = true
      }
      for def in inst.defs {
        if def.reg is Physical(preg) &&
          preg.class is Int &&
          is_callee_saved_alloc(preg.index) {
          used.add(preg.index)
        }
      }
    }
  }
  // If the function makes any calls, we must save LR (X30)
  // Note: X20-X24 are no longer pre-loaded in prologue (following Cranelift's approach)
  // They are loaded on-demand from vmctx and only need saving if used by regalloc
  if has_calls {
    used.add(30) // LR
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
  for preg in func.get_param_pregs() {
    if preg is Some(p) &&
      (p.class is Float32 || p.class is Float64) &&
      is_callee_saved_fpr(p.index) {
      used.add(p.index)
    }
  }
  for block in func.get_blocks() {
    for inst in block.insts {
      for def in inst.defs {
        if def.reg is Physical(preg) &&
          (preg.class is Float32 || preg.class is Float64) &&
          is_callee_saved_fpr(preg.index) {
          used.add(preg.index)
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
/// Emit prologue for ABI v3
///
/// Stack Frame Layout (from high to low address):
/// ┌───────────────────────────┐
/// │  Caller's Stack Args      │ (if any)
/// ├═══════════════════════════┤ ← SP at function entry
/// │  Frame Pointer (X29)      │ ← Setup area (16 bytes)
/// ├───────────────────────────┤
/// │  Link Register (X30)      │
/// ├───────────────────────────┤ ← FP points here after setup
/// │  Clobbered Callee-Saves   │ (X19-X28 as needed)
/// ├───────────────────────────┤
/// │  Clobbered FPRs           │ (V8-V15 as needed)
/// ├───────────────────────────┤
/// │  Spill Slots              │ (register spill area)
/// ├───────────────────────────┤
/// │  Outgoing Arguments       │ (for calls with stack args)
/// └═══════════════════════════┘ ← SP after prologue
///
/// ABI v3 Parameter Passing:
/// - X0 = callee_vmctx (cached to X19)
/// - X1 = caller_vmctx (unused in current impl)
/// - X2-X7 = user integer params (up to 6)
/// - V0-V7 = user float params (S for f32, D for f64)
/// Emit stack pointer adjustment for arbitrary sizes (Cranelift-style)
///
/// Handles any size by using:
/// - ADD/SUB with imm12 for values <= 4095
/// - Load constant to X16 + ADD/SUB reg for larger values
fn MachineCode::emit_sp_adjust(self : MachineCode, amount : Int) -> Unit {
  if amount == 0 {
    return
  }
  let (abs_amount, is_sub) = if amount < 0 {
    (-amount, true)
  } else {
    (amount, false)
  }
  if abs_amount <= 4095 {
    // Use immediate form
    if is_sub {
      self.emit_sub_imm(31, 31, abs_amount)
    } else {
      self.emit_add_imm(31, 31, abs_amount)
    }
  } else {
    // Load constant to X16, then use register form
    self.emit_load_imm64(16, abs_amount.to_int64())
    if is_sub {
      self.emit_sub_reg(31, 31, 16)
    } else {
      self.emit_add_reg(31, 31, 16)
    }
  }
}

///|
fn MachineCode::emit_prologue(
  self : MachineCode,
  stack_frame : JITStackFrame,
  params : Array[@abi.VReg],
  param_pregs : Array[@abi.PReg?],
) -> Unit {
  let saved_gprs = stack_frame.saved_gprs
  let saved_fprs = stack_frame.saved_fprs

  // Cranelift-style prologue:
  // 1. Save FP/LR with fixed -16 pre-indexed (avoids SImm7 overflow)
  // 2. Save clobbered GPRs with -16 pre-indexed pushes
  // 3. Save clobbered FPRs with -16 pre-indexed pushes
  // 4. Allocate remaining stack (spill + outgoing) with emit_sp_adjust

  // Step 1: Save FP/LR with fixed -16 pre-indexed
  // stp x29, x30, [sp, #-16]!
  if stack_frame.has_setup_area {
    self.emit_stp_pre(29, 30, 31, -16)
    // mov x29, sp (set frame pointer)
    self.emit_mov_reg(29, 31)
  }

  // Step 2: Save callee-saved GPRs with pre-indexed pushes (Cranelift style)
  // Cranelift approach: handle remainder first, then reverse iterate pairs
  // This ensures save/restore order matches perfectly
  let num_gprs = saved_gprs.length()
  if num_gprs > 0 {
    // Handle remainder first (if odd number of registers)
    if num_gprs % 2 == 1 {
      let last_reg = saved_gprs[num_gprs - 1]
      // str last_reg, [sp, #-16]!
      self.emit_str_pre(last_reg, 31, -16)
    }

    // Reverse iterate pairs: from the last pair to the first
    let num_pairs = num_gprs / 2
    let mut pi = num_pairs - 1
    while pi >= 0 {
      let reg1 = saved_gprs[pi * 2]
      let reg2 = saved_gprs[pi * 2 + 1]
      // stp reg1, reg2, [sp, #-16]!
      self.emit_stp_pre(reg1, reg2, 31, -16)
      pi = pi - 1
    }
  }

  // Step 3: Save callee-saved FPRs with pre-indexed pushes (Cranelift style)
  // Cranelift approach: handle remainder first, then reverse iterate pairs
  let num_fprs = saved_fprs.length()
  if num_fprs > 0 {
    // Handle remainder first (if odd number of registers)
    if num_fprs % 2 == 1 {
      let last_reg = saved_fprs[num_fprs - 1]
      // str d_reg, [sp, #-16]!
      self.emit_str_d_pre(last_reg, 31, -16)
    }

    // Reverse iterate pairs: from the last pair to the first
    let num_pairs = num_fprs / 2
    let mut pi = num_pairs - 1
    while pi >= 0 {
      let reg1 = saved_fprs[pi * 2]
      let reg2 = saved_fprs[pi * 2 + 1]
      // stp d_reg1, d_reg2, [sp, #-16]!
      self.emit_stp_d_pre(reg1, reg2, 31, -16)
      pi = pi - 1
    }
  }

  // Step 4: Allocate remaining stack space (spill slots + outgoing args)
  // This uses emit_sp_adjust which handles any size correctly
  let remaining_size = stack_frame.spill_size + stack_frame.outgoing_args_size
  if remaining_size > 0 {
    self.emit_sp_adjust(-remaining_size)
  }

  // Step 5: Cache vmctx to X19 (the only pinned register, like Cranelift's X21)
  // Following Cranelift: vmctx is params[0], passed in X0
  // All other values (memory_base, memory_size, func_table, table0_base) are
  // loaded on-demand from vmctx, following Cranelift's approach.
  self.emit_mov_reg(19, 0)

  // Step 6: Move arguments from ABI registers to allocated registers
  // Following Cranelift: all params use X0-X7 (int) or V0-V7 (float)
  // vmctx is params[0] and comes in X0, already cached to X19 above
  let max_int_params = @abi.MAX_REG_PARAMS // 8
  let max_float_params = @abi.MAX_FLOAT_REG_PARAMS // 8
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
        // Float params come in V0-V7 directly
        if float_idx < max_float_params {
          let v_src = float_idx // V0, V1, V2, ...
          match dest_preg {
            Some(preg) =>
              if preg.index != v_src {
                match param.class {
                  Float32 => self.emit_fmov_s(preg.index, v_src)
                  _ => self.emit_fmov_d(preg.index, v_src)
                }
              }
            None => ()
          }
          float_idx = float_idx + 1
        }
      Int =>
        // Integer params come in X0-X7
        if int_idx < max_int_params {
          let x_src = int_idx // X0, X1, X2, ...
          match dest_preg {
            Some(preg) =>
              if preg.index != x_src {
                self.emit_mov_reg(preg.index, x_src)
              }
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
  // v3 ABI: Check if we need SRET (more than 8 int or 8 float returns)
  let needs_sret = func.needs_extra_results_ptr()
  // Check if we call functions that return more than register capacity
  // In that case, we need to allocate a local buffer and use X8 (SRET) to point to it
  let calls_multi_value = func.calls_multi_value_function()
  // We need SRET if either we return multi-value OR we call multi-value functions
  let uses_sret = needs_sret || calls_multi_value
  // Collect callee-saved GPRs that this function clobbers
  let clobbered = collect_used_callee_saved(func, uses_sret)
  // Collect callee-saved FPRs (D8-D15) that this function clobbers
  let clobbered_fprs = collect_used_callee_saved_fprs(func)

  // Build stack frame layout using JITStackFrame
  // has_calls is true if function needs SRET, calls multi-value functions, or has outgoing args
  let has_calls = needs_sret ||
    calls_multi_value ||
    func.get_max_outgoing_args_size() > 0
  let stack_frame = JITStackFrame::build(
    clobbered,
    clobbered_fprs,
    func.get_num_spill_slots(),
    has_calls~,
    outgoing_args_size=func.get_max_outgoing_args_size(),
  )

  // Emit prologue: save callee-saved registers, cache vmctx to X19, and move params
  mc.emit_prologue(stack_frame, func.get_params(), func.get_param_pregs())

  // Emit function body
  for block in func.get_blocks() {
    mc.define_label(block.id)
    for inst in block.insts {
      mc.emit_instruction(inst, stack_frame)
    }
    if block.terminator is Some(term) {
      mc.emit_terminator_with_epilogue(
        term,
        stack_frame,
        func.get_result_types(),
      )
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
    Add(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_64 {
        self.emit_add_reg(rd, rn, rm)
      } else {
        self.emit_add_reg32(rd, rn, rm)
      }
    }
    AddImm(imm, is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_64 {
        self.emit_add_imm(rd, rn, imm)
      } else {
        self.emit_add_imm32(rd, rn, imm)
      }
    }
    Sub(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_64 {
        self.emit_sub_reg(rd, rn, rm)
      } else {
        self.emit_sub_reg32(rd, rn, rm)
      }
    }
    Mul(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_64 {
        self.emit_mul(rd, rn, rm)
      } else {
        self.emit_mul32(rd, rn, rm)
      }
    }
    SDiv(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_64 {
        self.emit_sdiv(rd, rn, rm)
      } else {
        self.emit_sdiv32(rd, rn, rm)
      }
    }
    UDiv(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_64 {
        self.emit_udiv(rd, rn, rm)
      } else {
        self.emit_udiv32(rd, rn, rm)
      }
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
    Shl(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_64 {
        self.emit_lsl_reg(rd, rn, rm)
      } else {
        self.emit_lsl_reg32(rd, rn, rm)
      }
    }
    AShr(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_64 {
        self.emit_asr_reg(rd, rn, rm)
      } else {
        self.emit_asr_reg32(rd, rn, rm)
      }
    }
    LShr(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_64 {
        self.emit_lsr_reg(rd, rn, rm)
      } else {
        self.emit_lsr_reg32(rd, rn, rm)
      }
    }
    Rotr(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_64 {
        self.emit_ror_reg(rd, rn, rm)
      } else {
        self.emit_ror_reg32(rd, rn, rm)
      }
    }
    Not => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.emit_mvn(rd, rn)
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
    Cmp(kind, is_64) => {
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_64 {
        self.emit_cmp_reg(rn, rm)
      } else {
        self.emit_cmp_reg32(rn, rm)
      }
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
    Clz(is_64) => {
      // Count leading zeros
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_64 {
        self.emit_clz(rd, rn)
      } else {
        self.emit_clz32(rd, rn)
      }
    }
    Rbit(is_64) => {
      // Reverse bits in register
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_64 {
        self.emit_rbit(rd, rn)
      } else {
        self.emit_rbit32(rd, rn)
      }
    }
    Popcnt(is_64) => {
      // Population count (count number of 1 bits)
      // AArch64 doesn't have a direct POPCNT for GPRs, we use SIMD:
      // For 64-bit:
      //   1. FMOV D16, Xn (move to vector register)
      //   2. CNT V16.8B, V16.8B (count bits in each byte)
      //   3. ADDV B16, V16.8B (sum all byte counts)
      //   4. FMOV Wd, S16 (move back to GPR)
      // For 32-bit:
      //   1. FMOV S16, Wn (move to vector register, upper bytes zero)
      //   2. CNT V16.8B, V16.8B (count bits in each byte)
      //   3. ADDV B16, V16.8B (sum all byte counts)
      //   4. FMOV Wd, S16 (move back to GPR)
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_64 {
        // FMOV D16, Xn
        self.emit_fmov_x_to_d(16, rn)
      } else {
        // FMOV S16, Wn
        self.emit_fmov_w_to_s(16, rn)
      }
      // CNT V16.8B, V16.8B
      self.emit_cnt_8b(16, 16)
      // ADDV B16, V16.8B
      self.emit_addv_b(16, 16)
      // FMOV Wd, S16 (result is small enough to fit in W register)
      self.emit_fmov_s_to_w(rd, 16)
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
    TrapIfUgt(trap_code) => {
      // Trap if lhs > rhs (unsigned comparison)
      // Uses: [lhs, rhs]
      // Emits: CMP lhs, rhs; B.LS skip; BRK #trap_code
      let lhs = reg_num(inst.uses[0])
      let rhs = reg_num(inst.uses[1])
      // CMP lhs, rhs
      self.emit_cmp_reg(lhs, rhs)
      // B.LS +8 (skip BRK if lhs <= rhs)
      // LS condition code = 9
      self.emit_b_cond_offset(9, 8)
      // BRK #trap_code
      self.emit_brk(trap_code)
    }
    TrapIfUge(trap_code) => {
      // Trap if lhs >= rhs (unsigned comparison)
      // Uses: [lhs, rhs]
      // Emits: CMP lhs, rhs; B.LO skip; BRK #trap_code
      let lhs = reg_num(inst.uses[0])
      let rhs = reg_num(inst.uses[1])
      // CMP lhs, rhs
      self.emit_cmp_reg(lhs, rhs)
      // B.LO +8 (skip BRK if lhs < rhs)
      // LO condition code = 3
      self.emit_b_cond_offset(3, 8)
      // BRK #trap_code
      self.emit_brk(trap_code)
    }
    FpuCmp(is_f32) => {
      // Floating-point compare (sets NZCV flags)
      // Uses: [lhs, rhs], Defs: []
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        self.emit_fcmp_s(rn, rm)
      } else {
        self.emit_fcmp_d(rn, rm)
      }
    }
    TrapIf(cond, trap_code) => {
      // Conditional trap based on flags
      // B.!cond skip; BRK #trap_code
      // We need to branch OVER the trap if condition is NOT met
      // So we use the inverted condition for the branch
      let skip_cond = match cond {
        Eq => 1 // NE
        Ne => 0 // EQ
        Hs => 3 // LO
        Lo => 2 // HS
        Mi => 5 // PL
        Pl => 4 // MI
        Vs => 7 // VC
        Vc => 6 // VS
        Hi => 9 // LS
        Ls => 8 // HI
        Ge => 11 // LT
        Lt => 10 // GE
        Gt => 13 // LE
        Le => 12 // GT
        Al => 15 // NV (never - will always trap)
      }
      // B.!cond +8 (skip BRK)
      self.emit_b_cond_offset(skip_cond, 8)
      // BRK #trap_code
      self.emit_brk(trap_code)
    }
    TrapIfZero(is_64, trap_code) => {
      // Trap if operand is zero (for division by zero)
      // Uses: [rn]
      // Emits: CBNZ rn, +8; BRK #trap_code
      let rn = reg_num(inst.uses[0])
      // CBNZ rn, +8 (skip BRK if not zero)
      self.emit_cbnz_offset(rn, is_64, 8)
      // BRK #trap_code
      self.emit_brk(trap_code)
    }
    TrapIfDivOverflow(is_64, trap_code) => {
      // Trap if signed division would overflow (INT_MIN / -1)
      // Uses: [lhs, rhs]
      // Following Cranelift's approach (no scratch registers needed):
      //   ADDS XZR, rhs, #1      ; Check rhs == -1 (sets Z if rhs == -1)
      //   CCMP lhs, #1, #0, Eq   ; If Z set, do CMP lhs-1 (sets V if overflow), else NZCV=0
      //   B.VC +8                ; Skip BRK if V clear
      //   BRK #trap_code         ; Trap on overflow
      //
      // The key insight: INT_MIN - 1 overflows, setting V flag.
      // - If rhs != -1: CCMP sets NZCV=0, V=0, no trap
      // - If rhs == -1 && lhs != INT_MIN: lhs-1 doesn't overflow, V=0, no trap
      // - If rhs == -1 && lhs == INT_MIN: INT_MIN-1 overflows, V=1, trap!
      let lhs = reg_num(inst.uses[0])
      let rhs = reg_num(inst.uses[1])
      // ADDS XZR/WZR, rhs, #1 - check if rhs == -1
      self.emit_adds_imm_zr(rhs, 1, is_64)
      // CCMP lhs, #1, #0, Eq - if Z set (rhs==-1), do lhs-1, else set NZCV=0
      // Eq condition code = 0
      self.emit_ccmp_imm(lhs, 1, 0, 0, is_64)
      // B.VC +8 (VC = V clear = condition 7, skip BRK if no overflow)
      self.emit_b_cond_offset(7, 8)
      // BRK #trap_code
      self.emit_brk(trap_code)
    }
    FcvtToInt(is_f32, is_i64, is_signed) => {
      // Raw float-to-int conversion (no checks)
      // Uses: [src_fp], Defs: [dst_int]
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_signed {
        self.emit_fcvtzs(rd, rn, int64=is_i64, double=!is_f32)
      } else {
        self.emit_fcvtzu(rd, rn, int64=is_i64, double=!is_f32)
      }
    }
    FpuSel(is_f32, cond) => {
      // Floating-point conditional select
      // Uses: [true_val, false_val], Defs: [result]
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      let cond_bits = cond.to_bits()
      if is_f32 {
        self.emit_fcsel_s(rd, rn, rm, cond_bits)
      } else {
        self.emit_fcsel_d(rd, rn, rm, cond_bits)
      }
    }
    FpuMaxnm(is_f32) => {
      // Floating-point maximum (NaN-propagating)
      // Uses: [lhs, rhs], Defs: [result]
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        self.emit_fmaxnm_s(rd, rn, rm)
      } else {
        self.emit_fmaxnm_d(rd, rn, rm)
      }
    }
    FpuMinnm(is_f32) => {
      // Floating-point minimum (NaN-propagating)
      // Uses: [lhs, rhs], Defs: [result]
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        self.emit_fminnm_s(rd, rn, rm)
      } else {
        self.emit_fminnm_d(rd, rn, rm)
      }
    }
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
    ReturnCallIndirect(_num_args, _num_results) => {
      // Tail call optimization following Cranelift's design
      // Parameters are already set up by lowering phase via:
      // - StoreToStack for overflow arguments
      // - add_use_fixed constraints for register arguments (X17=func_ptr, X0/X1=vmctx, X2-X7/V0-V7=args)
      // Emit only needs to:
      // 1. Restore callee-saved registers (epilogue)
      // 2. BR to function pointer (doesn't save return address, callee returns to our caller)

      // Epilogue - restore callee-saved registers and frame pointer
      // Following Cranelift's emit_return_call_common_sequence
      self.emit_epilogue(stack_frame)

      // BR (not BLR) - jump to function without saving return address
      // func_ptr is guaranteed to be in X17 by add_use_fixed constraint in lowering
      // This is the KEY tail call semantic: callee returns directly to our caller
      self.emit_br(17)

      // Note: No code after BR - control never returns here
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
      // BRK #4: trap with code 4 for indirect call type mismatch
      self.emit_brk(4)
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
    LoadStackParam(param_idx, class, int_overflow_count) => {
      // Load stack parameter from stack (Cranelift-style layout)
      //
      // Stack layout from callee's perspective:
      // ┌───────────────────────────┐
      // │  Caller's overflow args   │ ← [entry_SP + 0], [entry_SP + 8], ...
      // ├═══════════════════════════┤ ← entry_SP (= current_SP + total_size)
      // │  FP/LR (setup area)       │
      // │  GPR saves                │
      // │  FPR saves                │
      // │  Spill slots              │
      // │  Outgoing args            │
      // └═══════════════════════════┘ ← current_SP
      //
      // param_idx >= 0: int overflow at index param_idx
      // param_idx < 0: float overflow at index (-param_idx - 1)
      //
      // The offset calculation:
      // - frame_size (= total_size) gets us from current_SP to entry_SP
      // - param_idx * 8 for the specific argument
      // Note: total_size already includes setup_area_size, so we don't add it again
      let stack_offset = if param_idx >= 0 {
        // Int stack param: directly at param_idx * 8
        frame_size + param_idx * 8
      } else {
        // Float stack param: after all int overflow params
        let float_idx = -param_idx - 1
        frame_size + int_overflow_count * 8 + float_idx * 8
      }
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
    LoadPtr(ty, offset) => {
      // Raw pointer load (no bounds checking)
      // Uses: [base], Defs: [result]
      let result_reg = wreg_num(inst.defs[0])
      let base_reg = reg_num(inst.uses[0])
      self.emit_load(ty, result_reg, base_reg, offset)
    }
    StorePtr(ty, offset) => {
      // Raw pointer store (no bounds checking)
      // Uses: [base, value], Defs: []
      let base_reg = reg_num(inst.uses[0])
      let value_reg = reg_num(inst.uses[1])
      self.emit_store(ty, value_reg, base_reg, offset)
    }
    LoadPtrNarrow(bits, signed, offset) => {
      // Raw pointer narrow load (no bounds checking)
      // Uses: [base], Defs: [result]
      let result_reg = wreg_num(inst.defs[0])
      let base_reg = reg_num(inst.uses[0])
      match (bits, signed) {
        (8, true) => self.emit_ldrsb_x_imm(result_reg, base_reg, offset)
        (8, false) => self.emit_ldrb_imm(result_reg, base_reg, offset)
        (16, true) => self.emit_ldrsh_x_imm(result_reg, base_reg, offset)
        (16, false) => self.emit_ldrh_imm(result_reg, base_reg, offset)
        (32, true) => self.emit_ldrsw_imm(result_reg, base_reg, offset)
        (32, false) => self.emit_ldr_w_imm(result_reg, base_reg, offset)
        _ => () // Unsupported bit width
      }
    }
    StorePtrNarrow(bits, offset) => {
      // Raw pointer narrow store (no bounds checking)
      // Uses: [base, value], Defs: []
      let base_reg = reg_num(inst.uses[0])
      let value_reg = reg_num(inst.uses[1])
      match bits {
        8 => self.emit_strb_imm(value_reg, base_reg, offset)
        16 => self.emit_strh_imm(value_reg, base_reg, offset)
        32 => self.emit_str_w_imm(value_reg, base_reg, offset)
        _ => () // Unsupported bit width
      }
    }
    LoadGCFuncPtr(libcall) => {
      // Load GC runtime function pointer
      // Uses: [], Defs: [result (function pointer)]
      let result_reg = wreg_num(inst.defs[0])
      let func_ptr = match libcall {
        RefTest => @jit_ffi.c_jit_get_gc_ref_test_ptr()
        RefCast => @jit_ffi.c_jit_get_gc_ref_cast_ptr()
        StructNew => @jit_ffi.c_jit_get_gc_struct_new_ptr()
        StructGet => @jit_ffi.c_jit_get_gc_struct_get_ptr()
        StructSet => @jit_ffi.c_jit_get_gc_struct_set_ptr()
        ArrayNew => @jit_ffi.c_jit_get_gc_array_new_ptr()
        ArrayGet => @jit_ffi.c_jit_get_gc_array_get_ptr()
        ArraySet => @jit_ffi.c_jit_get_gc_array_set_ptr()
        ArrayLen => @jit_ffi.c_jit_get_gc_array_len_ptr()
        ArrayFill => @jit_ffi.c_jit_get_gc_array_fill_ptr()
        ArrayCopy => @jit_ffi.c_jit_get_gc_array_copy_ptr()
        TypeCheckSubtype => @jit_ffi.c_jit_get_gc_type_check_subtype_ptr()
      }
      self.emit_load_imm64(result_reg, func_ptr)
    }
    LoadJITFuncPtr(libcall) => {
      // Load JIT runtime function pointer (v3/v4 ctx-passing helpers)
      // Uses: [], Defs: [result (function pointer)]
      let result_reg = wreg_num(inst.defs[0])
      let func_ptr = match libcall {
        MemoryGrowV3 => @jit_ffi.c_jit_get_memory_grow_ptr_v3()
        MemorySizeV3 => @jit_ffi.c_jit_get_memory_size_ptr_v3()
        MemoryFillV3 => @jit_ffi.c_jit_get_memory_fill_ptr_v3()
        MemoryCopyV3 => @jit_ffi.c_jit_get_memory_copy_ptr_v3()
        TableGrowV3 => @jit_ffi.c_jit_get_table_grow_ptr_v3()
        // v4 helpers with memidx for multi-memory support
        MemoryGrowV4 => @jit_ffi.c_jit_get_memory_grow_ptr_v4()
        MemorySizeV4 => @jit_ffi.c_jit_get_memory_size_ptr_v4()
        MemoryFillV4 => @jit_ffi.c_jit_get_memory_fill_ptr_v4()
        MemoryCopyV4 => @jit_ffi.c_jit_get_memory_copy_ptr_v4()
      }
      self.emit_load_imm64(result_reg, func_ptr)
    }
    LoadExceptionFuncPtr(libcall) => {
      // Load exception handling runtime function pointer
      // Uses: [], Defs: [result (function pointer)]
      let result_reg = wreg_num(inst.defs[0])
      let func_ptr = match libcall {
        TryBegin => @jit_ffi.c_jit_get_exception_try_begin_ptr()
        TryEnd => @jit_ffi.c_jit_get_exception_try_end_ptr()
        Throw => @jit_ffi.c_jit_get_exception_throw_ptr()
        ThrowRef => @jit_ffi.c_jit_get_exception_throw_ref_ptr()
        Delegate => @jit_ffi.c_jit_get_exception_delegate_ptr()
        GetTag => @jit_ffi.c_jit_get_exception_get_tag_ptr()
        GetValue => @jit_ffi.c_jit_get_exception_get_value_ptr()
        GetValueCount => @jit_ffi.c_jit_get_exception_get_value_count_ptr()
        Sigsetjmp => @jit_ffi.c_jit_get_sigsetjmp_ptr()
        SpillLocals => @jit_ffi.c_jit_get_exception_spill_locals_ptr()
        GetSpilledLocal => @jit_ffi.c_jit_get_exception_get_spilled_local_ptr()
      }
      self.emit_load_imm64(result_reg, func_ptr)
    }
    CallPtr(_, _, _call_conv) =>
      // Cranelift-style call: all arguments are already in place
      //
      // The lower phase generates:
      // - AdjustSP to allocate stack space for overflow args
      // - StoreToStack for each overflow arg
      // - CallPtr with FixedReg constraints for register args
      // - AdjustSP to deallocate stack space
      //
      // The regalloc phase processes constraints and inserts moves:
      // For Wasm calling convention:
      // - func_ptr is constrained to X17
      // - callee_vmctx is constrained to X0
      // - caller_vmctx is constrained to X1
      // - int user args are constrained to X2-X7
      // - float user args are constrained to V0-V7
      // - results are constrained to X0/V0 etc.
      // For C calling convention:
      // - func_ptr is constrained to X17
      // - int args are constrained to X0-X7 (no vmctx)
      // - float args are constrained to V0-V7
      // - results are constrained to X0/V0 etc.
      //
      // By the time we get here, everything is in the right place!
      // Just emit the branch-and-link instruction.
      self.emit_blr(17)
    AdjustSP(delta) =>
      // Adjust stack pointer by delta bytes
      // Used in Cranelift-style call lowering for outgoing args
      if delta > 0 {
        self.emit_add_imm(31, 31, delta)
      } else if delta < 0 {
        self.emit_sub_imm(31, 31, -delta)
      }
    // delta == 0: nop
    StoreToStack(offset) => {
      // Store value to [SP + outgoing_args_offset + offset]
      // Used in Cranelift-style call lowering for overflow args
      // The outgoing args area is pre-allocated in prologue, so SP doesn't change
      let actual_offset = stack_frame.outgoing_args_offset + offset
      let src = reg_num(inst.uses[0])
      let src_class = match inst.uses[0] {
        Physical(preg) => preg.class
        Virtual(vreg) => vreg.class
      }
      match src_class {
        Int => self.emit_str_imm(src, 31, actual_offset)
        Float32 => self.emit_str_s_imm(src, 31, actual_offset)
        Float64 => self.emit_str_d_imm(src, 31, actual_offset)
      }
    }
    LoadSP => {
      // Load stack pointer into result register
      // Uses ADD Xd, SP, #0 because MOV with SP has encoding issues
      let result_reg = wreg_num(inst.defs[0])
      self.emit_add_imm(result_reg, 31, 0)
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
/// Emit epilogue for ABI v3 (Cranelift-style)
///
/// Reverses the prologue operations in reverse order (Cranelift style):
/// 1. Deallocate remaining stack space (spill + outgoing)
/// 2. Restore callee-saved FPRs with post-indexed pops (forward pairs, then remainder)
/// 3. Restore callee-saved GPRs with post-indexed pops (forward pairs, then remainder)
/// 4. Restore FP/LR with post-indexed pop
fn MachineCode::emit_epilogue(
  self : MachineCode,
  stack_frame : JITStackFrame,
) -> Unit {
  let saved_gprs = stack_frame.saved_gprs
  let saved_fprs = stack_frame.saved_fprs

  // Step 1: Deallocate remaining stack space (spill slots + outgoing args)
  let remaining_size = stack_frame.spill_size + stack_frame.outgoing_args_size
  if remaining_size > 0 {
    self.emit_sp_adjust(remaining_size)
  }

  // Step 2: Restore callee-saved FPRs with post-indexed pops (Cranelift style)
  // Cranelift approach: forward iterate pairs, then handle remainder
  // This mirrors the prologue which does: remainder first, then reverse pairs
  let num_fprs = saved_fprs.length()
  if num_fprs > 0 {
    // Forward iterate pairs
    let num_pairs = num_fprs / 2
    let mut pi = 0
    while pi < num_pairs {
      let reg1 = saved_fprs[pi * 2]
      let reg2 = saved_fprs[pi * 2 + 1]
      // ldp d_reg1, d_reg2, [sp], #16
      self.emit_ldp_d_post(reg1, reg2, 31, 16)
      pi = pi + 1
    }

    // Handle remainder last (if odd number of registers)
    if num_fprs % 2 == 1 {
      let last_reg = saved_fprs[num_fprs - 1]
      // ldr d_reg, [sp], #16
      self.emit_ldr_d_post(last_reg, 31, 16)
    }
  }

  // Step 3: Restore callee-saved GPRs with post-indexed pops (Cranelift style)
  // Cranelift approach: forward iterate pairs, then handle remainder
  let num_gprs = saved_gprs.length()
  if num_gprs > 0 {
    // Forward iterate pairs
    let num_pairs = num_gprs / 2
    let mut pi = 0
    while pi < num_pairs {
      let reg1 = saved_gprs[pi * 2]
      let reg2 = saved_gprs[pi * 2 + 1]
      // ldp reg1, reg2, [sp], #16
      self.emit_ldp_post(reg1, reg2, 31, 16)
      pi = pi + 1
    }

    // Handle remainder last (if odd number of registers)
    if num_gprs % 2 == 1 {
      let last_reg = saved_gprs[num_gprs - 1]
      // ldr reg, [sp], #16
      self.emit_ldr_post(last_reg, 31, 16)
    }
  }

  // Step 4: Restore FP/LR with post-indexed pop
  if stack_frame.has_setup_area {
    // ldp x29, x30, [sp], #16
    self.emit_ldp_post(29, 30, 31, 16)
  }
}

///|
/// Emit terminator with epilogue for Return (v3 ABI using JITStackFrame)
fn MachineCode::emit_terminator_with_epilogue(
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
      // v3 ABI: Up to 8 integer returns in X0-X7, up to 8 float returns in V0-V7
      // If more returns are needed, SRET pointer is passed in X8
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

      // v3 ABI: Use X0-X7 for integer returns (up to 8)
      let max_int_ret_regs = @abi.MAX_INT_RET_REGS // 8
      let max_float_ret_regs = @abi.MAX_FLOAT_RET_REGS // 8

      // Handle integer returns - need two-phase if sources conflict with destinations
      let int_need_two_phase = {
        let mut need = false
        for idx, entry in int_sources {
          let (src, _) = entry
          if idx < max_int_ret_regs {
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
        let temp_int_base = 10 // X10-X17 as temps (we have up to 8)
        let num_in_regs = if int_sources.length() < max_int_ret_regs {
          int_sources.length()
        } else {
          max_int_ret_regs
        }
        for idx in 0..<num_in_regs {
          let (src, _) = int_sources[idx]
          self.emit_mov_reg(temp_int_base + idx, src)
        }
        // Then move from temps to destinations
        for idx in 0..<num_in_regs {
          self.emit_mov_reg(idx, temp_int_base + idx)
        }
        // Extra results go to SRET buffer (X8)
        for idx in max_int_ret_regs..<int_sources.length() {
          let (src, _) = int_sources[idx]
          self.emit_str_offset(src, @abi.REG_SRET, extra_offset)
          extra_offset = extra_offset + 8
        }
      } else {
        // Direct move: no conflict
        for idx, entry in int_sources {
          let (src, _) = entry
          if idx < max_int_ret_regs && src != idx {
            self.emit_mov_reg(idx, src)
          } else if idx >= max_int_ret_regs {
            // Extra results go to SRET buffer (X8)
            self.emit_str_offset(src, @abi.REG_SRET, extra_offset)
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
        let temp_float_base = 24 // V24-V31 as temps
        let num_in_regs = if float_sources.length() < max_float_ret_regs {
          float_sources.length()
        } else {
          max_float_ret_regs
        }
        for idx in 0..<num_in_regs {
          let (ty, src, _) = float_sources[idx]
          let temp = temp_float_base + idx
          if src != temp {
            match ty {
              F32 => self.emit_fmov_s(temp, src)
              _ => self.emit_fmov_d(temp, src)
            }
          }
        }
        for idx in 0..<num_in_regs {
          let (ty, _, _) = float_sources[idx]
          let temp = temp_float_base + idx
          if temp != idx {
            match ty {
              F32 => self.emit_fmov_s(idx, temp)
              _ => self.emit_fmov_d(idx, temp)
            }
          }
        }
        // Extra float results go to SRET buffer (X8)
        for idx in max_float_ret_regs..<float_sources.length() {
          let (_, src, _) = float_sources[idx]
          self.emit_str_d_offset(src, @abi.REG_SRET, extra_offset)
          extra_offset = extra_offset + 8
        }
      } else {
        // Direct move: no conflict possible
        for idx, entry in float_sources {
          let (ty, src, _) = entry
          if idx < max_float_ret_regs {
            if src != idx {
              match ty {
                F32 => self.emit_fmov_s(idx, src)
                _ => self.emit_fmov_d(idx, src)
              }
            }
          } else {
            // Extra float results go to SRET buffer (X8)
            self.emit_str_d_offset(src, @abi.REG_SRET, extra_offset)
            extra_offset = extra_offset + 8
          }
        }
      }
      // Emit epilogue to restore callee-saved registers before return
      self.emit_epilogue(stack_frame)
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
