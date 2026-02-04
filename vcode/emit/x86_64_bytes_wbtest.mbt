///|
/// Whitebox tests for minimal x86_64 encoding helpers.

///|
test "x86_64 mov imm64 encoding (rax)" {
  let mc = MachineCode::new()
  mc.x86_emit_mov_imm64(0, 0x1122334455667788L)
  inspect(
    mc.get_bytes(),
    content="[72, 184, 136, 119, 102, 85, 68, 51, 34, 17]",
  )
}

///|
test "x86_64 mov imm64 encoding (r8)" {
  let mc = MachineCode::new()
  mc.x86_emit_mov_imm64(8, 0x0102030405060708L)
  inspect(mc.get_bytes(), content="[73, 184, 8, 7, 6, 5, 4, 3, 2, 1]")
}

///|
test "x86_64 add rr encoding (rax += r8)" {
  let mc = MachineCode::new()
  mc.x86_emit_add_rr(0, 8)
  inspect(mc.get_bytes(), content="[76, 1, 192]")
}

///|
test "x86_64 cmp/test encodings (r8 vs rax)" {
  let mc = MachineCode::new()
  mc.x86_emit_cmp_rr(8, 0) // cmp r8, rax
  mc.x86_emit_test_rr(8, 8) // test r8, r8
  inspect(mc.get_bytes(), content="[73, 57, 192, 77, 133, 192]")
}

///|
test "x86_64 jcc rel32 fixup patches disp32" {
  let mc = MachineCode::new()
  mc.x86_emit_jcc_rel32(@instr.Cond::Eq, 1)
  // 2 bytes padding between branch and label.
  mc.emit_byte(0x90)
  mc.emit_byte(0x90)
  mc.define_label(1)
  mc.resolve_fixups()
  // jcc takes 6 bytes total: 0F 84 disp32. disp = 2.
  inspect(mc.get_bytes(), content="[15, 132, 2, 0, 0, 0, 144, 144]")
}

///|
test "x86_64 sub rr encoding (rax -= r8)" {
  let mc = MachineCode::new()
  mc.x86_emit_sub_rr(0, 8)
  inspect(mc.get_bytes(), content="[76, 41, 192]")
}

///|
test "x86_64 jmp rel32 fixup patches disp32" {
  let mc = MachineCode::new()
  mc.x86_emit_jmp_rel32(1)
  // 3 bytes padding between jump and label.
  mc.emit_byte(0x90)
  mc.emit_byte(0x90)
  mc.emit_byte(0x90)
  mc.define_label(1)
  mc.resolve_fixups()
  inspect(mc.get_bytes(), content="[233, 3, 0, 0, 0, 144, 144, 144]")
}

///|
test "x86_64 trap imm16 encoding" {
  let mc = MachineCode::new()
  mc.x86_emit_trap_imm16(0x1234)
  inspect(mc.get_bytes(), content="[204, 52, 18]")
}

///|
test "x86_64 push/pop encoding (rbx, r14, r15)" {
  let mc = MachineCode::new()
  mc.x86_emit_push_r64(3) // rbx
  mc.x86_emit_push_r64(14) // r14
  mc.x86_emit_pop_r64(15) // r15
  inspect(mc.get_bytes(), content="[83, 65, 86, 65, 95]")
}

///|
test "x86_64 mov rr encoding (r14 <- rdi)" {
  let mc = MachineCode::new()
  mc.x86_emit_mov_rr(14, 7)
  inspect(mc.get_bytes(), content="[73, 137, 254]")
}

///|
test "x86_64 sub/add rsp imm32 encodings" {
  let mc = MachineCode::new()
  mc.x86_emit_sub_rsp_imm32(16)
  mc.x86_emit_add_rsp_imm32(32)
  inspect(
    mc.get_bytes(),
    content="[72, 129, 236, 16, 0, 0, 0, 72, 129, 196, 32, 0, 0, 0]",
  )
}

///|
test "x86_64 mov [rsp+disp], r10 encoding" {
  let mc = MachineCode::new()
  mc.x86_emit_mov_m64_r64(4, 8, 10)
  inspect(mc.get_bytes(), content="[76, 137, 148, 36, 8, 0, 0, 0]")
}

///|
test "x86_64 mov r12, [r14+disp] encoding" {
  let mc = MachineCode::new()
  mc.x86_emit_mov_r64_m64(12, 14, 0x1234)
  inspect(mc.get_bytes(), content="[77, 139, 166, 52, 18, 0, 0]")
}

///|
test "x86_64 movaps xmm15, xmm0 encoding" {
  let mc = MachineCode::new()
  mc.x86_emit_movaps_xmm_xmm(15, 0)
  inspect(mc.get_bytes(), content="[68, 15, 40, 248]")
}

///|
test "x86_64 call r64 encoding" {
  let mc = MachineCode::new()
  mc.x86_emit_call_r64(0) // rax
  mc.x86_emit_call_r64(11) // r11
  inspect(mc.get_bytes(), content="[255, 208, 65, 255, 211]")
}

///|
test "x86_64 mov loads/stores (m32) encodings" {
  let mc = MachineCode::new()
  mc.x86_emit_mov_r32_m32(9, 8, 0x1234) // r9d = [r8 + disp32]
  mc.x86_emit_mov_m32_r32(8, 16, 9) // [r8 + disp32] = r9d
  inspect(
    mc.get_bytes(),
    content="[69, 139, 136, 52, 18, 0, 0, 69, 137, 136, 16, 0, 0, 0]",
  )
}

///|
test "x86_64 mov stores (m8/m16) encodings" {
  let mc = MachineCode::new()
  mc.x86_emit_mov_m8_r8(8, 0x1234, 9) // [r8+disp32] = r9b
  mc.x86_emit_mov_m16_r16(4, 8, 11) // [rsp+disp32] = r11w
  inspect(
    mc.get_bytes(),
    content="[69, 136, 136, 52, 18, 0, 0, 102, 68, 137, 156, 36, 8, 0, 0, 0]",
  )
}

///|
test "x86_64 movss encodings (m32)" {
  let mc = MachineCode::new()
  mc.x86_emit_movss_xmm_m32(1, 4, 0)
  mc.x86_emit_movss_m32_xmm(4, 8, 1)
  inspect(
    mc.get_bytes(),
    content="[243, 15, 16, 140, 36, 0, 0, 0, 0, 243, 15, 17, 140, 36, 8, 0, 0, 0]",
  )
}

///|
test "x86_64 movsx/movzx encodings" {
  let mc = MachineCode::new()
  mc.x86_emit_movsx_r64_m8(0, 4, 0)
  mc.x86_emit_movzx_r32_m16(10, 11, 8)
  inspect(
    mc.get_bytes(),
    content="[72, 15, 190, 132, 36, 0, 0, 0, 0, 69, 15, 183, 147, 8, 0, 0, 0]",
  )
}

///|
test "x86_64 movsd/movdqu stores to [rsp+disp]" {
  let mc = MachineCode::new()
  mc.x86_emit_movsd_m64_xmm(4, 0, 15)
  mc.x86_emit_movdqu_m128_xmm(4, 16, 15)
  inspect(
    mc.get_bytes(),
    content="[242, 68, 15, 17, 188, 36, 0, 0, 0, 0, 243, 68, 15, 127, 188, 36, 16, 0, 0, 0]",
  )
}

///|
test "x86_64 movsd/movdqu loads from [rsp+disp]" {
  let mc = MachineCode::new()
  mc.x86_emit_movsd_xmm_m64(15, 4, 0)
  mc.x86_emit_movdqu_xmm_m128(15, 4, 16)
  inspect(
    mc.get_bytes(),
    content="[242, 68, 15, 16, 188, 36, 0, 0, 0, 0, 243, 68, 15, 111, 188, 36, 16, 0, 0, 0]",
  )
}

///|
test "x86_64 ucomiss/ucomisd encodings" {
  let mc = MachineCode::new()
  mc.x86_emit_ucomiss_xmm_xmm(3, 4) // ucomiss xmm3, xmm4
  mc.x86_emit_ucomisd_xmm_xmm(11, 12) // ucomisd xmm11, xmm12
  inspect(mc.get_bytes(), content="[15, 46, 220, 102, 69, 15, 46, 220]")
}

///|
test "x86_64 SIMD bitwise encodings (SSE2)" {
  let mc = MachineCode::new()
  mc.x86_emit_pcmpeqd_xmm_xmm(15, 15) // pcmpeqd xmm15, xmm15
  mc.x86_emit_pand_xmm_xmm(1, 2) // pand xmm1, xmm2
  mc.x86_emit_por_xmm_xmm(1, 2) // por xmm1, xmm2
  mc.x86_emit_pxor_xmm_xmm(1, 2) // pxor xmm1, xmm2
  mc.x86_emit_pandn_xmm_xmm(1, 2) // pandn xmm1, xmm2
  inspect(
    mc.get_bytes(),
    content="[102, 69, 15, 118, 255, 102, 15, 219, 202, 102, 15, 235, 202, 102, 15, 239, 202, 102, 15, 223, 202]",
  )
}

///|
test "x86_64 pinsrq encoding (SSE4.1)" {
  let mc = MachineCode::new()
  mc.x86_emit_pinsrq_xmm_r64_imm8(1, 0, 1) // pinsrq xmm1, rax, 1
  inspect(mc.get_bytes(), content="[102, 72, 15, 58, 34, 200, 1]")
}

///|
test "x86_64 SIMD integer encodings (padd/psub/pmul/pshufd)" {
  let mc = MachineCode::new()
  mc.x86_emit_padd_xmm_xmm(@instr.B8, 1, 2) // paddb xmm1, xmm2
  mc.x86_emit_padd_xmm_xmm(@instr.D64, 1, 2) // paddq xmm1, xmm2
  mc.x86_emit_psub_xmm_xmm(@instr.S32, 1, 2) // psubd xmm1, xmm2
  mc.x86_emit_pmullw_xmm_xmm(1, 2) // pmullw xmm1, xmm2
  mc.x86_emit_pmulld_xmm_xmm(1, 2) // pmulld xmm1, xmm2
  mc.x86_emit_pcmpgt_xmm_xmm(@instr.S32, 1, 2) // pcmpgtd xmm1, xmm2
  mc.x86_emit_pcmpeq_xmm_xmm(@instr.H16, 1, 2) // pcmpeqw xmm1, xmm2
  mc.x86_emit_pshufd_xmm_xmm_imm8(1, 2, 0xB1) // pshufd xmm1, xmm2, 0xB1
  inspect(
    mc.get_bytes(),
    content="[102, 15, 252, 202, 102, 15, 212, 202, 102, 15, 250, 202, 102, 15, 213, 202, 102, 15, 56, 64, 202, 102, 15, 102, 202, 102, 15, 117, 202, 102, 15, 112, 202, 177]",
  )
}

///|
test "x86_64 SIMD pshufb/paddusb/bitmask encodings" {
  let mc = MachineCode::new()
  mc.x86_emit_paddusb_xmm_xmm(1, 2) // paddusb xmm1, xmm2
  mc.x86_emit_pshufb_xmm_xmm(1, 2) // pshufb xmm1, xmm2
  mc.x86_emit_pmovmskb_r32_xmm(0, 1) // pmovmskb eax, xmm1
  mc.x86_emit_packsswb_xmm_xmm(1, 2) // packsswb xmm1, xmm2
  mc.x86_emit_movmskps_r32_xmm(0, 1) // movmskps eax, xmm1
  mc.x86_emit_movmskpd_r32_xmm(0, 1) // movmskpd eax, xmm1
  inspect(
    mc.get_bytes(),
    content="[102, 15, 220, 202, 102, 15, 56, 0, 202, 102, 15, 215, 193, 102, 15, 99, 202, 15, 80, 193, 102, 15, 80, 193]",
  )
}

///|
test "x86_64 SIMD saturating add/sub encodings (SSE2)" {
  let mc = MachineCode::new()
  mc.x86_emit_paddsb_xmm_xmm(1, 2) // paddsb xmm1, xmm2
  mc.x86_emit_paddusb_xmm_xmm(1, 2) // paddusb xmm1, xmm2
  mc.x86_emit_paddsw_xmm_xmm(1, 2) // paddsw xmm1, xmm2
  mc.x86_emit_paddusw_xmm_xmm(1, 2) // paddusw xmm1, xmm2
  mc.x86_emit_psubsb_xmm_xmm(1, 2) // psubsb xmm1, xmm2
  mc.x86_emit_psubusb_xmm_xmm(1, 2) // psubusb xmm1, xmm2
  mc.x86_emit_psubsw_xmm_xmm(1, 2) // psubsw xmm1, xmm2
  mc.x86_emit_psubusw_xmm_xmm(1, 2) // psubusw xmm1, xmm2
  inspect(
    mc.get_bytes(),
    content="[102, 15, 236, 202, 102, 15, 220, 202, 102, 15, 237, 202, 102, 15, 221, 202, 102, 15, 232, 202, 102, 15, 216, 202, 102, 15, 233, 202, 102, 15, 217, 202]",
  )
}

///|
test "x86_64 SIMD integer min/max + average encodings" {
  let mc = MachineCode::new()
  mc.x86_emit_pavgb_xmm_xmm(1, 2) // pavgb xmm1, xmm2
  mc.x86_emit_pavgw_xmm_xmm(1, 2) // pavgw xmm1, xmm2
  mc.x86_emit_pminub_xmm_xmm(1, 2) // pminub xmm1, xmm2
  mc.x86_emit_pmaxub_xmm_xmm(1, 2) // pmaxub xmm1, xmm2
  mc.x86_emit_pminsw_xmm_xmm(1, 2) // pminsw xmm1, xmm2
  mc.x86_emit_pmaxsw_xmm_xmm(1, 2) // pmaxsw xmm1, xmm2
  mc.x86_emit_pminsb_xmm_xmm(1, 2) // pminsb xmm1, xmm2
  mc.x86_emit_pmaxsb_xmm_xmm(1, 2) // pmaxsb xmm1, xmm2
  mc.x86_emit_pminuw_xmm_xmm(1, 2) // pminuw xmm1, xmm2
  mc.x86_emit_pmaxuw_xmm_xmm(1, 2) // pmaxuw xmm1, xmm2
  mc.x86_emit_pminsd_xmm_xmm(1, 2) // pminsd xmm1, xmm2
  mc.x86_emit_pmaxsd_xmm_xmm(1, 2) // pmaxsd xmm1, xmm2
  mc.x86_emit_pminud_xmm_xmm(1, 2) // pminud xmm1, xmm2
  mc.x86_emit_pmaxud_xmm_xmm(1, 2) // pmaxud xmm1, xmm2
  inspect(
    mc.get_bytes(),
    content="[102, 15, 224, 202, 102, 15, 227, 202, 102, 15, 218, 202, 102, 15, 222, 202, 102, 15, 234, 202, 102, 15, 238, 202, 102, 15, 56, 56, 202, 102, 15, 56, 60, 202, 102, 15, 56, 58, 202, 102, 15, 56, 62, 202, 102, 15, 56, 57, 202, 102, 15, 56, 61, 202, 102, 15, 56, 59, 202, 102, 15, 56, 63, 202]",
  )
}

///|
test "x86_64 and/or/xor encodings" {
  let mc = MachineCode::new()
  mc.x86_emit_and_rr(0, 8) // and rax, r8
  mc.x86_emit_or_rr(0, 8) // or rax, r8
  mc.x86_emit_xor_rr(0, 8) // xor rax, r8
  inspect(mc.get_bytes(), content="[76, 33, 192, 76, 9, 192, 76, 49, 192]")
}

///|
test "x86_64 imul/not encodings" {
  let mc = MachineCode::new()
  mc.x86_emit_imul_rr(0, 8) // imul rax, r8
  mc.x86_emit_not_r64(11) // not r11
  inspect(mc.get_bytes(), content="[73, 15, 175, 192, 73, 247, 211]")
}

///|
test "x86_64 setcc + movzx encodings" {
  let mc = MachineCode::new()
  mc.x86_emit_setcc_r8(@instr.Cond::Eq, 9) // setz r9b
  mc.x86_emit_movzx_r32_r8(9, 9) // movzx r9d, r9b
  mc.x86_emit_setcc_r8(@instr.Cond::Ne, 4) // setnz spl (needs REX)
  inspect(
    mc.get_bytes(),
    content="[65, 15, 148, 193, 69, 15, 182, 201, 64, 15, 149, 196]",
  )
}

///|
test "x86_64 parity condition encodings (Ps/Pc)" {
  let mc = MachineCode::new()
  mc.x86_emit_setcc_r8(@instr.Cond::Ps, 0) // setp al
  mc.x86_emit_setcc_r8(@instr.Cond::Pc, 0) // setnp al
  inspect(mc.get_bytes(), content="[15, 154, 192, 15, 155, 192]")
}

///|
test "x86_64 scalar conversion encodings (SSE)" {
  let mc = MachineCode::new()
  mc.x86_emit_xorpd_xmm_xmm(0, 0) // xorpd xmm0, xmm0
  mc.x86_emit_cvttss2si_r64_xmm(0, 0) // cvttss2si rax, xmm0
  mc.x86_emit_cvttsd2si_r32_xmm(0, 1) // cvttsd2si eax, xmm1
  mc.x86_emit_cvtsi2sd_xmm_r64(0, 0) // cvtsi2sd xmm0, rax
  mc.x86_emit_cvtss2sd_xmm_xmm(1, 2) // cvtss2sd xmm1, xmm2
  mc.x86_emit_cvtsd2ss_xmm_xmm(3, 4) // cvtsd2ss xmm3, xmm4
  inspect(
    mc.get_bytes(),
    content="[102, 15, 87, 192, 243, 72, 15, 44, 192, 242, 15, 44, 193, 242, 72, 15, 42, 192, 243, 15, 90, 202, 242, 15, 90, 220]",
  )
}

///|
test "x86_64 reg extend encodings" {
  let mc = MachineCode::new()
  mc.x86_emit_mov_rr32(0, 3) // mov eax, ebx
  mc.x86_emit_movsxd_r64_r32(0, 3) // movsxd rax, ebx
  mc.x86_emit_movsx_r32_r8(0, 3) // movsx eax, bl
  mc.x86_emit_movsx_r64_r8(0, 3) // movsx rax, bl
  mc.x86_emit_movsx_r32_r16(0, 3) // movsx eax, bx
  mc.x86_emit_movsx_r64_r16(0, 3) // movsx rax, bx
  mc.x86_emit_movzx_r32_r16(0, 3) // movzx eax, bx
  mc.x86_emit_and_r_imm8_sxb64(0, 1) // and rax, 1
  inspect(
    mc.get_bytes(),
    content="[137, 216, 72, 99, 195, 15, 190, 195, 72, 15, 190, 195, 15, 191, 195, 72, 15, 191, 195, 15, 183, 195, 72, 131, 224, 1]",
  )
}

///|
test "x86_64 shifts/rotates encodings (cl + imm8)" {
  let mc = MachineCode::new()
  mc.x86_emit_shl_r_cl(0) // shl rax, cl
  mc.x86_emit_shr_r_cl(8) // shr r8, cl
  mc.x86_emit_sar_r32_cl(8) // sar r8d, cl
  mc.x86_emit_ror_r_imm8(0, 7) // ror rax, 7
  mc.x86_emit_shl_r32_imm8(8, 1) // shl r8d, 1
  inspect(
    mc.get_bytes(),
    content="[72, 211, 224, 73, 211, 232, 65, 211, 248, 72, 193, 200, 7, 65, 193, 224, 1]",
  )
}

///|
test "x86_64 div/idiv setup encodings (cqo/cdq + div)" {
  let mc = MachineCode::new()
  mc.x86_emit_cqo()
  mc.x86_emit_idiv_r64(8) // idiv r8
  mc.x86_emit_cdq()
  mc.x86_emit_div_r32(9) // div r9d
  inspect(mc.get_bytes(), content="[72, 153, 73, 247, 248, 153, 65, 247, 241]")
}

///|
test "x86_64 cmp reg, imm32 encodings" {
  let mc = MachineCode::new()
  mc.x86_emit_cmp_r_imm32(8, -1) // cmp r8, -1
  mc.x86_emit_cmp_r32_imm32(9, 0x12345678) // cmp r9d, imm32
  inspect(
    mc.get_bytes(),
    content="[73, 129, 248, 255, 255, 255, 255, 65, 129, 249, 120, 86, 52, 18]",
  )
}

///|
test "x86_64 shl/shr/sar/ror encodings (cl + imm8)" {
  let mc = MachineCode::new()
  // cl-count
  mc.x86_emit_shl_r_cl(0) // shl rax, cl
  mc.x86_emit_shr_r_cl(8) // shr r8, cl
  mc.x86_emit_sar_r32_cl(9) // sar r9d, cl
  mc.x86_emit_ror_r32_cl(0) // ror eax, cl
  // imm8-count
  mc.x86_emit_shl_r_imm8(0, 3) // shl rax, 3
  mc.x86_emit_shr_r_imm8(8, 1) // shr r8, 1
  mc.x86_emit_sar_r32_imm8(9, 7) // sar r9d, 7
  mc.x86_emit_ror_r32_imm8(0, 5) // ror eax, 5
  inspect(
    mc.get_bytes(),
    content="[72, 211, 224, 73, 211, 232, 65, 211, 249, 211, 200, 72, 193, 224, 3, 73, 193, 232, 1, 65, 193, 249, 7, 193, 200, 5]",
  )
}

///|
test "x86_64 cmovcc encodings" {
  let mc = MachineCode::new()
  mc.x86_emit_cmovcc_rr(@instr.Cond::Ne, 0, 8) // cmovne rax, r8
  mc.x86_emit_cmovcc_rr(@instr.Cond::Lt, 9, 10) // cmovl r9, r10
  inspect(mc.get_bytes(), content="[73, 15, 69, 192, 77, 15, 76, 202]")
}

///|
test "x86_64 movd/movq gpr<->xmm encodings" {
  let mc = MachineCode::new()
  mc.x86_emit_movd_r32_xmm(0, 1) // movd eax, xmm1
  mc.x86_emit_movd_xmm_r32(1, 0) // movd xmm1, eax
  mc.x86_emit_movq_r64_xmm(10, 15) // movq r10, xmm15
  mc.x86_emit_movq_xmm_r64(15, 10) // movq xmm15, r10
  inspect(
    mc.get_bytes(),
    content="[102, 15, 126, 200, 102, 15, 110, 200, 102, 77, 15, 126, 250, 102, 77, 15, 110, 250]",
  )
}
