///|
pub fn Instruction::emit(self : Instruction, mc : MachineCode) -> Unit {
  match self {
    LoadImm64(rd, imm) => {
      // Load a 64-bit immediate using MOVZ/MOVK or MOVN/MOVK sequence.
      // Prefer the shorter sequence; on ties prefer MOVZ to keep output stable.
      let hw0 = (imm & 0xFFFFL).to_int()
      let hw1 = ((imm >> 16) & 0xFFFFL).to_int()
      let hw2 = ((imm >> 32) & 0xFFFFL).to_int()
      let hw3 = ((imm >> 48) & 0xFFFFL).to_int()
      let halfwords = FixedArray::make(4, 0)
      halfwords[0] = hw0
      halfwords[1] = hw1
      halfwords[2] = hw2
      halfwords[3] = hw3
      let mut non_zero = 0
      let mut non_ffff = 0
      for i in 0..<4 {
        if halfwords[i] != 0 {
          non_zero = non_zero + 1
        }
        if halfwords[i] != 0xFFFF {
          non_ffff = non_ffff + 1
        }
      }
      let movz_count = if non_zero == 0 { 1 } else { non_zero }
      let movn_count = if non_ffff == 0 { 1 } else { non_ffff }
      if movn_count < movz_count {
        // MOVN strategy: start from all-ones, patch non-0xFFFF halfwords.
        if non_ffff == 0 {
          Movn(rd, 0, 0).emit(mc)
        } else {
          let mut init_i = 0
          while init_i < 4 && halfwords[init_i] == 0xFFFF {
            init_i = init_i + 1
          }
          let init_hw = halfwords[init_i]
          let init_imm = init_hw ^ 0xFFFF
          Movn(rd, init_imm, init_i * 16).emit(mc)
          for i in 0..<4 {
            if i != init_i && halfwords[i] != 0xFFFF {
              Movk(rd, halfwords[i], i * 16).emit(mc)
            }
          }
        }
        // MOVZ strategy: start from 0, patch non-zero halfwords.
      } else if non_zero == 0 {
        Movz(rd, 0, 0).emit(mc)
      } else {
        let mut init_i = 0
        while init_i < 4 && halfwords[init_i] == 0 {
          init_i = init_i + 1
        }
        Movz(rd, halfwords[init_i], init_i * 16).emit(mc)
        for i in 0..<4 {
          if i != init_i && halfwords[i] != 0 {
            Movk(rd, halfwords[i], i * 16).emit(mc)
          }
        }
      }
    }
    AlignTo(alignment) =>
      // Emit NOPs until aligned to the specified byte boundary
      while mc.current_pos() % alignment != 0 {
        Nop.emit(mc)
      }
    B(target_block) => {
      mc.annotate(self.annotate())
      let (b0, b1, b2, b3) = self.instr_bytes()
      mc.emit_inst(b0, b1, b2, b3)
      mc.add_fixup(target_block, FixupKind::Branch26)
    }
    BCond(_, target_block) => {
      mc.annotate(self.annotate())
      let (b0, b1, b2, b3) = self.instr_bytes()
      mc.emit_inst(b0, b1, b2, b3)
      mc.add_fixup(target_block, FixupKind::Branch19)
    }
    Cbz(_, target_block) => {
      mc.annotate(self.annotate())
      let (b0, b1, b2, b3) = self.instr_bytes()
      mc.emit_inst(b0, b1, b2, b3)
      mc.add_fixup(target_block, FixupKind::Branch19)
    }
    Cbnz(_, target_block) => {
      mc.annotate(self.annotate())
      let (b0, b1, b2, b3) = self.instr_bytes()
      mc.emit_inst(b0, b1, b2, b3)
      mc.add_fixup(target_block, FixupKind::Branch19)
    }
    Cbz32(_, target_block) => {
      mc.annotate(self.annotate())
      let (b0, b1, b2, b3) = self.instr_bytes()
      mc.emit_inst(b0, b1, b2, b3)
      mc.add_fixup(target_block, FixupKind::Branch19)
    }
    Cbnz32(_, target_block) => {
      mc.annotate(self.annotate())
      let (b0, b1, b2, b3) = self.instr_bytes()
      mc.emit_inst(b0, b1, b2, b3)
      mc.add_fixup(target_block, FixupKind::Branch19)
    }
    Bl(target_block) => {
      mc.annotate(self.annotate())
      let (b0, b1, b2, b3) = self.instr_bytes()
      mc.emit_inst(b0, b1, b2, b3)
      mc.add_fixup(target_block, FixupKind::Branch26)
    }
    _ => {
      mc.annotate(self.annotate())
      let (b0, b1, b2, b3) = self.instr_bytes()
      mc.emit_inst(b0, b1, b2, b3)
    }
  }
}

// ============ Public emit functions (backward compatibility) ============

///|
pub fn MachineCode::emit_add_reg(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  AddReg(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_add_shifted(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
  shift : @instr.ShiftType,
  amount : Int,
) -> Unit {
  AddShifted(rd, rn, rm, shift, amount).emit(self)
}

///|
pub fn MachineCode::emit_add_uxtw(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
  shift : Int,
) -> Unit {
  AddExtUxtw(rd, rn, rm, shift).emit(self)
}

///|
pub fn MachineCode::emit_sub_shifted(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
  shift : @instr.ShiftType,
  amount : Int,
) -> Unit {
  SubShifted(rd, rn, rm, shift, amount).emit(self)
}

///|
pub fn MachineCode::emit_and_shifted(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
  shift : @instr.ShiftType,
  amount : Int,
) -> Unit {
  AndShifted(rd, rn, rm, shift, amount).emit(self)
}

///|
pub fn MachineCode::emit_orr_shifted(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
  shift : @instr.ShiftType,
  amount : Int,
) -> Unit {
  OrrShifted(rd, rn, rm, shift, amount).emit(self)
}

///|
pub fn MachineCode::emit_eor_shifted(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
  shift : @instr.ShiftType,
  amount : Int,
) -> Unit {
  EorShifted(rd, rn, rm, shift, amount).emit(self)
}

///|
pub fn MachineCode::emit_madd(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
  ra : Int,
) -> Unit {
  Madd(rd, rn, rm, ra).emit(self)
}

///|
pub fn MachineCode::emit_msub(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
  ra : Int,
) -> Unit {
  Msub(rd, rn, rm, ra).emit(self)
}

///|
pub fn MachineCode::emit_mneg(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  Mneg(rd, rn, rm).emit(self)
}

///|
/// UMULH Xd, Xn, Xm - Unsigned multiply high (64-bit)
pub fn MachineCode::emit_umulh(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  Umulh(rd, rn, rm).emit(self)
}

///|
/// SMULH Xd, Xn, Xm - Signed multiply high (64-bit)
pub fn MachineCode::emit_smulh(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  Smulh(rd, rn, rm).emit(self)
}

///|
/// UMULL Xd, Wn, Wm - Unsigned 32x32->64 multiply
pub fn MachineCode::emit_umull(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  Umull(rd, rn, rm).emit(self)
}

///|
/// SMULL Xd, Wn, Wm - Signed 32x32->64 multiply
pub fn MachineCode::emit_smull(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  Smull(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_add_imm(
  self : MachineCode,
  rd : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  AddImm(rd, rn, imm12).emit(self)
}

///|
/// Emit ADD with immediate shifted left by 12 bits
pub fn MachineCode::emit_add_imm_shifted12(
  self : MachineCode,
  rd : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  AddImmShifted12(rd, rn, imm12).emit(self)
}

///|
pub fn MachineCode::emit_sub_imm_shifted12(
  self : MachineCode,
  rd : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  SubImmShifted12(rd, rn, imm12).emit(self)
}

///|
pub fn MachineCode::emit_sub_reg(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  SubReg(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_sub_imm(
  self : MachineCode,
  rd : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  SubImm(rd, rn, imm12).emit(self)
}

///|
pub fn MachineCode::emit_mul(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  Mul(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_sdiv(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  Sdiv(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_udiv(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  Udiv(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_and_reg(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  AndReg(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_and_reg32(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  AndReg32(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_and_imm(
  self : MachineCode,
  rd : Int,
  rn : Int,
  imm_bits : Int,
) -> Unit {
  AndImm(rd, rn, imm_bits).emit(self)
}

///|
pub fn MachineCode::emit_and_imm32(
  self : MachineCode,
  rd : Int,
  rn : Int,
  imm_bits : Int,
) -> Unit {
  AndImm32(rd, rn, imm_bits).emit(self)
}

///|
pub fn MachineCode::emit_orr_reg(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  OrrReg(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_orr_reg32(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  OrrReg32(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_orr_imm(
  self : MachineCode,
  rd : Int,
  rn : Int,
  imm_bits : Int,
) -> Unit {
  OrrImm(rd, rn, imm_bits).emit(self)
}

///|
pub fn MachineCode::emit_orr_imm32(
  self : MachineCode,
  rd : Int,
  rn : Int,
  imm_bits : Int,
) -> Unit {
  OrrImm32(rd, rn, imm_bits).emit(self)
}

///|
pub fn MachineCode::emit_eor_reg(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  EorReg(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_eor_reg32(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  EorReg32(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_eor_imm(
  self : MachineCode,
  rd : Int,
  rn : Int,
  imm_bits : Int,
) -> Unit {
  EorImm(rd, rn, imm_bits).emit(self)
}

///|
pub fn MachineCode::emit_eor_imm32(
  self : MachineCode,
  rd : Int,
  rn : Int,
  imm_bits : Int,
) -> Unit {
  EorImm32(rd, rn, imm_bits).emit(self)
}

///|
pub fn MachineCode::emit_lsl_reg(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  LslReg(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_asr_reg(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  AsrReg(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_lsr_reg(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  LsrReg(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_ror_reg(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  RorReg(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_mvn(self : MachineCode, rd : Int, rm : Int) -> Unit {
  Mvn(rd, rm).emit(self)
}

///|
pub fn MachineCode::emit_mvn32(self : MachineCode, rd : Int, rm : Int) -> Unit {
  Mvn32(rd, rm).emit(self)
}

///|
pub fn MachineCode::emit_clz(self : MachineCode, rd : Int, rn : Int) -> Unit {
  Clz(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_rbit(self : MachineCode, rd : Int, rn : Int) -> Unit {
  Rbit(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_sdiv32(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  Sdiv32(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_udiv32(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  Udiv32(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_sub_reg32(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  SubReg32(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_add_reg32(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  AddReg32(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_add_imm32(
  self : MachineCode,
  rd : Int,
  rn : Int,
  imm : Int,
) -> Unit {
  AddImm32(rd, rn, imm).emit(self)
}

///|
pub fn MachineCode::emit_add_imm32_shifted12(
  self : MachineCode,
  rd : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  AddImm32Shifted12(rd, rn, imm12).emit(self)
}

///|
pub fn MachineCode::emit_sub_imm32(
  self : MachineCode,
  rd : Int,
  rn : Int,
  imm : Int,
) -> Unit {
  SubImm32(rd, rn, imm).emit(self)
}

///|
pub fn MachineCode::emit_sub_imm32_shifted12(
  self : MachineCode,
  rd : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  SubImm32Shifted12(rd, rn, imm12).emit(self)
}

///|
pub fn MachineCode::emit_mul32(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  Mul32(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_lsl_reg32(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  LslReg32(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_lsr_reg32(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  LsrReg32(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_asr_reg32(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  AsrReg32(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_ror_reg32(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  RorReg32(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_lsr_imm(
  self : MachineCode,
  rd : Int,
  rn : Int,
  shift : Int,
) -> Unit {
  LsrImm(rd, rn, shift).emit(self)
}

///|
pub fn MachineCode::emit_lsr_imm32(
  self : MachineCode,
  rd : Int,
  rn : Int,
  shift : Int,
) -> Unit {
  LsrImm32(rd, rn, shift).emit(self)
}

///|
pub fn MachineCode::emit_lsl_imm(
  self : MachineCode,
  rd : Int,
  rn : Int,
  shift : Int,
) -> Unit {
  LslImm(rd, rn, shift).emit(self)
}

///|
pub fn MachineCode::emit_lsl_imm32(
  self : MachineCode,
  rd : Int,
  rn : Int,
  shift : Int,
) -> Unit {
  LslImm32(rd, rn, shift).emit(self)
}

///|
pub fn MachineCode::emit_asr_imm(
  self : MachineCode,
  rd : Int,
  rn : Int,
  shift : Int,
) -> Unit {
  AsrImm(rd, rn, shift).emit(self)
}

///|
pub fn MachineCode::emit_asr_imm32(
  self : MachineCode,
  rd : Int,
  rn : Int,
  shift : Int,
) -> Unit {
  AsrImm32(rd, rn, shift).emit(self)
}

///|
pub fn MachineCode::emit_ror_imm(
  self : MachineCode,
  rd : Int,
  rn : Int,
  shift : Int,
) -> Unit {
  RorImm(rd, rn, shift).emit(self)
}

///|
pub fn MachineCode::emit_ror_imm32(
  self : MachineCode,
  rd : Int,
  rn : Int,
  shift : Int,
) -> Unit {
  RorImm32(rd, rn, shift).emit(self)
}

///|
pub fn MachineCode::emit_clz32(self : MachineCode, rd : Int, rn : Int) -> Unit {
  Clz32(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_rbit32(self : MachineCode, rd : Int, rn : Int) -> Unit {
  Rbit32(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_cmp_reg32(
  self : MachineCode,
  rn : Int,
  rm : Int,
) -> Unit {
  CmpReg32(rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_cmp_imm32(
  self : MachineCode,
  rn : Int,
  imm : Int,
) -> Unit {
  // AArch64 CMP immediate supports a 12-bit unsigned immediate, optionally shifted left by 12.
  //
  // For larger/negative immediates, materialize the value in a reserved scratch register and
  // use CMP (register) instead. This avoids silent truncation of imm12.
  if imm >= 0 && imm <= 4095 {
    CmpImm32(rn, imm).emit(self)
  } else if imm >= 0 && (imm & 0xFFF) == 0 && imm >> 12 <= 4095 {
    CmpImm32Shifted12(rn, imm >> 12).emit(self)
  } else {
    let scratch = scratch1_index()
    self.emit_load_imm64(scratch, imm.to_int64())
    self.emit_cmp_reg32(rn, scratch)
  }
}

///|
fn MachineCode::emit_adds_imm_zr(
  self : MachineCode,
  rn : Int,
  imm12 : Int,
  is_64 : Bool,
) -> Unit {
  AddsImmZr(rn, imm12, is_64).emit(self)
}

///|
fn MachineCode::emit_ccmp_imm(
  self : MachineCode,
  rn : Int,
  imm5 : Int,
  nzcv : Int,
  cond : Int,
  is_64 : Bool,
) -> Unit {
  CCmpImm(rn, imm5, nzcv, cond, is_64).emit(self)
}

///|
pub fn MachineCode::emit_fcvtzs(
  self : MachineCode,
  rd : Int,
  rn : Int,
  int64~ : Bool,
  double~ : Bool,
) -> Unit {
  Fcvtzs(rd, rn, int64, double).emit(self)
}

///|
pub fn MachineCode::emit_fcvtzu(
  self : MachineCode,
  rd : Int,
  rn : Int,
  int64~ : Bool,
  double~ : Bool,
) -> Unit {
  Fcvtzu(rd, rn, int64, double).emit(self)
}

///|
pub fn MachineCode::emit_scvtf(
  self : MachineCode,
  rd : Int,
  rn : Int,
  int64~ : Bool,
  double~ : Bool,
) -> Unit {
  Scvtf(rd, rn, int64, double).emit(self)
}

///|
pub fn MachineCode::emit_ucvtf(
  self : MachineCode,
  rd : Int,
  rn : Int,
  int64~ : Bool,
  double~ : Bool,
) -> Unit {
  Ucvtf(rd, rn, int64, double).emit(self)
}

///|
pub fn MachineCode::emit_mov_reg(
  self : MachineCode,
  rd : Int,
  rm : Int,
) -> Unit {
  MovReg(rd, rm).emit(self)
}

///|
pub fn MachineCode::emit_mov_reg32(
  self : MachineCode,
  rd : Int,
  rm : Int,
) -> Unit {
  MovReg32(rd, rm).emit(self)
}

///|
pub fn MachineCode::emit_movz(
  self : MachineCode,
  rd : Int,
  imm16 : Int,
  shift : Int,
) -> Unit {
  Movz(rd, imm16, shift).emit(self)
}

///|
pub fn MachineCode::emit_movk(
  self : MachineCode,
  rd : Int,
  imm16 : Int,
  shift : Int,
) -> Unit {
  Movk(rd, imm16, shift).emit(self)
}

///|
pub fn MachineCode::emit_load_imm64(
  self : MachineCode,
  rd : Int,
  imm : Int64,
) -> Unit {
  LoadImm64(rd, imm).emit(self)
}

///|
/// Load 64-bit immediate with fixed 4 instructions (MOVZ + 3 MOVKs or NOPs).
/// Use this when you need a predictable instruction count for branch offset calculations.
pub fn MachineCode::emit_load_imm64_fixed(
  self : MachineCode,
  rd : Int,
  imm : Int64,
) -> Unit {
  let v0 = (imm & 0xFFFFL).to_int()
  let v1 = ((imm >> 16) & 0xFFFFL).to_int()
  let v2 = ((imm >> 32) & 0xFFFFL).to_int()
  let v3 = ((imm >> 48) & 0xFFFFL).to_int()
  // Always emit exactly 4 instructions
  Movz(rd, v0, 0).emit(self)
  Movk(rd, v1, 16).emit(self)
  Movk(rd, v2, 32).emit(self)
  Movk(rd, v3, 48).emit(self)
}

///|
pub fn MachineCode::emit_ldr_imm(
  self : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  LdrImm(rt, rn, imm12).emit(self)
}

///|
pub fn MachineCode::emit_ldr_imm_signed(
  self : MachineCode,
  rt : Int,
  rn : Int,
  simm9 : Int,
) -> Unit {
  LdrImmSigned(rt, rn, simm9).emit(self)
}

///|
pub fn MachineCode::emit_str_imm(
  self : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  StrImm(rt, rn, imm12).emit(self)
}

///|
pub fn MachineCode::emit_ldr_reg_scaled(
  self : MachineCode,
  rt : Int,
  rn : Int,
  rm : Int,
  shift : Int,
) -> Unit {
  LdrRegScaled(rt, rn, rm, shift).emit(self)
}

///|
pub fn MachineCode::emit_ldr_reg_offset(
  self : MachineCode,
  rt : Int,
  rn : Int,
  rm : Int,
  option : Int,
  size_bits : Int,
  shift : Int,
) -> Unit {
  LdrRegOffset(rt, rn, rm, option, size_bits, shift).emit(self)
}

///|
pub fn MachineCode::emit_str_reg_scaled(
  self : MachineCode,
  rt : Int,
  rn : Int,
  rm : Int,
  shift : Int,
) -> Unit {
  StrRegScaled(rt, rn, rm, shift).emit(self)
}

///|
pub fn MachineCode::emit_str_reg_offset(
  self : MachineCode,
  rt : Int,
  rn : Int,
  rm : Int,
  option : Int,
  size_bits : Int,
  shift : Int,
) -> Unit {
  StrRegOffset(rt, rn, rm, option, size_bits, shift).emit(self)
}

///|
pub fn MachineCode::emit_ldr_w_reg_scaled(
  self : MachineCode,
  rt : Int,
  rn : Int,
  rm : Int,
  shift : Int,
) -> Unit {
  LdrWRegScaled(rt, rn, rm, shift).emit(self)
}

///|
pub fn MachineCode::emit_str_w_reg_scaled(
  self : MachineCode,
  rt : Int,
  rn : Int,
  rm : Int,
  shift : Int,
) -> Unit {
  StrWRegScaled(rt, rn, rm, shift).emit(self)
}

///|
pub fn MachineCode::emit_ldrb_reg(
  self : MachineCode,
  rt : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  LdrbReg(rt, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_strb_reg(
  self : MachineCode,
  rt : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  StrbReg(rt, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_ldrh_reg(
  self : MachineCode,
  rt : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  LdrhReg(rt, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_strh_reg(
  self : MachineCode,
  rt : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  StrhReg(rt, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_ldrb_imm(
  self : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  LdrbImm(rt, rn, imm12).emit(self)
}

///|
pub fn MachineCode::emit_ldrh_imm(
  self : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  LdrhImm(rt, rn, imm12).emit(self)
}

///|
pub fn MachineCode::emit_ldr_w_imm(
  self : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  LdrWImm(rt, rn, imm12).emit(self)
}

///|
pub fn MachineCode::emit_strb_imm(
  self : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  StrbImm(rt, rn, imm12).emit(self)
}

///|
pub fn MachineCode::emit_strh_imm(
  self : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  StrhImm(rt, rn, imm12).emit(self)
}

///|
pub fn MachineCode::emit_str_w_imm(
  self : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  StrWImm(rt, rn, imm12).emit(self)
}

///|
pub fn MachineCode::emit_stp_pre(
  self : MachineCode,
  rt1 : Int,
  rt2 : Int,
  rn : Int,
  imm : Int,
) -> Unit {
  StpPre(rt1, rt2, rn, imm).emit(self)
}

///|
pub fn MachineCode::emit_ldp_post(
  self : MachineCode,
  rt1 : Int,
  rt2 : Int,
  rn : Int,
  imm : Int,
) -> Unit {
  LdpPost(rt1, rt2, rn, imm).emit(self)
}

///|
pub fn MachineCode::emit_ldrsb_x_imm(
  self : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  LdrsbXImm(rt, rn, imm12).emit(self)
}

///|
pub fn MachineCode::emit_ldrsb_w_imm(
  self : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  LdrsbWImm(rt, rn, imm12).emit(self)
}

///|
pub fn MachineCode::emit_ldrsh_x_imm(
  self : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  LdrshXImm(rt, rn, imm12).emit(self)
}

///|
pub fn MachineCode::emit_ldrsh_w_imm(
  self : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  LdrshWImm(rt, rn, imm12).emit(self)
}

///|
pub fn MachineCode::emit_ldrsw_imm(
  self : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  LdrswImm(rt, rn, imm12).emit(self)
}

///|
pub fn MachineCode::emit_sxtb_x(self : MachineCode, rd : Int, rn : Int) -> Unit {
  SxtbX(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_sxth_x(self : MachineCode, rd : Int, rn : Int) -> Unit {
  SxthX(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_sxtw(self : MachineCode, rd : Int, rn : Int) -> Unit {
  Sxtw(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_sxtb_w(self : MachineCode, rd : Int, rn : Int) -> Unit {
  SxtbW(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_sxth_w(self : MachineCode, rd : Int, rn : Int) -> Unit {
  SxthW(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_uxtb_x(self : MachineCode, rd : Int, rn : Int) -> Unit {
  UxtbX(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_uxth_x(self : MachineCode, rd : Int, rn : Int) -> Unit {
  UxthX(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_uxtb_w(self : MachineCode, rd : Int, rn : Int) -> Unit {
  UxtbW(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_uxth_w(self : MachineCode, rd : Int, rn : Int) -> Unit {
  UxthW(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_b(self : MachineCode, target_block : Int) -> Unit {
  B(target_block).emit(self)
}

///|
pub fn MachineCode::emit_b_cond(
  self : MachineCode,
  cond : Int,
  target_block : Int,
) -> Unit {
  BCond(cond, target_block).emit(self)
}

///|
pub fn MachineCode::emit_cbz(
  self : MachineCode,
  rt : Int,
  target_block : Int,
) -> Unit {
  Cbz(rt, target_block).emit(self)
}

///|
pub fn MachineCode::emit_cbnz(
  self : MachineCode,
  rt : Int,
  target_block : Int,
) -> Unit {
  Cbnz(rt, target_block).emit(self)
}

///|
pub fn MachineCode::emit_cbz32(
  self : MachineCode,
  rt : Int,
  target_block : Int,
) -> Unit {
  Cbz32(rt, target_block).emit(self)
}

///|
pub fn MachineCode::emit_cbnz32(
  self : MachineCode,
  rt : Int,
  target_block : Int,
) -> Unit {
  Cbnz32(rt, target_block).emit(self)
}

///|
fn MachineCode::emit_b_cond_offset(
  self : MachineCode,
  cond : Int,
  offset_bytes : Int,
) -> Unit {
  BCondOffset(cond, offset_bytes).emit(self)
}

///|
fn MachineCode::emit_brk(self : MachineCode, imm16 : Int) -> Unit {
  Brk(imm16).emit(self)
}

///|
fn MachineCode::emit_cbnz_offset(
  self : MachineCode,
  rt : Int,
  is_64 : Bool,
  offset_bytes : Int,
) -> Unit {
  CbnzOffset(rt, is_64, offset_bytes).emit(self)
}

///|
pub fn MachineCode::emit_ret(self : MachineCode, rn : Int) -> Unit {
  Ret(rn).emit(self)
}

///|
pub fn MachineCode::emit_br(self : MachineCode, rn : Int) -> Unit {
  Br(rn).emit(self)
}

///|
pub fn MachineCode::emit_adr(
  self : MachineCode,
  rd : Int,
  offset : Int,
) -> Unit {
  Adr(rd, offset).emit(self)
}

///|
pub fn MachineCode::emit_bl(self : MachineCode, target_block : Int) -> Unit {
  Bl(target_block).emit(self)
}

///|
pub fn MachineCode::emit_blr(self : MachineCode, rn : Int) -> Unit {
  Blr(rn).emit(self)
}

///|
pub fn MachineCode::emit_dmb_ish(self : MachineCode) -> Unit {
  DmbIsh.emit(self)
}

///|
pub fn MachineCode::emit_cmp_reg(
  self : MachineCode,
  rn : Int,
  rm : Int,
) -> Unit {
  CmpReg(rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_cmp_imm(
  self : MachineCode,
  rn : Int,
  imm : Int,
) -> Unit {
  // AArch64 CMP immediate supports a 12-bit unsigned immediate, optionally shifted left by 12.
  //
  // For larger/negative immediates, materialize the value in a reserved scratch register and
  // use CMP (register) instead. This avoids silent truncation of imm12.
  if imm >= 0 && imm <= 4095 {
    CmpImm(rn, imm).emit(self)
  } else if imm >= 0 && (imm & 0xFFF) == 0 && imm >> 12 <= 4095 {
    CmpImmShifted12(rn, imm >> 12).emit(self)
  } else {
    let scratch = scratch1_index()
    self.emit_load_imm64(scratch, imm.to_int64())
    self.emit_cmp_reg(rn, scratch)
  }
}

///|
pub fn MachineCode::emit_cset(self : MachineCode, rd : Int, cond : Int) -> Unit {
  Cset(rd, cond).emit(self)
}

///|
pub fn MachineCode::emit_csel(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
  cond : Int,
) -> Unit {
  Csel(rd, rn, rm, cond).emit(self)
}

///|
pub fn MachineCode::emit_fcsel_d(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
  cond : Int,
) -> Unit {
  FcselD(rd, rn, rm, cond).emit(self)
}

///|
pub fn MachineCode::emit_fcsel_s(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
  cond : Int,
) -> Unit {
  FcselS(rd, rn, rm, cond).emit(self)
}

///|
pub fn MachineCode::emit_fadd_d(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  FaddD(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_fadd_s(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  FaddS(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_fsub_d(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  FsubD(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_fsub_s(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  FsubS(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_fmul_d(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  FmulD(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_fmul_s(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  FmulS(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_fdiv_d(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  FdivD(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_fdiv_s(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  FdivS(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_fmax_d(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  FmaxD(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_fmax_s(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  FmaxS(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_fmin_d(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  FminD(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_fmin_s(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  FminS(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_fmaxnm_d(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  FmaxnmD(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_fmaxnm_s(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  FmaxnmS(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_fminnm_d(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  FminnmD(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_fminnm_s(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  FminnmS(rd, rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_fsqrt_d(
  self : MachineCode,
  rd : Int,
  rn : Int,
) -> Unit {
  FsqrtD(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_fsqrt_s(
  self : MachineCode,
  rd : Int,
  rn : Int,
) -> Unit {
  FsqrtS(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_fabs_d(self : MachineCode, rd : Int, rn : Int) -> Unit {
  FabsD(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_fabs_s(self : MachineCode, rd : Int, rn : Int) -> Unit {
  FabsS(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_fneg_d(self : MachineCode, rd : Int, rn : Int) -> Unit {
  FnegD(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_fneg_s(self : MachineCode, rd : Int, rn : Int) -> Unit {
  FnegS(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_frintp_d(
  self : MachineCode,
  rd : Int,
  rn : Int,
) -> Unit {
  FrintpD(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_frintp_s(
  self : MachineCode,
  rd : Int,
  rn : Int,
) -> Unit {
  FrintpS(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_frintm_d(
  self : MachineCode,
  rd : Int,
  rn : Int,
) -> Unit {
  FrintmD(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_frintm_s(
  self : MachineCode,
  rd : Int,
  rn : Int,
) -> Unit {
  FrintmS(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_frintz_d(
  self : MachineCode,
  rd : Int,
  rn : Int,
) -> Unit {
  FrintzD(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_frintz_s(
  self : MachineCode,
  rd : Int,
  rn : Int,
) -> Unit {
  FrintzS(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_frintn_d(
  self : MachineCode,
  rd : Int,
  rn : Int,
) -> Unit {
  FrintnD(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_frintn_s(
  self : MachineCode,
  rd : Int,
  rn : Int,
) -> Unit {
  FrintnS(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_fmov_d(self : MachineCode, rd : Int, rm : Int) -> Unit {
  FmovD(rd, rm).emit(self)
}

///|
pub fn MachineCode::emit_fmov_s(self : MachineCode, rd : Int, rm : Int) -> Unit {
  FmovS(rd, rm).emit(self)
}

///|
pub fn MachineCode::emit_fmov_d_to_x(
  self : MachineCode,
  rd : Int,
  rn : Int,
) -> Unit {
  FmovDToX(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_fmov_s_to_w(
  self : MachineCode,
  rd : Int,
  rn : Int,
) -> Unit {
  FmovSToW(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_fmov_x_to_d(
  self : MachineCode,
  rd : Int,
  rn : Int,
) -> Unit {
  FmovXToD(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_fmov_w_to_s(
  self : MachineCode,
  rd : Int,
  rn : Int,
) -> Unit {
  FmovWToS(rd, rn).emit(self)
}

///|
/// EXT Vd.16B, Vn.16B, Vm.16B, #imm
/// Extract and concatenate bytes from two vectors
/// imm is the byte offset (0-15)
pub fn MachineCode::emit_ext_16b(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
  imm : Int,
) -> Unit {
  // EXT Vd.16B, Vn.16B, Vm.16B, #imm: 0x6E000000 | (Rm << 16) | (imm4 << 11) | (Rn << 5) | Rd
  let enc = 0x6E000000 |
    ((rm & 31) << 16) |
    ((imm & 15) << 11) |
    ((rn & 31) << 5) |
    (rd & 31)
  let b0 = enc & 0xFF
  let b1 = (enc >> 8) & 0xFF
  let b2 = (enc >> 16) & 0xFF
  let b3 = (enc >> 24) & 0xFF
  self.emit_inst(b0, b1, b2, b3)
}

///|
pub fn MachineCode::emit_fcvt_d_s(
  self : MachineCode,
  rd : Int,
  rn : Int,
) -> Unit {
  FcvtDS(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_fcvt_s_d(
  self : MachineCode,
  rd : Int,
  rn : Int,
) -> Unit {
  FcvtSD(rd, rn).emit(self)
}

///|
pub fn MachineCode::emit_ldr_s_imm(
  self : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  LdrSImm(rt, rn, imm12).emit(self)
}

///|
pub fn MachineCode::emit_str_s_imm(
  self : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  StrSImm(rt, rn, imm12).emit(self)
}

///|
pub fn MachineCode::emit_ldr_d_imm(
  self : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  LdrDImm(rt, rn, imm12).emit(self)
}

///|
pub fn MachineCode::emit_str_d_imm(
  self : MachineCode,
  rt : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  StrDImm(rt, rn, imm12).emit(self)
}

///|
/// LDR Qt, [Xn, #imm] (128-bit Q-register load)
pub fn MachineCode::emit_ldr_q_imm(
  self : MachineCode,
  rt : Int,
  rn : Int,
  imm : Int,
) -> Unit {
  LdrQ(rt, rn, imm).emit(self)
}

///|
/// STR Qt, [Xn, #imm] (128-bit Q-register store)
pub fn MachineCode::emit_str_q_imm(
  self : MachineCode,
  rt : Int,
  rn : Int,
  imm : Int,
) -> Unit {
  StrQ(rt, rn, imm).emit(self)
}

///|
fn MachineCode::emit_str_offset(
  self : MachineCode,
  rt : Int,
  rn : Int,
  offset : Int,
) -> Unit {
  StrImm(rt, rn, offset).emit(self)
}

///|
fn MachineCode::emit_str_d_offset(
  self : MachineCode,
  rt : Int,
  rn : Int,
  offset : Int,
) -> Unit {
  StrDImm(rt, rn, offset).emit(self)
}

///|
/// Emit STP with signed offset (not pre/post indexed)
pub fn MachineCode::emit_stp_offset(
  self : MachineCode,
  rt1 : Int,
  rt2 : Int,
  rn : Int,
  offset : Int,
) -> Unit {
  StpOffset(rt1, rt2, rn, offset).emit(self)
}

///|
/// Emit LDP with signed offset (not pre/post indexed)
pub fn MachineCode::emit_ldp_offset(
  self : MachineCode,
  rt1 : Int,
  rt2 : Int,
  rn : Int,
  offset : Int,
) -> Unit {
  LdpOffset(rt1, rt2, rn, offset).emit(self)
}

///|
/// Emit STP for FPR pairs (64-bit D registers) with signed offset
pub fn MachineCode::emit_stp_d_offset(
  self : MachineCode,
  rt1 : Int,
  rt2 : Int,
  rn : Int,
  offset : Int,
) -> Unit {
  StpDOffset(rt1, rt2, rn, offset).emit(self)
}

///|
/// Emit LDP for FPR pairs (64-bit D registers) with signed offset
pub fn MachineCode::emit_ldp_d_offset(
  self : MachineCode,
  rt1 : Int,
  rt2 : Int,
  rn : Int,
  offset : Int,
) -> Unit {
  LdpDOffset(rt1, rt2, rn, offset).emit(self)
}

///|
/// Emit STR with pre-indexed addressing: STR Xt, [Xn, #simm9]!
pub fn MachineCode::emit_str_pre(
  self : MachineCode,
  rt : Int,
  rn : Int,
  simm9 : Int,
) -> Unit {
  StrPre(rt, rn, simm9).emit(self)
}

///|
/// Emit STP for FPR pairs with pre-indexed addressing: STP Dt1, Dt2, [Xn, #imm]!
pub fn MachineCode::emit_stp_d_pre(
  self : MachineCode,
  rt1 : Int,
  rt2 : Int,
  rn : Int,
  imm : Int,
) -> Unit {
  StpDPre(rt1, rt2, rn, imm).emit(self)
}

///|
/// Emit STR for FPR with pre-indexed addressing: STR Dt, [Xn, #simm9]!
pub fn MachineCode::emit_str_d_pre(
  self : MachineCode,
  rt : Int,
  rn : Int,
  simm9 : Int,
) -> Unit {
  StrDPre(rt, rn, simm9).emit(self)
}

///|
/// Emit LDR with post-indexed addressing: LDR Xt, [Xn], #simm9
pub fn MachineCode::emit_ldr_post(
  self : MachineCode,
  rt : Int,
  rn : Int,
  simm9 : Int,
) -> Unit {
  LdrPost(rt, rn, simm9).emit(self)
}

///|
/// Emit LDP for FPR pairs with post-indexed addressing: LDP Dt1, Dt2, [Xn], #imm
pub fn MachineCode::emit_ldp_d_post(
  self : MachineCode,
  rt1 : Int,
  rt2 : Int,
  rn : Int,
  imm : Int,
) -> Unit {
  LdpDPost(rt1, rt2, rn, imm).emit(self)
}

///|
/// Emit LDR for FPR with post-indexed addressing: LDR Dt, [Xn], #simm9
pub fn MachineCode::emit_ldr_d_post(
  self : MachineCode,
  rt : Int,
  rn : Int,
  simm9 : Int,
) -> Unit {
  LdrDPost(rt, rn, simm9).emit(self)
}

///|
pub fn MachineCode::emit_fcmp_d(self : MachineCode, rn : Int, rm : Int) -> Unit {
  FcmpD(rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_fcmp_s(self : MachineCode, rn : Int, rm : Int) -> Unit {
  FcmpS(rn, rm).emit(self)
}

///|
pub fn MachineCode::emit_nop(self : MachineCode) -> Unit {
  Nop.emit(self)
}

///|
/// CNT Vd.8B, Vn.8B - count bits in each byte
pub fn MachineCode::emit_cnt_8b(self : MachineCode, rd : Int, rn : Int) -> Unit {
  Cnt8B(rd, rn).emit(self)
}

///|
/// ADDV Bd, Vn.8B - sum all bytes into Bd
pub fn MachineCode::emit_addv_b(self : MachineCode, rd : Int, rn : Int) -> Unit {
  AddvB(rd, rn).emit(self)
}

// ============ VCode to Machine Code ============

///|
/// Check if a register is a callee-saved integer register (X19-X28).
///
/// Note: when `enable_pinned_reg` is enabled, the pinned VMContext register
/// (X21) is treated as globally-reserved and should be filtered out by callers.
fn is_callee_saved_alloc(reg : Int) -> Bool {
  reg >= 19 && reg <= 28
}

///|
fn is_callee_saved_fpr(reg : Int) -> Bool {
  reg >= 8 && reg <= 15
}
