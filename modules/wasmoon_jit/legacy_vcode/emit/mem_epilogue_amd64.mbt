///|
/// x86_64 terminator emission (minimal subset).
///
/// Implement enough to return from functions and take traps. Full control-flow
/// emission (branches, tables, calls) will be added incrementally.

///|
fn MachineCode::emit_terminator_with_epilogue_x86_64(
  self : MachineCode,
  term : @instr.VCodeTerminator,
  stack_frame : JITStackFrame,
  result_types : Array[@ir.Type],
  next_block : Int?,
  _shared_exit_block : Int?,
) -> Unit {
  let isa = @isa.ISA::current()
  self.annotate(term.to_string())
  match term {
    Branch(cond, then_b, else_b) => {
      // Treat Branch as "cond != 0".
      let rt = reg_num(cond)
      // Branch inversion: if then_b is next block, invert to branch to else_b.
      if next_block == Some(then_b) {
        // cond == 0 => else_b
        self.x86_emit_test_rr32(rt, rt)
        self.x86_emit_jcc_rel32(Eq, else_b)
      } else {
        self.x86_emit_test_rr32(rt, rt)
        self.x86_emit_jcc_rel32(Ne, then_b)
        if next_block != Some(else_b) {
          self.x86_emit_jmp_rel32(else_b)
        }
      }
    }
    BranchZero(reg, is_nonzero, is_64, then_b, else_b) => {
      let rt = reg_num(reg)
      if is_64 {
        self.x86_emit_test_rr(rt, rt)
      } else {
        self.x86_emit_test_rr32(rt, rt)
      }
      let cond_to_then = if is_nonzero { @instr.Cond::Ne } else { Eq }
      if next_block == Some(then_b) {
        self.x86_emit_jcc_rel32(cond_to_then.invert(), else_b)
      } else {
        self.x86_emit_jcc_rel32(cond_to_then, then_b)
        if next_block != Some(else_b) {
          self.x86_emit_jmp_rel32(else_b)
        }
      }
    }
    BranchCmp(lhs, rhs, cond, is_64, then_b, else_b) => {
      let rn = reg_num(lhs)
      let rm = reg_num(rhs)
      if is_64 {
        self.x86_emit_cmp_rr(rn, rm)
      } else {
        self.x86_emit_cmp_rr32(rn, rm)
      }
      if next_block == Some(then_b) {
        self.x86_emit_jcc_rel32(cond.invert(), else_b)
      } else {
        self.x86_emit_jcc_rel32(cond, then_b)
        if next_block != Some(else_b) {
          self.x86_emit_jmp_rel32(else_b)
        }
      }
    }
    BranchCmpImm(lhs, imm, cond, is_64, then_b, else_b) => {
      let rn = reg_num(lhs)
      if @machv_emit.fits_signed_i32(imm) {
        if is_64 {
          self.x86_emit_cmp_r_imm32(rn, imm)
        } else {
          self.x86_emit_cmp_r32_imm32(rn, imm)
        }
      } else {
        let mut scratch = isa.scratch_reg_1_index()
        if scratch == rn {
          scratch = isa.scratch_reg_2_index()
        }
        self.x86_emit_mov_imm64(scratch, imm.to_int64())
        if is_64 {
          self.x86_emit_cmp_rr(rn, scratch)
        } else {
          self.x86_emit_cmp_rr32(rn, scratch)
        }
      }
      if next_block == Some(then_b) {
        self.x86_emit_jcc_rel32(cond.invert(), else_b)
      } else {
        self.x86_emit_jcc_rel32(cond, then_b)
        if next_block != Some(else_b) {
          self.x86_emit_jmp_rel32(else_b)
        }
      }
    }
    Jump(target, args) =>
      if args.length() > 0 || next_block != Some(target) {
        self.x86_emit_jmp_rel32(target)
      }
    Trap(msg) =>
      self.x86_emit_trap_imm16(
        @wasmoon_jit.legacy_trap_immediate_from_message(msg),
      )
    BrTable(index, targets, default) => {
      // Jump table implementation for br_table (Cranelift-style rel32 table).
      //
      // Layout:
      //   cmp index, n; jae default
      //   lea base, [rip + table]
      //   tmp = base + (index << 2)
      //   rel32 = *(i32*)tmp
      //   target = (tmp + 4) + rel32
      //   jmp target
      // table: dd target0 - (entry_end), dd target1 - (entry_end), ...
      let index_reg = reg_num(index)
      let num_targets = targets.length()
      let table = self.new_internal_label()
      let base = isa.scratch_reg_1_index()
      let tmp = isa.scratch_reg_2_index()

      // Bounds check: if index >= num_targets (unsigned), jump to default.
      self.x86_emit_cmp_r32_imm32(index_reg, num_targets)
      self.x86_emit_jcc_rel32(Hs, default)

      // tmp = index*4
      // `br_table` index is i32 in Wasm; ensure zero-extension to avoid
      // accidentally using garbage in the high 32 bits.
      self.x86_emit_mov_rr32(tmp, index_reg)
      self.x86_emit_shl_r32_imm8(tmp, 2)
      // base = &table
      self.x86_emit_lea_r64_riprel32(base, table)
      // tmp = base + index*4
      self.x86_emit_add_rr(tmp, base)

      // base = rel32 (sign-extended)
      self.x86_emit_mov_r32_m32(base, tmp, 0)
      self.x86_emit_movsxd_r64_r32(base, base)

      // tmp = entry_end
      self.x86_emit_add_r_imm8(tmp, 4)
      // tmp = target
      self.x86_emit_add_rr(tmp, base)
      self.x86_emit_jmp_r64(tmp)

      // Emit jump table data (rel32 entries).
      self.define_label(table)
      for target in targets {
        let disp_offset = self.current_pos()
        self.emit_inst(0, 0, 0, 0)
        let next_ip_offset = self.current_pos()
        self.add_x86_rel32_fixup(target, disp_offset, next_ip_offset)
      }
    }
    Return(values) => {
      // Minimal return convention:
      // - ints go to ISA.wasm_ret_gprs()
      // - floats/vectors go to ISA.wasm_ret_fprs()
      //
      // For now, require returns fit in the register lists.
      let int_rets = isa.wasm_ret_gprs()
      let fp_rets = isa.wasm_ret_fprs()
      let int_moves : Array[(Int, Int)] = []
      let int_ret_regs_i32 : Array[Int] = []
      let fp_moves : Array[(Int, Int)] = []
      let mut int_idx = 0
      let mut fp_idx = 0
      for i, v in values {
        let src = reg_num(v)
        let ty = if i < result_types.length() { result_types[i] } else { I64 }
        match ty {
          F32 | F64 | V128 => {
            guard fp_idx < fp_rets.length() else {
              abort("x86_64 return: too many fp returns")
            }
            fp_moves.push((src, fp_rets[fp_idx].index))
            fp_idx += 1
          }
          _ => {
            guard int_idx < int_rets.length() else {
              abort("x86_64 return: too many int returns")
            }
            let dst = int_rets[int_idx].index
            int_moves.push((src, dst))
            if ty is I32 {
              int_ret_regs_i32.push(dst)
            }
            int_idx += 1
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
                  abort("return parallel move (x86 gpr): cycle")
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
                  abort("return parallel move (x86 xmm): cycle")
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

      emit_parallel_moves_gpr(self, isa.scratch_reg_2_index(), int_moves)
      emit_parallel_moves_xmm(self, 15, fp_moves)
      // Canonicalize i32 returns to low-32-bit values.
      // This prevents stale high 32 bits from affecting later i32 condition uses.
      for reg in int_ret_regs_i32 {
        self.x86_emit_mov_rr32(reg, reg)
      }

      // Return sequence.
      self.emit_epilogue(stack_frame)
      self.x86_emit_ret()
    }
  }
}
