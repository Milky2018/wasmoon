// NEON SIMD instruction encodings (extracted from Instruction::instr_bytes)

///|
fn Instruction::instr_bytes_simd(self : Instruction) -> (Int, Int, Int, Int) {
  match self {
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
    _ =>
      abort(
        "non-SIMD instruction routed to instr_bytes_simd: \{self.annotate()}",
      )
  }
}
