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
    AddImm32Shifted12(rd, rn, imm12) => {
      // ADD Wd, Wn, #imm12, lsl #12
      let imm = imm12 & 0xFFF
      let inst = (0b0 << 31) |
        (0 << 30) |
        (0 << 29) |
        (0b100010 << 23) |
        (1 << 22) | // sh=1: shift imm12 left by 12
        (imm << 10) |
        ((rn & 31) << 5) |
        (rd & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    SubImm32(rd, rn, imm) => {
      // SUB Wd, Wn, #imm (32-bit)
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = ((rn >> 3) & 3) | ((imm & 0x3F) << 2)
      let b2 = (imm >> 6) & 0x3F
      let b3 = 0x51 // SUB imm 32-bit: sf=0, op=1
      (b0, b1, b2, b3)
    }
    SubImm32Shifted12(rd, rn, imm12) => {
      // SUB Wd, Wn, #imm12, lsl #12
      let imm = imm12 & 0xFFF
      let inst = (0b0 << 31) |
        (1 << 30) |
        (0 << 29) |
        (0b100010 << 23) |
        (1 << 22) | // sh=1: shift imm12 left by 12
        (imm << 10) |
        ((rn & 31) << 5) |
        (rd & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
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
    AndReg32(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = (rn >> 3) & 3
      let b2 = rm & 31
      let b3 = 0x0A // AND 32-bit: sf=0
      (b0, b1, b2, b3)
    }
    AndImm(rd, rn, imm_bits) => {
      // AND (immediate): bits_31_23 = 000_100100 with sf=1.
      let top9 = 0b000_100100 | (1 << 8)
      let inst = (top9 << 23) |
        ((imm_bits & 0x1FFF) << 10) |
        ((rn & 31) << 5) |
        (rd & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    AndImm32(rd, rn, imm_bits) => {
      // AND (immediate) 32-bit: bits_31_23 = 000_100100 with sf=0.
      let top9 = 0b000_100100
      let inst = (top9 << 23) |
        ((imm_bits & 0x1FFF) << 10) |
        ((rn & 31) << 5) |
        (rd & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
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
    OrrReg32(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = (rn >> 3) & 3
      let b2 = rm & 31
      let b3 = 0x2A // ORR 32-bit: sf=0
      (b0, b1, b2, b3)
    }
    OrrImm(rd, rn, imm_bits) => {
      // ORR (immediate): bits_31_23 = 001_100100 with sf=1.
      let top9 = 0b001_100100 | (1 << 8)
      let inst = (top9 << 23) |
        ((imm_bits & 0x1FFF) << 10) |
        ((rn & 31) << 5) |
        (rd & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    OrrImm32(rd, rn, imm_bits) => {
      // ORR (immediate) 32-bit: bits_31_23 = 001_100100 with sf=0.
      let top9 = 0b001_100100
      let inst = (top9 << 23) |
        ((imm_bits & 0x1FFF) << 10) |
        ((rn & 31) << 5) |
        (rd & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
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
    EorReg32(rd, rn, rm) => {
      let b0 = (rd & 31) | ((rn & 7) << 5)
      let b1 = (rn >> 3) & 3
      let b2 = rm & 31
      let b3 = 0x4A // EOR 32-bit: sf=0
      (b0, b1, b2, b3)
    }
    EorImm(rd, rn, imm_bits) => {
      // EOR (immediate): bits_31_23 = 010_100100 with sf=1.
      let top9 = 0b010_100100 | (1 << 8)
      let inst = (top9 << 23) |
        ((imm_bits & 0x1FFF) << 10) |
        ((rn & 31) << 5) |
        (rd & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
    }
    EorImm32(rd, rn, imm_bits) => {
      // EOR (immediate) 32-bit: bits_31_23 = 010_100100 with sf=0.
      let top9 = 0b010_100100
      let inst = (top9 << 23) |
        ((imm_bits & 0x1FFF) << 10) |
        ((rn & 31) << 5) |
        (rd & 31)
      (inst & 255, (inst >> 8) & 255, (inst >> 16) & 255, (inst >> 24) & 255)
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
    CmpImmShifted12(rn, imm12) => {
      // CMP Xn, #imm12, lsl #12 (encoded as SUBS XZR, Xn, #imm12, LSL #12)
      let imm = imm12 & 0xFFF
      let inst = (0b1 << 31) |
        (1 << 30) |
        (1 << 29) | // S=1 (sets flags)
        (0b100010 << 23) |
        (1 << 22) | // sh=1: shift imm12 left by 12
        (imm << 10) |
        ((rn & 31) << 5) |
        31 // Rd = XZR
      (
        inst & 0xFF,
        (inst >> 8) & 0xFF,
        (inst >> 16) & 0xFF,
        (inst >> 24) & 0xFF,
      )
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
    CmpImm32Shifted12(rn, imm12) => {
      // CMP Wn, #imm12, lsl #12 (encoded as SUBS WZR, Wn, #imm12, LSL #12)
      let imm = imm12 & 0xFFF
      let inst = (0b0 << 31) |
        (1 << 30) |
        (1 << 29) | // S=1 (sets flags)
        (0b100010 << 23) |
        (1 << 22) | // sh=1: shift imm12 left by 12
        (imm << 10) |
        ((rn & 31) << 5) |
        31 // Rd = WZR
      (
        inst & 0xFF,
        (inst >> 8) & 0xFF,
        (inst >> 16) & 0xFF,
        (inst >> 24) & 0xFF,
      )
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
    _ => self.instr_bytes_simd()
  }
}
