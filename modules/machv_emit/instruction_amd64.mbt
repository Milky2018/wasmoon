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
      Eq => Eq
      Ne => Ne
      Slt => Lt
      Sle => Le
      Sgt => Gt
      Sge => Ge
      Ult => Lo
      Ule => Ls
      Ugt => Hi
      Uge => Hs
    }
  }

  fn reg_class_of(reg : @abi.Reg) -> @abi.RegClass {
    match reg {
      Physical(preg) => preg.class
      Virtual(vreg) => vreg.class
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
      Int => self.x86_emit_mov_rr(dst, src)
      Float32 | Float64 | Vector => self.x86_emit_movaps_xmm_xmm(dst, src)
    }
  }

  ///|
  /// Prepare a two-operand SSE instruction destination.
  ///
  /// Many amd64 SIMD instructions are 2-operand (dst is overwritten). Our VCode
  /// IR does not enforce `dst == lhs`, so the emitter must handle aliasing
  /// where `dst` equals the rhs operand.
  ///
  /// Returns the register index to use as the rhs input (either `b` or `tmp`).
  fn prepare_xmm_two_operand(
    self : MachineCode,
    rd : Int,
    a : Int,
    b : Int,
    tmp : Int,
  ) -> Int {
    if rd == a {
      return b
    }
    if rd == b {
      self.x86_emit_movaps_xmm_xmm(tmp, b)
      self.x86_emit_movaps_xmm_xmm(rd, a)
      return tmp
    }
    self.x86_emit_movaps_xmm_xmm(rd, a)
    b
  }

  fn materialize_xmm_const(
    self : MachineCode,
    dst_xmm : Int,
    low : Int64,
    high : Int64,
    scratch_gpr : Int,
  ) -> Unit {
    let data = Bytes::makei(16, fn(i) {
      if i < 8 {
        ((low >> (i * 8)) & 0xFFL).to_byte()
      } else {
        ((high >> ((i - 8) * 8)) & 0xFFL).to_byte()
      }
    })
    let label = self.intern_amd64_const(data, 16)
    self.x86_emit_lea_r64_riprel32(scratch_gpr, label)
    self.x86_emit_movdqu_xmm_m128(dst_xmm, scratch_gpr, 0)
  }

  fn emit_add_imm_to_reg_in_chunks(
    self : MachineCode,
    reg : Int,
    imm : Int,
  ) -> Unit {
    if imm == 0 {
      return
    }
    let mut remaining = imm
    while remaining > 127 {
      self.x86_emit_add_r_imm8(reg, 127)
      remaining = remaining - 127
    }
    while remaining < -128 {
      self.x86_emit_add_r_imm8(reg, -128)
      remaining = remaining + 128
    }
    if remaining != 0 {
      self.x86_emit_add_r_imm8(reg, remaining)
    }
  }

  fn fits_i8(value : Int) -> Bool {
    value >= -128 && value <= 127
  }

  fn fits_i32(value : Int) -> Bool {
    value >= -2147483648 && value <= 2147483647
  }

  fn pick_scratch_gpr(
    isa : @isa.ISA,
    avoid0 : Int,
    avoid1 : Int,
    avoid2 : Int,
    avoid3 : Int,
  ) -> Int {
    let s1 = isa.scratch_reg_1_index()
    if s1 != avoid0 && s1 != avoid1 && s1 != avoid2 && s1 != avoid3 {
      return s1
    }
    let s2 = isa.scratch_reg_2_index()
    if s2 != avoid0 && s2 != avoid1 && s2 != avoid2 && s2 != avoid3 {
      return s2
    }
    abort(
      "x86_64 emit: no scratch register available (avoid=\{avoid0},\{avoid1},\{avoid2},\{avoid3})",
    )
  }

  ///|
  /// Fallback for integer indexed loads when both reserved scratch registers are
  /// occupied by explicit operands.
  ///
  /// We can safely reuse the integer destination register (`rt`) as the
  /// temporary index value when `rt != base`, because the load overwrites `rt`
  /// at the end of the sequence.
  fn try_emit_int_load_with_dst_tmp(
    self : MachineCode,
    ty : @instr.MemType,
    rt : Int,
    base : Int,
    index : Int,
    ext : @instr.IndexExtend,
    shift : Int,
    offset : Int,
    can_use_scaled_amode : Bool,
  ) -> Bool {
    if rt == base {
      return false
    }
    match ty {
      I32 | I64 => {
        match ext {
          None => if rt != index { self.x86_emit_mov_rr(rt, index) }
          Uxtw =>
            if rt != index {
              self.x86_emit_mov_rr32(rt, index)
            } else {
              self.x86_emit_mov_rr32(rt, rt)
            }
          Sxtw =>
            if rt != index {
              self.x86_emit_movsxd_r64_r32(rt, index)
            } else {
              self.x86_emit_movsxd_r64_r32(rt, rt)
            }
        }
        if can_use_scaled_amode && (rt & 7) != 4 {
          match ty {
            I32 =>
              self.x86_emit_mov_r32_m32_base_index_scale_disp(
                rt, base, rt, shift, offset,
              )
            I64 =>
              self.x86_emit_mov_r64_m64_base_index_scale_disp(
                rt, base, rt, shift, offset,
              )
            _ => ()
          }
          return true
        }
        if shift > 0 {
          self.x86_emit_shl_r_imm8(rt, shift)
        }
        if (rt & 7) != 4 {
          match ty {
            I32 =>
              self.x86_emit_mov_r32_m32_base_index_scale_disp(
                rt, base, rt, 0, offset,
              )
            I64 =>
              self.x86_emit_mov_r64_m64_base_index_scale_disp(
                rt, base, rt, 0, offset,
              )
            _ => ()
          }
          return true
        }
        self.x86_emit_add_rr(rt, base)
        match ty {
          I32 => self.x86_emit_mov_r32_m32(rt, rt, offset)
          I64 => self.x86_emit_mov_r64_m64(rt, rt, offset)
          _ => ()
        }
        true
      }
      _ => false
    }
  }

  fn emit_amd64_abort(msg : String) -> Unit {
    println("wasmoon amd64 emit: \{msg}")
    abort(msg)
  }

  ///|
  /// Scalar min/max with WebAssembly semantics, aligned with Cranelift x64.
  ///
  /// Implements the `XmmMinMaxSeq` sequence from Cranelift:
  /// - Handle NaNs symmetrically (propagate a quiet NaN via add).
  /// - Handle +0/-0 by merging sign bits on ordered-equal.
  fn emit_scalar_min_max_seq(
    self : MachineCode,
    is_f32 : Bool,
    is_min : Bool,
    rd : Int,
    lhs : Int,
    rhs : Int,
  ) -> Unit {
    // The Cranelift sequence expects dst == rhs. We can enforce this with
    // a couple of moves, preserving `lhs` if it aliases `rd`.
    let tmp = 14 // reserved via MachineEnvData.scratch_float
    let lhs_reg = if rd == rhs {
      lhs
    } else if rd == lhs {
      self.x86_emit_movaps_xmm_xmm(tmp, lhs)
      self.x86_emit_movaps_xmm_xmm(rd, rhs)
      tmp
    } else {
      self.x86_emit_movaps_xmm_xmm(rd, rhs)
      lhs
    }
    let done = self.new_internal_label()
    let propagate_nan = self.new_internal_label()
    let do_min_max = self.new_internal_label()
    if is_f32 {
      self.x86_emit_ucomiss_xmm_xmm(rd, lhs_reg)
    } else {
      self.x86_emit_ucomisd_xmm_xmm(rd, lhs_reg)
    }

    // If not equal, use native min/max.
    self.x86_emit_jcc_rel32(Ne, do_min_max) // JNZ
    // If unordered (NaN), propagate NaN via add.
    self.x86_emit_jcc_rel32(Ps, propagate_nan) // JP

    // Ordered and equal: merge sign bits to handle -0 vs +0.
    if is_f32 {
      if is_min {
        self.x86_emit_orps_xmm_xmm(rd, lhs_reg)
      } else {
        self.x86_emit_andps_xmm_xmm(rd, lhs_reg)
      }
    } else if is_min {
      self.x86_emit_orpd_xmm_xmm(rd, lhs_reg)
    } else {
      self.x86_emit_andpd_xmm_xmm(rd, lhs_reg)
    }
    self.x86_emit_jmp_rel32(done)
    self.define_label(propagate_nan)
    if is_f32 {
      self.x86_emit_addss_xmm_xmm(rd, lhs_reg)
    } else {
      self.x86_emit_addsd_xmm_xmm(rd, lhs_reg)
    }
    // PF is still set from the UCOMIS* above, so JP is always taken here.
    self.x86_emit_jcc_rel32(Ps, done)
    self.define_label(do_min_max)
    if is_f32 {
      if is_min {
        self.x86_emit_minss_xmm_xmm(rd, lhs_reg)
      } else {
        self.x86_emit_maxss_xmm_xmm(rd, lhs_reg)
      }
    } else if is_min {
      self.x86_emit_minsd_xmm_xmm(rd, lhs_reg)
    } else {
      self.x86_emit_maxsd_xmm_xmm(rd, lhs_reg)
    }
    self.define_label(done)
  }

  self.annotate(inst.to_string())
  match inst.opcode {
    Umulh => {
      // Unsigned multiply high: rd = (lhs * rhs) >> 64.
      //
      // amd64 encoding uses implicit RAX/RDX: MUL r/m64 computes RDX:RAX.
      // Lowering constrains result to RDX; this emitter moves lhs to RAX.
      let rd = wreg_num(inst.defs[0])
      let lhs = reg_num(inst.uses[0])
      let mut rhs = reg_num(inst.uses[1])
      if lhs != 0 && rhs == 0 {
        let scratch = pick_scratch_gpr(isa, rd, lhs, rhs, -1)
        self.x86_emit_mov_rr(scratch, rhs)
        rhs = scratch
      }
      if lhs != 0 {
        self.x86_emit_mov_rr(0, lhs)
      }
      self.x86_emit_mul_r64(rhs)
      if rd != 2 {
        self.x86_emit_mov_rr(rd, 2)
      }
    }
    Smulh => {
      // Signed multiply high: rd = (lhs * rhs) >> 64.
      //
      // amd64 encoding uses implicit RAX/RDX: IMUL r/m64 computes RDX:RAX.
      // Lowering constrains result to RDX; this emitter moves lhs to RAX.
      let rd = wreg_num(inst.defs[0])
      let lhs = reg_num(inst.uses[0])
      let mut rhs = reg_num(inst.uses[1])
      if lhs != 0 && rhs == 0 {
        let scratch = pick_scratch_gpr(isa, rd, lhs, rhs, -1)
        self.x86_emit_mov_rr(scratch, rhs)
        rhs = scratch
      }
      if lhs != 0 {
        self.x86_emit_mov_rr(0, lhs)
      }
      self.x86_emit_imul1_r64(rhs)
      if rd != 2 {
        self.x86_emit_mov_rr(rd, 2)
      }
    }
    Smull => {
      // Signed widening multiply: sign-extend i32 operands, keep low 64 bits.
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      let mut rhs = isa.scratch_reg_1_index()
      if rhs == rd {
        rhs = isa.scratch_reg_2_index()
      }
      self.x86_emit_mov_rr32(rd, rn)
      self.x86_emit_movsxd_r64_r32(rd, rd)
      self.x86_emit_mov_rr32(rhs, rm)
      self.x86_emit_movsxd_r64_r32(rhs, rhs)
      self.x86_emit_imul_rr(rd, rhs)
    }
    Umull => {
      // Unsigned widening multiply: zero-extend i32 operands, keep low 64 bits.
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      let rhs = pick_scratch_gpr(isa, rd, rn, rm, -1)
      self.x86_emit_mov_rr32(rd, rn)
      self.x86_emit_mov_rr32(rhs, rm)
      self.x86_emit_imul_rr(rd, rhs)
    }
    Add(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      // Cranelift x64 emit_lea alignment:
      // - prefer add when dst aliases one operand (equivalent to lea disp=0, scale=1),
      // - otherwise keep lea form.
      if rd == rn {
        if is_64 {
          self.x86_emit_add_rr(rd, rm)
        } else {
          self.x86_emit_add_rr32(rd, rm)
        }
        return
      }
      if rd == rm {
        if is_64 {
          self.x86_emit_add_rr(rd, rn)
        } else {
          self.x86_emit_add_rr32(rd, rn)
        }
        return
      }
      // x86 SIB requires index != rsp/r12, so try both operand orders.
      if (rm & 7) != 4 {
        if is_64 {
          self.x86_emit_lea_r64_base_index_scale_disp(rd, rn, rm, 0, 0)
        } else {
          self.x86_emit_lea_r32_base_index_scale_disp(rd, rn, rm, 0, 0)
        }
        return
      }
      if (rn & 7) != 4 {
        if is_64 {
          self.x86_emit_lea_r64_base_index_scale_disp(rd, rm, rn, 0, 0)
        } else {
          self.x86_emit_lea_r32_base_index_scale_disp(rd, rm, rn, 0, 0)
        }
        return
      }
      if is_64 {
        self.x86_emit_mov_rr(rd, rn)
        self.x86_emit_add_rr(rd, rm)
      } else {
        self.x86_emit_mov_rr32(rd, rn)
        self.x86_emit_add_rr32(rd, rm)
      }
    }
    Sub(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if rd == rn {
        if is_64 {
          self.x86_emit_sub_rr(rd, rm)
        } else {
          self.x86_emit_sub_rr32(rd, rm)
        }
        return
      }
      if rd == rm {
        if is_64 {
          self.x86_emit_neg_r64(rd)
          self.x86_emit_add_rr(rd, rn)
        } else {
          self.x86_emit_neg_r32(rd)
          self.x86_emit_add_rr32(rd, rn)
        }
        return
      }
      if is_64 {
        self.x86_emit_mov_rr(rd, rn)
        self.x86_emit_sub_rr(rd, rm)
      } else {
        self.x86_emit_mov_rr32(rd, rn)
        self.x86_emit_sub_rr32(rd, rm)
      }
    }
    AddImm(imm, is_64) => {
      // Cranelift-style: prefer direct reg-imm ALU forms (imm8/imm32) and
      // only fall back to scratch materialization for out-of-range immediates.
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if rd != rn {
        if is_64 {
          self.x86_emit_mov_rr(rd, rn)
        } else {
          self.x86_emit_mov_rr32(rd, rn)
        }
      }
      if fits_i32(imm) {
        if is_64 {
          if fits_i8(imm) {
            self.x86_emit_add_r_imm8(rd, imm)
          } else {
            self.x86_emit_add_r_imm32(rd, imm)
          }
        } else if fits_i8(imm) {
          self.x86_emit_add_r32_imm8(rd, imm)
        } else {
          self.x86_emit_add_r32_imm32(rd, imm)
        }
      } else {
        let scratch = pick_scratch_gpr(isa, rd, rn, -1, -1)
        self.x86_emit_mov_imm64(scratch, imm.to_int64())
        if is_64 {
          self.x86_emit_add_rr(rd, scratch)
        } else {
          self.x86_emit_add_rr32(rd, scratch)
        }
      }
    }
    SubImm(imm, is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if rd != rn {
        if is_64 {
          self.x86_emit_mov_rr(rd, rn)
        } else {
          self.x86_emit_mov_rr32(rd, rn)
        }
      }
      if fits_i32(imm) {
        if is_64 {
          if fits_i8(imm) {
            self.x86_emit_sub_r_imm8(rd, imm)
          } else {
            self.x86_emit_sub_r_imm32(rd, imm)
          }
        } else if fits_i8(imm) {
          self.x86_emit_sub_r32_imm8(rd, imm)
        } else {
          self.x86_emit_sub_r32_imm32(rd, imm)
        }
      } else {
        let scratch = pick_scratch_gpr(isa, rd, rn, -1, -1)
        self.x86_emit_mov_imm64(scratch, imm.to_int64())
        if is_64 {
          self.x86_emit_sub_rr(rd, scratch)
        } else {
          self.x86_emit_sub_rr32(rd, scratch)
        }
      }
    }
    FAdd(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let src = prepare_xmm_two_operand(self, rd, a, b, 14)
      if is_f32 {
        self.x86_emit_addss_xmm_xmm(rd, src)
      } else {
        self.x86_emit_addsd_xmm_xmm(rd, src)
      }
    }
    FSub(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let src = prepare_xmm_two_operand(self, rd, a, b, 14)
      if is_f32 {
        self.x86_emit_subss_xmm_xmm(rd, src)
      } else {
        self.x86_emit_subsd_xmm_xmm(rd, src)
      }
    }
    FMul(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let src = prepare_xmm_two_operand(self, rd, a, b, 14)
      if is_f32 {
        self.x86_emit_mulss_xmm_xmm(rd, src)
      } else {
        self.x86_emit_mulsd_xmm_xmm(rd, src)
      }
    }
    FDiv(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let src = prepare_xmm_two_operand(self, rd, a, b, 14)
      if is_f32 {
        self.x86_emit_divss_xmm_xmm(rd, src)
      } else {
        self.x86_emit_divsd_xmm_xmm(rd, src)
      }
    }
    FSqrt(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      if rd != src {
        self.x86_emit_movaps_xmm_xmm(rd, src)
      }
      if is_f32 {
        self.x86_emit_sqrtss_xmm_xmm(rd, rd)
      } else {
        self.x86_emit_sqrtsd_xmm_xmm(rd, rd)
      }
    }
    FAbs(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      if rd != src {
        self.x86_emit_movaps_xmm_xmm(rd, src)
      }
      let mut mask = 14 // reserved via MachineEnvData.scratch_float
      if mask == rd {
        mask = 15
      }
      let scratch_gpr = isa.scratch_reg_1_index()
      if is_f32 {
        // Mirrors Cranelift x64: andps x, (imm f32 0x7fffffff).
        materialize_xmm_const(self, mask, 0x7FFFFFFF, 0L, scratch_gpr)
        self.x86_emit_andps_xmm_xmm(rd, mask)
      } else {
        // Mirrors Cranelift x64: andpd x, (imm f64 0x7fffffffffffffff).
        materialize_xmm_const(self, mask, 0x7FFFFFFFFFFFFFFFL, 0L, scratch_gpr)
        self.x86_emit_andpd_xmm_xmm(rd, mask)
      }
    }
    FNeg(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      if rd != src {
        self.x86_emit_movaps_xmm_xmm(rd, src)
      }
      let mut mask = 14 // reserved via MachineEnvData.scratch_float
      if mask == rd {
        mask = 15
      }
      let scratch_gpr = isa.scratch_reg_1_index()
      if is_f32 {
        // Mirrors Cranelift x64: xorps x, (imm f32 0x80000000).
        materialize_xmm_const(self, mask, 0x80000000, 0L, scratch_gpr)
        self.x86_emit_xorps_xmm_xmm(rd, mask)
      } else {
        // Mirrors Cranelift x64: xorpd x, (imm f64 0x8000000000000000).
        materialize_xmm_const(self, mask, 0x8000000000000000L, 0L, scratch_gpr)
        self.x86_emit_xorpd_xmm_xmm(rd, mask)
      }
    }
    FMin(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let lhs = reg_num(inst.uses[0])
      let rhs = reg_num(inst.uses[1])
      emit_scalar_min_max_seq(self, is_f32, true, rd, lhs, rhs)
    }
    FMax(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let lhs = reg_num(inst.uses[0])
      let rhs = reg_num(inst.uses[1])
      emit_scalar_min_max_seq(self, is_f32, false, rd, lhs, rhs)
    }
    FCeil(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      if is_f32 {
        self.x86_emit_roundss_xmm_xmm_imm8(rd, src, 2)
      } else {
        self.x86_emit_roundsd_xmm_xmm_imm8(rd, src, 2)
      }
    }
    FFloor(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      if is_f32 {
        self.x86_emit_roundss_xmm_xmm_imm8(rd, src, 1)
      } else {
        self.x86_emit_roundsd_xmm_xmm_imm8(rd, src, 1)
      }
    }
    FTrunc(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      if is_f32 {
        self.x86_emit_roundss_xmm_xmm_imm8(rd, src, 3)
      } else {
        self.x86_emit_roundsd_xmm_xmm_imm8(rd, src, 3)
      }
    }
    FNearest(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      if is_f32 {
        self.x86_emit_roundss_xmm_xmm_imm8(rd, src, 0)
      } else {
        self.x86_emit_roundsd_xmm_xmm_imm8(rd, src, 0)
      }
    }
    Mul(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      let src = if rd == rn {
        rm
      } else if rd == rm {
        rn
      } else {
        if is_64 {
          self.x86_emit_mov_rr(rd, rn)
        } else {
          self.x86_emit_mov_rr32(rd, rn)
        }
        rm
      }
      if is_64 {
        self.x86_emit_imul_rr(rd, src)
      } else {
        self.x86_emit_imul_rr32(rd, src)
      }
    }
    Madd => {
      // rd = acc + (src1 * src2)  (i64 only; generated by lowering patterns)
      let rd = wreg_num(inst.defs[0])
      let acc = reg_num(inst.uses[0])
      let src1 = reg_num(inst.uses[1])
      let src2 = reg_num(inst.uses[2])
      let tmp = pick_scratch_gpr(isa, rd, acc, src1, src2)
      self.x86_emit_mov_rr(tmp, src1)
      self.x86_emit_imul_rr(tmp, src2)
      self.x86_emit_add_rr(tmp, acc)
      if rd != tmp {
        self.x86_emit_mov_rr(rd, tmp)
      }
    }
    Msub => {
      // rd = acc - (src1 * src2)  (i64 only; generated by lowering patterns)
      let rd = wreg_num(inst.defs[0])
      let acc = reg_num(inst.uses[0])
      let src1 = reg_num(inst.uses[1])
      let src2 = reg_num(inst.uses[2])
      let tmp = pick_scratch_gpr(isa, rd, acc, src1, src2)
      self.x86_emit_mov_rr(tmp, src1)
      self.x86_emit_imul_rr(tmp, src2)
      if rd != acc {
        self.x86_emit_mov_rr(rd, acc)
      }
      self.x86_emit_sub_rr(rd, tmp)
    }
    Mneg => {
      // rd = -(src1 * src2)  (i64 only; generated by lowering patterns)
      let rd = wreg_num(inst.defs[0])
      let src1 = reg_num(inst.uses[0])
      let src2 = reg_num(inst.uses[1])
      let tmp = pick_scratch_gpr(isa, rd, src1, src2, -1)
      self.x86_emit_mov_rr(tmp, src1)
      self.x86_emit_imul_rr(tmp, src2)
      self.x86_emit_neg_r64(tmp)
      if rd != tmp {
        self.x86_emit_mov_rr(rd, tmp)
      }
    }
    Madd32 => {
      // rd = acc + (src1 * src2)  (i32 form)
      let rd = wreg_num(inst.defs[0])
      let acc = reg_num(inst.uses[0])
      let src1 = reg_num(inst.uses[1])
      let src2 = reg_num(inst.uses[2])
      let tmp = pick_scratch_gpr(isa, rd, acc, src1, src2)
      self.x86_emit_mov_rr32(tmp, src1)
      self.x86_emit_imul_rr32(tmp, src2)
      if rd != acc {
        self.x86_emit_mov_rr32(rd, acc)
      }
      self.x86_emit_add_rr32(rd, tmp)
    }
    Msub32 => {
      // rd = acc - (src1 * src2)  (i32 form)
      let rd = wreg_num(inst.defs[0])
      let acc = reg_num(inst.uses[0])
      let src1 = reg_num(inst.uses[1])
      let src2 = reg_num(inst.uses[2])
      let tmp = pick_scratch_gpr(isa, rd, acc, src1, src2)
      self.x86_emit_mov_rr32(tmp, src1)
      self.x86_emit_imul_rr32(tmp, src2)
      if rd != acc {
        self.x86_emit_mov_rr32(rd, acc)
      }
      self.x86_emit_sub_rr32(rd, tmp)
    }
    Mneg32 => {
      // rd = -(src1 * src2)  (i32 form)
      let rd = wreg_num(inst.defs[0])
      let src1 = reg_num(inst.uses[0])
      let src2 = reg_num(inst.uses[1])
      let prod = pick_scratch_gpr(isa, rd, src1, src2, -1)
      self.x86_emit_mov_rr32(prod, src1)
      self.x86_emit_imul_rr32(prod, src2)
      self.x86_emit_xor_rr32(rd, rd)
      self.x86_emit_sub_rr32(rd, prod)
    }
    And(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      let src = if rd == rn {
        rm
      } else if rd == rm {
        rn
      } else {
        if is_64 {
          self.x86_emit_mov_rr(rd, rn)
        } else {
          self.x86_emit_mov_rr32(rd, rn)
        }
        rm
      }
      if is_64 {
        self.x86_emit_and_rr(rd, src)
      } else {
        self.x86_emit_and_rr32(rd, src)
      }
    }
    AndImm(imm, is_64) => {
      // Fallback: materialize imm into scratch and use and.
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if rd != rn {
        if is_64 {
          self.x86_emit_mov_rr(rd, rn)
        } else {
          self.x86_emit_mov_rr32(rd, rn)
        }
      }
      let scratch = pick_scratch_gpr(isa, rd, rn, -1, -1)
      self.x86_emit_mov_imm64(scratch, imm)
      if is_64 {
        self.x86_emit_and_rr(rd, scratch)
      } else {
        self.x86_emit_and_rr32(rd, scratch)
      }
    }
    AndNot(is_64) => {
      // rd = rn & ~rm
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      let mut tmp = isa.scratch_reg_1_index()
      if tmp == rd || tmp == rn || tmp == rm {
        tmp = isa.scratch_reg_2_index()
      }
      if tmp == rd || tmp == rn || tmp == rm {
        abort("x86_64 andnot: no scratch register available")
      }
      if rd != rn {
        if is_64 {
          self.x86_emit_mov_rr(rd, rn)
        } else {
          self.x86_emit_mov_rr32(rd, rn)
        }
      }
      if is_64 {
        self.x86_emit_mov_rr(tmp, rm)
        self.x86_emit_not_r64(tmp)
        self.x86_emit_and_rr(rd, tmp)
      } else {
        self.x86_emit_mov_rr32(tmp, rm)
        self.x86_emit_not_r32(tmp)
        self.x86_emit_and_rr32(rd, tmp)
      }
    }
    Or(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      let src = if rd == rn {
        rm
      } else if rd == rm {
        rn
      } else {
        if is_64 {
          self.x86_emit_mov_rr(rd, rn)
        } else {
          self.x86_emit_mov_rr32(rd, rn)
        }
        rm
      }
      if is_64 {
        self.x86_emit_or_rr(rd, src)
      } else {
        self.x86_emit_or_rr32(rd, src)
      }
    }
    OrImm(imm, is_64) => {
      // Fallback: materialize imm into scratch and use or.
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if rd != rn {
        if is_64 {
          self.x86_emit_mov_rr(rd, rn)
        } else {
          self.x86_emit_mov_rr32(rd, rn)
        }
      }
      let scratch = pick_scratch_gpr(isa, rd, rn, -1, -1)
      self.x86_emit_mov_imm64(scratch, imm)
      if is_64 {
        self.x86_emit_or_rr(rd, scratch)
      } else {
        self.x86_emit_or_rr32(rd, scratch)
      }
    }
    OrNot(is_64) => {
      // rd = rn | ~rm
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      let mut tmp = isa.scratch_reg_1_index()
      if tmp == rd || tmp == rn || tmp == rm {
        tmp = isa.scratch_reg_2_index()
      }
      if tmp == rd || tmp == rn || tmp == rm {
        abort("x86_64 ornot: no scratch register available")
      }
      if rd != rn {
        if is_64 {
          self.x86_emit_mov_rr(rd, rn)
        } else {
          self.x86_emit_mov_rr32(rd, rn)
        }
      }
      if is_64 {
        self.x86_emit_mov_rr(tmp, rm)
        self.x86_emit_not_r64(tmp)
        self.x86_emit_or_rr(rd, tmp)
      } else {
        self.x86_emit_mov_rr32(tmp, rm)
        self.x86_emit_not_r32(tmp)
        self.x86_emit_or_rr32(rd, tmp)
      }
    }
    Xor(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      let src = if rd == rn {
        rm
      } else if rd == rm {
        rn
      } else {
        if is_64 {
          self.x86_emit_mov_rr(rd, rn)
        } else {
          self.x86_emit_mov_rr32(rd, rn)
        }
        rm
      }
      if is_64 {
        self.x86_emit_xor_rr(rd, src)
      } else {
        self.x86_emit_xor_rr32(rd, src)
      }
    }
    XorImm(imm, is_64) => {
      // Fallback: materialize imm into scratch and use xor.
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if rd != rn {
        if is_64 {
          self.x86_emit_mov_rr(rd, rn)
        } else {
          self.x86_emit_mov_rr32(rd, rn)
        }
      }
      let scratch = pick_scratch_gpr(isa, rd, rn, -1, -1)
      self.x86_emit_mov_imm64(scratch, imm)
      if is_64 {
        self.x86_emit_xor_rr(rd, scratch)
      } else {
        self.x86_emit_xor_rr32(rd, scratch)
      }
    }
    XorNot(is_64) => {
      // rd = rn ^ ~rm
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      let mut tmp = isa.scratch_reg_1_index()
      if tmp == rd || tmp == rn || tmp == rm {
        tmp = isa.scratch_reg_2_index()
      }
      if tmp == rd || tmp == rn || tmp == rm {
        abort("x86_64 xornot: no scratch register available")
      }
      if rd != rn {
        if is_64 {
          self.x86_emit_mov_rr(rd, rn)
        } else {
          self.x86_emit_mov_rr32(rd, rn)
        }
      }
      if is_64 {
        self.x86_emit_mov_rr(tmp, rm)
        self.x86_emit_not_r64(tmp)
        self.x86_emit_xor_rr(rd, tmp)
      } else {
        self.x86_emit_mov_rr32(tmp, rm)
        self.x86_emit_not_r32(tmp)
        self.x86_emit_xor_rr32(rd, tmp)
      }
    }
    AddExtend(ext, amount) => {
      // AArch64-specific ADD with extended W operand:
      //   rd = rn + extend_32_to_64(rm) << amount
      // amd64 fallback materializes the extension explicitly.
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      let tmp = pick_scratch_gpr(isa, rd, rn, rm, -1)
      match ext {
        Uxtw => self.x86_emit_mov_rr32(tmp, rm)
        Sxtw => self.x86_emit_movsxd_r64_r32(tmp, rm)
        None => abort("x86_64 add_extend expects Uxtw or Sxtw, got None")
      }
      let sh = amount & 63
      if sh != 0 {
        self.x86_emit_shl_r_imm8(tmp, sh)
      }
      if rd != rn {
        self.x86_emit_mov_rr(rd, rn)
      }
      self.x86_emit_add_rr(rd, tmp)
    }
    SubExtend(ext, amount) => {
      // AArch64-specific SUB with extended W operand:
      //   rd = rn - extend_32_to_64(rm) << amount
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      let tmp = pick_scratch_gpr(isa, rd, rn, rm, -1)
      match ext {
        Uxtw => self.x86_emit_mov_rr32(tmp, rm)
        Sxtw => self.x86_emit_movsxd_r64_r32(tmp, rm)
        None => abort("x86_64 sub_extend expects Uxtw or Sxtw, got None")
      }
      let sh = amount & 63
      if sh != 0 {
        self.x86_emit_shl_r_imm8(tmp, sh)
      }
      if rd != rn {
        self.x86_emit_mov_rr(rd, rn)
      }
      self.x86_emit_sub_rr(rd, tmp)
    }
    AddShifted(shift, amount) => {
      // AArch64 fused "op + shifted operand" form.
      //
      // amd64 lowering may still emit these today; emulate with a scratch register:
      //   tmp = rm << amount
      //   rd = rn + tmp
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if shift is Lsl && amount >= 0 && amount <= 3 {
        // Cranelift emit_lea does add-conversion for scale=1, disp=0 when dst aliases base/index.
        if amount == 0 {
          if rd == rn {
            self.x86_emit_add_rr(rd, rm)
            return
          }
          if rd == rm {
            self.x86_emit_add_rr(rd, rn)
            return
          }
        }
        // Cranelift x64 iadd-shift style: lea rd, [base + index * scale].
        if (rm & 7) != 4 {
          self.x86_emit_lea_r64_base_index_scale_disp(rd, rn, rm, amount, 0)
          return
        }
        // For scale=1, addition is commutative; swap operands to avoid rsp/r12 index.
        if amount == 0 && (rn & 7) != 4 {
          self.x86_emit_lea_r64_base_index_scale_disp(rd, rm, rn, 0, 0)
          return
        }
      }
      let tmp = pick_scratch_gpr(isa, rd, rn, rm, -1)
      self.x86_emit_mov_rr(tmp, rm)
      let sh = amount & 63
      if sh != 0 {
        match shift {
          Lsl => self.x86_emit_shl_r_imm8(tmp, sh)
          Lsr => self.x86_emit_shr_r_imm8(tmp, sh)
          Asr => self.x86_emit_sar_r_imm8(tmp, sh)
        }
      }
      if rd != rn {
        self.x86_emit_mov_rr(rd, rn)
      }
      self.x86_emit_add_rr(rd, tmp)
    }
    AddShifted32(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if shift is Lsl && amount >= 0 && amount <= 3 {
        if amount == 0 {
          if rd == rn {
            self.x86_emit_add_rr32(rd, rm)
            return
          }
          if rd == rm {
            self.x86_emit_add_rr32(rd, rn)
            return
          }
        }
        if (rm & 7) != 4 {
          self.x86_emit_lea_r32_base_index_scale_disp(rd, rn, rm, amount, 0)
          return
        }
        if amount == 0 && (rn & 7) != 4 {
          self.x86_emit_lea_r32_base_index_scale_disp(rd, rm, rn, 0, 0)
          return
        }
      }
      let tmp = pick_scratch_gpr(isa, rd, rn, rm, -1)
      self.x86_emit_mov_rr32(tmp, rm)
      let sh = amount & 31
      if sh != 0 {
        match shift {
          Lsl => self.x86_emit_shl_r32_imm8(tmp, sh)
          Lsr => self.x86_emit_shr_r32_imm8(tmp, sh)
          Asr => self.x86_emit_sar_r32_imm8(tmp, sh)
        }
      }
      if rd != rn {
        self.x86_emit_mov_rr32(rd, rn)
      }
      self.x86_emit_add_rr32(rd, tmp)
    }
    SubShifted(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      let tmp = pick_scratch_gpr(isa, rd, rn, rm, -1)
      self.x86_emit_mov_rr(tmp, rm)
      let sh = amount & 63
      if sh != 0 {
        match shift {
          Lsl => self.x86_emit_shl_r_imm8(tmp, sh)
          Lsr => self.x86_emit_shr_r_imm8(tmp, sh)
          Asr => self.x86_emit_sar_r_imm8(tmp, sh)
        }
      }
      if rd != rn {
        self.x86_emit_mov_rr(rd, rn)
      }
      self.x86_emit_sub_rr(rd, tmp)
    }
    SubShifted32(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      let tmp = pick_scratch_gpr(isa, rd, rn, rm, -1)
      self.x86_emit_mov_rr32(tmp, rm)
      let sh = amount & 31
      if sh != 0 {
        match shift {
          Lsl => self.x86_emit_shl_r32_imm8(tmp, sh)
          Lsr => self.x86_emit_shr_r32_imm8(tmp, sh)
          Asr => self.x86_emit_sar_r32_imm8(tmp, sh)
        }
      }
      if rd != rn {
        self.x86_emit_mov_rr32(rd, rn)
      }
      self.x86_emit_sub_rr32(rd, tmp)
    }
    AndShifted(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      let tmp = pick_scratch_gpr(isa, rd, rn, rm, -1)
      self.x86_emit_mov_rr(tmp, rm)
      let sh = amount & 63
      if sh != 0 {
        match shift {
          Lsl => self.x86_emit_shl_r_imm8(tmp, sh)
          Lsr => self.x86_emit_shr_r_imm8(tmp, sh)
          Asr => self.x86_emit_sar_r_imm8(tmp, sh)
        }
      }
      if rd != rn {
        self.x86_emit_mov_rr(rd, rn)
      }
      self.x86_emit_and_rr(rd, tmp)
    }
    AndShifted32(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      let tmp = pick_scratch_gpr(isa, rd, rn, rm, -1)
      self.x86_emit_mov_rr32(tmp, rm)
      let sh = amount & 31
      if sh != 0 {
        match shift {
          Lsl => self.x86_emit_shl_r32_imm8(tmp, sh)
          Lsr => self.x86_emit_shr_r32_imm8(tmp, sh)
          Asr => self.x86_emit_sar_r32_imm8(tmp, sh)
        }
      }
      if rd != rn {
        self.x86_emit_mov_rr32(rd, rn)
      }
      self.x86_emit_and_rr32(rd, tmp)
    }
    OrShifted(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      let tmp = pick_scratch_gpr(isa, rd, rn, rm, -1)
      self.x86_emit_mov_rr(tmp, rm)
      let sh = amount & 63
      if sh != 0 {
        match shift {
          Lsl => self.x86_emit_shl_r_imm8(tmp, sh)
          Lsr => self.x86_emit_shr_r_imm8(tmp, sh)
          Asr => self.x86_emit_sar_r_imm8(tmp, sh)
        }
      }
      if rd != rn {
        self.x86_emit_mov_rr(rd, rn)
      }
      self.x86_emit_or_rr(rd, tmp)
    }
    OrShifted32(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      let tmp = pick_scratch_gpr(isa, rd, rn, rm, -1)
      self.x86_emit_mov_rr32(tmp, rm)
      let sh = amount & 31
      if sh != 0 {
        match shift {
          Lsl => self.x86_emit_shl_r32_imm8(tmp, sh)
          Lsr => self.x86_emit_shr_r32_imm8(tmp, sh)
          Asr => self.x86_emit_sar_r32_imm8(tmp, sh)
        }
      }
      if rd != rn {
        self.x86_emit_mov_rr32(rd, rn)
      }
      self.x86_emit_or_rr32(rd, tmp)
    }
    XorShifted(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      let tmp = pick_scratch_gpr(isa, rd, rn, rm, -1)
      self.x86_emit_mov_rr(tmp, rm)
      let sh = amount & 63
      if sh != 0 {
        match shift {
          Lsl => self.x86_emit_shl_r_imm8(tmp, sh)
          Lsr => self.x86_emit_shr_r_imm8(tmp, sh)
          Asr => self.x86_emit_sar_r_imm8(tmp, sh)
        }
      }
      if rd != rn {
        self.x86_emit_mov_rr(rd, rn)
      }
      self.x86_emit_xor_rr(rd, tmp)
    }
    XorShifted32(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      let tmp = pick_scratch_gpr(isa, rd, rn, rm, -1)
      self.x86_emit_mov_rr32(tmp, rm)
      let sh = amount & 31
      if sh != 0 {
        match shift {
          Lsl => self.x86_emit_shl_r32_imm8(tmp, sh)
          Lsr => self.x86_emit_shr_r32_imm8(tmp, sh)
          Asr => self.x86_emit_sar_r32_imm8(tmp, sh)
        }
      }
      if rd != rn {
        self.x86_emit_mov_rr32(rd, rn)
      }
      self.x86_emit_xor_rr32(rd, tmp)
    }
    Not(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if rd != rn {
        if is_64 {
          self.x86_emit_mov_rr(rd, rn)
        } else {
          self.x86_emit_mov_rr32(rd, rn)
        }
      }
      if is_64 {
        self.x86_emit_not_r64(rd)
      } else {
        self.x86_emit_not_r32(rd)
      }
    }
    Clz(is_64) => {
      // Count leading zeros.
      //
      // Use a baseline x86_64 sequence:
      // - if x == 0 -> result = bit_width
      // - else result = (bit_width - 1) - bsr(x)
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let tmp = isa.scratch_reg_1_index()
      let tmp2 = isa.scratch_reg_2_index()
      let nonzero = self.new_internal_label()
      let done = self.new_internal_label()
      if is_64 {
        self.x86_emit_mov_rr(tmp, rn)
        self.x86_emit_test_rr(tmp, tmp)
        self.x86_emit_jcc_rel32(Ne, nonzero)
        self.x86_emit_mov_imm64(rd, 64L)
        self.x86_emit_jmp_rel32(done)
        self.define_label(nonzero)
        self.x86_emit_bsr_r64_r64(tmp2, tmp)
        self.x86_emit_mov_imm64(rd, 63L)
        self.x86_emit_sub_rr(rd, tmp2)
        self.define_label(done)
      } else {
        self.x86_emit_mov_rr32(tmp, rn)
        self.x86_emit_test_rr32(tmp, tmp)
        self.x86_emit_jcc_rel32(Ne, nonzero)
        self.x86_emit_mov_imm64(rd, 32L)
        self.x86_emit_jmp_rel32(done)
        self.define_label(nonzero)
        self.x86_emit_bsr_r32_r32(tmp2, tmp)
        self.x86_emit_mov_imm64(rd, 31L)
        self.x86_emit_sub_rr32(rd, tmp2)
        self.define_label(done)
      }
    }
    Popcnt(is_64) => {
      // Population count.
      //
      // Software popcount to avoid CPU feature gating.
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let x = isa.scratch_reg_1_index()
      let t = isa.scratch_reg_2_index()
      if is_64 {
        // x = rn
        self.x86_emit_mov_rr(x, rn)

        // x = x - ((x >> 1) & 0x5555...)
        self.x86_emit_mov_rr(t, x)
        self.x86_emit_shr_r_imm8(t, 1)
        self.x86_emit_mov_imm64(rd, 0x5555555555555555L)
        self.x86_emit_and_rr(t, rd)
        self.x86_emit_mov_rr(rd, x)
        self.x86_emit_sub_rr(rd, t)
        self.x86_emit_mov_rr(x, rd)

        // x = (x & 0x3333...) + ((x >> 2) & 0x3333...)
        self.x86_emit_mov_rr(t, x)
        self.x86_emit_shr_r_imm8(t, 2)
        self.x86_emit_mov_imm64(rd, 0x3333333333333333L)
        self.x86_emit_and_rr(x, rd)
        self.x86_emit_and_rr(t, rd)
        self.x86_emit_mov_rr(rd, x)
        self.x86_emit_add_rr(rd, t)
        self.x86_emit_mov_rr(x, rd)

        // x = (x + (x >> 4)) & 0x0f0f...
        self.x86_emit_mov_rr(t, x)
        self.x86_emit_shr_r_imm8(t, 4)
        self.x86_emit_mov_rr(rd, x)
        self.x86_emit_add_rr(rd, t)
        self.x86_emit_mov_imm64(t, 0x0F0F0F0F0F0F0F0FL)
        self.x86_emit_and_rr(rd, t)
        self.x86_emit_mov_rr(x, rd)

        // x = x + (x >> 8); x = x + (x >> 16); x = x + (x >> 32)
        self.x86_emit_mov_rr(t, x)
        self.x86_emit_shr_r_imm8(t, 8)
        self.x86_emit_add_rr(x, t)
        self.x86_emit_mov_rr(t, x)
        self.x86_emit_shr_r_imm8(t, 16)
        self.x86_emit_add_rr(x, t)
        self.x86_emit_mov_rr(t, x)
        self.x86_emit_shr_r_imm8(t, 32)
        self.x86_emit_add_rr(x, t)

        // rd = x & 0x7f
        self.x86_emit_mov_imm64(rd, 0x7FL)
        self.x86_emit_and_rr(x, rd)
        if rd != x {
          self.x86_emit_mov_rr32(rd, x)
        }
      } else {
        // x = rn
        self.x86_emit_mov_rr32(x, rn)

        // x = x - ((x >> 1) & 0x55555555)
        self.x86_emit_mov_rr32(t, x)
        self.x86_emit_shr_r32_imm8(t, 1)
        self.x86_emit_mov_imm64(rd, 0x55555555L)
        self.x86_emit_and_rr32(t, rd)
        self.x86_emit_mov_rr32(rd, x)
        self.x86_emit_sub_rr32(rd, t)
        self.x86_emit_mov_rr32(x, rd)

        // x = (x & 0x33333333) + ((x >> 2) & 0x33333333)
        self.x86_emit_mov_rr32(t, x)
        self.x86_emit_shr_r32_imm8(t, 2)
        self.x86_emit_mov_imm64(rd, 0x33333333L)
        self.x86_emit_and_rr32(x, rd)
        self.x86_emit_and_rr32(t, rd)
        self.x86_emit_mov_rr32(rd, x)
        self.x86_emit_add_rr32(rd, t)
        self.x86_emit_mov_rr32(x, rd)

        // x = (x + (x >> 4)) & 0x0f0f0f0f
        self.x86_emit_mov_rr32(t, x)
        self.x86_emit_shr_r32_imm8(t, 4)
        self.x86_emit_mov_rr32(rd, x)
        self.x86_emit_add_rr32(rd, t)
        self.x86_emit_mov_imm64(t, 0x0F0F0F0FL)
        self.x86_emit_and_rr32(rd, t)
        self.x86_emit_mov_rr32(x, rd)

        // x = x + (x >> 8); x = x + (x >> 16)
        self.x86_emit_mov_rr32(t, x)
        self.x86_emit_shr_r32_imm8(t, 8)
        self.x86_emit_add_rr32(x, t)
        self.x86_emit_mov_rr32(t, x)
        self.x86_emit_shr_r32_imm8(t, 16)
        self.x86_emit_add_rr32(x, t)

        // rd = x & 0x3f
        self.x86_emit_mov_imm64(rd, 0x3FL)
        self.x86_emit_and_rr32(x, rd)
        if rd != x {
          self.x86_emit_mov_rr32(rd, x)
        }
      }
    }
    Rbit(is_64) => {
      // Reverse bits.
      //
      // Software bit-reversal using shift/mask swaps.
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let x = isa.scratch_reg_1_index()
      let t = isa.scratch_reg_2_index()
      if is_64 {
        self.x86_emit_mov_rr(x, rn)

        // Swap odd/even bits.
        self.x86_emit_mov_rr(t, x)
        self.x86_emit_shr_r_imm8(t, 1)
        self.x86_emit_mov_imm64(rd, 0x5555555555555555L)
        self.x86_emit_and_rr(t, rd)
        self.x86_emit_and_rr(x, rd)
        self.x86_emit_shl_r_imm8(x, 1)
        self.x86_emit_or_rr(x, t)

        // Swap consecutive pairs.
        self.x86_emit_mov_rr(t, x)
        self.x86_emit_shr_r_imm8(t, 2)
        self.x86_emit_mov_imm64(rd, 0x3333333333333333L)
        self.x86_emit_and_rr(t, rd)
        self.x86_emit_and_rr(x, rd)
        self.x86_emit_shl_r_imm8(x, 2)
        self.x86_emit_or_rr(x, t)

        // Swap nibbles.
        self.x86_emit_mov_rr(t, x)
        self.x86_emit_shr_r_imm8(t, 4)
        self.x86_emit_mov_imm64(rd, 0x0F0F0F0F0F0F0F0FL)
        self.x86_emit_and_rr(t, rd)
        self.x86_emit_and_rr(x, rd)
        self.x86_emit_shl_r_imm8(x, 4)
        self.x86_emit_or_rr(x, t)

        // Swap bytes.
        self.x86_emit_mov_rr(t, x)
        self.x86_emit_shr_r_imm8(t, 8)
        self.x86_emit_mov_imm64(rd, 0x00FF00FF00FF00FFL)
        self.x86_emit_and_rr(t, rd)
        self.x86_emit_and_rr(x, rd)
        self.x86_emit_shl_r_imm8(x, 8)
        self.x86_emit_or_rr(x, t)

        // Swap 16-bit words.
        self.x86_emit_mov_rr(t, x)
        self.x86_emit_shr_r_imm8(t, 16)
        self.x86_emit_mov_imm64(rd, 0x0000FFFF0000FFFFL)
        self.x86_emit_and_rr(t, rd)
        self.x86_emit_and_rr(x, rd)
        self.x86_emit_shl_r_imm8(x, 16)
        self.x86_emit_or_rr(x, t)

        // Swap 32-bit dwords.
        self.x86_emit_mov_rr(t, x)
        self.x86_emit_shr_r_imm8(t, 32)
        self.x86_emit_mov_imm64(rd, 0x00000000FFFFFFFFL)
        self.x86_emit_and_rr(t, rd)
        self.x86_emit_and_rr(x, rd)
        self.x86_emit_shl_r_imm8(x, 32)
        self.x86_emit_or_rr(x, t)
        if rd != x {
          self.x86_emit_mov_rr(rd, x)
        }
      } else {
        self.x86_emit_mov_rr32(x, rn)
        self.x86_emit_mov_rr32(t, x)
        self.x86_emit_shr_r32_imm8(t, 1)
        self.x86_emit_mov_imm64(rd, 0x55555555L)
        self.x86_emit_and_rr32(t, rd)
        self.x86_emit_and_rr32(x, rd)
        self.x86_emit_shl_r32_imm8(x, 1)
        self.x86_emit_or_rr32(x, t)
        self.x86_emit_mov_rr32(t, x)
        self.x86_emit_shr_r32_imm8(t, 2)
        self.x86_emit_mov_imm64(rd, 0x33333333L)
        self.x86_emit_and_rr32(t, rd)
        self.x86_emit_and_rr32(x, rd)
        self.x86_emit_shl_r32_imm8(x, 2)
        self.x86_emit_or_rr32(x, t)
        self.x86_emit_mov_rr32(t, x)
        self.x86_emit_shr_r32_imm8(t, 4)
        self.x86_emit_mov_imm64(rd, 0x0F0F0F0FL)
        self.x86_emit_and_rr32(t, rd)
        self.x86_emit_and_rr32(x, rd)
        self.x86_emit_shl_r32_imm8(x, 4)
        self.x86_emit_or_rr32(x, t)
        self.x86_emit_mov_rr32(t, x)
        self.x86_emit_shr_r32_imm8(t, 8)
        self.x86_emit_mov_imm64(rd, 0x00FF00FFL)
        self.x86_emit_and_rr32(t, rd)
        self.x86_emit_and_rr32(x, rd)
        self.x86_emit_shl_r32_imm8(x, 8)
        self.x86_emit_or_rr32(x, t)
        self.x86_emit_mov_rr32(t, x)
        self.x86_emit_shr_r32_imm8(t, 16)
        self.x86_emit_mov_imm64(rd, 0x0000FFFFL)
        self.x86_emit_and_rr32(t, rd)
        self.x86_emit_and_rr32(x, rd)
        self.x86_emit_shl_r32_imm8(x, 16)
        self.x86_emit_or_rr32(x, t)
        if rd != x {
          self.x86_emit_mov_rr32(rd, x)
        }
      }
    }
    Move => {
      let rd = wreg_num(inst.defs[0])
      let rm = reg_num(inst.uses[0])
      if rd == rm {
        return
      }
      let reg_class = match inst.defs[0].reg {
        Physical(preg) => preg.class
        Virtual(_) => Int
      }
      match reg_class {
        Int => self.x86_emit_mov_rr(rd, rm)
        Float32 | Float64 | Vector => self.x86_emit_movaps_xmm_xmm(rd, rm)
      }
    }
    LoadConst(v) => {
      let rd = wreg_num(inst.defs[0])
      self.x86_emit_mov_imm64(rd, v)
    }
    LoadConstF32(bits) => {
      let rd = wreg_num(inst.defs[0])
      let scratch = isa.scratch_reg_1_index()
      let label = self.intern_amd64_const_f32(bits)
      self.x86_emit_lea_r64_riprel32(scratch, label)
      self.x86_emit_movss_xmm_m32(rd, scratch, 0)
    }
    LoadConstF64(bits) => {
      let rd = wreg_num(inst.defs[0])
      let scratch = isa.scratch_reg_1_index()
      let label = self.intern_amd64_const_f64(bits)
      self.x86_emit_lea_r64_riprel32(scratch, label)
      self.x86_emit_movsd_xmm_m64(rd, scratch, 0)
    }
    LoadExternalFuncAddr(symbol) => {
      let rd = wreg_num(inst.defs[0])
      let fixup_offset = self.current_pos()
      self.x86_emit_mov_imm64(rd, 0L)
      self.add_external_func_addr_fixup(fixup_offset, symbol, rd)
    }
    Cmp(kind, is_64) => {
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
    FCmp(kind) => {
      // Match Cranelift x64 scalar fcmp lowering (see wasmtime cranelift x64 inst.isle `emit_fcmp`):
      // - UCOMIS* sets ZF/CF/PF; unordered => PF=1.
      // - Eq: NP && Z
      // - Ne: P || NZ
      // - Lt/Le use swapped operands + (NBE/NB), avoiding explicit orderedness checks.
      let lhs = reg_num(inst.uses[0])
      let rhs = reg_num(inst.uses[1])
      let rd = wreg_num(inst.defs[0])
      let class = reg_class_of(inst.uses[0])
      let is_f32 = class == Float32
      if class != Float32 && class != Float64 {
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
        Eq => {
          emit_ucomis(self, is_f32, lhs, rhs)
          self.x86_emit_setcc_r8(Eq, rd) // Z
          self.x86_emit_setcc_r8(Pc, scratch) // NP (parity clear)
          self.x86_emit_movzx_r32_r8(rd, rd)
          self.x86_emit_movzx_r32_r8(scratch, scratch)
          self.x86_emit_and_rr32(rd, scratch)
        }
        Ne => {
          emit_ucomis(self, is_f32, lhs, rhs)
          self.x86_emit_setcc_r8(Ne, rd) // NZ
          self.x86_emit_setcc_r8(Ps, scratch) // P (parity set)
          self.x86_emit_movzx_r32_r8(rd, rd)
          self.x86_emit_movzx_r32_r8(scratch, scratch)
          self.x86_emit_or_rr32(rd, scratch)
        }
        Gt => {
          emit_ucomis(self, is_f32, lhs, rhs)
          self.x86_emit_setcc_r8(Hi, rd) // NBE (ordered >)
          self.x86_emit_movzx_r32_r8(rd, rd)
        }
        Ge => {
          emit_ucomis(self, is_f32, lhs, rhs)
          self.x86_emit_setcc_r8(Hs, rd) // NB (ordered >=)
          self.x86_emit_movzx_r32_r8(rd, rd)
        }
        Lt => {
          emit_ucomis(self, is_f32, rhs, lhs)
          self.x86_emit_setcc_r8(Hi, rd) // NBE (ordered <)
          self.x86_emit_movzx_r32_r8(rd, rd)
        }
        Le => {
          emit_ucomis(self, is_f32, rhs, lhs)
          self.x86_emit_setcc_r8(Hs, rd) // NB (ordered <=)
          self.x86_emit_movzx_r32_r8(rd, rd)
        }
      }
    }
    FpuCmp(is_f32) => {
      // Floating-point compare that only sets flags (no result).
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        self.x86_emit_ucomiss_xmm_xmm(rn, rm)
      } else {
        self.x86_emit_ucomisd_xmm_xmm(rn, rm)
      }
    }
    FpuSel(_is_f32, cond) => {
      // Select between two XMM values based on flags from the preceding compare.
      let rd = wreg_num(inst.defs[0])
      let true_reg = reg_num(inst.uses[0])
      let false_reg = reg_num(inst.uses[1])
      if rd != false_reg {
        self.x86_emit_movaps_xmm_xmm(rd, false_reg)
      }
      let done = self.new_internal_label()
      self.x86_emit_jcc_rel32(cond.invert(), done)
      if rd != true_reg {
        self.x86_emit_movaps_xmm_xmm(rd, true_reg)
      }
      self.define_label(done)
    }
    FpuMaxnm(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let lhs = reg_num(inst.uses[0])
      let rhs = reg_num(inst.uses[1])
      emit_scalar_min_max_seq(self, is_f32, false, rd, lhs, rhs)
    }
    FpuMinnm(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let lhs = reg_num(inst.uses[0])
      let rhs = reg_num(inst.uses[1])
      emit_scalar_min_max_seq(self, is_f32, true, rd, lhs, rhs)
    }
    TrapIf(cond, trap_code) => {
      // Trap if condition is true (based on the most recent flags).
      if cond is Al {
        self.x86_emit_trap_imm16(trap_code)
        return
      }
      let done = self.new_internal_label()
      self.x86_emit_jcc_rel32(cond.invert(), done)
      self.x86_emit_trap_imm16(trap_code)
      self.define_label(done)
    }
    TrapIfUgt(trap_code) => {
      // Trap if lhs > rhs (unsigned).
      let lhs = reg_num(inst.uses[0])
      let rhs = reg_num(inst.uses[1])
      self.x86_emit_cmp_rr(lhs, rhs)
      let done = self.new_internal_label()
      self.x86_emit_jcc_rel32(Ls, done)
      self.x86_emit_trap_imm16(trap_code)
      self.define_label(done)
    }
    TrapIfUge(trap_code) => {
      // Trap if lhs >= rhs (unsigned).
      let lhs = reg_num(inst.uses[0])
      let rhs = reg_num(inst.uses[1])
      self.x86_emit_cmp_rr(lhs, rhs)
      let done = self.new_internal_label()
      self.x86_emit_jcc_rel32(Lo, done)
      self.x86_emit_trap_imm16(trap_code)
      self.define_label(done)
    }
    TypeCheckIndirect(expected_type) => {
      // Check if actual_type == expected_type, trap if not.
      //
      // Uses: [actual_type_vreg]
      let actual_type_reg = reg_num(inst.uses[0])
      self.x86_emit_cmp_r32_imm32(actual_type_reg, expected_type)
      let ok = self.new_internal_label()
      self.x86_emit_jcc_rel32(Eq, ok)
      // Trap code matches the AArch64 brk immediate used for indirect-call type
      // mismatch.
      self.x86_emit_trap_imm16(2)
      self.define_label(ok)
    }
    TypeCheckSubtypeIndirect(expected_type, helper_symbol) => {
      // Fast path for call_indirect type checks:
      // - If actual_type == expected_type: do nothing.
      // - Otherwise: call the runtime subtype checker (traps on failure).
      //
      // Uses: [actual_type_vreg]
      let actual_type_reg = reg_num(inst.uses[0])
      self.x86_emit_cmp_r32_imm32(actual_type_reg, expected_type)
      let done = self.new_internal_label()
      self.x86_emit_jcc_rel32(Eq, done)

      // Slow path: call gc_type_check_subtype_impl(actual, expected).
      // SysV AMD64 args: rdi, rsi.
      let arg0 = 7 // rdi
      let arg1 = 6 // rsi
      self.x86_emit_mov_rr32(arg0, actual_type_reg)
      self.x86_emit_mov_imm64(arg1, expected_type.to_int64())
      let scratch = isa.scratch_reg_1_index()
      let fixup_offset = self.current_pos()
      self.x86_emit_mov_imm64(scratch, 0L)
      self.add_external_func_addr_fixup(fixup_offset, helper_symbol, scratch)
      self.x86_emit_call_r64(scratch)
      self.define_label(done)
    }
    Extend(kind) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match kind {
        Signed8To32 => self.x86_emit_movsx_r32_r8(rd, rn)
        Signed8To64 => self.x86_emit_movsx_r64_r8(rd, rn)
        Signed16To32 => self.x86_emit_movsx_r32_r16(rd, rn)
        Signed16To64 => self.x86_emit_movsx_r64_r16(rd, rn)
        Signed32To64 => self.x86_emit_movsxd_r64_r32(rd, rn)
        Unsigned8To32 | Unsigned8To64 => self.x86_emit_movzx_r32_r8(rd, rn)
        Unsigned16To32 | Unsigned16To64 => self.x86_emit_movzx_r32_r16(rd, rn)
        Unsigned32To64 => self.x86_emit_mov_rr32(rd, rn)
      }
    }
    Truncate => {
      // i64 -> i32 truncation: write through a 32-bit move to clear upper bits.
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if rd != rn {
        self.x86_emit_mov_rr32(rd, rn)
      }
    }
    Nop => ()
    FPromote => {
      // f32 -> f64
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.x86_emit_cvtss2sd_xmm_xmm(rd, rn)
    }
    FDemote => {
      // f64 -> f32
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.x86_emit_cvtsd2ss_xmm_xmm(rd, rn)
    }
    IntToFloat(kind) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match kind {
        I32SToF32 => self.x86_emit_cvtsi2ss_xmm_r32(rd, rn)
        I32SToF64 => self.x86_emit_cvtsi2sd_xmm_r32(rd, rn)
        I64SToF32 => self.x86_emit_cvtsi2ss_xmm_r64(rd, rn)
        I64SToF64 => self.x86_emit_cvtsi2sd_xmm_r64(rd, rn)
        // u32 fits in signed i64 when zero-extended; use the r64 form.
        I32UToF32 => self.x86_emit_cvtsi2ss_xmm_r64(rd, rn)
        I32UToF64 => self.x86_emit_cvtsi2sd_xmm_r64(rd, rn)
        I64UToF32 | I64UToF64 => {
          let scratch1 = isa.scratch_reg_1_index()
          let scratch2 = isa.scratch_reg_2_index()
          // Match Cranelift x64 `CvtUint64ToFloatSeq`:
          // - if src is non-negative, signed conversion is fine
          // - else convert (src>>1 | src&1) as signed and double the float result
          let nonneg = self.new_internal_label()
          let done = self.new_internal_label()
          self.x86_emit_test_rr(rn, rn)
          self.x86_emit_jcc_rel32(Pl, nonneg) // JNS

          // scratch1 = src >> 1
          self.x86_emit_mov_rr(scratch1, rn)
          self.x86_emit_shr_r_imm8(scratch1, 1)

          // scratch2 = src & 1
          self.x86_emit_mov_rr(scratch2, rn)
          self.x86_emit_and_r_imm8_sxb64(scratch2, 1)

          // scratch2 = (src>>1) | (src&1)
          self.x86_emit_or_rr(scratch2, scratch1)

          // dst = cvt(scratch2); dst += dst
          if kind is I64UToF32 {
            self.x86_emit_cvtsi2ss_xmm_r64(rd, scratch2)
            self.x86_emit_addss_xmm_xmm(rd, rd)
          } else {
            self.x86_emit_cvtsi2sd_xmm_r64(rd, scratch2)
            self.x86_emit_addsd_xmm_xmm(rd, rd)
          }
          self.x86_emit_jmp_rel32(done)
          self.define_label(nonneg)
          if kind is I64UToF32 {
            self.x86_emit_cvtsi2ss_xmm_r64(rd, rn)
          } else {
            self.x86_emit_cvtsi2sd_xmm_r64(rd, rn)
          }
          self.define_label(done)
        }
      }
    }
    Bitcast => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let dst_class = reg_class_of_w(inst.defs[0])
      let src_class = reg_class_of(inst.uses[0])
      match (dst_class, src_class) {
        (Int, Float32) => self.x86_emit_movd_r32_xmm(rd, rn)
        (Int, Float64) => self.x86_emit_movq_r64_xmm(rd, rn)
        (Float32, Int) => self.x86_emit_movd_xmm_r32(rd, rn)
        (Float64, Int) => self.x86_emit_movq_xmm_r64(rd, rn)
        _ => abort("x86_64 Bitcast: unsupported reg class combination")
      }
    }
    FcvtToInt(is_f32, is_i64, is_signed) => {
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
        self.x86_emit_jcc_rel32(Vc, done) // JNO

        // NaN => 0
        emit_ucomis(self, is_f32, src_xmm, src_xmm)
        self.x86_emit_jcc_rel32(Pc, not_nan) // JNP
        emit_xor_self(self, is_i64, dst)
        self.x86_emit_jmp_rel32(done)
        self.define_label(not_nan)

        // If src <= 0, keep INT_MIN (already in dst); else saturate to INT_MAX.
        self.x86_emit_xorpd_xmm_xmm(tmp_xmm, tmp_xmm)
        emit_ucomis(self, is_f32, tmp_xmm, src_xmm)
        self.x86_emit_jcc_rel32(Hs, done) // JAE
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
        self.x86_emit_jcc_rel32(Hs, handle_large) // JAE/JNB

        // NaN => 0
        self.x86_emit_jcc_rel32(Pc, not_nan) // JNP
        emit_xor_self(self, is_i64, dst)
        self.x86_emit_jmp_rel32(done)
        self.define_label(not_nan)

        // Small path: cvtt + if result >= 0 then done else 0.
        emit_cvtt(self, is_f32, is_i64, dst, src_xmm)
        emit_cmp_imm(self, is_i64, dst, 0)
        self.x86_emit_jcc_rel32(Ge, done) // JGE
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
        self.x86_emit_jcc_rel32(Ge, next_is_large)
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
    Shl(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = match inst.use_constraints[1] {
        FixedReg(preg) => preg.index
        _ => reg_num(inst.uses[1])
      }
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
    ShlImm(amt, is_64) => {
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
    LShr(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = match inst.use_constraints[1] {
        FixedReg(preg) => preg.index
        _ => reg_num(inst.uses[1])
      }
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
    LShrImm(amt, is_64) => {
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
    AShr(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = match inst.use_constraints[1] {
        FixedReg(preg) => preg.index
        _ => reg_num(inst.uses[1])
      }
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
    AShrImm(amt, is_64) => {
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
    Rotr(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = match inst.use_constraints[1] {
        FixedReg(preg) => preg.index
        _ => reg_num(inst.uses[1])
      }
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
    RotrImm(amt, is_64) => {
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
    ExtrImm(amt, is_64) => {
      // AArch64 EXTR fallback on amd64:
      //   (rn << (bits - amt)) | (rm >> amt)
      // with shift domain masked per lane width.
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      let bits = if is_64 { 64 } else { 32 }
      let amt_masked = if is_64 { amt & 63 } else { amt & 31 }
      if amt_masked == 0 {
        if is_64 {
          if rd != rm {
            self.x86_emit_mov_rr(rd, rm)
          }
        } else if rd != rm {
          self.x86_emit_mov_rr32(rd, rm)
        }
        return
      }
      let mut tmp = isa.scratch_reg_1_index()
      if tmp == rd || tmp == rn || tmp == rm {
        tmp = isa.scratch_reg_2_index()
      }
      if tmp == rd || tmp == rn || tmp == rm {
        abort("x86_64 extr_imm: no scratch register available")
      }
      if is_64 {
        self.x86_emit_mov_rr(tmp, rm)
        self.x86_emit_shr_r_imm8(tmp, amt_masked)
        if rd != rn {
          self.x86_emit_mov_rr(rd, rn)
        }
        self.x86_emit_shl_r_imm8(rd, bits - amt_masked)
        self.x86_emit_or_rr(rd, tmp)
      } else {
        self.x86_emit_mov_rr32(tmp, rm)
        self.x86_emit_shr_r32_imm8(tmp, amt_masked)
        if rd != rn {
          self.x86_emit_mov_rr32(rd, rn)
        }
        self.x86_emit_shl_r32_imm8(rd, bits - amt_masked)
        self.x86_emit_or_rr32(rd, tmp)
      }
    }
    Select => {
      let rd = wreg_num(inst.defs[0])
      let cond_reg = reg_num(inst.uses[0])
      let true_reg = reg_num(inst.uses[1])
      let false_reg = reg_num(inst.uses[2])
      let class = reg_class_of_w(inst.defs[0])
      match class {
        // Match Cranelift x64: integer select uses cmov.
        Int => {
          // Set flags based on cond != 0.
          self.x86_emit_test_rr32(cond_reg, cond_reg)
          // Avoid clobbering `true_reg` when `rd` aliases it.
          if rd == true_reg {
            // Keep `true` in place and overwrite with `false` only on cond == 0.
            self.x86_emit_cmovcc_rr(Eq, rd, false_reg)
          } else {
            // dst = false
            emit_reg_move(self, rd, false_reg, class)
            // dst = cond ? true : dst
            self.x86_emit_cmovcc_rr(Ne, rd, true_reg)
          }
        }
        // Match Cranelift x64: XMM select uses a branch (no cmov for XMM).
        Float32 | Float64 | Vector => {
          self.x86_emit_test_rr32(cond_reg, cond_reg)
          if rd == true_reg {
            // Keep `true` in place and overwrite with `false` only on cond == 0.
            let next = self.new_internal_label()
            self.x86_emit_jcc_rel32(Ne, next)
            emit_reg_move(self, rd, false_reg, class)
            self.define_label(next)
          } else {
            // dst = false
            emit_reg_move(self, rd, false_reg, class)
            let next = self.new_internal_label()
            self.x86_emit_jcc_rel32(Eq, next)
            emit_reg_move(self, rd, true_reg, class)
            self.define_label(next)
          }
        }
      }
    }
    SelectCmp(kind, is_64) => {
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
        Int =>
          if rd == true_reg {
            // Keep `true` in place and overwrite with `false` only when cond is false.
            if is_64 {
              self.x86_emit_cmovcc_rr(cond.invert(), rd, false_reg)
            } else {
              self.x86_emit_cmovcc_rr32(cond.invert(), rd, false_reg)
            }
          } else {
            emit_reg_move(self, rd, false_reg, class)
            if is_64 {
              self.x86_emit_cmovcc_rr(cond, rd, true_reg)
            } else {
              self.x86_emit_cmovcc_rr32(cond, rd, true_reg)
            }
          }
        // XMM: branch-based move (no cmov).
        Float32 | Float64 | Vector =>
          if rd == true_reg {
            let next = self.new_internal_label()
            self.x86_emit_jcc_rel32(cond, next)
            emit_reg_move(self, rd, false_reg, class)
            self.define_label(next)
          } else {
            emit_reg_move(self, rd, false_reg, class)
            let next = self.new_internal_label()
            self.x86_emit_jcc_rel32(cond.invert(), next)
            emit_reg_move(self, rd, true_reg, class)
            self.define_label(next)
          }
      }
    }
    TrapIfZero(is_64, trap_code) => {
      let rn = reg_num(inst.uses[0])
      if is_64 {
        self.x86_emit_test_rr(rn, rn)
      } else {
        self.x86_emit_test_rr32(rn, rn)
      }
      let done_l = self.new_internal_label()
      self.x86_emit_jcc_rel32(Ne, done_l)
      self.x86_emit_trap_imm16(trap_code)
      self.define_label(done_l)
    }
    TrapIfDivOverflow(is_64, trap_code) => {
      // Trap if lhs == INT_MIN && rhs == -1.
      let lhs = reg_num(inst.uses[0])
      let rhs = reg_num(inst.uses[1])
      let done_l = self.new_internal_label()
      if is_64 {
        // Cranelift-aligned guard shape for checked sdiv:
        // only overflow candidate is divisor == -1 and dividend == INT_MIN.
        self.x86_emit_cmp_r_imm32(rhs, -1)
        self.x86_emit_jcc_rel32(Ne, done_l)
        let scratch = pick_scratch_gpr(isa, lhs, rhs, -1, -1)
        self.x86_emit_mov_imm64(scratch, 0x8000000000000000L)
        self.x86_emit_cmp_rr(lhs, scratch)
        self.x86_emit_jcc_rel32(Ne, done_l)
      } else {
        self.x86_emit_cmp_r32_imm32(rhs, -1)
        self.x86_emit_jcc_rel32(Ne, done_l)
        self.x86_emit_cmp_r32_imm32(lhs, -2147483648)
        self.x86_emit_jcc_rel32(Ne, done_l)
      }
      self.x86_emit_trap_imm16(trap_code)
      self.define_label(done_l)
    }
    SDiv(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let lhs = reg_num(inst.uses[0])
      let rhs = reg_num(inst.uses[1])

      // Preserve divisor if it lives in rax/rdx, since those are overwritten.
      let mut divisor = rhs
      if rhs == 0 || rhs == 2 {
        let scratch = pick_scratch_gpr(isa, lhs, rhs, rd, -1)
        if is_64 {
          self.x86_emit_mov_rr(scratch, rhs)
        } else {
          self.x86_emit_mov_rr32(scratch, rhs)
        }
        divisor = scratch
      }

      // Move dividend into rax and sign-extend into rdx.
      if lhs != 0 {
        if is_64 {
          self.x86_emit_mov_rr(0, lhs)
        } else {
          self.x86_emit_mov_rr32(0, lhs)
        }
      }
      if is_64 {
        self.x86_emit_cqo()
        self.x86_emit_idiv_r64(divisor)
      } else {
        self.x86_emit_cdq()
        self.x86_emit_idiv_r32(divisor)
      }
      if rd != 0 {
        if is_64 {
          self.x86_emit_mov_rr(rd, 0)
        } else {
          self.x86_emit_mov_rr32(rd, 0)
        }
      }
    }
    UDiv(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let lhs = reg_num(inst.uses[0])
      let rhs = reg_num(inst.uses[1])

      let mut divisor = rhs
      if rhs == 0 || rhs == 2 {
        let scratch = pick_scratch_gpr(isa, lhs, rhs, rd, -1)
        if is_64 {
          self.x86_emit_mov_rr(scratch, rhs)
        } else {
          self.x86_emit_mov_rr32(scratch, rhs)
        }
        divisor = scratch
      }
      if lhs != 0 {
        if is_64 {
          self.x86_emit_mov_rr(0, lhs)
        } else {
          self.x86_emit_mov_rr32(0, lhs)
        }
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
    SRem(is_64) => {
      // Match Cranelift x64 CheckedSRemSeq behavior: guard `divisor == -1` and
      // return 0 without executing IDIV (avoids INT_MIN/-1 overflow trap).
      let rd = wreg_num(inst.defs[0])
      let lhs = reg_num(inst.uses[0])
      let rhs = reg_num(inst.uses[1])

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
      self.x86_emit_jcc_rel32(Ne, do_idiv)
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
        let scratch = pick_scratch_gpr(isa, lhs, rhs, rd, -1)
        if is_64 {
          self.x86_emit_mov_rr(scratch, rhs)
        } else {
          self.x86_emit_mov_rr32(scratch, rhs)
        }
        divisor = scratch
      }
      if lhs != 0 {
        if is_64 {
          self.x86_emit_mov_rr(0, lhs)
        } else {
          self.x86_emit_mov_rr32(0, lhs)
        }
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
    URem(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let lhs = reg_num(inst.uses[0])
      let rhs = reg_num(inst.uses[1])
      if rd != 2 {
        abort("x86_64 URem: expected dst in rdx")
      }

      // Preserve divisor if it conflicts with rax/rdx.
      let mut divisor = rhs
      if rhs == 0 || rhs == 2 {
        let scratch = pick_scratch_gpr(isa, lhs, rhs, rd, -1)
        if is_64 {
          self.x86_emit_mov_rr(scratch, rhs)
        } else {
          self.x86_emit_mov_rr32(scratch, rhs)
        }
        divisor = scratch
      }
      if lhs != 0 {
        if is_64 {
          self.x86_emit_mov_rr(0, lhs)
        } else {
          self.x86_emit_mov_rr32(0, lhs)
        }
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
    LoadMemBase(memidx) => {
      // Load linear memory base pointer from VMContext.
      // Uses: [vmctx], Defs: [result]
      let layout = stack_frame.require_runtime_layout()
      let dst = wreg_num(inst.defs[0])
      let vmctx_reg = reg_num(inst.uses[0])
      if memidx == 0 && stack_frame.cache_mem0_desc {
        // Fast path: memory0 descriptor pointer is cached in Mem0Desc role.
        self.x86_emit_mov_r64_m64(dst, @isaregs.mem0_desc_index(), 0)
      } else if memidx == 0 {
        self.x86_emit_mov_r64_m64(
          dst,
          vmctx_reg,
          layout.primary_memory_base_offset,
        )
      } else {
        self.x86_emit_mov_r64_m64(
          dst,
          vmctx_reg,
          layout.memory_directory_offset,
        )
        self.x86_emit_mov_r64_m64(dst, dst, memidx * layout.pointer_stride)
        self.x86_emit_mov_r64_m64(dst, dst, 0)
      }
    }
    Load(ty, offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if stack_frame.runtime_layout is Some(layout) {
        if stack_frame.cache_func_table &&
          ty is I64 &&
          rn == @isaregs.vmctx_index() &&
          offset == layout.function_table_offset {
          let ft = @isaregs.func_table_index()
          if rt != ft {
            self.x86_emit_mov_rr(rt, ft)
          }
          return
        }
      }
      match ty {
        I32 => self.x86_emit_mov_r32_m32(rt, rn, offset)
        I64 => self.x86_emit_mov_r64_m64(rt, rn, offset)
        F32 => self.x86_emit_movss_xmm_m32(rt, rn, offset)
        F64 => self.x86_emit_movsd_xmm_m64(rt, rn, offset)
        V128 => self.x86_emit_movdqu_xmm_m128(rt, rn, offset)
      }
    }
    Store(ty, offset) => {
      let rn = reg_num(inst.uses[0])
      let rt = reg_num(inst.uses[1])
      match ty {
        I32 => self.x86_emit_mov_m32_r32(rn, offset, rt)
        I64 => self.x86_emit_mov_m64_r64(rn, offset, rt)
        F32 => self.x86_emit_movss_m32_xmm(rn, offset, rt)
        F64 => self.x86_emit_movsd_m64_xmm(rn, offset, rt)
        V128 => self.x86_emit_movdqu_m128_xmm(rn, offset, rt)
      }
    }
    LoadPtr(ty, offset) => {
      // Raw pointer load (no bounds checking).
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match ty {
        I32 => self.x86_emit_mov_r32_m32(rt, rn, offset)
        I64 => self.x86_emit_mov_r64_m64(rt, rn, offset)
        F32 => self.x86_emit_movss_xmm_m32(rt, rn, offset)
        F64 => self.x86_emit_movsd_xmm_m64(rt, rn, offset)
        V128 => self.x86_emit_movdqu_xmm_m128(rt, rn, offset)
      }
    }
    LoadPtrRegOffset(ty, ext, shift, offset) => {
      // Raw pointer load with scaled index addressing (Cranelift-style sinkable load).
      let rt = wreg_num(inst.defs[0])
      let base = reg_num(inst.uses[0])
      let index = reg_num(inst.uses[1])
      let can_use_scaled_amode = shift >= 0 && shift <= 3
      let rt_gpr_avoid = match ty {
        I32 | I64 => rt
        _ => -1
      }
      let s1 = isa.scratch_reg_1_index()
      let s2 = isa.scratch_reg_2_index()
      let scratch_blocked = (s1 == base || s1 == index || s1 == rt_gpr_avoid) &&
        (s2 == base || s2 == index || s2 == rt_gpr_avoid)
      if scratch_blocked &&
        try_emit_int_load_with_dst_tmp(
          self, ty, rt, base, index, ext, shift, offset, can_use_scaled_amode,
        ) {
        return
      }
      if can_use_scaled_amode {
        if ext is None && (index & 7) != 4 {
          match ty {
            I32 =>
              self.x86_emit_mov_r32_m32_base_index_scale_disp(
                rt, base, index, shift, offset,
              )
            I64 =>
              self.x86_emit_mov_r64_m64_base_index_scale_disp(
                rt, base, index, shift, offset,
              )
            F32 =>
              self.x86_emit_movss_xmm_m32_base_index_scale_disp(
                rt, base, index, shift, offset,
              )
            F64 =>
              self.x86_emit_movsd_xmm_m64_base_index_scale_disp(
                rt, base, index, shift, offset,
              )
            V128 =>
              self.x86_emit_movdqu_xmm_m128_base_index_scale_disp(
                rt, base, index, shift, offset,
              )
          }
          return
        }
        if ext is None && shift == 0 && (index & 7) == 4 && (base & 7) != 4 {
          // Cranelift to_amode_add style commutative swap for iadd with scale=1:
          // avoid scratch when only index-register legality blocks encoding.
          match ty {
            I32 =>
              self.x86_emit_mov_r32_m32_base_index_scale_disp(
                rt, index, base, 0, offset,
              )
            I64 =>
              self.x86_emit_mov_r64_m64_base_index_scale_disp(
                rt, index, base, 0, offset,
              )
            F32 =>
              self.x86_emit_movss_xmm_m32_base_index_scale_disp(
                rt, index, base, 0, offset,
              )
            F64 =>
              self.x86_emit_movsd_xmm_m64_base_index_scale_disp(
                rt, index, base, 0, offset,
              )
            V128 =>
              self.x86_emit_movdqu_xmm_m128_base_index_scale_disp(
                rt, index, base, 0, offset,
              )
          }
          return
        }
        let idx = pick_scratch_gpr(isa, base, index, rt_gpr_avoid, -1)
        match ext {
          None => self.x86_emit_mov_rr(idx, index)
          Uxtw => self.x86_emit_mov_rr32(idx, index)
          Sxtw => self.x86_emit_movsxd_r64_r32(idx, index)
        }
        if (idx & 7) != 4 {
          match ty {
            I32 =>
              self.x86_emit_mov_r32_m32_base_index_scale_disp(
                rt, base, idx, shift, offset,
              )
            I64 =>
              self.x86_emit_mov_r64_m64_base_index_scale_disp(
                rt, base, idx, shift, offset,
              )
            F32 =>
              self.x86_emit_movss_xmm_m32_base_index_scale_disp(
                rt, base, idx, shift, offset,
              )
            F64 =>
              self.x86_emit_movsd_xmm_m64_base_index_scale_disp(
                rt, base, idx, shift, offset,
              )
            V128 =>
              self.x86_emit_movdqu_xmm_m128_base_index_scale_disp(
                rt, base, idx, shift, offset,
              )
          }
          return
        }
      }
      let idx = pick_scratch_gpr(isa, base, index, rt_gpr_avoid, -1)
      self.x86_emit_mov_rr(idx, index)
      match ext {
        None => ()
        Uxtw => self.x86_emit_mov_rr32(idx, idx)
        Sxtw => self.x86_emit_movsxd_r64_r32(idx, idx)
      }
      if shift > 0 {
        self.x86_emit_shl_r_imm8(idx, shift)
      }
      if (idx & 7) != 4 {
        match ty {
          I32 =>
            self.x86_emit_mov_r32_m32_base_index_scale_disp(
              rt, base, idx, 0, offset,
            )
          I64 =>
            self.x86_emit_mov_r64_m64_base_index_scale_disp(
              rt, base, idx, 0, offset,
            )
          F32 =>
            self.x86_emit_movss_xmm_m32_base_index_scale_disp(
              rt, base, idx, 0, offset,
            )
          F64 =>
            self.x86_emit_movsd_xmm_m64_base_index_scale_disp(
              rt, base, idx, 0, offset,
            )
          V128 =>
            self.x86_emit_movdqu_xmm_m128_base_index_scale_disp(
              rt, base, idx, 0, offset,
            )
        }
        return
      }
      self.x86_emit_add_rr(idx, base)
      match ty {
        I32 => self.x86_emit_mov_r32_m32(rt, idx, offset)
        I64 => self.x86_emit_mov_r64_m64(rt, idx, offset)
        F32 => self.x86_emit_movss_xmm_m32(rt, idx, offset)
        F64 => self.x86_emit_movsd_xmm_m64(rt, idx, offset)
        V128 => self.x86_emit_movdqu_xmm_m128(rt, idx, offset)
      }
    }
    LoadPtrNarrowRegOffset(bits, signed, ext, shift, offset) => {
      // Raw pointer narrow load with register-offset addressing.
      let rt = wreg_num(inst.defs[0])
      let base = reg_num(inst.uses[0])
      let index = reg_num(inst.uses[1])
      let can_use_scaled_amode = shift >= 0 && shift <= 3
      if can_use_scaled_amode && ext is None && (index & 7) != 4 {
        match (bits, signed) {
          (8, true) =>
            self.x86_emit_movsx_r64_m8_base_index_scale_disp(
              rt, base, index, shift, offset,
            )
          (8, false) =>
            self.x86_emit_movzx_r32_m8_base_index_scale_disp(
              rt, base, index, shift, offset,
            )
          (16, true) =>
            self.x86_emit_movsx_r64_m16_base_index_scale_disp(
              rt, base, index, shift, offset,
            )
          (16, false) =>
            self.x86_emit_movzx_r32_m16_base_index_scale_disp(
              rt, base, index, shift, offset,
            )
          (32, true) => {
            self.x86_emit_mov_r32_m32_base_index_scale_disp(
              rt, base, index, shift, offset,
            )
            self.x86_emit_movsxd_r64_r32(rt, rt)
          }
          (32, false) =>
            self.x86_emit_mov_r32_m32_base_index_scale_disp(
              rt, base, index, shift, offset,
            )
          _ => abort("x86_64 LoadPtrNarrowRegOffset: unsupported bits \{bits}")
        }
        return
      }
      if can_use_scaled_amode &&
        ext is None &&
        shift == 0 &&
        (index & 7) == 4 &&
        (base & 7) != 4 {
        match (bits, signed) {
          (8, true) =>
            self.x86_emit_movsx_r64_m8_base_index_scale_disp(
              rt, index, base, 0, offset,
            )
          (8, false) =>
            self.x86_emit_movzx_r32_m8_base_index_scale_disp(
              rt, index, base, 0, offset,
            )
          (16, true) =>
            self.x86_emit_movsx_r64_m16_base_index_scale_disp(
              rt, index, base, 0, offset,
            )
          (16, false) =>
            self.x86_emit_movzx_r32_m16_base_index_scale_disp(
              rt, index, base, 0, offset,
            )
          (32, true) => {
            self.x86_emit_mov_r32_m32_base_index_scale_disp(
              rt, index, base, 0, offset,
            )
            self.x86_emit_movsxd_r64_r32(rt, rt)
          }
          (32, false) =>
            self.x86_emit_mov_r32_m32_base_index_scale_disp(
              rt, index, base, 0, offset,
            )
          _ => abort("x86_64 LoadPtrNarrowRegOffset: unsupported bits \{bits}")
        }
        return
      }
      let idx = pick_scratch_gpr(isa, base, index, rt, -1)
      self.x86_emit_mov_rr(idx, index)
      match ext {
        None => ()
        Uxtw => self.x86_emit_mov_rr32(idx, idx)
        Sxtw => self.x86_emit_movsxd_r64_r32(idx, idx)
      }
      if can_use_scaled_amode && (idx & 7) != 4 {
        match (bits, signed) {
          (8, true) =>
            self.x86_emit_movsx_r64_m8_base_index_scale_disp(
              rt, base, idx, shift, offset,
            )
          (8, false) =>
            self.x86_emit_movzx_r32_m8_base_index_scale_disp(
              rt, base, idx, shift, offset,
            )
          (16, true) =>
            self.x86_emit_movsx_r64_m16_base_index_scale_disp(
              rt, base, idx, shift, offset,
            )
          (16, false) =>
            self.x86_emit_movzx_r32_m16_base_index_scale_disp(
              rt, base, idx, shift, offset,
            )
          (32, true) => {
            self.x86_emit_mov_r32_m32_base_index_scale_disp(
              rt, base, idx, shift, offset,
            )
            self.x86_emit_movsxd_r64_r32(rt, rt)
          }
          (32, false) =>
            self.x86_emit_mov_r32_m32_base_index_scale_disp(
              rt, base, idx, shift, offset,
            )
          _ => abort("x86_64 LoadPtrNarrowRegOffset: unsupported bits \{bits}")
        }
        return
      }
      if shift > 0 {
        self.x86_emit_shl_r_imm8(idx, shift)
      }
      if (idx & 7) != 4 {
        match (bits, signed) {
          (8, true) => {
            self.x86_emit_movsx_r64_m8_base_index_scale_disp(
              rt, base, idx, 0, offset,
            )
            return
          }
          (8, false) => {
            self.x86_emit_movzx_r32_m8_base_index_scale_disp(
              rt, base, idx, 0, offset,
            )
            return
          }
          (16, true) => {
            self.x86_emit_movsx_r64_m16_base_index_scale_disp(
              rt, base, idx, 0, offset,
            )
            return
          }
          (16, false) => {
            self.x86_emit_movzx_r32_m16_base_index_scale_disp(
              rt, base, idx, 0, offset,
            )
            return
          }
          (32, true) => {
            self.x86_emit_mov_r32_m32_base_index_scale_disp(
              rt, base, idx, 0, offset,
            )
            self.x86_emit_movsxd_r64_r32(rt, rt)
            return
          }
          (32, false) => {
            self.x86_emit_mov_r32_m32_base_index_scale_disp(
              rt, base, idx, 0, offset,
            )
            return
          }
          _ => ()
        }
      }
      self.x86_emit_add_rr(idx, base)
      match (bits, signed) {
        (8, true) => self.x86_emit_movsx_r64_m8(rt, idx, offset)
        (8, false) => self.x86_emit_movzx_r32_m8(rt, idx, offset)
        (16, true) => self.x86_emit_movsx_r64_m16(rt, idx, offset)
        (16, false) => self.x86_emit_movzx_r32_m16(rt, idx, offset)
        (32, true) => self.x86_emit_movsxd_r64_m32(rt, idx, offset)
        (32, false) => self.x86_emit_mov_r32_m32(rt, idx, offset)
        _ => abort("x86_64 LoadPtrNarrowRegOffset: unsupported bits \{bits}")
      }
    }
    StorePtr(ty, offset) => {
      // Raw pointer store (no bounds checking).
      let rn = reg_num(inst.uses[0])
      let rt = reg_num(inst.uses[1])
      match ty {
        I32 => self.x86_emit_mov_m32_r32(rn, offset, rt)
        I64 => self.x86_emit_mov_m64_r64(rn, offset, rt)
        F32 => self.x86_emit_movss_m32_xmm(rn, offset, rt)
        F64 => self.x86_emit_movsd_m64_xmm(rn, offset, rt)
        V128 => self.x86_emit_movdqu_m128_xmm(rn, offset, rt)
      }
    }
    StorePtrRegOffset(ty, ext, shift, offset) => {
      // Raw pointer store with scaled index addressing.
      let base = reg_num(inst.uses[0])
      let index = reg_num(inst.uses[1])
      let value = reg_num(inst.uses[2])
      let value_gpr_avoid = match ty {
        I32 | I64 => value
        _ => -1
      }
      let can_use_scaled_amode = shift >= 0 && shift <= 3
      if can_use_scaled_amode {
        if ext is None && (index & 7) != 4 {
          match ty {
            I32 =>
              self.x86_emit_mov_m32_r32_base_index_scale_disp(
                base, index, shift, offset, value,
              )
            I64 =>
              self.x86_emit_mov_m64_r64_base_index_scale_disp(
                base, index, shift, offset, value,
              )
            F32 =>
              self.x86_emit_movss_m32_xmm_base_index_scale_disp(
                base, index, shift, offset, value,
              )
            F64 =>
              self.x86_emit_movsd_m64_xmm_base_index_scale_disp(
                base, index, shift, offset, value,
              )
            V128 =>
              self.x86_emit_movdqu_m128_xmm_base_index_scale_disp(
                base, index, shift, offset, value,
              )
          }
          return
        }
        if ext is None && shift == 0 && (index & 7) == 4 && (base & 7) != 4 {
          match ty {
            I32 =>
              self.x86_emit_mov_m32_r32_base_index_scale_disp(
                index, base, 0, offset, value,
              )
            I64 =>
              self.x86_emit_mov_m64_r64_base_index_scale_disp(
                index, base, 0, offset, value,
              )
            F32 =>
              self.x86_emit_movss_m32_xmm_base_index_scale_disp(
                index, base, 0, offset, value,
              )
            F64 =>
              self.x86_emit_movsd_m64_xmm_base_index_scale_disp(
                index, base, 0, offset, value,
              )
            V128 =>
              self.x86_emit_movdqu_m128_xmm_base_index_scale_disp(
                index, base, 0, offset, value,
              )
          }
          return
        }
        let idx = pick_scratch_gpr(isa, base, index, value_gpr_avoid, -1)
        match ext {
          None => self.x86_emit_mov_rr(idx, index)
          Uxtw => self.x86_emit_mov_rr32(idx, index)
          Sxtw => self.x86_emit_movsxd_r64_r32(idx, index)
        }
        if (idx & 7) != 4 {
          match ty {
            I32 =>
              self.x86_emit_mov_m32_r32_base_index_scale_disp(
                base, idx, shift, offset, value,
              )
            I64 =>
              self.x86_emit_mov_m64_r64_base_index_scale_disp(
                base, idx, shift, offset, value,
              )
            F32 =>
              self.x86_emit_movss_m32_xmm_base_index_scale_disp(
                base, idx, shift, offset, value,
              )
            F64 =>
              self.x86_emit_movsd_m64_xmm_base_index_scale_disp(
                base, idx, shift, offset, value,
              )
            V128 =>
              self.x86_emit_movdqu_m128_xmm_base_index_scale_disp(
                base, idx, shift, offset, value,
              )
          }
          return
        }
      }
      let idx = pick_scratch_gpr(isa, base, index, value_gpr_avoid, -1)
      self.x86_emit_mov_rr(idx, index)
      match ext {
        None => ()
        Uxtw => self.x86_emit_mov_rr32(idx, idx)
        Sxtw => self.x86_emit_movsxd_r64_r32(idx, idx)
      }
      if shift > 0 {
        self.x86_emit_shl_r_imm8(idx, shift)
      }
      if (idx & 7) != 4 {
        match ty {
          I32 =>
            self.x86_emit_mov_m32_r32_base_index_scale_disp(
              base, idx, 0, offset, value,
            )
          I64 =>
            self.x86_emit_mov_m64_r64_base_index_scale_disp(
              base, idx, 0, offset, value,
            )
          F32 =>
            self.x86_emit_movss_m32_xmm_base_index_scale_disp(
              base, idx, 0, offset, value,
            )
          F64 =>
            self.x86_emit_movsd_m64_xmm_base_index_scale_disp(
              base, idx, 0, offset, value,
            )
          V128 =>
            self.x86_emit_movdqu_m128_xmm_base_index_scale_disp(
              base, idx, 0, offset, value,
            )
        }
        return
      }
      self.x86_emit_add_rr(idx, base)
      match ty {
        I32 => self.x86_emit_mov_m32_r32(idx, offset, value)
        I64 => self.x86_emit_mov_m64_r64(idx, offset, value)
        F32 => self.x86_emit_movss_m32_xmm(idx, offset, value)
        F64 => self.x86_emit_movsd_m64_xmm(idx, offset, value)
        V128 => self.x86_emit_movdqu_m128_xmm(idx, offset, value)
      }
    }
    StorePtrNarrowRegOffset(bits, ext, shift, offset) => {
      // Raw pointer narrow store with register-offset addressing.
      let base = reg_num(inst.uses[0])
      let index = reg_num(inst.uses[1])
      let value = reg_num(inst.uses[2])
      let can_use_scaled_amode = shift >= 0 && shift <= 3
      if can_use_scaled_amode && ext is None && (index & 7) != 4 {
        match bits {
          8 =>
            self.x86_emit_mov_m8_r8_base_index_scale_disp(
              base, index, shift, offset, value,
            )
          16 =>
            self.x86_emit_mov_m16_r16_base_index_scale_disp(
              base, index, shift, offset, value,
            )
          32 =>
            self.x86_emit_mov_m32_r32_base_index_scale_disp(
              base, index, shift, offset, value,
            )
          _ => abort("x86_64 StorePtrNarrowRegOffset: unsupported bits \{bits}")
        }
        return
      }
      if can_use_scaled_amode &&
        ext is None &&
        shift == 0 &&
        (index & 7) == 4 &&
        (base & 7) != 4 {
        match bits {
          8 =>
            self.x86_emit_mov_m8_r8_base_index_scale_disp(
              index, base, 0, offset, value,
            )
          16 =>
            self.x86_emit_mov_m16_r16_base_index_scale_disp(
              index, base, 0, offset, value,
            )
          32 =>
            self.x86_emit_mov_m32_r32_base_index_scale_disp(
              index, base, 0, offset, value,
            )
          _ => abort("x86_64 StorePtrNarrowRegOffset: unsupported bits \{bits}")
        }
        return
      }
      let idx = pick_scratch_gpr(isa, base, index, value, -1)
      self.x86_emit_mov_rr(idx, index)
      match ext {
        None => ()
        Uxtw => self.x86_emit_mov_rr32(idx, idx)
        Sxtw => self.x86_emit_movsxd_r64_r32(idx, idx)
      }
      if can_use_scaled_amode && (idx & 7) != 4 {
        match bits {
          8 =>
            self.x86_emit_mov_m8_r8_base_index_scale_disp(
              base, idx, shift, offset, value,
            )
          16 =>
            self.x86_emit_mov_m16_r16_base_index_scale_disp(
              base, idx, shift, offset, value,
            )
          32 =>
            self.x86_emit_mov_m32_r32_base_index_scale_disp(
              base, idx, shift, offset, value,
            )
          _ => abort("x86_64 StorePtrNarrowRegOffset: unsupported bits \{bits}")
        }
        return
      }
      if shift > 0 {
        self.x86_emit_shl_r_imm8(idx, shift)
      }
      if (idx & 7) != 4 {
        match bits {
          8 =>
            self.x86_emit_mov_m8_r8_base_index_scale_disp(
              base, idx, 0, offset, value,
            )
          16 =>
            self.x86_emit_mov_m16_r16_base_index_scale_disp(
              base, idx, 0, offset, value,
            )
          32 =>
            self.x86_emit_mov_m32_r32_base_index_scale_disp(
              base, idx, 0, offset, value,
            )
          _ => abort("x86_64 StorePtrNarrowRegOffset: unsupported bits \{bits}")
        }
        return
      }
      self.x86_emit_add_rr(idx, base)
      match bits {
        8 => self.x86_emit_mov_m8_r8(idx, offset, value)
        16 => self.x86_emit_mov_m16_r16(idx, offset, value)
        32 => self.x86_emit_mov_m32_r32(idx, offset, value)
        _ => abort("x86_64 StorePtrNarrowRegOffset: unsupported bits \{bits}")
      }
    }
    LoadPtrNarrow(bits, signed, offset) => {
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
    StorePtrNarrow(bits, offset) => {
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
    Load8S(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.x86_emit_movsx_r64_m8(rt, rn, offset)
    }
    Load8U(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.x86_emit_movzx_r32_m8(rt, rn, offset)
    }
    Load16S(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.x86_emit_movsx_r64_m16(rt, rn, offset)
    }
    Load16U(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.x86_emit_movzx_r32_m16(rt, rn, offset)
    }
    Load32S(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.x86_emit_movsxd_r64_m32(rt, rn, offset)
    }
    Load32U(offset) => {
      let rt = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      self.x86_emit_mov_r32_m32(rt, rn, offset)
    }
    LoadFuncAddr(func_idx) => {
      // Load function pointer from vmctx->func_table[func_idx].
      let rd = wreg_num(inst.defs[0])
      let vmctx = @isaregs.vmctx_index()
      let table = isa.scratch_reg_1_index()
      let layout = stack_frame.require_runtime_layout()
      self.x86_emit_mov_r64_m64(table, vmctx, layout.function_table_offset)
      self.x86_emit_mov_r64_m64(rd, table, func_idx * 8)
    }
    CallDirect(func_idx, _num_args, _num_results, _call_conv) => {
      // Call via vmctx->func_table[func_idx] to avoid rel32 patching.
      let vmctx = @isaregs.vmctx_index()
      let table = isa.scratch_reg_1_index()
      let callee = isa.scratch_reg_2_index()
      let layout = stack_frame.require_runtime_layout()
      self.x86_emit_mov_r64_m64(table, vmctx, layout.function_table_offset)
      self.x86_emit_mov_r64_m64(callee, table, func_idx * 8)
      self.x86_emit_call_r64(callee)
    }
    CallExternal(symbol, _num_args, _num_results, _call_conv) => {
      let callee = isa.scratch_reg_2_index()
      let fixup_offset = self.current_pos()
      self.x86_emit_mov_imm64(callee, 0L)
      self.add_external_func_addr_fixup(fixup_offset, symbol, callee)
      self.x86_emit_call_r64(callee)
    }
    CallPtr(_, _, _call_conv) => {
      // Standard call: arguments already placed by lowering.
      let target = match inst.use_constraints[0] {
        FixedReg(preg) => preg.index
        _ => reg_num(inst.uses[0])
      }
      self.x86_emit_call_r64(target)
    }
    ReturnCallIndirect(stack_arg_bytes, _) => {
      // Tail-call:
      // - fast path (no stack overflow args): epilogue + jmp
      // - overflow args: call + return for correctness with current ABI
      let target = match inst.use_constraints[0] {
        FixedReg(preg) => preg.index
        _ => reg_num(inst.uses[0])
      }
      if stack_arg_bytes > 0 {
        self.x86_emit_call_r64(target)
        self.emit_epilogue(stack_frame)
        self.x86_emit_ret()
      } else {
        // Preserve tail target across epilogue debug-state restore.
        // emit_epilogue() may use scratch2 (r11) as a temporary when writing
        // the runtime debug-current-function slot. Tail calls also constrain target to
        // scratch2, so copy to scratch1 first.
        let mut jump_target = target
        if target == @isaregs.current_isa().scratch_reg_2_index() {
          let preserved_target = @isaregs.current_isa().scratch_reg_1_index()
          self.x86_emit_mov_rr(preserved_target, target)
          jump_target = preserved_target
        }
        self.emit_epilogue(stack_frame)
        self.x86_emit_jmp_r64(jump_target)
      }
    }
    AdjustSP(delta) =>
      if delta > 0 {
        self.x86_emit_add_rsp_imm32(delta)
      } else if delta < 0 {
        self.x86_emit_sub_rsp_imm32(-delta)
      }
    StoreToStack(offset) => {
      // Store to pre-allocated outgoing args area at [rsp + outgoing_args_offset + offset].
      let actual_offset = stack_frame.outgoing_args_offset + offset
      let src = reg_num(inst.uses[0])
      let src_class = match inst.uses[0] {
        Physical(preg) => preg.class
        Virtual(vreg) => vreg.class
      }
      match src_class {
        Int => self.x86_emit_mov_m64_r64(4, actual_offset, src)
        Float32 | Float64 => self.x86_emit_movsd_m64_xmm(4, actual_offset, src)
        Vector => self.x86_emit_movdqu_m128_xmm(4, actual_offset, src)
      }
    }
    LoadSP => {
      // Load outgoing-args base into result register so it matches
      // StoreToStack's [rsp + outgoing_args_offset + off] addressing.
      let rd = wreg_num(inst.defs[0])
      self.x86_emit_mov_rr(rd, 4)
      emit_add_imm_to_reg_in_chunks(self, rd, stack_frame.outgoing_args_offset)
    }
    GCAllocStructSlowPrecise(type_idx, num_fields, alloc_slow_symbol) => {
      let dst = wreg_num(inst.defs[0])
      let vmctx = reg_num(inst.uses[0])
      let stack_base_off = stack_frame.outgoing_args_offset
      let arg0 = 7 // rdi
      let arg1 = 6 // rsi
      let arg2 = 2 // rdx
      let arg3 = 1 // rcx
      let arg4 = 8 // r8
      let tmp = isa.scratch_reg_2_index()

      if vmctx != arg0 {
        self.x86_emit_mov_rr(arg0, vmctx)
      }
      self.x86_emit_mov_imm64(arg1, type_idx.to_int64())
      self.x86_emit_mov_rr(arg2, 4) // rsp
      emit_add_imm_to_reg_in_chunks(self, arg2, stack_base_off)
      self.x86_emit_mov_imm64(arg3, num_fields.to_int64())
      let safepoint_root_indices : Array[Int] = []
      for i in 0..<num_fields {
        safepoint_root_indices.push(i)
      }
      let safepoint_id = self.record_gc_safepoint(
        self.current_pos(),
        root_count=num_fields,
        root_indices=safepoint_root_indices,
      )
      self.x86_emit_mov_imm64(arg4, safepoint_id.to_int64())
      let fixup_offset = self.current_pos()
      self.x86_emit_mov_imm64(tmp, 0L)
      self.add_external_func_addr_fixup(fixup_offset, alloc_slow_symbol, tmp)
      self.x86_emit_call_r64(tmp)
      if dst != 0 {
        self.x86_emit_mov_rr(dst, 0)
      }
    }
    GCAllocStructInline(type_idx, num_fields, register_symbol, slow_symbol) => {
      // Inline bump allocation with slow-path fallback.
      let dst = wreg_num(inst.defs[0])
      let vmctx = @isaregs.vmctx_index()
      let arg0 = 7 // rdi
      let arg1 = 6 // rsi
      let arg2 = 2 // rdx
      let arg3 = 1 // rcx
      let arg4 = 8 // r8
      let obj = isa.scratch_reg_1_index()
      let end = isa.scratch_reg_2_index()
      let tmp = 0 // rax
      let gc_header_size = 16
      let gc_align = 16
      let stack_base_off = stack_frame.outgoing_args_offset
      let total_size = @abi.align_up(gc_header_size + num_fields * 8, gc_align)
      let kind = 1 // GC_KIND_STRUCT
      let header_low = kind.to_int64() |
        ((type_idx & 0xFFFF).to_int64() << 16) |
        (total_size.to_int64() << 32)

      let slow = self.new_internal_label()
      let done = self.new_internal_label()
      let layout = stack_frame.require_runtime_layout()

      // next = vmctx->gc_heap_ptr; end = next + total_size.
      self.x86_emit_mov_r64_m64(obj, vmctx, layout.gc_allocation_cursor_offset)
      self.x86_emit_mov_rr(end, obj)
      emit_add_imm_to_reg_in_chunks(self, end, total_size)
      // if end > vmctx->gc_heap_limit: slow path.
      self.x86_emit_mov_r64_m64(tmp, vmctx, layout.gc_allocation_limit_offset)
      self.x86_emit_cmp_rr(end, tmp)
      self.x86_emit_jcc_rel32(Hi, slow)

      // Fast path: header + fields copy from outgoing-args stack area.
      self.x86_emit_mov_imm64(tmp, header_low)
      self.x86_emit_mov_m64_r64(obj, 0, tmp)
      self.x86_emit_mov_imm64(tmp, num_fields.to_int64())
      self.x86_emit_mov_m64_r64(obj, 8, tmp)
      for i in 0..<num_fields {
        let off = i * 8
        self.x86_emit_mov_r64_m64(tmp, 4, stack_base_off + off)
        self.x86_emit_mov_m64_r64(obj, gc_header_size + off, tmp)
      }
      self.x86_emit_mov_m64_r64(vmctx, layout.gc_allocation_cursor_offset, end)

      // register_struct_inline(vmctx, obj_ptr, total_size)
      if vmctx != arg0 {
        self.x86_emit_mov_rr(arg0, vmctx)
      }
      if obj != arg1 {
        self.x86_emit_mov_rr(arg1, obj)
      }
      self.x86_emit_mov_imm64(arg2, total_size.to_int64())
      let register_fixup_offset = self.current_pos()
      self.x86_emit_mov_imm64(end, 0L)
      self.add_external_func_addr_fixup(
        register_fixup_offset, register_symbol, end,
      )
      self.x86_emit_call_r64(end)
      if dst != 0 {
        self.x86_emit_mov_rr(dst, 0)
      }
      self.x86_emit_jmp_rel32(done)

      // Slow path: gc_alloc_struct_slow(vmctx, type_idx, fields_ptr, num_fields, safepoint_id)
      self.define_label(slow)
      if vmctx != arg0 {
        self.x86_emit_mov_rr(arg0, vmctx)
      }
      self.x86_emit_mov_imm64(arg1, type_idx.to_int64())
      self.x86_emit_mov_rr(arg2, 4) // rsp
      emit_add_imm_to_reg_in_chunks(self, arg2, stack_base_off)
      self.x86_emit_mov_imm64(arg3, num_fields.to_int64())
      let safepoint_root_indices : Array[Int] = []
      for i in 0..<num_fields {
        safepoint_root_indices.push(i)
      }
      let safepoint_id = self.record_gc_safepoint(
        self.current_pos(),
        root_count=num_fields,
        root_indices=safepoint_root_indices,
      )
      self.x86_emit_mov_imm64(arg4, safepoint_id.to_int64())
      let slow_fixup_offset = self.current_pos()
      self.x86_emit_mov_imm64(end, 0L)
      self.add_external_func_addr_fixup(slow_fixup_offset, slow_symbol, end)
      self.x86_emit_call_r64(end)
      if dst != 0 {
        self.x86_emit_mov_rr(dst, 0)
      }
      self.define_label(done)
    }
    GCAllocArrayFixedInline(type_idx, len, register_symbol, slow_symbol) => {
      // Inline bump allocation with slow-path fallback.
      let dst = wreg_num(inst.defs[0])
      let vmctx = @isaregs.vmctx_index()
      let arg0 = 7 // rdi
      let arg1 = 6 // rsi
      let arg2 = 2 // rdx
      let arg3 = 1 // rcx
      let arg4 = 8 // r8
      let obj = isa.scratch_reg_1_index()
      let end = isa.scratch_reg_2_index()
      let tmp = 0 // rax
      let gc_header_size = 16
      let gc_align = 16
      let array_meta_size = 8
      let stack_base_off = stack_frame.outgoing_args_offset
      let total_size = @abi.align_up(
        gc_header_size + array_meta_size + len * 8,
        gc_align,
      )
      let kind = 2 // GC_KIND_ARRAY
      let header_low = kind.to_int64() |
        ((type_idx & 0xFFFF).to_int64() << 16) |
        (total_size.to_int64() << 32)

      let slow = self.new_internal_label()
      let done = self.new_internal_label()
      let layout = stack_frame.require_runtime_layout()

      // next = vmctx->gc_heap_ptr; end = next + total_size.
      self.x86_emit_mov_r64_m64(obj, vmctx, layout.gc_allocation_cursor_offset)
      self.x86_emit_mov_rr(end, obj)
      emit_add_imm_to_reg_in_chunks(self, end, total_size)
      // if end > vmctx->gc_heap_limit: slow path.
      self.x86_emit_mov_r64_m64(tmp, vmctx, layout.gc_allocation_limit_offset)
      self.x86_emit_cmp_rr(end, tmp)
      self.x86_emit_jcc_rel32(Hi, slow)

      // Fast path: header + len + elements copy.
      self.x86_emit_mov_imm64(tmp, header_low)
      self.x86_emit_mov_m64_r64(obj, 0, tmp)
      self.x86_emit_mov_imm64(tmp, 0L)
      self.x86_emit_mov_m64_r64(obj, 8, tmp)
      self.x86_emit_mov_imm64(tmp, len.to_int64())
      self.x86_emit_mov_m64_r64(obj, gc_header_size, tmp)
      for i in 0..<len {
        let off = i * 8
        self.x86_emit_mov_r64_m64(tmp, 4, stack_base_off + off)
        self.x86_emit_mov_m64_r64(
          obj,
          gc_header_size + array_meta_size + off,
          tmp,
        )
      }
      self.x86_emit_mov_m64_r64(vmctx, layout.gc_allocation_cursor_offset, end)

      // register_array_inline(vmctx, obj_ptr, total_size)
      if vmctx != arg0 {
        self.x86_emit_mov_rr(arg0, vmctx)
      }
      if obj != arg1 {
        self.x86_emit_mov_rr(arg1, obj)
      }
      self.x86_emit_mov_imm64(arg2, total_size.to_int64())
      let register_fixup_offset = self.current_pos()
      self.x86_emit_mov_imm64(end, 0L)
      self.add_external_func_addr_fixup(
        register_fixup_offset, register_symbol, end,
      )
      self.x86_emit_call_r64(end)
      if dst != 0 {
        self.x86_emit_mov_rr(dst, 0)
      }
      self.x86_emit_jmp_rel32(done)

      // Slow path: gc_alloc_array_from_values_slow(vmctx, type_idx, values_ptr, len, safepoint_id)
      self.define_label(slow)
      if vmctx != arg0 {
        self.x86_emit_mov_rr(arg0, vmctx)
      }
      self.x86_emit_mov_imm64(arg1, type_idx.to_int64())
      self.x86_emit_mov_rr(arg2, 4) // rsp
      emit_add_imm_to_reg_in_chunks(self, arg2, stack_base_off)
      self.x86_emit_mov_imm64(arg3, len.to_int64())
      let safepoint_root_indices : Array[Int] = []
      for i in 0..<len {
        safepoint_root_indices.push(i)
      }
      let safepoint_id = self.record_gc_safepoint(
        self.current_pos(),
        root_count=len,
        root_indices=safepoint_root_indices,
      )
      self.x86_emit_mov_imm64(arg4, safepoint_id.to_int64())
      let slow_fixup_offset = self.current_pos()
      self.x86_emit_mov_imm64(end, 0L)
      self.add_external_func_addr_fixup(slow_fixup_offset, slow_symbol, end)
      self.x86_emit_call_r64(end)
      if dst != 0 {
        self.x86_emit_mov_rr(dst, 0)
      }
      self.define_label(done)
    }
    GCAllocArraySlowPrecise(type_idx, alloc_slow_symbol) => {
      let dst = wreg_num(inst.defs[0])
      let vmctx = reg_num(inst.uses[0])
      let mut len_reg = reg_num(inst.uses[1])
      let mut init_reg = reg_num(inst.uses[2])
      let arg0 = 7 // rdi
      let arg1 = 6 // rsi
      let arg2 = 2 // rdx
      let arg3 = 1 // rcx
      let arg4 = 8 // r8
      let save0 = isa.scratch_reg_1_index()
      let tmp = isa.scratch_reg_2_index()

      // Preserve sources that would be clobbered by setting call args.
      if len_reg == arg0 ||
        len_reg == arg1 ||
        len_reg == arg3 ||
        len_reg == arg4 {
        self.x86_emit_mov_rr(save0, len_reg)
        len_reg = save0
      }
      if init_reg == arg0 ||
        init_reg == arg1 ||
        init_reg == arg2 ||
        init_reg == arg4 {
        self.x86_emit_mov_rr(tmp, init_reg)
        init_reg = tmp
      }
      if vmctx != arg0 {
        self.x86_emit_mov_rr(arg0, vmctx)
      }
      self.x86_emit_mov_imm64(arg1, type_idx.to_int64())
      if len_reg != arg2 {
        self.x86_emit_mov_rr(arg2, len_reg)
      }
      if init_reg != arg3 {
        self.x86_emit_mov_rr(arg3, init_reg)
      }
      let safepoint_id = self.record_gc_safepoint(
        self.current_pos(),
        root_count=1,
        root_indices=[0],
      )
      self.x86_emit_mov_imm64(arg4, safepoint_id.to_int64())
      let fixup_offset = self.current_pos()
      self.x86_emit_mov_imm64(tmp, 0L)
      self.add_external_func_addr_fixup(fixup_offset, alloc_slow_symbol, tmp)
      self.x86_emit_call_r64(tmp)
      if dst != 0 {
        self.x86_emit_mov_rr(dst, 0)
      }
    }
    LoadConstV128(bytes) => {
      // Materialize a 128-bit constant via constant pool (Cranelift-style).
      let rd = wreg_num(inst.defs[0])
      let scratch = isa.scratch_reg_1_index()
      let label = self.intern_amd64_const(bytes, 16)
      self.x86_emit_lea_r64_riprel32(scratch, label)
      self.x86_emit_movdqu_xmm_m128(rd, scratch, 0)
    }
    SIMDSplat(lane_size) => {
      // Splat scalar integer to all lanes.
      //
      // Mirrors Cranelift x64 lowering rules in `lower.isle` (SSE2 baseline):
      // - i8x16.splat:  movd + punpcklbw + pshuflw + pshufd
      // - i16x8.splat:  movd + pshuflw + pshufd
      // - i32x4.splat:  movd + pshufd
      // - i64x2.splat:  movq + pshufd 0x44
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      match lane_size {
        B8 => {
          self.x86_emit_movd_xmm_r32(rd, src)
          self.x86_emit_punpcklbw_xmm_xmm(rd, rd)
          self.x86_emit_pshuflw_xmm_xmm_imm8(rd, rd, 0)
          self.x86_emit_pshufd_xmm_xmm_imm8(rd, rd, 0)
        }
        H16 => {
          self.x86_emit_movd_xmm_r32(rd, src)
          self.x86_emit_pshuflw_xmm_xmm_imm8(rd, rd, 0)
          self.x86_emit_pshufd_xmm_xmm_imm8(rd, rd, 0)
        }
        S32 => {
          self.x86_emit_movd_xmm_r32(rd, src)
          self.x86_emit_pshufd_xmm_xmm_imm8(rd, rd, 0)
        }
        D64 => {
          self.x86_emit_movq_xmm_r64(rd, src)
          self.x86_emit_pshufd_xmm_xmm_imm8(rd, rd, 0x44)
        }
      }
    }
    SIMDSplatF(is_f32) => {
      // Splat scalar float to all lanes.
      //
      // - f32x4.splat: SHUFPS xmm, xmm, 0x00 (SSE1)
      // - f64x2.splat: SHUFPD xmm, xmm, 0x00 (SSE2)
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      if rd != src {
        self.x86_emit_movaps_xmm_xmm(rd, src)
      }
      if is_f32 {
        self.x86_emit_shufps_xmm_xmm_imm8(rd, rd, 0x00)
      } else {
        self.x86_emit_shufpd_xmm_xmm_imm8(rd, rd, 0x00)
      }
    }
    SIMDInsert(lane_size, lane) => {
      // Insert scalar integer into a vector lane.
      //
      // Use `pinsr*` (SSE2/SSE4.1) to update one lane while preserving others.
      let rd = wreg_num(inst.defs[0])
      let vec = reg_num(inst.uses[0])
      let src = reg_num(inst.uses[1])
      if rd != vec {
        self.x86_emit_movaps_xmm_xmm(rd, vec)
      }
      match lane_size {
        B8 => self.x86_emit_pinsrb_xmm_r32_imm8(rd, src, lane)
        H16 => self.x86_emit_pinsrw_xmm_r32_imm8(rd, src, lane)
        S32 => self.x86_emit_pinsrd_xmm_r32_imm8(rd, src, lane)
        D64 => self.x86_emit_pinsrq_xmm_r64_imm8(rd, src, lane)
      }
    }
    SIMDExtractU(lane_size, lane) => {
      // Extract scalar integer lane, zero-extending to the destination GPR.
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      match lane_size {
        B8 => self.x86_emit_pextrb_r32_xmm_imm8(rd, src, lane)
        H16 => self.x86_emit_pextrw_r32_xmm_imm8(rd, src, lane)
        S32 => self.x86_emit_pextrd_r32_xmm_imm8(rd, src, lane)
        D64 => self.x86_emit_pextrq_r64_xmm_imm8(rd, src, lane)
      }
    }
    SIMDExtractS(lane_size, lane) => {
      // Extract scalar integer lane, sign-extending to the destination GPR.
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      match lane_size {
        B8 => {
          self.x86_emit_pextrb_r32_xmm_imm8(rd, src, lane)
          self.x86_emit_shl_r_imm8(rd, 56)
          self.x86_emit_sar_r_imm8(rd, 56)
        }
        H16 => {
          self.x86_emit_pextrw_r32_xmm_imm8(rd, src, lane)
          self.x86_emit_shl_r_imm8(rd, 48)
          self.x86_emit_sar_r_imm8(rd, 48)
        }
        S32 => {
          self.x86_emit_pextrd_r32_xmm_imm8(rd, src, lane)
          self.x86_emit_movsxd_r64_r32(rd, rd)
        }
        D64 => self.x86_emit_pextrq_r64_xmm_imm8(rd, src, lane)
      }
    }
    SIMDExtractF(is_f32, lane) => {
      // Extract scalar float lane into an XMM register.
      //
      // Mirrors Cranelift x64 lowering rules in `lower.isle`.
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      if rd != src {
        self.x86_emit_movaps_xmm_xmm(rd, src)
      }
      if is_f32 {
        if lane != 0 {
          // Broadcast dword lane to all lanes; the low lane then holds the scalar.
          self.x86_emit_pshufd_xmm_xmm_imm8(rd, rd, (lane & 3) * 0x55)
        }
      } else if lane == 1 {
        // Select the high 64-bit lane into the low lane.
        self.x86_emit_pshufd_xmm_xmm_imm8(rd, rd, 0xEE)
      } else if lane != 0 {
        abort("SIMDExtractF f64 lane out of range: \{lane}")
      }
    }
    SIMDInsertF(is_f32, lane) => {
      // Insert scalar float into a vector lane.
      //
      // Mirrors Cranelift x64 lowering rules in `lower.isle`.
      let rd = wreg_num(inst.defs[0])
      let vec = reg_num(inst.uses[0])
      let src = reg_num(inst.uses[1])
      if rd != vec {
        self.x86_emit_movaps_xmm_xmm(rd, vec)
      }
      if is_f32 {
        // INSERTPS: insert 32-bit lane 0 of `src` into lane `lane` of `rd`.
        self.x86_emit_insertps_xmm_xmm_imm8(rd, src, (lane & 3) << 4)
      } else if lane == 0 {
        self.x86_emit_movsd_xmm_xmm(rd, src)
      } else if lane == 1 {
        self.x86_emit_movlhps_xmm_xmm(rd, src)
      } else {
        abort("SIMDInsertF f64 lane out of range: \{lane}")
      }
    }
    SIMDAnd => {
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let src = prepare_xmm_two_operand(self, rd, a, b, 14)
      self.x86_emit_pand_xmm_xmm(rd, src)
    }
    SIMDOr => {
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let src = prepare_xmm_two_operand(self, rd, a, b, 14)
      self.x86_emit_por_xmm_xmm(rd, src)
    }
    SIMDXor => {
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let src = prepare_xmm_two_operand(self, rd, a, b, 14)
      self.x86_emit_pxor_xmm_xmm(rd, src)
    }
    SIMDBic => {
      // a & ~b == (~b) & a, matching the x86 `PANDN` operand order.
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      if rd == b {
        self.x86_emit_pandn_xmm_xmm(rd, a)
      } else if rd == a {
        // Preserve `b` in a scratch reg before clobbering `rd`.
        let tmp = 14 // reserved via MachineEnvData.scratch_float
        self.x86_emit_movaps_xmm_xmm(tmp, b)
        self.x86_emit_pandn_xmm_xmm(tmp, a)
        self.x86_emit_movaps_xmm_xmm(rd, tmp)
      } else {
        self.x86_emit_movaps_xmm_xmm(rd, b)
        self.x86_emit_pandn_xmm_xmm(rd, a)
      }
    }
    SIMDNot => {
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      let tmp = 15 // reserved via MachineEnvData.scratch_float
      if rd != src {
        self.x86_emit_movaps_xmm_xmm(rd, src)
      }
      self.x86_emit_pcmpeqd_xmm_xmm(tmp, tmp) // tmp = all ones
      self.x86_emit_pxor_xmm_xmm(rd, tmp)
    }
    SIMDAdd(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let src = prepare_xmm_two_operand(self, rd, a, b, 14)
      self.x86_emit_padd_xmm_xmm(lane_size, rd, src)
    }
    SIMDSub(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let src = prepare_xmm_two_operand(self, rd, a, b, 14)
      self.x86_emit_psub_xmm_xmm(lane_size, rd, src)
    }
    SIMDSqadd(lane_size) => {
      // Signed saturating add (wasm: i8x16.add_sat_s, i16x8.add_sat_s).
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let src = prepare_xmm_two_operand(self, rd, a, b, 14)
      match lane_size {
        B8 => self.x86_emit_paddsb_xmm_xmm(rd, src)
        H16 => self.x86_emit_paddsw_xmm_xmm(rd, src)
        _ => abort("x86_64 SIMDSqadd: unsupported lane size \{lane_size}")
      }
    }
    SIMDUqadd(lane_size) => {
      // Unsigned saturating add (wasm: i8x16.add_sat_u, i16x8.add_sat_u).
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let src = prepare_xmm_two_operand(self, rd, a, b, 14)
      match lane_size {
        B8 => self.x86_emit_paddusb_xmm_xmm(rd, src)
        H16 => self.x86_emit_paddusw_xmm_xmm(rd, src)
        _ => abort("x86_64 SIMDUqadd: unsupported lane size \{lane_size}")
      }
    }
    SIMDSqsub(lane_size) => {
      // Signed saturating subtract (wasm: i8x16.sub_sat_s, i16x8.sub_sat_s).
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let src = prepare_xmm_two_operand(self, rd, a, b, 14)
      match lane_size {
        B8 => self.x86_emit_psubsb_xmm_xmm(rd, src)
        H16 => self.x86_emit_psubsw_xmm_xmm(rd, src)
        _ => abort("x86_64 SIMDSqsub: unsupported lane size \{lane_size}")
      }
    }
    SIMDUqsub(lane_size) => {
      // Unsigned saturating subtract (wasm: i8x16.sub_sat_u, i16x8.sub_sat_u).
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let src = prepare_xmm_two_operand(self, rd, a, b, 14)
      match lane_size {
        B8 => self.x86_emit_psubusb_xmm_xmm(rd, src)
        H16 => self.x86_emit_psubusw_xmm_xmm(rd, src)
        _ => abort("x86_64 SIMDUqsub: unsupported lane size \{lane_size}")
      }
    }
    SIMDSmin(lane_size) => {
      // Signed integer minimum.
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let src = prepare_xmm_two_operand(self, rd, a, b, 14)
      match lane_size {
        B8 => self.x86_emit_pminsb_xmm_xmm(rd, src) // SSE4.1
        H16 => self.x86_emit_pminsw_xmm_xmm(rd, src) // SSE2
        S32 => self.x86_emit_pminsd_xmm_xmm(rd, src) // SSE4.1
        D64 => abort("x86_64 SIMDSmin: i64x2 min not supported by wasm SIMD")
      }
    }
    SIMDUmin(lane_size) => {
      // Unsigned integer minimum.
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let src = prepare_xmm_two_operand(self, rd, a, b, 14)
      match lane_size {
        B8 => self.x86_emit_pminub_xmm_xmm(rd, src) // SSE2
        H16 => self.x86_emit_pminuw_xmm_xmm(rd, src) // SSE4.1
        S32 => self.x86_emit_pminud_xmm_xmm(rd, src) // SSE4.1
        D64 => abort("x86_64 SIMDUmin: i64x2 min not supported by wasm SIMD")
      }
    }
    SIMDSmax(lane_size) => {
      // Signed integer maximum.
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let src = prepare_xmm_two_operand(self, rd, a, b, 14)
      match lane_size {
        B8 => self.x86_emit_pmaxsb_xmm_xmm(rd, src) // SSE4.1
        H16 => self.x86_emit_pmaxsw_xmm_xmm(rd, src) // SSE2
        S32 => self.x86_emit_pmaxsd_xmm_xmm(rd, src) // SSE4.1
        D64 => abort("x86_64 SIMDSmax: i64x2 max not supported by wasm SIMD")
      }
    }
    SIMDUmax(lane_size) => {
      // Unsigned integer maximum.
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let src = prepare_xmm_two_operand(self, rd, a, b, 14)
      match lane_size {
        B8 => self.x86_emit_pmaxub_xmm_xmm(rd, src) // SSE2
        H16 => self.x86_emit_pmaxuw_xmm_xmm(rd, src) // SSE4.1
        S32 => self.x86_emit_pmaxud_xmm_xmm(rd, src) // SSE4.1
        D64 => abort("x86_64 SIMDUmax: i64x2 max not supported by wasm SIMD")
      }
    }
    SIMDUrhadd(lane_size) => {
      // Unsigned rounding halving add: (a + b + 1) >> 1.
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let src = prepare_xmm_two_operand(self, rd, a, b, 14)
      match lane_size {
        B8 => self.x86_emit_pavgb_xmm_xmm(rd, src) // SSE2
        H16 => self.x86_emit_pavgw_xmm_xmm(rd, src) // SSE2
        _ => abort("x86_64 SIMDUrhadd: unsupported lane size \{lane_size}")
      }
    }
    SIMDAbs(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      match lane_size {
        B8 => self.x86_emit_pabsb_xmm_xmm(rd, src) // SSSE3
        H16 => self.x86_emit_pabsw_xmm_xmm(rd, src) // SSSE3
        S32 => self.x86_emit_pabsd_xmm_xmm(rd, src) // SSSE3
        D64 => {
          // Align with Cranelift x64 lowering for i64x2.abs without AVX512:
          // generate a per-lane sign mask via psrad+pshufd, then xor/sub.
          let sign = 14 // reserved via MachineEnvData.scratch_float
          if rd != src {
            self.x86_emit_movaps_xmm_xmm(rd, src)
          }
          self.x86_emit_movaps_xmm_xmm(sign, rd)
          self.x86_emit_psrad_xmm_imm8(sign, 31)
          self.x86_emit_pshufd_xmm_xmm_imm8(sign, sign, 0xF5)
          self.x86_emit_pxor_xmm_xmm(rd, sign)
          self.x86_emit_psub_xmm_xmm(D64, rd, sign)
        }
      }
    }
    SIMDNeg(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      let mut tmp = 14 // reserved via MachineEnvData.scratch_float
      if tmp == rd {
        tmp = 15
      }
      let src_reg = if rd == src {
        self.x86_emit_movaps_xmm_xmm(tmp, src)
        tmp
      } else {
        src
      }
      self.x86_emit_pxor_xmm_xmm(rd, rd)
      self.x86_emit_psub_xmm_xmm(lane_size, rd, src_reg)
    }
    SIMDCnt => {
      // Align with Cranelift x64 i8x16.popcnt when SSSE3 is available
      // (Mula's algorithm with a nibble lookup table).
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      let tmp0 = 14 // reserved via MachineEnvData.scratch_float
      let tmp1 = 15 // reserved via MachineEnvData.scratch_float
      let scratch_gpr = isa.scratch_reg_1_index()

      // Keep a copy if the output aliases the input.
      let src_saved = if rd == src {
        self.x86_emit_movaps_xmm_xmm(tmp0, src)
        tmp0
      } else {
        src
      }

      // low_nibbles = src & 0x0f
      materialize_xmm_const(
        self, tmp1, 0x0F0F0F0F0F0F0F0FL, 0x0F0F0F0F0F0F0F0FL, scratch_gpr,
      )
      self.x86_emit_movaps_xmm_xmm(rd, src_saved)
      self.x86_emit_pand_xmm_xmm(rd, tmp1)

      // bit_counts_low = pshufb(lookup, low_nibbles)
      materialize_xmm_const(
        self, tmp1, 0x0302020102010100L, 0x0403030203020201L, scratch_gpr,
      )
      self.x86_emit_pshufb_xmm_xmm(tmp1, rd)

      // high_nibbles = (src >> 4) & 0x0f  (shift within 16-bit lanes)
      self.x86_emit_movaps_xmm_xmm(rd, src_saved)
      self.x86_emit_psrlw_xmm_imm8(rd, 4)
      materialize_xmm_const(
        self, tmp0, 0x0F0F0F0F0F0F0F0FL, 0x0F0F0F0F0F0F0F0FL, scratch_gpr,
      )
      self.x86_emit_pand_xmm_xmm(rd, tmp0)

      // bit_counts_high = pshufb(lookup, high_nibbles)
      materialize_xmm_const(
        self, tmp0, 0x0302020102010100L, 0x0403030203020201L, scratch_gpr,
      )
      self.x86_emit_pshufb_xmm_xmm(tmp0, rd)

      // result = bit_counts_low + bit_counts_high
      self.x86_emit_padd_xmm_xmm(B8, tmp1, tmp0)
      if rd != tmp1 {
        self.x86_emit_movaps_xmm_xmm(rd, tmp1)
      }
    }
    SIMDBroadcastShift(lane_size, negate) => {
      // x86 packed shifts take a scalar count from the low bits of an XMM
      // register, so we materialize the masked (and optionally negated) count
      // into `shift_vec`.
      let tmp_gpr = wreg_num(inst.defs[0])
      let shift_vec = wreg_num(inst.defs[1])
      let shift = reg_num(inst.uses[0])
      let mask = match lane_size {
        B8 => 7
        H16 => 15
        S32 => 31
        D64 => 63
      }
      if tmp_gpr != shift {
        self.x86_emit_mov_rr(tmp_gpr, shift)
      }
      self.x86_emit_and_r_imm8_sxb64(tmp_gpr, mask)
      if negate {
        self.x86_emit_neg_r64(tmp_gpr)
      }
      self.x86_emit_movq_xmm_r64(shift_vec, tmp_gpr)
    }
    SIMDShiftByVec(lane_size, use_ushl) => {
      // Interpret the shift amount as a signed scalar:
      // - non-negative => left shift
      // - negative => right shift by -amount
      //
      // This matches the semantics used by AArch64 SSHL/USHL lowering.
      let rd = wreg_num(inst.defs[0])
      let vec = reg_num(inst.uses[0])
      let shift_vec = reg_num(inst.uses[1])
      let tmp_gpr = isa.scratch_reg_1_index()
      let tmp_gpr2 = isa.scratch_reg_2_index()
      let cnt_xmm = 14 // reserved via MachineEnvData.scratch_float
      let tmp_xmm = 15 // reserved via MachineEnvData.scratch_float
      let do_right = self.new_internal_label()
      let done = self.new_internal_label()

      // tmp_gpr = shift amount (signed)
      self.x86_emit_movq_r64_xmm(tmp_gpr, shift_vec)
      self.x86_emit_test_rr(tmp_gpr, tmp_gpr)
      self.x86_emit_jcc_rel32(Mi, do_right) // JS

      // Left shift (count >= 0).
      match lane_size {
        B8 => {
          // i8x16 shl via 16x8 shift + dynamic mask (Cranelift-style idea).
          if rd != vec {
            self.x86_emit_movaps_xmm_xmm(rd, vec)
          }
          // rd = psllw(rd, shift_vec)
          self.x86_emit_psll_xmm_xmm(H16, rd, shift_vec)

          // tmp_xmm = hi_mask = (0xFF00 << count)
          self.x86_emit_pcmpeqd_xmm_xmm(tmp_xmm, tmp_xmm)
          self.x86_emit_psllw_xmm_imm8(tmp_xmm, 8) // 0xFF00
          self.x86_emit_psll_xmm_xmm(H16, tmp_xmm, shift_vec)

          // cnt_xmm = lo_mask = 0x00FF
          self.x86_emit_pcmpeqd_xmm_xmm(cnt_xmm, cnt_xmm)
          self.x86_emit_psrlw_xmm_imm8(cnt_xmm, 8) // 0x00FF

          // tmp_xmm |= cnt_xmm; rd &= tmp_xmm
          self.x86_emit_por_xmm_xmm(tmp_xmm, cnt_xmm)
          self.x86_emit_pand_xmm_xmm(rd, tmp_xmm)
        }
        _ => {
          if rd != vec {
            self.x86_emit_movaps_xmm_xmm(rd, vec)
          }
          self.x86_emit_psll_xmm_xmm(lane_size, rd, shift_vec)
        }
      }
      self.x86_emit_jmp_rel32(done)

      // Right shift (count < 0): count = -count.
      self.define_label(do_right)
      self.x86_emit_neg_r64(tmp_gpr)
      self.x86_emit_movq_xmm_r64(cnt_xmm, tmp_gpr)
      match lane_size {
        B8 =>
          if use_ushl {
            // i8x16 ushr via 16x8 shift + dynamic mask (Cranelift-style idea).
            if rd != vec {
              self.x86_emit_movaps_xmm_xmm(rd, vec)
            }
            self.x86_emit_psrl_xmm_xmm(H16, rd, cnt_xmm)

            // tmp_xmm = low_mask = (0x00FF >> count)
            self.x86_emit_pcmpeqd_xmm_xmm(tmp_xmm, tmp_xmm)
            self.x86_emit_psrlw_xmm_imm8(tmp_xmm, 8) // 0x00FF
            self.x86_emit_psrl_xmm_xmm(H16, tmp_xmm, cnt_xmm)

            // cnt_xmm = high_mask = 0xFF00
            self.x86_emit_pcmpeqd_xmm_xmm(cnt_xmm, cnt_xmm)
            self.x86_emit_psllw_xmm_imm8(cnt_xmm, 8) // 0xFF00
            self.x86_emit_por_xmm_xmm(tmp_xmm, cnt_xmm)
            self.x86_emit_pand_xmm_xmm(rd, tmp_xmm)
          } else {
            // i8x16 sshr: match Cranelift's widen+psraw+packsswb trick.
            //
            // Use the output reg as a temporary XMM for the (count + 8).
            if rd != vec {
              self.x86_emit_movaps_xmm_xmm(rd, vec)
            }
            // tmp_xmm = lo = punpcklbw(vec, vec)
            self.x86_emit_movaps_xmm_xmm(tmp_xmm, vec)
            self.x86_emit_punpcklbw_xmm_xmm(tmp_xmm, tmp_xmm)
            // cnt_xmm = hi = punpckhbw(vec, vec)
            self.x86_emit_movaps_xmm_xmm(cnt_xmm, vec)
            self.x86_emit_punpckhbw_xmm_xmm(cnt_xmm, cnt_xmm)

            // tmp_gpr = count + 8
            self.x86_emit_mov_imm64(tmp_gpr2, 8)
            self.x86_emit_add_rr(tmp_gpr, tmp_gpr2)
            self.x86_emit_movd_xmm_r32(rd, tmp_gpr)
            self.x86_emit_psra_xmm_xmm(H16, tmp_xmm, rd)
            self.x86_emit_psra_xmm_xmm(H16, cnt_xmm, rd)
            self.x86_emit_packsswb_xmm_xmm(tmp_xmm, cnt_xmm)
            if rd != tmp_xmm {
              self.x86_emit_movaps_xmm_xmm(rd, tmp_xmm)
            }
          }
        H16 | S32 =>
          if use_ushl {
            if rd != vec {
              self.x86_emit_movaps_xmm_xmm(rd, vec)
            }
            self.x86_emit_psrl_xmm_xmm(lane_size, rd, cnt_xmm)
          } else {
            if rd != vec {
              self.x86_emit_movaps_xmm_xmm(rd, vec)
            }
            self.x86_emit_psra_xmm_xmm(lane_size, rd, cnt_xmm)
          }
        D64 =>
          if use_ushl {
            if rd != vec {
              self.x86_emit_movaps_xmm_xmm(rd, vec)
            }
            self.x86_emit_psrl_xmm_xmm(D64, rd, cnt_xmm)
          } else {
            // i64x2 sshr via Cranelift `lower_i64x2_sshr_gpr` sequence.
            if rd != vec {
              self.x86_emit_movaps_xmm_xmm(rd, vec)
            }
            materialize_xmm_const(
              self, tmp_xmm, 0x8000000000000000L, 0x8000000000000000L, tmp_gpr2,
            )
            // sign_bit_loc = mask >> count
            self.x86_emit_psrl_xmm_xmm(D64, tmp_xmm, cnt_xmm)
            // ushr = vec >> count
            self.x86_emit_psrl_xmm_xmm(D64, rd, cnt_xmm)
            // (ushr ^ sign_bit_loc) - sign_bit_loc
            self.x86_emit_pxor_xmm_xmm(rd, tmp_xmm)
            self.x86_emit_psub_xmm_xmm(D64, rd, tmp_xmm)
          }
      }
      self.define_label(done)
    }
    SIMDNarrow(dst_lane_size, is_signed) => {
      // Narrow two vectors to one, with saturation.
      //
      // Match Cranelift x64 lowering using PACK* instructions.
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let tmp = 15 // reserved via MachineEnvData.scratch_float
      let rhs = prepare_xmm_two_operand(self, rd, a, b, tmp)
      match dst_lane_size {
        B8 =>
          if is_signed {
            self.x86_emit_packsswb_xmm_xmm(rd, rhs)
          } else {
            self.x86_emit_packuswb_xmm_xmm(rd, rhs)
          }
        H16 =>
          if is_signed {
            self.x86_emit_packssdw_xmm_xmm(rd, rhs)
          } else {
            self.x86_emit_packusdw_xmm_xmm(rd, rhs)
          }
        _ =>
          abort("amd64 SIMDNarrow: unsupported dst lane size \{dst_lane_size}")
      }
    }
    SIMDExtendLow(dst_lane_size, is_signed) => {
      // Widen the lower half lanes.
      //
      // Match Cranelift x64 `swiden_low`/`uwiden_low` rules using SSE4.1
      // `pmovsx*`/`pmovzx*`.
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      match dst_lane_size {
        H16 =>
          if is_signed {
            self.x86_emit_pmovsxbw_xmm_xmm(rd, src)
          } else {
            self.x86_emit_pmovzxbw_xmm_xmm(rd, src)
          }
        S32 =>
          if is_signed {
            self.x86_emit_pmovsxwd_xmm_xmm(rd, src)
          } else {
            self.x86_emit_pmovzxwd_xmm_xmm(rd, src)
          }
        D64 =>
          if is_signed {
            self.x86_emit_pmovsxdq_xmm_xmm(rd, src)
          } else {
            self.x86_emit_pmovzxdq_xmm_xmm(rd, src)
          }
        _ =>
          abort(
            "amd64 SIMDExtendLow: unsupported dst lane size \{dst_lane_size}",
          )
      }
    }
    SIMDExtendHigh(dst_lane_size, is_signed) => {
      // Widen the upper half lanes.
      //
      // Match Cranelift x64 `swiden_high` rules: move the high lanes down then
      // apply the SSE4.1 pmovsx/pmovzx widening instructions.
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      match dst_lane_size {
        H16 => {
          if rd != src {
            self.x86_emit_movaps_xmm_xmm(rd, src)
          }
          self.x86_emit_palignr_xmm_xmm_imm8(rd, rd, 8)
          if is_signed {
            self.x86_emit_pmovsxbw_xmm_xmm(rd, rd)
          } else {
            self.x86_emit_pmovzxbw_xmm_xmm(rd, rd)
          }
        }
        S32 => {
          if rd != src {
            self.x86_emit_movaps_xmm_xmm(rd, src)
          }
          self.x86_emit_palignr_xmm_xmm_imm8(rd, rd, 8)
          if is_signed {
            self.x86_emit_pmovsxwd_xmm_xmm(rd, rd)
          } else {
            self.x86_emit_pmovzxwd_xmm_xmm(rd, rd)
          }
        }
        D64 => {
          if rd != src {
            self.x86_emit_movaps_xmm_xmm(rd, src)
          }
          // Bring lanes 2 and 3 down.
          self.x86_emit_pshufd_xmm_xmm_imm8(rd, rd, 0xEE)
          if is_signed {
            self.x86_emit_pmovsxdq_xmm_xmm(rd, rd)
          } else {
            self.x86_emit_pmovzxdq_xmm_xmm(rd, rd)
          }
        }
        _ =>
          abort(
            "amd64 SIMDExtendHigh: unsupported dst lane size \{dst_lane_size}",
          )
      }
    }
    SIMDExtMulLow(dst_lane_size, is_signed) => {
      // Multiply lower half lanes and widen the result.
      //
      // Match Cranelift x64 special cases for extmul.
      let rd = wreg_num(inst.defs[0])
      let x = reg_num(inst.uses[0])
      let y = reg_num(inst.uses[1])
      let t0 = 14 // reserved via MachineEnvData.scratch_float
      let t1 = 15 // reserved via MachineEnvData.scratch_float
      match dst_lane_size {
        H16 => {
          if is_signed {
            self.x86_emit_pmovsxbw_xmm_xmm(rd, x)
            self.x86_emit_pmovsxbw_xmm_xmm(t0, y)
          } else {
            self.x86_emit_pmovzxbw_xmm_xmm(rd, x)
            self.x86_emit_pmovzxbw_xmm_xmm(t0, y)
          }
          self.x86_emit_pmullw_xmm_xmm(rd, t0)
        }
        S32 => {
          // lo = pmullw(x, y); hi = pmulh*(x, y); punpcklwd(lo, hi)
          let mut y_keep = y
          if rd == y {
            self.x86_emit_movaps_xmm_xmm(t1, y)
            y_keep = t1
          }
          self.x86_emit_movaps_xmm_xmm(t0, x)
          if is_signed {
            self.x86_emit_pmulhw_xmm_xmm(t0, y_keep)
          } else {
            self.x86_emit_pmulhuw_xmm_xmm(t0, y_keep)
          }
          if rd != x {
            self.x86_emit_movaps_xmm_xmm(rd, x)
          }
          self.x86_emit_pmullw_xmm_xmm(rd, y_keep)
          self.x86_emit_punpcklwd_xmm_xmm(rd, t0)
        }
        D64 => {
          let imm = 0x50
          self.x86_emit_pshufd_xmm_xmm_imm8(t0, x, imm)
          self.x86_emit_pshufd_xmm_xmm_imm8(t1, y, imm)
          if is_signed {
            self.x86_emit_pmuldq_xmm_xmm(t0, t1)
          } else {
            self.x86_emit_pmuludq_xmm_xmm(t0, t1)
          }
          self.x86_emit_movaps_xmm_xmm(rd, t0)
        }
        _ =>
          abort(
            "amd64 SIMDExtMulLow: unsupported dst lane size \{dst_lane_size}",
          )
      }
    }
    SIMDExtMulHigh(dst_lane_size, is_signed) => {
      // Multiply upper half lanes and widen the result.
      //
      // Match Cranelift x64 special cases for extmul.
      let rd = wreg_num(inst.defs[0])
      let x = reg_num(inst.uses[0])
      let y = reg_num(inst.uses[1])
      let t0 = 14 // reserved via MachineEnvData.scratch_float
      let t1 = 15 // reserved via MachineEnvData.scratch_float
      match dst_lane_size {
        H16 => {
          if rd != x {
            self.x86_emit_movaps_xmm_xmm(rd, x)
          }
          self.x86_emit_palignr_xmm_xmm_imm8(rd, rd, 8)
          self.x86_emit_movaps_xmm_xmm(t0, y)
          self.x86_emit_palignr_xmm_xmm_imm8(t0, t0, 8)
          if is_signed {
            self.x86_emit_pmovsxbw_xmm_xmm(rd, rd)
            self.x86_emit_pmovsxbw_xmm_xmm(t0, t0)
          } else {
            self.x86_emit_pmovzxbw_xmm_xmm(rd, rd)
            self.x86_emit_pmovzxbw_xmm_xmm(t0, t0)
          }
          self.x86_emit_pmullw_xmm_xmm(rd, t0)
        }
        S32 => {
          // lo = pmullw(x, y); hi = pmulh*(x, y); punpckhwd(lo, hi)
          let mut y_keep = y
          if rd == y {
            self.x86_emit_movaps_xmm_xmm(t1, y)
            y_keep = t1
          }
          self.x86_emit_movaps_xmm_xmm(t0, x)
          if is_signed {
            self.x86_emit_pmulhw_xmm_xmm(t0, y_keep)
          } else {
            self.x86_emit_pmulhuw_xmm_xmm(t0, y_keep)
          }
          if rd != x {
            self.x86_emit_movaps_xmm_xmm(rd, x)
          }
          self.x86_emit_pmullw_xmm_xmm(rd, y_keep)
          self.x86_emit_punpckhwd_xmm_xmm(rd, t0)
        }
        D64 => {
          let imm = 0xFA
          self.x86_emit_pshufd_xmm_xmm_imm8(t0, x, imm)
          self.x86_emit_pshufd_xmm_xmm_imm8(t1, y, imm)
          if is_signed {
            self.x86_emit_pmuldq_xmm_xmm(t0, t1)
          } else {
            self.x86_emit_pmuludq_xmm_xmm(t0, t1)
          }
          self.x86_emit_movaps_xmm_xmm(rd, t0)
        }
        _ =>
          abort(
            "amd64 SIMDExtMulHigh: unsupported dst lane size \{dst_lane_size}",
          )
      }
    }
    SIMDExtAddPairwise(dst_lane_size, is_signed) => {
      // Pairwise add adjacent lanes and widen the result.
      //
      // Match Cranelift x64 special cases for extadd_pairwise.
      let rd = wreg_num(inst.defs[0])
      let val = reg_num(inst.uses[0])
      let t0 = 14 // reserved via MachineEnvData.scratch_float
      let t1 = 15 // reserved via MachineEnvData.scratch_float
      let mut scratch = isa.scratch_reg_1_index()
      if scratch == rd {
        scratch = isa.scratch_reg_2_index()
      }
      match dst_lane_size {
        H16 => {
          // i16x8.extadd_pairwise_i8x16_{s,u}
          let ones = 0x0101010101010101L
          materialize_xmm_const(self, t0, ones, ones, scratch)
          if is_signed {
            // pmaddubsw(ones, val)
            if rd == val {
              self.x86_emit_movaps_xmm_xmm(t1, val)
              self.x86_emit_movaps_xmm_xmm(rd, t0)
              self.x86_emit_pmaddubsw_xmm_xmm(rd, t1)
            } else {
              self.x86_emit_movaps_xmm_xmm(rd, t0)
              self.x86_emit_pmaddubsw_xmm_xmm(rd, val)
            }
          } else {
            // pmaddubsw(val, ones)
            if rd != val {
              self.x86_emit_movaps_xmm_xmm(rd, val)
            }
            self.x86_emit_pmaddubsw_xmm_xmm(rd, t0)
          }
        }
        S32 => {
          // i32x4.extadd_pairwise_i16x8_{s,u}
          let madd_ones = 0x0001000100010001L
          if is_signed {
            materialize_xmm_const(self, t0, madd_ones, madd_ones, scratch)
            if rd != val {
              self.x86_emit_movaps_xmm_xmm(rd, val)
            }
            self.x86_emit_pmaddwd_xmm_xmm(rd, t0)
          } else {
            // Bias into signed domain, pmaddwd, then fixup.
            let xor_const = 0x8000800080008000L
            let addd_const = 0x0001000000010000L
            if rd != val {
              self.x86_emit_movaps_xmm_xmm(rd, val)
            }
            materialize_xmm_const(self, t0, xor_const, xor_const, scratch)
            self.x86_emit_pxor_xmm_xmm(rd, t0)
            materialize_xmm_const(self, t1, madd_ones, madd_ones, scratch)
            self.x86_emit_pmaddwd_xmm_xmm(rd, t1)
            materialize_xmm_const(self, t0, addd_const, addd_const, scratch)
            self.x86_emit_padd_xmm_xmm(S32, rd, t0)
          }
        }
        _ =>
          abort(
            "amd64 SIMDExtAddPairwise: unsupported dst lane size \{dst_lane_size}",
          )
      }
    }
    SIMDDot => {
      // i32x4.dot_i16x8_s: use PMADDWD directly (Cranelift special case).
      let rd = wreg_num(inst.defs[0])
      let x = reg_num(inst.uses[0])
      let y = reg_num(inst.uses[1])
      let tmp = 15 // reserved via MachineEnvData.scratch_float
      let rhs = prepare_xmm_two_operand(self, rd, x, y, tmp)
      self.x86_emit_pmaddwd_xmm_xmm(rd, rhs)
    }
    SIMDQ15MulrSat => {
      // i16x8.q15mulr_sat_s / relaxed_q15mulr_s: rounding multiply high with
      // signed saturation.
      //
      // Match Cranelift x64 lowering using PMULHRSW + fixup for the
      // -32768 corner case.
      let rd = wreg_num(inst.defs[0])
      let x = reg_num(inst.uses[0])
      let y = reg_num(inst.uses[1])
      let t0 = 14 // reserved via MachineEnvData.scratch_float
      let t1 = 15 // reserved via MachineEnvData.scratch_float
      let rhs = prepare_xmm_two_operand(self, rd, x, y, t1)
      self.x86_emit_pmulhrsw_xmm_xmm(rd, rhs)

      // If a lane equals 0x8000, xor with all-ones to produce 0x7FFF.
      let mut scratch = isa.scratch_reg_1_index()
      if scratch == rd {
        scratch = isa.scratch_reg_2_index()
      }
      let mask = 0x8000800080008000L
      materialize_xmm_const(self, t0, mask, mask, scratch)
      self.x86_emit_movaps_xmm_xmm(t1, rd)
      self.x86_emit_pcmpeq_xmm_xmm(H16, t1, t0)
      self.x86_emit_pxor_xmm_xmm(rd, t1)
    }
    SIMDFMla(is_f32) => {
      // relaxed_madd: a * b + c
      let rd = wreg_num(inst.defs[0])
      let acc = reg_num(inst.uses[0])
      let a = reg_num(inst.uses[1])
      let b = reg_num(inst.uses[2])
      let t0 = 14
      self.x86_emit_movaps_xmm_xmm(t0, a)
      if is_f32 {
        self.x86_emit_mulps_xmm_xmm(t0, b)
      } else {
        self.x86_emit_mulpd_xmm_xmm(t0, b)
      }
      if rd != acc {
        self.x86_emit_movaps_xmm_xmm(rd, acc)
      }
      if is_f32 {
        self.x86_emit_addps_xmm_xmm(rd, t0)
      } else {
        self.x86_emit_addpd_xmm_xmm(rd, t0)
      }
    }
    SIMDFMls(is_f32) => {
      // relaxed_nmadd: c - a * b
      let rd = wreg_num(inst.defs[0])
      let acc = reg_num(inst.uses[0])
      let a = reg_num(inst.uses[1])
      let b = reg_num(inst.uses[2])
      let t0 = 14
      self.x86_emit_movaps_xmm_xmm(t0, a)
      if is_f32 {
        self.x86_emit_mulps_xmm_xmm(t0, b)
      } else {
        self.x86_emit_mulpd_xmm_xmm(t0, b)
      }
      if rd != acc {
        self.x86_emit_movaps_xmm_xmm(rd, acc)
      }
      if is_f32 {
        self.x86_emit_subps_xmm_xmm(rd, t0)
      } else {
        self.x86_emit_subpd_xmm_xmm(rd, t0)
      }
    }
    SIMDRelaxedDot8to16 => {
      // Cranelift-aligned x64 strategy: PMADDUBSW with swapped operands.
      // rd = pmaddubsw(b_unsigned, a_signed)
      let rd = wreg_num(inst.defs[0])
      let tmp = wreg_num(inst.defs[1])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let rhs = prepare_xmm_two_operand(self, rd, b, a, tmp)
      self.x86_emit_pmaddubsw_xmm_xmm(rd, rhs)
    }
    SIMDRelaxedDot8to32Add => {
      // Cranelift-style sequence:
      // dot16 = pmaddubsw(b, a)
      // dot32 = pmaddwd(dot16, ones16)
      // rd = acc + dot32
      let rd = wreg_num(inst.defs[0])
      let dot = wreg_num(inst.defs[1])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let acc = reg_num(inst.uses[2])
      let ones = 14
      let scratch = isa.scratch_reg_1_index()
      if dot != b {
        self.x86_emit_movaps_xmm_xmm(dot, b)
      }
      self.x86_emit_pmaddubsw_xmm_xmm(dot, a)
      materialize_xmm_const(
        self, ones, 0x0001000100010001L, 0x0001000100010001L, scratch,
      )
      self.x86_emit_pmaddwd_xmm_xmm(dot, ones)
      if rd != acc {
        self.x86_emit_movaps_xmm_xmm(rd, acc)
      }
      self.x86_emit_padd_xmm_xmm(S32, rd, dot)
    }
    SIMDLoad(offset) => {
      let rd = wreg_num(inst.defs[0])
      let base = reg_num(inst.uses[0])
      self.x86_emit_movdqu_xmm_m128(rd, base, offset)
    }
    SIMDStore(offset) => {
      let vec = reg_num(inst.uses[0])
      let base = reg_num(inst.uses[1])
      self.x86_emit_movdqu_m128_xmm(base, offset, vec)
    }
    SIMDLoadSplat(lane_size, offset) => {
      // Note: current lowering passes `offset=0` because the effective address
      // already includes the wasm memory offset.
      let rd = wreg_num(inst.defs[0])
      let base = reg_num(inst.uses[0])
      let scratch1 = isa.scratch_reg_1_index()
      let scratch2 = isa.scratch_reg_2_index()
      match lane_size {
        B8 => {
          // i8x16 splat: load u8 -> movd -> pshufb with a zero mask.
          self.x86_emit_movzx_r32_m8(scratch1, base, offset)
          self.x86_emit_movd_xmm_r32(rd, scratch1)
          let mut mask = 14 // reserved via MachineEnvData.scratch_float
          if mask == rd {
            mask = 15
          }
          self.x86_emit_pxor_xmm_xmm(mask, mask)
          self.x86_emit_pshufb_xmm_xmm(rd, mask)
        }
        H16 => {
          // i16x8 splat: duplicate into a dword, then pshufd broadcast.
          self.x86_emit_movzx_r32_m16(scratch1, base, offset)
          self.x86_emit_mov_rr32(scratch2, scratch1)
          self.x86_emit_shl_r32_imm8(scratch2, 16)
          self.x86_emit_or_rr32(scratch2, scratch1)
          self.x86_emit_movd_xmm_r32(rd, scratch2)
          self.x86_emit_pshufd_xmm_xmm_imm8(rd, rd, 0x00)
        }
        S32 => {
          self.x86_emit_mov_r32_m32(scratch1, base, offset)
          self.x86_emit_movd_xmm_r32(rd, scratch1)
          self.x86_emit_pshufd_xmm_xmm_imm8(rd, rd, 0x00)
        }
        D64 => {
          self.x86_emit_mov_r64_m64(scratch1, base, offset)
          self.x86_emit_movq_xmm_r64(rd, scratch1)
          self.x86_emit_pshufd_xmm_xmm_imm8(rd, rd, 0x44)
        }
      }
    }
    SIMDLoadZero(is_64, offset) => {
      // Zero-extend 32-bit/64-bit scalar load into v128.
      let rd = wreg_num(inst.defs[0])
      let base = reg_num(inst.uses[0])
      self.x86_emit_pxor_xmm_xmm(rd, rd)
      if is_64 {
        self.x86_emit_movsd_xmm_m64(rd, base, offset)
      } else {
        self.x86_emit_movss_xmm_m32(rd, base, offset)
      }
    }
    SIMDLoadExtend(bits, signed, offset) => {
      // Extend lane values loaded from memory:
      // - 8x8 -> i16x8
      // - 16x4 -> i32x4
      // - 32x2 -> i64x2
      // Align with Cranelift x64 lowering using PMOVSX*/PMOVZX* (SSE4.1).
      let rd = wreg_num(inst.defs[0])
      let base = reg_num(inst.uses[0])
      let scratch_gpr = isa.scratch_reg_1_index()
      let mut tmp_xmm = 14 // reserved via MachineEnvData.scratch_float
      if tmp_xmm == rd {
        tmp_xmm = 15
      }
      // Load 64 bits and move into an XMM register.
      self.x86_emit_mov_r64_m64(scratch_gpr, base, offset)
      self.x86_emit_movq_xmm_r64(tmp_xmm, scratch_gpr)
      match bits {
        8 =>
          if signed {
            self.x86_emit_pmovsxbw_xmm_xmm(rd, tmp_xmm)
          } else {
            self.x86_emit_pmovzxbw_xmm_xmm(rd, tmp_xmm)
          }
        16 =>
          if signed {
            self.x86_emit_pmovsxwd_xmm_xmm(rd, tmp_xmm)
          } else {
            self.x86_emit_pmovzxwd_xmm_xmm(rd, tmp_xmm)
          }
        32 =>
          if signed {
            self.x86_emit_pmovsxdq_xmm_xmm(rd, tmp_xmm)
          } else {
            self.x86_emit_pmovzxdq_xmm_xmm(rd, tmp_xmm)
          }
        _ => abort("x86_64 SIMDLoadExtend: unsupported src bits \{bits}")
      }
    }
    SIMDLoadLane(lane_size, lane, offset) => {
      // Insert a scalar loaded from memory into one lane of an existing vector.
      let rd = wreg_num(inst.defs[0])
      let base = reg_num(inst.uses[0])
      let vec = reg_num(inst.uses[1])
      let scratch = isa.scratch_reg_1_index()
      if rd != vec {
        self.x86_emit_movaps_xmm_xmm(rd, vec)
      }
      match lane_size {
        B8 => {
          self.x86_emit_movzx_r32_m8(scratch, base, offset)
          self.x86_emit_pinsrb_xmm_r32_imm8(rd, scratch, lane)
        }
        H16 => {
          self.x86_emit_movzx_r32_m16(scratch, base, offset)
          self.x86_emit_pinsrw_xmm_r32_imm8(rd, scratch, lane)
        }
        S32 => {
          self.x86_emit_mov_r32_m32(scratch, base, offset)
          self.x86_emit_pinsrd_xmm_r32_imm8(rd, scratch, lane)
        }
        D64 => {
          self.x86_emit_mov_r64_m64(scratch, base, offset)
          self.x86_emit_pinsrq_xmm_r64_imm8(rd, scratch, lane)
        }
      }
    }
    SIMDStoreLane(lane_size, lane, offset) => {
      // Extract one lane from a vector and store it to memory.
      let base = reg_num(inst.uses[0])
      let vec = reg_num(inst.uses[1])
      let scratch = isa.scratch_reg_1_index()
      match lane_size {
        B8 => {
          self.x86_emit_pextrb_r32_xmm_imm8(scratch, vec, lane)
          self.x86_emit_mov_m8_r8(base, offset, scratch)
        }
        H16 => {
          self.x86_emit_pextrw_r32_xmm_imm8(scratch, vec, lane)
          self.x86_emit_mov_m16_r16(base, offset, scratch)
        }
        S32 => {
          self.x86_emit_pextrd_r32_xmm_imm8(scratch, vec, lane)
          self.x86_emit_mov_m32_r32(base, offset, scratch)
        }
        D64 => {
          self.x86_emit_pextrq_r64_xmm_imm8(scratch, vec, lane)
          self.x86_emit_mov_m64_r64(base, offset, scratch)
        }
      }
    }
    SIMDFCmp(is_f32, kind) => {
      // Align with Cranelift x64 vector fcmp lowering: use CMPP* immediates,
      // and for `gt/ge` swap operands and use `lt/le` predicate indices.
      let rd = wreg_num(inst.defs[0])
      let x = reg_num(inst.uses[0])
      let y = reg_num(inst.uses[1])
      let mut tmp = 14 // reserved via MachineEnvData.scratch_float
      if tmp == rd {
        tmp = 15
      }
      let (lhs, rhs, imm) = match kind {
        Eq => (x, y, 0)
        Gt => (y, x, 1) // a > b <=> b < a
        Ge => (y, x, 2) // a >= b <=> b <= a
      }
      let rhs_reg = prepare_xmm_two_operand(self, rd, lhs, rhs, tmp)
      if is_f32 {
        self.x86_emit_cmpps_xmm_xmm_imm8(rd, rhs_reg, imm)
      } else {
        self.x86_emit_cmppd_xmm_xmm_imm8(rd, rhs_reg, imm)
      }
    }
    SIMDFCvtToIntS(is_f32) => {
      // Match Cranelift x64 `fcvt_to_sint_sat` for f32x4:
      // handle NaN and overflow lanes in-vector.
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      if !is_f32 {
        emit_amd64_abort("SIMDFCvtToIntS f64x2 is not implemented")
      }
      let t0 = 14
      self.x86_emit_movaps_xmm_xmm(t0, src)
      self.x86_emit_cmpps_xmm_xmm_imm8(t0, t0, 0) // ordered equal: !NaN
      self.x86_emit_movaps_xmm_xmm(rd, src)
      self.x86_emit_andps_xmm_xmm(rd, t0)
      self.x86_emit_pxor_xmm_xmm(t0, rd)
      self.x86_emit_cvttps2dq_xmm_xmm(rd, rd)
      self.x86_emit_pand_xmm_xmm(t0, rd)
      self.x86_emit_psrad_xmm_imm8(t0, 31)
      self.x86_emit_pxor_xmm_xmm(rd, t0)
    }
    SIMDFCvtToIntU(is_f32) => {
      // Match Cranelift x64 `fcvt_to_uint_sat` for f32x4.
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      if !is_f32 {
        emit_amd64_abort("SIMDFCvtToIntU f64x2 is not implemented")
      }
      let t0 = 14
      let t1 = 15
      self.x86_emit_pxor_xmm_xmm(t1, t1) // zeros
      self.x86_emit_movaps_xmm_xmm(rd, src)
      self.x86_emit_maxps_xmm_xmm(rd, t1)
      self.x86_emit_pcmpeqd_xmm_xmm(t1, t1) // all ones
      self.x86_emit_psrld_xmm_imm8(t1, 1) // 0x7fffffff
      self.x86_emit_cvtdq2ps_xmm_xmm(t1, t1) // INT_MAX+1 as f32
      self.x86_emit_movaps_xmm_xmm(t0, rd)
      self.x86_emit_cvttps2dq_xmm_xmm(rd, rd)
      self.x86_emit_subps_xmm_xmm(t0, t1)
      self.x86_emit_cmpps_xmm_xmm_imm8(t1, t0, 2) // <=
      self.x86_emit_cvttps2dq_xmm_xmm(t0, t0)
      self.x86_emit_pxor_xmm_xmm(t0, t1)
      self.x86_emit_pxor_xmm_xmm(t1, t1)
      self.x86_emit_pmaxsd_xmm_xmm(t0, t1)
      self.x86_emit_padd_xmm_xmm(S32, rd, t0)
    }
    SIMDIntToFloatS(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      if is_f32 {
        self.x86_emit_cvtdq2ps_xmm_xmm(rd, src)
      } else {
        emit_amd64_abort("SIMDIntToFloatS f64x2 is not implemented")
      }
    }
    SIMDIntToFloatU(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      if !is_f32 {
        emit_amd64_abort("SIMDIntToFloatU f64x2 is not implemented")
      }
      // Match Cranelift x64 sequence for fcvt_from_uint i32x4 -> f32x4.
      let a_lo = 14
      let a_hi = 15
      self.x86_emit_movaps_xmm_xmm(a_lo, src)
      self.x86_emit_pslld_xmm_imm8(a_lo, 16)
      self.x86_emit_psrld_xmm_imm8(a_lo, 16)
      self.x86_emit_movaps_xmm_xmm(a_hi, src)
      self.x86_emit_psub_xmm_xmm(S32, a_hi, a_lo)
      self.x86_emit_cvtdq2ps_xmm_xmm(a_lo, a_lo)
      self.x86_emit_psrld_xmm_imm8(a_hi, 1)
      self.x86_emit_cvtdq2ps_xmm_xmm(a_hi, a_hi)
      self.x86_emit_addps_xmm_xmm(a_hi, a_hi)
      if rd != a_hi {
        self.x86_emit_movaps_xmm_xmm(rd, a_hi)
      }
      self.x86_emit_addps_xmm_xmm(rd, a_lo)
    }
    SIMDTruncSatF64ToI32SZero => {
      // Match Cranelift x64 special-case lowering for
      // i32x4.trunc_sat_f64x2_s_zero.
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      let t0 = 14
      let t1 = 15
      let scratch = isa.scratch_reg_1_index()
      self.x86_emit_movaps_xmm_xmm(t0, src)
      self.x86_emit_cmppd_xmm_xmm_imm8(t0, t0, 0) // ordered equal: !NaN
      materialize_xmm_const(
        self, t1, 0x41DFFFFFFFC00000L, 0x41DFFFFFFFC00000L, scratch,
      )
      self.x86_emit_andpd_xmm_xmm(t0, t1)
      self.x86_emit_movaps_xmm_xmm(rd, src)
      self.x86_emit_minpd_xmm_xmm(rd, t0)
      self.x86_emit_cvttpd2dq_xmm_xmm(rd, rd)
    }
    SIMDTruncSatF64ToI32UZero => {
      // Match Cranelift x64 special-case lowering for
      // i32x4.trunc_sat_f64x2_u_zero.
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      let t0 = 14
      let zeros = 15
      let scratch = isa.scratch_reg_1_index()
      self.x86_emit_xorpd_xmm_xmm(zeros, zeros)
      self.x86_emit_movaps_xmm_xmm(rd, src)
      self.x86_emit_maxpd_xmm_xmm(rd, zeros)
      materialize_xmm_const(
        self, t0, 0x41EFFFFFFFE00000L, 0x41EFFFFFFFE00000L, scratch,
      )
      self.x86_emit_minpd_xmm_xmm(rd, t0)
      self.x86_emit_roundpd_xmm_xmm_imm8(rd, rd, 3) // round toward zero
      materialize_xmm_const(
        self, t0, 0x4330000000000000L, 0x4330000000000000L, scratch,
      )
      self.x86_emit_addpd_xmm_xmm(rd, t0)
      self.x86_emit_shufps_xmm_xmm_imm8(rd, zeros, 0x88)
    }
    SIMDConvertLowI32ToF64S => {
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      self.x86_emit_cvtdq2pd_xmm_xmm(rd, src)
    }
    SIMDConvertLowI32ToF64U => {
      // Match Cranelift x64 `fcvt_from_uint (uwiden_low i32x4)` sequence.
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      let t0 = 14
      let scratch = isa.scratch_reg_1_index()
      materialize_xmm_const(self, t0, 0x4330000043300000L, 0L, scratch)
      if rd != src {
        self.x86_emit_movaps_xmm_xmm(rd, src)
      }
      self.x86_emit_unpcklps_xmm_xmm(rd, t0)
      materialize_xmm_const(
        self, t0, 0x4330000000000000L, 0x4330000000000000L, scratch,
      )
      self.x86_emit_subpd_xmm_xmm(rd, t0)
    }
    SIMDDemoteF64ToF32Zero => {
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      self.x86_emit_xorps_xmm_xmm(rd, rd)
      self.x86_emit_cvtpd2ps_xmm_xmm(rd, src)
    }
    SIMDPromoteLowF32ToF64 => {
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      self.x86_emit_cvtps2pd_xmm_xmm(rd, src)
    }
    SIMDFAdd(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let src = prepare_xmm_two_operand(self, rd, a, b, 14)
      if is_f32 {
        self.x86_emit_addps_xmm_xmm(rd, src)
      } else {
        self.x86_emit_addpd_xmm_xmm(rd, src)
      }
    }
    SIMDFSub(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let src = prepare_xmm_two_operand(self, rd, a, b, 14)
      if is_f32 {
        self.x86_emit_subps_xmm_xmm(rd, src)
      } else {
        self.x86_emit_subpd_xmm_xmm(rd, src)
      }
    }
    SIMDFMul(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let src = prepare_xmm_two_operand(self, rd, a, b, 14)
      if is_f32 {
        self.x86_emit_mulps_xmm_xmm(rd, src)
      } else {
        self.x86_emit_mulpd_xmm_xmm(rd, src)
      }
    }
    SIMDFDiv(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let src = prepare_xmm_two_operand(self, rd, a, b, 14)
      if is_f32 {
        self.x86_emit_divps_xmm_xmm(rd, src)
      } else {
        self.x86_emit_divpd_xmm_xmm(rd, src)
      }
    }
    SIMDFAbs(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      if rd != src {
        self.x86_emit_movaps_xmm_xmm(rd, src)
      }
      let mut mask = 14 // reserved via MachineEnvData.scratch_float
      if mask == rd {
        mask = 15
      }
      // mask = 0x7FFF.. (clear sign bit)
      self.x86_emit_pcmpeqd_xmm_xmm(mask, mask) // all ones
      if is_f32 {
        self.x86_emit_psrld_xmm_imm8(mask, 1)
      } else {
        self.x86_emit_psrlq_xmm_imm8(mask, 1)
      }
      self.x86_emit_pand_xmm_xmm(rd, mask)
    }
    SIMDFNeg(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      if rd != src {
        self.x86_emit_movaps_xmm_xmm(rd, src)
      }
      let mut sign = 14 // reserved via MachineEnvData.scratch_float
      if sign == rd {
        sign = 15
      }
      // sign = 0x8000.. (sign bit mask)
      self.x86_emit_pcmpeqd_xmm_xmm(sign, sign) // all ones
      if is_f32 {
        self.x86_emit_pslld_xmm_imm8(sign, 31)
      } else {
        self.x86_emit_psllq_xmm_imm8(sign, 63)
      }
      self.x86_emit_pxor_xmm_xmm(rd, sign)
    }
    SIMDFSqrt(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      if is_f32 {
        self.x86_emit_sqrtps_xmm_xmm(rd, src)
      } else {
        self.x86_emit_sqrtpd_xmm_xmm(rd, src)
      }
    }
    SIMDFCeil(is_f32) => {
      // Align with Cranelift x64 RoundImm encoding:
      //   ceil: 2 (RoundUp), floor: 1 (RoundDown), nearest: 0, trunc: 3 (RoundZero).
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      if is_f32 {
        self.x86_emit_roundps_xmm_xmm_imm8(rd, src, 2)
      } else {
        self.x86_emit_roundpd_xmm_xmm_imm8(rd, src, 2)
      }
    }
    SIMDFFloor(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      if is_f32 {
        self.x86_emit_roundps_xmm_xmm_imm8(rd, src, 1)
      } else {
        self.x86_emit_roundpd_xmm_xmm_imm8(rd, src, 1)
      }
    }
    SIMDFNearest(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      if is_f32 {
        self.x86_emit_roundps_xmm_xmm_imm8(rd, src, 0)
      } else {
        self.x86_emit_roundpd_xmm_xmm_imm8(rd, src, 0)
      }
    }
    SIMDFTrunc(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      if is_f32 {
        self.x86_emit_roundps_xmm_xmm_imm8(rd, src, 3)
      } else {
        self.x86_emit_roundpd_xmm_xmm_imm8(rd, src, 3)
      }
    }
    SIMDFMin(is_f32) => {
      // Floating-point minimum with NaN propagation and signed-zero rules,
      // aligned with Cranelift x64 lowering (see cranelift x64 lower.isle rules
      // for `fmin`).
      let rd = wreg_num(inst.defs[0])
      let x = reg_num(inst.uses[0])
      let y = reg_num(inst.uses[1])
      let t0 = 14 // reserved via MachineEnvData.scratch_float
      let t1 = 15 // reserved via MachineEnvData.scratch_float
      if is_f32 {
        // min1 = minps(x, y)
        self.x86_emit_movaps_xmm_xmm(t0, x)
        self.x86_emit_minps_xmm_xmm(t0, y)
        // min2 = minps(y, x)
        self.x86_emit_movaps_xmm_xmm(t1, y)
        self.x86_emit_minps_xmm_xmm(t1, x)
        // min_or = min1 | min2
        self.x86_emit_por_xmm_xmm(t0, t1)
        // is_nan_mask = cmp_unord(min2, min_or) (unordered is symmetric)
        self.x86_emit_cmpps_xmm_xmm_imm8(t1, t0, 3)
        // min_or_2 = min_or | is_nan_mask
        self.x86_emit_por_xmm_xmm(t0, t1)
        // nan_fraction_mask = is_nan_mask >> 10
        self.x86_emit_psrld_xmm_imm8(t1, 10)
        // final = andn(nan_fraction_mask, min_or_2)
        self.x86_emit_pandn_xmm_xmm(t1, t0)
        if rd != t1 {
          self.x86_emit_movaps_xmm_xmm(rd, t1)
        }
      } else {
        self.x86_emit_movaps_xmm_xmm(t0, x)
        self.x86_emit_minpd_xmm_xmm(t0, y)
        self.x86_emit_movaps_xmm_xmm(t1, y)
        self.x86_emit_minpd_xmm_xmm(t1, x)
        self.x86_emit_por_xmm_xmm(t0, t1)
        self.x86_emit_cmppd_xmm_xmm_imm8(t1, t0, 3)
        self.x86_emit_por_xmm_xmm(t0, t1)
        self.x86_emit_psrlq_xmm_imm8(t1, 13)
        self.x86_emit_pandn_xmm_xmm(t1, t0)
        if rd != t1 {
          self.x86_emit_movaps_xmm_xmm(rd, t1)
        }
      }
    }
    SIMDFMax(is_f32) => {
      // Floating-point maximum with NaN propagation and signed-zero rules,
      // aligned with Cranelift x64 lowering (see cranelift x64 lower.isle rules
      // for `fmax`).
      let rd = wreg_num(inst.defs[0])
      let x = reg_num(inst.uses[0])
      let y = reg_num(inst.uses[1])
      let t0 = 14 // reserved via MachineEnvData.scratch_float
      let t1 = 15 // reserved via MachineEnvData.scratch_float
      if is_f32 {
        // max1 = maxps(x, y)
        self.x86_emit_movaps_xmm_xmm(t0, x)
        self.x86_emit_maxps_xmm_xmm(t0, y)
        // max2 = maxps(y, x)
        self.x86_emit_movaps_xmm_xmm(t1, y)
        self.x86_emit_maxps_xmm_xmm(t1, x)
        // max_xor = max1 ^ max2
        self.x86_emit_pxor_xmm_xmm(t1, t0)
        // max_blended_nan = max1 | max_xor
        self.x86_emit_por_xmm_xmm(t0, t1)
        // max_blended_nan_positive = max_blended_nan - max_xor
        self.x86_emit_subps_xmm_xmm(t0, t1)
        // is_nan_mask = cmp_unord(max_blended_nan_positive, max_blended_nan_positive)
        self.x86_emit_movaps_xmm_xmm(t1, t0)
        self.x86_emit_cmpps_xmm_xmm_imm8(t1, t1, 3)
        // nan_fraction_mask = is_nan_mask >> 10
        self.x86_emit_psrld_xmm_imm8(t1, 10)
        // final = andn(nan_fraction_mask, max_blended_nan_positive)
        self.x86_emit_pandn_xmm_xmm(t1, t0)
        if rd != t1 {
          self.x86_emit_movaps_xmm_xmm(rd, t1)
        }
      } else {
        self.x86_emit_movaps_xmm_xmm(t0, x)
        self.x86_emit_maxpd_xmm_xmm(t0, y)
        self.x86_emit_movaps_xmm_xmm(t1, y)
        self.x86_emit_maxpd_xmm_xmm(t1, x)
        self.x86_emit_pxor_xmm_xmm(t1, t0)
        self.x86_emit_por_xmm_xmm(t0, t1)
        self.x86_emit_subpd_xmm_xmm(t0, t1)
        self.x86_emit_movaps_xmm_xmm(t1, t0)
        self.x86_emit_cmppd_xmm_xmm_imm8(t1, t1, 3)
        self.x86_emit_psrlq_xmm_imm8(t1, 13)
        self.x86_emit_pandn_xmm_xmm(t1, t0)
        if rd != t1 {
          self.x86_emit_movaps_xmm_xmm(rd, t1)
        }
      }
    }
    SIMDFPMin(is_f32) => {
      // Pseudo-min: match wasm pmin semantics (select-style, first operand
      // preferred on equality/unordered) by swapping operands for SSE MINP*,
      // which returns the second operand for equal/unordered cases.
      let rd = wreg_num(inst.defs[0])
      let x = reg_num(inst.uses[0])
      let y = reg_num(inst.uses[1])
      let tmp = 14 // reserved via MachineEnvData.scratch_float
      self.x86_emit_movaps_xmm_xmm(tmp, y)
      if is_f32 {
        self.x86_emit_minps_xmm_xmm(tmp, x)
      } else {
        self.x86_emit_minpd_xmm_xmm(tmp, x)
      }
      if rd != tmp {
        self.x86_emit_movaps_xmm_xmm(rd, tmp)
      }
    }
    SIMDFPMax(is_f32) => {
      // Pseudo-max: match wasm pmax semantics (select-style, first operand
      // preferred on equality/unordered) by swapping operands for SSE MAXP*,
      // which returns the second operand for equal/unordered cases.
      let rd = wreg_num(inst.defs[0])
      let x = reg_num(inst.uses[0])
      let y = reg_num(inst.uses[1])
      let tmp = 14 // reserved via MachineEnvData.scratch_float
      self.x86_emit_movaps_xmm_xmm(tmp, y)
      if is_f32 {
        self.x86_emit_maxps_xmm_xmm(tmp, x)
      } else {
        self.x86_emit_maxpd_xmm_xmm(tmp, x)
      }
      if rd != tmp {
        self.x86_emit_movaps_xmm_xmm(rd, tmp)
      }
    }
    SIMDMul(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      match lane_size {
        B8 => abort("x86_64 SIMDMul: unsupported lane size \{lane_size}")
        H16 => {
          let src = prepare_xmm_two_operand(self, rd, a, b, 14)
          self.x86_emit_pmullw_xmm_xmm(rd, src)
        }
        S32 => {
          let src = prepare_xmm_two_operand(self, rd, a, b, 14)
          self.x86_emit_pmulld_xmm_xmm(rd, src) // SSE4.1
        }
        D64 => {
          // Match Cranelift x64 lowering for i64x2.mul without AVX-512:
          //
          // a * b = (Al*Bl) + ((Ah*Bl + Al*Bh) << 32)
          // where A = [Ah:Al], B = [Bh:Bl] per 64-bit lane.
          let t0 = 14 // scratch
          let t1 = 15 // scratch

          // t0 = Ah * Bl
          self.x86_emit_movaps_xmm_xmm(t0, a)
          self.x86_emit_psrlq_xmm_imm8(t0, 32)
          self.x86_emit_pmuludq_xmm_xmm(t0, b)

          // t1 = Al * Bh
          self.x86_emit_movaps_xmm_xmm(t1, b)
          self.x86_emit_psrlq_xmm_imm8(t1, 32)
          self.x86_emit_pmuludq_xmm_xmm(t1, a)

          // t0 = (Ah*Bl + Al*Bh) << 32
          self.x86_emit_padd_xmm_xmm(D64, t0, t1)
          self.x86_emit_psllq_xmm_imm8(t0, 32)

          // t1 = Al * Bl
          self.x86_emit_movaps_xmm_xmm(t1, a)
          self.x86_emit_pmuludq_xmm_xmm(t1, b)

          // t1 += cross terms
          self.x86_emit_padd_xmm_xmm(D64, t1, t0)
          if rd != t1 {
            self.x86_emit_movaps_xmm_xmm(rd, t1)
          }
        }
      }
    }
    SIMDCmp(lane_size, kind) => {
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
      fn emit_i64x2_pcmpgt(
        self : MachineCode,
        rd : Int,
        lhs : Int,
        rhs : Int,
        t0 : Int,
        t1 : Int,
      ) -> Unit {
        // Match Cranelift x64 non-SSE4.2 i64x2 gt expansion from inst.isle.
        //
        // This sequence is written to be robust when `rd` aliases `lhs`/`rhs`:
        // copy inputs to scratch XMMs first, then freely clobber `rd`.
        self.x86_emit_movaps_xmm_xmm(t0, lhs) // t0 = lhs
        self.x86_emit_movaps_xmm_xmm(t1, rhs) // t1 = rhs
        // mask = 0x00000000_80000000 in each 64-bit lane (flip sign bit of lo32).
        // This must *not* broadcast to all dwords; match Cranelift exactly.
        materialize_xmm_const(
          self,
          rd,
          0x00000000_80000000L,
          0x00000000_80000000L,
          isa.scratch_reg_1_index(),
        )
        self.x86_emit_pxor_xmm_xmm(t0, rd) // t0 = lhs_masked
        self.x86_emit_pxor_xmm_xmm(t1, rd) // t1 = rhs_masked
        self.x86_emit_movaps_xmm_xmm(rd, t0) // rd = lhs_masked
        self.x86_emit_pcmpeqd_xmm_xmm(rd, t1) // rd = cmp_eq
        self.x86_emit_pcmpgt_xmm_xmm(S32, t0, t1) // t0 = cmp32
        self.x86_emit_pshufd_xmm_xmm_imm8(t1, t0, 0xA0) // t1 = low_halves_gt
        self.x86_emit_pshufd_xmm_xmm_imm8(t0, t0, 0xF5) // t0 = high_halves_gt
        self.x86_emit_pshufd_xmm_xmm_imm8(rd, rd, 0xF5) // rd = high_halves_eq
        self.x86_emit_pand_xmm_xmm(t1, rd)
        self.x86_emit_por_xmm_xmm(t1, t0)
        self.x86_emit_movaps_xmm_xmm(rd, t1)
      }

      match kind {
        Eq =>
          if lane_size is D64 {
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
        GtS =>
          if lane_size is D64 {
            emit_i64x2_pcmpgt(self, rd, x, y, t0, t1)
          } else {
            self.x86_emit_movaps_xmm_xmm(rd, x)
            self.x86_emit_pcmpgt_xmm_xmm(lane_size, rd, y)
          }
        GeS =>
          // a >= b  <=>  !(b > a)
          if lane_size is D64 {
            emit_i64x2_pcmpgt(self, rd, y, x, t0, t1)
            self.x86_emit_pcmpeqd_xmm_xmm(t0, t0)
            self.x86_emit_pxor_xmm_xmm(rd, t0)
          } else {
            self.x86_emit_movaps_xmm_xmm(rd, y)
            self.x86_emit_pcmpgt_xmm_xmm(lane_size, rd, x)
            self.x86_emit_pcmpeqd_xmm_xmm(t0, t0)
            self.x86_emit_pxor_xmm_xmm(rd, t0)
          }
        GtU => {
          if lane_size is D64 {
            abort(
              "x86_64 SIMDCmp.gt.u: i64x2 unsigned compare not supported by wasm SIMD",
            )
          }
          // Match Cranelift x64: flip sign bit and do signed compare.
          let pattern = match lane_size {
            B8 => 0x80808080
            H16 => 0x80008000
            S32 => 0x80000000
            D64 => 0
          }
          emit_broadcast_dword_pattern(self, rd, pattern)
          self.x86_emit_movaps_xmm_xmm(t0, x)
          self.x86_emit_pxor_xmm_xmm(t0, rd)
          self.x86_emit_movaps_xmm_xmm(t1, y)
          self.x86_emit_pxor_xmm_xmm(t1, rd)
          self.x86_emit_movaps_xmm_xmm(rd, t0)
          self.x86_emit_pcmpgt_xmm_xmm(lane_size, rd, t1)
        }
        GeU => {
          if lane_size is D64 {
            abort(
              "x86_64 SIMDCmp.ge.u: i64x2 unsigned compare not supported by wasm SIMD",
            )
          }
          // a >= b <=> !(b > a) after unsigned compare.
          let pattern = match lane_size {
            B8 => 0x80808080
            H16 => 0x80008000
            S32 => 0x80000000
            D64 => 0
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
    SIMDShuffle(lanes) => {
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
      let scratch_gpr = isa.scratch_reg_1_index()

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
      materialize_xmm_const(self, mask, low_a, high_a, scratch_gpr)
      self.x86_emit_pshufb_xmm_xmm(tmp_a, mask)
      materialize_xmm_const(self, mask, low_b, high_b, scratch_gpr)
      self.x86_emit_pshufb_xmm_xmm(tmp_b, mask)

      // rd = tmp_a | tmp_b
      if rd != tmp_a {
        self.x86_emit_movaps_xmm_xmm(rd, tmp_a)
      }
      self.x86_emit_por_xmm_xmm(rd, tmp_b)
    }
    SIMDSwizzle => {
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
      let scratch_gpr = isa.scratch_reg_1_index()
      if rd != values {
        self.x86_emit_movaps_xmm_xmm(rd, values)
      }
      self.x86_emit_movaps_xmm_xmm(mask, indices)
      materialize_xmm_const(
        self, c70, 0x7070707070707070L, 0x7070707070707070L, scratch_gpr,
      )
      self.x86_emit_paddusb_xmm_xmm(mask, c70)
      self.x86_emit_pshufb_xmm_xmm(rd, mask)
    }
    SIMDBsl => {
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
    SIMDAnyTrue => {
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
      self.x86_emit_pcmpeq_xmm_xmm(B8, tmp, zero)
      self.x86_emit_pmovmskb_r32_xmm(scratch, tmp)
      self.x86_emit_cmp_r32_imm32(scratch, 0xFFFF)
      self.x86_emit_setcc_r8(Ne, rd)
      self.x86_emit_movzx_r32_r8(rd, rd)
    }
    SIMDAllTrue(lane_size) => {
      // i*x*.all_true: return 1 if all lanes are non-zero, 0 otherwise.
      //
      // Match Cranelift-style lowering: compare lanes against zero, then use
      // PMOVMSKB to check whether any lane is zero.
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      let mut scratch = isa.scratch_reg_1_index()
      if scratch == rd {
        scratch = isa.scratch_reg_2_index()
      }
      let zero = 15 // reserved via MachineEnvData.scratch_float
      match lane_size {
        B8 | H16 | S32 => {
          // tmp is provided by lowering for B8/H16/S32.
          let tmp = wreg_num(inst.defs[1])
          self.x86_emit_movaps_xmm_xmm(tmp, src)
          self.x86_emit_pxor_xmm_xmm(zero, zero)
          self.x86_emit_pcmpeq_xmm_xmm(lane_size, tmp, zero) // lane == 0 => 0xFF..
          self.x86_emit_pmovmskb_r32_xmm(scratch, tmp)
          self.x86_emit_cmp_r32_imm32(scratch, 0)
          self.x86_emit_setcc_r8(Eq, rd)
          self.x86_emit_movzx_r32_r8(rd, rd)
        }
        D64 => {
          // No pcmpeqq without SSE4.1; emulate lane==0 with 32-bit compares.
          //
          // tmp = pcmpeqd(src, 0)
          // tmp_swapped = pshufd(tmp, 0xB1)
          // tmp = pand(tmp, tmp_swapped)  (both halves == 0)
          // any_zero = pmovmskb(tmp) != 0
          let tmp = 14 // reserved via MachineEnvData.scratch_float
          let tmp2 = 15 // reserved via MachineEnvData.scratch_float
          self.x86_emit_movaps_xmm_xmm(tmp, src)
          self.x86_emit_pxor_xmm_xmm(tmp2, tmp2) // tmp2 = 0
          self.x86_emit_pcmpeqd_xmm_xmm(tmp, tmp2)
          self.x86_emit_pshufd_xmm_xmm_imm8(tmp2, tmp, 0xB1)
          self.x86_emit_pand_xmm_xmm(tmp, tmp2)
          self.x86_emit_pmovmskb_r32_xmm(scratch, tmp)
          self.x86_emit_cmp_r32_imm32(scratch, 0)
          self.x86_emit_setcc_r8(Eq, rd)
          self.x86_emit_movzx_r32_r8(rd, rd)
        }
      }
    }
    SIMDBitmask(lane_size) => {
      // Extract the MSB/sign bit of each lane into a scalar i32.
      let rd = wreg_num(inst.defs[0])
      let src = reg_num(inst.uses[0])
      match lane_size {
        B8 => self.x86_emit_pmovmskb_r32_xmm(rd, src)
        H16 => {
          let tmp = 15 // reserved via MachineEnvData.scratch_float
          self.x86_emit_movaps_xmm_xmm(tmp, src)
          self.x86_emit_packsswb_xmm_xmm(tmp, tmp)
          self.x86_emit_pmovmskb_r32_xmm(rd, tmp)
          // packsswb(x, x) duplicates the 8-lane mask into both halves.
          self.x86_emit_shr_r32_imm8(rd, 8)
        }
        S32 => self.x86_emit_movmskps_r32_xmm(rd, src)
        D64 => self.x86_emit_movmskpd_r32_xmm(rd, src)
      }
    }
    StackLoad(offset) => {
      let rd = wreg_num(inst.defs[0])
      let def_class = match inst.defs[0].reg {
        Physical(preg) => preg.class
        Virtual(vreg) => vreg.class
      }
      let disp = spill_base_offset + offset
      match def_class {
        Int => self.x86_emit_mov_r64_m64(rd, 4, disp)
        Float32 | Float64 => self.x86_emit_movsd_xmm_m64(rd, 4, disp)
        Vector => self.x86_emit_movdqu_xmm_m128(rd, 4, disp)
      }
    }
    StackStore(offset) => {
      let rt = reg_num(inst.uses[0])
      let use_class = match inst.uses[0] {
        Physical(preg) => preg.class
        Virtual(vreg) => vreg.class
      }
      let disp = spill_base_offset + offset
      match use_class {
        Int => self.x86_emit_mov_m64_r64(4, disp, rt)
        Float32 | Float64 => self.x86_emit_movsd_m64_xmm(4, disp, rt)
        Vector => self.x86_emit_movdqu_m128_xmm(4, disp, rt)
      }
    }
    LoadStackParam(offset, class) => {
      // Load from [entry_sp + offset] where entry_sp = rsp + total_size.
      let rd = wreg_num(inst.defs[0])
      let disp = frame_size + offset
      match class {
        Int => self.x86_emit_mov_r64_m64(rd, 4, disp)
        Float32 | Float64 => self.x86_emit_movsd_xmm_m64(rd, 4, disp)
        Vector => self.x86_emit_movdqu_xmm_m128(rd, 4, disp)
      }
    }
  }
}
