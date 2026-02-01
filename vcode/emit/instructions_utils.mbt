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
