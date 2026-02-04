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
