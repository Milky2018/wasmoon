///|
fn MachineCode::emit_instruction(
  self : MachineCode,
  inst : @instr.Inst,
  stack_frame : EmitStackFrame,
) -> Unit {
  if self.isa is AMD64 {
    self.emit_instruction_x86_64(inst, stack_frame)
    return
  }
  // Cache stack-frame offsets used by spill and frame-slot emission.
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
        // 32-bit ADD immediate has the same encoding rules as 64-bit (just sf=0).
      } else if imm >= 0 && imm <= 4095 {
        self.emit_add_imm32(rd, rn, imm)
      } else if imm >= 0 && (imm & 0xFFF) == 0 && imm >> 12 <= 4095 {
        self.emit_add_imm32_shifted12(rd, rn, imm >> 12)
      } else {
        // Fallback: materialize immediate and use ADD (register).
        let scratch = self.isa.scratch_reg_1_index()
        self.emit_load_imm64(scratch, imm.to_int64())
        self.emit_add_reg32(rd, rn, scratch)
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
        // AArch64 SUB immediate can encode:
        // - imm12 directly (0-4095) when sh=0
        // - imm12 << 12 (multiples of 4096 up to 0xFFF000) when sh=1
        if imm >= 0 && imm <= 4095 {
          self.emit_sub_imm(rd, rn, imm)
        } else if imm >= 0 && (imm & 0xFFF) == 0 && imm >> 12 <= 4095 {
          self.emit_sub_imm_shifted12(rd, rn, imm >> 12)
        } else {
          // Fallback: materialize immediate and use SUB (register).
          let scratch = self.isa.scratch_reg_1_index()
          self.emit_load_imm64(scratch, imm.to_int64())
          self.emit_sub_reg(rd, rn, scratch)
        }
      } else if imm >= 0 && imm <= 4095 {
        self.emit_sub_imm32(rd, rn, imm)
      } else if imm >= 0 && (imm & 0xFFF) == 0 && imm >> 12 <= 4095 {
        self.emit_sub_imm32_shifted12(rd, rn, imm >> 12)
      } else {
        // Fallback: materialize immediate and use SUB (register).
        let scratch = self.isa.scratch_reg_1_index()
        self.emit_load_imm64(scratch, imm.to_int64())
        self.emit_sub_reg32(rd, rn, scratch)
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
    And(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_64 {
        self.emit_and_reg(rd, rn, rm)
      } else {
        self.emit_and_reg32(rd, rn, rm)
      }
    }
    AndNot(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_64 {
        self.emit_bic_reg(rd, rn, rm)
      } else {
        self.emit_bic_reg32(rd, rn, rm)
      }
    }
    AndImm(imm, is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match @instr.aarch64_logic_imm_enc_bits(imm, is_64) {
        Some(bits) =>
          if is_64 {
            self.emit_and_imm(rd, rn, bits)
          } else {
            self.emit_and_imm32(rd, rn, bits)
          }
        None => {
          // Fallback: materialize immediate and use AND (register).
          let scratch = self.isa.scratch_reg_1_index()
          self.emit_load_imm64(scratch, imm)
          if is_64 {
            self.emit_and_reg(rd, rn, scratch)
          } else {
            self.emit_and_reg32(rd, rn, scratch)
          }
        }
      }
    }
    Or(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_64 {
        self.emit_orr_reg(rd, rn, rm)
      } else {
        self.emit_orr_reg32(rd, rn, rm)
      }
    }
    OrNot(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_64 {
        self.emit_orn_reg(rd, rn, rm)
      } else {
        self.emit_orn_reg32(rd, rn, rm)
      }
    }
    OrImm(imm, is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match @instr.aarch64_logic_imm_enc_bits(imm, is_64) {
        Some(bits) =>
          if is_64 {
            self.emit_orr_imm(rd, rn, bits)
          } else {
            self.emit_orr_imm32(rd, rn, bits)
          }
        None => {
          let scratch = self.isa.scratch_reg_1_index()
          self.emit_load_imm64(scratch, imm)
          if is_64 {
            self.emit_orr_reg(rd, rn, scratch)
          } else {
            self.emit_orr_reg32(rd, rn, scratch)
          }
        }
      }
    }
    Xor(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_64 {
        self.emit_eor_reg(rd, rn, rm)
      } else {
        self.emit_eor_reg32(rd, rn, rm)
      }
    }
    XorNot(is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_64 {
        self.emit_eon_reg(rd, rn, rm)
      } else {
        self.emit_eon_reg32(rd, rn, rm)
      }
    }
    XorImm(imm, is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match @instr.aarch64_logic_imm_enc_bits(imm, is_64) {
        Some(bits) =>
          if is_64 {
            self.emit_eor_imm(rd, rn, bits)
          } else {
            self.emit_eor_imm32(rd, rn, bits)
          }
        None => {
          let scratch = self.isa.scratch_reg_1_index()
          self.emit_load_imm64(scratch, imm)
          if is_64 {
            self.emit_eor_reg(rd, rn, scratch)
          } else {
            self.emit_eor_reg32(rd, rn, scratch)
          }
        }
      }
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
    ShlImm(shift, is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_64 {
        self.emit_lsl_imm(rd, rn, shift)
      } else {
        self.emit_lsl_imm32(rd, rn, shift)
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
    AShrImm(shift, is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_64 {
        self.emit_asr_imm(rd, rn, shift)
      } else {
        self.emit_asr_imm32(rd, rn, shift)
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
    LShrImm(shift, is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_64 {
        self.emit_lsr_imm(rd, rn, shift)
      } else {
        self.emit_lsr_imm32(rd, rn, shift)
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
    RotrImm(shift, is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_64 {
        self.emit_ror_imm(rd, rn, shift)
      } else {
        self.emit_ror_imm32(rd, rn, shift)
      }
    }
    ExtrImm(shift, is_64) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_64 {
        self.emit_extr_imm(rd, rn, rm, shift)
      } else {
        self.emit_extr_imm32(rd, rn, rm, shift)
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
          // Fallback for cases rejected by the MachV type checker.
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
      // Fast path: cached embedding context-derived pointer 1.
      if stack_frame.embedding_abi is Some({ context_layout: Some(layout), .. }) {
        if stack_frame.cache_context_1 &&
          ty is I64 &&
          rn == stack_frame.context_reg_index() &&
          offset == layout.require_cache_role_offset(ContextCache1) {
          guard stack_frame.context_cache_1_index() is Some(cache_reg) else {
            abort("embedding context cache 1 register role is required")
          }
          if rt != cache_reg {
            self.emit_mov_reg(rt, cache_reg)
          }
          return
        }
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
    IntCmp(is_64) => {
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_64 {
        self.emit_cmp_reg(rn, rm)
      } else {
        self.emit_cmp_reg32(rn, rm)
      }
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
      // Compare the integer select condition with zero: CMP Wcond, #0
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
        AMD64(_) => abort("aarch64 TrapIf received an AMD64 condition")
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
      let cond_bits = aarch64_cond_bits(cond)
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
    AddExtend(ext, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match ext {
        ZeroExtend32 => self.emit_add_uxtw(rd, rn, rm, amount)
        SignExtend32 => self.emit_add_sxtw(rd, rn, rm, amount)
        None =>
          abort("AddExtend expects ZeroExtend32 or SignExtend32, got None")
      }
    }
    SubExtend(ext, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match ext {
        ZeroExtend32 => self.emit_sub_uxtw(rd, rn, rm, amount)
        SignExtend32 => self.emit_sub_sxtw(rd, rn, rm, amount)
        None =>
          abort("SubExtend expects ZeroExtend32 or SignExtend32, got None")
      }
    }
    AddShifted32(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_add_shifted32(rd, rn, rm, shift, amount)
    }
    SubShifted(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_sub_shifted(rd, rn, rm, shift, amount)
    }
    SubShifted32(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_sub_shifted32(rd, rn, rm, shift, amount)
    }
    AndShifted(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_and_shifted(rd, rn, rm, shift, amount)
    }
    AndShifted32(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_and_shifted32(rd, rn, rm, shift, amount)
    }
    OrShifted(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_orr_shifted(rd, rn, rm, shift, amount)
    }
    OrShifted32(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_orr_shifted32(rd, rn, rm, shift, amount)
    }
    XorShifted(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_eor_shifted(rd, rn, rm, shift, amount)
    }
    XorShifted32(shift, amount) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_eor_shifted32(rd, rn, rm, shift, amount)
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
    Madd32 => {
      // Wd = Wa + Wn * Wm, uses: [acc, src1, src2]
      let rd = wreg_num(inst.defs[0])
      let ra = reg_num(inst.uses[0]) // accumulator
      let rn = reg_num(inst.uses[1]) // multiplicand
      let rm = reg_num(inst.uses[2]) // multiplier
      self.emit_madd32(rd, rn, rm, ra)
    }
    Msub32 => {
      // Wd = Wa - Wn * Wm, uses: [acc, src1, src2]
      let rd = wreg_num(inst.defs[0])
      let ra = reg_num(inst.uses[0]) // accumulator
      let rn = reg_num(inst.uses[1]) // multiplicand
      let rm = reg_num(inst.uses[2]) // multiplier
      self.emit_msub32(rd, rn, rm, ra)
    }
    Mneg32 => {
      // Wd = -(Wn * Wm), uses: [src1, src2]
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      self.emit_mneg32(rd, rn, rm)
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
    ReturnCallIndirect(stack_arg_bytes, _num_results) => {
      // Tail call optimization.
      //
      // When no overflow stack args are involved we can emit a true tail jump:
      // epilogue + BR.
      //
      // With overflow stack args, the current ABI frame layout cannot guarantee
      // safe in-place tail stack forwarding for all cases, so lower to
      // call+return to preserve correctness.
      let target = match inst.use_constraints[0] {
        FixedReg(preg) => preg.index
        _ => reg_num(inst.uses[0])
      }
      if stack_arg_bytes > 0 {
        self.emit_blr(target)
        self.emit_epilogue(stack_frame)
        self.emit_ret(30)
      } else {
        self.emit_epilogue(stack_frame)
        self.emit_br(target)
      }
    }
    CallExternalIfI32NeImm(expected_value, helper_symbol) => {
      // Fast path for conditional helper calls:
      // - If actual == expected_value: do nothing.
      // - Otherwise: call helper(actual, expected_value).
      //
      // Uses: [actual_i32_vreg]
      let actual_value_reg = reg_num(inst.uses[0])
      if expected_value >= 0 && expected_value <= 4095 {
        self.emit_cmp_imm32(actual_value_reg, expected_value)
      } else {
        self.emit_load_imm64(17, expected_value.to_int64())
        self.emit_cmp_reg32(actual_value_reg, 17)
      }

      // Branch to done if equal.
      let done_label = -self.current_pos() - 1
      self.emit_b_cond(aarch64_cond_bits(Eq), done_label)

      // Slow path helper args: x0 = actual, x1 = expected.
      self.emit_mov_reg(0, actual_value_reg)
      self.emit_load_imm64(1, expected_value.to_int64())
      let fixup_offset = self.current_pos()
      self.emit_load_imm64_fixed(17, 0L)
      self.add_external_func_addr_fixup(fixup_offset, helper_symbol, 17)
      self.emit_blr(17)
      self.define_label(done_label)
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
    LoadPtr(ty, offset) => {
      // Raw pointer load (no bounds checking)
      // Uses: [base], Defs: [result]
      let result_reg = wreg_num(inst.defs[0])
      let base_reg = reg_num(inst.uses[0])
      self.emit_load(ty, result_reg, base_reg, offset)
    }
    LoadPtrRegOffset(ty, ext, shift, offset) => {
      // Raw pointer load with register offset (no bounds checking)
      // Uses: [base, index], Defs: [result]
      let result_reg = wreg_num(inst.defs[0])
      let base_reg = reg_num(inst.uses[0])
      let index_reg = reg_num(inst.uses[1])
      if offset != 0 {
        abort("LoadPtrRegOffset: non-zero offset not supported on AArch64")
      }
      self.emit_load_reg_offset(ty, result_reg, base_reg, index_reg, ext, shift)
    }
    LoadPtrNarrowRegOffset(bits, signed, ext, shift, offset) => {
      // Raw pointer narrow load with register offset (no bounds checking).
      let result_reg = wreg_num(inst.defs[0])
      let base_reg = reg_num(inst.uses[0])
      let index_reg = reg_num(inst.uses[1])
      if offset != 0 {
        abort(
          "LoadPtrNarrowRegOffset: non-zero offset not supported on AArch64",
        )
      }
      let option = index_extend_to_option(ext)
      match (bits, signed) {
        (8, false) =>
          self.emit_ldr_reg_offset(
            result_reg, base_reg, index_reg, option, 0, shift,
          )
        (16, false) =>
          self.emit_ldr_reg_offset(
            result_reg, base_reg, index_reg, option, 1, shift,
          )
        (32, false) =>
          self.emit_ldr_reg_offset(
            result_reg, base_reg, index_reg, option, 2, shift,
          )
        (8, true) => {
          self.emit_ldr_reg_offset(
            result_reg, base_reg, index_reg, option, 0, shift,
          )
          self.emit_sxtb_x(result_reg, result_reg)
        }
        (16, true) => {
          self.emit_ldr_reg_offset(
            result_reg, base_reg, index_reg, option, 1, shift,
          )
          self.emit_sxth_x(result_reg, result_reg)
        }
        (32, true) => {
          self.emit_ldr_reg_offset(
            result_reg, base_reg, index_reg, option, 2, shift,
          )
          self.emit_sxtw(result_reg, result_reg)
        }
        _ => abort("LoadPtrNarrowRegOffset: unsupported bits=\{bits}")
      }
    }
    StorePtr(ty, offset) => {
      // Raw pointer store (no bounds checking)
      // Uses: [base, value], Defs: []
      let base_reg = reg_num(inst.uses[0])
      let value_reg = reg_num(inst.uses[1])
      self.emit_store(ty, value_reg, base_reg, offset)
    }
    StorePtrRegOffset(ty, ext, shift, offset) => {
      // Raw pointer store with register offset (no bounds checking)
      // Uses: [base, index, value], Defs: []
      let base_reg = reg_num(inst.uses[0])
      let index_reg = reg_num(inst.uses[1])
      let value_reg = reg_num(inst.uses[2])
      if offset != 0 {
        abort("StorePtrRegOffset: non-zero offset not supported on AArch64")
      }
      self.emit_store_reg_offset(ty, value_reg, base_reg, index_reg, ext, shift)
    }
    StorePtrNarrowRegOffset(bits, ext, shift, offset) => {
      // Raw pointer narrow store with register offset (no bounds checking).
      let base_reg = reg_num(inst.uses[0])
      let index_reg = reg_num(inst.uses[1])
      let value_reg = reg_num(inst.uses[2])
      if offset != 0 {
        abort(
          "StorePtrNarrowRegOffset: non-zero offset not supported on AArch64",
        )
      }
      let option = index_extend_to_option(ext)
      match bits {
        8 =>
          self.emit_str_reg_offset(
            value_reg, base_reg, index_reg, option, 0, shift,
          )
        16 =>
          self.emit_str_reg_offset(
            value_reg, base_reg, index_reg, option, 1, shift,
          )
        32 =>
          self.emit_str_reg_offset(
            value_reg, base_reg, index_reg, option, 2, shift,
          )
        _ => abort("StorePtrNarrowRegOffset: unsupported bits=\{bits}")
      }
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
    LoadExternalFuncAddr(symbol) => {
      // Load external function pointer
      // Uses: [], Defs: [result (function pointer)]
      let result_reg = wreg_num(inst.defs[0])
      let fixup_offset = self.current_pos()
      self.emit_load_imm64_fixed(result_reg, 0L)
      self.add_external_func_addr_fixup(fixup_offset, symbol, result_reg)
    }
    LoadCodeAddr(symbol) => {
      // Load function address (patched at JIT load time)
      let result_reg = wreg_num(inst.defs[0])
      let fixup_offset = self.current_pos()
      self.emit_load_imm64_fixed(result_reg, 0L)
      self.add_code_addr_fixup(fixup_offset, symbol, result_reg)
    }
    // Emit BL with runtime fixup. A local veneer fallback is appended later
    // (during function finalization) for out-of-range targets.
    CallDirect(target, _num_args, _num_results, _call_conv) => {
      self.emit_bl_code(target)
      if stack_frame.cache_context_0 {
        let layout = stack_frame.require_embedding_context_layout()
        guard stack_frame.context_cache_0_index() is Some(cache_reg) else {
          abort("embedding context cache 0 register role is required")
        }
        self.emit_ldr_imm(
          cache_reg,
          stack_frame.context_reg_index(),
          layout.require_cache_role_offset(ContextCache0Source),
        )
      }
    }
    CallExternal(symbol, _num_args, _num_results, _call_conv) => {
      self.emit_bl_external(symbol)
      if stack_frame.cache_context_0 {
        let layout = stack_frame.require_embedding_context_layout()
        guard stack_frame.context_cache_0_index() is Some(cache_reg) else {
          abort("embedding context cache 0 register role is required")
        }
        self.emit_ldr_imm(
          cache_reg,
          stack_frame.context_reg_index(),
          layout.require_cache_role_offset(ContextCache0Source),
        )
      }
    }
    CallPtr(_, _, _call_conv) => {
      // Standard call: all arguments are already in place.
      // Use a fixed-reg constraint if present; otherwise use assigned reg.
      let target = match inst.use_constraints[0] {
        FixedReg(preg) => preg.index
        _ => reg_num(inst.uses[0])
      }
      self.emit_blr(target)
      if stack_frame.cache_context_0 {
        let layout = stack_frame.require_embedding_context_layout()
        guard stack_frame.context_cache_0_index() is Some(cache_reg) else {
          abort("embedding context cache 0 register role is required")
        }
        self.emit_ldr_imm(
          cache_reg,
          stack_frame.context_reg_index(),
          layout.require_cache_role_offset(ContextCache0Source),
        )
      }
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
      // Load outgoing-args base into result register.
      // StoreToStack writes to [SP + outgoing_args_offset + off], so LoadSP must
      // return the same base address to keep pointer-based runtime helpers
      // (hostcall/exception/GC) coherent.
      //
      // Uses ADD Xd, SP, #0 because MOV with SP has encoding issues.
      let result_reg = wreg_num(inst.defs[0])
      self.emit_add_imm(result_reg, 31, 0)
      let mut base_off = stack_frame.outgoing_args_offset
      while base_off > 0 {
        let chunk = if base_off > 4095 { 4095 } else { base_off }
        self.emit_add_imm(result_reg, result_reg, chunk)
        base_off = base_off - chunk
      }
      while base_off < 0 {
        let chunk = if base_off < -4095 { 4095 } else { -base_off }
        self.emit_sub_imm(result_reg, result_reg, chunk)
        base_off = base_off + chunk
      }
    }
    LoadSafepointId(root_count) => {
      let dst = wreg_num(inst.defs[0])
      let safepoint_root_indices : Array[Int] = []
      for i in 0..<root_count {
        safepoint_root_indices.push(i)
      }
      let safepoint_id = self.record_gc_safepoint(
        self.current_pos(),
        root_count~,
        root_indices=safepoint_root_indices,
      )
      self.emit_load_imm64(dst, safepoint_id.to_int64())
    }
    AMD64(_) => abort("verified AArch64 emission received an AMD64 opcode")
    // ============ SIMD Instructions ============
    _ =>
      self.emit_instruction_simd(
        inst, stack_frame, spill_base_offset, frame_size,
      )
  }
}
