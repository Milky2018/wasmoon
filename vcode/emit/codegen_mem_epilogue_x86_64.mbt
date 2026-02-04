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
  fn trap_msg_to_imm16(msg : String) -> Int {
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
    @instr.Branch(cond, then_b, else_b) => {
      // Treat Branch as "cond != 0".
      let rt = reg_num(cond)
      // Branch inversion: if then_b is next block, invert to branch to else_b.
      if next_block == Some(then_b) {
        // cond == 0 => else_b
        self.x86_emit_test_rr(rt, rt)
        self.x86_emit_jcc_rel32(@instr.Cond::Eq, else_b)
      } else {
        self.x86_emit_test_rr(rt, rt)
        self.x86_emit_jcc_rel32(@instr.Cond::Ne, then_b)
        if next_block != Some(else_b) {
          self.x86_emit_jmp_rel32(else_b)
        }
      }
    }
    @instr.BranchZero(reg, is_nonzero, is_64, then_b, else_b) => {
      let rt = reg_num(reg)
      if is_64 {
        self.x86_emit_test_rr(rt, rt)
      } else {
        self.x86_emit_test_rr32(rt, rt)
      }
      let cond_to_then = if is_nonzero {
        @instr.Cond::Ne
      } else {
        @instr.Cond::Eq
      }
      if next_block == Some(then_b) {
        self.x86_emit_jcc_rel32(cond_to_then.invert(), else_b)
      } else {
        self.x86_emit_jcc_rel32(cond_to_then, then_b)
        if next_block != Some(else_b) {
          self.x86_emit_jmp_rel32(else_b)
        }
      }
    }
    @instr.BranchCmp(lhs, rhs, cond, is_64, then_b, else_b) => {
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
    @instr.BranchCmpImm(lhs, imm, cond, is_64, then_b, else_b) => {
      let rn = reg_num(lhs)
      let scratch = isa.scratch_reg_1_index()
      self.x86_emit_mov_imm64(scratch, imm.to_int64())
      if is_64 {
        self.x86_emit_cmp_rr(rn, scratch)
      } else {
        self.x86_emit_cmp_rr32(rn, scratch)
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
    @instr.Jump(target, _args) =>
      if next_block != Some(target) {
        self.x86_emit_jmp_rel32(target)
      }
    @instr.Trap(msg) => self.x86_emit_trap_imm16(trap_msg_to_imm16(msg))
    @instr.Return(values) => {
      // Minimal return convention:
      // - ints go to ISA.wasm_ret_gprs()
      // - floats/vectors go to ISA.wasm_ret_fprs()
      //
      // For now, require returns fit in the register lists.
      let int_rets = isa.wasm_ret_gprs()
      let fp_rets = isa.wasm_ret_fprs()
      let int_moves : Array[(Int, Int)] = []
      let fp_moves : Array[(Int, Int)] = []
      let mut int_idx = 0
      let mut fp_idx = 0
      for i, v in values {
        let src = reg_num(v)
        let ty = if i < result_types.length() {
          result_types[i]
        } else {
          @ir.Type::I64
        }
        match ty {
          @ir.Type::F32 | @ir.Type::F64 | @ir.Type::V128 => {
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
            int_moves.push((src, int_rets[int_idx].index))
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

      // Return sequence.
      self.emit_epilogue(stack_frame)
      self.x86_emit_ret()
    }
    _ => abort("x86_64 terminator not implemented: \{term}")
  }
}
