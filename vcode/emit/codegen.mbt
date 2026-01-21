// Code Generation
// Translates VCode to machine code

///|
/// Convert 8 bytes from Bytes at given offset to Int64 (little-endian)
fn bytes_to_int64_le(bytes : Bytes, offset : Int) -> Int64 {
  let b0 = bytes[offset].to_int64() & 0xFFL
  let b1 = bytes[offset + 1].to_int64() & 0xFFL
  let b2 = bytes[offset + 2].to_int64() & 0xFFL
  let b3 = bytes[offset + 3].to_int64() & 0xFFL
  let b4 = bytes[offset + 4].to_int64() & 0xFFL
  let b5 = bytes[offset + 5].to_int64() & 0xFFL
  let b6 = bytes[offset + 6].to_int64() & 0xFFL
  let b7 = bytes[offset + 7].to_int64() & 0xFFL
  b0 |
  (b1 << 8) |
  (b2 << 16) |
  (b3 << 24) |
  (b4 << 32) |
  (b5 << 40) |
  (b6 << 48) |
  (b7 << 56)
}

///|
fn collect_used_callee_saved(
  func : @regalloc.VCodeFunction,
  enable_pinned_reg : Bool,
  _needs_sret : Bool,
) -> Array[Int] {
  // ABI: SRET uses X8 which is caller-saved, so no special exclusion needed
  let used : @hashset.HashSet[Int] = @hashset.new()
  let mut has_calls = false

  // Check param_pregs: parameters that cross calls are moved to callee-saved registers.
  for preg in func.get_param_pregs() {
    if preg is Some(p) && is_callee_saved_alloc(p.index) {
      if !enable_pinned_reg || p.index != @abi.REG_VMCTX {
        used.add(p.index)
      }
    }
  }
  for block in func.get_blocks() {
    for inst in block.insts {
      // Check if this instruction is a function call
      // Design: use call_type() to determine if an instruction
      // behaves like a call (clobbers caller-saved registers)
      if inst.opcode.call_type() is @instr.Regular {
        has_calls = true
      }
      for def in inst.defs {
        if def.reg is Physical(preg) &&
          preg.class is Int &&
          is_callee_saved_alloc(preg.index) {
          if !enable_pinned_reg || preg.index != @abi.REG_VMCTX {
            used.add(preg.index)
          }
        }
      }
    }
  }
  // If the function makes any calls, we must save LR (X30)
  // Note: X20-X24 are no longer pre-loaded in prologue (on-demand)
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
fn collect_used_callee_saved_fprs(func : @regalloc.VCodeFunction) -> Array[Int] {
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
/// Check if a function makes any calls
fn func_has_calls(func : @regalloc.VCodeFunction) -> Bool {
  for block in func.get_blocks() {
    for inst in block.insts {
      // Check if this instruction is a function call
      match inst.opcode.call_type() {
        @instr.Regular | @instr.TailCall => return true
        _ => ()
      }
    }
  }
  false
}

///|
/// Check if a function reads any incoming stack parameters
fn func_has_incoming_stack_args(func : @regalloc.VCodeFunction) -> Bool {
  for block in func.get_blocks() {
    for inst in block.insts {
      if inst.opcode is @instr.LoadStackParam(_, _) {
        return true
      }
    }
  }
  false
}

///|
/// Check if a function uses vmctx (x19)
/// A function needs vmctx if:
/// - It uses X19 as a physical register in any instruction
/// - It uses X19 in any terminator
fn func_uses_vmctx(func : @regalloc.VCodeFunction) -> Bool {
  for block in func.get_blocks() {
    // Check instructions for X19 usage
    for inst in block.insts {
      for use_ in inst.uses {
        if use_ is Physical(preg) && preg.index == @abi.REG_VMCTX {
          return true
        }
      }
    }
    // Check terminator for X19 usage
    if block.terminator is Some(term) {
      if terminator_uses_vmctx(term) {
        return true
      }
    }
  }
  false
}

///|
/// Check if a terminator uses vmctx (x19)
fn terminator_uses_vmctx(term : @instr.VCodeTerminator) -> Bool {
  match term {
    Return(values) => {
      for v in values {
        if v is Physical(preg) && preg.index == @abi.REG_VMCTX {
          return true
        }
      }
      false
    }
    Branch(cond, _, _) => cond is Physical(preg) && preg.index == @abi.REG_VMCTX
    BranchCmp(lhs, rhs, _, _, _, _) =>
      (lhs is Physical(preg) && preg.index == @abi.REG_VMCTX) ||
      (rhs is Physical(preg2) && preg2.index == @abi.REG_VMCTX)
    BranchZero(reg, _, _, _, _) =>
      reg is Physical(preg) && preg.index == @abi.REG_VMCTX
    BranchCmpImm(lhs, _, _, _, _, _) =>
      lhs is Physical(preg) && preg.index == @abi.REG_VMCTX
    BrTable(index, _, _) =>
      index is Physical(preg) && preg.index == @abi.REG_VMCTX
    Jump(_) | Trap(_) => false
  }
}

///|
/// Emit prologue (Standard)
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
/// ABI Parameter Passing:
/// - X0 = vmctx (cached to pinned vmctx reg)
/// - X1.. = user args
/// - V0-V7 = user float params (S for f32, D for f64)
/// Emit stack pointer adjustment for arbitrary sizes (Standard)
///
/// Handles any size by using:
/// - ADD/SUB with imm12 for values <= 4095
/// - ADD/SUB with imm12<<12 (4KB steps) for larger values
fn MachineCode::emit_sp_adjust(self : MachineCode, amount : Int) -> Unit {
  if amount == 0 {
    return
  }
  let (abs_amount, is_sub) = if amount < 0 {
    (-amount, true)
  } else {
    (amount, false)
  }
  let step = 4096
  if is_sub {
    // Stack allocation: touch stack pages so a guard page can't be skipped by a
    // single large SP adjustment (e.g. large frames on the independent WASM stack).
    //
    // We probe in 4KB steps (<= minimum common page size), then do the remainder.
    // This guarantees that if we cross into a PROT_NONE guard page, we fault while
    // the faulting address is within the guard region (so the signal handler can
    // classify it as "call stack exhausted").
    if abs_amount <= 4095 {
      self.emit_sub_imm(31, 31, abs_amount)
      // Touch at the new SP to fault immediately on overflow.
      self.emit_str_imm(31, 31, 0)
      return
    }
    // abs_amount >= 4096
    let mut remaining = abs_amount
    while remaining >= step {
      self.emit_sub_imm_shifted12(31, 31, 1)
      self.emit_str_imm(31, 31, 0)
      remaining = remaining - step
    }
    if remaining > 0 {
      // remaining < step, so it fits in imm12
      self.emit_sub_imm(31, 31, remaining)
      self.emit_str_imm(31, 31, 0)
    }
    return
  }
  // Stack deallocation (or other upward adjustment): no probing needed.
  if abs_amount <= 4095 {
    self.emit_add_imm(31, 31, abs_amount)
  } else {
    let mut remaining = abs_amount
    while remaining >= step {
      self.emit_add_imm_shifted12(31, 31, 1)
      remaining = remaining - step
    }
    if remaining > 0 {
      self.emit_add_imm(31, 31, remaining)
    }
  }
}

///|
fn MachineCode::emit_prologue(
  self : MachineCode,
  stack_frame : JITStackFrame,
  params : Array[@abi.VReg],
  param_pregs : Array[@abi.PReg?],
  debug_func_idx : Int?,
  abi_settings : @abi.ABISettings,
) -> Unit {
  let saved_gprs = stack_frame.saved_gprs
  let saved_fprs = stack_frame.saved_fprs

  // Standard prologue:
  // 1. Save FP/LR with fixed -16 pre-indexed (avoids SImm7 overflow)
  // 2. Save clobbered GPRs with -16 pre-indexed pushes
  // 3. Save clobbered FPRs with -16 pre-indexed pushes
  // 4. Allocate remaining stack (spill + outgoing) with emit_sp_adjust

  // Step 1: Save FP/LR with fixed -16 pre-indexed
  // stp x29, x30, [sp, #-16]!
  if stack_frame.has_setup_area {
    self.emit_stp_pre(29, 30, 31, -16)
    // mov x29, sp (set frame pointer)
    // Use ADD X29, SP, #0 because MOV with SP register has encoding issues
    // (x31 as source is XZR, not SP, in ORR-based MOV)
    self.emit_add_imm(29, 31, 0)
  }

  // Best-effort: record current wasm func_idx for trap diagnostics.
  match debug_func_idx {
    Some(idx) => {
      self.emit_load_imm64(16, idx.to_int64())
      self.emit_str_w_imm(
        16,
        @abi.REG_CALLEE_VMCTX,
        @abi.VMCTX_DEBUG_CURRENT_FUNC_IDX_OFFSET,
      )
    }
    None => ()
  }

  // Step 2: Save callee-saved GPRs with pre-indexed pushes (Standard style)
  // Approach: handle remainder first, then reverse iterate pairs
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

  // Step 3: Save callee-saved FPRs with pre-indexed pushes (Standard style)
  // Approach: handle remainder first, then reverse iterate pairs
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

  // Step 5: Cache vmctx to X19 (only if function uses vmctx)
  // Note: vmctx is params[0], passed in X0
  // All other values (memory_base, memory_size, func_table, table0_base) are
  // loaded on-demand from vmctx, on-demand.
  if stack_frame.needs_vmctx {
    if !abi_settings.enable_pinned_reg {
      abort("unpinned VMContext ABI not implemented yet")
    }
    self.emit_mov_reg(@abi.REG_VMCTX, 0)
    // Optionally cache memory0 descriptor pointer in X20.
    // This allows `LoadMemBase(mem=0)` to be a single load from [X20 + 0].
    if stack_frame.cache_mem0_desc {
      self.emit_ldr_imm(
        @abi.REG_MEM0_DESC,
        @abi.REG_VMCTX,
        @abi.VMCTX_MEMORY0_OFFSET,
      )
    }
    // Optionally cache func_table pointer.
    if stack_frame.cache_func_table {
      self.emit_ldr_imm(
        @abi.REG_FUNC_TABLE,
        @abi.REG_VMCTX,
        @abi.VMCTX_FUNC_TABLE_OFFSET,
      )
    }
  }

  // Step 6: Move arguments from ABI registers to allocated registers
  // Note: all params use X0-X7 (int) or V0-V7 (float)
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
      Vector =>
        // Vector params come in V0-V7 (same as floats)
        if float_idx < max_float_params {
          let v_src = float_idx
          match dest_preg {
            Some(preg) =>
              if preg.index != v_src {
                OrrVec(preg.index, v_src).emit(self)
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
pub fn emit_function(
  func : @regalloc.VCodeFunction,
  debug_func_idx? : Int? = None,
  force_frame_setup? : Bool = false,
  abi_settings? : @abi.ABISettings = @abi.ABISettings::default(),
) -> MachineCode {
  // Optimize block layout for better branch prediction
  // Loop rotation makes back edges fall through, reducing taken branches
  let func = @layout.optimize_layout(func)
  let mc = MachineCode::new()
  // ABI: Check if we need SRET (more than 8 int or 8 float returns)
  let needs_sret = func.needs_extra_results_ptr()
  // Check if we call functions that return more than register capacity
  // In that case, we need to allocate a local buffer and use X8 (SRET) to point to it
  let calls_multi_value = func.calls_multi_value_function()
  // We need SRET if either we return multi-value OR we call multi-value functions
  let uses_sret = needs_sret || calls_multi_value
  // Collect callee-saved GPRs that this function clobbers
  let clobbered = collect_used_callee_saved(
    func,
    abi_settings.enable_pinned_reg,
    uses_sret,
  )
  // Collect callee-saved FPRs (D8-D15) that this function clobbers
  let clobbered_fprs = collect_used_callee_saved_fprs(func)

  // Build stack frame layout using JITStackFrame
  // has_calls is true if function makes any calls
  let has_calls = func_has_calls(func)
  let has_incoming_stack_args = func_has_incoming_stack_args(func)
  let uses_mem0 = func.uses_mem0()
  let uses_func_table = func.uses_func_table()

  // Check if function uses vmctx (x19)
  // A function needs vmctx if:
  // 1. It directly uses x19 in instructions/terminators
  // 2. It makes any calls (wasm ABI requires passing vmctx to callees)
  // 3. It uses memory0 base loads that may leverage cached memory0 descriptor
  let needs_vmctx = has_calls || func_uses_vmctx(func) || uses_mem0
  let clobbered_gprs = clobbered
  if uses_mem0 && !clobbered_gprs.contains(@abi.REG_MEM0_DESC) {
    clobbered_gprs.push(@abi.REG_MEM0_DESC)
  }
  if uses_func_table && !clobbered_gprs.contains(@abi.REG_FUNC_TABLE) {
    clobbered_gprs.push(@abi.REG_FUNC_TABLE)
  }
  let stack_frame = JITStackFrame::build(
    clobbered_gprs,
    clobbered_fprs,
    func.get_num_spill_slots(),
    has_calls~,
    outgoing_args_size=func.get_max_outgoing_args_size(),
    needs_vmctx~,
    cache_mem0_desc=uses_mem0,
    cache_func_table=uses_func_table,
    force_frame_setup~,
    has_incoming_stack_args~,
  )

  // Emit prologue: save callee-saved registers, cache vmctx to X19, and move params
  mc.emit_prologue(
    stack_frame,
    func.get_params(),
    func.get_param_pregs(),
    debug_func_idx,
    abi_settings,
  )

  // Emit function body (blocks now in optimized order)
  let blocks = func.get_blocks()
  // Optionally tail-merge multiple Return terminators into a shared exit block to
  // avoid duplicating the epilogue sequence at every return site.
  let mut return_count = 0
  let mut max_block_id = -1
  for block in blocks {
    if block.id > max_block_id {
      max_block_id = block.id
    }
    if block.terminator is Some(Return(_)) {
      return_count = return_count + 1
    }
  }
  let shared_exit_block = if return_count > 1 && stack_frame.total_size > 0 {
    Some(max_block_id + 1)
  } else {
    None
  }

  // Compute a conservative liveness mask for physical integer registers at block boundaries.
  // Used by codegen peepholes that remove instructions, to ensure the removed value is not live-out.
  let nblocks = blocks.length()
  let live_out_int : Array[Int64] = Array::make(nblocks, 0L)
  let live_in_int : Array[Int64] = Array::make(nblocks, 0L)
  let use_int : Array[Int64] = Array::make(nblocks, 0L)
  let def_int : Array[Int64] = Array::make(nblocks, 0L)
  let id_to_idx : Map[Int, Int] = {}
  for bi, b in blocks {
    id_to_idx.set(b.id, bi)
  }
  // Per-block use/def.
  for bi, b in blocks {
    let mut defined : Int64 = 0L
    let mut use_mask : Int64 = 0L
    let mut def_mask : Int64 = 0L
    for inst in b.insts {
      for u in inst.uses {
        match u {
          Physical(p) =>
            if p.class is Int {
              let bit = 1L << p.index
              if (defined & bit) == 0L {
                use_mask = use_mask | bit
              }
            }
          Virtual(_) => ()
        }
      }
      for d in inst.defs {
        match d.reg {
          Physical(p) =>
            if p.class is Int {
              let bit = 1L << p.index
              def_mask = def_mask | bit
              defined = defined | bit
            }
          Virtual(_) => ()
        }
      }
    }
    if b.terminator is Some(term) {
      match term {
        Jump(_, args) =>
          for a in args {
            match a {
              Physical(p) =>
                if p.class is Int {
                  let bit = 1L << p.index
                  if (defined & bit) == 0L {
                    use_mask = use_mask | bit
                  }
                }
              Virtual(_) => ()
            }
          }
        Branch(cond, _, _) =>
          match cond {
            Physical(p) =>
              if p.class is Int {
                let bit = 1L << p.index
                if (defined & bit) == 0L {
                  use_mask = use_mask | bit
                }
              }
            Virtual(_) => ()
          }
        BranchCmp(lhs, rhs, _, _, _, _) =>
          for r in [lhs, rhs] {
            match r {
              Physical(p) =>
                if p.class is Int {
                  let bit = 1L << p.index
                  if (defined & bit) == 0L {
                    use_mask = use_mask | bit
                  }
                }
              Virtual(_) => ()
            }
          }
        BranchZero(r, _, _, _, _) =>
          match r {
            Physical(p) =>
              if p.class is Int {
                let bit = 1L << p.index
                if (defined & bit) == 0L {
                  use_mask = use_mask | bit
                }
              }
            Virtual(_) => ()
          }
        BranchCmpImm(lhs, _, _, _, _, _) =>
          match lhs {
            Physical(p) =>
              if p.class is Int {
                let bit = 1L << p.index
                if (defined & bit) == 0L {
                  use_mask = use_mask | bit
                }
              }
            Virtual(_) => ()
          }
        Return(values) =>
          for v in values {
            match v {
              Physical(p) =>
                if p.class is Int {
                  let bit = 1L << p.index
                  if (defined & bit) == 0L {
                    use_mask = use_mask | bit
                  }
                }
              Virtual(_) => ()
            }
          }
        BrTable(index, _, _) =>
          match index {
            Physical(p) =>
              if p.class is Int {
                let bit = 1L << p.index
                if (defined & bit) == 0L {
                  use_mask = use_mask | bit
                }
              }
            Virtual(_) => ()
          }
        Trap(_) => ()
      }
    }
    use_int[bi] = use_mask
    def_int[bi] = def_mask
  }
  // Fixed-point.
  if nblocks > 0 {
    let mut changed = true
    while changed {
      changed = false
      let mut bi = nblocks - 1
      while bi >= 0 {
        let b = blocks[bi]
        let succs : Array[Int] = match b.terminator {
          Some(Jump(target, _)) => [target]
          Some(Branch(_, then_b, else_b)) => [then_b, else_b]
          Some(BranchCmp(_, _, _, _, then_b, else_b)) => [then_b, else_b]
          Some(BranchZero(_, _, _, then_b, else_b)) => [then_b, else_b]
          Some(BranchCmpImm(_, _, _, _, then_b, else_b)) => [then_b, else_b]
          Some(BrTable(_, targets, default)) => {
            let out : Array[Int] = []
            for t in targets {
              out.push(t)
            }
            out.push(default)
            out
          }
          _ => []
        }
        let mut out_mask : Int64 = 0L
        for sid in succs {
          if id_to_idx.get(sid) is Some(si) {
            out_mask = out_mask | live_in_int[si]
          }
        }
        let in_mask = use_int[bi] | (out_mask & (def_int[bi] ^ -1L))
        if out_mask != live_out_int[bi] || in_mask != live_in_int[bi] {
          live_out_int[bi] = out_mask
          live_in_int[bi] = in_mask
          changed = true
        }
        bi = bi - 1
      }
    }
  }
  for i, block in blocks {
    mc.define_label(block.id)
    let mut inst_idx = 0
    while inst_idx < block.insts.length() {
      let inst = block.insts[inst_idx]

      // Peephole: fuse an address add into the following load/store.
      // Pattern:
      //   add addr = base + off
      //   load/store [addr + 0]
      //
      // Emit as a single reg-offset load/store: [base + off].
      if inst.opcode is Add(true) &&
        inst.defs.length() == 1 &&
        inst.uses.length() == 2 &&
        inst_idx + 1 < block.insts.length() {
        let next = block.insts[inst_idx + 1]
        let add_dst = wreg_num(inst.defs[0])
        let add_rn = reg_num(inst.uses[0])
        let add_rm = reg_num(inst.uses[1])

        // Only safe to skip the add if its result is not used elsewhere.
        let mut add_used_later = false
        let mut killed_in_block = false
        for j in (inst_idx + 2)..<block.insts.length() {
          let later = block.insts[j]
          for use_ in later.uses {
            if reg_num(use_) == add_dst {
              add_used_later = true
              break
            }
          }
          if add_used_later {
            break
          }
          for def in later.defs {
            if wreg_num(def) == add_dst {
              killed_in_block = true
              break
            }
          }
          if killed_in_block {
            break
          }
        }
        if !add_used_later && !killed_in_block {
          let bit = 1L << add_dst
          if (live_out_int[i] & bit) != 0L {
            add_used_later = true
          }
        }
        if !add_used_later {
          let mut fused = false
          match next.opcode {
            LoadPtr(ty, 0) => {
              let base_reg = reg_num(next.uses[0])
              if base_reg == add_dst {
                let dst = wreg_num(next.defs[0])
                match ty {
                  I32 => {
                    mc.emit_ldr_w_reg_scaled(dst, add_rn, add_rm, 0)
                    fused = true
                  }
                  I64 => {
                    mc.emit_ldr_reg_scaled(dst, add_rn, add_rm, 0)
                    fused = true
                  }
                  _ => ()
                }
              }
            }
            StorePtr(ty, 0) => {
              let base_reg = reg_num(next.uses[0])
              if base_reg == add_dst {
                let value = reg_num(next.uses[1])
                match ty {
                  I32 => {
                    mc.emit_str_w_reg_scaled(value, add_rn, add_rm, 0)
                    fused = true
                  }
                  I64 => {
                    mc.emit_str_reg_scaled(value, add_rn, add_rm, 0)
                    fused = true
                  }
                  _ => ()
                }
              }
            }
            LoadPtrNarrow(bits, signed, 0) => {
              let base_reg = reg_num(next.uses[0])
              if base_reg == add_dst && !signed {
                let dst = wreg_num(next.defs[0])
                match bits {
                  8 => mc.emit_ldrb_reg(dst, add_rn, add_rm)
                  16 => mc.emit_ldrh_reg(dst, add_rn, add_rm)
                  32 => mc.emit_ldr_w_reg_scaled(dst, add_rn, add_rm, 0)
                  _ => ()
                }
                fused = bits == 8 || bits == 16 || bits == 32
              }
            }
            StorePtrNarrow(bits, 0) => {
              let base_reg = reg_num(next.uses[0])
              if base_reg == add_dst {
                let value = reg_num(next.uses[1])
                match bits {
                  8 => mc.emit_strb_reg(value, add_rn, add_rm)
                  16 => mc.emit_strh_reg(value, add_rn, add_rm)
                  32 => mc.emit_str_w_reg_scaled(value, add_rn, add_rm, 0)
                  _ => ()
                }
                fused = bits == 8 || bits == 16 || bits == 32
              }
            }
            _ => ()
          }
          if fused {
            inst_idx = inst_idx + 2
            continue
          }
        }
      }
      // Peephole: fold u32->u64 zero-extend into following 64-bit add.
      //   extend.u32_64 r = x  ; (mov wR, wX)
      //   add r = add base, r ; => add r, base, wX, uxtw
      // IMPORTANT: Only apply if the extend result is not used by any other
      // instruction. Otherwise we'd skip the extend and later uses would
      // read garbage.
      if inst.opcode is Extend(Unsigned32To64) &&
        inst.defs.length() == 1 &&
        inst.uses.length() == 1 &&
        inst_idx + 1 < block.insts.length() {
        let next = block.insts[inst_idx + 1]
        if next.opcode is Add(true) &&
          next.defs.length() == 1 &&
          next.uses.length() == 2 {
          let ext_dst = wreg_num(inst.defs[0])
          let ext_src = reg_num(inst.uses[0])
          let add_dst = wreg_num(next.defs[0])
          let add_op0 = reg_num(next.uses[0])
          let add_op1 = reg_num(next.uses[1])
          if add_dst == ext_dst {
            // Check that ext_dst is used exactly once (only in the Add)
            // If both operands are ext_dst (ext + ext), don't apply peephole
            let ext_use_count = (if add_op0 == ext_dst { 1 } else { 0 }) +
              (if add_op1 == ext_dst { 1 } else { 0 })
            // Also check that ext_dst is not used in remaining instructions
            let mut has_other_use = ext_use_count != 1
            if !has_other_use {
              for j in (inst_idx + 2)..<block.insts.length() {
                let later_inst = block.insts[j]
                for use_ in later_inst.uses {
                  if reg_num(use_) == ext_dst {
                    has_other_use = true
                    break
                  }
                }
                if has_other_use {
                  break
                }
              }
            }
            if !has_other_use {
              let base = if add_op0 == ext_dst {
                Some(add_op1)
              } else {
                Some(add_op0)
              }
              match base {
                Some(rn) => {
                  mc.emit_add_uxtw(add_dst, rn, ext_src, 0)
                  inst_idx = inst_idx + 2
                  continue
                }
                None => ()
              }
            }
          }
        }
      }
      mc.emit_instruction(inst, stack_frame)
      inst_idx = inst_idx + 1
    }
    if block.terminator is Some(term) {
      // Pass next block ID for fall-through optimization
      let next_block = if i + 1 < blocks.length() {
        Some(blocks[i + 1].id)
      } else {
        None
      }
      mc.emit_terminator_with_epilogue(
        term,
        stack_frame,
        func.get_result_types(),
        next_block,
        shared_exit_block,
      )
    }
  }
  // Emit the shared exit block epilogue (if enabled).
  if shared_exit_block is Some(exit_block) {
    mc.define_label(exit_block)
    mc.emit_epilogue(stack_frame)
    mc.emit_ret(30)
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
        // AArch64 ADD immediate can encode:
        // - imm12 directly (0-4095) when sh=0
        // - imm12 << 12 (multiples of 4096 up to 0xFFF000) when sh=1
        if imm <= 4095 {
          self.emit_add_imm(rd, rn, imm)
        } else if (imm & 0xFFF) == 0 && imm >> 12 <= 4095 {
          // Shifted form: the immediate is a multiple of 4096 and fits in 12 bits after shift
          self.emit_add_imm_shifted12(rd, rn, imm >> 12)
        } else {
          // Immediate too large or cannot be encoded - should not happen
          // Lowering should have rejected immediates > 0xFFF000
          abort("AddImm immediate \{imm} cannot be encoded (max 0xFFF000)")
        }
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
    SubImm(imm, is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_64 {
        self.emit_sub_imm(rd, rn, imm)
      } else {
        self.emit_sub_imm32(rd, rn, imm)
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
    Not(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_64 {
        self.emit_mvn(rd, rn)
      } else {
        self.emit_mvn32(rd, rn)
      }
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
      // Fast path: cached func_table pointer.
      if stack_frame.cache_func_table &&
        ty is I64 &&
        rn == @abi.REG_VMCTX &&
        offset == @abi.VMCTX_FUNC_TABLE_OFFSET {
        if rt != @abi.REG_FUNC_TABLE {
          self.emit_mov_reg(rt, @abi.REG_FUNC_TABLE)
        }
        return
      }
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
      // Peephole: skip redundant mov (rd == rm)
      if rd == rm {
        return
      }
      // Check register class to use appropriate move instruction
      let reg_class = match inst.defs[0].reg {
        Physical(preg) => preg.class
        Virtual(_) => Int // Should not happen at emit time
      }
      match reg_class {
        Float32 => self.emit_fmov_s(rd, rm)
        Float64 => self.emit_fmov_d(rd, rm)
        Int => self.emit_mov_reg(rd, rm)
        Vector => OrrVec(rd, rm).emit(self)
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
      // Compare cond with 0 (Wasm select condition is i32): CMP Wcond, #0
      self.emit_cmp_imm32(cond_reg, 0)
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
        Vector => {
          // Vector select: dst = cond != 0 ? true_val : false_val
          // Uses X16 as GPR temp, V16 as vector temp
          // Step 1: CSET X16, NE (X16 = 0 or 1)
          self.emit_cset(16, NE.to_int())
          // Step 2: NEG X16, X16 (X16 = 0 or -1 for mask)
          self.emit_sub_reg(16, 31, 16) // SUB X16, XZR, X16
          // Step 3: DUP V16.2D, X16 (broadcast to all bits)
          Dup2D(16, 16).emit(self)
          // Step 4: BSL V16.16B, Vtrue.16B, Vfalse.16B
          // BSL: V16 = (true_val & V16) | (false_val & ~V16)
          Bsl16B(16, true_val, false_val).emit(self)
          // Step 5: Move V16 to rd if needed
          if rd != 16 {
            Orr16B(rd, 16, 16).emit(self)
          }
        }
      }
    }
    SelectCmp(kind, is_64) => {
      // SelectCmp: fused compare and select
      // Uses: [cmp_lhs, cmp_rhs, true_val, false_val]
      // Emits: CMP lhs, rhs; CSEL rd, true_val, false_val, cond
      let rd = wreg_num(inst.defs[0])
      let lhs = reg_num(inst.uses[0])
      let rhs = reg_num(inst.uses[1])
      let true_val = reg_num(inst.uses[2])
      let false_val = reg_num(inst.uses[3])
      // Compare lhs with rhs
      if is_64 {
        self.emit_cmp_reg(lhs, rhs)
      } else {
        self.emit_cmp_reg32(lhs, rhs)
      }
      // Check register class to use appropriate select instruction
      let reg_class = match inst.defs[0].reg {
        Physical(preg) => preg.class
        Virtual(_) => Int // Should not happen at emit time
      }
      let cond = cmp_kind_to_cond(kind)
      match reg_class {
        Float32 => self.emit_fcsel_s(rd, true_val, false_val, cond)
        Float64 => self.emit_fcsel_d(rd, true_val, false_val, cond)
        Int => self.emit_csel(rd, true_val, false_val, cond)
        Vector => {
          // Vector select with fused compare
          // Step 1: CSET X16, cond
          self.emit_cset(16, cond)
          // Step 2: NEG X16, X16 (X16 = 0 or -1 for mask)
          self.emit_sub_reg(16, 31, 16)
          // Step 3: DUP V16.2D, X16 (broadcast to all bits)
          Dup2D(16, 16).emit(self)
          // Step 4: BSL V16.16B, Vtrue.16B, Vfalse.16B
          Bsl16B(16, true_val, false_val).emit(self)
          // Step 5: Move V16 to rd if needed
          if rd != 16 {
            Orr16B(rd, 16, 16).emit(self)
          }
        }
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
      // On-demand loading (no scratch registers needed):
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
    Umulh => {
      // Xd = (Xn * Xm) >> 64 (unsigned), uses: [src1, src2]
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_umulh(rd, rn, rm)
    }
    Smulh => {
      // Xd = (Xn * Xm) >> 64 (signed), uses: [src1, src2]
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_smulh(rd, rn, rm)
    }
    Umull => {
      // Xd = Wn * Wm (unsigned 32x32->64), uses: [src1, src2]
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_umull(rd, rn, rm)
    }
    Smull => {
      // Xd = Wn * Wm (signed 32x32->64), uses: [src1, src2]
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_smull(rd, rn, rm)
    }
    ReturnCallIndirect(_num_args, _num_results) => {
      // Tail call optimization
      // Parameters are already set up by lowering phase via:
      // - StoreToStack for overflow arguments
      // - add_use_fixed constraints for register arguments (X0=vmctx, X1-X7/V0-V7=args)
      // Emit only needs to:
      // 1. Restore callee-saved registers (epilogue)
      // 2. BR to function pointer (doesn't save return address, callee returns to our caller)

      // Epilogue - restore callee-saved registers and frame pointer
      // Tail call common sequence
      self.emit_epilogue(stack_frame)

      // BR (not BLR) - jump to function without saving return address
      // The call target is the first use operand.
      // This is the KEY tail call semantic: callee returns directly to our caller.
      let target = match inst.use_constraints[0] {
        @abi.FixedReg(preg) => preg.index
        _ => reg_num(inst.uses[0])
      }
      self.emit_br(target)

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
        Vector => self.emit_ldr_q_imm(rd, 31, spill_base_offset + offset) // LDR Qd, [SP, #offset]
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
        Vector => self.emit_str_q_imm(rt, 31, spill_base_offset + offset) // STR Qt, [SP, #offset]
      }
    }
    LoadStackParam(offset, class) => {
      // Load stack parameter from stack (Standard layout)
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
      // `offset` is the byte offset from entry_SP to the argument.
      // entry_SP = current_SP + frame_size.
      let stack_offset = frame_size + offset
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
        Vector => self.emit_ldr_q_imm(rd, 31, stack_offset) // LDR Qd, [SP, #offset]
      }
    }
    LoadMemBase(memidx) => {
      // Load linear memory base pointer from VMContext
      // Uses: [vmctx], Defs: [result]
      let dst = wreg_num(inst.defs[0])
      let vmctx_reg = reg_num(inst.uses[0])
      if memidx == 0 && stack_frame.cache_mem0_desc {
        // Fast path: memory0 descriptor pointer is cached in X20.
        self.emit_ldr_imm(dst, @abi.REG_MEM0_DESC, 0)
      } else if memidx == 0 {
        self.emit_ldr_imm(dst, vmctx_reg, @abi.VMCTX_MEMORY0_OFFSET)
        self.emit_ldr_imm(dst, dst, 0)
      } else {
        self.emit_ldr_imm(dst, vmctx_reg, @abi.VMCTX_MEMORIES_OFFSET)
        self.emit_ldr_imm(dst, dst, memidx * 8)
        self.emit_ldr_imm(dst, dst, 0)
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
        ArrayNewData => @jit_ffi.c_jit_get_gc_array_new_data_ptr()
        ArrayNewElem => @jit_ffi.c_jit_get_gc_array_new_elem_ptr()
        ArrayInitData => @jit_ffi.c_jit_get_gc_array_init_data_ptr()
        ArrayInitElem => @jit_ffi.c_jit_get_gc_array_init_elem_ptr()
        TypeCheckSubtype => @jit_ffi.c_jit_get_gc_type_check_subtype_ptr()
        // Inline allocation support (ctx-passing)
        RegisterStructInline =>
          @jit_ffi.c_jit_get_gc_register_struct_inline_ptr()
        RegisterArrayInline => @jit_ffi.c_jit_get_gc_register_array_inline_ptr()
        AllocStructSlow => @jit_ffi.c_jit_get_gc_alloc_struct_slow_ptr()
        AllocArraySlow => @jit_ffi.c_jit_get_gc_alloc_array_slow_ptr()
      }
      self.emit_load_imm64(result_reg, func_ptr)
    }
    LoadJITFuncPtr(libcall) => {
      // Load JIT runtime function pointer
      // Uses: [], Defs: [result (function pointer)]
      let result_reg = wreg_num(inst.defs[0])
      let func_ptr = match libcall {
        MemoryGrow => @jit_ffi.c_jit_get_memory_grow_ptr()
        MemorySize => @jit_ffi.c_jit_get_memory_size_ptr()
        MemoryFill => @jit_ffi.c_jit_get_memory_fill_ptr()
        MemoryCopy => @jit_ffi.c_jit_get_memory_copy_ptr()
        MemoryInit => @jit_ffi.c_jit_get_memory_init_ptr()
        DataDrop => @jit_ffi.c_jit_get_data_drop_ptr()
        TableGrow => @jit_ffi.c_jit_get_table_grow_ptr()
        TableFill => @jit_ffi.c_jit_get_table_fill_ptr()
        TableCopy => @jit_ffi.c_jit_get_table_copy_ptr()
        TableInit => @jit_ffi.c_jit_get_table_init_ptr()
        ElemDrop => @jit_ffi.c_jit_get_elem_drop_ptr()
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
    LoadFuncAddr(func_idx) => {
      // Load function address (patched at JIT load time)
      let result_reg = wreg_num(inst.defs[0])
      let fixup_offset = self.current_pos()
      self.emit_load_imm64_fixed(result_reg, 0L)
      self.add_func_addr_fixup(fixup_offset, func_idx, result_reg)
    }
    CallDirect(func_idx, _num_args, _num_results, _call_conv) =>
      // Direct call via BL (patched at JIT load time)
      self.emit_bl_func(func_idx)
    CallPtr(_, _, _call_conv) => {
      // Standard call: all arguments are already in place.
      // Use a fixed-reg constraint if present; otherwise use assigned reg.
      let target = match inst.use_constraints[0] {
        @abi.FixedReg(preg) => preg.index
        _ => reg_num(inst.uses[0])
      }
      self.emit_blr(target)
    }
    AdjustSP(delta) =>
      // Adjust stack pointer by delta bytes
      // Used in Standard call lowering for outgoing args
      if delta > 0 {
        self.emit_add_imm(31, 31, delta)
      } else if delta < 0 {
        self.emit_sub_imm(31, 31, -delta)
      }
    // delta == 0: nop
    StoreToStack(offset) => {
      // Store value to [SP + outgoing_args_offset + offset]
      // Used in Standard call lowering for overflow args
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
        Vector => self.emit_str_q_imm(src, 31, actual_offset)
      }
    }
    LoadSP => {
      // Load stack pointer into result register
      // Uses ADD Xd, SP, #0 because MOV with SP has encoding issues
      let result_reg = wreg_num(inst.defs[0])
      self.emit_add_imm(result_reg, 31, 0)
    }
    // ============ SIMD Instructions ============
    LoadConstV128(bytes) => {
      // Load V128 constant using GPR + INS instructions
      // Strategy: Load two 64-bit halves into X16, X17, then INS into vector register
      let rd = wreg_num(inst.defs[0])

      // Extract low and high 64-bit values (little-endian)
      let low = bytes_to_int64_le(bytes, 0)
      let high = bytes_to_int64_le(bytes, 8)

      // Optimization: all zeros -> MOVI Vd.2D, #0
      if low == 0L && high == 0L {
        MoviZero(rd).emit(self)
      } else {
        // General case: MOVI zero, then INS the two 64-bit values
        MoviZero(rd).emit(self)

        // Insert low 64-bit (D[0])
        if low != 0L {
          self.emit_load_imm64(16, low)
          InsD(rd, 0, 16).emit(self)
        }

        // Insert high 64-bit (D[1])
        if high != 0L {
          self.emit_load_imm64(16, high)
          InsD(rd, 1, 16).emit(self)
        }
      }
    }
    SIMDSplat(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match lane_size {
        B8 => Dup16B(rd, rn).emit(self)
        H16 => Dup8H(rd, rn).emit(self)
        S32 => Dup4S(rd, rn).emit(self)
        D64 => Dup2D(rd, rn).emit(self)
      }
    }
    SIMDSplatF(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        DupElem4S(rd, rn, 0).emit(self)
      } else {
        DupElem2D(rd, rn, 0).emit(self)
      }
    }
    SIMDExtractU(lane_size, lane) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match lane_size {
        B8 => UmovB(rd, rn, lane).emit(self)
        H16 => UmovH(rd, rn, lane).emit(self)
        S32 => UmovS(rd, rn, lane).emit(self)
        D64 => UmovD(rd, rn, lane).emit(self)
      }
    }
    SIMDExtractS(lane_size, lane) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match lane_size {
        B8 => SmovB(rd, rn, lane).emit(self)
        H16 => SmovH(rd, rn, lane).emit(self)
        S32 => SmovS(rd, rn, lane).emit(self)
        D64 => UmovD(rd, rn, lane).emit(self) // No SMOV for D64
      }
    }
    SIMDExtractF(is_f32, lane) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        DupScalarS(rd, rn, lane).emit(self)
      } else {
        DupScalarD(rd, rn, lane).emit(self)
      }
    }
    SIMDInsert(lane_size, lane) => {
      let rd = wreg_num(inst.defs[0])
      let rv = reg_num(inst.uses[0]) // source vector
      let rn = reg_num(inst.uses[1]) // value to insert
      // INS modifies destination in-place, so copy source vector first if different
      if rd != rv {
        OrrVec(rd, rv).emit(self)
      }
      match lane_size {
        B8 => InsB(rd, lane, rn).emit(self)
        H16 => InsH(rd, lane, rn).emit(self)
        S32 => InsS(rd, lane, rn).emit(self)
        D64 => InsD(rd, lane, rn).emit(self)
      }
    }
    SIMDInsertF(is_f32, lane) => {
      let rd = wreg_num(inst.defs[0])
      let rv = reg_num(inst.uses[0]) // source vector
      let rn = reg_num(inst.uses[1]) // value to insert
      // INS modifies destination in-place, so copy source vector first if different
      if rd != rv {
        OrrVec(rd, rv).emit(self)
      }
      if is_f32 {
        InsElemS(rd, lane, rn, 0).emit(self)
      } else {
        InsElemD(rd, lane, rn, 0).emit(self)
      }
    }
    SIMDShuffle(lanes) => {
      // i8x16.shuffle: select lanes from two source vectors using constant indices
      // Use two TBL1 calls instead of TBL2 to avoid consecutive register requirement.
      // Each TBL1 handles one source vector. TBL returns 0 for out-of-range indices.
      let rd = wreg_num(inst.defs[0])
      let temp1 = wreg_num(inst.defs[1]) // temp for TBL1 from first source
      let temp2 = wreg_num(inst.defs[2]) // temp for TBL1 from second source
      let rn = reg_num(inst.uses[0]) // first source (lanes 0-15)
      let rm = reg_num(inst.uses[1]) // second source (lanes 16-31)
      // Use V16 as a reserved scratch vector register for aliasing fixes.
      // This avoids clobbering `rd` when `rd` aliases an input.
      let scratch = 16
      // Aliasing analysis:
      // - rn == temp1: must save before indices1 build destroys temp1
      // - rn == temp2: safe (TBL1 reads rn before indices2 build touches temp2)
      // - rm == temp1: must save before indices1 build destroys temp1
      // - rm == temp2: must save before indices2 build destroys temp2
      //
      // Phase 1: Save temp1 if either input uses it
      let temp1_has_input = rn == temp1 || rm == temp1
      if temp1_has_input {
        Orr16B(scratch, temp1, temp1).emit(self) // Save input before clobbering temp1
      }
      let actual_rn = if rn == temp1 { scratch } else { rn }
      // Build two index vectors at compile time:
      // indices1: lanes < 16 keep original, lanes >= 16 use 0x80 (out of range)
      // indices2: lanes >= 16 use lane-16, lanes < 16 use 0x80 (out of range)
      let mut low1 = 0L
      let mut high1 = 0L
      let mut low2 = 0L
      let mut high2 = 0L
      for i in 0..<8 {
        let lane = lanes[i]
        if lane < 16 {
          low1 = low1 | ((lane.to_int64() & 0xFFL) << (i * 8))
          low2 = low2 | (0x80L << (i * 8))
        } else {
          low1 = low1 | (0x80L << (i * 8))
          low2 = low2 | (((lane - 16).to_int64() & 0xFFL) << (i * 8))
        }
        let lane2 = lanes[i + 8]
        if lane2 < 16 {
          high1 = high1 | ((lane2.to_int64() & 0xFFL) << (i * 8))
          high2 = high2 | (0x80L << (i * 8))
        } else {
          high1 = high1 | (0x80L << (i * 8))
          high2 = high2 | (((lane2 - 16).to_int64() & 0xFFL) << (i * 8))
        }
      }
      // Load indices1 into temp1
      MoviZero(temp1).emit(self)
      if low1 != 0L {
        self.emit_load_imm64(16, low1)
        InsD(temp1, 0, 16).emit(self)
      }
      if high1 != 0L {
        self.emit_load_imm64(16, high1)
        InsD(temp1, 1, 16).emit(self)
      }
      // TBL1 for first source
      Tbl1(temp1, actual_rn, temp1).emit(self) // temp1 = select from rn
      // Phase 2: Handle rm aliasing
      // - rm == temp1: already saved to rd in phase 1
      // - rm == temp2: save now before indices2 build destroys it
      let actual_rm = if rm == temp1 {
        scratch // Already saved before indices1 build
      } else if rm == temp2 {
        Orr16B(scratch, rm, rm).emit(self) // Save input before clobbering temp2
        scratch
      } else {
        rm
      }
      // Load indices2 into temp2
      MoviZero(temp2).emit(self)
      if low2 != 0L {
        self.emit_load_imm64(16, low2)
        InsD(temp2, 0, 16).emit(self)
      }
      if high2 != 0L {
        self.emit_load_imm64(16, high2)
        InsD(temp2, 1, 16).emit(self)
      }
      // TBL1 for second source
      Tbl1(temp2, actual_rm, temp2).emit(self) // temp2 = select from rm
      // Combine results with ORR (0 | value = value)
      Orr16B(rd, temp1, temp2).emit(self)
    }
    SIMDSwizzle => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      Tbl1(rd, rn, rm).emit(self)
    }
    SIMDNot => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      Not16B(rd, rn).emit(self)
    }
    SIMDAnd => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      And16B(rd, rn, rm).emit(self)
    }
    SIMDBic => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      Bic16B(rd, rn, rm).emit(self)
    }
    SIMDOr => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      Orr16B(rd, rn, rm).emit(self)
    }
    SIMDXor => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      Eor16B(rd, rn, rm).emit(self)
    }
    SIMDBsl => {
      // v128.bitselect(a, b, c) = (a & c) | (b & ~c)
      // uses[0] = a, uses[1] = b, uses[2] = c (mask)
      // BSL Vd, Vn, Vm: Vd = (Vn & Vd) | (Vm & ~Vd)
      // So we need: Vd = c (mask), Vn = a, Vm = b
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let c = reg_num(inst.uses[2]) // mask
      // Implement without any fixed scratch vector registers:
      // result = b ^ ((a ^ b) & c)
      //
      // Special case: if rd aliases the mask reg c and c is dead after this op,
      // BSL can compute the result in-place (Vd is both mask input and output).
      if rd == c {
        Bsl16B(rd, a, b).emit(self)
      } else if rd == b {
        // rd = a ^ b
        Eor16B(rd, a, b).emit(self)
        // rd = (a ^ b) & ~c
        Bic16B(rd, rd, c).emit(self)
        // rd = a ^ ((a ^ b) & ~c) = (a & c) | (b & ~c)
        Eor16B(rd, rd, a).emit(self)
      } else {
        // rd = a ^ b
        Eor16B(rd, a, b).emit(self)
        // rd = (a ^ b) & c
        And16B(rd, rd, c).emit(self)
        // rd = b ^ ((a ^ b) & c)
        Eor16B(rd, rd, b).emit(self)
      }
    }
    SIMDAnyTrue => {
      // v128.any_true: returns 1 if any bit is set, 0 otherwise
      // Algorithm: UMAXV Bd, Vn.16B (max byte across lanes)
      //            FMOV Xd, Dn (move to GPR - upper bits are zero)
      //            CMP Xd, #0; CSET Wd, NE
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let tmp = wreg_num(inst.defs[1])
      // Step 1: UMAXV to get max byte into tmp
      Umaxv16B(tmp, rn).emit(self)
      // Step 2: FMOV from Dtmp to X16 (result in low byte, rest is zero)
      self.emit_fmov_d_to_x(16, tmp)
      // Step 3: CMP X16, #0
      self.emit_cmp_imm(16, 0)
      // Step 4: CSET Wd, NE (rd = 1 if X16 != 0, else 0)
      self.emit_cset(rd, 1) // NE condition
    }
    SIMDAllTrue(lane_size) => {
      // i*x*.all_true: returns 1 if all lanes are non-zero, 0 otherwise
      // Algorithm: UMINV (min across lanes), compare != 0
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match lane_size {
        B8 =>
          // i8x16.all_true: UMINV Bd, Vn.16B
          Uminv16B(wreg_num(inst.defs[1]), rn).emit(self)
        H16 =>
          // i16x8.all_true: UMINV Hd, Vn.8H
          Uminv8H(wreg_num(inst.defs[1]), rn).emit(self)
        S32 =>
          // i32x4.all_true: UMINV Sd, Vn.4S
          Uminv4S(wreg_num(inst.defs[1]), rn).emit(self)
        D64 => {
          // i64x2.all_true: (lane0 != 0) && (lane1 != 0)
          UmovD(16, rn, 0).emit(self)
          UmovD(17, rn, 1).emit(self)
          self.emit_cmp_imm(16, 0)
          // If lane0 != 0 then CMP lane1, else force Z=1 so NE is false.
          self.emit_ccmp_imm(17, 0, 4, 1, true)
          self.emit_cset(rd, 1) // NE
          return
        }
      }
      // Common: compare result != 0 and set rd to 0/1
      if lane_size is D64 {
        // Already have result in X16, just compare
        self.emit_cmp_imm(16, 0)
      } else {
        let tmp = wreg_num(inst.defs[1])
        // FMOV from Dtmp to X16
        self.emit_fmov_d_to_x(16, tmp)
        self.emit_cmp_imm(16, 0)
      }
      // CSET Wd, NE
      self.emit_cset(rd, 1)
    }
    SIMDBitmask(lane_size) => {
      // Extract MSB of each lane into an integer
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match lane_size {
        D64 => {
          // i64x2.bitmask: 2 lanes -> 2-bit result
          // Extract lane 0 MSB using UMOV, then shift right by 63
          UmovD(16, rn, 0).emit(self) // X16 = Vn.D[0]
          self.emit_lsr_imm(16, 16, 63) // X16 = bit 0
          // Extract lane 1 MSB
          UmovD(17, rn, 1).emit(self) // X17 = Vn.D[1]
          self.emit_lsr_imm(17, 17, 63) // X17 = bit 1
          // Combine: rd = bit0 | (bit1 << 1)
          self.emit_orr_shifted(rd, 16, 17, @instr.ShiftType::Lsl, 1)
        }
        S32 => {
          // i32x4.bitmask: 4 lanes -> 4-bit result
          // Use LSR immediate, no extra register needed
          UmovS(16, rn, 0).emit(self) // W16 = Vn.S[0]
          self.emit_lsr_imm32(16, 16, 31) // bit 0
          UmovS(17, rn, 1).emit(self)
          self.emit_lsr_imm32(17, 17, 31)
          self.emit_orr_shifted(16, 16, 17, @instr.ShiftType::Lsl, 1) // bits 0-1
          UmovS(17, rn, 2).emit(self)
          self.emit_lsr_imm32(17, 17, 31)
          self.emit_orr_shifted(16, 16, 17, @instr.ShiftType::Lsl, 2) // bits 0-2
          UmovS(17, rn, 3).emit(self)
          self.emit_lsr_imm32(17, 17, 31)
          self.emit_orr_shifted(rd, 16, 17, @instr.ShiftType::Lsl, 3) // bits 0-3
        }
        H16 => {
          // i16x8.bitmask: 8 lanes -> 8-bit result
          // Use LSR immediate, no extra register needed
          UmovH(16, rn, 0).emit(self)
          self.emit_lsr_imm32(16, 16, 15) // bit 0
          UmovH(17, rn, 1).emit(self)
          self.emit_lsr_imm32(17, 17, 15)
          self.emit_orr_shifted(16, 16, 17, @instr.ShiftType::Lsl, 1)
          UmovH(17, rn, 2).emit(self)
          self.emit_lsr_imm32(17, 17, 15)
          self.emit_orr_shifted(16, 16, 17, @instr.ShiftType::Lsl, 2)
          UmovH(17, rn, 3).emit(self)
          self.emit_lsr_imm32(17, 17, 15)
          self.emit_orr_shifted(16, 16, 17, @instr.ShiftType::Lsl, 3)
          UmovH(17, rn, 4).emit(self)
          self.emit_lsr_imm32(17, 17, 15)
          self.emit_orr_shifted(16, 16, 17, @instr.ShiftType::Lsl, 4)
          UmovH(17, rn, 5).emit(self)
          self.emit_lsr_imm32(17, 17, 15)
          self.emit_orr_shifted(16, 16, 17, @instr.ShiftType::Lsl, 5)
          UmovH(17, rn, 6).emit(self)
          self.emit_lsr_imm32(17, 17, 15)
          self.emit_orr_shifted(16, 16, 17, @instr.ShiftType::Lsl, 6)
          UmovH(17, rn, 7).emit(self)
          self.emit_lsr_imm32(17, 17, 15)
          self.emit_orr_shifted(rd, 16, 17, @instr.ShiftType::Lsl, 7)
        }
        B8 => {
          // i8x16.bitmask: 16 lanes -> 16-bit result
          // Use weighted add approach for efficiency
          // Temps allocated by regalloc: defs[1]=weights, defs[2]=shift, defs[3]=work
          let v_weights = wreg_num(inst.defs[1])
          let v_shift = wreg_num(inst.defs[2])
          let v_work = wreg_num(inst.defs[3])
          // Check for aliasing: if rn aliases v_weights or v_shift, we must copy
          // rn to v_work first before those temps are overwritten.
          // (rn == v_work is safe because Sshl reads before writing)
          let actual_rn = if rn == v_weights || rn == v_shift {
            Orr16B(v_work, rn, rn).emit(self) // MOV v_work, rn
            v_work
          } else {
            rn
          }
          // Step 1: Load weights [1,2,4,8,16,32,64,128,1,2,4,8,16,32,64,128]
          // 0x8040201008040201 = weights for 8 bytes (little endian)
          // Use X16/X17 (linker scratch GPR) for loading immediate
          LoadImm64(17, 0x8040201008040201L).emit(self)
          self.emit_fmov_x_to_d(v_weights, 17) // v_weights.D[0] = weights
          DupElem2D(v_weights, v_weights, 0).emit(self) // v_weights.D[1] = v_weights.D[0]
          // Step 2: Shift each byte right by 7 to get 0/1 based on MSB
          // Load -7 into all lanes (0xF9 = -7 in signed byte)
          self.emit_movz(17, 0xF9, 0) // X17 = 0xF9 = -7 as unsigned byte
          Dup16B(v_shift, 17).emit(self) // v_shift.16B = all 0xF9 = -7
          Sshl16B(v_work, actual_rn, v_shift).emit(self) // v_work = signed shift right by 7
          // Now v_work has 0x00 or 0xFF in each lane (all 0s or all 1s)
          // Step 3: AND with weights to get weighted bits
          And16B(v_work, v_work, v_weights).emit(self) // v_work = weighted bits
          // Step 4: Pairwise add to combine
          Uaddlp8H(v_work, v_work).emit(self) // v_work.8H = pairwise sums
          Uaddlp4S(v_work, v_work).emit(self) // v_work.4S = pairwise sums
          Uaddlp2D(v_work, v_work).emit(self) // v_work.2D = pairwise sums
          // v_work.D[0] = low 8 bits, v_work.D[1] = high 8 bits
          self.emit_fmov_d_to_x(16, v_work) // X16 = low 8 bits
          self.emit_ext_16b(v_shift, v_work, v_work, 8) // rotate to get high half (reuse v_shift)
          self.emit_fmov_d_to_x(17, v_shift) // X17 = high 8 bits
          // Combine: rd = low | (high << 8)
          self.emit_orr_shifted(rd, 16, 17, @instr.ShiftType::Lsl, 8)
        }
      }
    }
    SIMDAdd(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match lane_size {
        B8 => Add16B(rd, rn, rm).emit(self)
        H16 => Add8H(rd, rn, rm).emit(self)
        S32 => Add4S(rd, rn, rm).emit(self)
        D64 => Add2D(rd, rn, rm).emit(self)
      }
    }
    SIMDSub(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match lane_size {
        B8 => Sub16B(rd, rn, rm).emit(self)
        H16 => Sub8H(rd, rn, rm).emit(self)
        S32 => Sub4S(rd, rn, rm).emit(self)
        D64 => Sub2D(rd, rn, rm).emit(self)
      }
    }
    SIMDMul(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match lane_size {
        B8 => abort("SIMD JIT: MUL.16B not supported, need expansion")
        H16 => Mul8H(rd, rn, rm).emit(self)
        S32 => Mul4S(rd, rn, rm).emit(self)
        D64 => {
          // i64x2.mul emulation: NEON doesn't have MUL.2D
          // a*b = (a_hi*b_lo + a_lo*b_hi) << 32 + a_lo*b_lo
          // IMPORTANT: the result register can alias an input register.
          // Use temporaries for all intermediates and only write `rd` at the end.
          //
          // Also IMPORTANT: this expands to multiple machine instructions, so we
          // must not rely on `rn` / `rm` remaining unmodified after the first
          // instruction. Regalloc may legally reuse dead input regs for temps.
          // Copy inputs into reserved scratch V16/V17 first.
          //
          // Temps allocated by regalloc: defs[1..5]
          let t0 = wreg_num(inst.defs[1]) // a_lo (2s)
          let t1 = wreg_num(inst.defs[2]) // b_lo (2s), then reused as cross2 (2d)
          let t2 = wreg_num(inst.defs[3]) // low product (2d)
          let t3 = wreg_num(inst.defs[4]) // scratch for hi halves (2s)
          let t4 = wreg_num(inst.defs[5]) // cross sum (2d)

          // Save inputs to scratch regs (V16/V17 are non-allocatable).
          let a = 16
          let b = 17
          OrrVec(a, rn).emit(self)
          OrrVec(b, rm).emit(self)

          // 1. Extract low 32-bit halves
          Xtn2S(t0, a).emit(self) // t0 = [a0_lo, a1_lo]
          Xtn2S(t1, b).emit(self) // t1 = [b0_lo, b1_lo]

          // 2. low = a_lo * b_lo
          Umull2D(t2, t0, t1).emit(self)

          // 3. a_hi = high 32-bit halves of a
          Rev64_4S(t3, a).emit(self)
          Xtn2S(t3, t3).emit(self) // t3 = [a0_hi, a1_hi]

          // 4. cross1 = a_hi * b_lo
          Umull2D(t4, t3, t1).emit(self)

          // 5. b_hi = high 32-bit halves of b
          Rev64_4S(t3, b).emit(self)
          Xtn2S(t3, t3).emit(self) // t3 = [b0_hi, b1_hi]

          // 6. cross2 = a_lo * b_hi (reuse t1 as a 2d dest)
          Umull2D(t1, t0, t3).emit(self)

          // 7. cross = cross1 + cross2
          Add2D(t4, t4, t1).emit(self)

          // 8. Shift cross products left by 32
          ShlImm2D(t4, t4, 32).emit(self)

          // 9. Add to low*low to get final result
          Add2D(rd, t2, t4).emit(self)
        }
      }
    }
    SIMDSqadd(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match lane_size {
        B8 => Sqadd16B(rd, rn, rm).emit(self)
        H16 => Sqadd8H(rd, rn, rm).emit(self)
        S32 => Sqadd4S(rd, rn, rm).emit(self)
        D64 => Sqadd2D(rd, rn, rm).emit(self)
      }
    }
    SIMDUqadd(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match lane_size {
        B8 => Uqadd16B(rd, rn, rm).emit(self)
        H16 => Uqadd8H(rd, rn, rm).emit(self)
        S32 => Uqadd4S(rd, rn, rm).emit(self)
        D64 => Uqadd2D(rd, rn, rm).emit(self)
      }
    }
    SIMDSqsub(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match lane_size {
        B8 => Sqsub16B(rd, rn, rm).emit(self)
        H16 => Sqsub8H(rd, rn, rm).emit(self)
        S32 => Sqsub4S(rd, rn, rm).emit(self)
        D64 => Sqsub2D(rd, rn, rm).emit(self)
      }
    }
    SIMDUqsub(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match lane_size {
        B8 => Uqsub16B(rd, rn, rm).emit(self)
        H16 => Uqsub8H(rd, rn, rm).emit(self)
        S32 => Uqsub4S(rd, rn, rm).emit(self)
        D64 => Uqsub2D(rd, rn, rm).emit(self)
      }
    }
    SIMDSmin(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match lane_size {
        B8 => Smin16B(rd, rn, rm).emit(self)
        H16 => Smin8H(rd, rn, rm).emit(self)
        S32 => Smin4S(rd, rn, rm).emit(self)
        D64 => abort("SIMD JIT: SMIN.2D not supported")
      }
    }
    SIMDUmin(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match lane_size {
        B8 => Umin16B(rd, rn, rm).emit(self)
        H16 => Umin8H(rd, rn, rm).emit(self)
        S32 => Umin4S(rd, rn, rm).emit(self)
        D64 => abort("SIMD JIT: UMIN.2D not supported")
      }
    }
    SIMDSmax(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match lane_size {
        B8 => Smax16B(rd, rn, rm).emit(self)
        H16 => Smax8H(rd, rn, rm).emit(self)
        S32 => Smax4S(rd, rn, rm).emit(self)
        D64 => abort("SIMD JIT: SMAX.2D not supported")
      }
    }
    SIMDUmax(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match lane_size {
        B8 => Umax16B(rd, rn, rm).emit(self)
        H16 => Umax8H(rd, rn, rm).emit(self)
        S32 => Umax4S(rd, rn, rm).emit(self)
        D64 => abort("SIMD JIT: UMAX.2D not supported")
      }
    }
    SIMDUrhadd(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match lane_size {
        B8 => Urhadd16B(rd, rn, rm).emit(self)
        H16 => Urhadd8H(rd, rn, rm).emit(self)
        S32 => Urhadd4S(rd, rn, rm).emit(self)
        D64 => abort("SIMD JIT: URHADD.2D not supported")
      }
    }
    SIMDAbs(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match lane_size {
        B8 => Abs16B(rd, rn).emit(self)
        H16 => Abs8H(rd, rn).emit(self)
        S32 => Abs4S(rd, rn).emit(self)
        D64 => Abs2D(rd, rn).emit(self)
      }
    }
    SIMDNeg(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match lane_size {
        B8 => Neg16B(rd, rn).emit(self)
        H16 => Neg8H(rd, rn).emit(self)
        S32 => Neg4S(rd, rn).emit(self)
        D64 => Neg2D(rd, rn).emit(self)
      }
    }
    SIMDCnt => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      Cnt16B(rd, rn).emit(self)
    }
    SIMDBroadcastShift(lane_size, negate) => {
      // Mask scalar shift amount and broadcast to vector
      // Uses: [shift_scalar], Defs: [temp_gpr, shift_vec]
      let temp_gpr = wreg_num(inst.defs[0]) // temp GPR for masked shift
      let rd = wreg_num(inst.defs[1]) // destination vector register
      let rm = reg_num(inst.uses[0]) // source scalar (GPR)
      // Mask shift amount to valid range using UBFX
      let width = match lane_size {
        B8 => 3 // mask = 7 = 0b111
        H16 => 4 // mask = 15 = 0b1111
        S32 => 5 // mask = 31 = 0b11111
        D64 => 6 // mask = 63 = 0b111111
      }
      UbfxWidth(temp_gpr, rm, width).emit(self)
      // Negate if needed (for right shifts)
      if negate {
        self.emit_sub_reg(temp_gpr, 31, temp_gpr) // temp_gpr = -temp_gpr
      }
      // Broadcast to all lanes
      match lane_size {
        B8 => Dup16B(rd, temp_gpr).emit(self)
        H16 => Dup8H(rd, temp_gpr).emit(self)
        S32 => Dup4S(rd, temp_gpr).emit(self)
        D64 => Dup2D(rd, temp_gpr).emit(self)
      }
    }
    SIMDShiftByVec(lane_size, use_ushl) => {
      // Vector shift: input_vec shifted by shift_vec (already broadcast)
      // Uses: [input_vec, shift_vec], Defs: [result]
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0]) // input vector
      let rm = reg_num(inst.uses[1]) // shift vector
      if use_ushl {
        // Unsigned shift (USHL)
        match lane_size {
          B8 => Ushl16B(rd, rn, rm).emit(self)
          H16 => Ushl8H(rd, rn, rm).emit(self)
          S32 => Ushl4S(rd, rn, rm).emit(self)
          D64 => Ushl2D(rd, rn, rm).emit(self)
        }
      } else {
        // Signed shift (SSHL) - used for left shift and signed right shift
        match lane_size {
          B8 => Sshl16B(rd, rn, rm).emit(self)
          H16 => Sshl8H(rd, rn, rm).emit(self)
          S32 => Sshl4S(rd, rn, rm).emit(self)
          D64 => Sshl2D(rd, rn, rm).emit(self)
        }
      }
    }
    SIMDCmp(lane_size, cmp_kind) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match (lane_size, cmp_kind) {
        (B8, Eq) => Cmeq16B(rd, rn, rm).emit(self)
        (H16, Eq) => Cmeq8H(rd, rn, rm).emit(self)
        (S32, Eq) => Cmeq4S(rd, rn, rm).emit(self)
        (D64, Eq) => Cmeq2D(rd, rn, rm).emit(self)
        (B8, GtS) => Cmgt16B(rd, rn, rm).emit(self)
        (H16, GtS) => Cmgt8H(rd, rn, rm).emit(self)
        (S32, GtS) => Cmgt4S(rd, rn, rm).emit(self)
        (D64, GtS) => Cmgt2D(rd, rn, rm).emit(self)
        (B8, GeS) => Cmge16B(rd, rn, rm).emit(self)
        (H16, GeS) => Cmge8H(rd, rn, rm).emit(self)
        (S32, GeS) => Cmge4S(rd, rn, rm).emit(self)
        (D64, GeS) => Cmge2D(rd, rn, rm).emit(self)
        (B8, GtU) => Cmhi16B(rd, rn, rm).emit(self)
        (H16, GtU) => Cmhi8H(rd, rn, rm).emit(self)
        (S32, GtU) => Cmhi4S(rd, rn, rm).emit(self)
        (D64, GtU) => Cmhi2D(rd, rn, rm).emit(self)
        (B8, GeU) => Cmhs16B(rd, rn, rm).emit(self)
        (H16, GeU) => Cmhs8H(rd, rn, rm).emit(self)
        (S32, GeU) => Cmhs4S(rd, rn, rm).emit(self)
        (D64, GeU) => Cmhs2D(rd, rn, rm).emit(self)
      }
    }
    SIMDNarrow(lane_size, is_signed) => {
      // Narrow two v128 to one v128 with saturation
      // First input -> lower half, second input -> upper half
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0]) // First input
      let rm = reg_num(inst.uses[1]) // Second input
      match (lane_size, is_signed) {
        (B8, true) => {
          // i8x16.narrow_i16x8_s
          Sqxtn8B(rd, rn).emit(self) // Lower 8 bytes from first input
          Sqxtn2_16B(rd, rm).emit(self) // Upper 8 bytes from second input
        }
        (B8, false) => {
          // i8x16.narrow_i16x8_u
          Sqxtun8B(rd, rn).emit(self) // Lower 8 bytes from first input
          Sqxtun2_16B(rd, rm).emit(self) // Upper 8 bytes from second input
        }
        (H16, true) => {
          // i16x8.narrow_i32x4_s
          Sqxtn4H(rd, rn).emit(self) // Lower 4 halfwords from first input
          Sqxtn2_8H(rd, rm).emit(self) // Upper 4 halfwords from second input
        }
        (H16, false) => {
          // i16x8.narrow_i32x4_u
          Sqxtun4H(rd, rn).emit(self) // Lower 4 halfwords from first input
          Sqxtun2_8H(rd, rm).emit(self) // Upper 4 halfwords from second input
        }
        _ => abort("Unsupported narrow operation")
      }
    }
    SIMDExtendLow(lane_size, is_signed) => {
      // Extend lower half of input to full width
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match (lane_size, is_signed) {
        (H16, true) => Sxtl8H(rd, rn).emit(self) // i8 -> i16 (low 8 bytes)
        (H16, false) => Uxtl8H(rd, rn).emit(self)
        (S32, true) => Sxtl4S(rd, rn).emit(self) // i16 -> i32 (low 4 halfwords)
        (S32, false) => Uxtl4S(rd, rn).emit(self)
        (D64, true) => Sxtl2D(rd, rn).emit(self) // i32 -> i64 (low 2 words)
        (D64, false) => Uxtl2D(rd, rn).emit(self)
        _ => abort("Unsupported extend low operation")
      }
    }
    SIMDExtendHigh(lane_size, is_signed) => {
      // Extend upper half of input to full width
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match (lane_size, is_signed) {
        (H16, true) => Sxtl2_8H(rd, rn).emit(self) // i8 -> i16 (high 8 bytes)
        (H16, false) => Uxtl2_8H(rd, rn).emit(self)
        (S32, true) => Sxtl2_4S(rd, rn).emit(self) // i16 -> i32 (high 4 halfwords)
        (S32, false) => Uxtl2_4S(rd, rn).emit(self)
        (D64, true) => Sxtl2_2D(rd, rn).emit(self) // i32 -> i64 (high 2 words)
        (D64, false) => Uxtl2_2D(rd, rn).emit(self)
        _ => abort("Unsupported extend high operation")
      }
    }
    SIMDExtMulLow(lane_size, is_signed) => {
      // Extended multiply: multiply lower halves and produce wider result
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match (lane_size, is_signed) {
        (H16, true) => Smull8H(rd, rn, rm).emit(self) // i8x8 -> i16x8
        (H16, false) => Umull8H(rd, rn, rm).emit(self)
        (S32, true) => Smull4S(rd, rn, rm).emit(self) // i16x4 -> i32x4
        (S32, false) => Umull4S(rd, rn, rm).emit(self)
        (D64, true) => Smull2D(rd, rn, rm).emit(self) // i32x2 -> i64x2
        (D64, false) => Umull2D(rd, rn, rm).emit(self)
        _ => abort("Unsupported extmul low operation")
      }
    }
    SIMDExtMulHigh(lane_size, is_signed) => {
      // Extended multiply: multiply upper halves and produce wider result
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match (lane_size, is_signed) {
        (H16, true) => Smull2_8H(rd, rn, rm).emit(self) // i8x8 -> i16x8
        (H16, false) => Umull2_8H(rd, rn, rm).emit(self)
        (S32, true) => Smull2_4S(rd, rn, rm).emit(self) // i16x4 -> i32x4
        (S32, false) => Umull2_4S(rd, rn, rm).emit(self)
        (D64, true) => Smull2_2D(rd, rn, rm).emit(self) // i32x2 -> i64x2
        (D64, false) => Umull2_2D(rd, rn, rm).emit(self)
        _ => abort("Unsupported extmul high operation")
      }
    }
    SIMDExtAddPairwise(lane_size, is_signed) => {
      // Extended add pairwise: add adjacent pairs and widen result
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match (lane_size, is_signed) {
        (H16, true) => Saddlp8H(rd, rn).emit(self) // pairs of i8 -> i16
        (H16, false) => Uaddlp8H(rd, rn).emit(self)
        (S32, true) => Saddlp4S(rd, rn).emit(self) // pairs of i16 -> i32
        (S32, false) => Uaddlp4S(rd, rn).emit(self)
        _ => abort("Unsupported ext add pairwise operation")
      }
    }
    SIMDDot => {
      // i32x4.dot_i16x8_s: multiply i16 pairs and add to get i32
      // result[i] = a[2*i]*b[2*i] + a[2*i+1]*b[2*i+1]
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      // Step 1: SMULL low halves [a0*b0, a1*b1, a2*b2, a3*b3]
      Smull4S(16, rn, rm).emit(self)
      // Step 2: SMULL2 high halves [a4*b4, a5*b5, a6*b6, a7*b7]
      Smull2_4S(17, rn, rm).emit(self)
      // Step 3: ADDP to add adjacent pairs
      // Result: [a0*b0+a1*b1, a2*b2+a3*b3, a4*b4+a5*b5, a6*b6+a7*b7]
      Addp4S(rd, 16, 17).emit(self)
    }
    SIMDQ15MulrSat => {
      // i16x8.q15mulr_sat_s: saturating Q15 rounding multiply
      // result = saturate((a * b + 0x4000) >> 15)
      // SQRDMULH does exactly this
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      Sqrdmulh8H(rd, rn, rm).emit(self)
    }
    SIMDFAdd(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        Fadd4S(rd, rn, rm).emit(self)
      } else {
        Fadd2D(rd, rn, rm).emit(self)
      }
    }
    SIMDFSub(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        Fsub4S(rd, rn, rm).emit(self)
      } else {
        Fsub2D(rd, rn, rm).emit(self)
      }
    }
    SIMDFMul(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        Fmul4S(rd, rn, rm).emit(self)
      } else {
        Fmul2D(rd, rn, rm).emit(self)
      }
    }
    SIMDFDiv(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        Fdiv4S(rd, rn, rm).emit(self)
      } else {
        Fdiv2D(rd, rn, rm).emit(self)
      }
    }
    SIMDFMin(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        Fmin4S(rd, rn, rm).emit(self)
      } else {
        Fmin2D(rd, rn, rm).emit(self)
      }
    }
    SIMDFMax(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        Fmax4S(rd, rn, rm).emit(self)
      } else {
        Fmax2D(rd, rn, rm).emit(self)
      }
    }
    SIMDFPMin(is_f32) => {
      // pmin: returns min, but with comparison-based selection
      // pmin(a, b) = if a < b then a else b
      // Use FCMGT + BSL: FCMGT Vmask, Va, Vb; BSL Vmask, Vb, Va
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0]) // a
      let rm = reg_num(inst.uses[1]) // b
      // Step 1: FCMGT V16, Vn, Vm (mask = all 1s where a > b)
      if is_f32 {
        Fcmgt4S(16, rn, rm).emit(self)
      } else {
        Fcmgt2D(16, rn, rm).emit(self)
      }
      // Step 2: BSL V16, Vm, Vn (where a > b, use b; else use a)
      Bsl16B(16, rm, rn).emit(self)
      // Step 3: Move result to rd
      if rd != 16 {
        Orr16B(rd, 16, 16).emit(self)
      }
    }
    SIMDFPMax(is_f32) => {
      // pmax: returns max, but with comparison-based selection
      // pmax(a, b) = if b > a then b else a
      // Use FCMGT + BSL: FCMGT Vmask, Vb, Va; BSL Vmask, Vb, Va
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0]) // a
      let rm = reg_num(inst.uses[1]) // b
      // Step 1: FCMGT V16, Vm, Vn (mask = all 1s where b > a)
      if is_f32 {
        Fcmgt4S(16, rm, rn).emit(self)
      } else {
        Fcmgt2D(16, rm, rn).emit(self)
      }
      // Step 2: BSL V16, Vm, Vn (where b > a, use b; else use a)
      Bsl16B(16, rm, rn).emit(self)
      // Step 3: Move result to rd
      if rd != 16 {
        Orr16B(rd, 16, 16).emit(self)
      }
    }
    SIMDFAbs(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        Fabs4S(rd, rn).emit(self)
      } else {
        Fabs2D(rd, rn).emit(self)
      }
    }
    SIMDFNeg(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        Fneg4S(rd, rn).emit(self)
      } else {
        Fneg2D(rd, rn).emit(self)
      }
    }
    SIMDFSqrt(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        Fsqrt4S(rd, rn).emit(self)
      } else {
        Fsqrt2D(rd, rn).emit(self)
      }
    }
    SIMDFCeil(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        Frintp4S(rd, rn).emit(self)
      } else {
        Frintp2D(rd, rn).emit(self)
      }
    }
    SIMDFFloor(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        Frintm4S(rd, rn).emit(self)
      } else {
        Frintm2D(rd, rn).emit(self)
      }
    }
    SIMDFTrunc(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        Frintz4S(rd, rn).emit(self)
      } else {
        Frintz2D(rd, rn).emit(self)
      }
    }
    SIMDFNearest(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        Frintn4S(rd, rn).emit(self)
      } else {
        Frintn2D(rd, rn).emit(self)
      }
    }
    SIMDFCmp(is_f32, kind) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match kind {
        Eq =>
          if is_f32 {
            Fcmeq4S(rd, rn, rm).emit(self)
          } else {
            Fcmeq2D(rd, rn, rm).emit(self)
          }
        Gt =>
          if is_f32 {
            Fcmgt4S(rd, rn, rm).emit(self)
          } else {
            Fcmgt2D(rd, rn, rm).emit(self)
          }
        Ge =>
          if is_f32 {
            Fcmge4S(rd, rn, rm).emit(self)
          } else {
            Fcmge2D(rd, rn, rm).emit(self)
          }
      }
    }
    SIMDFCvtToIntS(is_f32) => {
      // FCVTZS: float -> signed int (truncating, saturating)
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        Fcvtzs4S(rd, rn).emit(self)
      } else {
        Fcvtzs2D(rd, rn).emit(self)
      }
    }
    SIMDFCvtToIntU(is_f32) => {
      // FCVTZU: float -> unsigned int (truncating, saturating)
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        Fcvtzu4S(rd, rn).emit(self)
      } else {
        Fcvtzu2D(rd, rn).emit(self)
      }
    }
    SIMDIntToFloatS(is_f32) => {
      // SCVTF: signed int -> float
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        Scvtf4S(rd, rn).emit(self)
      } else {
        Scvtf2D(rd, rn).emit(self)
      }
    }
    SIMDIntToFloatU(is_f32) => {
      // UCVTF: unsigned int -> float
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        Ucvtf4S(rd, rn).emit(self)
      } else {
        Ucvtf2D(rd, rn).emit(self)
      }
    }
    SIMDTruncSatF64ToI32SZero => {
      // f64x2 -> i32x4 with zeros in high lanes (signed)
      // FCVTZS Vtmp.2D, Vn.2D; SQXTN Vd.2S, Vtmp.2D
      let rd = wreg_num(inst.defs[0])
      let tmp = wreg_num(inst.defs[1])
      let rn = reg_num(inst.uses[0])
      Fcvtzs2D(tmp, rn).emit(self) // Convert to i64x2 with saturation to INT64 range
      Sqxtn2S(rd, tmp).emit(self) // Saturating narrow to i32x2 (zeros in high lanes)
    }
    SIMDTruncSatF64ToI32UZero => {
      // f64x2 -> i32x4 with zeros in high lanes (unsigned)
      // FCVTZU Vtmp.2D, Vn.2D; UQXTN Vd.2S, Vtmp.2D
      let rd = wreg_num(inst.defs[0])
      let tmp = wreg_num(inst.defs[1])
      let rn = reg_num(inst.uses[0])
      Fcvtzu2D(tmp, rn).emit(self) // Convert to u64x2 with saturation to UINT64 range
      Uqxtn2S(rd, tmp).emit(self) // Saturating narrow to u32x2 (zeros in high lanes)
    }
    SIMDConvertLowI32ToF64S => {
      // Low 2 i32 lanes -> f64x2 (signed)
      // SXTL Vtmp.2D, Vn.2S; SCVTF Vd.2D, Vtmp.2D
      let rd = wreg_num(inst.defs[0])
      let tmp = wreg_num(inst.defs[1])
      let rn = reg_num(inst.uses[0])
      Sxtl2D(tmp, rn).emit(self) // Sign-extend i32x2 to i64x2
      Scvtf2D(rd, tmp).emit(self) // Convert i64x2 to f64x2
    }
    SIMDConvertLowI32ToF64U => {
      // Low 2 i32 lanes -> f64x2 (unsigned)
      // UXTL Vtmp.2D, Vn.2S; UCVTF Vd.2D, Vtmp.2D
      let rd = wreg_num(inst.defs[0])
      let tmp = wreg_num(inst.defs[1])
      let rn = reg_num(inst.uses[0])
      Uxtl2D(tmp, rn).emit(self) // Zero-extend i32x2 to i64x2
      Ucvtf2D(rd, tmp).emit(self) // Convert i64x2 to f64x2
    }
    SIMDDemoteF64ToF32Zero => {
      // f64x2 -> f32x4 with zeros in high lanes
      // FCVTN Vd.2S, Vn.2D (high 64 bits become zeros)
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      Fcvtn2S(rd, rn).emit(self)
    }
    SIMDPromoteLowF32ToF64 => {
      // Low 2 f32 lanes -> f64x2
      // FCVTL Vd.2D, Vn.2S
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      Fcvtl2D(rd, rn).emit(self)
    }
    SIMDLoad(offset) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      LdrQ(rd, rn, offset).emit(self)
    }
    SIMDStore(offset) => {
      let rt = reg_num(inst.uses[0])
      let rn = reg_num(inst.uses[1])
      StrQ(rt, rn, offset).emit(self)
    }
    SIMDLoadSplat(lane_size, offset) => {
      // Load and replicate to all lanes
      // uses[0] = base address
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // LD1R doesn't have immediate offset form, compute address if needed
      if offset == 0 {
        match lane_size {
          B8 => Ld1rB(rd, rn).emit(self)
          H16 => Ld1rH(rd, rn).emit(self)
          S32 => Ld1rS(rd, rn).emit(self)
          D64 => Ld1rD(rd, rn).emit(self)
        }
      } else {
        // Use x16 as temp for address calculation
        AddImm(16, rn, offset).emit(self)
        match lane_size {
          B8 => Ld1rB(rd, 16).emit(self)
          H16 => Ld1rH(rd, 16).emit(self)
          S32 => Ld1rS(rd, 16).emit(self)
          D64 => Ld1rD(rd, 16).emit(self)
        }
      }
    }
    SIMDLoadExtend(src_bits, signed, offset) => {
      // Load 64 bits and extend each element
      // uses[0] = base address
      // src_bits: 8 -> i8x8 to i16x8, 16 -> i16x4 to i32x4, 32 -> i32x2 to i64x2
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // Load 64 bits into low half using LDR D
      LdrDImm(rd, rn, offset).emit(self)
      // Then extend using SXTL/UXTL
      match (src_bits, signed) {
        (8, true) => Sxtl8H(rd, rd).emit(self) // i8x8 -> i16x8 (signed)
        (8, false) => Uxtl8H(rd, rd).emit(self) // i8x8 -> i16x8 (unsigned)
        (16, true) => Sxtl4S(rd, rd).emit(self) // i16x4 -> i32x4 (signed)
        (16, false) => Uxtl4S(rd, rd).emit(self) // i16x4 -> i32x4 (unsigned)
        (32, true) => Sxtl2D(rd, rd).emit(self) // i32x2 -> i64x2 (signed)
        (32, false) => Uxtl2D(rd, rd).emit(self) // i32x2 -> i64x2 (unsigned)
        _ => abort("Invalid src_bits for SIMDLoadExtend")
      }
    }
    SIMDLoadZero(is_64, offset) => {
      // Load 32 or 64 bits to low lane, zero upper bits
      // uses[0] = base address
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // Scalar float load zeros upper bits
      if is_64 {
        LdrDImm(rd, rn, offset).emit(self)
      } else {
        LdrSImm(rd, rn, offset).emit(self)
      }
    }
    SIMDLoadLane(lane_size, lane, offset) => {
      // Load single element to specific lane
      // uses[0] = base address (GPR)
      // uses[1] = existing vector
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let vec = reg_num(inst.uses[1])
      // Copy existing vector to destination first (LD1 modifies in place)
      if rd != vec {
        Orr16B(rd, vec, vec).emit(self)
      }
      // LD1 doesn't have immediate offset form, compute address if needed
      if offset == 0 {
        match lane_size {
          B8 => Ld1B(rd, rn, lane).emit(self)
          H16 => Ld1H(rd, rn, lane).emit(self)
          S32 => Ld1S(rd, rn, lane).emit(self)
          D64 => Ld1D(rd, rn, lane).emit(self)
        }
      } else {
        // Use x16 as temp for address calculation
        AddImm(16, rn, offset).emit(self)
        match lane_size {
          B8 => Ld1B(rd, 16, lane).emit(self)
          H16 => Ld1H(rd, 16, lane).emit(self)
          S32 => Ld1S(rd, 16, lane).emit(self)
          D64 => Ld1D(rd, 16, lane).emit(self)
        }
      }
    }
    SIMDStoreLane(lane_size, lane, offset) => {
      // Store single element from specific lane
      // uses[0] = base address
      // uses[1] = vector
      let rn = reg_num(inst.uses[0])
      let vec = reg_num(inst.uses[1])
      // ST1 doesn't have immediate offset form, compute address if needed
      if offset == 0 {
        match lane_size {
          B8 => St1B(vec, rn, lane).emit(self)
          H16 => St1H(vec, rn, lane).emit(self)
          S32 => St1S(vec, rn, lane).emit(self)
          D64 => St1D(vec, rn, lane).emit(self)
        }
      } else {
        // Use x16 as temp for address calculation
        AddImm(16, rn, offset).emit(self)
        match lane_size {
          B8 => St1B(vec, 16, lane).emit(self)
          H16 => St1H(vec, 16, lane).emit(self)
          S32 => St1S(vec, 16, lane).emit(self)
          D64 => St1D(vec, 16, lane).emit(self)
        }
      }
    }
    // ============ Relaxed SIMD ============
    SIMDFMla(is_f32) => {
      // FMLA: Vd = Vd + Vn * Vm
      // defs[0] = result
      // uses[0] = accumulator, uses[1] = v1, uses[2] = v2
      let rd = wreg_num(inst.defs[0])
      let acc = reg_num(inst.uses[0])
      let rn = reg_num(inst.uses[1])
      let rm = reg_num(inst.uses[2])
      // This expands to multiple instructions. Copy multiplicands into reserved
      // scratch regs so we can freely overwrite `rd` with the accumulator.
      let a = 16
      let b = 17
      OrrVec(a, rn).emit(self)
      OrrVec(b, rm).emit(self)
      OrrVec(rd, acc).emit(self) // accumulator
      if is_f32 {
        Fmla4S(rd, a, b).emit(self)
      } else {
        Fmla2D(rd, a, b).emit(self)
      }
    }
    SIMDFMls(is_f32) => {
      // FMLS: Vd = Vd - Vn * Vm
      // defs[0] = result
      // uses[0] = accumulator, uses[1] = v1, uses[2] = v2
      let rd = wreg_num(inst.defs[0])
      let acc = reg_num(inst.uses[0])
      let rn = reg_num(inst.uses[1])
      let rm = reg_num(inst.uses[2])
      let a = 16
      let b = 17
      OrrVec(a, rn).emit(self)
      OrrVec(b, rm).emit(self)
      OrrVec(rd, acc).emit(self) // accumulator
      if is_f32 {
        Fmls4S(rd, a, b).emit(self)
      } else {
        Fmls2D(rd, a, b).emit(self)
      }
    }
    SIMDRelaxedDot8to16 => {
      // i16x8.relaxed_dot_i8x16_i7x16_s: dot product of i8x16 vectors to i16x8
      // result[i] = a[2*i]*b[2*i] + a[2*i+1]*b[2*i+1]
      // uses[0] = v1 (i8x16), uses[1] = v2 (i8x16)
      let rd = wreg_num(inst.defs[0])
      let tmp = wreg_num(inst.defs[1])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      // Multi-instruction expansion: copy inputs into reserved scratch regs so
      // `rd` may alias an input without clobbering it before the second SMULL.
      let a = 16
      let b = 17
      OrrVec(a, rn).emit(self)
      OrrVec(b, rm).emit(self)
      // Step 1: SMULL for lower 8 bytes - products for bytes 0-7
      Smull8H(rd, a, b).emit(self)
      // Step 2: SMULL2 for upper 8 bytes - products for bytes 8-15
      Smull2_8H(tmp, a, b).emit(self)
      // Step 3: ADDP pairwise add to get final dot products
      // Result: [a0*b0+a1*b1, a2*b2+a3*b3, ..., a14*b14+a15*b15]
      Addp8H(rd, rd, tmp).emit(self)
    }
    SIMDRelaxedDot8to32Add => {
      // i32x4.relaxed_dot_i8x16_i7x16_add_s: dot product + accumulator
      // result[i] = c[i] + sum(a[4*i+k]*b[4*i+k], k=0..3)
      // uses[0] = v1, uses[1] = v2, uses[2] = accumulator
      let rd = wreg_num(inst.defs[0])
      let tmp = wreg_num(inst.defs[1])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      let acc = reg_num(inst.uses[2])
      // Multi-instruction expansion. Protect operands that must remain available
      // after `rd`/`tmp` are overwritten by using reserved scratch regs V16/V17.
      let mut a = rn
      let mut b = rm
      let mut acc_reg = acc
      if acc_reg == rd || acc_reg == tmp {
        OrrVec(16, acc_reg).emit(self)
        acc_reg = 16
      }
      // `rn`/`rm` are used in both SMULL and SMULL2. If `rd` aliases one of them,
      // the first SMULL would clobber the input before SMULL2.
      if rd == a {
        OrrVec(17, a).emit(self)
        a = 17
      }
      if rd == b && b != a {
        OrrVec(17, b).emit(self)
        b = 17
      }
      // Step 1: SMULL for lower 8 bytes
      Smull8H(rd, a, b).emit(self)
      // Step 2: SMULL2 for upper 8 bytes
      Smull2_8H(tmp, a, b).emit(self)
      // Step 3: ADDP pairwise to get i16x8 dot products
      Addp8H(rd, rd, tmp).emit(self)
      // Step 4: SADDLP to get i32x4 from i16x8 (another pairwise add with widening)
      Saddlp4S(rd, rd).emit(self)
      // Step 5: Add accumulator
      Add4S(rd, rd, acc_reg).emit(self)
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
    I32 => self.emit_ldr_w_imm(rt, rn, offset)
    I64 => self.emit_ldr_imm(rt, rn, offset)
    F32 => self.emit_ldr_s_imm(rt, rn, offset)
    F64 => self.emit_ldr_d_imm(rt, rn, offset)
    V128 => self.emit_ldr_q_imm(rt, rn, offset)
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
    I32 => self.emit_str_w_imm(rt, rn, offset)
    I64 => self.emit_str_imm(rt, rn, offset)
    F32 => self.emit_str_s_imm(rt, rn, offset)
    F64 => self.emit_str_d_imm(rt, rn, offset)
    V128 => self.emit_str_q_imm(rt, rn, offset)
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
/// Emit epilogue (Standard)
///
/// Reverses the prologue operations in reverse order (Standard style):
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

  // Step 2: Restore callee-saved FPRs with post-indexed pops (Standard style)
  // Approach: forward iterate pairs, then handle remainder
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

  // Step 3: Restore callee-saved GPRs with post-indexed pops (Standard style)
  // Approach: forward iterate pairs, then handle remainder
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
/// Emit terminator with epilogue for Return (JITStackFrame)
/// next_block: the ID of the physically next block, used for fall-through optimization
fn MachineCode::emit_terminator_with_epilogue(
  self : MachineCode,
  term : @instr.VCodeTerminator,
  stack_frame : JITStackFrame,
  result_types : Array[@ir.Type],
  next_block : Int?,
  shared_exit_block : Int?,
) -> Unit {
  match term {
    Jump(target, _args) =>
      // Unconditional branch.
      // If the target is the next block in linear order, omit the branch and fall through.
      if next_block != Some(target) {
        self.emit_b(target)
      }
    Branch(cond, then_b, else_b) => {
      let rt = reg_num(cond)
      // Branch inversion: if then_b is next block, use CBZ to else_b
      if next_block == Some(then_b) {
        self.emit_cbz(rt, else_b)
      } else {
        self.emit_cbnz(rt, then_b)
        if next_block != Some(else_b) {
          self.emit_b(else_b)
        }
      }
    }
    BranchCmp(lhs, rhs, cond, is_64, then_b, else_b) => {
      // CMP lhs, rhs + B.cond then_b + B else_b
      let rn = reg_num(lhs)
      let rm = reg_num(rhs)
      if is_64 {
        self.emit_cmp_reg(rn, rm)
      } else {
        self.emit_cmp_reg32(rn, rm)
      }
      // Branch inversion: if then_b is next block, invert condition and branch to else_b
      if next_block == Some(then_b) {
        self.emit_b_cond(cond.invert().to_bits(), else_b)
      } else {
        self.emit_b_cond(cond.to_bits(), then_b)
        if next_block != Some(else_b) {
          self.emit_b(else_b)
        }
      }
    }
    BranchZero(reg, is_nonzero, is_64, then_b, else_b) => {
      // CBZ/CBNZ reg, then_b + B else_b
      // Use 32-bit CBZ/CBNZ for i32 to only check low 32 bits
      let rt = reg_num(reg)
      // Branch inversion: if then_b is next block, invert condition and branch to else_b
      if next_block == Some(then_b) {
        // Invert: CBZ->CBNZ, CBNZ->CBZ
        if is_nonzero {
          if is_64 {
            self.emit_cbz(rt, else_b)
          } else {
            self.emit_cbz32(rt, else_b)
          }
        } else if is_64 {
          self.emit_cbnz(rt, else_b)
        } else {
          self.emit_cbnz32(rt, else_b)
        }
      } else {
        if is_nonzero {
          if is_64 {
            self.emit_cbnz(rt, then_b)
          } else {
            self.emit_cbnz32(rt, then_b)
          }
        } else if is_64 {
          self.emit_cbz(rt, then_b)
        } else {
          self.emit_cbz32(rt, then_b)
        }
        if next_block != Some(else_b) {
          self.emit_b(else_b)
        }
      }
    }
    BranchCmpImm(lhs, imm, cond, is_64, then_b, else_b) => {
      // CMP lhs, #imm + B.cond then_b + B else_b
      let rn = reg_num(lhs)
      if is_64 {
        self.emit_cmp_imm(rn, imm)
      } else {
        self.emit_cmp_imm32(rn, imm)
      }
      // Branch inversion: if then_b is next block, invert condition and branch to else_b
      if next_block == Some(then_b) {
        // Invert: B.cond then_b becomes B.!cond else_b, fall through to then_b
        self.emit_b_cond(cond.invert().to_bits(), else_b)
      } else {
        // Normal: B.cond then_b, then handle else_b
        self.emit_b_cond(cond.to_bits(), then_b)
        // Skip else branch if it's the next block (fall-through)
        if next_block != Some(else_b) {
          self.emit_b(else_b)
        }
      }
    }
    Return(values) => {
      // ABI: Up to 8 integer returns in X0-X7, up to 8 float returns in V0-V7
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
          F32 | F64 | V128 => float_sources.push((ty, src, i))
          _ => int_sources.push((src, i))
        }
      }

      // ABI: Use X0-X7 for integer returns (up to 8)
      let max_int_ret_regs = @abi.MAX_INT_RET_REGS // 8
      let max_float_ret_regs = @abi.MAX_FLOAT_RET_REGS // 8

      // We must implement parallel moves for returns, because sources can overlap
      // destinations (e.g. returning (x1, x0) requires a swap). Do this using
      // reserved scratch registers (X16/V16) so leaf functions don't need a
      // spill area just for swaps.
      let mut extra_offset = 0
      fn emit_parallel_moves_x(
        self : MachineCode,
        moves : Array[(Int, Int)], // (src, dst)
      ) -> Unit {
        let pending = moves.copy()
        fn dst_is_used_as_src(pending : Array[(Int, Int)], dst : Int) -> Bool {
          for mv in pending {
            let (src, _) = mv
            if src == dst {
              return true
            }
          }
          false
        }

        while !pending.is_empty() {
          // Find an acyclic move: dst not used as a src by any remaining move.
          let mut idx_opt : Int? = None
          for i in 0..<pending.length() {
            let (_, dst) = pending[i]
            if !dst_is_used_as_src(pending, dst) {
              idx_opt = Some(i)
              break
            }
          }
          match idx_opt {
            Some(i) => {
              let (src, dst) = pending.remove(i)
              if src != dst {
                self.emit_mov_reg(dst, src)
              }
            }
            None => {
              // Cycle: break it via X16 (IP0).
              let scratch = 16
              let (saved_src, hole_dst) = pending.remove(0)
              self.emit_mov_reg(scratch, saved_src)
              let mut cur_dst = saved_src
              while cur_dst != hole_dst {
                let mut found = -1
                for i in 0..<pending.length() {
                  let (_, dst) = pending[i]
                  if dst == cur_dst {
                    found = i
                    break
                  }
                }
                guard found >= 0 else {
                  abort("return parallel move (x): broken cycle")
                }
                let (next_src, _) = pending.remove(found)
                if next_src != cur_dst {
                  self.emit_mov_reg(cur_dst, next_src)
                }
                cur_dst = next_src
              }
              self.emit_mov_reg(hole_dst, scratch)
            }
          }
        }
      }

      fn emit_parallel_moves_v(
        self : MachineCode,
        moves : Array[(Int, Int)], // (src, dst) in V-reg indices
      ) -> Unit {
        let pending = moves.copy()
        fn dst_is_used_as_src(pending : Array[(Int, Int)], dst : Int) -> Bool {
          for mv in pending {
            let (src, _) = mv
            if src == dst {
              return true
            }
          }
          false
        }

        while !pending.is_empty() {
          let mut idx_opt : Int? = None
          for i in 0..<pending.length() {
            let (_, dst) = pending[i]
            if !dst_is_used_as_src(pending, dst) {
              idx_opt = Some(i)
              break
            }
          }
          match idx_opt {
            Some(i) => {
              let (src, dst) = pending.remove(i)
              if src != dst {
                OrrVec(dst, src).emit(self)
              }
            }
            None => {
              // Cycle: break it via V16.
              let scratch = 16
              let (saved_src, hole_dst) = pending.remove(0)
              OrrVec(scratch, saved_src).emit(self)
              let mut cur_dst = saved_src
              while cur_dst != hole_dst {
                let mut found = -1
                for i in 0..<pending.length() {
                  let (_, dst) = pending[i]
                  if dst == cur_dst {
                    found = i
                    break
                  }
                }
                guard found >= 0 else {
                  abort("return parallel move (v): broken cycle")
                }
                let (next_src, _) = pending.remove(found)
                if next_src != cur_dst {
                  OrrVec(cur_dst, next_src).emit(self)
                }
                cur_dst = next_src
              }
              OrrVec(hole_dst, scratch).emit(self)
            }
          }
        }
      }

      // Integer returns in registers (X0-X7).
      let int_moves : Array[(Int, Int)] = []
      for idx, entry in int_sources {
        let (src, _) = entry
        if idx < max_int_ret_regs {
          if src != idx {
            int_moves.push((src, idx))
          }
        } else {
          // Extra results go to SRET buffer (X8).
          self.emit_str_offset(src, @abi.REG_SRET, extra_offset)
          extra_offset = extra_offset + 8
        }
      }
      emit_parallel_moves_x(self, int_moves)

      // Float/SIMD returns in registers (V0-V7). Use vector moves for all types
      // to avoid D/S aliasing hazards.
      let float_moves : Array[(Int, Int)] = []
      let num_float_in_regs = if float_sources.length() < max_float_ret_regs {
        float_sources.length()
      } else {
        max_float_ret_regs
      }
      for idx in 0..<num_float_in_regs {
        let (_, src, _) = float_sources[idx]
        if src != idx {
          float_moves.push((src, idx))
        }
      }
      emit_parallel_moves_v(self, float_moves)

      // Extra float results go to SRET buffer (X8).
      for idx in max_float_ret_regs..<float_sources.length() {
        let (_, src, _) = float_sources[idx]
        self.emit_str_d_offset(src, @abi.REG_SRET, extra_offset)
        extra_offset = extra_offset + 8
      }
      match shared_exit_block {
        Some(exit_block) =>
          // Tail merge: all returns share a single exit block that emits the epilogue + ret.
          // If this is the last physically-emitted block, fall through into the exit block.
          if next_block is None {
            ()
          } else {
            self.emit_b(exit_block)
          }
        None => {
          // Emit epilogue to restore callee-saved registers before return
          self.emit_epilogue(stack_frame)
          self.emit_ret(30)
        }
      }
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
