///|
fn MachineCode::emit_instruction(
  self : MachineCode,
  inst : @instr.VCodeInst,
  stack_frame : JITStackFrame,
) -> Unit {
  if current_isa() is @isa.AMD64 {
    self.emit_instruction_x86_64(inst, stack_frame)
    return
  }
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
        // 32-bit ADD immediate has the same encoding rules as 64-bit (just sf=0).
      } else if imm >= 0 && imm <= 4095 {
        self.emit_add_imm32(rd, rn, imm)
      } else if imm >= 0 && (imm & 0xFFF) == 0 && imm >> 12 <= 4095 {
        self.emit_add_imm32_shifted12(rd, rn, imm >> 12)
      } else {
        // Fallback: materialize immediate and use ADD (register).
        let scratch = scratch1_index()
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
          let scratch = scratch1_index()
          self.emit_load_imm64(scratch, imm.to_int64())
          self.emit_sub_reg(rd, rn, scratch)
        }
      } else if imm >= 0 && imm <= 4095 {
        self.emit_sub_imm32(rd, rn, imm)
      } else if imm >= 0 && (imm & 0xFFF) == 0 && imm >> 12 <= 4095 {
        self.emit_sub_imm32_shifted12(rd, rn, imm >> 12)
      } else {
        // Fallback: materialize immediate and use SUB (register).
        let scratch = scratch1_index()
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
          let scratch = scratch1_index()
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
          let scratch = scratch1_index()
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
          let scratch = scratch1_index()
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
        rn == vmctx_index() &&
        offset == @abi.VMCTX_FUNC_TABLE_OFFSET {
        let func_table = func_table_index()
        if rt != func_table {
          self.emit_mov_reg(rt, func_table)
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
        Ps | Pc => abort("aarch64 TrapIf: parity conditions are x86_64-only")
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
      // BRK #2: trap (indirect call type mismatch)
      self.emit_brk(2)
    }
    TypeCheckSubtypeIndirect(expected_type) => {
      // Fast path for call_indirect type checks:
      // - If actual_type == expected_type: do nothing.
      // - Otherwise: call the runtime subtype checker (traps on failure).
      //
      // Uses: [actual_type_vreg]
      let actual_type_reg = reg_num(inst.uses[0])
      // Compare as i32 (type indices are 32-bit).
      if expected_type >= 0 && expected_type <= 4095 {
        self.emit_cmp_imm32(actual_type_reg, expected_type)
      } else {
        self.emit_load_imm64(17, expected_type.to_int64())
        self.emit_cmp_reg32(actual_type_reg, 17)
      }

      // Branch to done if equal.
      let done_label = -self.current_pos() - 1
      self.emit_b_cond(@instr.Cond::Eq.to_bits(), done_label)

      // Slow path: call gc_type_check_subtype_impl(actual, expected).
      // Args: x0 = actual_type, x1 = expected_type
      self.emit_mov_reg(0, actual_type_reg)
      self.emit_load_imm64(1, expected_type.to_int64())
      let func_ptr = @jit_ffi.c_jit_get_gc_type_check_subtype_ptr()
      self.emit_load_imm64(17, func_ptr)
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
    LoadMemBase(memidx) => {
      // Load linear memory base pointer from VMContext
      // Uses: [vmctx], Defs: [result]
      let dst = wreg_num(inst.defs[0])
      let vmctx_reg = reg_num(inst.uses[0])
      if memidx == 0 && stack_frame.cache_mem0_desc {
        // Fast path: memory0 descriptor pointer is cached in X20.
        self.emit_ldr_imm(dst, mem0_desc_index(), 0)
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
    LoadPtrRegOffset(ty, ext, shift) => {
      // Raw pointer load with register offset (no bounds checking)
      // Uses: [base, index], Defs: [result]
      let result_reg = wreg_num(inst.defs[0])
      let base_reg = reg_num(inst.uses[0])
      let index_reg = reg_num(inst.uses[1])
      self.emit_load_reg_offset(ty, result_reg, base_reg, index_reg, ext, shift)
    }
    LoadPtrNarrowRegOffset(bits, signed, ext, shift) => {
      // Raw pointer narrow load with register offset (no bounds checking).
      let result_reg = wreg_num(inst.defs[0])
      let base_reg = reg_num(inst.uses[0])
      let index_reg = reg_num(inst.uses[1])
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
    StorePtrRegOffset(ty, ext, shift) => {
      // Raw pointer store with register offset (no bounds checking)
      // Uses: [base, index, value], Defs: []
      let base_reg = reg_num(inst.uses[0])
      let index_reg = reg_num(inst.uses[1])
      let value_reg = reg_num(inst.uses[2])
      self.emit_store_reg_offset(ty, value_reg, base_reg, index_reg, ext, shift)
    }
    StorePtrNarrowRegOffset(bits, ext, shift) => {
      // Raw pointer narrow store with register offset (no bounds checking).
      let base_reg = reg_num(inst.uses[0])
      let index_reg = reg_num(inst.uses[1])
      let value_reg = reg_num(inst.uses[2])
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
        MemoryFillMem0 => @jit_ffi.c_jit_get_memory_fill_mem0_ptr()
        MemoryCopy => @jit_ffi.c_jit_get_memory_copy_ptr()
        MemoryCopyMem0 => @jit_ffi.c_jit_get_memory_copy_mem0_ptr()
        MemoryInit => @jit_ffi.c_jit_get_memory_init_ptr()
        DataDrop => @jit_ffi.c_jit_get_data_drop_ptr()
        TableGrow => @jit_ffi.c_jit_get_table_grow_ptr()
        TableFill => @jit_ffi.c_jit_get_table_fill_ptr()
        TableCopy => @jit_ffi.c_jit_get_table_copy_ptr()
        TableInit => @jit_ffi.c_jit_get_table_init_ptr()
        ElemDrop => @jit_ffi.c_jit_get_elem_drop_ptr()
        HostCall => @jit_ffi.c_jit_get_hostcall_ptr()
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
      // Emit BL with runtime fixup. A local veneer fallback is appended later
      // (during function finalization) for out-of-range targets.
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
    _ =>
      self.emit_instruction_simd(
        inst, stack_frame, spill_base_offset, frame_size,
      )
  }
}
