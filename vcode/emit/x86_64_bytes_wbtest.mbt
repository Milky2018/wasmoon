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
