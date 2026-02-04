///|
/// x86_64 VCode -> machine code emission (minimal subset).
///
/// This is Step 3 scaffolding: implement enough to validate the ABI plumbing
/// (prologue/epilogue, stack slots, simple arithmetic). The full backend will
/// be implemented incrementally.

///|
fn MachineCode::emit_instruction_x86_64(
  self : MachineCode,
  inst : @instr.VCodeInst,
  stack_frame : JITStackFrame,
) -> Unit {
  let spill_base_offset = stack_frame.spill_offset
  let frame_size = stack_frame.total_size
  let isa = @isa.ISA::current()
  fn cmp_kind_to_cond(kind : @instr.CmpKind) -> @instr.Cond {
    match kind {
      @instr.CmpKind::Eq => @instr.Cond::Eq
      @instr.CmpKind::Ne => @instr.Cond::Ne
      @instr.CmpKind::Slt => @instr.Cond::Lt
      @instr.CmpKind::Sle => @instr.Cond::Le
      @instr.CmpKind::Sgt => @instr.Cond::Gt
      @instr.CmpKind::Sge => @instr.Cond::Ge
      @instr.CmpKind::Ult => @instr.Cond::Lo
      @instr.CmpKind::Ule => @instr.Cond::Ls
      @instr.CmpKind::Ugt => @instr.Cond::Hi
      @instr.CmpKind::Uge => @instr.Cond::Hs
    }
  }

  fn fcmp_kind_to_cond(kind : @instr.FCmpKind) -> @instr.Cond {
    // x86 UCOMIS* sets flags like an unsigned compare:
    // - CF=1 => less-than
    // - ZF=1 => equal
    // - PF=1 => unordered (NaN)
    match kind {
      @instr.FCmpKind::Eq => @instr.Cond::Eq
      @instr.FCmpKind::Ne => @instr.Cond::Ne
      @instr.FCmpKind::Lt => @instr.Cond::Lo
      @instr.FCmpKind::Le => @instr.Cond::Ls
      @instr.FCmpKind::Gt => @instr.Cond::Hi
      @instr.FCmpKind::Ge => @instr.Cond::Hs
    }
  }

  fn reg_class_of(reg : @abi.Reg) -> @abi.RegClass {
    match reg {
      @abi.Physical(preg) => preg.class
      @abi.Virtual(vreg) => vreg.class
    }
  }

  fn reg_class_of_w(wreg : @abi.Writable) -> @abi.RegClass {
    reg_class_of(wreg.reg)
  }

  fn emit_reg_move(
    self : MachineCode,
    dst : Int,
    src : Int,
    class : @abi.RegClass,
  ) -> Unit {
    if dst == src {
      return
    }
    match class {
      @abi.Int => self.x86_emit_mov_rr(dst, src)
      @abi.Float32 | @abi.Float64 | @abi.Vector =>
        self.x86_emit_movaps_xmm_xmm(dst, src)
    }
  }

  match inst.opcode {
    @instr.Add(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      // Expect the standard 2-operand lowering: rd == rn.
      if rd != rn {
        abort("x86_64 Add: expected dst == lhs")
      }
      if is_64 {
        self.x86_emit_add_rr(rd, rm)
      } else {
        self.x86_emit_add_rr32(rd, rm)
      }
    }
    @instr.Sub(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if rd != rn {
        abort("x86_64 Sub: expected dst == lhs")
      }
      if is_64 {
        self.x86_emit_sub_rr(rd, rm)
      } else {
        self.x86_emit_sub_rr32(rd, rm)
      }
    }
    @instr.AddImm(imm, is_64) => {
      // Fallback: materialize imm into scratch and use add/sub.
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if rd != rn {
        abort("x86_64 AddImm: expected dst == lhs")
      }
      let scratch = isa.scratch_reg_1_index()
      self.x86_emit_mov_imm64(scratch, imm.to_int64())
      if is_64 {
        self.x86_emit_add_rr(rd, scratch)
      } else {
        self.x86_emit_add_rr32(rd, scratch)
      }
    }
    @instr.SubImm(imm, is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if rd != rn {
        abort("x86_64 SubImm: expected dst == lhs")
      }
      let scratch = isa.scratch_reg_1_index()
      self.x86_emit_mov_imm64(scratch, imm.to_int64())
      if is_64 {
        self.x86_emit_sub_rr(rd, scratch)
      } else {
        self.x86_emit_sub_rr32(rd, scratch)
      }
    }
    @instr.Mul(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if rd != rn {
        abort("x86_64 Mul: expected dst == lhs")
      }
      if is_64 {
        self.x86_emit_imul_rr(rd, rm)
      } else {
        self.x86_emit_imul_rr32(rd, rm)
      }
    }
    @instr.And(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if rd != rn {
        abort("x86_64 And: expected dst == lhs")
      }
      if is_64 {
        self.x86_emit_and_rr(rd, rm)
      } else {
        self.x86_emit_and_rr32(rd, rm)
      }
    }
    @instr.Or(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if rd != rn {
        abort("x86_64 Or: expected dst == lhs")
      }
      if is_64 {
        self.x86_emit_or_rr(rd, rm)
      } else {
        self.x86_emit_or_rr32(rd, rm)
      }
    }
    @instr.Xor(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if rd != rn {
        abort("x86_64 Xor: expected dst == lhs")
      }
      if is_64 {
        self.x86_emit_xor_rr(rd, rm)
      } else {
        self.x86_emit_xor_rr32(rd, rm)
      }
    }
    @instr.Not(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if rd != rn {
        abort("x86_64 Not: expected dst == src")
      }
      if is_64 {
        self.x86_emit_not_r64(rd)
      } else {
        self.x86_emit_not_r32(rd)
      }
    }
    @instr.Move => {
      let rd = wreg_num(inst.defs[0])
      let rm = reg_num(inst.uses[0])
      if rd == rm {
        return
      }
      let reg_class = match inst.defs[0].reg {
        @abi.Physical(preg) => preg.class
        @abi.Virtual(_) => @abi.Int
      }
      match reg_class {
        @abi.Int => self.x86_emit_mov_rr(rd, rm)
        @abi.Float32 | @abi.Float64 | @abi.Vector =>
          self.x86_emit_movaps_xmm_xmm(rd, rm)
      }
    }
    @instr.LoadConst(v) => {
      let rd = wreg_num(inst.defs[0])
      self.x86_emit_mov_imm64(rd, v)
    }
    @instr.LoadConstF32(bits) => {
      let rd = wreg_num(inst.defs[0])
      let scratch = isa.scratch_reg_1_index()
      // Materialize the raw f32 bits into a GPR then move into XMM.
      self.x86_emit_mov_imm64(scratch, bits.to_int64())
      self.x86_emit_movd_xmm_r32(rd, scratch)
    }
    @instr.LoadConstF64(bits) => {
      let rd = wreg_num(inst.defs[0])
      let scratch = isa.scratch_reg_1_index()
      // Materialize the raw f64 bits into a GPR then move into XMM.
      self.x86_emit_mov_imm64(scratch, bits)
      self.x86_emit_movq_xmm_r64(rd, scratch)
    }
    @instr.LoadGCFuncPtr(libcall) => {
      let rd = wreg_num(inst.defs[0])
      let func_ptr = match libcall {
        @instr.GCLibcall::RefTest => @jit_ffi.c_jit_get_gc_ref_test_ptr()
        @instr.GCLibcall::RefCast => @jit_ffi.c_jit_get_gc_ref_cast_ptr()
        @instr.GCLibcall::StructNew => @jit_ffi.c_jit_get_gc_struct_new_ptr()
        @instr.GCLibcall::StructGet => @jit_ffi.c_jit_get_gc_struct_get_ptr()
        @instr.GCLibcall::StructSet => @jit_ffi.c_jit_get_gc_struct_set_ptr()
        @instr.GCLibcall::ArrayNew => @jit_ffi.c_jit_get_gc_array_new_ptr()
        @instr.GCLibcall::ArrayGet => @jit_ffi.c_jit_get_gc_array_get_ptr()
        @instr.GCLibcall::ArraySet => @jit_ffi.c_jit_get_gc_array_set_ptr()
        @instr.GCLibcall::ArrayLen => @jit_ffi.c_jit_get_gc_array_len_ptr()
        @instr.GCLibcall::ArrayFill => @jit_ffi.c_jit_get_gc_array_fill_ptr()
        @instr.GCLibcall::ArrayCopy => @jit_ffi.c_jit_get_gc_array_copy_ptr()
        @instr.GCLibcall::ArrayNewData =>
          @jit_ffi.c_jit_get_gc_array_new_data_ptr()
        @instr.GCLibcall::ArrayNewElem =>
          @jit_ffi.c_jit_get_gc_array_new_elem_ptr()
        @instr.GCLibcall::ArrayInitData =>
          @jit_ffi.c_jit_get_gc_array_init_data_ptr()
        @instr.GCLibcall::ArrayInitElem =>
          @jit_ffi.c_jit_get_gc_array_init_elem_ptr()
        @instr.GCLibcall::TypeCheckSubtype =>
          @jit_ffi.c_jit_get_gc_type_check_subtype_ptr()
        @instr.GCLibcall::RegisterStructInline =>
          @jit_ffi.c_jit_get_gc_register_struct_inline_ptr()
        @instr.GCLibcall::RegisterArrayInline =>
          @jit_ffi.c_jit_get_gc_register_array_inline_ptr()
        @instr.GCLibcall::AllocStructSlow =>
          @jit_ffi.c_jit_get_gc_alloc_struct_slow_ptr()
        @instr.GCLibcall::AllocArraySlow =>
          @jit_ffi.c_jit_get_gc_alloc_array_slow_ptr()
      }
      self.x86_emit_mov_imm64(rd, func_ptr)
    }
    @instr.LoadJITFuncPtr(libcall) => {
      let rd = wreg_num(inst.defs[0])
      let func_ptr = match libcall {
        @instr.JITLibcall::MemoryGrow => @jit_ffi.c_jit_get_memory_grow_ptr()
        @instr.JITLibcall::MemorySize => @jit_ffi.c_jit_get_memory_size_ptr()
        @instr.JITLibcall::MemoryFill => @jit_ffi.c_jit_get_memory_fill_ptr()
        @instr.JITLibcall::MemoryCopy => @jit_ffi.c_jit_get_memory_copy_ptr()
        @instr.JITLibcall::MemoryInit => @jit_ffi.c_jit_get_memory_init_ptr()
        @instr.JITLibcall::DataDrop => @jit_ffi.c_jit_get_data_drop_ptr()
        @instr.JITLibcall::TableGrow => @jit_ffi.c_jit_get_table_grow_ptr()
        @instr.JITLibcall::TableFill => @jit_ffi.c_jit_get_table_fill_ptr()
        @instr.JITLibcall::TableCopy => @jit_ffi.c_jit_get_table_copy_ptr()
        @instr.JITLibcall::TableInit => @jit_ffi.c_jit_get_table_init_ptr()
        @instr.JITLibcall::ElemDrop => @jit_ffi.c_jit_get_elem_drop_ptr()
        @instr.JITLibcall::HostCall => @jit_ffi.c_jit_get_hostcall_ptr()
      }
      self.x86_emit_mov_imm64(rd, func_ptr)
    }
    @instr.LoadExceptionFuncPtr(libcall) => {
      let rd = wreg_num(inst.defs[0])
      let func_ptr = match libcall {
        @instr.ExceptionLibcall::TryBegin =>
          @jit_ffi.c_jit_get_exception_try_begin_ptr()
        @instr.ExceptionLibcall::TryEnd =>
          @jit_ffi.c_jit_get_exception_try_end_ptr()
        @instr.ExceptionLibcall::Throw =>
          @jit_ffi.c_jit_get_exception_throw_ptr()
        @instr.ExceptionLibcall::ThrowRef =>
          @jit_ffi.c_jit_get_exception_throw_ref_ptr()
        @instr.ExceptionLibcall::Delegate =>
          @jit_ffi.c_jit_get_exception_delegate_ptr()
        @instr.ExceptionLibcall::GetTag =>
          @jit_ffi.c_jit_get_exception_get_tag_ptr()
        @instr.ExceptionLibcall::GetValue =>
          @jit_ffi.c_jit_get_exception_get_value_ptr()
        @instr.ExceptionLibcall::GetValueCount =>
          @jit_ffi.c_jit_get_exception_get_value_count_ptr()
        @instr.ExceptionLibcall::Sigsetjmp => @jit_ffi.c_jit_get_sigsetjmp_ptr()
        @instr.ExceptionLibcall::SpillLocals =>
          @jit_ffi.c_jit_get_exception_spill_locals_ptr()
        @instr.ExceptionLibcall::GetSpilledLocal =>
          @jit_ffi.c_jit_get_exception_get_spilled_local_ptr()
      }
      self.x86_emit_mov_imm64(rd, func_ptr)
    }
    @instr.Cmp(kind, is_64) => {
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_64 {
        self.x86_emit_cmp_rr(rn, rm)
      } else {
        self.x86_emit_cmp_rr32(rn, rm)
      }
      let rd = wreg_num(inst.defs[0])
      let cond = cmp_kind_to_cond(kind)
      self.x86_emit_setcc_r8(cond, rd)
      self.x86_emit_movzx_r32_r8(rd, rd)
    }
    @instr.FCmp(kind) => {
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      // FCmp operands are in XMM regs. Use ucomiss/ucomisd based on reg class.
      if reg_class_of(inst.uses[0]) is @abi.Float32 {
        self.x86_emit_ucomiss_xmm_xmm(rn, rm)
      } else {
        self.x86_emit_ucomisd_xmm_xmm(rn, rm)
      }
      let rd = wreg_num(inst.defs[0])
      let cond = fcmp_kind_to_cond(kind)

      // For unordered (NaN), UCOMIS* sets PF=1, ZF=1, CF=1.
      // WebAssembly semantics:
      // - eq/lt/le are false on NaN
      // - ne is true on NaN
      // - gt/ge are false on NaN already via CF/ZF
      let scratch = isa.scratch_reg_1_index()
      match kind {
        @instr.FCmpKind::Eq => {
          self.x86_emit_setcc_r8(cond, rd)
          self.x86_emit_setcc_r8(@instr.Cond::Vc, scratch) // ordered (PF==0)
          self.x86_emit_movzx_r32_r8(rd, rd)
          self.x86_emit_movzx_r32_r8(scratch, scratch)
          self.x86_emit_and_rr32(rd, scratch)
        }
        @instr.FCmpKind::Ne => {
          self.x86_emit_setcc_r8(cond, rd)
          self.x86_emit_setcc_r8(@instr.Cond::Vs, scratch) // unordered (PF==1)
          self.x86_emit_movzx_r32_r8(rd, rd)
          self.x86_emit_movzx_r32_r8(scratch, scratch)
          self.x86_emit_or_rr32(rd, scratch)
        }
        @instr.FCmpKind::Lt | @instr.FCmpKind::Le => {
          self.x86_emit_setcc_r8(cond, rd)
          self.x86_emit_setcc_r8(@instr.Cond::Vc, scratch) // ordered (PF==0)
          self.x86_emit_movzx_r32_r8(rd, rd)
          self.x86_emit_movzx_r32_r8(scratch, scratch)
          self.x86_emit_and_rr32(rd, scratch)
        }
        _ => {
          self.x86_emit_setcc_r8(cond, rd)
          self.x86_emit_movzx_r32_r8(rd, rd)
        }
      }
    }
    @instr.FpuCmp(is_f32) => {
      // Floating-point compare that only sets flags (no result).
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        self.x86_emit_ucomiss_xmm_xmm(rn, rm)
      } else {
        self.x86_emit_ucomisd_xmm_xmm(rn, rm)
      }
    }
    @instr.Shl(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if rm != 1 {
        abort("x86_64 Shl: expected shift count in rcx")
      }
      if rd != rn {
        self.x86_emit_mov_rr(rd, rn)
      }
      if is_64 {
        self.x86_emit_shl_r_cl(rd)
      } else {
        self.x86_emit_shl_r32_cl(rd)
      }
    }
    @instr.ShlImm(amt, is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if rd != rn {
        self.x86_emit_mov_rr(rd, rn)
      }
      if is_64 {
        self.x86_emit_shl_r_imm8(rd, amt)
      } else {
        self.x86_emit_shl_r32_imm8(rd, amt)
      }
    }
    @instr.LShr(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if rm != 1 {
        abort("x86_64 LShr: expected shift count in rcx")
      }
      if rd != rn {
        self.x86_emit_mov_rr(rd, rn)
      }
      if is_64 {
        self.x86_emit_shr_r_cl(rd)
      } else {
        self.x86_emit_shr_r32_cl(rd)
      }
    }
    @instr.LShrImm(amt, is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if rd != rn {
        self.x86_emit_mov_rr(rd, rn)
      }
      if is_64 {
        self.x86_emit_shr_r_imm8(rd, amt)
      } else {
        self.x86_emit_shr_r32_imm8(rd, amt)
      }
    }
    @instr.AShr(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if rm != 1 {
        abort("x86_64 AShr: expected shift count in rcx")
      }
      if rd != rn {
        self.x86_emit_mov_rr(rd, rn)
      }
      if is_64 {
        self.x86_emit_sar_r_cl(rd)
      } else {
        self.x86_emit_sar_r32_cl(rd)
      }
    }
    @instr.AShrImm(amt, is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if rd != rn {
        self.x86_emit_mov_rr(rd, rn)
      }
      if is_64 {
        self.x86_emit_sar_r_imm8(rd, amt)
      } else {
        self.x86_emit_sar_r32_imm8(rd, amt)
      }
    }
    @instr.Rotr(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if rm != 1 {
        abort("x86_64 Rotr: expected shift count in rcx")
      }
      if rd != rn {
        self.x86_emit_mov_rr(rd, rn)
      }
      if is_64 {
        self.x86_emit_ror_r_cl(rd)
      } else {
        self.x86_emit_ror_r32_cl(rd)
      }
    }
    @instr.RotrImm(amt, is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if rd != rn {
        self.x86_emit_mov_rr(rd, rn)
      }
      if is_64 {
        self.x86_emit_ror_r_imm8(rd, amt)
      } else {
        self.x86_emit_ror_r32_imm8(rd, amt)
      }
    }
    @instr.Select => {
      let rd = wreg_num(inst.defs[0])
      let cond_reg = reg_num(inst.uses[0])
      let true_reg = reg_num(inst.uses[1])
      let false_reg = reg_num(inst.uses[2])
      let class = reg_class_of_w(inst.defs[0])
      match class {
        // Match Cranelift x64: integer select uses cmov.
        @abi.Int => {
          // dst = false
          emit_reg_move(self, rd, false_reg, class)
          // Set flags based on cond != 0.
          self.x86_emit_test_rr32(cond_reg, cond_reg)
          // dst = cond ? true : dst
          self.x86_emit_cmovcc_rr(@instr.Cond::Ne, rd, true_reg)
        }
        // Match Cranelift x64: XMM select uses a branch (no cmov for XMM).
        @abi.Float32 | @abi.Float64 | @abi.Vector => {
          // dst = false
          emit_reg_move(self, rd, false_reg, class)
          self.x86_emit_test_rr32(cond_reg, cond_reg)
          let next = self.new_internal_label()
          self.x86_emit_jcc_rel32(@instr.Cond::Eq, next)
          emit_reg_move(self, rd, true_reg, class)
          self.define_label(next)
        }
      }
    }
    @instr.SelectCmp(kind, is_64) => {
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_64 {
        self.x86_emit_cmp_rr(rn, rm)
      } else {
        self.x86_emit_cmp_rr32(rn, rm)
      }
      let rd = wreg_num(inst.defs[0])
      let true_reg = reg_num(inst.uses[2])
      let false_reg = reg_num(inst.uses[3])
      let class = reg_class_of_w(inst.defs[0])
      let cond = cmp_kind_to_cond(kind)
      match class {
        // Match Cranelift x64: integer selectcmp uses cmov.
        @abi.Int => {
          emit_reg_move(self, rd, false_reg, class)
          if is_64 {
            self.x86_emit_cmovcc_rr(cond, rd, true_reg)
          } else {
            self.x86_emit_cmovcc_rr32(cond, rd, true_reg)
          }
        }
        // XMM: branch-based move (no cmov).
        @abi.Float32 | @abi.Float64 | @abi.Vector => {
          emit_reg_move(self, rd, false_reg, class)
          let next = self.new_internal_label()
          self.x86_emit_jcc_rel32(cond.invert(), next)
          emit_reg_move(self, rd, true_reg, class)
          self.define_label(next)
        }
      }
    }
    @instr.TrapIfZero(is_64, trap_code) => {
      let rn = reg_num(inst.uses[0])
      if is_64 {
        self.x86_emit_test_rr(rn, rn)
      } else {
        self.x86_emit_test_rr32(rn, rn)
      }
      let done_l = self.new_internal_label()
      self.x86_emit_jcc_rel32(@instr.Cond::Ne, done_l)
      self.x86_emit_trap_imm16(trap_code)
      self.define_label(done_l)
    }
    @instr.TrapIfDivOverflow(is_64, trap_code) => {
      // Trap if lhs == INT_MIN && rhs == -1.
      let lhs = reg_num(inst.uses[0])
      let rhs = reg_num(inst.uses[1])
      let scratch = isa.scratch_reg_1_index()
      let done_l = self.new_internal_label()
      if is_64 {
        self.x86_emit_mov_imm64(scratch, 0x8000000000000000L)
        self.x86_emit_cmp_rr(lhs, scratch)
        self.x86_emit_jcc_rel32(@instr.Cond::Ne, done_l)
        self.x86_emit_mov_imm64(scratch, -1L)
        self.x86_emit_cmp_rr(rhs, scratch)
        self.x86_emit_jcc_rel32(@instr.Cond::Ne, done_l)
      } else {
        self.x86_emit_mov_imm64(scratch, 0x80000000L)
        self.x86_emit_cmp_rr32(lhs, scratch)
        self.x86_emit_jcc_rel32(@instr.Cond::Ne, done_l)
        self.x86_emit_mov_imm64(scratch, -1L)
        self.x86_emit_cmp_rr32(rhs, scratch)
        self.x86_emit_jcc_rel32(@instr.Cond::Ne, done_l)
      }
      self.x86_emit_trap_imm16(trap_code)
      self.define_label(done_l)
    }
    @instr.SDiv(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let lhs = reg_num(inst.uses[0])
      let rhs = reg_num(inst.uses[1])
      let scratch = isa.scratch_reg_1_index()

      // Preserve divisor if it lives in rax/rdx, since those are overwritten.
      let mut divisor = rhs
      if rhs == 0 || rhs == 2 {
        self.x86_emit_mov_rr(scratch, rhs)
        divisor = scratch
      }

      // Move dividend into rax and sign-extend into rdx.
      if lhs != 0 {
        self.x86_emit_mov_rr(0, lhs)
      }
      if is_64 {
        self.x86_emit_cqo()
        self.x86_emit_idiv_r64(divisor)
      } else {
        self.x86_emit_cdq()
        self.x86_emit_idiv_r32(divisor)
      }
      if rd != 0 {
        self.x86_emit_mov_rr(rd, 0)
      }
    }
    @instr.UDiv(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let lhs = reg_num(inst.uses[0])
      let rhs = reg_num(inst.uses[1])
      let scratch = isa.scratch_reg_1_index()
      let mut divisor = rhs
      if rhs == 0 || rhs == 2 {
        self.x86_emit_mov_rr(scratch, rhs)
        divisor = scratch
      }
      if lhs != 0 {
        self.x86_emit_mov_rr(0, lhs)
      }
      if is_64 {
        self.x86_emit_xor_rr(2, 2) // rdx = 0
        self.x86_emit_div_r64(divisor)
      } else {
        self.x86_emit_xor_rr32(2, 2) // edx = 0
        self.x86_emit_div_r32(divisor)
      }
      if rd != 0 {
        self.x86_emit_mov_rr(rd, 0)
      }
    }
    @instr.SRem(is_64) => {
      // Match Cranelift x64 CheckedSRemSeq behavior: guard `divisor == -1` and
      // return 0 without executing IDIV (avoids INT_MIN/-1 overflow trap).
      let rd = wreg_num(inst.defs[0])
      let lhs = reg_num(inst.uses[0])
      let rhs = reg_num(inst.uses[1])
      let scratch = isa.scratch_reg_1_index()

      // rdx is the architectural remainder output.
      if rd != 2 {
        abort("x86_64 SRem: expected dst in rdx")
      }

      // if rhs == -1: rdx = 0; goto done
      let do_idiv = self.new_internal_label()
      let done = self.new_internal_label()
      if is_64 {
        self.x86_emit_cmp_r_imm32(rhs, -1)
      } else {
        self.x86_emit_cmp_r32_imm32(rhs, -1)
      }
      self.x86_emit_jcc_rel32(@instr.Cond::Ne, do_idiv)
      if is_64 {
        self.x86_emit_xor_rr(2, 2)
      } else {
        self.x86_emit_xor_rr32(2, 2)
      }
      self.x86_emit_jmp_rel32(done)
      self.define_label(do_idiv)

      // Preserve divisor if it conflicts with rax/rdx.
      let mut divisor = rhs
      if rhs == 0 || rhs == 2 {
        self.x86_emit_mov_rr(scratch, rhs)
        divisor = scratch
      }
      if lhs != 0 {
        self.x86_emit_mov_rr(0, lhs)
      }
      if is_64 {
        self.x86_emit_cqo()
        self.x86_emit_idiv_r64(divisor)
      } else {
        self.x86_emit_cdq()
        self.x86_emit_idiv_r32(divisor)
      }
      // Remainder is in rdx already.
      self.define_label(done)
    }
    @instr.URem(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let lhs = reg_num(inst.uses[0])
      let rhs = reg_num(inst.uses[1])
      let scratch = isa.scratch_reg_1_index()
      if rd != 2 {
        abort("x86_64 URem: expected dst in rdx")
      }

      // Preserve divisor if it conflicts with rax/rdx.
      let mut divisor = rhs
      if rhs == 0 || rhs == 2 {
        self.x86_emit_mov_rr(scratch, rhs)
        divisor = scratch
      }
      if lhs != 0 {
        self.x86_emit_mov_rr(0, lhs)
      }
      if is_64 {
        self.x86_emit_xor_rr(2, 2)
        self.x86_emit_div_r64(divisor)
      } else {
        self.x86_emit_xor_rr32(2, 2)
        self.x86_emit_div_r32(divisor)
      }
      // Remainder is in rdx already.
    }
    @instr.LoadMemBase(memidx) => {
      // Load linear memory base pointer from VMContext.
      // Uses: [vmctx], Defs: [result]
      let dst = wreg_num(inst.defs[0])
      let vmctx_reg = reg_num(inst.uses[0])
      if memidx == 0 && stack_frame.cache_mem0_desc {
        // Fast path: memory0 descriptor pointer is cached in Mem0Desc role.
        self.x86_emit_mov_r64_m64(dst, mem0_desc_index(), 0)
      } else if memidx == 0 {
        self.x86_emit_mov_r64_m64(dst, vmctx_reg, @abi.VMCTX_MEMORY0_OFFSET)
        self.x86_emit_mov_r64_m64(dst, dst, 0)
      } else {
        self.x86_emit_mov_r64_m64(dst, vmctx_reg, @abi.VMCTX_MEMORIES_OFFSET)
        self.x86_emit_mov_r64_m64(dst, dst, memidx * 8)
        self.x86_emit_mov_r64_m64(dst, dst, 0)
      }
    }
    @instr.Load(ty, offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if stack_frame.cache_func_table &&
        ty is @instr.MemType::I64 &&
        rn == vmctx_index() &&
        offset == @abi.VMCTX_FUNC_TABLE_OFFSET {
        let ft = func_table_index()
        if rt != ft {
          self.x86_emit_mov_rr(rt, ft)
        }
        return
      }
      match ty {
        @instr.MemType::I32 => self.x86_emit_mov_r32_m32(rt, rn, offset)
        @instr.MemType::I64 => self.x86_emit_mov_r64_m64(rt, rn, offset)
        @instr.MemType::F32 => self.x86_emit_movss_xmm_m32(rt, rn, offset)
        @instr.MemType::F64 => self.x86_emit_movsd_xmm_m64(rt, rn, offset)
        @instr.MemType::V128 => self.x86_emit_movdqu_xmm_m128(rt, rn, offset)
      }
    }
    @instr.Store(ty, offset) => {
      let rn = reg_num(inst.uses[0])
      let rt = reg_num(inst.uses[1])
      match ty {
        @instr.MemType::I32 => self.x86_emit_mov_m32_r32(rn, offset, rt)
        @instr.MemType::I64 => self.x86_emit_mov_m64_r64(rn, offset, rt)
        @instr.MemType::F32 => self.x86_emit_movss_m32_xmm(rn, offset, rt)
        @instr.MemType::F64 => self.x86_emit_movsd_m64_xmm(rn, offset, rt)
        @instr.MemType::V128 => self.x86_emit_movdqu_m128_xmm(rn, offset, rt)
      }
    }
    @instr.LoadPtr(ty, offset) => {
      // Raw pointer load (no bounds checking).
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match ty {
        @instr.MemType::I32 => self.x86_emit_mov_r32_m32(rt, rn, offset)
        @instr.MemType::I64 => self.x86_emit_mov_r64_m64(rt, rn, offset)
        @instr.MemType::F32 => self.x86_emit_movss_xmm_m32(rt, rn, offset)
        @instr.MemType::F64 => self.x86_emit_movsd_xmm_m64(rt, rn, offset)
        @instr.MemType::V128 => self.x86_emit_movdqu_xmm_m128(rt, rn, offset)
      }
    }
    @instr.StorePtr(ty, offset) => {
      // Raw pointer store (no bounds checking).
      let rn = reg_num(inst.uses[0])
      let rt = reg_num(inst.uses[1])
      match ty {
        @instr.MemType::I32 => self.x86_emit_mov_m32_r32(rn, offset, rt)
        @instr.MemType::I64 => self.x86_emit_mov_m64_r64(rn, offset, rt)
        @instr.MemType::F32 => self.x86_emit_movss_m32_xmm(rn, offset, rt)
        @instr.MemType::F64 => self.x86_emit_movsd_m64_xmm(rn, offset, rt)
        @instr.MemType::V128 => self.x86_emit_movdqu_m128_xmm(rn, offset, rt)
      }
    }
    @instr.LoadPtrNarrow(bits, signed, offset) => {
      // Raw pointer narrow load (no bounds checking).
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match (bits, signed) {
        (8, true) => self.x86_emit_movsx_r64_m8(rt, rn, offset)
        (8, false) => self.x86_emit_movzx_r32_m8(rt, rn, offset)
        (16, true) => self.x86_emit_movsx_r64_m16(rt, rn, offset)
        (16, false) => self.x86_emit_movzx_r32_m16(rt, rn, offset)
        (32, true) => self.x86_emit_movsxd_r64_m32(rt, rn, offset)
        (32, false) => self.x86_emit_mov_r32_m32(rt, rn, offset)
        _ => abort("x86_64 LoadPtrNarrow: unsupported bits \{bits}")
      }
    }
    @instr.StorePtrNarrow(bits, offset) => {
      // Raw pointer narrow store (no bounds checking).
      let rn = reg_num(inst.uses[0])
      let rt = reg_num(inst.uses[1])
      match bits {
        8 => self.x86_emit_mov_m8_r8(rn, offset, rt)
        16 => self.x86_emit_mov_m16_r16(rn, offset, rt)
        32 => self.x86_emit_mov_m32_r32(rn, offset, rt)
        _ => abort("x86_64 StorePtrNarrow: unsupported bits \{bits}")
      }
    }
    @instr.Load8S(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.x86_emit_movsx_r64_m8(rt, rn, offset)
    }
    @instr.Load8U(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.x86_emit_movzx_r32_m8(rt, rn, offset)
    }
    @instr.Load16S(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.x86_emit_movsx_r64_m16(rt, rn, offset)
    }
    @instr.Load16U(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.x86_emit_movzx_r32_m16(rt, rn, offset)
    }
    @instr.Load32S(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.x86_emit_movsxd_r64_m32(rt, rn, offset)
    }
    @instr.Load32U(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.x86_emit_mov_r32_m32(rt, rn, offset)
    }
    @instr.LoadFuncAddr(func_idx) => {
      // Load function pointer from vmctx->func_table[func_idx].
      let rd = wreg_num(inst.defs[0])
      let vmctx = vmctx_index()
      let table = isa.scratch_reg_1_index()
      self.x86_emit_mov_r64_m64(table, vmctx, @abi.VMCTX_FUNC_TABLE_OFFSET)
      self.x86_emit_mov_r64_m64(rd, table, func_idx * 8)
    }
    @instr.CallDirect(func_idx, _num_args, _num_results, _call_conv) => {
      // Call via vmctx->func_table[func_idx] to avoid rel32 patching.
      let vmctx = vmctx_index()
      let table = isa.scratch_reg_1_index()
      let callee = isa.scratch_reg_2_index()
      self.x86_emit_mov_r64_m64(table, vmctx, @abi.VMCTX_FUNC_TABLE_OFFSET)
      self.x86_emit_mov_r64_m64(callee, table, func_idx * 8)
      self.x86_emit_call_r64(callee)
    }
    @instr.CallPtr(_, _, _call_conv) => {
      // Standard call: arguments already placed by lowering.
      let target = match inst.use_constraints[0] {
        @abi.FixedReg(preg) => preg.index
        _ => reg_num(inst.uses[0])
      }
      self.x86_emit_call_r64(target)
    }
    @instr.AdjustSP(delta) =>
      if delta > 0 {
        self.x86_emit_add_rsp_imm32(delta)
      } else if delta < 0 {
        self.x86_emit_sub_rsp_imm32(-delta)
      }
    @instr.StoreToStack(offset) => {
      // Store to pre-allocated outgoing args area at [rsp + outgoing_args_offset + offset].
      let actual_offset = stack_frame.outgoing_args_offset + offset
      let src = reg_num(inst.uses[0])
      let src_class = match inst.uses[0] {
        @abi.Physical(preg) => preg.class
        @abi.Virtual(vreg) => vreg.class
      }
      match src_class {
        @abi.Int => self.x86_emit_mov_m64_r64(4, actual_offset, src)
        @abi.Float32 | @abi.Float64 =>
          self.x86_emit_movsd_m64_xmm(4, actual_offset, src)
        @abi.Vector => self.x86_emit_movdqu_m128_xmm(4, actual_offset, src)
      }
    }
    @instr.LoadSP => {
      let rd = wreg_num(inst.defs[0])
      self.x86_emit_mov_rr(rd, 4)
    }
    @instr.StackLoad(offset) => {
      let rd = wreg_num(inst.defs[0])
      let def_class = match inst.defs[0].reg {
        @abi.Physical(preg) => preg.class
        @abi.Virtual(vreg) => vreg.class
      }
      let disp = spill_base_offset + offset
      match def_class {
        @abi.Int => self.x86_emit_mov_r64_m64(rd, 4, disp)
        @abi.Float32 | @abi.Float64 => self.x86_emit_movsd_xmm_m64(rd, 4, disp)
        @abi.Vector => self.x86_emit_movdqu_xmm_m128(rd, 4, disp)
      }
    }
    @instr.StackStore(offset) => {
      let rt = reg_num(inst.uses[0])
      let use_class = match inst.uses[0] {
        @abi.Physical(preg) => preg.class
        @abi.Virtual(vreg) => vreg.class
      }
      let disp = spill_base_offset + offset
      match use_class {
        @abi.Int => self.x86_emit_mov_m64_r64(4, disp, rt)
        @abi.Float32 | @abi.Float64 => self.x86_emit_movsd_m64_xmm(4, disp, rt)
        @abi.Vector => self.x86_emit_movdqu_m128_xmm(4, disp, rt)
      }
    }
    @instr.LoadStackParam(offset, class) => {
      // Load from [entry_sp + offset] where entry_sp = rsp + total_size.
      let rd = wreg_num(inst.defs[0])
      let disp = frame_size + offset
      match class {
        @abi.Int => self.x86_emit_mov_r64_m64(rd, 4, disp)
        @abi.Float32 | @abi.Float64 => self.x86_emit_movsd_xmm_m64(rd, 4, disp)
        @abi.Vector => self.x86_emit_movdqu_xmm_m128(rd, 4, disp)
      }
    }
    _ => abort("x86_64 opcode not implemented: \{inst.opcode}")
  }
}
