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
