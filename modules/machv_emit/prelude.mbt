// Code Generation
// Translates MachV to machine code

///|
fn require_embedding_abi(
  embedding_abi : @abi.EmbeddingABI?,
) -> @abi.EmbeddingABI {
  match embedding_abi {
    Some(abi) => abi
    None => abort("machv_emit: emission requires an embedding ABI")
  }
}

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
  func : @machv.Function,
  _needs_sret : Bool,
  isa : @isa.ISA,
) -> Array[Int] {
  // ABI: SRET uses a caller-saved register, so no special exclusion needed here.
  let used : @hashset.HashSet[Int] = HashSet([])
  let mut has_calls = false
  let env = isa.machine_env()
  let callee_saved_int : @hashset.HashSet[Int] = HashSet([])
  for r in env.callee_saved_int {
    callee_saved_int.add(r.index)
  }

  // Check param_pregs: parameters that cross calls are moved to callee-saved registers.
  for preg in func.get_param_pregs() {
    if preg is Some(p) && p.class is Int && callee_saved_int.contains(p.index) {
      used.add(p.index)
    }
  }
  for block in func.get_blocks() {
    for inst in block.insts {
      // Check if this instruction is a function call
      // Design: use call_type() to determine if an instruction
      // behaves like a call (clobbers caller-saved registers)
      if inst.opcode.call_type() is Regular {
        has_calls = true
      }
      for def in inst.defs {
        if def.reg is Physical(preg) &&
          preg.class is Int &&
          callee_saved_int.contains(preg.index) {
          used.add(preg.index)
        }
      }
    }
  }
  // If the function makes any calls, we must save LR on AArch64.
  // Note: X20-X24 are no longer pre-loaded in prologue (on-demand)
  // They are loaded on-demand from context and only need saving if used by regalloc
  if has_calls && isa is AArch64 {
    used.add(isa.lr_reg_index())
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
fn collect_used_callee_saved_fprs(
  func : @machv.Function,
  isa : @isa.ISA,
) -> Array[Int] {
  let used : @hashset.HashSet[Int] = HashSet([])
  let env = isa.machine_env()
  let callee_saved_fprs : @hashset.HashSet[Int] = HashSet([])
  for r in env.callee_saved_float {
    callee_saved_fprs.add(r.index)
  }
  // Check param_pregs: float parameters that cross calls are moved to callee-saved FPRs
  // These are defined in the prologue via `fmov sN, wM` or `fmov dN, xM`
  for preg in func.get_param_pregs() {
    if preg is Some(p) &&
      (p.class is Float32 || p.class is Float64) &&
      callee_saved_fprs.contains(p.index) {
      used.add(p.index)
    }
  }
  for block in func.get_blocks() {
    for inst in block.insts {
      for def in inst.defs {
        if def.reg is Physical(preg) &&
          (preg.class is Float32 || preg.class is Float64) &&
          callee_saved_fprs.contains(preg.index) {
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
fn func_has_calls(func : @machv.Function) -> Bool {
  func.has_calls()
}

///|
/// Check if a function reads any incoming stack parameters
fn func_has_incoming_stack_args(func : @machv.Function) -> Bool {
  for block in func.get_blocks() {
    for inst in block.insts {
      if inst.opcode is LoadStackParam(_, _) {
        return true
      }
    }
  }
  false
}

///|
/// Check if a function uses the embedding context register.
fn func_uses_context_reg(func : @machv.Function, context_reg : Int) -> Bool {
  for block in func.get_blocks() {
    for inst in block.insts {
      for use_ in inst.uses {
        if use_ is Physical(preg) && preg.index == context_reg {
          return true
        }
      }
    }
    if block.terminator is Some(term) &&
      terminator_uses_context_reg(term, context_reg) {
      return true
    }
  }
  false
}

///|
fn terminator_uses_context_reg(
  term : @instr.MachVTerminator,
  context_reg : Int,
) -> Bool {
  match term {
    Return(values) => {
      for v in values {
        if v is Physical(preg) && preg.index == context_reg {
          return true
        }
      }
      false
    }
    Branch(cond, _, _) => cond is Physical(preg) && preg.index == context_reg
    BranchCmp(lhs, rhs, _, _, _, _) =>
      (lhs is Physical(preg) && preg.index == context_reg) ||
      (rhs is Physical(preg2) && preg2.index == context_reg)
    BranchZero(reg, _, _, _, _) =>
      reg is Physical(preg) && preg.index == context_reg
    BranchCmpImm(lhs, _, _, _, _, _) =>
      lhs is Physical(preg) && preg.index == context_reg
    BrTable(index, _, _) => index is Physical(preg) && preg.index == context_reg
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
/// - X0 = context (cached to pinned context reg)
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
  if self.isa is AMD64 {
    let (abs_amount, is_sub) = if amount < 0 {
      (-amount, true)
    } else {
      (amount, false)
    }
    let step = 4096
    let scratch = self.isa.scratch_reg_1_index()
    if is_sub {
      // Probe only when crossing at least one full page, matching Cranelift's
      // inline-probestack rule (probe_count = frame_size / guard_size).
      if abs_amount < step {
        self.x86_emit_sub_rsp_imm32(abs_amount)
        return
      }
      // Probe in 4KB steps to avoid skipping over a stack guard page.
      let mut remaining = abs_amount
      while remaining >= step {
        self.x86_emit_sub_rsp_imm32(step)
        self.x86_emit_mov_m64_r64(4, 0, scratch)
        remaining = remaining - step
      }
      if remaining > 0 {
        self.x86_emit_sub_rsp_imm32(remaining)
        self.x86_emit_mov_m64_r64(4, 0, scratch)
      }
      return
    }
    // Stack deallocation (or other upward adjustment): no probing needed.
    let mut remaining = abs_amount
    while remaining >= step {
      self.x86_emit_add_rsp_imm32(step)
      remaining = remaining - step
    }
    if remaining > 0 {
      self.x86_emit_add_rsp_imm32(remaining)
    }
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
    // single large SP adjustment (e.g. large frames on an embedding-managed stack).
    //
    // We probe in 4KB steps only when crossing at least one full page.
    // This follows Cranelift's `probe_count = frame_size / guard_size` behavior
    // and avoids an extra store for small stack frames.
    if abs_amount < step {
      self.emit_sub_imm(31, 31, abs_amount)
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
  stack_frame : EmitStackFrame,
  params : Array[@abi.VReg],
  param_pregs : Array[@abi.PReg?],
  debug_func_idx : Int?,
) -> Unit {
  if self.isa is AMD64 {
    let isa = self.isa
    let saved_gprs = stack_frame.saved_gprs

    // Setup area: push rbp so the stack is 16-byte aligned after the prologue
    // (SysV ABI requires 16-byte alignment at call sites).
    if stack_frame.has_setup_area {
      self.x86_emit_push_r64(isa.fp_reg_index())
      // rbp = rsp
      self.x86_emit_mov_rr(isa.fp_reg_index(), 4)
      // Setup area size is ISA-dependent; on amd64 this is typically 8.
      self.x86_emit_sub_rsp_imm32(stack_frame.setup_area_size - 8)
    }

    // Save callee-saved GPRs.
    for r in saved_gprs {
      self.x86_emit_push_r64(r)
    }
    // Padding for 16-byte alignment when saving an odd number of 8-byte regs.
    let gpr_padding = stack_frame.gpr_save_size - saved_gprs.length() * 8
    if gpr_padding > 0 {
      self.x86_emit_sub_rsp_imm32(gpr_padding)
    }

    // SysV has no callee-saved XMM regs. Keep the stack layout plumbing generic.
    if stack_frame.saved_fprs.length() > 0 {
      abort("x86_64 prologue: unexpected callee-saved fprs")
    }

    // Allocate spill slots + outgoing args (with stack probing for large frames).
    let remaining_size = stack_frame.spill_size + stack_frame.outgoing_args_size
    if remaining_size > 0 {
      self.emit_sp_adjust(-remaining_size)
    }

    if debug_func_idx is Some(idx) {
      let call_conv = stack_frame.require_call_conv_layout()
      let context_src = call_conv.context_arg.index
      let layout = stack_frame.require_embedding_context_layout()
      let scratch = 11
      if self.debug_prev_func_idx_spill_offset >= 0 {
        self.x86_emit_mov_r32_m32(
          scratch,
          context_src,
          layout.require_active_function_index_offset(),
        )
        self.x86_emit_mov_m32_r32(
          4,
          self.debug_prev_func_idx_spill_offset,
          scratch,
        )
      }
      self.x86_emit_mov_imm64(scratch, idx.to_int64())
      self.x86_emit_mov_m32_r32(
        context_src,
        layout.require_active_function_index_offset(),
        scratch,
      )
    }

    // Cache embedding context and optional context-derived pointers.
    if stack_frame.needs_context_reg {
      if !stack_frame.require_embedding_abi().reserve_context_role {
        abort("unpinned embedding context ABI not implemented yet")
      }
      let call_conv = stack_frame.require_call_conv_layout()
      let context_src = call_conv.context_arg.index
      let context = stack_frame.context_reg_index()
      if context != context_src {
        self.x86_emit_mov_rr(context, context_src)
      }
      if stack_frame.cache_context_0 {
        let layout = stack_frame.require_embedding_context_layout()
        guard stack_frame.context_cache_0_index() is Some(cache_reg) else {
          abort("embedding context cache 0 register role is required")
        }
        self.x86_emit_mov_r64_m64(
          cache_reg,
          context,
          layout.require_cache_role_offset(ContextCache0Descriptor),
        )
      }
      if stack_frame.cache_context_1 {
        let layout = stack_frame.require_embedding_context_layout()
        guard stack_frame.context_cache_1_index() is Some(cache_reg) else {
          abort("embedding context cache 1 register role is required")
        }
        self.x86_emit_mov_r64_m64(
          cache_reg,
          context,
          layout.require_cache_role_offset(ContextCache1),
        )
      }
    }

    // Move arguments from ABI registers to allocated registers (if any).
    // Use parallel-move resolution to avoid source clobbering when registers
    // form cycles (e.g. rdi->rsi and rsi->rdx).
    fn emit_parallel_moves_gpr(
      self : MachineCode,
      scratch : Int,
      moves : Array[(Int, Int)],
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
              self.x86_emit_mov_rr(dst, src)
            }
          }
          None => {
            let (saved_src, hole_dst) = pending.remove(0)
            self.x86_emit_mov_rr(scratch, saved_src)
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
                abort("prologue parallel move (x86 gpr): cycle")
              }
              let (next_src, _) = pending.remove(found)
              if next_src != cur_dst {
                self.x86_emit_mov_rr(cur_dst, next_src)
              }
              cur_dst = next_src
            }
            self.x86_emit_mov_rr(hole_dst, scratch)
          }
        }
      }
    }

    fn emit_parallel_moves_xmm(
      self : MachineCode,
      scratch : Int,
      moves : Array[(Int, Int)],
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
              self.x86_emit_movaps_xmm_xmm(dst, src)
            }
          }
          None => {
            let (saved_src, hole_dst) = pending.remove(0)
            self.x86_emit_movaps_xmm_xmm(scratch, saved_src)
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
                abort("prologue parallel move (x86 xmm): cycle")
              }
              let (next_src, _) = pending.remove(found)
              if next_src != cur_dst {
                self.x86_emit_movaps_xmm_xmm(cur_dst, next_src)
              }
              cur_dst = next_src
            }
            self.x86_emit_movaps_xmm_xmm(hole_dst, scratch)
          }
        }
      }
    }

    let call_conv = stack_frame.require_call_conv_layout()
    let user_gprs = call_conv.user_arg_gprs
    let float_regs = call_conv.arg_fprs
    let int_moves : Array[(Int, Int)] = []
    let fp_moves : Array[(Int, Int)] = []
    let mut int_idx = 0
    let mut float_idx = 0
    for param_idx, param in params {
      let dest_preg = if param_idx < param_pregs.length() {
        param_pregs[param_idx]
      } else {
        None
      }
      match param.class {
        Int =>
          if int_idx < 1 + user_gprs.length() {
            let src = if int_idx == 0 {
              call_conv.context_arg.index
            } else {
              user_gprs[int_idx - 1].index
            }
            match dest_preg {
              Some(preg) =>
                if preg.index != src {
                  let context_dst = stack_frame.context_reg_index()
                  let is_redundant_context_move = int_idx == 0 &&
                    stack_frame.needs_context_reg &&
                    preg.index == context_dst
                  if !is_redundant_context_move {
                    int_moves.push((src, preg.index))
                  }
                }
              None => ()
            }
            int_idx += 1
          }
        Float32 | Float64 | Vector =>
          if float_idx < float_regs.length() {
            let src = float_regs[float_idx].index
            match dest_preg {
              Some(preg) =>
                if preg.index != src {
                  fp_moves.push((src, preg.index))
                }
              None => ()
            }
            float_idx += 1
          }
      }
    }
    emit_parallel_moves_gpr(self, isa.scratch_reg_1_index(), int_moves)
    emit_parallel_moves_xmm(self, 15, fp_moves)
    return
  }
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

  if debug_func_idx is Some(idx) {
    let call_conv = stack_frame.require_call_conv_layout()
    let context_reg = call_conv.context_arg.index
    let layout = stack_frame.require_embedding_context_layout()
    if self.debug_prev_func_idx_spill_offset >= 0 {
      self.emit_ldr_w_imm(
        16,
        context_reg,
        layout.require_active_function_index_offset(),
      )
      if self.debug_prev_func_idx_spill_offset <= 16380 {
        self.emit_str_w_imm(16, 31, self.debug_prev_func_idx_spill_offset)
      } else {
        self.emit_load_imm64(
          17,
          self.debug_prev_func_idx_spill_offset.to_int64(),
        )
        self.emit_add_reg(17, 31, 17)
        self.emit_str_w_imm(16, 17, 0)
      }
    }
    self.emit_load_imm64(16, idx.to_int64())
    self.emit_str_w_imm(
      16,
      context_reg,
      layout.require_active_function_index_offset(),
    )
  }

  // Step 5: Cache the embedding context when needed.
  if stack_frame.needs_context_reg {
    if !stack_frame.require_embedding_abi().reserve_context_role {
      abort("unpinned embedding context ABI not implemented yet")
    }
    let context = stack_frame.context_reg_index()
    let call_conv = stack_frame.require_call_conv_layout()
    self.emit_mov_reg(context, call_conv.context_arg.index)
    // Optionally cache embedding context-derived pointer 0.
    if stack_frame.cache_context_0 {
      let layout = stack_frame.require_embedding_context_layout()
      guard stack_frame.context_cache_0_index() is Some(cache_reg) else {
        abort("embedding context cache 0 register role is required")
      }
      self.emit_ldr_imm(
        cache_reg,
        context,
        layout.require_cache_role_offset(ContextCache0Source),
      )
    }
    // Optionally cache embedding context-derived pointer 1.
    if stack_frame.cache_context_1 {
      let layout = stack_frame.require_embedding_context_layout()
      guard stack_frame.context_cache_1_index() is Some(cache_reg) else {
        abort("embedding context cache 1 register role is required")
      }
      self.emit_ldr_imm(
        cache_reg,
        context,
        layout.require_cache_role_offset(ContextCache1),
      )
    }
  }

  // Step 6: Move arguments from ABI registers to allocated registers
  let call_conv = stack_frame.require_call_conv_layout()
  let int_arg_regs = [call_conv.context_arg, ..call_conv.user_arg_gprs]
  let float_arg_regs = call_conv.arg_fprs
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
        if float_idx < float_arg_regs.length() {
          let v_src = float_arg_regs[float_idx].index
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
        if float_idx < float_arg_regs.length() {
          let v_src = float_arg_regs[float_idx].index
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
        if int_idx < int_arg_regs.length() {
          let x_src = int_arg_regs[int_idx].index
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
/// Emit machine code for a MachV function
pub fn emit_function(
  func : @machv.Function,
  isa? : @isa.ISA = AArch64,
  debug_func_idx? : Int? = None,
  force_frame_setup? : Bool = false,
  embedding_abi? : @abi.EmbeddingABI? = None,
  record_disasm? : Bool = true,
) -> MachineCode {
  // Optimize block layout for better branch prediction
  // Loop rotation makes back edges fall through, reducing taken branches
  let func = @layout.optimize_layout(func)
  let mc = MachineCode::new(isa~, record_disasm~)
  let embedding_abi = require_embedding_abi(embedding_abi)
  let call_conv_layout = embedding_abi.call_conv
  // ABI: check if this function or one of its calls needs the embedding's
  // extra-results pointer according to the selected call convention.
  let needs_sret = func.needs_extra_results_ptr_for_call_conv(call_conv_layout)
  let calls_multi_value = func.calls_multi_value_function_for_call_conv(
    call_conv_layout,
  )
  // We need SRET if either we return multi-value OR we call multi-value functions
  let uses_sret = needs_sret || calls_multi_value
  // Collect callee-saved GPRs that this function clobbers
  let clobbered = collect_used_callee_saved(func, uses_sret, isa)
  // Collect callee-saved FPRs (D8-D15) that this function clobbers
  let clobbered_fprs = collect_used_callee_saved_fprs(func, isa)

  // Build stack frame layout using EmitStackFrame
  // has_calls is true if function makes any calls
  let has_calls = func_has_calls(func)
  let has_incoming_stack_args = func_has_incoming_stack_args(func)
  let uses_context_cache_0_source = func.uses_context_cache_0_source()
  let cache_context_0 = func.should_reserve_context_cache_0()
  let cache_context_1 = func.should_reserve_context_cache_1()
  let context_reg = embedding_abi.reg_roles.context

  let force_context_reg_cache = embedding_abi.reserve_context_role &&
    isa is AMD64 &&
    context_reg is Some(_)
  let needs_context_reg = force_context_reg_cache ||
    has_calls ||
    (context_reg is Some({ index, .. }) && func_uses_context_reg(func, index)) ||
    uses_context_cache_0_source
  let clobbered_gprs = clobbered
  if cache_context_0 &&
    embedding_abi.reg_roles.context_cache_0 is Some(cache) &&
    !clobbered_gprs.contains(cache.index) {
    clobbered_gprs.push(cache.index)
  }
  if cache_context_1 &&
    embedding_abi.reg_roles.context_cache_1 is Some(cache) &&
    !clobbered_gprs.contains(cache.index) {
    clobbered_gprs.push(cache.index)
  }
  let num_spill_slots = func.get_num_spill_slots()
  let needs_debug_idx_restore = debug_func_idx is Some(_) && needs_context_reg
  let total_spill_slots = if needs_debug_idx_restore {
    num_spill_slots + 1
  } else {
    num_spill_slots
  }
  let stack_frame = EmitStackFrame::build(
    clobbered_gprs,
    clobbered_fprs,
    total_spill_slots,
    has_calls~,
    outgoing_args_size=func.get_max_outgoing_args_size(),
    needs_context_reg~,
    cache_context_0~,
    cache_context_1~,
    force_frame_setup~,
    has_incoming_stack_args~,
    embedding_abi=Some(embedding_abi),
    isa~,
  )
  if needs_debug_idx_restore {
    mc.set_debug_prev_func_idx_spill_offset(
      stack_frame.get_spill_offset(num_spill_slots),
    )
  }

  // Emit prologue: save callee-saved registers, cache context to X19, and move params
  mc.emit_prologue(
    stack_frame,
    func.get_params(),
    func.get_param_pregs(),
    debug_func_idx,
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
        if u is Physical(p) && p.class is Int {
          let bit = 1L << p.index
          if (defined & bit) == 0L {
            use_mask = use_mask | bit
          }
        }
      }
      for d in inst.defs {
        if d.reg is Physical(p) && p.class is Int {
          let bit = 1L << p.index
          def_mask = def_mask | bit
          defined = defined | bit
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
  let is_amd64 = mc.isa is AMD64
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
      if !is_amd64 &&
        inst.opcode is Add(true) &&
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
      if !is_amd64 &&
        inst.opcode is Extend(Unsigned32To64) &&
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
              if base is Some(rn) {
                mc.emit_add_uxtw(add_dst, rn, ext_src, 0)
                inst_idx = inst_idx + 2
                continue
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
        func.get_result_kinds(),
        next_block,
        shared_exit_block,
      )
    }
  }
  // Emit the shared exit block epilogue (if enabled).
  if shared_exit_block is Some(exit_block) {
    mc.define_label(exit_block)
    mc.emit_epilogue(stack_frame)
    if is_amd64 {
      mc.x86_emit_ret()
    } else {
      mc.emit_ret(30)
    }
  }
  if !is_amd64 {
    mc.materialize_call_veneers()
  } else {
    mc.emit_amd64_const_pool()
  }
  mc.resolve_fixups()
  mc
}

// ============ Cranelift-Style Emission (MachV + regalloc::Output) ============

///|
fn output_uses_preg(
  func : @machv.Function,
  output : @machv_regalloc.Output,
  preg_idx : Int,
) -> Bool {
  ignore(func)
  output.uses_preg_index_any(preg_idx, true)
}

///|
fn collect_used_callee_saved_from_output(
  func : @machv.Function,
  output : @machv_regalloc.Output,
  isa : @isa.ISA,
) -> Array[Int] {
  let used : Array[Bool] = Array::make(128, false)
  let env = isa.machine_env()
  let callee_saved_int : Array[Bool] = Array::make(128, false)
  for r in env.callee_saved_int {
    if r.index >= 0 && r.index < callee_saved_int.length() {
      callee_saved_int[r.index] = true
    }
  }

  // Params are defined in the prologue, so they count as clobbers.
  for i in 0..<func.get_params().length() {
    if output.get_param_loc(i) is Reg(p) &&
      p.class is Int &&
      p.index >= 0 &&
      p.index < callee_saved_int.length() &&
      callee_saved_int[p.index] {
      used[p.index] = true
    }
  }

  // Edits (moves) define their destination reg.
  for edit_entry in output.iter_edits() {
    let ((_block_id, _inst_idx, _pos), edit) = edit_entry
    if edit is Move(_from, Reg(p), _class) &&
      p.class is Int &&
      p.index >= 0 &&
      p.index < callee_saved_int.length() &&
      callee_saved_int[p.index] {
      used[p.index] = true
    }
  }

  // Instruction defs.
  for block in func.get_blocks() {
    //
    // Ignore *physical* defs here. Calls model clobbers as physical defs so
    // regalloc can treat them as kills. However, prologue saves must be driven
    // by allocated callee-saved registers that actually hold virtual values
    // (params / vreg defs / regalloc edits), matching Cranelift's machinst ABI
    // design.
    for inst_idx, inst in block.insts {
      for di in 0..<inst.defs.length() {
        if inst.defs[di].reg is Virtual(_) &&
          output.inst_def_loc(block.id, inst_idx, false, di) is Reg(p) &&
          p.class is Int &&
          p.index >= 0 &&
          p.index < callee_saved_int.length() &&
          callee_saved_int[p.index] {
          used[p.index] = true
        }
      }
    }
  }
  if func_has_calls(func) && isa is AArch64 {
    let lr = isa.lr_reg_index()
    if lr >= 0 && lr < used.length() {
      used[lr] = true
    }
  }
  let result : Array[Int] = []
  for i, is_used in used {
    if is_used {
      result.push(i)
    }
  }
  result.sort()
  result
}

///|
fn collect_used_callee_saved_fprs_from_output(
  func : @machv.Function,
  output : @machv_regalloc.Output,
  isa : @isa.ISA,
) -> Array[Int] {
  let used : Array[Bool] = Array::make(128, false)
  let env = isa.machine_env()
  let callee_saved_fprs : Array[Bool] = Array::make(128, false)
  for r in env.callee_saved_float {
    if r.index >= 0 && r.index < callee_saved_fprs.length() {
      callee_saved_fprs[r.index] = true
    }
  }

  // Params are defined in the prologue, so they count as clobbers.
  for i in 0..<func.get_params().length() {
    if output.get_param_loc(i) is Reg(p) &&
      (p.class is Float32 || p.class is Float64) &&
      p.index >= 0 &&
      p.index < callee_saved_fprs.length() &&
      callee_saved_fprs[p.index] {
      used[p.index] = true
    }
  }

  // Edits define their destination reg.
  for edit_entry in output.iter_edits() {
    let ((_block_id, _inst_idx, _pos), edit) = edit_entry
    if edit is Move(_from, Reg(p), _class) &&
      (p.class is Float32 || p.class is Float64) &&
      p.index >= 0 &&
      p.index < callee_saved_fprs.length() &&
      callee_saved_fprs[p.index] {
      used[p.index] = true
    }
  }

  // Instruction defs: only count allocations of virtual values (see comment
  // above in collect_used_callee_saved_from_output).
  for block in func.get_blocks() {
    for inst_idx, inst in block.insts {
      for di in 0..<inst.defs.length() {
        if inst.defs[di].reg is Virtual(_) &&
          output.inst_def_loc(block.id, inst_idx, false, di) is Reg(p) &&
          (p.class is Float32 || p.class is Float64) &&
          p.index >= 0 &&
          p.index < callee_saved_fprs.length() &&
          callee_saved_fprs[p.index] {
          used[p.index] = true
        }
      }
    }
  }
  let result : Array[Int] = []
  for i, is_used in used {
    if is_used {
      result.push(i)
    }
  }
  result.sort()
  result
}

///|
fn invalidate_edit_slot_cache_reg(
  slot_cache : Map[Int, @abi.PReg],
  preg : @abi.PReg,
) -> Unit {
  let to_remove : Array[Int] = []
  for slot, cached in slot_cache {
    if cached.index == preg.index && cached.class == preg.class {
      to_remove.push(slot)
    }
  }
  for slot in to_remove {
    slot_cache.remove(slot) |> ignore
  }
}

///|
fn invalidate_edit_slot_cache_defs(
  slot_cache : Map[Int, @abi.PReg],
  inst : @instr.MachVInst,
) -> Unit {
  for def in inst.defs {
    if def.reg is Physical(preg) {
      invalidate_edit_slot_cache_reg(slot_cache, preg)
    }
  }
}

///|
fn spill_slots_for_class(class : @abi.RegClass) -> Int {
  match class {
    Vector => 2
    _ => 1
  }
}

///|
fn invalidate_edit_slot_cache_range(
  slot_cache : Map[Int, @abi.PReg],
  base_slot : Int,
  class : @abi.RegClass,
) -> Unit {
  let width = spill_slots_for_class(class)
  for i in 0..<width {
    slot_cache.remove(base_slot + i) |> ignore
  }
}

///|
fn emit_edit_move_with_cache(
  mc : MachineCode,
  edit : @machv_regalloc.Edit,
  stack_frame : EmitStackFrame,
  slot_cache : Map[Int, @abi.PReg],
) -> Unit {
  match edit {
    Move(from, to, class) =>
      match (from, to) {
        (Reg(src), Reg(dst)) => {
          let dst_preg : @abi.PReg = { index: dst.index, class }
          invalidate_edit_slot_cache_reg(slot_cache, dst_preg)
          let inst = @instr.MachVInst::new(Move)
          inst.add_def({ reg: Physical(dst_preg) })
          inst.add_use(Physical({ index: src.index, class }))
          mc.emit_instruction(inst, stack_frame)
        }
        (Spill(slot), Reg(dst)) => {
          let dst_preg : @abi.PReg = { index: dst.index, class }
          invalidate_edit_slot_cache_reg(slot_cache, dst_preg)
          invalidate_edit_slot_cache_range(slot_cache, slot, class)
          let inst = @instr.MachVInst::new(StackLoad(slot * 8))
          inst.add_def({ reg: Physical(dst_preg) })
          mc.emit_instruction(inst, stack_frame)
        }
        (Reg(src), Spill(slot)) => {
          let src_preg : @abi.PReg = { index: src.index, class }
          invalidate_edit_slot_cache_range(slot_cache, slot, class)
          let inst = @instr.MachVInst::new(StackStore(slot * 8))
          inst.add_use(Physical(src_preg))
          mc.emit_instruction(inst, stack_frame)
        }
        (Spill(from_slot), Spill(to_slot)) =>
          abort(
            "regalloc output should not contain stack-to-stack moves: \{from_slot} -> \{to_slot} (class=\{class})",
          )
      }
  }
}

///|
fn map_inst_for_emission(
  block_id : Int,
  inst_idx : Int,
  inst : @instr.MachVInst,
  output : @machv_regalloc.Output,
) -> @instr.MachVInst {
  for di in 0..<inst.defs.length() {
    match output.inst_def_loc(block_id, inst_idx, false, di) {
      Reg(preg) => inst.defs[di] = { reg: Physical(preg) }
      Spill(_) => abort("Spill loc in instruction def allocation")
    }
  }
  for ui in 0..<inst.uses.length() {
    match output.inst_use_loc(block_id, inst_idx, false, ui) {
      Reg(preg) => inst.uses[ui] = Physical(preg)
      Spill(_) => abort("Spill loc in instruction use allocation")
    }
  }
  inst
}

///|
fn map_term_for_emission(
  block_id : Int,
  term_inst : Int,
  term : @instr.MachVTerminator,
  output : @machv_regalloc.Output,
) -> @instr.MachVTerminator {
  // Jump and Trap don't consume vregs in the emitter.
  match term {
    Jump(_, _) | Trap(_) => term
    Branch(_cond, then_b, else_b) => {
      let loc = output.inst_use_loc(block_id, term_inst, true, 0)
      guard loc is Reg(p) else {
        abort("Spill loc in terminator use allocation")
      }
      Branch(Physical(p), then_b, else_b)
    }
    BranchCmp(_lhs, _rhs, cond, is_64, then_b, else_b) => {
      let l0 = output.inst_use_loc(block_id, term_inst, true, 0)
      let l1 = output.inst_use_loc(block_id, term_inst, true, 1)
      guard (l0, l1) is (Reg(p0), Reg(p1)) else {
        abort("Spill loc in terminator use allocation")
      }
      BranchCmp(Physical(p0), Physical(p1), cond, is_64, then_b, else_b)
    }
    BranchZero(_r, is_nonzero, is_64, then_b, else_b) => {
      let l0 = output.inst_use_loc(block_id, term_inst, true, 0)
      guard l0 is Reg(p0) else {
        abort("Spill loc in terminator use allocation")
      }
      BranchZero(Physical(p0), is_nonzero, is_64, then_b, else_b)
    }
    BranchCmpImm(_lhs, imm, cond, is_64, then_b, else_b) => {
      let l0 = output.inst_use_loc(block_id, term_inst, true, 0)
      guard l0 is Reg(p0) else {
        abort("Spill loc in terminator use allocation")
      }
      BranchCmpImm(Physical(p0), imm, cond, is_64, then_b, else_b)
    }
    Return(values) => {
      let mapped : Array[@abi.Reg] = []
      for i in 0..<values.length() {
        let li = output.inst_use_loc(block_id, term_inst, true, i)
        guard li is Reg(p0) else {
          abort("Spill loc in terminator use allocation")
        }
        mapped.push(Physical(p0))
      }
      Return(mapped)
    }
    BrTable(_index, targets, default) => {
      let l0 = output.inst_use_loc(block_id, term_inst, true, 0)
      guard l0 is Reg(p0) else {
        abort("Spill loc in terminator use allocation")
      }
      BrTable(Physical(p0), targets, default)
    }
  }
}

///|
fn MachineCode::emit_prologue_with_output(
  self : MachineCode,
  stack_frame : EmitStackFrame,
  params : Array[@abi.VReg],
  output : @machv_regalloc.Output,
  debug_func_idx : Int?,
) -> Unit {
  if self.isa is AMD64 {
    let isa = self.isa
    // Reuse the existing prologue structure (save regs, allocate frame, cache context),
    // then do a Cranelift-style "param moves + param spills" stage.
    //
    // We must spill any spilled params *before* we clobber their incoming ABI regs.

    // Emit the prologue without param moves.
    let dummy_param_pregs : Array[@abi.PReg?] = []
    for _ in 0..<params.length() {
      dummy_param_pregs.push(None)
    }
    self.emit_prologue(stack_frame, params, dummy_param_pregs, debug_func_idx)
    let call_conv = stack_frame.require_call_conv_layout()
    let user_gprs = call_conv.user_arg_gprs
    let float_regs = call_conv.arg_fprs

    // Store spilled params from incoming ABI regs to spill slots.
    let mut int_idx = 0
    let mut float_idx = 0
    for param_idx, param in params {
      let loc = output.get_param_loc(param_idx)
      match param.class {
        Int =>
          if int_idx < 1 + user_gprs.length() {
            let src = if int_idx == 0 {
              call_conv.context_arg.index
            } else {
              user_gprs[int_idx - 1].index
            }
            match loc {
              Spill(slot) =>
                self.x86_emit_mov_m64_r64(
                  4,
                  stack_frame.spill_offset + slot * 8,
                  src,
                )
              _ => ()
            }
            int_idx += 1
          }
        Float32 | Float64 =>
          if float_idx < float_regs.length() {
            let src = float_regs[float_idx].index
            match loc {
              Spill(slot) =>
                self.x86_emit_movsd_m64_xmm(
                  4,
                  stack_frame.spill_offset + slot * 8,
                  src,
                )
              _ => ()
            }
            float_idx += 1
          }
        Vector =>
          if float_idx < float_regs.length() {
            let src = float_regs[float_idx].index
            match loc {
              Spill(slot) =>
                self.x86_emit_movdqu_m128_xmm(
                  4,
                  stack_frame.spill_offset + slot * 8,
                  src,
                )
              _ => ()
            }
            float_idx += 1
          }
      }
    }
    fn emit_parallel_moves_gpr(
      self : MachineCode,
      scratch : Int,
      moves : Array[(Int, Int)],
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
              self.x86_emit_mov_rr(dst, src)
            }
          }
          None => {
            let (saved_src, hole_dst) = pending.remove(0)
            self.x86_emit_mov_rr(scratch, saved_src)
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
                abort("prologue parallel move (x86 gpr): cycle")
              }
              let (next_src, _) = pending.remove(found)
              if next_src != cur_dst {
                self.x86_emit_mov_rr(cur_dst, next_src)
              }
              cur_dst = next_src
            }
            self.x86_emit_mov_rr(hole_dst, scratch)
          }
        }
      }
    }

    fn emit_parallel_moves_xmm(
      self : MachineCode,
      scratch : Int,
      moves : Array[(Int, Int)],
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
              self.x86_emit_movaps_xmm_xmm(dst, src)
            }
          }
          None => {
            let (saved_src, hole_dst) = pending.remove(0)
            self.x86_emit_movaps_xmm_xmm(scratch, saved_src)
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
                abort("prologue parallel move (x86 xmm): cycle")
              }
              let (next_src, _) = pending.remove(found)
              if next_src != cur_dst {
                self.x86_emit_movaps_xmm_xmm(cur_dst, next_src)
              }
              cur_dst = next_src
            }
            self.x86_emit_movaps_xmm_xmm(hole_dst, scratch)
          }
        }
      }
    }

    // Collect moves from ABI incoming regs to allocated regs.
    let int_moves : Array[(Int, Int)] = []
    let fp_moves : Array[(Int, Int)] = []
    int_idx = 0
    float_idx = 0
    for param_idx, param in params {
      let loc = output.get_param_loc(param_idx)
      match param.class {
        Int =>
          if int_idx < 1 + user_gprs.length() {
            let src = if int_idx == 0 {
              call_conv.context_arg.index
            } else {
              user_gprs[int_idx - 1].index
            }
            match loc {
              Reg(dst) =>
                if dst.index != src {
                  let context_dst = stack_frame.context_reg_index()
                  let is_redundant_context_move = int_idx == 0 &&
                    stack_frame.needs_context_reg &&
                    dst.index == context_dst
                  if !is_redundant_context_move {
                    int_moves.push((src, dst.index))
                  }
                }
              _ => ()
            }
            int_idx += 1
          }
        Float32 | Float64 | Vector =>
          if float_idx < float_regs.length() {
            let src = float_regs[float_idx].index
            match loc {
              Reg(dst) =>
                if dst.index != src {
                  fp_moves.push((src, dst.index))
                }
              _ => ()
            }
            float_idx += 1
          }
      }
    }
    emit_parallel_moves_gpr(self, isa.scratch_reg_1_index(), int_moves)
    emit_parallel_moves_xmm(self, 15, fp_moves)
    return
  }
  // Reuse the existing prologue structure (save regs, allocate frame, cache context),
  // then do a Cranelift-style "param moves + param spills" stage.
  //
  // We must spill any spilled params *before* we clobber their incoming ABI regs.

  // Emit the "standard" prologue without param moves by passing `None` for all params.
  let dummy_param_pregs : Array[@abi.PReg?] = []
  for _ in 0..<params.length() {
    dummy_param_pregs.push(None)
  }
  self.emit_prologue(stack_frame, params, dummy_param_pregs, debug_func_idx)

  // Store spilled params from incoming ABI regs to spill slots.
  let call_conv = stack_frame.require_call_conv_layout()
  let int_arg_regs = [call_conv.context_arg, ..call_conv.user_arg_gprs]
  let float_arg_regs = call_conv.arg_fprs
  let mut int_idx = 0
  let mut float_idx = 0
  for param_idx, param in params {
    let loc = output.get_param_loc(param_idx)
    match param.class {
      Int =>
        if int_idx < int_arg_regs.length() {
          let x_src = int_arg_regs[int_idx].index
          match loc {
            Spill(slot) =>
              self.emit_str_imm(x_src, 31, stack_frame.spill_offset + slot * 8)
            _ => ()
          }
          int_idx += 1
        }
      Float32 | Float64 =>
        if float_idx < float_arg_regs.length() {
          let v_src = float_arg_regs[float_idx].index
          match loc {
            Spill(slot) =>
              self.emit_str_d_imm(
                v_src,
                31,
                stack_frame.spill_offset + slot * 8,
              )
            _ => ()
          }
          float_idx += 1
        }
      Vector =>
        if float_idx < float_arg_regs.length() {
          let v_src = float_arg_regs[float_idx].index
          match loc {
            Spill(slot) =>
              self.emit_str_q_imm(
                v_src,
                31,
                stack_frame.spill_offset + slot * 8,
              )
            _ => ()
          }
          float_idx += 1
        }
    }
  }

  // Now move register params to their assigned registers, using a parallel move resolver.
  fn emit_parallel_moves_x(
    self : MachineCode,
    moves : Array[(Int, Int)],
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
            self.emit_mov_reg(dst, src)
          }
        }
        None => {
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
            guard found >= 0 else { abort("prologue parallel move (x): cycle") }
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
    moves : Array[(Int, Int)],
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
            guard found >= 0 else { abort("prologue parallel move (v): cycle") }
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

  // Collect moves from ABI incoming regs to allocated regs.
  let int_moves : Array[(Int, Int)] = []
  let fp_moves : Array[(Int, Int)] = []
  int_idx = 0
  float_idx = 0
  for param_idx, param in params {
    let loc = output.get_param_loc(param_idx)
    match param.class {
      Int =>
        if int_idx < int_arg_regs.length() {
          let x_src = int_arg_regs[int_idx].index
          match loc {
            Reg(dst) =>
              if dst.index != x_src {
                let context_dst = stack_frame.context_reg_index()
                let is_redundant_context_move = int_idx == 0 &&
                  stack_frame.needs_context_reg &&
                  dst.index == context_dst
                if !is_redundant_context_move {
                  int_moves.push((x_src, dst.index))
                }
              }
            _ => ()
          }
          int_idx += 1
        }
      Float32 | Float64 | Vector =>
        if float_idx < float_arg_regs.length() {
          let v_src = float_arg_regs[float_idx].index
          match loc {
            Reg(dst) =>
              if dst.index != v_src {
                fp_moves.push((v_src, dst.index))
              }
            _ => ()
          }
          float_idx += 1
        }
    }
  }
  emit_parallel_moves_x(self, int_moves)
  emit_parallel_moves_v(self, fp_moves)
}

///|
/// Emit machine code using the Cranelift-style regalloc output.
pub fn emit_function_with_regalloc(
  func : @machv.Function,
  output : @machv_regalloc.Output,
  isa? : @isa.ISA = AArch64,
  debug_func_idx? : Int? = None,
  force_frame_setup? : Bool = false,
  embedding_abi? : @abi.EmbeddingABI? = None,
  record_disasm? : Bool = true,
) -> MachineCode {
  // Regalloc output carries edge copies as edits keyed by original blocks.
  // Reorder blocks, but do not thread jumps across edge-copy blocks.
  let func = @layout.optimize_layout_preserving_edges(func)
  let mc = MachineCode::new(isa~, record_disasm~)
  let is_amd64 = isa is AMD64
  let embedding_abi = require_embedding_abi(embedding_abi)

  // Compute clobbers from regalloc output.
  let clobbered = collect_used_callee_saved_from_output(func, output, isa)
  let clobbered_fprs = collect_used_callee_saved_fprs_from_output(
    func, output, isa,
  )
  let has_calls = func_has_calls(func)
  let has_incoming_stack_args = func_has_incoming_stack_args(func)
  let uses_context_cache_0_source = func.uses_context_cache_0_source()
  let cache_context_0 = func.should_reserve_context_cache_0()
  let cache_context_1 = func.should_reserve_context_cache_1()
  let context_reg = embedding_abi.reg_roles.context
  let force_context_reg_cache = embedding_abi.reserve_context_role &&
    isa is AMD64 &&
    context_reg is Some(_)
  let needs_context_reg = force_context_reg_cache ||
    has_calls ||
    (context_reg is Some({ index, .. }) && func_uses_context_reg(func, index)) ||
    (
      context_reg is Some({ index, .. }) &&
      output_uses_preg(func, output, index)
    ) ||
    uses_context_cache_0_source
  let clobbered_gprs = clobbered
  if cache_context_0 &&
    embedding_abi.reg_roles.context_cache_0 is Some(cache) &&
    !clobbered_gprs.contains(cache.index) {
    clobbered_gprs.push(cache.index)
  }
  if cache_context_1 &&
    embedding_abi.reg_roles.context_cache_1 is Some(cache) &&
    !clobbered_gprs.contains(cache.index) {
    clobbered_gprs.push(cache.index)
  }
  let num_spill_slots = output.get_num_spillslots()
  let needs_debug_idx_restore = debug_func_idx is Some(_) && needs_context_reg
  let total_spill_slots = if needs_debug_idx_restore {
    num_spill_slots + 1
  } else {
    num_spill_slots
  }
  let stack_frame = EmitStackFrame::build(
    clobbered_gprs,
    clobbered_fprs,
    total_spill_slots,
    has_calls~,
    outgoing_args_size=func.get_max_outgoing_args_size(),
    needs_context_reg~,
    cache_context_0~,
    cache_context_1~,
    force_frame_setup~,
    has_incoming_stack_args~,
    embedding_abi=Some(embedding_abi),
    isa~,
  )
  if needs_debug_idx_restore {
    mc.set_debug_prev_func_idx_spill_offset(
      stack_frame.get_spill_offset(num_spill_slots),
    )
  }

  // Emit prologue.
  mc.emit_prologue_with_output(
    stack_frame,
    func.get_params(),
    output,
    debug_func_idx,
  )

  // Emit function body.
  let blocks = func.get_blocks()
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
  let edit_slot_cache : Map[Int, @abi.PReg] = {}
  fn emit_point_edits(
    mc : MachineCode,
    output : @machv_regalloc.Output,
    block_id : Int,
    inst_idx : Int,
    pos : @machv_regalloc.ProgPos,
    stack_frame : EmitStackFrame,
    edit_slot_cache : Map[Int, @abi.PReg],
  ) -> Unit {
    if output.edits_at(block_id, inst_idx, pos) is Some(edits) {
      for edit in edits {
        emit_edit_move_with_cache(mc, edit, stack_frame, edit_slot_cache)
      }
    }
  }
  for i, block in blocks {
    edit_slot_cache.clear()
    mc.define_label(block.id)
    for inst_idx, inst in block.insts {
      // Edits before instruction.
      emit_point_edits(
        mc,
        output,
        block.id,
        inst_idx,
        Before,
        stack_frame,
        edit_slot_cache,
      )
      let mapped = map_inst_for_emission(block.id, inst_idx, inst, output)
      mc.emit_instruction(mapped, stack_frame)
      invalidate_edit_slot_cache_defs(edit_slot_cache, mapped)

      // Edits after instruction.
      emit_point_edits(
        mc,
        output,
        block.id,
        inst_idx,
        After,
        stack_frame,
        edit_slot_cache,
      )
    }
    if block.terminator is Some(term) {
      let term_inst = block.insts.length()
      // Edits before terminator (block-arg moves, terminator reloads, etc).
      emit_point_edits(
        mc,
        output,
        block.id,
        term_inst,
        Before,
        stack_frame,
        edit_slot_cache,
      )
      let next_block = if i + 1 < blocks.length() {
        Some(blocks[i + 1].id)
      } else {
        None
      }
      let mapped_term = map_term_for_emission(block.id, term_inst, term, output)
      mc.emit_terminator_with_epilogue(
        mapped_term,
        stack_frame,
        func.get_result_kinds(),
        next_block,
        shared_exit_block,
      )
    }
  }
  if shared_exit_block is Some(exit_block) {
    mc.define_label(exit_block)
    mc.emit_epilogue(stack_frame)
    if is_amd64 {
      mc.x86_emit_ret()
    } else {
      mc.emit_ret(30)
    }
  }
  if !is_amd64 {
    mc.materialize_call_veneers()
  } else {
    mc.emit_amd64_const_pool()
  }
  mc.resolve_fixups()
  mc
}
