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
      // Match Cranelift x64 scalar fcmp lowering (see wasmtime cranelift x64 inst.isle `emit_fcmp`):
      // - UCOMIS* sets ZF/CF/PF; unordered => PF=1.
      // - Eq: NP && Z
      // - Ne: P || NZ
      // - Lt/Le use swapped operands + (NBE/NB), avoiding explicit orderedness checks.
      let lhs = reg_num(inst.uses[0])
      let rhs = reg_num(inst.uses[1])
      let rd = wreg_num(inst.defs[0])
      let class = reg_class_of(inst.uses[0])
      let is_f32 = class == @abi.Float32
      if class != @abi.Float32 && class != @abi.Float64 {
        abort("x86_64 FCmp: expected scalar float register class")
      }
      fn emit_ucomis(
        self : MachineCode,
        is_f32 : Bool,
        a : Int,
        b : Int,
      ) -> Unit {
        if is_f32 {
          self.x86_emit_ucomiss_xmm_xmm(a, b)
        } else {
          self.x86_emit_ucomisd_xmm_xmm(a, b)
        }
      }

      // Pick a scratch GPR distinct from rd (SETcc writes into low 8-bit).
      let mut scratch = isa.scratch_reg_1_index()
      if scratch == rd {
        scratch = isa.scratch_reg_2_index()
      }
      match kind {
        @instr.FCmpKind::Eq => {
          emit_ucomis(self, is_f32, lhs, rhs)
          self.x86_emit_setcc_r8(@instr.Cond::Eq, rd) // Z
          self.x86_emit_setcc_r8(@instr.Cond::Pc, scratch) // NP (parity clear)
          self.x86_emit_movzx_r32_r8(rd, rd)
          self.x86_emit_movzx_r32_r8(scratch, scratch)
          self.x86_emit_and_rr32(rd, scratch)
        }
        @instr.FCmpKind::Ne => {
          emit_ucomis(self, is_f32, lhs, rhs)
          self.x86_emit_setcc_r8(@instr.Cond::Ne, rd) // NZ
          self.x86_emit_setcc_r8(@instr.Cond::Ps, scratch) // P (parity set)
          self.x86_emit_movzx_r32_r8(rd, rd)
          self.x86_emit_movzx_r32_r8(scratch, scratch)
          self.x86_emit_or_rr32(rd, scratch)
        }
        @instr.FCmpKind::Gt => {
          emit_ucomis(self, is_f32, lhs, rhs)
          self.x86_emit_setcc_r8(@instr.Cond::Hi, rd) // NBE (ordered >)
          self.x86_emit_movzx_r32_r8(rd, rd)
        }
        @instr.FCmpKind::Ge => {
          emit_ucomis(self, is_f32, lhs, rhs)
          self.x86_emit_setcc_r8(@instr.Cond::Hs, rd) // NB (ordered >=)
          self.x86_emit_movzx_r32_r8(rd, rd)
        }
        @instr.FCmpKind::Lt => {
          emit_ucomis(self, is_f32, rhs, lhs)
          self.x86_emit_setcc_r8(@instr.Cond::Hi, rd) // NBE (ordered <)
          self.x86_emit_movzx_r32_r8(rd, rd)
        }
        @instr.FCmpKind::Le => {
          emit_ucomis(self, is_f32, rhs, lhs)
          self.x86_emit_setcc_r8(@instr.Cond::Hs, rd) // NB (ordered <=)
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
    @instr.TrapIf(cond, trap_code) => {
      // Trap if condition is true (based on the most recent flags).
      if cond is @instr.Cond::Al {
        self.x86_emit_trap_imm16(trap_code)
        return
      }
      let done = self.new_internal_label()
      self.x86_emit_jcc_rel32(cond.invert(), done)
      self.x86_emit_trap_imm16(trap_code)
      self.define_label(done)
    }
    @instr.Extend(kind) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match kind {
        @instr.ExtendKind::Signed8To32 => self.x86_emit_movsx_r32_r8(rd, rn)
        @instr.ExtendKind::Signed8To64 => self.x86_emit_movsx_r64_r8(rd, rn)
        @instr.ExtendKind::Signed16To32 => self.x86_emit_movsx_r32_r16(rd, rn)
        @instr.ExtendKind::Signed16To64 => self.x86_emit_movsx_r64_r16(rd, rn)
        @instr.ExtendKind::Signed32To64 => self.x86_emit_movsxd_r64_r32(rd, rn)
        @instr.ExtendKind::Unsigned8To32 | @instr.ExtendKind::Unsigned8To64 =>
          self.x86_emit_movzx_r32_r8(rd, rn)
        @instr.ExtendKind::Unsigned16To32 | @instr.ExtendKind::Unsigned16To64 =>
          self.x86_emit_movzx_r32_r16(rd, rn)
        @instr.ExtendKind::Unsigned32To64 => self.x86_emit_mov_rr32(rd, rn)
      }
    }
    @instr.Truncate => {
      // i64 -> i32 truncation: write through a 32-bit move to clear upper bits.
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if rd != rn {
        self.x86_emit_mov_rr32(rd, rn)
      }
    }
    @instr.FPromote => {
      // f32 -> f64
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.x86_emit_cvtss2sd_xmm_xmm(rd, rn)
    }
    @instr.FDemote => {
      // f64 -> f32
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.x86_emit_cvtsd2ss_xmm_xmm(rd, rn)
    }
    @instr.IntToFloat(kind) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match kind {
        @instr.IntToFloatKind::I32SToF32 =>
          self.x86_emit_cvtsi2ss_xmm_r32(rd, rn)
        @instr.IntToFloatKind::I32SToF64 =>
          self.x86_emit_cvtsi2sd_xmm_r32(rd, rn)
        @instr.IntToFloatKind::I64SToF32 =>
          self.x86_emit_cvtsi2ss_xmm_r64(rd, rn)
        @instr.IntToFloatKind::I64SToF64 =>
          self.x86_emit_cvtsi2sd_xmm_r64(rd, rn)
        // u32 fits in signed i64 when zero-extended; use the r64 form.
        @instr.IntToFloatKind::I32UToF32 =>
          self.x86_emit_cvtsi2ss_xmm_r64(rd, rn)
        @instr.IntToFloatKind::I32UToF64 =>
          self.x86_emit_cvtsi2sd_xmm_r64(rd, rn)
        @instr.IntToFloatKind::I64UToF32 | @instr.IntToFloatKind::I64UToF64 => {
          let scratch1 = isa.scratch_reg_1_index()
          let scratch2 = isa.scratch_reg_2_index()
          // Match Cranelift x64 `CvtUint64ToFloatSeq`:
          // - if src is non-negative, signed conversion is fine
          // - else convert (src>>1 | src&1) as signed and double the float result
          let nonneg = self.new_internal_label()
          let done = self.new_internal_label()
          self.x86_emit_test_rr(rn, rn)
          self.x86_emit_jcc_rel32(@instr.Cond::Pl, nonneg) // JNS

          // scratch1 = src >> 1
          self.x86_emit_mov_rr(scratch1, rn)
          self.x86_emit_shr_r_imm8(scratch1, 1)

          // scratch2 = src & 1
          self.x86_emit_mov_rr(scratch2, rn)
          self.x86_emit_and_r_imm8_sxb64(scratch2, 1)

          // scratch2 = (src>>1) | (src&1)
          self.x86_emit_or_rr(scratch2, scratch1)

          // dst = cvt(scratch2); dst += dst
          if kind is @instr.IntToFloatKind::I64UToF32 {
            self.x86_emit_cvtsi2ss_xmm_r64(rd, scratch2)
            self.x86_emit_addss_xmm_xmm(rd, rd)
          } else {
            self.x86_emit_cvtsi2sd_xmm_r64(rd, scratch2)
            self.x86_emit_addsd_xmm_xmm(rd, rd)
          }
          self.x86_emit_jmp_rel32(done)
          self.define_label(nonneg)
          if kind is @instr.IntToFloatKind::I64UToF32 {
            self.x86_emit_cvtsi2ss_xmm_r64(rd, rn)
          } else {
            self.x86_emit_cvtsi2sd_xmm_r64(rd, rn)
          }
          self.define_label(done)
        }
      }
    }
    @instr.Bitcast => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let dst_class = reg_class_of_w(inst.defs[0])
      let src_class = reg_class_of(inst.uses[0])
      match (dst_class, src_class) {
        (@abi.Int, @abi.Float32) => self.x86_emit_movd_r32_xmm(rd, rn)
        (@abi.Int, @abi.Float64) => self.x86_emit_movq_r64_xmm(rd, rn)
        (@abi.Float32, @abi.Int) => self.x86_emit_movd_xmm_r32(rd, rn)
        (@abi.Float64, @abi.Int) => self.x86_emit_movq_xmm_r64(rd, rn)
        _ => abort("x86_64 Bitcast: unsupported reg class combination")
      }
    }
    @instr.FcvtToInt(is_f32, is_i64, is_signed) => {
      // Match Cranelift x64 conversion sequences:
      // - signed: `CvtFloatToSintSeq` saturating behavior
      // - unsigned: `CvtFloatToUintSeq` saturating behavior
      let src_xmm = reg_num(inst.uses[0])
      let dst = wreg_num(inst.defs[0])
      let tmp_gpr = isa.scratch_reg_1_index()
      let tmp_xmm = 15 // reserved via MachineEnvData.scratch_float
      let tmp_xmm2 = 14 // reserved via MachineEnvData.scratch_float
      fn emit_ucomis(
        self : MachineCode,
        is_f32 : Bool,
        a : Int,
        b : Int,
      ) -> Unit {
        if is_f32 {
          self.x86_emit_ucomiss_xmm_xmm(a, b)
        } else {
          self.x86_emit_ucomisd_xmm_xmm(a, b)
        }
      }

      fn emit_cvtt(
        self : MachineCode,
        is_f32 : Bool,
        is_i64 : Bool,
        dst : Int,
        src : Int,
      ) -> Unit {
        match (is_f32, is_i64) {
          (true, false) => self.x86_emit_cvttss2si_r32_xmm(dst, src)
          (true, true) => self.x86_emit_cvttss2si_r64_xmm(dst, src)
          (false, false) => self.x86_emit_cvttsd2si_r32_xmm(dst, src)
          (false, true) => self.x86_emit_cvttsd2si_r64_xmm(dst, src)
        }
      }

      fn emit_cmp_imm(
        self : MachineCode,
        is_i64 : Bool,
        reg : Int,
        imm : Int,
      ) -> Unit {
        if is_i64 {
          self.x86_emit_cmp_r_imm32(reg, imm)
        } else {
          self.x86_emit_cmp_r32_imm32(reg, imm)
        }
      }

      fn emit_xor_self(self : MachineCode, is_i64 : Bool, reg : Int) -> Unit {
        if is_i64 {
          self.x86_emit_xor_rr(reg, reg)
        } else {
          self.x86_emit_xor_rr32(reg, reg)
        }
      }

      let done = self.new_internal_label()
      if is_signed {
        let not_nan = self.new_internal_label()
        emit_cvtt(self, is_f32, is_i64, dst, src_xmm)
        // Detect INT_MIN overflow/invalid sentinel via `cmp dst, 1; jno done`.
        emit_cmp_imm(self, is_i64, dst, 1)
        self.x86_emit_jcc_rel32(@instr.Cond::Vc, done) // JNO

        // NaN => 0
        emit_ucomis(self, is_f32, src_xmm, src_xmm)
        self.x86_emit_jcc_rel32(@instr.Cond::Pc, not_nan) // JNP
        emit_xor_self(self, is_i64, dst)
        self.x86_emit_jmp_rel32(done)
        self.define_label(not_nan)

        // If src <= 0, keep INT_MIN (already in dst); else saturate to INT_MAX.
        self.x86_emit_xorpd_xmm_xmm(tmp_xmm, tmp_xmm)
        emit_ucomis(self, is_f32, tmp_xmm, src_xmm)
        self.x86_emit_jcc_rel32(@instr.Cond::Hs, done) // JAE
        let int_max = if is_i64 { 0x7fffffffffffffffL } else { 0x7fffffffL }
        self.x86_emit_mov_imm64(dst, int_max)
        self.define_label(done)
      } else {
        // Unsigned saturating conversion.
        let handle_large = self.new_internal_label()
        let not_nan = self.new_internal_label()
        let next_is_large = self.new_internal_label()

        // Load 2**(width-1) as float into tmp_xmm.
        let threshold_bits : Int64 = match (is_f32, is_i64) {
          (true, false) => 0x4F000000L // f32(2^31)
          (false, false) => 0x41E0000000000000L // f64(2^31)
          (true, true) => 0x5F000000L // f32(2^63)
          (false, true) => 0x43E0000000000000L // f64(2^63)
        }
        if is_f32 {
          self.x86_emit_mov_imm64(tmp_gpr, threshold_bits)
          self.x86_emit_movd_xmm_r32(tmp_xmm, tmp_gpr)
        } else {
          self.x86_emit_mov_imm64(tmp_gpr, threshold_bits)
          self.x86_emit_movq_xmm_r64(tmp_xmm, tmp_gpr)
        }

        // Compare src with threshold; if src >= threshold, go to large path.
        emit_ucomis(self, is_f32, src_xmm, tmp_xmm)
        self.x86_emit_jcc_rel32(@instr.Cond::Hs, handle_large) // JAE/JNB

        // NaN => 0
        self.x86_emit_jcc_rel32(@instr.Cond::Pc, not_nan) // JNP
        emit_xor_self(self, is_i64, dst)
        self.x86_emit_jmp_rel32(done)
        self.define_label(not_nan)

        // Small path: cvtt + if result >= 0 then done else 0.
        emit_cvtt(self, is_f32, is_i64, dst, src_xmm)
        emit_cmp_imm(self, is_i64, dst, 0)
        self.x86_emit_jcc_rel32(@instr.Cond::Ge, done) // JGE
        emit_xor_self(self, is_i64, dst)
        self.x86_emit_jmp_rel32(done)

        // Large path: subtract threshold, convert, then add threshold back.
        self.define_label(handle_large)
        self.x86_emit_movaps_xmm_xmm(tmp_xmm2, src_xmm)
        if is_f32 {
          self.x86_emit_subss_xmm_xmm(tmp_xmm2, tmp_xmm)
        } else {
          self.x86_emit_subsd_xmm_xmm(tmp_xmm2, tmp_xmm)
        }
        emit_cvtt(self, is_f32, is_i64, dst, tmp_xmm2)
        emit_cmp_imm(self, is_i64, dst, 0)
        self.x86_emit_jcc_rel32(@instr.Cond::Ge, next_is_large)
        // Too large => UINT_MAX.
        let uint_max = if is_i64 { -1L } else { 0xFFFFFFFFL }
        self.x86_emit_mov_imm64(dst, uint_max)
        self.x86_emit_jmp_rel32(done)
        self.define_label(next_is_large)
        if is_i64 {
          self.x86_emit_mov_imm64(tmp_gpr, 1L << 63)
          self.x86_emit_add_rr(dst, tmp_gpr)
        } else {
          self.x86_emit_mov_imm64(tmp_gpr, 1L << 31)
          self.x86_emit_add_rr32(dst, tmp_gpr)
        }
        self.define_label(done)
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
    @instr.LoadConstV128(bytes) => {
      // Materialize a 128-bit constant.
      //
      // Cranelift uses constant pools / mem loads; for now we use a minimal
      // SSE4.1 sequence with `PINSRQ` to avoid a constant pool.
      let rd = wreg_num(inst.defs[0])
      let low = bytes_to_int64_le(bytes, 0)
      let high = bytes_to_int64_le(bytes, 8)

      // rd = 0
      self.x86_emit_xorpd_xmm_xmm(rd, rd)
      let scratch = isa.scratch_reg_1_index()
      if low != 0L {
        self.x86_emit_mov_imm64(scratch, low)
        self.x86_emit_pinsrq_xmm_r64_imm8(rd, scratch, 0)
      }
      if high != 0L {
        self.x86_emit_mov_imm64(scratch, high)
        self.x86_emit_pinsrq_xmm_r64_imm8(rd, scratch, 1)
      }
    }
    @instr.SIMDAnd => {
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      if rd != a {
        self.x86_emit_movaps_xmm_xmm(rd, a)
      }
      self.x86_emit_pand_xmm_xmm(rd, b)
    }
    @instr.SIMDOr => {
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      if rd != a {
        self.x86_emit_movaps_xmm_xmm(rd, a)
      }
      self.x86_emit_por_xmm_xmm(rd, b)
    }
    @instr.SIMDXor => {
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      if rd != a {
        self.x86_emit_movaps_xmm_xmm(rd, a)
      }
      self.x86_emit_pxor_xmm_xmm(rd, b)
    }
    @instr.SIMDBic => {
      // a & ~b == (~b) & a, matching the x86 `PANDN` operand order.
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      if rd != b {
        self.x86_emit_movaps_xmm_xmm(rd, b)
      }
      self.x86_emit_pandn_xmm_xmm(rd, a)
    }
    @instr.SIMDNot => {
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      let tmp = 15 // reserved via MachineEnvData.scratch_float
      if rd != src {
        self.x86_emit_movaps_xmm_xmm(rd, src)
      }
      self.x86_emit_pcmpeqd_xmm_xmm(tmp, tmp) // tmp = all ones
      self.x86_emit_pxor_xmm_xmm(rd, tmp)
    }
    @instr.SIMDAdd(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      if rd != a {
        self.x86_emit_movaps_xmm_xmm(rd, a)
      }
      self.x86_emit_padd_xmm_xmm(lane_size, rd, b)
    }
    @instr.SIMDSub(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      if rd != a {
        self.x86_emit_movaps_xmm_xmm(rd, a)
      }
      self.x86_emit_psub_xmm_xmm(lane_size, rd, b)
    }
    @instr.SIMDMul(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      if rd != a {
        self.x86_emit_movaps_xmm_xmm(rd, a)
      }
      match lane_size {
        @instr.H16 => self.x86_emit_pmullw_xmm_xmm(rd, b)
        @instr.S32 => self.x86_emit_pmulld_xmm_xmm(rd, b) // SSE4.1
        _ => abort("x86_64 SIMDMul: unsupported lane size \{lane_size}")
      }
    }
    @instr.SIMDCmp(lane_size, kind) => {
      // Integer SIMD comparisons return all-ones/all-zeros lanes.
      let rd = wreg_num(inst.defs[0])
      let x = reg_num(inst.uses[0])
      let y = reg_num(inst.uses[1])
      let t0 = 14 // reserved via MachineEnvData.scratch_float
      let t1 = 15 // reserved via MachineEnvData.scratch_float
      fn emit_broadcast_dword_pattern(
        self : MachineCode,
        dst_xmm : Int,
        dword : Int,
      ) -> Unit {
        let scratch = isa.scratch_reg_1_index()
        self.x86_emit_mov_imm64(scratch, dword.to_int64())
        self.x86_emit_movd_xmm_r32(dst_xmm, scratch)
        self.x86_emit_pshufd_xmm_xmm_imm8(dst_xmm, dst_xmm, 0)
      }

      match kind {
        @instr.SIMDCmpKind::Eq =>
          if lane_size is @instr.D64 {
            // Match Cranelift x64: emulate pcmpeqq without SSE4.1.
            //
            // cmp32 = pcmpeqd(x, y)
            // cmp32_swapped = pshufd(cmp32, 0b10_11_00_01)
            // result = pand(cmp32, cmp32_swapped)
            self.x86_emit_movaps_xmm_xmm(rd, x)
            self.x86_emit_pcmpeqd_xmm_xmm(rd, y)
            self.x86_emit_pshufd_xmm_xmm_imm8(t0, rd, 0xB1)
            self.x86_emit_pand_xmm_xmm(rd, t0)
          } else {
            self.x86_emit_movaps_xmm_xmm(rd, x)
            self.x86_emit_pcmpeq_xmm_xmm(lane_size, rd, y)
          }
        @instr.SIMDCmpKind::GtS =>
          if lane_size is @instr.D64 {
            // Match Cranelift x64: emulate i64x2 gt via 32-bit compares.
            //
            // See: cranelift/codegen/src/isa/x64/inst.isle (x64_pcmpgt $I64X2)
            //
            // mask = [0x80000000, 0x0, 0x80000000, 0x0] in u32 lanes.
            // x_masked = x ^ mask
            // y_masked = y ^ mask
            // cmp32 = pcmpgtd(x_masked, y_masked)
            // low_halves_gt = pshufd(cmp32, 0xA0)
            // high_halves_gt = pshufd(cmp32, 0xF5)
            // cmp_eq = pcmpeqd(x, y)
            // high_halves_eq = pshufd(cmp_eq, 0xF5)
            // result = por(pand(low_halves_gt, high_halves_eq), high_halves_gt)
            emit_broadcast_dword_pattern(self, rd, 0x80000000)
            self.x86_emit_movaps_xmm_xmm(t0, x)
            self.x86_emit_pxor_xmm_xmm(t0, rd)
            self.x86_emit_movaps_xmm_xmm(t1, y)
            self.x86_emit_pxor_xmm_xmm(t1, rd)
            self.x86_emit_pcmpgt_xmm_xmm(@instr.S32, t0, t1)
            self.x86_emit_pshufd_xmm_xmm_imm8(t1, t0, 0xA0) // low_halves_gt
            self.x86_emit_pshufd_xmm_xmm_imm8(rd, t0, 0xF5) // high_halves_gt
            self.x86_emit_movaps_xmm_xmm(t0, x)
            self.x86_emit_pcmpeqd_xmm_xmm(t0, y)
            self.x86_emit_pshufd_xmm_xmm_imm8(t0, t0, 0xF5) // high_halves_eq
            self.x86_emit_pand_xmm_xmm(t1, t0)
            self.x86_emit_por_xmm_xmm(t1, rd)
            self.x86_emit_movaps_xmm_xmm(rd, t1)
          } else {
            self.x86_emit_movaps_xmm_xmm(rd, x)
            self.x86_emit_pcmpgt_xmm_xmm(lane_size, rd, y)
          }
        @instr.SIMDCmpKind::GeS =>
          // a >= b  <=>  !(b > a)
          if lane_size is @instr.D64 {
            // Use the i64x2 gt sequence on swapped operands, then invert.
            // tmp = b > a
            let tmp = t1
            let ones = t0
            // Compute tmp into `tmp` by temporarily using rd.
            // Reuse the GtS sequence by swapping x/y.
            emit_broadcast_dword_pattern(self, rd, 0x80000000)
            self.x86_emit_movaps_xmm_xmm(ones, y)
            self.x86_emit_pxor_xmm_xmm(ones, rd)
            self.x86_emit_movaps_xmm_xmm(tmp, x)
            self.x86_emit_pxor_xmm_xmm(tmp, rd)
            self.x86_emit_pcmpgt_xmm_xmm(@instr.S32, ones, tmp) // ones = cmp32
            self.x86_emit_pshufd_xmm_xmm_imm8(tmp, ones, 0xA0) // low_halves_gt
            self.x86_emit_pshufd_xmm_xmm_imm8(rd, ones, 0xF5) // high_halves_gt
            self.x86_emit_movaps_xmm_xmm(ones, y)
            self.x86_emit_pcmpeqd_xmm_xmm(ones, x)
            self.x86_emit_pshufd_xmm_xmm_imm8(ones, ones, 0xF5) // high_halves_eq
            self.x86_emit_pand_xmm_xmm(tmp, ones)
            self.x86_emit_por_xmm_xmm(tmp, rd)
            // Invert tmp.
            self.x86_emit_pcmpeqd_xmm_xmm(ones, ones)
            self.x86_emit_pxor_xmm_xmm(tmp, ones)
            self.x86_emit_movaps_xmm_xmm(rd, tmp)
          } else {
            self.x86_emit_movaps_xmm_xmm(rd, y)
            self.x86_emit_pcmpgt_xmm_xmm(lane_size, rd, x)
            self.x86_emit_pcmpeqd_xmm_xmm(t0, t0)
            self.x86_emit_pxor_xmm_xmm(rd, t0)
          }
        @instr.SIMDCmpKind::GtU => {
          if lane_size is @instr.D64 {
            abort(
              "x86_64 SIMDCmp.gt.u: i64x2 unsigned compare not supported by wasm SIMD",
            )
          }
          // Match Cranelift x64: flip sign bit and do signed compare.
          let pattern = match lane_size {
            @instr.B8 => 0x80808080
            @instr.H16 => 0x80008000
            @instr.S32 => 0x80000000
            @instr.D64 => 0
          }
          emit_broadcast_dword_pattern(self, rd, pattern)
          self.x86_emit_movaps_xmm_xmm(t0, x)
          self.x86_emit_pxor_xmm_xmm(t0, rd)
          self.x86_emit_movaps_xmm_xmm(t1, y)
          self.x86_emit_pxor_xmm_xmm(t1, rd)
          self.x86_emit_movaps_xmm_xmm(rd, t0)
          self.x86_emit_pcmpgt_xmm_xmm(lane_size, rd, t1)
        }
        @instr.SIMDCmpKind::GeU => {
          if lane_size is @instr.D64 {
            abort(
              "x86_64 SIMDCmp.ge.u: i64x2 unsigned compare not supported by wasm SIMD",
            )
          }
          // a >= b <=> !(b > a) after unsigned compare.
          let pattern = match lane_size {
            @instr.B8 => 0x80808080
            @instr.H16 => 0x80008000
            @instr.S32 => 0x80000000
            @instr.D64 => 0
          }
          emit_broadcast_dword_pattern(self, rd, pattern)
          self.x86_emit_movaps_xmm_xmm(t0, y)
          self.x86_emit_pxor_xmm_xmm(t0, rd)
          self.x86_emit_movaps_xmm_xmm(t1, x)
          self.x86_emit_pxor_xmm_xmm(t1, rd)
          self.x86_emit_movaps_xmm_xmm(rd, t0)
          self.x86_emit_pcmpgt_xmm_xmm(lane_size, rd, t1) // b > a
          self.x86_emit_pcmpeqd_xmm_xmm(t0, t0) // ones
          self.x86_emit_pxor_xmm_xmm(rd, t0) // invert
        }
      }
    }
    @instr.SIMDShuffle(lanes) => {
      // i8x16.shuffle: select lanes from two source vectors using constant indices.
      //
      // Match Cranelift x64 lowering strategy: build two SSSE3 `pshufb` masks and
      // combine with `por`.
      //
      // out = pshufb(a, mask_a) | pshufb(b, mask_b)
      // where each mask byte is either 0..15 (select) or 0x80 (zero).
      let rd = wreg_num(inst.defs[0])
      let tmp_a = wreg_num(inst.defs[1])
      let tmp_b = wreg_num(inst.defs[2])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let mask = 15 // reserved via MachineEnvData.scratch_float
      fn emit_const_v128(
        self : MachineCode,
        xmm : Int,
        low : Int64,
        high : Int64,
      ) -> Unit {
        self.x86_emit_xorpd_xmm_xmm(xmm, xmm)
        let scratch = isa.scratch_reg_1_index()
        if low != 0L {
          self.x86_emit_mov_imm64(scratch, low)
          self.x86_emit_pinsrq_xmm_r64_imm8(xmm, scratch, 0)
        }
        if high != 0L {
          self.x86_emit_mov_imm64(scratch, high)
          self.x86_emit_pinsrq_xmm_r64_imm8(xmm, scratch, 1)
        }
      }

      // tmp_a = a, tmp_b = b
      if tmp_a != a {
        self.x86_emit_movaps_xmm_xmm(tmp_a, a)
      }
      if tmp_b != b {
        self.x86_emit_movaps_xmm_xmm(tmp_b, b)
      }

      // Build two 16-byte masks as two i64 halves (little-endian).
      let mut low_a = 0L
      let mut high_a = 0L
      let mut low_b = 0L
      let mut high_b = 0L
      for i in 0..<8 {
        let lane0 = lanes[i]
        let b0_a = if lane0 < 16 { lane0 } else { 0x80 }
        let b0_b = if lane0 < 16 { 0x80 } else { lane0 - 16 }
        low_a = low_a | ((b0_a.to_int64() & 0xFFL) << (i * 8))
        low_b = low_b | ((b0_b.to_int64() & 0xFFL) << (i * 8))
        let lane1 = lanes[i + 8]
        let b1_a = if lane1 < 16 { lane1 } else { 0x80 }
        let b1_b = if lane1 < 16 { 0x80 } else { lane1 - 16 }
        high_a = high_a | ((b1_a.to_int64() & 0xFFL) << (i * 8))
        high_b = high_b | ((b1_b.to_int64() & 0xFFL) << (i * 8))
      }

      // Shuffle a then b with their respective masks.
      emit_const_v128(self, mask, low_a, high_a)
      self.x86_emit_pshufb_xmm_xmm(tmp_a, mask)
      emit_const_v128(self, mask, low_b, high_b)
      self.x86_emit_pshufb_xmm_xmm(tmp_b, mask)

      // rd = tmp_a | tmp_b
      if rd != tmp_a {
        self.x86_emit_movaps_xmm_xmm(rd, tmp_a)
      }
      self.x86_emit_por_xmm_xmm(rd, tmp_b)
    }
    @instr.SIMDSwizzle => {
      // i8x16.swizzle: select lanes from one vector using runtime indices.
      //
      // Match Cranelift x64 lowering: use SSSE3 `pshufb` with a saturating-add
      // tweak so indices >= 16 zero the output lanes.
      //
      // mask = indices; mask = paddusb(mask, splat(0x70)); pshufb(values, mask)
      let rd = wreg_num(inst.defs[0])
      let values = reg_num(inst.uses[0])
      let indices = reg_num(inst.uses[1])
      let mask = 15 // reserved via MachineEnvData.scratch_float
      let c70 = 14 // reserved via MachineEnvData.scratch_float
      fn emit_const_v128(self : MachineCode, xmm : Int, low : Int64) -> Unit {
        self.x86_emit_xorpd_xmm_xmm(xmm, xmm)
        if low != 0L {
          let scratch = isa.scratch_reg_1_index()
          self.x86_emit_mov_imm64(scratch, low)
          self.x86_emit_pinsrq_xmm_r64_imm8(xmm, scratch, 0)
          self.x86_emit_pinsrq_xmm_r64_imm8(xmm, scratch, 1)
        }
      }

      if rd != values {
        self.x86_emit_movaps_xmm_xmm(rd, values)
      }
      self.x86_emit_movaps_xmm_xmm(mask, indices)
      emit_const_v128(self, c70, 0x7070707070707070L)
      self.x86_emit_paddusb_xmm_xmm(mask, c70)
      self.x86_emit_pshufb_xmm_xmm(rd, mask)
    }
    @instr.SIMDBsl => {
      // v128.bitselect(a, b, c) = (a & c) | (b & ~c)
      //
      // Match Cranelift-style bitselect using boolean ops; handle common aliasing
      // cases with a reserved scratch vector register.
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let c = reg_num(inst.uses[2])
      let tmp = 15 // reserved via MachineEnvData.scratch_float

      // Preserve `b`/`c` if they alias `rd`, since the sequence needs them twice.
      let mut b_keep = b
      let mut c_keep = c
      if rd == b {
        self.x86_emit_movaps_xmm_xmm(tmp, b)
        b_keep = tmp
      }
      if rd == c {
        // If we already used `tmp` to save `b`, it still holds `b_keep`. Save
        // `c` into the other reserved scratch register.
        let tmp2 = 14
        self.x86_emit_movaps_xmm_xmm(tmp2, c)
        c_keep = tmp2
      }

      // rd = b ^ ((a ^ b) & c)
      if rd != a {
        self.x86_emit_movaps_xmm_xmm(rd, a)
      }
      self.x86_emit_pxor_xmm_xmm(rd, b_keep) // a ^ b
      self.x86_emit_pand_xmm_xmm(rd, c_keep) // (a ^ b) & c
      self.x86_emit_pxor_xmm_xmm(rd, b_keep) // b ^ ...
    }
    @instr.SIMDAnyTrue => {
      // v128.any_true: return 1 if any bit is set, 0 otherwise.
      //
      // Match Cranelift x64 lowering: compare against zero per byte then
      // extract the "all zero?" mask with PMOVMSKB.
      //
      // tmp = pcmpeqb(src, 0)
      // bits = pmovmskb(tmp)
      // rd = (bits != 0xFFFF)
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      let tmp = wreg_num(inst.defs[1])
      let zero = 15 // reserved via MachineEnvData.scratch_float
      let mut scratch = isa.scratch_reg_1_index()
      if scratch == rd {
        scratch = isa.scratch_reg_2_index()
      }
      self.x86_emit_movaps_xmm_xmm(tmp, src)
      self.x86_emit_pxor_xmm_xmm(zero, zero)
      self.x86_emit_pcmpeq_xmm_xmm(@instr.B8, tmp, zero)
      self.x86_emit_pmovmskb_r32_xmm(scratch, tmp)
      self.x86_emit_cmp_r32_imm32(scratch, 0xFFFF)
      self.x86_emit_setcc_r8(@instr.Cond::Ne, rd)
      self.x86_emit_movzx_r32_r8(rd, rd)
    }
    @instr.SIMDBitmask(lane_size) => {
      // Extract the MSB/sign bit of each lane into a scalar i32.
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      match lane_size {
        @instr.B8 => self.x86_emit_pmovmskb_r32_xmm(rd, src)
        @instr.H16 => {
          let tmp = 15 // reserved via MachineEnvData.scratch_float
          self.x86_emit_movaps_xmm_xmm(tmp, src)
          self.x86_emit_packsswb_xmm_xmm(tmp, tmp)
          self.x86_emit_pmovmskb_r32_xmm(rd, tmp)
          // packsswb(x, x) duplicates the 8-lane mask into both halves.
          self.x86_emit_shr_r32_imm8(rd, 8)
        }
        @instr.S32 => self.x86_emit_movmskps_r32_xmm(rd, src)
        @instr.D64 => self.x86_emit_movmskpd_r32_xmm(rd, src)
      }
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
