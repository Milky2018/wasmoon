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
