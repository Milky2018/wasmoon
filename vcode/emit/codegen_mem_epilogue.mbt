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
fn index_extend_to_option(ext : @instr.IndexExtend) -> Int {
  match ext {
    None => 0b011 // LSL (X offset)
    Uxtw => 0b010 // UXTW
    Sxtw => 0b110 // SXTW
  }
}

///|
fn MachineCode::emit_load_reg_offset(
  self : MachineCode,
  ty : @instr.MemType,
  rt : Int,
  rn : Int,
  rm : Int,
  ext : @instr.IndexExtend,
  shift : Int,
) -> Unit {
  let option = index_extend_to_option(ext)
  match ty {
    I32 => self.emit_ldr_reg_offset(rt, rn, rm, option, 2, shift)
    I64 => self.emit_ldr_reg_offset(rt, rn, rm, option, 3, shift)
    _ => abort("emit_load_reg_offset unsupported type: \{ty}")
  }
}

///|
fn MachineCode::emit_store_reg_offset(
  self : MachineCode,
  ty : @instr.MemType,
  rt : Int,
  rn : Int,
  rm : Int,
  ext : @instr.IndexExtend,
  shift : Int,
) -> Unit {
  let option = index_extend_to_option(ext)
  match ty {
    I32 => self.emit_str_reg_offset(rt, rn, rm, option, 2, shift)
    I64 => self.emit_str_reg_offset(rt, rn, rm, option, 3, shift)
    _ => abort("emit_store_reg_offset unsupported type: \{ty}")
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
  if current_isa() is @isa.AMD64 {
    let isa = current_isa()
    let saved_gprs = stack_frame.saved_gprs

    // Step 1: Deallocate remaining stack space (spill slots + outgoing args).
    let remaining_size = stack_frame.spill_size + stack_frame.outgoing_args_size
    if remaining_size > 0 {
      self.emit_sp_adjust(remaining_size)
    }

    // SysV has no callee-saved XMM regs.
    if stack_frame.saved_fprs.length() > 0 {
      abort("x86_64 epilogue: unexpected callee-saved fprs")
    }

    // Undo GPR-save padding.
    let gpr_padding = stack_frame.gpr_save_size - saved_gprs.length() * 8
    if gpr_padding > 0 {
      self.x86_emit_add_rsp_imm32(gpr_padding)
    }

    // Restore callee-saved GPRs (reverse order).
    let mut i = saved_gprs.length() - 1
    while i >= 0 {
      self.x86_emit_pop_r64(saved_gprs[i])
      i = i - 1
    }

    // Restore rbp and setup-area padding.
    if stack_frame.has_setup_area {
      if stack_frame.setup_area_size > 8 {
        self.x86_emit_add_rsp_imm32(stack_frame.setup_area_size - 8)
      }
      self.x86_emit_pop_r64(isa.fp_reg_index())
    }
    return
  }
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
  if current_isa() is @isa.AMD64 {
    self.emit_terminator_with_epilogue_x86_64(
      term, stack_frame, result_types, next_block, shared_exit_block,
    )
    return
  }
  fn trap_msg_to_brk_imm(msg : String) -> Int {
    // Keep this mapping in sync with `jit/jit_ffi/trap.c`:
    //   0 unreachable
    //   1 out of bounds (memory/table)
    //   2 indirect call type mismatch
    //   3 invalid conversion to integer
    //   4 integer divide by zero
    //   5 integer overflow
    if msg == "unreachable" {
      0
    } else if msg.contains("out of bounds") {
      1
    } else if msg.contains("type mismatch") {
      2
    } else if msg.contains("invalid conversion") {
      3
    } else if msg.contains("divide by zero") {
      4
    } else if msg.contains("overflow") {
      5
    } else {
      0
    }
  }

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
    Trap(msg) => self.emit_brk(trap_msg_to_brk_imm(msg))
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
