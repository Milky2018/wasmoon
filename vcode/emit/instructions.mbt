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
  // Add with extended register operand: ADD Xd, Xn, Wm, UXTW #shift
  AddExtUxtw(Int, Int, Int, Int) // rd, rn, rm, shift (0-4)
  AddImm(Int, Int, Int)
  AddImmShifted12(Int, Int, Int) // ADD with immediate shifted left by 12
  SubReg(Int, Int, Int)
  SubShifted(Int, Int, Int, @instr.ShiftType, Int)
  SubImm(Int, Int, Int)
  SubImmShifted12(Int, Int, Int) // SUB with immediate shifted left by 12
  Mul(Int, Int, Int)
  Madd(Int, Int, Int, Int)
  Msub(Int, Int, Int, Int)
  Mneg(Int, Int, Int)
  Umulh(Int, Int, Int) // Unsigned multiply high (64-bit)
  Smulh(Int, Int, Int) // Signed multiply high (64-bit)
  Umull(Int, Int, Int) // Unsigned 32x32->64 multiply
  Smull(Int, Int, Int) // Signed 32x32->64 multiply
  Sdiv(Int, Int, Int)
  Udiv(Int, Int, Int)
  Sdiv32(Int, Int, Int) // 32-bit signed divide
  Udiv32(Int, Int, Int) // 32-bit unsigned divide
  SubReg32(Int, Int, Int) // 32-bit subtract
  AddReg32(Int, Int, Int) // 32-bit add
  AddImm32(Int, Int, Int) // 32-bit add immediate
  SubImm32(Int, Int, Int) // 32-bit sub immediate
  Mul32(Int, Int, Int) // 32-bit multiply
  // Bitwise - Register
  AndReg(Int, Int, Int)
  AndShifted(Int, Int, Int, @instr.ShiftType, Int)
  OrrReg(Int, Int, Int)
  OrrShifted(Int, Int, Int, @instr.ShiftType, Int)
  EorReg(Int, Int, Int)
  EorShifted(Int, Int, Int, @instr.ShiftType, Int)
  Mvn(Int, Int)
  Mvn32(Int, Int) // 32-bit bitwise NOT
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
  // Shift - Immediate (64-bit): LSR Xd, Xn, #shift
  LsrImm(Int, Int, Int)
  // Shift - Immediate (32-bit): LSR Wd, Wn, #shift
  LsrImm32(Int, Int, Int)
  // Unsigned Bitfield Extract: UBFX Xd, Xn, #0, #width
  // Extracts bits [0, width-1] from Xn to Xd (zero-extended)
  UbfxWidth(Int, Int, Int)
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
  Movn(Int, Int, Int)
  LoadImm64(Int, Int64)
  // Load/Store - GPR
  LdrImm(Int, Int, Int)
  LdrImmSigned(Int, Int, Int)
  LdrRegScaled(Int, Int, Int, Int)
  // Register-offset load/store using X register offset (UXTX), optional scaling.
  // shift is either 0 (no scale) or the natural scale for the access size.
  LdrWRegScaled(Int, Int, Int, Int)
  StrWRegScaled(Int, Int, Int, Int)
  LdrbReg(Int, Int, Int)
  StrbReg(Int, Int, Int)
  LdrhReg(Int, Int, Int)
  StrhReg(Int, Int, Int)
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
  // Pre-indexed stores (Standard prologue)
  StrPre(Int, Int, Int) // rt, rn, simm9 - STR Xt, [Xn, #simm9]!
  StpDPre(Int, Int, Int, Int) // rt1, rt2, rn, imm7 - STP Dt1, Dt2, [Xn, #imm7]!
  StrDPre(Int, Int, Int) // rt, rn, simm9 - STR Dt, [Xn, #simm9]!
  // Post-indexed loads (Standard epilogue)
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
  Cbz(Int, Int) // 64-bit CBZ
  Cbnz(Int, Int) // 64-bit CBNZ
  Cbz32(Int, Int) // 32-bit CBZ
  Cbnz32(Int, Int) // 32-bit CBNZ
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
  // ============ NEON SIMD Instructions ============
  // V128 Load/Store
  LdrQ(Int, Int, Int) // LDR Qd, [Xn, #imm] (128-bit)
  StrQ(Int, Int, Int) // STR Qs, [Xn, #imm] (128-bit)
  // Splat (DUP from GPR)
  Dup16B(Int, Int) // DUP Vd.16B, Wn
  Dup8H(Int, Int) // DUP Vd.8H, Wn
  Dup4S(Int, Int) // DUP Vd.4S, Wn
  Dup2D(Int, Int) // DUP Vd.2D, Xn
  // Splat from element (DUP from scalar)
  DupElem4S(Int, Int, Int) // DUP Vd.4S, Vn.S[lane]
  DupElem2D(Int, Int, Int) // DUP Vd.2D, Vn.D[lane]
  // Extract lane (UMOV/SMOV)
  UmovB(Int, Int, Int) // UMOV Wd, Vn.B[lane]
  UmovH(Int, Int, Int) // UMOV Wd, Vn.H[lane]
  UmovS(Int, Int, Int) // UMOV Wd, Vn.S[lane]
  UmovD(Int, Int, Int) // UMOV Xd, Vn.D[lane]
  SmovB(Int, Int, Int) // SMOV Wd, Vn.B[lane]
  SmovH(Int, Int, Int) // SMOV Wd, Vn.H[lane]
  SmovS(Int, Int, Int) // SMOV Xd, Vn.S[lane] (sign extend to 64-bit)
  // Extract float lane (DUP to scalar)
  DupScalarS(Int, Int, Int) // DUP Sd, Vn.S[lane]
  DupScalarD(Int, Int, Int) // DUP Dd, Vn.D[lane]
  // Insert lane (INS from GPR)
  InsB(Int, Int, Int) // INS Vd.B[lane], Wn
  InsH(Int, Int, Int) // INS Vd.H[lane], Wn
  InsS(Int, Int, Int) // INS Vd.S[lane], Wn
  InsD(Int, Int, Int) // INS Vd.D[lane], Xn
  // Insert from element
  InsElemS(Int, Int, Int, Int) // INS Vd.S[lane], Vn.S[0]
  InsElemD(Int, Int, Int, Int) // INS Vd.D[lane], Vn.D[0]
  // Bitwise
  Not16B(Int, Int) // NOT Vd.16B, Vn.16B
  And16B(Int, Int, Int) // AND Vd.16B, Vn.16B, Vm.16B
  Orr16B(Int, Int, Int) // ORR Vd.16B, Vn.16B, Vm.16B
  Eor16B(Int, Int, Int) // EOR Vd.16B, Vn.16B, Vm.16B
  Bic16B(Int, Int, Int) // BIC Vd.16B, Vn.16B, Vm.16B
  Bsl16B(Int, Int, Int) // BSL Vd.16B, Vn.16B, Vm.16B
  // Swizzle/Shuffle
  Tbl1(Int, Int, Int) // TBL Vd.16B, {Vn.16B}, Vm.16B
  // Integer arithmetic (16 lanes, 8-bit)
  Add16B(Int, Int, Int) // ADD Vd.16B, Vn.16B, Vm.16B
  Sub16B(Int, Int, Int) // SUB Vd.16B, Vn.16B, Vm.16B
  // Integer arithmetic (8 lanes, 16-bit)
  Add8H(Int, Int, Int) // ADD Vd.8H, Vn.8H, Vm.8H
  Sub8H(Int, Int, Int) // SUB Vd.8H, Vn.8H, Vm.8H
  Mul8H(Int, Int, Int) // MUL Vd.8H, Vn.8H, Vm.8H
  // Integer arithmetic (4 lanes, 32-bit)
  Add4S(Int, Int, Int) // ADD Vd.4S, Vn.4S, Vm.4S
  Sub4S(Int, Int, Int) // SUB Vd.4S, Vn.4S, Vm.4S
  Mul4S(Int, Int, Int) // MUL Vd.4S, Vn.4S, Vm.4S
  // Integer arithmetic (2 lanes, 64-bit)
  Add2D(Int, Int, Int) // ADD Vd.2D, Vn.2D, Vm.2D
  Sub2D(Int, Int, Int) // SUB Vd.2D, Vn.2D, Vm.2D
  // No MUL for 64-bit lanes in NEON, need PMULL or separate approach
  // Saturating arithmetic
  Sqadd16B(Int, Int, Int) // SQADD Vd.16B, Vn.16B, Vm.16B
  Sqadd8H(Int, Int, Int) // SQADD Vd.8H, Vn.8H, Vm.8H
  Sqadd4S(Int, Int, Int) // SQADD Vd.4S, Vn.4S, Vm.4S
  Sqadd2D(Int, Int, Int) // SQADD Vd.2D, Vn.2D, Vm.2D
  Uqadd16B(Int, Int, Int) // UQADD Vd.16B, Vn.16B, Vm.16B
  Uqadd8H(Int, Int, Int) // UQADD Vd.8H, Vn.8H, Vm.8H
  Uqadd4S(Int, Int, Int) // UQADD Vd.4S, Vn.4S, Vm.4S
  Uqadd2D(Int, Int, Int) // UQADD Vd.2D, Vn.2D, Vm.2D
  Sqsub16B(Int, Int, Int) // SQSUB Vd.16B, Vn.16B, Vm.16B
  Sqsub8H(Int, Int, Int) // SQSUB Vd.8H, Vn.8H, Vm.8H
  Sqsub4S(Int, Int, Int) // SQSUB Vd.4S, Vn.4S, Vm.4S
  Sqsub2D(Int, Int, Int) // SQSUB Vd.2D, Vn.2D, Vm.2D
  Uqsub16B(Int, Int, Int) // UQSUB Vd.16B, Vn.16B, Vm.16B
  Uqsub8H(Int, Int, Int) // UQSUB Vd.8H, Vn.8H, Vm.8H
  Uqsub4S(Int, Int, Int) // UQSUB Vd.4S, Vn.4S, Vm.4S
  Uqsub2D(Int, Int, Int) // UQSUB Vd.2D, Vn.2D, Vm.2D
  // Min/Max
  Smin16B(Int, Int, Int) // SMIN Vd.16B, Vn.16B, Vm.16B
  Smin8H(Int, Int, Int) // SMIN Vd.8H, Vn.8H, Vm.8H
  Smin4S(Int, Int, Int) // SMIN Vd.4S, Vn.4S, Vm.4S
  Umin16B(Int, Int, Int) // UMIN Vd.16B, Vn.16B, Vm.16B
  Umin8H(Int, Int, Int) // UMIN Vd.8H, Vn.8H, Vm.8H
  Umin4S(Int, Int, Int) // UMIN Vd.4S, Vn.4S, Vm.4S
  Smax16B(Int, Int, Int) // SMAX Vd.16B, Vn.16B, Vm.16B
  Smax8H(Int, Int, Int) // SMAX Vd.8H, Vn.8H, Vm.8H
  Smax4S(Int, Int, Int) // SMAX Vd.4S, Vn.4S, Vm.4S
  Umax16B(Int, Int, Int) // UMAX Vd.16B, Vn.16B, Vm.16B
  Umax8H(Int, Int, Int) // UMAX Vd.8H, Vn.8H, Vm.8H
  Umax4S(Int, Int, Int) // UMAX Vd.4S, Vn.4S, Vm.4S
  // Urhadd
  Urhadd16B(Int, Int, Int) // URHADD Vd.16B, Vn.16B, Vm.16B
  Urhadd8H(Int, Int, Int) // URHADD Vd.8H, Vn.8H, Vm.8H
  Urhadd4S(Int, Int, Int) // URHADD Vd.4S, Vn.4S, Vm.4S
  // Abs/Neg
  Abs16B(Int, Int) // ABS Vd.16B, Vn.16B
  Abs8H(Int, Int) // ABS Vd.8H, Vn.8H
  Abs4S(Int, Int) // ABS Vd.4S, Vn.4S
  Abs2D(Int, Int) // ABS Vd.2D, Vn.2D
  Neg16B(Int, Int) // NEG Vd.16B, Vn.16B
  Neg8H(Int, Int) // NEG Vd.8H, Vn.8H
  Neg4S(Int, Int) // NEG Vd.4S, Vn.4S
  Neg2D(Int, Int) // NEG Vd.2D, Vn.2D
  // CNT for full 128-bit
  Cnt16B(Int, Int) // CNT Vd.16B, Vn.16B
  // Shifts (register-based with scalar in GPR)
  Sshl16B(Int, Int, Int) // SSHL Vd.16B, Vn.16B, Vm.16B (shift by element)
  Sshl8H(Int, Int, Int) // SSHL Vd.8H, Vn.8H, Vm.8H
  Sshl4S(Int, Int, Int) // SSHL Vd.4S, Vn.4S, Vm.4S
  Sshl2D(Int, Int, Int) // SSHL Vd.2D, Vn.2D, Vm.2D
  Ushl16B(Int, Int, Int) // USHL Vd.16B, Vn.16B, Vm.16B
  Ushl8H(Int, Int, Int) // USHL Vd.8H, Vn.8H, Vm.8H
  Ushl4S(Int, Int, Int) // USHL Vd.4S, Vn.4S, Vm.4S
  Ushl2D(Int, Int, Int) // USHL Vd.2D, Vn.2D, Vm.2D
  // Comparison
  Cmeq16B(Int, Int, Int) // CMEQ Vd.16B, Vn.16B, Vm.16B
  Cmeq8H(Int, Int, Int) // CMEQ Vd.8H, Vn.8H, Vm.8H
  Cmeq4S(Int, Int, Int) // CMEQ Vd.4S, Vn.4S, Vm.4S
  Cmeq2D(Int, Int, Int) // CMEQ Vd.2D, Vn.2D, Vm.2D
  Cmgt16B(Int, Int, Int) // CMGT Vd.16B, Vn.16B, Vm.16B
  Cmgt8H(Int, Int, Int) // CMGT Vd.8H, Vn.8H, Vm.8H
  Cmgt4S(Int, Int, Int) // CMGT Vd.4S, Vn.4S, Vm.4S
  Cmgt2D(Int, Int, Int) // CMGT Vd.2D, Vn.2D, Vm.2D
  Cmge16B(Int, Int, Int) // CMGE Vd.16B, Vn.16B, Vm.16B
  Cmge8H(Int, Int, Int) // CMGE Vd.8H, Vn.8H, Vm.8H
  Cmge4S(Int, Int, Int) // CMGE Vd.4S, Vn.4S, Vm.4S
  Cmge2D(Int, Int, Int) // CMGE Vd.2D, Vn.2D, Vm.2D
  Cmhi16B(Int, Int, Int) // CMHI Vd.16B, Vn.16B, Vm.16B (unsigned >)
  Cmhi8H(Int, Int, Int) // CMHI Vd.8H, Vn.8H, Vm.8H
  Cmhi4S(Int, Int, Int) // CMHI Vd.4S, Vn.4S, Vm.4S
  Cmhi2D(Int, Int, Int) // CMHI Vd.2D, Vn.2D, Vm.2D
  Cmhs16B(Int, Int, Int) // CMHS Vd.16B, Vn.16B, Vm.16B (unsigned >=)
  Cmhs8H(Int, Int, Int) // CMHS Vd.8H, Vn.8H, Vm.8H
  Cmhs4S(Int, Int, Int) // CMHS Vd.4S, Vn.4S, Vm.4S
  Cmhs2D(Int, Int, Int) // CMHS Vd.2D, Vn.2D, Vm.2D
  // Narrowing (non-saturating - used by i64x2.mul implementation)
  Xtn2S(Int, Int) // XTN Vd.2S, Vn.2D
  // Narrowing (saturating - used by WebAssembly narrow operations)
  Sqxtn8B(Int, Int) // SQXTN Vd.8B, Vn.8H
  Sqxtn4H(Int, Int) // SQXTN Vd.4H, Vn.4S
  Sqxtn2S(Int, Int) // SQXTN Vd.2S, Vn.2D
  Sqxtun8B(Int, Int) // SQXTUN Vd.8B, Vn.8H
  Sqxtun4H(Int, Int) // SQXTUN Vd.4H, Vn.4S
  // Note: Sqxtun2S not needed - no i64->i32 narrow in WebAssembly
  // Note: Uqxtn8B/4H not needed - WebAssembly narrow_u uses SQXTUN (signed source)
  Uqxtn2S(Int, Int) // UQXTN Vd.2S, Vn.2D - used by i32x4.trunc_sat_f64x2_u_zero
  // Narrowing (second half - writes to upper portion of Vd)
  Sqxtn2_16B(Int, Int) // SQXTN2 Vd.16B, Vn.8H (writes upper 8 bytes)
  Sqxtn2_8H(Int, Int) // SQXTN2 Vd.8H, Vn.4S (writes upper 4 halfwords)
  Sqxtun2_16B(Int, Int) // SQXTUN2 Vd.16B, Vn.8H (writes upper 8 bytes)
  Sqxtun2_8H(Int, Int) // SQXTUN2 Vd.8H, Vn.4S (writes upper 4 halfwords)
  // Extending
  Sxtl8H(Int, Int) // SXTL Vd.8H, Vn.8B (aka SSHLL with shift 0)
  Sxtl4S(Int, Int) // SXTL Vd.4S, Vn.4H
  Sxtl2D(Int, Int) // SXTL Vd.2D, Vn.2S
  Sxtl2_8H(Int, Int) // SXTL2 Vd.8H, Vn.16B
  Sxtl2_4S(Int, Int) // SXTL2 Vd.4S, Vn.8H
  Sxtl2_2D(Int, Int) // SXTL2 Vd.2D, Vn.4S
  Uxtl8H(Int, Int) // UXTL Vd.8H, Vn.8B (aka USHLL with shift 0)
  Uxtl4S(Int, Int) // UXTL Vd.4S, Vn.4H
  Uxtl2D(Int, Int) // UXTL Vd.2D, Vn.2S
  Uxtl2_8H(Int, Int) // UXTL2 Vd.8H, Vn.16B
  Uxtl2_4S(Int, Int) // UXTL2 Vd.4S, Vn.8H
  Uxtl2_2D(Int, Int) // UXTL2 Vd.2D, Vn.4S
  // Extended multiply (low half)
  Smull8H(Int, Int, Int) // SMULL Vd.8H, Vn.8B, Vm.8B
  Smull4S(Int, Int, Int) // SMULL Vd.4S, Vn.4H, Vm.4H
  Smull2D(Int, Int, Int) // SMULL Vd.2D, Vn.2S, Vm.2S
  Umull8H(Int, Int, Int) // UMULL Vd.8H, Vn.8B, Vm.8B
  Umull4S(Int, Int, Int) // UMULL Vd.4S, Vn.4H, Vm.4H
  Umull2D(Int, Int, Int) // UMULL Vd.2D, Vn.2S, Vm.2S
  // Extended multiply (high half)
  Smull2_8H(Int, Int, Int) // SMULL2 Vd.8H, Vn.16B, Vm.16B
  Smull2_4S(Int, Int, Int) // SMULL2 Vd.4S, Vn.8H, Vm.8H
  Smull2_2D(Int, Int, Int) // SMULL2 Vd.2D, Vn.4S, Vm.4S
  Umull2_8H(Int, Int, Int) // UMULL2 Vd.8H, Vn.16B, Vm.16B
  Umull2_4S(Int, Int, Int) // UMULL2 Vd.4S, Vn.8H, Vm.8H
  Umull2_2D(Int, Int, Int) // UMULL2 Vd.2D, Vn.4S, Vm.4S
  // Pairwise add
  Saddlp8H(Int, Int) // SADDLP Vd.8H, Vn.16B
  Saddlp4S(Int, Int) // SADDLP Vd.4S, Vn.8H
  Uaddlp8H(Int, Int) // UADDLP Vd.8H, Vn.16B
  Uaddlp4S(Int, Int) // UADDLP Vd.4S, Vn.8H
  Uaddlp2D(Int, Int) // UADDLP Vd.2D, Vn.4S
  // Pairwise add (for dot product)
  Addp8H(Int, Int, Int) // ADDP Vd.8H, Vn.8H, Vm.8H
  Addp4S(Int, Int, Int) // ADDP Vd.4S, Vn.4S, Vm.4S
  // Q15 saturating rounding multiply high
  Sqrdmulh8H(Int, Int, Int) // SQRDMULH Vd.8H, Vn.8H, Vm.8H
  // Float arithmetic
  Fadd4S(Int, Int, Int) // FADD Vd.4S, Vn.4S, Vm.4S
  Fadd2D(Int, Int, Int) // FADD Vd.2D, Vn.2D, Vm.2D
  Fsub4S(Int, Int, Int) // FSUB Vd.4S, Vn.4S, Vm.4S
  Fsub2D(Int, Int, Int) // FSUB Vd.2D, Vn.2D, Vm.2D
  Fmul4S(Int, Int, Int) // FMUL Vd.4S, Vn.4S, Vm.4S
  Fmul2D(Int, Int, Int) // FMUL Vd.2D, Vn.2D, Vm.2D
  Fdiv4S(Int, Int, Int) // FDIV Vd.4S, Vn.4S, Vm.4S
  Fdiv2D(Int, Int, Int) // FDIV Vd.2D, Vn.2D, Vm.2D
  Fmin4S(Int, Int, Int) // FMIN Vd.4S, Vn.4S, Vm.4S
  Fmin2D(Int, Int, Int) // FMIN Vd.2D, Vn.2D, Vm.2D
  Fmax4S(Int, Int, Int) // FMAX Vd.4S, Vn.4S, Vm.4S
  Fmax2D(Int, Int, Int) // FMAX Vd.2D, Vn.2D, Vm.2D
  // Fused multiply-add (relaxed SIMD)
  Fmla4S(Int, Int, Int) // FMLA Vd.4S, Vn.4S, Vm.4S: Vd = Vd + Vn * Vm
  Fmla2D(Int, Int, Int) // FMLA Vd.2D, Vn.2D, Vm.2D
  Fmls4S(Int, Int, Int) // FMLS Vd.4S, Vn.4S, Vm.4S: Vd = Vd - Vn * Vm
  Fmls2D(Int, Int, Int) // FMLS Vd.2D, Vn.2D, Vm.2D
  // Float unary
  Fabs4S(Int, Int) // FABS Vd.4S, Vn.4S
  Fabs2D(Int, Int) // FABS Vd.2D, Vn.2D
  Fneg4S(Int, Int) // FNEG Vd.4S, Vn.4S
  Fneg2D(Int, Int) // FNEG Vd.2D, Vn.2D
  Fsqrt4S(Int, Int) // FSQRT Vd.4S, Vn.4S
  Fsqrt2D(Int, Int) // FSQRT Vd.2D, Vn.2D
  Frintp4S(Int, Int) // FRINTP Vd.4S, Vn.4S (ceil)
  Frintp2D(Int, Int) // FRINTP Vd.2D, Vn.2D
  Frintm4S(Int, Int) // FRINTM Vd.4S, Vn.4S (floor)
  Frintm2D(Int, Int) // FRINTM Vd.2D, Vn.2D
  Frintz4S(Int, Int) // FRINTZ Vd.4S, Vn.4S (trunc)
  Frintz2D(Int, Int) // FRINTZ Vd.2D, Vn.2D
  Frintn4S(Int, Int) // FRINTN Vd.4S, Vn.4S (nearest)
  Frintn2D(Int, Int) // FRINTN Vd.2D, Vn.2D
  // Float comparison
  Fcmeq4S(Int, Int, Int) // FCMEQ Vd.4S, Vn.4S, Vm.4S
  Fcmeq2D(Int, Int, Int) // FCMEQ Vd.2D, Vn.2D, Vm.2D
  Fcmgt4S(Int, Int, Int) // FCMGT Vd.4S, Vn.4S, Vm.4S
  Fcmgt2D(Int, Int, Int) // FCMGT Vd.2D, Vn.2D, Vm.2D
  Fcmge4S(Int, Int, Int) // FCMGE Vd.4S, Vn.4S, Vm.4S
  Fcmge2D(Int, Int, Int) // FCMGE Vd.2D, Vn.2D, Vm.2D
  // Float conversion
  Fcvtzs4S(Int, Int) // FCVTZS Vd.4S, Vn.4S (f32 -> i32)
  Fcvtzs2D(Int, Int) // FCVTZS Vd.2D, Vn.2D (f64 -> i64)
  Fcvtzu4S(Int, Int) // FCVTZU Vd.4S, Vn.4S
  Fcvtzu2D(Int, Int) // FCVTZU Vd.2D, Vn.2D
  Scvtf4S(Int, Int) // SCVTF Vd.4S, Vn.4S (i32 -> f32)
  Scvtf2D(Int, Int) // SCVTF Vd.2D, Vn.2D (i64 -> f64)
  Ucvtf4S(Int, Int) // UCVTF Vd.4S, Vn.4S
  Ucvtf2D(Int, Int) // UCVTF Vd.2D, Vn.2D
  // F64/F32 conversions
  Fcvtn2S(Int, Int) // FCVTN Vd.2S, Vn.2D (demote f64x2 -> f32x2, lower 64 bits)
  Fcvtl2D(Int, Int) // FCVTL Vd.2D, Vn.2S (promote f32x2 -> f64x2)
  // Load splat
  Ld1rB(Int, Int) // LD1R {Vd.16B}, [Xn]
  Ld1rH(Int, Int) // LD1R {Vd.8H}, [Xn]
  Ld1rS(Int, Int) // LD1R {Vd.4S}, [Xn]
  Ld1rD(Int, Int) // LD1R {Vd.2D}, [Xn]
  // Load single lane
  Ld1B(Int, Int, Int) // LD1 {Vd.B}[lane], [Xn]
  Ld1H(Int, Int, Int) // LD1 {Vd.H}[lane], [Xn]
  Ld1S(Int, Int, Int) // LD1 {Vd.S}[lane], [Xn]
  Ld1D(Int, Int, Int) // LD1 {Vd.D}[lane], [Xn]
  // Store single lane
  St1B(Int, Int, Int) // ST1 {Vn.B}[lane], [Xd]
  St1H(Int, Int, Int) // ST1 {Vn.H}[lane], [Xd]
  St1S(Int, Int, Int) // ST1 {Vn.S}[lane], [Xd]
  St1D(Int, Int, Int) // ST1 {Vn.D}[lane], [Xd]
  // UMAXV/UMINV for any_true/all_true
  Umaxv16B(Int, Int) // UMAXV Bd, Vn.16B
  Uminv16B(Int, Int) // UMINV Bd, Vn.16B
  Uminv8H(Int, Int) // UMINV Hd, Vn.8H
  Uminv4S(Int, Int) // UMINV Sd, Vn.4S
  // MOVI for zeroing
  MoviZero(Int) // MOVI Vd.2D, #0
  // Orr for move
  OrrVec(Int, Int) // ORR Vd.16B, Vn.16B, Vn.16B (move)
  // For i64x2.mul emulation
  Rev64_4S(Int, Int) // REV64 Vd.4S, Vn.4S (swap 32-bit halves within 64-bit lanes)
  ShlImm2D(Int, Int, Int) // SHL Vd.2D, Vn.2D, #imm
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
    AddExtUxtw(rd, rn, rm, shift) => {
      let suffix = if shift == 0 { "uxtw" } else { "uxtw #\{shift}" }
      "add x\{rd}, x\{rn}, w\{rm}, \{suffix}"
    }
    AddImm(rd, rn, imm12) => {
      let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
      let rd_name = if rd == 31 { "sp" } else { "x\{rd}" }
      "add \{rd_name}, \{rn_name}, #\{imm12}"
    }
    AddImmShifted12(rd, rn, imm12) => {
      let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
      let rd_name = if rd == 31 { "sp" } else { "x\{rd}" }
      "add \{rd_name}, \{rn_name}, #\{imm12}, lsl #12"
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
    SubImmShifted12(rd, rn, imm12) => {
      let rn_name = if rn == 31 { "sp" } else { "x\{rn}" }
      let rd_name = if rd == 31 { "sp" } else { "x\{rd}" }
      "sub \{rd_name}, \{rn_name}, #\{imm12}, lsl #12"
    }
    Mul(rd, rn, rm) => "mul x\{rd}, x\{rn}, x\{rm}"
    Madd(rd, rn, rm, ra) => "madd x\{rd}, x\{rn}, x\{rm}, x\{ra}"
    Msub(rd, rn, rm, ra) => "msub x\{rd}, x\{rn}, x\{rm}, x\{ra}"
    Mneg(rd, rn, rm) => "mneg x\{rd}, x\{rn}, x\{rm}"
    Umulh(rd, rn, rm) => "umulh x\{rd}, x\{rn}, x\{rm}"
    Smulh(rd, rn, rm) => "smulh x\{rd}, x\{rn}, x\{rm}"
    Umull(rd, rn, rm) => "umull x\{rd}, w\{rn}, w\{rm}"
    Smull(rd, rn, rm) => "smull x\{rd}, w\{rn}, w\{rm}"
    Sdiv(rd, rn, rm) => "sdiv x\{rd}, x\{rn}, x\{rm}"
    Udiv(rd, rn, rm) => "udiv x\{rd}, x\{rn}, x\{rm}"
    Sdiv32(rd, rn, rm) => "sdiv w\{rd}, w\{rn}, w\{rm}"
    Udiv32(rd, rn, rm) => "udiv w\{rd}, w\{rn}, w\{rm}"
    SubReg32(rd, rn, rm) => "sub w\{rd}, w\{rn}, w\{rm}"
    AddReg32(rd, rn, rm) => "add w\{rd}, w\{rn}, w\{rm}"
    AddImm32(rd, rn, imm) => "add w\{rd}, w\{rn}, #\{imm}"
    SubImm32(rd, rn, imm) => "sub w\{rd}, w\{rn}, #\{imm}"
    Mul32(rd, rn, rm) => "mul w\{rd}, w\{rn}, w\{rm}"
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
    Mvn32(rd, rm) => "mvn w\{rd}, w\{rm}"
    LslReg(rd, rn, rm) => "lsl x\{rd}, x\{rn}, x\{rm}"
    LsrReg(rd, rn, rm) => "lsr x\{rd}, x\{rn}, x\{rm}"
    AsrReg(rd, rn, rm) => "asr x\{rd}, x\{rn}, x\{rm}"
    RorReg(rd, rn, rm) => "ror x\{rd}, x\{rn}, x\{rm}"
    LslReg32(rd, rn, rm) => "lsl w\{rd}, w\{rn}, w\{rm}"
    LsrReg32(rd, rn, rm) => "lsr w\{rd}, w\{rn}, w\{rm}"
    AsrReg32(rd, rn, rm) => "asr w\{rd}, w\{rn}, w\{rm}"
    RorReg32(rd, rn, rm) => "ror w\{rd}, w\{rn}, w\{rm}"
    LsrImm(rd, rn, shift) => "lsr x\{rd}, x\{rn}, #\{shift}"
    LsrImm32(rd, rn, shift) => "lsr w\{rd}, w\{rn}, #\{shift}"
    UbfxWidth(rd, rn, width) => "ubfx x\{rd}, x\{rn}, #0, #\{width}"
    Clz(rd, rn) => "clz x\{rd}, x\{rn}"
    Rbit(rd, rn) => "rbit x\{rd}, x\{rn}"
    Clz32(rd, rn) => "clz w\{rd}, w\{rn}"
    Rbit32(rd, rn) => "rbit w\{rd}, w\{rn}"
    MovReg(rd, rm) => "mov x\{rd}, x\{rm}"
    MovReg32(rd, rm) => "mov w\{rd}, w\{rm}"
    Movz(rd, imm16, shift) => "movz x\{rd}, #\{imm16}, lsl #\{shift}"
    Movk(rd, imm16, shift) => "movk x\{rd}, #\{imm16}, lsl #\{shift}"
    Movn(rd, imm16, shift) => "movn x\{rd}, #\{imm16}, lsl #\{shift}"
    LoadImm64(_, _) => "load_imm64 (multi-instruction)"
    LdrImm(rt, rn, imm12) => "ldr x\{rt}, [x\{rn}, #\{imm12}]"
    LdrImmSigned(rt, rn, simm9) => "ldur x\{rt}, [x\{rn}, #\{simm9}]"
    LdrRegScaled(rt, rn, rm, shift) =>
      "ldr x\{rt}, [x\{rn}, x\{rm}, lsl #\{shift}]"
    LdrWRegScaled(rt, rn, rm, shift) =>
      "ldr w\{rt}, [x\{rn}, x\{rm}, lsl #\{shift}]"
    StrWRegScaled(rt, rn, rm, shift) =>
      "str w\{rt}, [x\{rn}, x\{rm}, lsl #\{shift}]"
    LdrbReg(rt, rn, rm) => "ldrb w\{rt}, [x\{rn}, x\{rm}]"
    StrbReg(rt, rn, rm) => "strb w\{rt}, [x\{rn}, x\{rm}]"
    LdrhReg(rt, rn, rm) => "ldrh w\{rt}, [x\{rn}, x\{rm}]"
    StrhReg(rt, rn, rm) => "strh w\{rt}, [x\{rn}, x\{rm}]"
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
    Cbz32(rt, target_block) => "cbz w\{rt}, block\{target_block}"
    Cbnz32(rt, target_block) => "cbnz w\{rt}, block\{target_block}"
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
    // NEON SIMD instructions
    LdrQ(rd, rn, imm) => "ldr q\{rd}, [x\{rn}, #\{imm}]"
    StrQ(rt, rn, imm) => "str q\{rt}, [x\{rn}, #\{imm}]"
    Dup16B(rd, rn) => "dup v\{rd}.16b, w\{rn}"
    Dup8H(rd, rn) => "dup v\{rd}.8h, w\{rn}"
    Dup4S(rd, rn) => "dup v\{rd}.4s, w\{rn}"
    Dup2D(rd, rn) => "dup v\{rd}.2d, x\{rn}"
    DupElem4S(rd, rn, lane) => "dup v\{rd}.4s, v\{rn}.s[\{lane}]"
    DupElem2D(rd, rn, lane) => "dup v\{rd}.2d, v\{rn}.d[\{lane}]"
    UmovB(rd, rn, lane) => "umov w\{rd}, v\{rn}.b[\{lane}]"
    UmovH(rd, rn, lane) => "umov w\{rd}, v\{rn}.h[\{lane}]"
    UmovS(rd, rn, lane) => "umov w\{rd}, v\{rn}.s[\{lane}]"
    UmovD(rd, rn, lane) => "umov x\{rd}, v\{rn}.d[\{lane}]"
    SmovB(rd, rn, lane) => "smov w\{rd}, v\{rn}.b[\{lane}]"
    SmovH(rd, rn, lane) => "smov w\{rd}, v\{rn}.h[\{lane}]"
    SmovS(rd, rn, lane) => "smov x\{rd}, v\{rn}.s[\{lane}]"
    DupScalarS(rd, rn, lane) => "dup s\{rd}, v\{rn}.s[\{lane}]"
    DupScalarD(rd, rn, lane) => "dup d\{rd}, v\{rn}.d[\{lane}]"
    InsB(rd, lane, rn) => "ins v\{rd}.b[\{lane}], w\{rn}"
    InsH(rd, lane, rn) => "ins v\{rd}.h[\{lane}], w\{rn}"
    InsS(rd, lane, rn) => "ins v\{rd}.s[\{lane}], w\{rn}"
    InsD(rd, lane, rn) => "ins v\{rd}.d[\{lane}], x\{rn}"
    InsElemS(rd, dlane, rn, slane) =>
      "ins v\{rd}.s[\{dlane}], v\{rn}.s[\{slane}]"
    InsElemD(rd, dlane, rn, slane) =>
      "ins v\{rd}.d[\{dlane}], v\{rn}.d[\{slane}]"
    Not16B(rd, rn) => "not v\{rd}.16b, v\{rn}.16b"
    And16B(rd, rn, rm) => "and v\{rd}.16b, v\{rn}.16b, v\{rm}.16b"
    Orr16B(rd, rn, rm) => "orr v\{rd}.16b, v\{rn}.16b, v\{rm}.16b"
    Eor16B(rd, rn, rm) => "eor v\{rd}.16b, v\{rn}.16b, v\{rm}.16b"
    Bic16B(rd, rn, rm) => "bic v\{rd}.16b, v\{rn}.16b, v\{rm}.16b"
    Bsl16B(rd, rn, rm) => "bsl v\{rd}.16b, v\{rn}.16b, v\{rm}.16b"
    Tbl1(rd, rn, rm) => "tbl v\{rd}.16b, {v\{rn}.16b}, v\{rm}.16b"
    Add16B(rd, rn, rm) => "add v\{rd}.16b, v\{rn}.16b, v\{rm}.16b"
    Sub16B(rd, rn, rm) => "sub v\{rd}.16b, v\{rn}.16b, v\{rm}.16b"
    Add8H(rd, rn, rm) => "add v\{rd}.8h, v\{rn}.8h, v\{rm}.8h"
    Sub8H(rd, rn, rm) => "sub v\{rd}.8h, v\{rn}.8h, v\{rm}.8h"
    Mul8H(rd, rn, rm) => "mul v\{rd}.8h, v\{rn}.8h, v\{rm}.8h"
    Add4S(rd, rn, rm) => "add v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Sub4S(rd, rn, rm) => "sub v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Mul4S(rd, rn, rm) => "mul v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Add2D(rd, rn, rm) => "add v\{rd}.2d, v\{rn}.2d, v\{rm}.2d"
    Sub2D(rd, rn, rm) => "sub v\{rd}.2d, v\{rn}.2d, v\{rm}.2d"
    Sqadd16B(rd, rn, rm) => "sqadd v\{rd}.16b, v\{rn}.16b, v\{rm}.16b"
    Sqadd8H(rd, rn, rm) => "sqadd v\{rd}.8h, v\{rn}.8h, v\{rm}.8h"
    Sqadd4S(rd, rn, rm) => "sqadd v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Sqadd2D(rd, rn, rm) => "sqadd v\{rd}.2d, v\{rn}.2d, v\{rm}.2d"
    Uqadd16B(rd, rn, rm) => "uqadd v\{rd}.16b, v\{rn}.16b, v\{rm}.16b"
    Uqadd8H(rd, rn, rm) => "uqadd v\{rd}.8h, v\{rn}.8h, v\{rm}.8h"
    Uqadd4S(rd, rn, rm) => "uqadd v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Uqadd2D(rd, rn, rm) => "uqadd v\{rd}.2d, v\{rn}.2d, v\{rm}.2d"
    Sqsub16B(rd, rn, rm) => "sqsub v\{rd}.16b, v\{rn}.16b, v\{rm}.16b"
    Sqsub8H(rd, rn, rm) => "sqsub v\{rd}.8h, v\{rn}.8h, v\{rm}.8h"
    Sqsub4S(rd, rn, rm) => "sqsub v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Sqsub2D(rd, rn, rm) => "sqsub v\{rd}.2d, v\{rn}.2d, v\{rm}.2d"
    Uqsub16B(rd, rn, rm) => "uqsub v\{rd}.16b, v\{rn}.16b, v\{rm}.16b"
    Uqsub8H(rd, rn, rm) => "uqsub v\{rd}.8h, v\{rn}.8h, v\{rm}.8h"
    Uqsub4S(rd, rn, rm) => "uqsub v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Uqsub2D(rd, rn, rm) => "uqsub v\{rd}.2d, v\{rn}.2d, v\{rm}.2d"
    Smin16B(rd, rn, rm) => "smin v\{rd}.16b, v\{rn}.16b, v\{rm}.16b"
    Smin8H(rd, rn, rm) => "smin v\{rd}.8h, v\{rn}.8h, v\{rm}.8h"
    Smin4S(rd, rn, rm) => "smin v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Umin16B(rd, rn, rm) => "umin v\{rd}.16b, v\{rn}.16b, v\{rm}.16b"
    Umin8H(rd, rn, rm) => "umin v\{rd}.8h, v\{rn}.8h, v\{rm}.8h"
    Umin4S(rd, rn, rm) => "umin v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Smax16B(rd, rn, rm) => "smax v\{rd}.16b, v\{rn}.16b, v\{rm}.16b"
    Smax8H(rd, rn, rm) => "smax v\{rd}.8h, v\{rn}.8h, v\{rm}.8h"
    Smax4S(rd, rn, rm) => "smax v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Umax16B(rd, rn, rm) => "umax v\{rd}.16b, v\{rn}.16b, v\{rm}.16b"
    Umax8H(rd, rn, rm) => "umax v\{rd}.8h, v\{rn}.8h, v\{rm}.8h"
    Umax4S(rd, rn, rm) => "umax v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Urhadd16B(rd, rn, rm) => "urhadd v\{rd}.16b, v\{rn}.16b, v\{rm}.16b"
    Urhadd8H(rd, rn, rm) => "urhadd v\{rd}.8h, v\{rn}.8h, v\{rm}.8h"
    Urhadd4S(rd, rn, rm) => "urhadd v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Abs16B(rd, rn) => "abs v\{rd}.16b, v\{rn}.16b"
    Abs8H(rd, rn) => "abs v\{rd}.8h, v\{rn}.8h"
    Abs4S(rd, rn) => "abs v\{rd}.4s, v\{rn}.4s"
    Abs2D(rd, rn) => "abs v\{rd}.2d, v\{rn}.2d"
    Neg16B(rd, rn) => "neg v\{rd}.16b, v\{rn}.16b"
    Neg8H(rd, rn) => "neg v\{rd}.8h, v\{rn}.8h"
    Neg4S(rd, rn) => "neg v\{rd}.4s, v\{rn}.4s"
    Neg2D(rd, rn) => "neg v\{rd}.2d, v\{rn}.2d"
    Cnt16B(rd, rn) => "cnt v\{rd}.16b, v\{rn}.16b"
    Sshl16B(rd, rn, rm) => "sshl v\{rd}.16b, v\{rn}.16b, v\{rm}.16b"
    Sshl8H(rd, rn, rm) => "sshl v\{rd}.8h, v\{rn}.8h, v\{rm}.8h"
    Sshl4S(rd, rn, rm) => "sshl v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Sshl2D(rd, rn, rm) => "sshl v\{rd}.2d, v\{rn}.2d, v\{rm}.2d"
    Ushl16B(rd, rn, rm) => "ushl v\{rd}.16b, v\{rn}.16b, v\{rm}.16b"
    Ushl8H(rd, rn, rm) => "ushl v\{rd}.8h, v\{rn}.8h, v\{rm}.8h"
    Ushl4S(rd, rn, rm) => "ushl v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Ushl2D(rd, rn, rm) => "ushl v\{rd}.2d, v\{rn}.2d, v\{rm}.2d"
    Cmeq16B(rd, rn, rm) => "cmeq v\{rd}.16b, v\{rn}.16b, v\{rm}.16b"
    Cmeq8H(rd, rn, rm) => "cmeq v\{rd}.8h, v\{rn}.8h, v\{rm}.8h"
    Cmeq4S(rd, rn, rm) => "cmeq v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Cmeq2D(rd, rn, rm) => "cmeq v\{rd}.2d, v\{rn}.2d, v\{rm}.2d"
    Cmgt16B(rd, rn, rm) => "cmgt v\{rd}.16b, v\{rn}.16b, v\{rm}.16b"
    Cmgt8H(rd, rn, rm) => "cmgt v\{rd}.8h, v\{rn}.8h, v\{rm}.8h"
    Cmgt4S(rd, rn, rm) => "cmgt v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Cmgt2D(rd, rn, rm) => "cmgt v\{rd}.2d, v\{rn}.2d, v\{rm}.2d"
    Cmge16B(rd, rn, rm) => "cmge v\{rd}.16b, v\{rn}.16b, v\{rm}.16b"
    Cmge8H(rd, rn, rm) => "cmge v\{rd}.8h, v\{rn}.8h, v\{rm}.8h"
    Cmge4S(rd, rn, rm) => "cmge v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Cmge2D(rd, rn, rm) => "cmge v\{rd}.2d, v\{rn}.2d, v\{rm}.2d"
    Cmhi16B(rd, rn, rm) => "cmhi v\{rd}.16b, v\{rn}.16b, v\{rm}.16b"
    Cmhi8H(rd, rn, rm) => "cmhi v\{rd}.8h, v\{rn}.8h, v\{rm}.8h"
    Cmhi4S(rd, rn, rm) => "cmhi v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Cmhi2D(rd, rn, rm) => "cmhi v\{rd}.2d, v\{rn}.2d, v\{rm}.2d"
    Cmhs16B(rd, rn, rm) => "cmhs v\{rd}.16b, v\{rn}.16b, v\{rm}.16b"
    Cmhs8H(rd, rn, rm) => "cmhs v\{rd}.8h, v\{rn}.8h, v\{rm}.8h"
    Cmhs4S(rd, rn, rm) => "cmhs v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Cmhs2D(rd, rn, rm) => "cmhs v\{rd}.2d, v\{rn}.2d, v\{rm}.2d"
    Xtn2S(rd, rn) => "xtn v\{rd}.2s, v\{rn}.2d"
    Sqxtn8B(rd, rn) => "sqxtn v\{rd}.8b, v\{rn}.8h"
    Sqxtn4H(rd, rn) => "sqxtn v\{rd}.4h, v\{rn}.4s"
    Sqxtn2S(rd, rn) => "sqxtn v\{rd}.2s, v\{rn}.2d"
    Sqxtun8B(rd, rn) => "sqxtun v\{rd}.8b, v\{rn}.8h"
    Sqxtun4H(rd, rn) => "sqxtun v\{rd}.4h, v\{rn}.4s"
    Uqxtn2S(rd, rn) => "uqxtn v\{rd}.2s, v\{rn}.2d"
    Sqxtn2_16B(rd, rn) => "sqxtn2 v\{rd}.16b, v\{rn}.8h"
    Sqxtn2_8H(rd, rn) => "sqxtn2 v\{rd}.8h, v\{rn}.4s"
    Sqxtun2_16B(rd, rn) => "sqxtun2 v\{rd}.16b, v\{rn}.8h"
    Sqxtun2_8H(rd, rn) => "sqxtun2 v\{rd}.8h, v\{rn}.4s"
    Sxtl8H(rd, rn) => "sxtl v\{rd}.8h, v\{rn}.8b"
    Sxtl4S(rd, rn) => "sxtl v\{rd}.4s, v\{rn}.4h"
    Sxtl2D(rd, rn) => "sxtl v\{rd}.2d, v\{rn}.2s"
    Sxtl2_8H(rd, rn) => "sxtl2 v\{rd}.8h, v\{rn}.16b"
    Sxtl2_4S(rd, rn) => "sxtl2 v\{rd}.4s, v\{rn}.8h"
    Sxtl2_2D(rd, rn) => "sxtl2 v\{rd}.2d, v\{rn}.4s"
    Uxtl8H(rd, rn) => "uxtl v\{rd}.8h, v\{rn}.8b"
    Uxtl4S(rd, rn) => "uxtl v\{rd}.4s, v\{rn}.4h"
    Uxtl2D(rd, rn) => "uxtl v\{rd}.2d, v\{rn}.2s"
    Uxtl2_8H(rd, rn) => "uxtl2 v\{rd}.8h, v\{rn}.16b"
    Uxtl2_4S(rd, rn) => "uxtl2 v\{rd}.4s, v\{rn}.8h"
    Uxtl2_2D(rd, rn) => "uxtl2 v\{rd}.2d, v\{rn}.4s"
    Smull8H(rd, rn, rm) => "smull v\{rd}.8h, v\{rn}.8b, v\{rm}.8b"
    Smull4S(rd, rn, rm) => "smull v\{rd}.4s, v\{rn}.4h, v\{rm}.4h"
    Smull2D(rd, rn, rm) => "smull v\{rd}.2d, v\{rn}.2s, v\{rm}.2s"
    Umull8H(rd, rn, rm) => "umull v\{rd}.8h, v\{rn}.8b, v\{rm}.8b"
    Umull4S(rd, rn, rm) => "umull v\{rd}.4s, v\{rn}.4h, v\{rm}.4h"
    Umull2D(rd, rn, rm) => "umull v\{rd}.2d, v\{rn}.2s, v\{rm}.2s"
    Smull2_8H(rd, rn, rm) => "smull2 v\{rd}.8h, v\{rn}.16b, v\{rm}.16b"
    Smull2_4S(rd, rn, rm) => "smull2 v\{rd}.4s, v\{rn}.8h, v\{rm}.8h"
    Smull2_2D(rd, rn, rm) => "smull2 v\{rd}.2d, v\{rn}.4s, v\{rm}.4s"
    Umull2_8H(rd, rn, rm) => "umull2 v\{rd}.8h, v\{rn}.16b, v\{rm}.16b"
    Umull2_4S(rd, rn, rm) => "umull2 v\{rd}.4s, v\{rn}.8h, v\{rm}.8h"
    Umull2_2D(rd, rn, rm) => "umull2 v\{rd}.2d, v\{rn}.4s, v\{rm}.4s"
    Saddlp8H(rd, rn) => "saddlp v\{rd}.8h, v\{rn}.16b"
    Saddlp4S(rd, rn) => "saddlp v\{rd}.4s, v\{rn}.8h"
    Uaddlp8H(rd, rn) => "uaddlp v\{rd}.8h, v\{rn}.16b"
    Uaddlp4S(rd, rn) => "uaddlp v\{rd}.4s, v\{rn}.8h"
    Uaddlp2D(rd, rn) => "uaddlp v\{rd}.2d, v\{rn}.4s"
    Addp8H(rd, rn, rm) => "addp v\{rd}.8h, v\{rn}.8h, v\{rm}.8h"
    Addp4S(rd, rn, rm) => "addp v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Sqrdmulh8H(rd, rn, rm) => "sqrdmulh v\{rd}.8h, v\{rn}.8h, v\{rm}.8h"
    Fadd4S(rd, rn, rm) => "fadd v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Fadd2D(rd, rn, rm) => "fadd v\{rd}.2d, v\{rn}.2d, v\{rm}.2d"
    Fsub4S(rd, rn, rm) => "fsub v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Fsub2D(rd, rn, rm) => "fsub v\{rd}.2d, v\{rn}.2d, v\{rm}.2d"
    Fmul4S(rd, rn, rm) => "fmul v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Fmul2D(rd, rn, rm) => "fmul v\{rd}.2d, v\{rn}.2d, v\{rm}.2d"
    Fdiv4S(rd, rn, rm) => "fdiv v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Fdiv2D(rd, rn, rm) => "fdiv v\{rd}.2d, v\{rn}.2d, v\{rm}.2d"
    Fmin4S(rd, rn, rm) => "fmin v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Fmin2D(rd, rn, rm) => "fmin v\{rd}.2d, v\{rn}.2d, v\{rm}.2d"
    Fmax4S(rd, rn, rm) => "fmax v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Fmax2D(rd, rn, rm) => "fmax v\{rd}.2d, v\{rn}.2d, v\{rm}.2d"
    Fmla4S(rd, rn, rm) => "fmla v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Fmla2D(rd, rn, rm) => "fmla v\{rd}.2d, v\{rn}.2d, v\{rm}.2d"
    Fmls4S(rd, rn, rm) => "fmls v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Fmls2D(rd, rn, rm) => "fmls v\{rd}.2d, v\{rn}.2d, v\{rm}.2d"
    Fabs4S(rd, rn) => "fabs v\{rd}.4s, v\{rn}.4s"
    Fabs2D(rd, rn) => "fabs v\{rd}.2d, v\{rn}.2d"
    Fneg4S(rd, rn) => "fneg v\{rd}.4s, v\{rn}.4s"
    Fneg2D(rd, rn) => "fneg v\{rd}.2d, v\{rn}.2d"
    Fsqrt4S(rd, rn) => "fsqrt v\{rd}.4s, v\{rn}.4s"
    Fsqrt2D(rd, rn) => "fsqrt v\{rd}.2d, v\{rn}.2d"
    Frintp4S(rd, rn) => "frintp v\{rd}.4s, v\{rn}.4s"
    Frintp2D(rd, rn) => "frintp v\{rd}.2d, v\{rn}.2d"
    Frintm4S(rd, rn) => "frintm v\{rd}.4s, v\{rn}.4s"
    Frintm2D(rd, rn) => "frintm v\{rd}.2d, v\{rn}.2d"
    Frintz4S(rd, rn) => "frintz v\{rd}.4s, v\{rn}.4s"
    Frintz2D(rd, rn) => "frintz v\{rd}.2d, v\{rn}.2d"
    Frintn4S(rd, rn) => "frintn v\{rd}.4s, v\{rn}.4s"
    Frintn2D(rd, rn) => "frintn v\{rd}.2d, v\{rn}.2d"
    Fcmeq4S(rd, rn, rm) => "fcmeq v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Fcmeq2D(rd, rn, rm) => "fcmeq v\{rd}.2d, v\{rn}.2d, v\{rm}.2d"
    Fcmgt4S(rd, rn, rm) => "fcmgt v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Fcmgt2D(rd, rn, rm) => "fcmgt v\{rd}.2d, v\{rn}.2d, v\{rm}.2d"
    Fcmge4S(rd, rn, rm) => "fcmge v\{rd}.4s, v\{rn}.4s, v\{rm}.4s"
    Fcmge2D(rd, rn, rm) => "fcmge v\{rd}.2d, v\{rn}.2d, v\{rm}.2d"
    Fcvtzs4S(rd, rn) => "fcvtzs v\{rd}.4s, v\{rn}.4s"
    Fcvtzs2D(rd, rn) => "fcvtzs v\{rd}.2d, v\{rn}.2d"
    Fcvtzu4S(rd, rn) => "fcvtzu v\{rd}.4s, v\{rn}.4s"
    Fcvtzu2D(rd, rn) => "fcvtzu v\{rd}.2d, v\{rn}.2d"
    Scvtf4S(rd, rn) => "scvtf v\{rd}.4s, v\{rn}.4s"
    Scvtf2D(rd, rn) => "scvtf v\{rd}.2d, v\{rn}.2d"
    Ucvtf4S(rd, rn) => "ucvtf v\{rd}.4s, v\{rn}.4s"
    Ucvtf2D(rd, rn) => "ucvtf v\{rd}.2d, v\{rn}.2d"
    Fcvtn2S(rd, rn) => "fcvtn v\{rd}.2s, v\{rn}.2d"
    Fcvtl2D(rd, rn) => "fcvtl v\{rd}.2d, v\{rn}.2s"
    Ld1rB(rd, rn) => "ld1r {v\{rd}.16b}, [x\{rn}]"
    Ld1rH(rd, rn) => "ld1r {v\{rd}.8h}, [x\{rn}]"
    Ld1rS(rd, rn) => "ld1r {v\{rd}.4s}, [x\{rn}]"
    Ld1rD(rd, rn) => "ld1r {v\{rd}.2d}, [x\{rn}]"
    Ld1B(rd, rn, lane) => "ld1 {v\{rd}.b}[\{lane}], [x\{rn}]"
    Ld1H(rd, rn, lane) => "ld1 {v\{rd}.h}[\{lane}], [x\{rn}]"
    Ld1S(rd, rn, lane) => "ld1 {v\{rd}.s}[\{lane}], [x\{rn}]"
    Ld1D(rd, rn, lane) => "ld1 {v\{rd}.d}[\{lane}], [x\{rn}]"
    St1B(rt, rn, lane) => "st1 {v\{rt}.b}[\{lane}], [x\{rn}]"
    St1H(rt, rn, lane) => "st1 {v\{rt}.h}[\{lane}], [x\{rn}]"
    St1S(rt, rn, lane) => "st1 {v\{rt}.s}[\{lane}], [x\{rn}]"
    St1D(rt, rn, lane) => "st1 {v\{rt}.d}[\{lane}], [x\{rn}]"
    Umaxv16B(rd, rn) => "umaxv b\{rd}, v\{rn}.16b"
    Uminv16B(rd, rn) => "uminv b\{rd}, v\{rn}.16b"
    Uminv8H(rd, rn) => "uminv h\{rd}, v\{rn}.8h"
    Uminv4S(rd, rn) => "uminv s\{rd}, v\{rn}.4s"
    MoviZero(rd) => "movi v\{rd}.2d, #0"
    OrrVec(rd, rn) => "orr v\{rd}.16b, v\{rn}.16b, v\{rn}.16b"
    Rev64_4S(rd, rn) => "rev64 v\{rd}.4s, v\{rn}.4s"
    ShlImm2D(rd, rn, imm) => "shl v\{rd}.2d, v\{rn}.2d, #\{imm}"
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
    AddExtUxtw(rd, rn, rm, shift) => {
      // ADD (extended register): sf=1 (64-bit), op=0 (add), S=0, option=UXTW (010)
      // Encoding:  sf op S 01011 00 1 Rm option imm3 Rn Rd
      // See ARM ARM "Add/subtract (extended register)".
      let imm3 = shift & 7
      let option_uxtw = 2 // 010 = UXTW
      let inst = (0b1 << 31) |
        (0 << 30) |
        (0 << 29) |
        (0b01011 << 24) |
        (0 << 22) |
        (0b1 << 21) |
        ((rm & 31) << 16) |
        ((option_uxtw & 7) << 13) |
        ((imm3 & 7) << 10) |
        ((rn & 31) << 5) |
        (rd & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
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
    AddImmShifted12(rd, rn, imm12) => {
      // Same as AddImm but with sh=1 (bit 22)
      let imm = imm12 & 0xFFF
      let inst = (0b1 << 31) |
        (0 << 30) |
        (0 << 29) |
        (0b100010 << 23) |
        (1 << 22) | // sh=1: shift imm12 left by 12
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
    SubImmShifted12(rd, rn, imm12) => {
      // Same as SubImm but with sh=1 (bit 22)
      let imm = imm12 & 0xFFF
      let inst = (0b1 << 31) |
        (1 << 30) |
        (0 << 29) |
        (0b100010 << 23) |
        (1 << 22) | // sh=1: shift imm12 left by 12
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
    Umulh(rd, rn, rm) => {
      // UMULH: sf=1, op31=110, Ra=11111
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 0x7C // Ra=31, o0=0
      let b2 = 0xC0 | (rm & 31) // op31=110
      let b3 = 0x9B
      (b0, b1, b2, b3)
    }
    Smulh(rd, rn, rm) => {
      // SMULH: sf=1, op31=010, Ra=11111
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 0x7C // Ra=31, o0=0
      let b2 = 0x40 | (rm & 31) // op31=010
      let b3 = 0x9B
      (b0, b1, b2, b3)
    }
    Umull(rd, rn, rm) => {
      // UMULL = UMADDL with Ra=XZR: sf=1, op31=101, Ra=11111
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 0x7C // Ra=31, o0=0
      let b2 = 0xA0 | (rm & 31) // op31=101
      let b3 = 0x9B
      (b0, b1, b2, b3)
    }
    Smull(rd, rn, rm) => {
      // SMULL = SMADDL with Ra=XZR: sf=1, op31=001, Ra=11111
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | 0x7C // Ra=31, o0=0
      let b2 = 0x20 | (rm & 31) // op31=001
      let b3 = 0x9B
      (b0, b1, b2, b3)
    }
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
    AddReg32(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = (rn >> 3) & 3
      let b2 = rm & 31
      let b3 = 0x0B // ADD 32-bit: sf=0
      (b0, b1, b2, b3)
    }
    AddImm32(rd, rn, imm) => {
      // ADD Wd, Wn, #imm (32-bit)
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((imm & 0x3F) << 2)
      let b2 = (imm >> 6) & 0x3F
      let b3 = 0x11 // ADD imm 32-bit: sf=0
      (b0, b1, b2, b3)
    }
    SubImm32(rd, rn, imm) => {
      // SUB Wd, Wn, #imm (32-bit)
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((imm & 0x3F) << 2)
      let b2 = (imm >> 6) & 0x3F
      let b3 = 0x51 // SUB imm 32-bit: sf=0, op=1
      (b0, b1, b2, b3)
    }
    Mul32(rd, rn, rm) => {
      // MUL Wd, Wn, Wm (32-bit) = MADD Wd, Wn, Wm, WZR
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | (0x1F << 2) // ra = 31 (WZR)
      let b2 = (rm & 31) | (0 << 5)
      let b3 = 0x1B // MADD 32-bit: sf=0
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
      let b3 = 170 // 0xAA for 64-bit ORN
      (b0, b1, b2, b3)
    }
    Mvn32(rd, rm) => {
      let b0 = (rd & 31) | ((31 & 7) << 5)
      let b1 = (31 >> 3) & 3
      let b2 = (rm & 31) | 32
      let b3 = 42 // 0x2A for 32-bit ORN (sf=0)
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
    LsrImm(rd, rn, shift) => {
      // LSR Xd, Xn, #shift = UBFM Xd, Xn, #shift, #63
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = 0xFC | ((rn >> 3) & 3) // imms=63
      let b2 = 0x40 | (shift & 63) // N=1, immr=shift
      let b3 = 0xD3 // sf=1, opc=10, 100110
      (b0, b1, b2, b3)
    }
    LsrImm32(rd, rn, shift) => {
      // LSR Wd, Wn, #shift = UBFM Wd, Wn, #shift, #31
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = 0x7C | ((rn >> 3) & 3) // imms=31
      let b2 = shift & 31 // N=0, immr=shift
      let b3 = 0x53 // sf=0, opc=10, 100110
      (b0, b1, b2, b3)
    }
    UbfxWidth(rd, rn, width) => {
      // UBFX Xd, Xn, #0, #width = UBFM Xd, Xn, #0, #(width-1)
      // Extracts bits [0, width-1] (i.e., mask by (1 << width) - 1)
      let imms = width - 1
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = (imms << 2) | ((rn >> 3) & 3)
      let b2 = 0x40 // N=1, immr=0
      let b3 = 0xD3 // sf=1, opc=10, 100110
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
    Movn(rd, imm16, shift) => {
      let hw = shift / 16
      let imm = imm16 & 0xFFFF
      let b0 = (rd & 31) | ((imm & 7) << 5)
      let b1 = (imm >> 3) & 255
      let b2 = ((imm >> 11) & 31) | ((hw & 3) << 5) | 128
      let x92 = 0x92
      let b3 = x92 | ((hw >> 2) & 1)
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
    LdrWRegScaled(rt, rn, rm, shift) => {
      let s_bit = if shift == 2 { 1 } else { 0 }
      let inst = (0b10 << 30) |
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
    StrWRegScaled(rt, rn, rm, shift) => {
      let s_bit = if shift == 2 { 1 } else { 0 }
      let inst = (0b10 << 30) |
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
    LdrbReg(rt, rn, rm) => {
      let inst = (0b00 << 30) |
        (0b111 << 27) |
        (0 << 26) |
        (0b00 << 24) |
        (0b01 << 22) |
        (1 << 21) |
        ((rm & 31) << 16) |
        (0b011 << 13) |
        (0 << 12) |
        (0b10 << 10) |
        ((rn & 31) << 5) |
        (rt & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    StrbReg(rt, rn, rm) => {
      let inst = (0b00 << 30) |
        (0b111 << 27) |
        (0 << 26) |
        (0b00 << 24) |
        (0b00 << 22) |
        (1 << 21) |
        ((rm & 31) << 16) |
        (0b011 << 13) |
        (0 << 12) |
        (0b10 << 10) |
        ((rn & 31) << 5) |
        (rt & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    LdrhReg(rt, rn, rm) => {
      let inst = (0b01 << 30) |
        (0b111 << 27) |
        (0 << 26) |
        (0b00 << 24) |
        (0b01 << 22) |
        (1 << 21) |
        ((rm & 31) << 16) |
        (0b011 << 13) |
        (0 << 12) |
        (0b10 << 10) |
        ((rn & 31) << 5) |
        (rt & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    StrhReg(rt, rn, rm) => {
      let inst = (0b01 << 30) |
        (0b111 << 27) |
        (0 << 26) |
        (0b00 << 24) |
        (0b00 << 22) |
        (1 << 21) |
        ((rm & 31) << 16) |
        (0b011 << 13) |
        (0 << 12) |
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
    Cbz(rt, _) => (rt & 31, 0, 0, 180) // 0xB4 - 64-bit
    Cbnz(rt, _) => (rt & 31, 0, 0, 181) // 0xB5 - 64-bit
    Cbz32(rt, _) => (rt & 31, 0, 0, 52) // 0x34 - 32-bit
    Cbnz32(rt, _) => (rt & 31, 0, 0, 53) // 0x35 - 32-bit
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
    // ============ NEON SIMD Instructions ============
    LdrQ(rd, rn, imm) => {
      // LDR Qt, [Xn, #imm] (128-bit): 0x3DC00000 | (imm12/16 << 10) | (Rn << 5) | Rd
      let scaled = (imm / 16) & 0xFFF
      let enc = 0x3DC00000 | (scaled << 10) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    StrQ(rt, rn, imm) => {
      // STR Qt, [Xn, #imm] (128-bit): 0x3D800000 | (imm12/16 << 10) | (Rn << 5) | Rt
      let scaled = (imm / 16) & 0xFFF
      let enc = 0x3D800000 | (scaled << 10) | ((rn & 31) << 5) | (rt & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Dup16B(rd, rn) => {
      // DUP Vd.16B, Wn: 0x4E010C00 | (Rn << 5) | Rd
      let enc = 0x4E010C00 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Dup8H(rd, rn) => {
      // DUP Vd.8H, Wn: 0x4E020C00 | (Rn << 5) | Rd
      let enc = 0x4E020C00 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Dup4S(rd, rn) => {
      // DUP Vd.4S, Wn: 0x4E040C00 | (Rn << 5) | Rd
      let enc = 0x4E040C00 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Dup2D(rd, rn) => {
      // DUP Vd.2D, Xn: 0x4E080C00 | (Rn << 5) | Rd
      let enc = 0x4E080C00 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    DupElem4S(rd, rn, lane) => {
      // DUP Vd.4S, Vn.S[lane]: 0x4E040400 | (lane << 19) | (Rn << 5) | Rd
      let enc = 0x4E040400 | ((lane & 3) << 19) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    DupElem2D(rd, rn, lane) => {
      // DUP Vd.2D, Vn.D[lane]: 0x4E080400 | (lane << 20) | (Rn << 5) | Rd
      let enc = 0x4E080400 | ((lane & 1) << 20) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    UmovB(rd, rn, lane) => {
      // UMOV Wd, Vn.B[lane]: 0x0E013C00 | (lane << 17) | (Rn << 5) | Rd
      let enc = 0x0E013C00 | ((lane & 15) << 17) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    UmovH(rd, rn, lane) => {
      // UMOV Wd, Vn.H[lane]: 0x0E023C00 | (lane << 18) | (Rn << 5) | Rd
      let enc = 0x0E023C00 | ((lane & 7) << 18) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    UmovS(rd, rn, lane) => {
      // UMOV Wd, Vn.S[lane]: 0x0E043C00 | (lane << 19) | (Rn << 5) | Rd
      let enc = 0x0E043C00 | ((lane & 3) << 19) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    UmovD(rd, rn, lane) => {
      // UMOV Xd, Vn.D[lane]: 0x4E083C00 | (lane << 20) | (Rn << 5) | Rd
      let enc = 0x4E083C00 | ((lane & 1) << 20) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    SmovB(rd, rn, lane) => {
      // SMOV Wd, Vn.B[lane]: 0x0E012C00 | (lane << 17) | (Rn << 5) | Rd
      let enc = 0x0E012C00 | ((lane & 15) << 17) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    SmovH(rd, rn, lane) => {
      // SMOV Wd, Vn.H[lane]: 0x0E022C00 | (lane << 18) | (Rn << 5) | Rd
      let enc = 0x0E022C00 | ((lane & 7) << 18) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    SmovS(rd, rn, lane) => {
      // SMOV Xd, Vn.S[lane]: 0x4E042C00 | (lane << 19) | (Rn << 5) | Rd
      let enc = 0x4E042C00 | ((lane & 3) << 19) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    DupScalarS(rd, rn, lane) => {
      // DUP Sd, Vn.S[lane]: 0x5E040400 | (lane << 19) | (Rn << 5) | Rd
      let enc = 0x5E040400 | ((lane & 3) << 19) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    DupScalarD(rd, rn, lane) => {
      // DUP Dd, Vn.D[lane]: 0x5E080400 | (lane << 20) | (Rn << 5) | Rd
      let enc = 0x5E080400 | ((lane & 1) << 20) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    InsB(rd, lane, rn) => {
      // INS Vd.B[lane], Wn: 0x4E001C00 | (imm5 << 16) | (Rn << 5) | Rd
      // imm5[0] = 1 (B size), imm5[4:1] = lane index (0-15)
      let imm5 = (lane << 1) | 1
      let enc = 0x4E001C00 | (imm5 << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    InsH(rd, lane, rn) => {
      // INS Vd.H[lane], Wn: 0x4E001C00 | (imm5 << 16) | (Rn << 5) | Rd
      // imm5[1:0] = 10 (H size), imm5[4:2] = lane index (0-7)
      let imm5 = (lane << 2) | 2
      let enc = 0x4E001C00 | (imm5 << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    InsS(rd, lane, rn) => {
      // INS Vd.S[lane], Wn: 0x4E001C00 | (imm5 << 16) | (Rn << 5) | Rd
      // imm5[2:0] = 100 (S size), imm5[4:3] = lane index (0-3)
      let imm5 = (lane << 3) | 4
      let enc = 0x4E001C00 | (imm5 << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    InsD(rd, lane, rn) => {
      // INS Vd.D[lane], Xn: 0x4E001C00 | (imm5 << 16) | (Rn << 5) | Rd
      // imm5[3:0] = 1000 (D size), imm5[4] = lane index
      let imm5 = (lane << 4) | 8
      let enc = 0x4E001C00 | (imm5 << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    InsElemS(rd, dlane, rn, slane) => {
      // INS Vd.S[dlane], Vn.S[slane]: 0x6E000400 | (dlane << 19) | (slane << 13) | (Rn << 5) | Rd
      let imm5 = (dlane << 3) | 4
      let imm4 = slane << 2
      let enc = 0x6E000400 |
        (imm5 << 16) |
        (imm4 << 11) |
        ((rn & 31) << 5) |
        (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    InsElemD(rd, dlane, rn, slane) => {
      // INS Vd.D[dlane], Vn.D[slane]: 0x6E000400 | (dlane << 20) | (slane << 14) | (Rn << 5) | Rd
      let imm5 = (dlane << 4) | 8
      let imm4 = slane << 3
      let enc = 0x6E000400 |
        (imm5 << 16) |
        (imm4 << 11) |
        ((rn & 31) << 5) |
        (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Not16B(rd, rn) => {
      // NOT Vd.16B, Vn.16B: 0x6E205800 | (Rn << 5) | Rd
      let enc = 0x6E205800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    And16B(rd, rn, rm) => {
      // AND Vd.16B, Vn.16B, Vm.16B: 0x4E201C00 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4E201C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Orr16B(rd, rn, rm) => {
      // ORR Vd.16B, Vn.16B, Vm.16B: 0x4EA01C00 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4EA01C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Eor16B(rd, rn, rm) => {
      // EOR Vd.16B, Vn.16B, Vm.16B: 0x6E201C00 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x6E201C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Bic16B(rd, rn, rm) => {
      // BIC Vd.16B, Vn.16B, Vm.16B: 0x4E601C00 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4E601C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Bsl16B(rd, rn, rm) => {
      // BSL Vd.16B, Vn.16B, Vm.16B: 0x6E601C00 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x6E601C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Tbl1(rd, rn, rm) => {
      // TBL Vd.16B, {Vn.16B}, Vm.16B: 0x4E000000 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4E000000 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Add16B(rd, rn, rm) => {
      // ADD Vd.16B, Vn.16B, Vm.16B: 0x4E208400 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4E208400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sub16B(rd, rn, rm) => {
      // SUB Vd.16B, Vn.16B, Vm.16B: 0x6E208400 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x6E208400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Add8H(rd, rn, rm) => {
      // ADD Vd.8H, Vn.8H, Vm.8H: 0x4E608400 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4E608400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sub8H(rd, rn, rm) => {
      // SUB Vd.8H, Vn.8H, Vm.8H: 0x6E608400 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x6E608400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Mul8H(rd, rn, rm) => {
      // MUL Vd.8H, Vn.8H, Vm.8H: 0x4E609C00 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4E609C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Add4S(rd, rn, rm) => {
      // ADD Vd.4S, Vn.4S, Vm.4S: 0x4EA08400 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4EA08400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sub4S(rd, rn, rm) => {
      // SUB Vd.4S, Vn.4S, Vm.4S: 0x6EA08400 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x6EA08400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Mul4S(rd, rn, rm) => {
      // MUL Vd.4S, Vn.4S, Vm.4S: 0x4EA09C00 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4EA09C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Add2D(rd, rn, rm) => {
      // ADD Vd.2D, Vn.2D, Vm.2D: 0x4EE08400 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4EE08400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sub2D(rd, rn, rm) => {
      // SUB Vd.2D, Vn.2D, Vm.2D: 0x6EE08400 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x6EE08400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sqadd16B(rd, rn, rm) => {
      // SQADD Vd.16B, Vn.16B, Vm.16B: 0x4E200C00 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4E200C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sqadd8H(rd, rn, rm) => {
      let enc = 0x4E600C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sqadd4S(rd, rn, rm) => {
      let enc = 0x4EA00C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sqadd2D(rd, rn, rm) => {
      let enc = 0x4EE00C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Uqadd16B(rd, rn, rm) => {
      // UQADD Vd.16B, Vn.16B, Vm.16B: 0x6E200C00 | ...
      let enc = 0x6E200C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Uqadd8H(rd, rn, rm) => {
      let enc = 0x6E600C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Uqadd4S(rd, rn, rm) => {
      let enc = 0x6EA00C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Uqadd2D(rd, rn, rm) => {
      let enc = 0x6EE00C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sqsub16B(rd, rn, rm) => {
      let enc = 0x4E202C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sqsub8H(rd, rn, rm) => {
      let enc = 0x4E602C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sqsub4S(rd, rn, rm) => {
      let enc = 0x4EA02C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sqsub2D(rd, rn, rm) => {
      let enc = 0x4EE02C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Uqsub16B(rd, rn, rm) => {
      let enc = 0x6E202C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Uqsub8H(rd, rn, rm) => {
      let enc = 0x6E602C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Uqsub4S(rd, rn, rm) => {
      let enc = 0x6EA02C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Uqsub2D(rd, rn, rm) => {
      let enc = 0x6EE02C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Smin16B(rd, rn, rm) => {
      let enc = 0x4E206C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Smin8H(rd, rn, rm) => {
      let enc = 0x4E606C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Smin4S(rd, rn, rm) => {
      let enc = 0x4EA06C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Umin16B(rd, rn, rm) => {
      let enc = 0x6E206C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Umin8H(rd, rn, rm) => {
      let enc = 0x6E606C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Umin4S(rd, rn, rm) => {
      let enc = 0x6EA06C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Smax16B(rd, rn, rm) => {
      let enc = 0x4E206400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Smax8H(rd, rn, rm) => {
      let enc = 0x4E606400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Smax4S(rd, rn, rm) => {
      let enc = 0x4EA06400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Umax16B(rd, rn, rm) => {
      let enc = 0x6E206400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Umax8H(rd, rn, rm) => {
      let enc = 0x6E606400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Umax4S(rd, rn, rm) => {
      let enc = 0x6EA06400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Urhadd16B(rd, rn, rm) => {
      let enc = 0x6E201400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Urhadd8H(rd, rn, rm) => {
      let enc = 0x6E601400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Urhadd4S(rd, rn, rm) => {
      let enc = 0x6EA01400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Abs16B(rd, rn) => {
      let enc = 0x4E20B800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Abs8H(rd, rn) => {
      let enc = 0x4E60B800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Abs4S(rd, rn) => {
      let enc = 0x4EA0B800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Abs2D(rd, rn) => {
      let enc = 0x4EE0B800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Neg16B(rd, rn) => {
      let enc = 0x6E20B800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Neg8H(rd, rn) => {
      let enc = 0x6E60B800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Neg4S(rd, rn) => {
      let enc = 0x6EA0B800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Neg2D(rd, rn) => {
      let enc = 0x6EE0B800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Cnt16B(rd, rn) => {
      let enc = 0x4E205800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sshl16B(rd, rn, rm) => {
      let enc = 0x4E204400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sshl8H(rd, rn, rm) => {
      let enc = 0x4E604400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sshl4S(rd, rn, rm) => {
      let enc = 0x4EA04400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sshl2D(rd, rn, rm) => {
      let enc = 0x4EE04400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Ushl16B(rd, rn, rm) => {
      let enc = 0x6E204400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Ushl8H(rd, rn, rm) => {
      let enc = 0x6E604400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Ushl4S(rd, rn, rm) => {
      let enc = 0x6EA04400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Ushl2D(rd, rn, rm) => {
      let enc = 0x6EE04400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Cmeq16B(rd, rn, rm) => {
      let enc = 0x6E208C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Cmeq8H(rd, rn, rm) => {
      let enc = 0x6E608C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Cmeq4S(rd, rn, rm) => {
      let enc = 0x6EA08C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Cmeq2D(rd, rn, rm) => {
      let enc = 0x6EE08C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Cmgt16B(rd, rn, rm) => {
      let enc = 0x4E203400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Cmgt8H(rd, rn, rm) => {
      let enc = 0x4E603400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Cmgt4S(rd, rn, rm) => {
      let enc = 0x4EA03400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Cmgt2D(rd, rn, rm) => {
      let enc = 0x4EE03400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Cmge16B(rd, rn, rm) => {
      let enc = 0x4E203C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Cmge8H(rd, rn, rm) => {
      let enc = 0x4E603C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Cmge4S(rd, rn, rm) => {
      let enc = 0x4EA03C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Cmge2D(rd, rn, rm) => {
      let enc = 0x4EE03C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Cmhi16B(rd, rn, rm) => {
      let enc = 0x6E203400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Cmhi8H(rd, rn, rm) => {
      let enc = 0x6E603400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Cmhi4S(rd, rn, rm) => {
      let enc = 0x6EA03400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Cmhi2D(rd, rn, rm) => {
      let enc = 0x6EE03400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Cmhs16B(rd, rn, rm) => {
      let enc = 0x6E203C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Cmhs8H(rd, rn, rm) => {
      let enc = 0x6E603C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Cmhs4S(rd, rn, rm) => {
      let enc = 0x6EA03C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Cmhs2D(rd, rn, rm) => {
      let enc = 0x6EE03C00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    OrrVec(rd, rn) => {
      // ORR Vd.16B, Vn.16B, Vn.16B (vector move): same as Orr16B with rm=rn
      let enc = 0x4EA01C00 | ((rn & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    MoviZero(rd) => {
      // MOVI Vd.2D, #0: 0x6F00E400 | Rd
      // This zeroes the entire 128-bit vector register
      let enc = 0x6F00E400 | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Umaxv16B(rd, rn) => {
      // UMAXV Bd, Vn.16B: 0x6E30A800 | (Rn << 5) | Rd
      let enc = 0x6E30A800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Uminv16B(rd, rn) => {
      // UMINV Bd, Vn.16B: 0x6E31A800 | (Rn << 5) | Rd
      let enc = 0x6E31A800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Uminv8H(rd, rn) => {
      // UMINV Hd, Vn.8H: 0x6E71A800 | (Rn << 5) | Rd
      // Note: U bit (bit 29) must be 1 for unsigned; 0x4E would be SMINV
      let enc = 0x6E71A800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Uminv4S(rd, rn) => {
      // UMINV Sd, Vn.4S: 0x6EB1A800 | (Rn << 5) | Rd
      let enc = 0x6EB1A800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Uaddlp8H(rd, rn) => {
      // UADDLP Vd.8H, Vn.16B: 0x6E202800 | (Rn << 5) | Rd
      let enc = 0x6E202800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Uaddlp4S(rd, rn) => {
      // UADDLP Vd.4S, Vn.8H: 0x6E602800 | (Rn << 5) | Rd
      let enc = 0x6E602800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Uaddlp2D(rd, rn) => {
      // UADDLP Vd.2D, Vn.4S: 0x6EA02800 | (Rn << 5) | Rd
      let enc = 0x6EA02800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    // Signed pairwise add long
    Saddlp8H(rd, rn) => {
      // SADDLP Vd.8H, Vn.16B: 0x4E202800 | (Rn << 5) | Rd
      let enc = 0x4E202800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Saddlp4S(rd, rn) => {
      // SADDLP Vd.4S, Vn.8H: 0x4E602800 | (Rn << 5) | Rd
      let enc = 0x4E602800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    // Pairwise add (for dot product)
    Addp4S(rd, rn, rm) => {
      // ADDP Vd.4S, Vn.4S, Vm.4S: 0x4EA0BC00 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4EA0BC00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Addp8H(rd, rn, rm) => {
      // ADDP Vd.8H, Vn.8H, Vm.8H: 0x4E60BC00 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4E60BC00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    // Q15 saturating rounding multiply high
    Sqrdmulh8H(rd, rn, rm) => {
      // SQRDMULH Vd.8H, Vn.8H, Vm.8H: 0x6E60B400 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x6E60B400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    // Float SIMD arithmetic
    Fadd4S(rd, rn, rm) => {
      // FADD Vd.4S, Vn.4S, Vm.4S: 0x4E20D400 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4E20D400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fadd2D(rd, rn, rm) => {
      // FADD Vd.2D, Vn.2D, Vm.2D: 0x4E60D400 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4E60D400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fsub4S(rd, rn, rm) => {
      // FSUB Vd.4S, Vn.4S, Vm.4S: 0x4EA0D400 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4EA0D400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fsub2D(rd, rn, rm) => {
      // FSUB Vd.2D, Vn.2D, Vm.2D: 0x4EE0D400 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4EE0D400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fmul4S(rd, rn, rm) => {
      // FMUL Vd.4S, Vn.4S, Vm.4S: 0x6E20DC00 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x6E20DC00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fmul2D(rd, rn, rm) => {
      // FMUL Vd.2D, Vn.2D, Vm.2D: 0x6E60DC00 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x6E60DC00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fdiv4S(rd, rn, rm) => {
      // FDIV Vd.4S, Vn.4S, Vm.4S: 0x6E20FC00 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x6E20FC00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fdiv2D(rd, rn, rm) => {
      // FDIV Vd.2D, Vn.2D, Vm.2D: 0x6E60FC00 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x6E60FC00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fmin4S(rd, rn, rm) => {
      // FMIN Vd.4S, Vn.4S, Vm.4S: 0x4EA0F400 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4EA0F400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fmin2D(rd, rn, rm) => {
      // FMIN Vd.2D, Vn.2D, Vm.2D: 0x4EE0F400 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4EE0F400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fmax4S(rd, rn, rm) => {
      // FMAX Vd.4S, Vn.4S, Vm.4S: 0x4E20F400 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4E20F400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fmax2D(rd, rn, rm) => {
      // FMAX Vd.2D, Vn.2D, Vm.2D: 0x4E60F400 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4E60F400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fmla4S(rd, rn, rm) => {
      // FMLA Vd.4S, Vn.4S, Vm.4S: 0x4E20CC00 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4E20CC00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fmla2D(rd, rn, rm) => {
      // FMLA Vd.2D, Vn.2D, Vm.2D: 0x4E60CC00 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4E60CC00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fmls4S(rd, rn, rm) => {
      // FMLS Vd.4S, Vn.4S, Vm.4S: 0x4EA0CC00 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4EA0CC00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fmls2D(rd, rn, rm) => {
      // FMLS Vd.2D, Vn.2D, Vm.2D: 0x4EE0CC00 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4EE0CC00 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fabs4S(rd, rn) => {
      // FABS Vd.4S, Vn.4S: 0x4EA0F800 | (Rn << 5) | Rd
      let enc = 0x4EA0F800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fabs2D(rd, rn) => {
      // FABS Vd.2D, Vn.2D: 0x4EE0F800 | (Rn << 5) | Rd
      let enc = 0x4EE0F800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fneg4S(rd, rn) => {
      // FNEG Vd.4S, Vn.4S: 0x6EA0F800 | (Rn << 5) | Rd
      let enc = 0x6EA0F800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fneg2D(rd, rn) => {
      // FNEG Vd.2D, Vn.2D: 0x6EE0F800 | (Rn << 5) | Rd
      let enc = 0x6EE0F800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fsqrt4S(rd, rn) => {
      // FSQRT Vd.4S, Vn.4S: 0x6EA1F800 | (Rn << 5) | Rd
      let enc = 0x6EA1F800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fsqrt2D(rd, rn) => {
      // FSQRT Vd.2D, Vn.2D: 0x6EE1F800 | (Rn << 5) | Rd
      let enc = 0x6EE1F800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    // Float comparisons
    Fcmeq4S(rd, rn, rm) => {
      // FCMEQ Vd.4S, Vn.4S, Vm.4S: 0x4E20E400 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4E20E400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fcmeq2D(rd, rn, rm) => {
      // FCMEQ Vd.2D, Vn.2D, Vm.2D: 0x4E60E400 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4E60E400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fcmgt4S(rd, rn, rm) => {
      // FCMGT Vd.4S, Vn.4S, Vm.4S: 0x6EA0E400 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x6EA0E400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fcmgt2D(rd, rn, rm) => {
      // FCMGT Vd.2D, Vn.2D, Vm.2D: 0x6EE0E400 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x6EE0E400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fcmge4S(rd, rn, rm) => {
      // FCMGE Vd.4S, Vn.4S, Vm.4S: 0x6E20E400 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x6E20E400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fcmge2D(rd, rn, rm) => {
      // FCMGE Vd.2D, Vn.2D, Vm.2D: 0x6E60E400 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x6E60E400 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    // Float rounding
    Frintp4S(rd, rn) => {
      // FRINTP Vd.4S, Vn.4S (ceil): 0x4EA18800 | (Rn << 5) | Rd
      let enc = 0x4EA18800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Frintp2D(rd, rn) => {
      // FRINTP Vd.2D, Vn.2D (ceil): 0x4EE18800 | (Rn << 5) | Rd
      let enc = 0x4EE18800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Frintm4S(rd, rn) => {
      // FRINTM Vd.4S, Vn.4S (floor): 0x4E219800 | (Rn << 5) | Rd
      let enc = 0x4E219800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Frintm2D(rd, rn) => {
      // FRINTM Vd.2D, Vn.2D (floor): 0x4E619800 | (Rn << 5) | Rd
      let enc = 0x4E619800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Frintz4S(rd, rn) => {
      // FRINTZ Vd.4S, Vn.4S (trunc): 0x4EA19800 | (Rn << 5) | Rd
      let enc = 0x4EA19800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Frintz2D(rd, rn) => {
      // FRINTZ Vd.2D, Vn.2D (trunc): 0x4EE19800 | (Rn << 5) | Rd
      let enc = 0x4EE19800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Frintn4S(rd, rn) => {
      // FRINTN Vd.4S, Vn.4S (nearest): 0x4E218800 | (Rn << 5) | Rd
      let enc = 0x4E218800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Frintn2D(rd, rn) => {
      // FRINTN Vd.2D, Vn.2D (nearest): 0x4E618800 | (Rn << 5) | Rd
      let enc = 0x4E618800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Rev64_4S(rd, rn) => {
      // REV64 Vd.4S, Vn.4S: 0x4EA00800 | (Rn << 5) | Rd
      // Swaps 32-bit halves within each 64-bit lane
      let enc = 0x4EA00800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    ShlImm2D(rd, rn, imm) => {
      // SHL Vd.2D, Vn.2D, #imm: 0x4F405400 | ((imm+64) << 16) | (Rn << 5) | Rd
      // For .2D, shift amount encoding is (imm + 64)
      let shift_enc = (imm + 64) & 127
      let enc = 0x4F005400 | (shift_enc << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Xtn2S(rd, rn) => {
      // XTN Vd.2S, Vn.2D: 0x0EA12800 | (Rn << 5) | Rd
      // Narrows 64-bit elements to 32-bit, extracting lower halves
      let enc = 0x0EA12800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Umull2D(rd, rn, rm) => {
      // UMULL Vd.2D, Vn.2S, Vm.2S: 0x2EA0C000 | (Rm << 16) | (Rn << 5) | Rd
      // Multiplies 32-bit elements, producing 64-bit results
      let enc = 0x2EA0C000 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    // Integer to float conversions
    Scvtf4S(rd, rn) => {
      // SCVTF Vd.4S, Vn.4S (signed i32 -> f32): 0x4E21D800 | (Rn << 5) | Rd
      let enc = 0x4E21D800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Scvtf2D(rd, rn) => {
      // SCVTF Vd.2D, Vn.2D (signed i64 -> f64): 0x4E61D800 | (Rn << 5) | Rd
      let enc = 0x4E61D800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Ucvtf4S(rd, rn) => {
      // UCVTF Vd.4S, Vn.4S (unsigned i32 -> f32): 0x6E21D800 | (Rn << 5) | Rd
      let enc = 0x6E21D800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Ucvtf2D(rd, rn) => {
      // UCVTF Vd.2D, Vn.2D (unsigned i64 -> f64): 0x6E61D800 | (Rn << 5) | Rd
      let enc = 0x6E61D800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    // Float to integer conversions (truncating toward zero, saturating)
    Fcvtzs4S(rd, rn) => {
      // FCVTZS Vd.4S, Vn.4S (f32 -> signed i32): 0x4EA1B800 | (Rn << 5) | Rd
      let enc = 0x4EA1B800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fcvtzs2D(rd, rn) => {
      // FCVTZS Vd.2D, Vn.2D (f64 -> signed i64): 0x4EE1B800 | (Rn << 5) | Rd
      let enc = 0x4EE1B800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fcvtzu4S(rd, rn) => {
      // FCVTZU Vd.4S, Vn.4S (f32 -> unsigned i32): 0x6EA1B800 | (Rn << 5) | Rd
      let enc = 0x6EA1B800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fcvtzu2D(rd, rn) => {
      // FCVTZU Vd.2D, Vn.2D (f64 -> unsigned i64): 0x6EE1B800 | (Rn << 5) | Rd
      let enc = 0x6EE1B800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    // Sign/zero extend i32x2 to i64x2 (for low lane conversions)
    Sxtl2D(rd, rn) => {
      // SXTL Vd.2D, Vn.2S (aka SSHLL #0): 0x0F20A400 | (Rn << 5) | Rd
      let enc = 0x0F20A400 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Uxtl2D(rd, rn) => {
      // UXTL Vd.2D, Vn.2S (aka USHLL #0): 0x2F20A400 | (Rn << 5) | Rd
      let enc = 0x2F20A400 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    // Additional extend operations (for all sizes)
    Sxtl8H(rd, rn) => {
      // SXTL Vd.8H, Vn.8B (aka SSHLL #0): 0x0F08A400 | (Rn << 5) | Rd
      let enc = 0x0F08A400 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sxtl4S(rd, rn) => {
      // SXTL Vd.4S, Vn.4H (aka SSHLL #0): 0x0F10A400 | (Rn << 5) | Rd
      let enc = 0x0F10A400 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Uxtl8H(rd, rn) => {
      // UXTL Vd.8H, Vn.8B (aka USHLL #0): 0x2F08A400 | (Rn << 5) | Rd
      let enc = 0x2F08A400 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Uxtl4S(rd, rn) => {
      // UXTL Vd.4S, Vn.4H (aka USHLL #0): 0x2F10A400 | (Rn << 5) | Rd
      let enc = 0x2F10A400 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    // Extend high (SXTL2/UXTL2 - takes upper half of input)
    Sxtl2_8H(rd, rn) => {
      // SXTL2 Vd.8H, Vn.16B (aka SSHLL2 #0): 0x4F08A400 | (Rn << 5) | Rd
      let enc = 0x4F08A400 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sxtl2_4S(rd, rn) => {
      // SXTL2 Vd.4S, Vn.8H (aka SSHLL2 #0): 0x4F10A400 | (Rn << 5) | Rd
      let enc = 0x4F10A400 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sxtl2_2D(rd, rn) => {
      // SXTL2 Vd.2D, Vn.4S (aka SSHLL2 #0): 0x4F20A400 | (Rn << 5) | Rd
      let enc = 0x4F20A400 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Uxtl2_8H(rd, rn) => {
      // UXTL2 Vd.8H, Vn.16B (aka USHLL2 #0): 0x6F08A400 | (Rn << 5) | Rd
      let enc = 0x6F08A400 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Uxtl2_4S(rd, rn) => {
      // UXTL2 Vd.4S, Vn.8H (aka USHLL2 #0): 0x6F10A400 | (Rn << 5) | Rd
      let enc = 0x6F10A400 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Uxtl2_2D(rd, rn) => {
      // UXTL2 Vd.2D, Vn.4S (aka USHLL2 #0): 0x6F20A400 | (Rn << 5) | Rd
      let enc = 0x6F20A400 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    // Float precision conversions
    Fcvtn2S(rd, rn) => {
      // FCVTN Vd.2S, Vn.2D (demote f64x2 to f32x2): 0x0E616800 | (Rn << 5) | Rd
      let enc = 0x0E616800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Fcvtl2D(rd, rn) => {
      // FCVTL Vd.2D, Vn.2S (promote f32x2 to f64x2): 0x0E617800 | (Rn << 5) | Rd
      let enc = 0x0E617800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    // Saturating narrow (lower half)
    // Note: 0x2800 is XTN (non-saturating), 0x4800 is SQXTN (saturating)
    Sqxtn8B(rd, rn) => {
      // SQXTN Vd.8B, Vn.8H: 0x0E214800 | (Rn << 5) | Rd
      let enc = 0x0E214800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sqxtn4H(rd, rn) => {
      // SQXTN Vd.4H, Vn.4S: 0x0E614800 | (Rn << 5) | Rd
      let enc = 0x0E614800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sqxtn2S(rd, rn) => {
      // SQXTN Vd.2S, Vn.2D: 0x0EA14800 | (Rn << 5) | Rd
      // Note: 0x2800 is XTN (non-saturating), 0x4800 is SQXTN (saturating)
      let enc = 0x0EA14800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sqxtun8B(rd, rn) => {
      // SQXTUN Vd.8B, Vn.8H: 0x2E212800 | (Rn << 5) | Rd
      let enc = 0x2E212800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sqxtun4H(rd, rn) => {
      // SQXTUN Vd.4H, Vn.4S: 0x2E612800 | (Rn << 5) | Rd
      let enc = 0x2E612800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Uqxtn2S(rd, rn) => {
      // UQXTN Vd.2S, Vn.2D: 0x2EA14800 | (Rn << 5) | Rd
      let enc = 0x2EA14800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    // Saturating narrow (upper half - writes to upper portion)
    // Note: 0x2800 is XTN2 (non-saturating), 0x4800 is SQXTN2 (saturating)
    Sqxtn2_16B(rd, rn) => {
      // SQXTN2 Vd.16B, Vn.8H: 0x4E214800 | (Rn << 5) | Rd
      let enc = 0x4E214800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sqxtn2_8H(rd, rn) => {
      // SQXTN2 Vd.8H, Vn.4S: 0x4E614800 | (Rn << 5) | Rd
      let enc = 0x4E614800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sqxtun2_16B(rd, rn) => {
      // SQXTUN2 Vd.16B, Vn.8H: 0x6E212800 | (Rn << 5) | Rd
      let enc = 0x6E212800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Sqxtun2_8H(rd, rn) => {
      // SQXTUN2 Vd.8H, Vn.4S: 0x6E612800 | (Rn << 5) | Rd
      let enc = 0x6E612800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    // Extended multiply (SMULL/UMULL - low half, SMULL2/UMULL2 - high half)
    Smull8H(rd, rn, rm) => {
      // SMULL Vd.8H, Vn.8B, Vm.8B: 0x0E20C000 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x0E20C000 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Smull4S(rd, rn, rm) => {
      // SMULL Vd.4S, Vn.4H, Vm.4H: 0x0E60C000 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x0E60C000 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Smull2D(rd, rn, rm) => {
      // SMULL Vd.2D, Vn.2S, Vm.2S: 0x0EA0C000 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x0EA0C000 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Umull8H(rd, rn, rm) => {
      // UMULL Vd.8H, Vn.8B, Vm.8B: 0x2E20C000 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x2E20C000 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Umull4S(rd, rn, rm) => {
      // UMULL Vd.4S, Vn.4H, Vm.4H: 0x2E60C000 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x2E60C000 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    // Note: Umull2D already defined above for i64x2.mul emulation
    Smull2_8H(rd, rn, rm) => {
      // SMULL2 Vd.8H, Vn.16B, Vm.16B: 0x4E20C000 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4E20C000 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Smull2_4S(rd, rn, rm) => {
      // SMULL2 Vd.4S, Vn.8H, Vm.8H: 0x4E60C000 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4E60C000 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Smull2_2D(rd, rn, rm) => {
      // SMULL2 Vd.2D, Vn.4S, Vm.4S: 0x4EA0C000 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x4EA0C000 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Umull2_8H(rd, rn, rm) => {
      // UMULL2 Vd.8H, Vn.16B, Vm.16B: 0x6E20C000 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x6E20C000 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Umull2_4S(rd, rn, rm) => {
      // UMULL2 Vd.4S, Vn.8H, Vm.8H: 0x6E60C000 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x6E60C000 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Umull2_2D(rd, rn, rm) => {
      // UMULL2 Vd.2D, Vn.4S, Vm.4S: 0x6EA0C000 | (Rm << 16) | (Rn << 5) | Rd
      let enc = 0x6EA0C000 | ((rm & 31) << 16) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    // Load and replicate (LD1R)
    Ld1rB(rd, rn) => {
      // LD1R {Vd.16B}, [Xn]: 0x4D40C000 | (Rn << 5) | Rd
      let enc = 0x4D40C000 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Ld1rH(rd, rn) => {
      // LD1R {Vd.8H}, [Xn]: 0x4D40C400 | (Rn << 5) | Rd
      let enc = 0x4D40C400 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Ld1rS(rd, rn) => {
      // LD1R {Vd.4S}, [Xn]: 0x4D40C800 | (Rn << 5) | Rd
      let enc = 0x4D40C800 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Ld1rD(rd, rn) => {
      // LD1R {Vd.2D}, [Xn]: 0x4D40CC00 | (Rn << 5) | Rd
      let enc = 0x4D40CC00 | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    // Load single element to lane (LD1)
    Ld1B(rd, rn, lane) => {
      // LD1 {Vd.B}[lane], [Xn]: 0x0D400000 | (Q << 30) | (lane_hi << 11) | (lane_lo << 10) | (Rn << 5) | Rd
      // For .B lanes 0-15: Q=lane[3], lane encoding in bits [12:10, 30]
      let q = (lane >> 3) & 1
      let s = (lane >> 2) & 1
      let size = lane & 3
      let enc = 0x0D400000 |
        (q << 30) |
        (s << 12) |
        (size << 10) |
        ((rn & 31) << 5) |
        (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Ld1H(rd, rn, lane) => {
      // LD1 {Vd.H}[lane], [Xn]: lanes 0-7
      let q = (lane >> 2) & 1
      let s = (lane >> 1) & 1
      let size = (lane & 1) << 1
      let enc = 0x0D404000 |
        (q << 30) |
        (s << 12) |
        (size << 10) |
        ((rn & 31) << 5) |
        (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Ld1S(rd, rn, lane) => {
      // LD1 {Vd.S}[lane], [Xn]: lanes 0-3
      let q = (lane >> 1) & 1
      let s = lane & 1
      let enc = 0x0D408000 |
        (q << 30) |
        (s << 12) |
        ((rn & 31) << 5) |
        (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    Ld1D(rd, rn, lane) => {
      // LD1 {Vd.D}[lane], [Xn]: lanes 0-1
      let q = lane & 1
      let enc = 0x0D408400 | (q << 30) | ((rn & 31) << 5) | (rd & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    // Store single element from lane (ST1)
    St1B(rn, rd, lane) => {
      // ST1 {Vn.B}[lane], [Xd]: Same encoding as LD1 but with L=0 instead of L=1
      let q = (lane >> 3) & 1
      let s = (lane >> 2) & 1
      let size = lane & 3
      let enc = 0x0D000000 |
        (q << 30) |
        (s << 12) |
        (size << 10) |
        ((rd & 31) << 5) |
        (rn & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    St1H(rn, rd, lane) => {
      // ST1 {Vn.H}[lane], [Xd]: lanes 0-7
      let q = (lane >> 2) & 1
      let s = (lane >> 1) & 1
      let size = (lane & 1) << 1
      let enc = 0x0D004000 |
        (q << 30) |
        (s << 12) |
        (size << 10) |
        ((rd & 31) << 5) |
        (rn & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    St1S(rn, rd, lane) => {
      // ST1 {Vn.S}[lane], [Xd]: lanes 0-3
      let q = (lane >> 1) & 1
      let s = lane & 1
      let enc = 0x0D008000 |
        (q << 30) |
        (s << 12) |
        ((rd & 31) << 5) |
        (rn & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
    St1D(rn, rd, lane) => {
      // ST1 {Vn.D}[lane], [Xd]: lanes 0-1
      let q = lane & 1
      let enc = 0x0D008400 | (q << 30) | ((rd & 31) << 5) | (rn & 31)
      (enc & 0xFF, (enc >> 8) & 0xFF, (enc >> 16) & 0xFF, (enc >> 24) & 0xFF)
    }
  }
}

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
fn MachineCode::emit_sub_imm_shifted12(
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
pub fn MachineCode::emit_sub_imm32(
  self : MachineCode,
  rd : Int,
  rn : Int,
  imm : Int,
) -> Unit {
  SubImm32(rd, rn, imm).emit(self)
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
