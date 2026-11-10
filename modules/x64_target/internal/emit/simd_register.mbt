///|
/// Legacy SSE register-to-register opcodes. Each entry selects its mandatory
/// prefix and opcode map; register extension is encoded by the shared REX path.
pub(all) enum XmmRegisterOp {
  Movaps
  Minps
  Minpd
  Maxps
  Maxpd
  Subps
  Subpd
  Addps
  Addpd
  Mulps
  Mulpd
  Divps
  Divpd
  Sqrtps
  Sqrtpd
  Movss
  Movsd
  Movlhps
  Unpcklps
  Ucomiss
  Ucomisd
  Pcmpeqd
  Pand
  Por
  Pxor
  Pandn
  Phaddw
  Pmullw
  Pmulld
  Paddusb
  Paddsb
  Paddsw
  Paddusw
  Psubsb
  Psubsw
  Psubusb
  Psubusw
  Pavgb
  Pavgw
  Pminub
  Pmaxub
  Pminsw
  Pmaxsw
  Pminsb
  Pmaxsb
  Pminuw
  Pmaxuw
  Pminsd
  Pmaxsd
  Pminud
  Pmaxud
  Pabsb
  Pabsw
  Pabsd
  Pmovsxbw
  Pmovzxbw
  Pmovsxwd
  Pmovzxwd
  Pmovsxdq
  Pmovzxdq
  Pshufb
  Punpcklbw
  Punpckhbw
  Packsswb
  Packuswb
  Packssdw
  Packusdw
  Pmaddwd
  Pmaddubsw
  Pmulhrsw
  Xorpd
  Xorps
  Subss
  Subsd
  Addss
  Addsd
  Minss
  Minsd
  Maxss
  Maxsd
  Mulss
  Mulsd
  Divss
  Divsd
  Sqrtss
  Sqrtsd
  Andps
  Andpd
  Orps
  Orpd
  Cvtss2sd
  Cvtsd2ss
  Cvtdq2ps
  Cvttps2dq
  Cvttpd2dq
  Cvtdq2pd
  Cvtps2pd
  Cvtpd2ps
}

///|
pub fn CodeBuffer::x86_emit_xmm(
  self : CodeBuffer,
  operation : XmmRegisterOp,
  dst : Int32,
  src : Int32,
) -> Unit {
  let (prefix, escape, opcode) = match operation {
    Movaps => (0, 0, 0x28)
    Minps => (0, 0, 0x5D)
    Minpd => (0x66, 0, 0x5D)
    Maxps => (0, 0, 0x5F)
    Maxpd => (0x66, 0, 0x5F)
    Subps => (0, 0, 0x5C)
    Subpd => (0x66, 0, 0x5C)
    Addps => (0, 0, 0x58)
    Addpd => (0x66, 0, 0x58)
    Mulps => (0, 0, 0x59)
    Mulpd => (0x66, 0, 0x59)
    Divps => (0, 0, 0x5E)
    Divpd => (0x66, 0, 0x5E)
    Sqrtps => (0, 0, 0x51)
    Sqrtpd => (0x66, 0, 0x51)
    Movss => (0xF3, 0, 0x10)
    Movsd => (0xF2, 0, 0x10)
    Movlhps => (0, 0, 0x16)
    Unpcklps => (0, 0, 0x14)
    Ucomiss => (0, 0, 0x2E)
    Ucomisd => (0x66, 0, 0x2E)
    Pcmpeqd => (0x66, 0, 0x76)
    Pand => (0x66, 0, 0xDB)
    Por => (0x66, 0, 0xEB)
    Pxor => (0x66, 0, 0xEF)
    Pandn => (0x66, 0, 0xDF)
    Phaddw => (0x66, 0x38, 0x01)
    Pmullw => (0x66, 0, 0xD5)
    Pmulld => (0x66, 0x38, 0x40)
    Paddusb => (0x66, 0, 0xDC)
    Paddsb => (0x66, 0, 0xEC)
    Paddsw => (0x66, 0, 0xED)
    Paddusw => (0x66, 0, 0xDD)
    Psubsb => (0x66, 0, 0xE8)
    Psubsw => (0x66, 0, 0xE9)
    Psubusb => (0x66, 0, 0xD8)
    Psubusw => (0x66, 0, 0xD9)
    Pavgb => (0x66, 0, 0xE0)
    Pavgw => (0x66, 0, 0xE3)
    Pminub => (0x66, 0, 0xDA)
    Pmaxub => (0x66, 0, 0xDE)
    Pminsw => (0x66, 0, 0xEA)
    Pmaxsw => (0x66, 0, 0xEE)
    Pminsb => (0x66, 0x38, 0x38)
    Pmaxsb => (0x66, 0x38, 0x3C)
    Pminuw => (0x66, 0x38, 0x3A)
    Pmaxuw => (0x66, 0x38, 0x3E)
    Pminsd => (0x66, 0x38, 0x39)
    Pmaxsd => (0x66, 0x38, 0x3D)
    Pminud => (0x66, 0x38, 0x3B)
    Pmaxud => (0x66, 0x38, 0x3F)
    Pabsb => (0x66, 0x38, 0x1C)
    Pabsw => (0x66, 0x38, 0x1D)
    Pabsd => (0x66, 0x38, 0x1E)
    Pmovsxbw => (0x66, 0x38, 0x20)
    Pmovzxbw => (0x66, 0x38, 0x30)
    Pmovsxwd => (0x66, 0x38, 0x23)
    Pmovzxwd => (0x66, 0x38, 0x33)
    Pmovsxdq => (0x66, 0x38, 0x25)
    Pmovzxdq => (0x66, 0x38, 0x35)
    Pshufb => (0x66, 0x38, 0x00)
    Punpcklbw => (0x66, 0, 0x60)
    Punpckhbw => (0x66, 0, 0x68)
    Packsswb => (0x66, 0, 0x63)
    Packuswb => (0x66, 0, 0x67)
    Packssdw => (0x66, 0, 0x6B)
    Packusdw => (0x66, 0x38, 0x2B)
    Pmaddwd => (0x66, 0, 0xF5)
    Pmaddubsw => (0x66, 0x38, 0x04)
    Pmulhrsw => (0x66, 0x38, 0x0B)
    Xorpd => (0x66, 0, 0x57)
    Xorps => (0, 0, 0x57)
    Subss => (0xF3, 0, 0x5C)
    Subsd => (0xF2, 0, 0x5C)
    Addss => (0xF3, 0, 0x58)
    Addsd => (0xF2, 0, 0x58)
    Minss => (0xF3, 0, 0x5D)
    Minsd => (0xF2, 0, 0x5D)
    Maxss => (0xF3, 0, 0x5F)
    Maxsd => (0xF2, 0, 0x5F)
    Mulss => (0xF3, 0, 0x59)
    Mulsd => (0xF2, 0, 0x59)
    Divss => (0xF3, 0, 0x5E)
    Divsd => (0xF2, 0, 0x5E)
    Sqrtss => (0xF3, 0, 0x51)
    Sqrtsd => (0xF2, 0, 0x51)
    Andps => (0, 0, 0x54)
    Andpd => (0x66, 0, 0x54)
    Orps => (0, 0, 0x56)
    Orpd => (0x66, 0, 0x56)
    Cvtss2sd => (0xF3, 0, 0x5A)
    Cvtsd2ss => (0xF2, 0, 0x5A)
    Cvtdq2ps => (0, 0, 0x5B)
    Cvttps2dq => (0xF3, 0, 0x5B)
    Cvttpd2dq => (0x66, 0, 0xE6)
    Cvtdq2pd => (0xF3, 0, 0xE6)
    Cvtps2pd => (0, 0, 0x5A)
    Cvtpd2ps => (0x66, 0, 0x5A)
  }
  self.emit_legacy_rr(prefix, escape, opcode, dst, src, false)
}
