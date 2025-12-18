// AArch64 Instruction Encoding
// This module contains all AArch64 instruction encoders using an Instruction enum

///|
fn reg_num(reg : @abi.Reg) -> Int {
  match reg {
    Physical(preg) => preg.index
    Virtual(_) => abort("Virtual register in code emission")
  }
}

// Writable register encoding helper

///|
fn wreg_num(wreg : @abi.Writable) -> Int {
  reg_num(wreg.reg)
}

///|
/// AArch64 Instruction enum - covers all instruction types
enum Instruction {
  // Arithmetic - Register
  AddReg(Int, Int, Int)
  AddShifted(Int, Int, Int, @instr.ShiftType, Int)
  AddImm(Int, Int, Int)
  SubReg(Int, Int, Int)
  SubShifted(Int, Int, Int, @instr.ShiftType, Int)
  SubImm(Int, Int, Int)
  Mul(Int, Int, Int)
  Madd(Int, Int, Int, Int)
  Msub(Int, Int, Int, Int)
  Mneg(Int, Int, Int)
  Sdiv(Int, Int, Int)
  Udiv(Int, Int, Int)
  Sdiv32(Int, Int, Int) // 32-bit signed divide
  Udiv32(Int, Int, Int) // 32-bit unsigned divide
  SubReg32(Int, Int, Int) // 32-bit subtract
  // Bitwise - Register
  AndReg(Int, Int, Int)
  AndShifted(Int, Int, Int, @instr.ShiftType, Int)
  OrrReg(Int, Int, Int)
  OrrShifted(Int, Int, Int, @instr.ShiftType, Int)
  EorReg(Int, Int, Int)
  EorShifted(Int, Int, Int, @instr.ShiftType, Int)
  Mvn(Int, Int)
  // Shift/Rotate - Register (64-bit)
  LslReg(Int, Int, Int)
  LsrReg(Int, Int, Int)
  AsrReg(Int, Int, Int)
  RorReg(Int, Int, Int)
  // Shift/Rotate - Register (32-bit)
  LslReg32(Int, Int, Int)
  LsrReg32(Int, Int, Int)
  AsrReg32(Int, Int, Int)
  RorReg32(Int, Int, Int)
  // Bit manipulation (64-bit)
  Clz(Int, Int)
  Rbit(Int, Int)
  // Bit manipulation (32-bit)
  Clz32(Int, Int)
  Rbit32(Int, Int)
  // Move
  MovReg(Int, Int)
  MovReg32(Int, Int)
  Movz(Int, Int, Int)
  Movk(Int, Int, Int)
  LoadImm64(Int, Int64)
  // Load/Store - GPR
  LdrImm(Int, Int, Int)
  LdrImmSigned(Int, Int, Int)
  LdrRegScaled(Int, Int, Int, Int)
  StrImm(Int, Int, Int)
  StrRegScaled(Int, Int, Int, Int)
  LdrbImm(Int, Int, Int)
  LdrhImm(Int, Int, Int)
  LdrWImm(Int, Int, Int)
  StrbImm(Int, Int, Int)
  StrhImm(Int, Int, Int)
  StrWImm(Int, Int, Int)
  // Load/Store - Sign extend
  LdrsbXImm(Int, Int, Int)
  LdrsbWImm(Int, Int, Int)
  LdrshXImm(Int, Int, Int)
  LdrshWImm(Int, Int, Int)
  LdrswImm(Int, Int, Int)
  // Load/Store Pair
  StpPre(Int, Int, Int, Int)
  LdpPost(Int, Int, Int, Int)
  StpOffset(Int, Int, Int, Int) // rt1, rt2, rn, offset
  LdpOffset(Int, Int, Int, Int) // rt1, rt2, rn, offset
  StpDOffset(Int, Int, Int, Int) // rt1(d), rt2(d), rn, offset (FPR)
  LdpDOffset(Int, Int, Int, Int) // rt1(d), rt2(d), rn, offset (FPR)
  // Pre-indexed stores (Cranelift-style prologue)
  StrPre(Int, Int, Int) // rt, rn, simm9 - STR Xt, [Xn, #simm9]!
  StpDPre(Int, Int, Int, Int) // rt1, rt2, rn, imm7 - STP Dt1, Dt2, [Xn, #imm7]!
  StrDPre(Int, Int, Int) // rt, rn, simm9 - STR Dt, [Xn, #simm9]!
  // Post-indexed loads (Cranelift-style epilogue)
  LdrPost(Int, Int, Int) // rt, rn, simm9 - LDR Xt, [Xn], #simm9
  LdpDPost(Int, Int, Int, Int) // rt1, rt2, rn, imm7 - LDP Dt1, Dt2, [Xn], #imm7
  LdrDPost(Int, Int, Int) // rt, rn, simm9 - LDR Dt, [Xn], #simm9
  // Sign/Zero extension
  SxtbX(Int, Int)
  SxthX(Int, Int)
  Sxtw(Int, Int)
  SxtbW(Int, Int)
  SxthW(Int, Int)
  UxtbX(Int, Int)
  UxthX(Int, Int)
  UxtbW(Int, Int)
  UxthW(Int, Int)
  // Float conversion
  Fcvtzs(Int, Int, Bool, Bool)
  Fcvtzu(Int, Int, Bool, Bool)
  Scvtf(Int, Int, Bool, Bool)
  Ucvtf(Int, Int, Bool, Bool)
  // Float arithmetic
  FaddD(Int, Int, Int)
  FaddS(Int, Int, Int)
  FsubD(Int, Int, Int)
  FsubS(Int, Int, Int)
  FmulD(Int, Int, Int)
  FmulS(Int, Int, Int)
  FdivD(Int, Int, Int)
  FdivS(Int, Int, Int)
  FmaxD(Int, Int, Int)
  FmaxS(Int, Int, Int)
  FminD(Int, Int, Int)
  FminS(Int, Int, Int)
  FmaxnmD(Int, Int, Int)
  FmaxnmS(Int, Int, Int)
  FminnmD(Int, Int, Int)
  FminnmS(Int, Int, Int)
  // Float unary
  FsqrtD(Int, Int)
  FsqrtS(Int, Int)
  FabsD(Int, Int)
  FabsS(Int, Int)
  FnegD(Int, Int)
  FnegS(Int, Int)
  FrintpD(Int, Int)
  FrintpS(Int, Int)
  FrintmD(Int, Int)
  FrintmS(Int, Int)
  FrintzD(Int, Int)
  FrintzS(Int, Int)
  FrintnD(Int, Int)
  FrintnS(Int, Int)
  // Float move
  FmovD(Int, Int)
  FmovS(Int, Int)
  FmovDToX(Int, Int)
  FmovSToW(Int, Int)
  FmovXToD(Int, Int)
  FmovWToS(Int, Int)
  // Float conversion
  FcvtDS(Int, Int)
  FcvtSD(Int, Int)
  // Float load/store
  LdrSImm(Int, Int, Int)
  StrSImm(Int, Int, Int)
  LdrDImm(Int, Int, Int)
  StrDImm(Int, Int, Int)
  // Float compare
  FcmpD(Int, Int)
  FcmpS(Int, Int)
  // Comparison
  CmpReg(Int, Int)
  CmpReg32(Int, Int) // 32-bit compare
  CmpImm(Int, Int)
  CmpImm32(Int, Int) // 32-bit compare immediate
  // ADDS XZR/WZR, Xn, #imm - add immediate and set flags (result discarded)
  AddsImmZr(Int, Int, Bool) // rn, imm12, is_64
  // CCMP Xn, #imm, #nzcv, cond - conditional compare immediate
  CCmpImm(Int, Int, Int, Int, Bool) // rn, imm5, nzcv, cond, is_64
  Cset(Int, Int)
  Csel(Int, Int, Int, Int)
  FcselD(Int, Int, Int, Int)
  FcselS(Int, Int, Int, Int)
  // Branch
  B(Int)
  BCond(Int, Int)
  Cbz(Int, Int)
  Cbnz(Int, Int)
  BCondOffset(Int, Int)
  CbnzOffset(Int, Bool, Int) // rt, is_64, offset_bytes - branch if not zero with immediate offset
  Brk(Int)
  Ret(Int)
  Br(Int)
  Bl(Int)
  Blr(Int)
  Adr(Int, Int)
  // Memory barrier
  DmbIsh
  // NOP
  Nop
  // Alignment helper (emits multiple NOPs)
  AlignTo(Int)
  // SIMD for popcnt
  Cnt8B(Int, Int) // CNT Vd.8B, Vn.8B - count bits in each byte
  AddvB(Int, Int) // ADDV Bd, Vn.8B - sum all bytes
}

///|
fn Instruction::annotate(self : Instruction) -> String {
  match self {
    AddReg(rd, rn, rm) => "add x\{rd}, x\{rn}, x\{rm}"
    AddShifted(rd, rn, rm, shift, amount) => {
      let shift_name = match shift {
        Lsl => "lsl"
        Lsr => "lsr"
        Asr => "asr"
      }
      "add x\{rd}, x\{rn}, x\{rm}, \{shift_name} #\{amount}"
    }
    AddImm(rd, rn, imm12) => {
      let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
      let rd_name = if rd == 31 { "sp" } else { "x\{rd}" }
      "add \{rd_name}, \{rn_name}, #\{imm12}"
    }
    SubReg(rd, rn, rm) => "sub x\{rd}, x\{rn}, x\{rm}"
    SubShifted(rd, rn, rm, shift, amount) => {
      let shift_name = match shift {
        Lsl => "lsl"
        Lsr => "lsr"
        Asr => "asr"
      }
      "sub x\{rd}, x\{rn}, x\{rm}, \{shift_name} #\{amount}"
    }
    SubImm(rd, rn, imm12) => {
      let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
      let rd_name = if rd == 31 { "sp" } else { "x\{rd}" }
      "sub \{rd_name}, \{rn_name}, #\{imm12}"
    }
    Mul(rd, rn, rm) => "mul x\{rd}, x\{rn}, x\{rm}"
    Madd(rd, rn, rm, ra) => "madd x\{rd}, x\{rn}, x\{rm}, x\{ra}"
    Msub(rd, rn, rm, ra) => "msub x\{rd}, x\{rn}, x\{rm}, x\{ra}"
    Mneg(rd, rn, rm) => "mneg x\{rd}, x\{rn}, x\{rm}"
    Sdiv(rd, rn, rm) => "sdiv x\{rd}, x\{rn}, x\{rm}"
    Udiv(rd, rn, rm) => "udiv x\{rd}, x\{rn}, x\{rm}"
    Sdiv32(rd, rn, rm) => "sdiv w\{rd}, w\{rn}, w\{rm}"
    Udiv32(rd, rn, rm) => "udiv w\{rd}, w\{rn}, w\{rm}"
    SubReg32(rd, rn, rm) => "sub w\{rd}, w\{rn}, w\{rm}"
    AndReg(rd, rn, rm) => "and x\{rd}, x\{rn}, x\{rm}"
    AndShifted(rd, rn, rm, shift, amount) => {
      let shift_name = match shift {
        Lsl => "lsl"
        Lsr => "lsr"
        Asr => "asr"
      }
      "and x\{rd}, x\{rn}, x\{rm}, \{shift_name} #\{amount}"
    }
    OrrReg(rd, rn, rm) => "orr x\{rd}, x\{rn}, x\{rm}"
    OrrShifted(rd, rn, rm, shift, amount) => {
      let shift_name = match shift {
        Lsl => "lsl"
        Lsr => "lsr"
        Asr => "asr"
      }
      "orr x\{rd}, x\{rn}, x\{rm}, \{shift_name} #\{amount}"
    }
    EorReg(rd, rn, rm) => "eor x\{rd}, x\{rn}, x\{rm}"
    EorShifted(rd, rn, rm, shift, amount) => {
      let shift_name = match shift {
        Lsl => "lsl"
        Lsr => "lsr"
        Asr => "asr"
      }
      "eor x\{rd}, x\{rn}, x\{rm}, \{shift_name} #\{amount}"
    }
    Mvn(rd, rm) => "mvn x\{rd}, x\{rm}"
    LslReg(rd, rn, rm) => "lsl x\{rd}, x\{rn}, x\{rm}"
    LsrReg(rd, rn, rm) => "lsr x\{rd}, x\{rn}, x\{rm}"
    AsrReg(rd, rn, rm) => "asr x\{rd}, x\{rn}, x\{rm}"
    RorReg(rd, rn, rm) => "ror x\{rd}, x\{rn}, x\{rm}"
    LslReg32(rd, rn, rm) => "lsl w\{rd}, w\{rn}, w\{rm}"
    LsrReg32(rd, rn, rm) => "lsr w\{rd}, w\{rn}, w\{rm}"
    AsrReg32(rd, rn, rm) => "asr w\{rd}, w\{rn}, w\{rm}"
    RorReg32(rd, rn, rm) => "ror w\{rd}, w\{rn}, w\{rm}"
    Clz(rd, rn) => "clz x\{rd}, x\{rn}"
    Rbit(rd, rn) => "rbit x\{rd}, x\{rn}"
    Clz32(rd, rn) => "clz w\{rd}, w\{rn}"
    Rbit32(rd, rn) => "rbit w\{rd}, w\{rn}"
    MovReg(rd, rm) => "mov x\{rd}, x\{rm}"
    MovReg32(rd, rm) => "mov w\{rd}, w\{rm}"
    Movz(rd, imm16, shift) => "movz x\{rd}, #\{imm16}, lsl #\{shift}"
    Movk(rd, imm16, shift) => "movk x\{rd}, #\{imm16}, lsl #\{shift}"
    LoadImm64(_, _) => "load_imm64 (multi-instruction)"
    LdrImm(rt, rn, imm12) => "ldr x\{rt}, [x\{rn}, #\{imm12}]"
    LdrImmSigned(rt, rn, simm9) => "ldur x\{rt}, [x\{rn}, #\{simm9}]"
    LdrRegScaled(rt, rn, rm, shift) =>
      "ldr x\{rt}, [x\{rn}, x\{rm}, lsl #\{shift}]"
    StrImm(rt, rn, imm12) => "str x\{rt}, [x\{rn}, #\{imm12}]"
    StrRegScaled(rt, rn, rm, shift) =>
      "str x\{rt}, [x\{rn}, x\{rm}, lsl #\{shift}]"
    LdrbImm(rt, rn, imm12) => "ldrb w\{rt}, [x\{rn}, #\{imm12}]"
    LdrhImm(rt, rn, imm12) => "ldrh w\{rt}, [x\{rn}, #\{imm12}]"
    LdrWImm(rt, rn, imm12) => "ldr w\{rt}, [x\{rn}, #\{imm12}]"
    StrbImm(rt, rn, imm12) => "strb w\{rt}, [x\{rn}, #\{imm12}]"
    StrhImm(rt, rn, imm12) => "strh w\{rt}, [x\{rn}, #\{imm12}]"
    StrWImm(rt, rn, imm12) => "str w\{rt}, [x\{rn}, #\{imm12}]"
    LdrsbXImm(rt, rn, imm12) => "ldrsb x\{rt}, [x\{rn}, #\{imm12}]"
    LdrsbWImm(rt, rn, imm12) => "ldrsb w\{rt}, [x\{rn}, #\{imm12}]"
    LdrshXImm(rt, rn, imm12) => "ldrsh x\{rt}, [x\{rn}, #\{imm12}]"
    LdrshWImm(rt, rn, imm12) => "ldrsh w\{rt}, [x\{rn}, #\{imm12}]"
    LdrswImm(rt, rn, imm12) => "ldrsw x\{rt}, [x\{rn}, #\{imm12}]"
    StpPre(rt1, rt2, rn, imm) => {
      let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
      "stp x\{rt1}, x\{rt2}, [\{rn_name}, #\{imm}]!"
    }
    LdpPost(rt1, rt2, rn, imm) => {
      let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
      "ldp x\{rt1}, x\{rt2}, [\{rn_name}], #\{imm}"
    }
    StpOffset(rt1, rt2, rn, offset) => {
      let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
      "stp x\{rt1}, x\{rt2}, [\{rn_name}, #\{offset}]"
    }
    LdpOffset(rt1, rt2, rn, offset) => {
      let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
      "ldp x\{rt1}, x\{rt2}, [\{rn_name}, #\{offset}]"
    }
    StpDOffset(rt1, rt2, rn, offset) => {
      let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
      "stp d\{rt1}, d\{rt2}, [\{rn_name}, #\{offset}]"
    }
    LdpDOffset(rt1, rt2, rn, offset) => {
      let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
      "ldp d\{rt1}, d\{rt2}, [\{rn_name}, #\{offset}]"
    }
    StrPre(rt, rn, simm9) => {
      let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
      "str x\{rt}, [\{rn_name}, #\{simm9}]!"
    }
    StpDPre(rt1, rt2, rn, imm) => {
      let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
      "stp d\{rt1}, d\{rt2}, [\{rn_name}, #\{imm}]!"
    }
    StrDPre(rt, rn, simm9) => {
      let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
      "str d\{rt}, [\{rn_name}, #\{simm9}]!"
    }
    LdrPost(rt, rn, simm9) => {
      let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
      "ldr x\{rt}, [\{rn_name}], #\{simm9}"
    }
    LdpDPost(rt1, rt2, rn, imm) => {
      let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
      "ldp d\{rt1}, d\{rt2}, [\{rn_name}], #\{imm}"
    }
    LdrDPost(rt, rn, simm9) => {
      let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
      "ldr d\{rt}, [\{rn_name}], #\{simm9}"
    }
    SxtbX(rd, rn) => "sxtb x\{rd}, w\{rn}"
    SxthX(rd, rn) => "sxth x\{rd}, w\{rn}"
    Sxtw(rd, rn) => "sxtw x\{rd}, w\{rn}"
    SxtbW(rd, rn) => "sxtb w\{rd}, w\{rn}"
    SxthW(rd, rn) => "sxth w\{rd}, w\{rn}"
    UxtbX(rd, rn) => "uxtb x\{rd}, w\{rn}"
    UxthX(rd, rn) => "uxth x\{rd}, w\{rn}"
    UxtbW(rd, rn) => "uxtb w\{rd}, w\{rn}"
    UxthW(rd, rn) => "uxth w\{rd}, w\{rn}"
    Fcvtzs(rd, rn, int64, double) => {
      let int_name = if int64 { "x" } else { "w" }
      let float_name = if double { "d" } else { "s" }
      "fcvtzs \{int_name}\{rd}, \{float_name}\{rn}"
    }
    Fcvtzu(rd, rn, int64, double) => {
      let int_name = if int64 { "x" } else { "w" }
      let float_name = if double { "d" } else { "s" }
      "fcvtzu \{int_name}\{rd}, \{float_name}\{rn}"
    }
    Scvtf(rd, rn, int64, double) => {
      let int_name = if int64 { "x" } else { "w" }
      let float_name = if double { "d" } else { "s" }
      "scvtf \{float_name}\{rd}, \{int_name}\{rn}"
    }
    Ucvtf(rd, rn, int64, double) => {
      let int_name = if int64 { "x" } else { "w" }
      let float_name = if double { "d" } else { "s" }
      "ucvtf \{float_name}\{rd}, \{int_name}\{rn}"
    }
    FaddD(rd, rn, rm) => "fadd d\{rd}, d\{rn}, d\{rm}"
    FaddS(rd, rn, rm) => "fadd s\{rd}, s\{rn}, s\{rm}"
    FsubD(rd, rn, rm) => "fsub d\{rd}, d\{rn}, d\{rm}"
    FsubS(rd, rn, rm) => "fsub s\{rd}, s\{rn}, s\{rm}"
    FmulD(rd, rn, rm) => "fmul d\{rd}, d\{rn}, d\{rm}"
    FmulS(rd, rn, rm) => "fmul s\{rd}, s\{rn}, s\{rm}"
    FdivD(rd, rn, rm) => "fdiv d\{rd}, d\{rn}, d\{rm}"
    FdivS(rd, rn, rm) => "fdiv s\{rd}, s\{rn}, s\{rm}"
    FmaxD(rd, rn, rm) => "fmax d\{rd}, d\{rn}, d\{rm}"
    FmaxS(rd, rn, rm) => "fmax s\{rd}, s\{rn}, s\{rm}"
    FminD(rd, rn, rm) => "fmin d\{rd}, d\{rn}, d\{rm}"
    FminS(rd, rn, rm) => "fmin s\{rd}, s\{rn}, s\{rm}"
    FmaxnmD(rd, rn, rm) => "fmaxnm d\{rd}, d\{rn}, d\{rm}"
    FmaxnmS(rd, rn, rm) => "fmaxnm s\{rd}, s\{rn}, s\{rm}"
    FminnmD(rd, rn, rm) => "fminnm d\{rd}, d\{rn}, d\{rm}"
    FminnmS(rd, rn, rm) => "fminnm s\{rd}, s\{rn}, s\{rm}"
    FsqrtD(rd, rn) => "fsqrt d\{rd}, d\{rn}"
    FsqrtS(rd, rn) => "fsqrt s\{rd}, s\{rn}"
    FabsD(rd, rn) => "fabs d\{rd}, d\{rn}"
    FabsS(rd, rn) => "fabs s\{rd}, s\{rn}"
    FnegD(rd, rn) => "fneg d\{rd}, d\{rn}"
    FnegS(rd, rn) => "fneg s\{rd}, s\{rn}"
    FrintpD(rd, rn) => "frintp d\{rd}, d\{rn}"
    FrintpS(rd, rn) => "frintp s\{rd}, s\{rn}"
    FrintmD(rd, rn) => "frintm d\{rd}, d\{rn}"
    FrintmS(rd, rn) => "frintm s\{rd}, s\{rn}"
    FrintzD(rd, rn) => "frintz d\{rd}, d\{rn}"
    FrintzS(rd, rn) => "frintz s\{rd}, s\{rn}"
    FrintnD(rd, rn) => "frintn d\{rd}, d\{rn}"
    FrintnS(rd, rn) => "frintn s\{rd}, s\{rn}"
    FmovD(rd, rm) => "fmov d\{rd}, d\{rm}"
    FmovS(rd, rm) => "fmov s\{rd}, s\{rm}"
    FmovDToX(rd, rn) => "fmov x\{rd}, d\{rn}"
    FmovSToW(rd, rn) => "fmov w\{rd}, s\{rn}"
    FmovXToD(rd, rn) => "fmov d\{rd}, x\{rn}"
    FmovWToS(rd, rn) => "fmov s\{rd}, w\{rn}"
    FcvtDS(rd, rn) => "fcvt d\{rd}, s\{rn}"
    FcvtSD(rd, rn) => "fcvt s\{rd}, d\{rn}"
    LdrSImm(rt, rn, imm12) => "ldr s\{rt}, [x\{rn}, #\{imm12}]"
    StrSImm(rt, rn, imm12) => "str s\{rt}, [x\{rn}, #\{imm12}]"
    LdrDImm(rt, rn, imm12) => "ldr d\{rt}, [x\{rn}, #\{imm12}]"
    StrDImm(rt, rn, imm12) => "str d\{rt}, [x\{rn}, #\{imm12}]"
    FcmpD(rn, rm) => "fcmp d\{rn}, d\{rm}"
    FcmpS(rn, rm) => "fcmp s\{rn}, s\{rm}"
    CmpReg(rn, rm) => "cmp x\{rn}, x\{rm}"
    CmpReg32(rn, rm) => "cmp w\{rn}, w\{rm}"
    CmpImm(rn, imm12) => "cmp x\{rn}, #\{imm12}"
    CmpImm32(rn, imm12) => "cmp w\{rn}, #\{imm12}"
    AddsImmZr(rn, imm12, is_64) => {
      let reg = if is_64 { "x" } else { "w" }
      let zr = if is_64 { "xzr" } else { "wzr" }
      "adds \{zr}, \{reg}\{rn}, #\{imm12}"
    }
    CCmpImm(rn, imm5, nzcv, cond, is_64) => {
      let reg = if is_64 { "x" } else { "w" }
      let cond_name = cond_name_str(cond)
      "ccmp \{reg}\{rn}, #\{imm5}, #\{nzcv}, \{cond_name}"
    }
    Cset(rd, cond) => {
      let cond_name = cond_name_str(cond)
      "cset x\{rd}, \{cond_name}"
    }
    Csel(rd, rn, rm, cond) => {
      let cond_name = cond_name_str(cond)
      "csel x\{rd}, x\{rn}, x\{rm}, \{cond_name}"
    }
    FcselD(rd, rn, rm, cond) => {
      let cond_name = cond_name_str(cond)
      "fcsel d\{rd}, d\{rn}, d\{rm}, \{cond_name}"
    }
    FcselS(rd, rn, rm, cond) => {
      let cond_name = cond_name_str(cond)
      "fcsel s\{rd}, s\{rn}, s\{rm}, \{cond_name}"
    }
    B(target_block) => "b block\{target_block}"
    BCond(cond, target_block) => {
      let cond_name = cond_name_str(cond)
      "b.\{cond_name} block\{target_block}"
    }
    Cbz(rt, target_block) => "cbz x\{rt}, block\{target_block}"
    Cbnz(rt, target_block) => "cbnz x\{rt}, block\{target_block}"
    BCondOffset(cond, offset_bytes) => {
      let cond_name = cond_name_str(cond)
      "b.\{cond_name} .+\{offset_bytes}"
    }
    CbnzOffset(rt, is_64, offset_bytes) => {
      let reg = if is_64 { "x" } else { "w" }
      "cbnz \{reg}\{rt}, .+\{offset_bytes}"
    }
    Brk(imm16) => "brk #\{imm16}"
    Ret(_) => "ret"
    Br(rn) => "br x\{rn}"
    Bl(target_block) => "bl block\{target_block}"
    Blr(rn) => "blr x\{rn}"
    Adr(rd, offset) => "adr x\{rd}, .+\{offset}"
    DmbIsh => "dmb ish"
    Nop => "nop"
    AlignTo(alignment) => "align to \{alignment} bytes"
    Cnt8B(rd, rn) => "cnt v\{rd}.8b, v\{rn}.8b"
    AddvB(rd, rn) => "addv b\{rd}, v\{rn}.8b"
  }
}

///|
fn cond_name_str(cond : Int) -> String {
  match cond {
    0 => "eq"
    1 => "ne"
    2 => "hs"
    3 => "lo"
    4 => "mi"
    5 => "pl"
    6 => "vs"
    7 => "vc"
    8 => "hi"
    9 => "ls"
    10 => "ge"
    11 => "lt"
    12 => "gt"
    13 => "le"
    14 => "al"
    _ => "?\{cond}"
  }
}

///|
fn Instruction::instr_bytes(self : Instruction) -> (Int, Int, Int, Int) {
  match self {
    AddReg(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = (rn >> 3) & 3
      let b2 = rm & 31
      let b3 = 139
      (b0, b1, b2, b3)
    }
    AddShifted(rd, rn, rm, shift, amount) => {
      let shift_bits = match shift {
        Lsl => 0
        Lsr => 1
        Asr => 2
      }
      let imm6 = amount & 63
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((imm6 & 63) << 2)
      let b2 = (rm & 31) | ((shift_bits & 3) << 6)
      let b3 = 139
      (b0, b1, b2, b3)
    }
    AddImm(rd, rn, imm12) => {
      let imm = imm12 & 0xFFF
      let inst = (0b1 << 31) |
        (0 << 30) |
        (0 << 29) |
        (0b100010 << 23) |
        (0 << 22) |
        (imm << 10) |
        ((rn & 31) << 5) |
        (rd & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    SubReg(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = (rn >> 3) & 3
      let b2 = rm & 31
      let b3 = 203
      (b0, b1, b2, b3)
    }
    SubShifted(rd, rn, rm, shift, amount) => {
      let shift_bits = match shift {
        Lsl => 0
        Lsr => 1
        Asr => 2
      }
      let imm6 = amount & 63
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((imm6 & 63) << 2)
      let b2 = (rm & 31) | ((shift_bits & 3) << 6)
      let b3 = 203
      (b0, b1, b2, b3)
    }
    SubImm(rd, rn, imm12) => {
      let imm = imm12 & 0xFFF
      let inst = (0b1 << 31) |
        (1 << 30) |
        (0 << 29) |
        (0b100010 << 23) |
        (0 << 22) |
        (imm << 10) |
        ((rn & 31) << 5) |
        (rd & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    Mul(rd, rn, rm) => {
      let b0 = (rd & 0x1f) | ((rn & 0x7) << 5)
      let b1 = ((rn >> 3) & 0x3) | 0x7C
      let b2 = rm & 0x1f
      let b3 = 0x9B
      (b0, b1, b2, b3)
    }
    Madd(rd, rn, rm, ra) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((ra & 31) << 2)
      let b2 = rm & 31
      let b3 = 155
      (b0, b1, b2, b3)
    }
    Msub(rd, rn, rm, ra) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((ra & 31) << 2) | 128
      let b2 = rm & 31
      let b3 = 155
      (b0, b1, b2, b3)
    }
    Mneg(rd, rn, rm) => Msub(rd, rn, rm, 31).instr_bytes()
    Sdiv(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | (3 << 2)
      let b2 = 0xC0 | (rm & 31)
      let b3 = 0x9A
      (b0, b1, b2, b3)
    }
    Udiv(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | (2 << 2)
      let b2 = 0xC0 | (rm & 31)
      let b3 = 0x9A
      (b0, b1, b2, b3)
    }
    Sdiv32(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | (3 << 2)
      let b2 = 0xC0 | (rm & 31)
      let b3 = 0x1A // 32-bit: sf=0
      (b0, b1, b2, b3)
    }
    Udiv32(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | (2 << 2)
      let b2 = 0xC0 | (rm & 31)
      let b3 = 0x1A // 32-bit: sf=0
      (b0, b1, b2, b3)
    }
    SubReg32(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = (rn >> 3) & 3
      let b2 = rm & 31
      let b3 = 0x4B // SUB 32-bit: sf=0
      (b0, b1, b2, b3)
    }
    AndReg(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = (rn >> 3) & 3
      let b2 = rm & 31
      let b3 = 138
      (b0, b1, b2, b3)
    }
    AndShifted(rd, rn, rm, shift, amount) => {
      let shift_bits = match shift {
        Lsl => 0
        Lsr => 1
        Asr => 2
      }
      let imm6 = amount & 63
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((imm6 & 63) << 2)
      let b2 = (rm & 31) | ((shift_bits & 3) << 6)
      let b3 = 138
      (b0, b1, b2, b3)
    }
    OrrReg(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = (rn >> 3) & 3
      let b2 = rm & 31
      let b3 = 170
      (b0, b1, b2, b3)
    }
    OrrShifted(rd, rn, rm, shift, amount) => {
      let shift_bits = match shift {
        Lsl => 0
        Lsr => 1
        Asr => 2
      }
      let imm6 = amount & 63
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((imm6 & 63) << 2)
      let b2 = (rm & 31) | ((shift_bits & 3) << 6)
      let b3 = 170
      (b0, b1, b2, b3)
    }
    EorReg(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = (rn >> 3) & 3
      let b2 = rm & 31
      let b3 = 202
      (b0, b1, b2, b3)
    }
    EorShifted(rd, rn, rm, shift, amount) => {
      let shift_bits = match shift {
        Lsl => 0
        Lsr => 1
        Asr => 2
      }
      let imm6 = amount & 63
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((imm6 & 63) << 2)
      let b2 = (rm & 31) | ((shift_bits & 3) << 6)
      let b3 = 202
      (b0, b1, b2, b3)
    }
    Mvn(rd, rm) => {
      let b0 = (rd & 31) | ((31 & 7) << 5)
      let b1 = (31 >> 3) & 3
      let b2 = (rm & 31) | 32
      let b3 = 170
      (b0, b1, b2, b3)
    }
    LslReg(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | (8 << 2)
      let b2 = 0xC0 | (rm & 31)
      let b3 = 0x9A
      (b0, b1, b2, b3)
    }
    LsrReg(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | (9 << 2)
      let b2 = 0xC0 | (rm & 31)
      let b3 = 0x9A
      (b0, b1, b2, b3)
    }
    AsrReg(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | (10 << 2)
      let b2 = 0xC0 | (rm & 31)
      let b3 = 0x9A
      (b0, b1, b2, b3)
    }
    RorReg(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | (11 << 2)
      let b2 = 0xC0 | (rm & 31)
      let b3 = 0x9A
      (b0, b1, b2, b3)
    }
    LslReg32(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | (8 << 2)
      let b2 = 0xC0 | (rm & 31)
      let b3 = 0x1A // 32-bit: sf=0
      (b0, b1, b2, b3)
    }
    LsrReg32(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | (9 << 2)
      let b2 = 0xC0 | (rm & 31)
      let b3 = 0x1A // 32-bit: sf=0
      (b0, b1, b2, b3)
    }
    AsrReg32(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | (10 << 2)
      let b2 = 0xC0 | (rm & 31)
      let b3 = 0x1A // 32-bit: sf=0
      (b0, b1, b2, b3)
    }
    RorReg32(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | (11 << 2)
      let b2 = 0xC0 | (rm & 31)
      let b3 = 0x1A // 32-bit: sf=0
      (b0, b1, b2, b3)
    }
    Clz(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 16
      let b2 = 192
      let b3 = 218
      (b0, b1, b2, b3)
    }
    Rbit(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = (rn >> 3) & 3
      let b2 = 192
      let b3 = 218
      (b0, b1, b2, b3)
    }
    Clz32(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 16
      let b2 = 192
      let b3 = 0x5A // 32-bit: sf=0
      (b0, b1, b2, b3)
    }
    Rbit32(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = (rn >> 3) & 3
      let b2 = 192
      let b3 = 0x5A // 32-bit: sf=0
      (b0, b1, b2, b3)
    }
    MovReg(rd, rm) => {
      let b0 = (rd & 31) | ((31 & 7) << 5)
      let b1 = (31 >> 3) & 3
      let b2 = rm & 31
      let b3 = 170
      (b0, b1, b2, b3)
    }
    MovReg32(rd, rm) => {
      let b0 = (rd & 31) | ((31 & 7) << 5)
      let b1 = (31 >> 3) & 3
      let b2 = rm & 31
      let b3 = 0x2A
      (b0, b1, b2, b3)
    }
    Movz(rd, imm16, shift) => {
      let hw = shift / 16
      let imm = imm16 & 0xFFFF
      let b0 = (rd & 31) | ((imm & 7) << 5)
      let b1 = (imm >> 3) & 255
      let b2 = ((imm >> 11) & 31) | ((hw & 3) << 5) | 128
      let xd2 = 210
      let b3 = xd2 | ((hw >> 2) & 1)
      (b0, b1, b2, b3)
    }
    Movk(rd, imm16, shift) => {
      let hw = shift / 16
      let imm = imm16 & 0xFFFF
      let b0 = (rd & 31) | ((imm & 7) << 5)
      let b1 = (imm >> 3) & 255
      let b2 = ((imm >> 11) & 31) | ((hw & 3) << 5) | 128
      let xf2 = 242
      let b3 = xf2 | ((hw >> 2) & 1)
      (b0, b1, b2, b3)
    }
    LoadImm64(_, _) => abort("LoadImm64 does not have single instruction bytes")
    LdrImm(rt, rn, imm12) => {
      let scaled = (imm12 / 8) & 0xFFF
      let inst = (0b11 << 30) |
        (0b111 << 27) |
        (0 << 26) |
        (0b01 << 24) |
        (0b01 << 22) |
        (scaled << 10) |
        ((rn & 31) << 5) |
        (rt & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    LdrImmSigned(rt, rn, simm9) => {
      let imm9 = simm9 & 0x1FF
      let inst = (0b11 << 30) |
        (0b111 << 27) |
        (0 << 26) |
        (0b00 << 24) |
        (0b01 << 22) |
        (0 << 21) |
        (imm9 << 12) |
        (0b00 << 10) |
        ((rn & 31) << 5) |
        (rt & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    LdrRegScaled(rt, rn, rm, shift) => {
      let s_bit = if shift == 3 { 1 } else { 0 }
      let inst = (0b11 << 30) |
        (0b111 << 27) |
        (0 << 26) |
        (0b00 << 24) |
        (0b01 << 22) |
        (1 << 21) |
        ((rm & 31) << 16) |
        (0b011 << 13) |
        (s_bit << 12) |
        (0b10 << 10) |
        ((rn & 31) << 5) |
        (rt & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    StrImm(rt, rn, imm12) => {
      let scaled = (imm12 / 8) & 0xFFF
      let inst = (0b11 << 30) |
        (0b111 << 27) |
        (0 << 26) |
        (0b01 << 24) |
        (0b00 << 22) |
        (scaled << 10) |
        ((rn & 31) << 5) |
        (rt & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    StrRegScaled(rt, rn, rm, shift) => {
      let s_bit = if shift == 3 { 1 } else { 0 }
      let inst = (0b11 << 30) |
        (0b111 << 27) |
        (0 << 26) |
        (0b00 << 24) |
        (0b00 << 22) |
        (1 << 21) |
        ((rm & 31) << 16) |
        (0b011 << 13) |
        (s_bit << 12) |
        (0b10 << 10) |
        ((rn & 31) << 5) |
        (rt & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    LdrbImm(rt, rn, imm12) => {
      let imm = imm12 & 0xFFF
      let b0 = (rt & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((imm & 63) << 2)
      let b2 = ((imm >> 6) & 63) | 64
      let b3 = 57
      (b0, b1, b2, b3)
    }
    LdrhImm(rt, rn, imm12) => {
      let scaled = (imm12 / 2) & 0xFFF
      let b0 = (rt & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((scaled & 63) << 2)
      let b2 = ((scaled >> 6) & 63) | 64
      let b3 = 121
      (b0, b1, b2, b3)
    }
    LdrWImm(rt, rn, imm12) => {
      let scaled = (imm12 / 4) & 0xFFF
      let b0 = (rt & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((scaled & 63) << 2)
      let b2 = ((scaled >> 6) & 63) | 64
      let b3 = 185
      (b0, b1, b2, b3)
    }
    StrbImm(rt, rn, imm12) => {
      let imm = imm12 & 0xFFF
      let b0 = (rt & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((imm & 63) << 2)
      let b2 = (imm >> 6) & 63
      let b3 = 57
      (b0, b1, b2, b3)
    }
    StrhImm(rt, rn, imm12) => {
      let scaled = (imm12 / 2) & 0xFFF
      let b0 = (rt & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((scaled & 63) << 2)
      let b2 = (scaled >> 6) & 63
      let b3 = 121
      (b0, b1, b2, b3)
    }
    StrWImm(rt, rn, imm12) => {
      let scaled = (imm12 / 4) & 0xFFF
      let b0 = (rt & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((scaled & 63) << 2)
      let b2 = (scaled >> 6) & 63
      let b3 = 185
      (b0, b1, b2, b3)
    }
    LdrsbXImm(rt, rn, imm12) => {
      let imm = imm12 & 0xFFF
      let b0 = (rt & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((imm & 63) << 2)
      let b2 = ((imm >> 6) & 63) | 128
      let b3 = 57
      (b0, b1, b2, b3)
    }
    LdrsbWImm(rt, rn, imm12) => {
      let imm = imm12 & 0xFFF
      let b0 = (rt & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((imm & 63) << 2)
      let b2 = ((imm >> 6) & 63) | 192
      let b3 = 57
      (b0, b1, b2, b3)
    }
    LdrshXImm(rt, rn, imm12) => {
      let scaled = (imm12 / 2) & 0xFFF
      let b0 = (rt & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((scaled & 63) << 2)
      let b2 = ((scaled >> 6) & 63) | 128
      let b3 = 121
      (b0, b1, b2, b3)
    }
    LdrshWImm(rt, rn, imm12) => {
      let scaled = (imm12 / 2) & 0xFFF
      let b0 = (rt & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((scaled & 63) << 2)
      let b2 = ((scaled >> 6) & 63) | 192
      let b3 = 121
      (b0, b1, b2, b3)
    }
    LdrswImm(rt, rn, imm12) => {
      let scaled = (imm12 / 4) & 0xFFF
      let b0 = (rt & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((scaled & 63) << 2)
      let b2 = ((scaled >> 6) & 63) | 128
      let b3 = 185
      (b0, b1, b2, b3)
    }
    StpPre(rt1, rt2, rn, imm) => {
      let imm7 = (imm / 8) & 0x7F
      let inst = (0b10 << 30) |
        (0b101 << 27) |
        (0 << 26) |
        (0b011 << 23) |
        (0 << 22) |
        (imm7 << 15) |
        ((rt2 & 31) << 10) |
        ((rn & 31) << 5) |
        (rt1 & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    LdpPost(rt1, rt2, rn, imm) => {
      let imm7 = (imm / 8) & 0x7F
      let inst = (0b10 << 30) |
        (0b101 << 27) |
        (0 << 26) |
        (0b001 << 23) |
        (1 << 22) |
        (imm7 << 15) |
        ((rt2 & 31) << 10) |
        ((rn & 31) << 5) |
        (rt1 & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    StpOffset(rt1, rt2, rn, offset) => {
      let imm7 = (offset / 8) & 0x7F
      let inst = (0b10 << 30) |
        (0b101 << 27) |
        (0 << 26) |
        (0b010 << 23) |
        (0 << 22) |
        (imm7 << 15) |
        ((rt2 & 31) << 10) |
        ((rn & 31) << 5) |
        (rt1 & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    LdpOffset(rt1, rt2, rn, offset) => {
      let imm7 = (offset / 8) & 0x7F
      let inst = (0b10 << 30) |
        (0b101 << 27) |
        (0 << 26) |
        (0b010 << 23) |
        (1 << 22) |
        (imm7 << 15) |
        ((rt2 & 31) << 10) |
        ((rn & 31) << 5) |
        (rt1 & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    StpDOffset(rt1, rt2, rn, offset) => {
      let imm7 = (offset / 8) & 0x7F
      let inst = (0b01 << 30) |
        (0b101 << 27) |
        (1 << 26) |
        (0b010 << 23) |
        (0 << 22) |
        (imm7 << 15) |
        ((rt2 & 31) << 10) |
        ((rn & 31) << 5) |
        (rt1 & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    LdpDOffset(rt1, rt2, rn, offset) => {
      let imm7 = (offset / 8) & 0x7F
      let inst = (0b01 << 30) |
        (0b101 << 27) |
        (1 << 26) |
        (0b010 << 23) |
        (1 << 22) |
        (imm7 << 15) |
        ((rt2 & 31) << 10) |
        ((rn & 31) << 5) |
        (rt1 & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    StrPre(rt, rn, simm9) => {
      // STR (immediate, pre-indexed): STR Xt, [Xn|SP, #simm9]!
      // Encoding: 11 | 111 | 0 | 00 | 00 | imm9 | 11 | Rn | Rt
      // = 0xF8000C00 | (imm9 << 12) | (Rn << 5) | Rt
      let imm9 = simm9 & 0x1FF
      let inst = 0xF8000C00 | (imm9 << 12) | ((rn & 31) << 5) | (rt & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    StpDPre(rt1, rt2, rn, imm) => {
      // STP (SIMD&FP, pre-indexed): STP Dt1, Dt2, [Xn|SP, #imm]!
      // opc=01 for 64-bit, V=1
      // Encoding: 01 | 101 | 1 | 011 | imm7 | Rt2 | Rn | Rt1
      // = 0x6D800000 | (imm7 << 15) | (Rt2 << 10) | (Rn << 5) | Rt1
      let imm7 = (imm / 8) & 0x7F
      let inst = 0x6D800000 |
        (imm7 << 15) |
        ((rt2 & 31) << 10) |
        ((rn & 31) << 5) |
        (rt1 & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    StrDPre(rt, rn, simm9) => {
      // STR (SIMD&FP, immediate, pre-indexed): STR Dt, [Xn|SP, #simm9]!
      // size=11 for 64-bit, V=1
      // Encoding: 11 | 111 | 1 | 00 | 00 | imm9 | 11 | Rn | Rt
      // = 0xFC000C00 | (imm9 << 12) | (Rn << 5) | Rt
      let imm9 = simm9 & 0x1FF
      let inst = 0xFC000C00 | (imm9 << 12) | ((rn & 31) << 5) | (rt & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    LdrPost(rt, rn, simm9) => {
      // LDR (immediate, post-indexed): LDR Xt, [Xn|SP], #simm9
      // Encoding: 11 | 111 | 0 | 00 | 01 | imm9 | 01 | Rn | Rt
      // = 0xF8400400 | (imm9 << 12) | (Rn << 5) | Rt
      let imm9 = simm9 & 0x1FF
      let inst = 0xF8400400 | (imm9 << 12) | ((rn & 31) << 5) | (rt & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    LdpDPost(rt1, rt2, rn, imm) => {
      // LDP (SIMD&FP, post-indexed): LDP Dt1, Dt2, [Xn|SP], #imm
      // opc=01 for 64-bit, V=1
      // Encoding: 01 | 101 | 1 | 001 | imm7 | Rt2 | Rn | Rt1
      // = 0x6CC00000 | (imm7 << 15) | (Rt2 << 10) | (Rn << 5) | Rt1
      let imm7 = (imm / 8) & 0x7F
      let inst = 0x6CC00000 |
        (imm7 << 15) |
        ((rt2 & 31) << 10) |
        ((rn & 31) << 5) |
        (rt1 & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    LdrDPost(rt, rn, simm9) => {
      // LDR (SIMD&FP, immediate, post-indexed): LDR Dt, [Xn|SP], #simm9
      // size=11 for 64-bit, V=1
      // Encoding: 11 | 111 | 1 | 00 | 01 | imm9 | 01 | Rn | Rt
      // = 0xFC400400 | (imm9 << 12) | (Rn << 5) | Rt
      let imm9 = simm9 & 0x1FF
      let inst = 0xFC400400 | (imm9 << 12) | ((rn & 31) << 5) | (rt & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    SxtbX(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | (7 << 2)
      let b2 = 0x40
      let b3 = 0x93
      (b0, b1, b2, b3)
    }
    SxthX(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | (15 << 2)
      let b2 = 0x40
      let b3 = 0x93
      (b0, b1, b2, b3)
    }
    Sxtw(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | (31 << 2)
      let b2 = 0x40
      let b3 = 0x93
      (b0, b1, b2, b3)
    }
    SxtbW(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | (7 << 2)
      let b2 = 0x00
      let b3 = 0x13
      (b0, b1, b2, b3)
    }
    SxthW(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | (15 << 2)
      let b2 = 0x00
      let b3 = 0x13
      (b0, b1, b2, b3)
    }
    UxtbX(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | (7 << 2)
      let b2 = 0x00
      let b3 = 0x53
      (b0, b1, b2, b3)
    }
    UxthX(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | (15 << 2)
      let b2 = 0x00
      let b3 = 0x53
      (b0, b1, b2, b3)
    }
    UxtbW(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | (7 << 2)
      let b2 = 0x00
      let b3 = 0x53
      (b0, b1, b2, b3)
    }
    UxthW(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | (15 << 2)
      let b2 = 0x00
      let b3 = 0x53
      (b0, b1, b2, b3)
    }
    Fcvtzs(rd, rn, int64, double) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = (rn >> 3) & 3
      let b2 = if double { 0x78 } else { 0x38 }
      let b3 = if int64 { 0x9E } else { 0x1E }
      (b0, b1, b2, b3)
    }
    Fcvtzu(rd, rn, int64, double) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = (rn >> 3) & 3
      let b2 = if double { 0x79 } else { 0x39 }
      let b3 = if int64 { 0x9E } else { 0x1E }
      (b0, b1, b2, b3)
    }
    Scvtf(rd, rn, int64, double) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = (rn >> 3) & 3
      let b2 = if double { 0x62 } else { 0x22 }
      let b3 = if int64 { 0x9E } else { 0x1E }
      (b0, b1, b2, b3)
    }
    Ucvtf(rd, rn, int64, double) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = (rn >> 3) & 3
      let b2 = if double { 0x63 } else { 0x23 }
      let b3 = if int64 { 0x9E } else { 0x1E }
      (b0, b1, b2, b3)
    }
    FaddD(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 0x28
      let b2 = 0x60 | (rm & 31)
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FaddS(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 0x28
      let b2 = 0x20 | (rm & 31)
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FsubD(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 0x38
      let b2 = 0x60 | (rm & 31)
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FsubS(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 0x38
      let b2 = 0x20 | (rm & 31)
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FmulD(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 0x08
      let b2 = 0x60 | (rm & 31)
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FmulS(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 0x08
      let b2 = 0x20 | (rm & 31)
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FdivD(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 0x18
      let b2 = 0x60 | (rm & 31)
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FdivS(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 0x18
      let b2 = 0x20 | (rm & 31)
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FmaxD(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 0x48
      let b2 = 0x60 | (rm & 31)
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FmaxS(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 0x48
      let b2 = 0x20 | (rm & 31)
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FminD(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 0x58
      let b2 = 0x60 | (rm & 31)
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FminS(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 0x58
      let b2 = 0x20 | (rm & 31)
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FmaxnmD(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 0x68
      let b2 = 0x60 | (rm & 31)
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FmaxnmS(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 0x68
      let b2 = 0x20 | (rm & 31)
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FminnmD(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 0x78
      let b2 = 0x60 | (rm & 31)
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FminnmS(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 0x78
      let b2 = 0x20 | (rm & 31)
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FsqrtD(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 192
      let b2 = 97
      let b3 = 30
      (b0, b1, b2, b3)
    }
    FsqrtS(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 192
      let b2 = 0x21
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FabsD(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 192
      let b2 = 96
      let b3 = 30
      (b0, b1, b2, b3)
    }
    FabsS(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 192
      let b2 = 0x20
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FnegD(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 64
      let b2 = 97
      let b3 = 30
      (b0, b1, b2, b3)
    }
    FnegS(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 64
      let b2 = 0x21
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FrintpD(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 192
      let b2 = 100
      let b3 = 30
      (b0, b1, b2, b3)
    }
    FrintpS(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 192
      let b2 = 0x24
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FrintmD(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 64
      let b2 = 101
      let b3 = 30
      (b0, b1, b2, b3)
    }
    FrintmS(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 64
      let b2 = 0x25
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FrintzD(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 192
      let b2 = 101
      let b3 = 30
      (b0, b1, b2, b3)
    }
    FrintzS(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 192
      let b2 = 0x25
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FrintnD(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 64
      let b2 = 100
      let b3 = 30
      (b0, b1, b2, b3)
    }
    FrintnS(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 64
      let b2 = 0x24
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FmovD(rd, rm) => {
      let b0 = (rd & 31) | ((rm & 7) << 5)
      let b1 = ((rm >> 3) & 3) | 64
      let b2 = 96
      let b3 = 30
      (b0, b1, b2, b3)
    }
    FmovS(rd, rm) => {
      let b0 = (rd & 31) | ((rm & 7) << 5)
      let b1 = ((rm >> 3) & 3) | 64
      let b2 = 0x20
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FmovDToX(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = (rn >> 3) & 3
      let b2 = 102
      let b3 = 158
      (b0, b1, b2, b3)
    }
    FmovSToW(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = (rn >> 3) & 3
      let b2 = 38
      let b3 = 30
      (b0, b1, b2, b3)
    }
    FmovXToD(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = (rn >> 3) & 3
      let b2 = 103
      let b3 = 158
      (b0, b1, b2, b3)
    }
    FmovWToS(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = (rn >> 3) & 3
      let b2 = 39
      let b3 = 30
      (b0, b1, b2, b3)
    }
    FcvtDS(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 192
      let b2 = 34
      let b3 = 30
      (b0, b1, b2, b3)
    }
    FcvtSD(rd, rn) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 64
      let b2 = 98
      let b3 = 30
      (b0, b1, b2, b3)
    }
    LdrSImm(rt, rn, imm12) => {
      let scaled = (imm12 / 4) & 0xFFF
      let b0 = (rt & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((scaled & 63) << 2)
      let b2 = ((scaled >> 6) & 63) | 64
      let b3 = 189
      (b0, b1, b2, b3)
    }
    StrSImm(rt, rn, imm12) => {
      let scaled = (imm12 / 4) & 0xFFF
      let b0 = (rt & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((scaled & 63) << 2)
      let b2 = (scaled >> 6) & 63
      let b3 = 189
      (b0, b1, b2, b3)
    }
    LdrDImm(rt, rn, imm12) => {
      let scaled = (imm12 / 8) & 0xFFF
      let b0 = (rt & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((scaled & 63) << 2)
      let b2 = ((scaled >> 6) & 63) | 64
      let b3 = 253
      (b0, b1, b2, b3)
    }
    StrDImm(rt, rn, imm12) => {
      let scaled = (imm12 / 8) & 0xFFF
      let b0 = (rt & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((scaled & 63) << 2)
      let b2 = (scaled >> 6) & 63
      let b3 = 253
      (b0, b1, b2, b3)
    }
    FcmpD(rn, rm) => {
      let b0 = (rn & 7) << 5
      let b1 = ((rn >> 3) & 3) | 0x20
      let b2 = 0x60 | (rm & 31)
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FcmpS(rn, rm) => {
      let b0 = (rn & 7) << 5
      let b1 = ((rn >> 3) & 3) | 0x20
      let b2 = 0x20 | (rm & 31)
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    CmpReg(rn, rm) => {
      let b0 = 31 | ((rn & 7) << 5)
      let b1 = (rn >> 3) & 3
      let b2 = rm & 31
      let b3 = 235
      (b0, b1, b2, b3)
    }
    CmpImm(rn, imm12) => {
      let imm = imm12 & 0xFFF
      let b0 = 31 | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((imm & 63) << 2)
      let b2 = (imm >> 6) & 63
      let b3 = 241
      (b0, b1, b2, b3)
    }
    CmpReg32(rn, rm) => {
      let b0 = 31 | ((rn & 7) << 5)
      let b1 = (rn >> 3) & 3
      let b2 = rm & 31
      let b3 = 0x6B // 32-bit: sf=0
      (b0, b1, b2, b3)
    }
    CmpImm32(rn, imm12) => {
      let imm = imm12 & 0xFFF
      let b0 = 31 | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((imm & 63) << 2)
      let b2 = (imm >> 6) & 63
      let b3 = 0x71 // 32-bit: sf=0
      (b0, b1, b2, b3)
    }
    AddsImmZr(rn, imm12, is_64) => {
      // ADDS XZR/WZR, Xn, #imm - add immediate with flags, result discarded
      // 64-bit: 0xB1000000 | (imm12 << 10) | (Rn << 5) | 31 (XZR)
      // 32-bit: 0x31000000 | (imm12 << 10) | (Rn << 5) | 31 (WZR)
      let imm = imm12 & 0xFFF
      let b0 = 31 | ((rn & 7) << 5) // Rd = 31 (XZR/WZR)
      let b1 = ((rn >> 3) & 3) | ((imm & 63) << 2)
      let b2 = (imm >> 6) & 63
      let b3 = if is_64 { 0xB1 } else { 0x31 }
      (b0, b1, b2, b3)
    }
    CCmpImm(rn, imm5, nzcv, cond, is_64) => {
      // CCMP Xn, #imm5, #nzcv, cond - conditional compare immediate
      // 64-bit: 0xFA400800 | (imm5 << 16) | (cond << 12) | (Rn << 5) | nzcv
      // 32-bit: 0x7A400800 | (imm5 << 16) | (cond << 12) | (Rn << 5) | nzcv
      let base = if is_64 { 0xFA400800 } else { 0x7A400800 }
      let inst = base |
        ((imm5 & 0x1F) << 16) |
        ((cond & 0xF) << 12) |
        ((rn & 0x1F) << 5) |
        (nzcv & 0xF)
      (
        inst & 0xFF,
        (inst >> 8) & 0xFF,
        (inst >> 16) & 0xFF,
        (inst >> 24) & 0xFF,
      )
    }
    Cset(rd, cond) => {
      let inv_cond = cond ^ 1
      let xe0 = 224
      let b0 = (rd & 31) | xe0
      let x07 = 7
      let x04 = 4
      let b1 = x07 | ((inv_cond & 15) << 4) | x04
      let b2 = 159
      let b3 = 154
      (b0, b1, b2, b3)
    }
    Csel(rd, rn, rm, cond) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((cond & 15) << 4)
      let b2 = (rm & 31) | 128
      let b3 = 154
      (b0, b1, b2, b3)
    }
    FcselD(rd, rn, rm, cond) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 0x0C | ((cond & 15) << 4)
      let b2 = 0x60 | (rm & 31)
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    FcselS(rd, rn, rm, cond) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 0x0C | ((cond & 15) << 4)
      let b2 = 0x20 | (rm & 31)
      let b3 = 0x1E
      (b0, b1, b2, b3)
    }
    B(_) => (0, 0, 0, 20)
    BCond(cond, _) => (cond & 15, 0, 0, 84)
    Cbz(rt, _) => (rt & 31, 0, 0, 180)
    Cbnz(rt, _) => (rt & 31, 0, 0, 181)
    BCondOffset(cond, offset_bytes) => {
      let imm19 = offset_bytes / 4
      let inst = 0x54000000 | ((imm19 & 0x7FFFF) << 5) | (cond & 0xF)
      (
        inst & 0xFF,
        (inst >> 8) & 0xFF,
        (inst >> 16) & 0xFF,
        (inst >> 24) & 0xFF,
      )
    }
    CbnzOffset(rt, is_64, offset_bytes) => {
      // CBNZ Xt: 0xB5000000 | (imm19 << 5) | Rt
      // CBNZ Wt: 0x35000000 | (imm19 << 5) | Rt
      let imm19 = offset_bytes / 4
      let base = if is_64 { 0xB5000000 } else { 0x35000000 }
      let inst = base | ((imm19 & 0x7FFFF) << 5) | (rt & 0x1F)
      (
        inst & 0xFF,
        (inst >> 8) & 0xFF,
        (inst >> 16) & 0xFF,
        (inst >> 24) & 0xFF,
      )
    }
    Brk(imm16) => {
      let inst = 0xD4200000 | ((imm16 & 0xFFFF) << 5)
      (
        inst & 0xFF,
        (inst >> 8) & 0xFF,
        (inst >> 16) & 0xFF,
        (inst >> 24) & 0xFF,
      )
    }
    Ret(rn) => {
      let b0 = (rn & 7) << 5
      let b1 = (rn >> 3) & 3
      (b0, b1, 95, 214)
    }
    Br(rn) => {
      let b0 = (rn & 7) << 5
      let b1 = (rn >> 3) & 3
      (b0, b1, 31, 214)
    }
    Bl(_) => (0, 0, 0, 148)
    Blr(rn) => {
      let b0 = (rn & 7) << 5
      let b1 = (rn >> 3) & 3
      (b0, b1, 63, 214)
    }
    Adr(rd, offset) => {
      let immlo = offset & 3
      let immhi = (offset >> 2) & 0x7FFFF
      let b0 = (rd & 31) | ((immhi & 7) << 5)
      let b1 = (immhi >> 3) & 0xFF
      let b2 = (immhi >> 11) & 0xFF
      let b3 = 16 | (immlo << 5)
      (b0, b1, b2, b3)
    }
    DmbIsh => (0xBF, 0x3B, 0x03, 0xD5)
    Nop => (31, 32, 3, 213)
    AlignTo(_) => abort("AlignTo does not have single instruction bytes")
    Cnt8B(rd, rn) => {
      // CNT Vd.8B, Vn.8B: 0x0E205800 | (Rn << 5) | Rd
      let enc = 0x0E205800 | ((rn & 31) << 5) | (rd & 31)
      let b0 = enc & 0xFF
      let b1 = (enc >> 8) & 0xFF
      let b2 = (enc >> 16) & 0xFF
      let b3 = (enc >> 24) & 0xFF
      (b0, b1, b2, b3)
    }
    AddvB(rd, rn) => {
      // ADDV Bd, Vn.8B: 0x0E31B800 | (Rn << 5) | Rd
      let enc = 0x0E31B800 | ((rn & 31) << 5) | (rd & 31)
      let b0 = enc & 0xFF
      let b1 = (enc >> 8) & 0xFF
      let b2 = (enc >> 16) & 0xFF
      let b3 = (enc >> 24) & 0xFF
      (b0, b1, b2, b3)
    }
  }
}

///|
pub fn Instruction::emit(self : Instruction, mc : MachineCode) -> Unit {
  match self {
    LoadImm64(rd, imm) => {
      // Load a 64-bit immediate using MOVZ/MOVK sequence
      let v0 = (imm & 0xFFFFL).to_int()
      let v1 = ((imm >> 16) & 0xFFFFL).to_int()
      let v2 = ((imm >> 32) & 0xFFFFL).to_int()
      let v3 = ((imm >> 48) & 0xFFFFL).to_int()
      let mut started = false
      if v0 != 0 || (v1 == 0 && v2 == 0 && v3 == 0) {
        Movz(rd, v0, 0).emit(mc)
        started = true
      }
      if v1 != 0 {
        if started {
          Movk(rd, v1, 16).emit(mc)
        } else {
          Movz(rd, v1, 16).emit(mc)
          started = true
        }
      }
      if v2 != 0 {
        if started {
          Movk(rd, v2, 32).emit(mc)
        } else {
          Movz(rd, v2, 32).emit(mc)
          started = true
        }
      }
      if v3 != 0 {
        if started {
          Movk(rd, v3, 48).emit(mc)
        } else {
          Movz(rd, v3, 48).emit(mc)
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
pub fn MachineCode::emit_add_imm(
  self : MachineCode,
  rd : Int,
  rn : Int,
  imm12 : Int,
) -> Unit {
  AddImm(rd, rn, imm12).emit(self)
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
pub fn MachineCode::emit_orr_reg(
  self : MachineCode,
  rd : Int,
  rn : Int,
  rm : Int,
) -> Unit {
  OrrReg(rd, rn, rm).emit(self)
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
  imm12 : Int,
) -> Unit {
  CmpImm32(rn, imm12).emit(self)
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
  imm12 : Int,
) -> Unit {
  CmpImm(rn, imm12).emit(self)
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
/// Check if a register is a callee-saved allocatable GPR (X19-X28)
/// All callee-saved registers are now available for allocation since
/// we use Cranelift-style on-demand loading from vmctx (X19).
fn is_callee_saved_alloc(reg : Int) -> Bool {
  reg >= 19 && reg <= 28
}

///|
fn is_callee_saved_fpr(reg : Int) -> Bool {
  reg >= 8 && reg <= 15
}
