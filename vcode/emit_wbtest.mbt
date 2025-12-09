// Tests for AArch64 code emission

///|
test "emit: add register" {
  let mc = MachineCode::new()
  emit_add_reg(mc, 0, 1, 2) // ADD X0, X1, X2
  let bytes = mc.get_bytes()
  // 64-bit ADD: 0x8B020020
  inspect(bytes[0], content="32") // 0x20 = rd=0 | (rn[2:0]=1)<<5
  inspect(bytes[1], content="0") // 0x00 = (rn >> 3) & 3 = 0
  inspect(bytes[2], content="2") // 0x02 = rm
  inspect(bytes[3], content="139") // 0x8B
}

///|
test "emit: sub register" {
  let mc = MachineCode::new()
  emit_sub_reg(mc, 3, 4, 5) // SUB X3, X4, X5
  let bytes = mc.get_bytes()
  // 64-bit SUB: 0xCB050083
  inspect(bytes[0], content="131") // 0x83 = rd=3 | (rn[2:0]=4)<<5
  inspect(bytes[1], content="0") // 0x00 = (rn >> 3) & 3 = 0
  inspect(bytes[2], content="5") // 0x05 = rm
  inspect(bytes[3], content="203") // 0xCB
}

///|
test "emit: mov register" {
  let mc = MachineCode::new()
  emit_mov_reg(mc, 0, 1) // MOV X0, X1 (ORR X0, XZR, X1)
  let bytes = mc.get_bytes()
  // MOV is ORR X0, XZR, X1: 0xAA0103E0
  // rd=0, rn=31 (XZR), rm=1
  inspect(bytes[0], content="224") // 0xE0 = rd=0 | (rn[2:0]=31&7=7)<<5 = 0 | 224 = 224
  inspect(bytes[1], content="3") // 0x03 = (rn >> 3) & 3 = (31 >> 3) & 3 = 3
  inspect(bytes[2], content="1") // 0x01 = rm
  inspect(bytes[3], content="170") // 0xAA
}

///|
test "emit: movz immediate" {
  let mc = MachineCode::new()
  emit_movz(mc, 0, 0x1234, 0) // MOVZ X0, #0x1234
  let bytes = mc.get_bytes()
  // MOVZ X0, #0x1234: 0xD2824680 (little-endian: 80 46 82 D2)
  inspect(bytes[3], content="210") // 0xD2
  inspect(bytes[2], content="130") // 0x82
}

///|
test "emit: movz immediate 42" {
  let mc = MachineCode::new()
  emit_movz(mc, 0, 42, 0) // MOVZ X0, #42
  let bytes = mc.get_bytes()
  // MOVZ X0, #42: 0xD2800540 (little-endian: 40 05 80 D2)
  inspect(bytes[0], content="64") // 0x40
  inspect(bytes[1], content="5") // 0x05
  inspect(bytes[2], content="128") // 0x80
  inspect(bytes[3], content="210") // 0xD2
}

///|
test "emit: load immediate 64-bit" {
  let mc = MachineCode::new()
  emit_load_imm64(mc, 0, 42L) // Load 42 into X0
  // Should emit MOVZ X0, #42
  inspect(mc.size() > 0, content="true")
}

///|
test "emit: ldr/str" {
  let mc = MachineCode::new()
  emit_ldr_imm(mc, 0, 1, 8) // LDR X0, [X1, #8]
  emit_str_imm(mc, 2, 3, 16) // STR X2, [X3, #16]
  inspect(mc.size(), content="8")
}

///|
test "emit: branch" {
  let mc = MachineCode::new()
  mc.define_label(0)
  emit_nop(mc) // Some code in block 0
  mc.define_label(1)
  emit_nop(mc) // Some code in block 1
  emit_b(mc, 0) // B to block 0
  mc.resolve_fixups()
  // Should have 3 instructions = 12 bytes
  inspect(mc.size(), content="12")
}

///|
test "emit: conditional branch" {
  let mc = MachineCode::new()
  mc.define_label(0)
  emit_cbz(mc, 0, 1) // CBZ X0, block1
  mc.define_label(1)
  emit_nop(mc)
  mc.resolve_fixups()
  inspect(mc.size(), content="8")
}

///|
test "emit: ret" {
  let mc = MachineCode::new()
  emit_ret(mc, 30) // RET X30
  let bytes = mc.get_bytes()
  // RET X30: 0xD65F03C0 (little-endian: C0 03 5F D6)
  inspect(bytes[0], content="192") // 0xC0
  inspect(bytes[1], content="3") // 0x03
  inspect(bytes[2], content="95") // 0x5F
  inspect(bytes[3], content="214") // 0xD6
}

///|
test "emit: nop" {
  let mc = MachineCode::new()
  emit_nop(mc)
  let bytes = mc.get_bytes()
  // NOP: 0xD503201F
  inspect(bytes[0], content="31") // 0x1F
  inspect(bytes[1], content="32") // 0x20
  inspect(bytes[2], content="3") // 0x03
  inspect(bytes[3], content="213") // 0xD5
}

///|
test "emit: fadd" {
  let mc = MachineCode::new()
  emit_fadd_d(mc, 0, 1, 2) // FADD D0, D1, D2
  let bytes = mc.get_bytes()
  // FADD (double): 0x1E622820
  inspect(bytes[3], content="30") // 0x1E
}

///|
test "emit: comparison" {
  let mc = MachineCode::new()
  emit_cmp_reg(mc, 0, 1) // CMP X0, X1
  emit_cset(mc, 2, EQ.to_int()) // CSET X2, EQ
  inspect(mc.size(), content="8")
}

///|
test "emit: full function" {
  // Create a simple add function: add(a, b) -> a + b
  let func = VCodeFunction::new("test_add")
  let _ = func.add_param(Int)
  let _ = func.add_param(Int)
  func.add_result(Int)
  let block = func.new_block()

  // X0 = X0 + X1 (assuming params in X0, X1)
  let add_inst = VCodeInst::new(Add)
  add_inst.add_def({ reg: Physical({ index: 0, class: Int }) })
  add_inst.add_use(Physical({ index: 0, class: Int }))
  add_inst.add_use(Physical({ index: 1, class: Int }))
  block.add_inst(add_inst)

  // Return X0
  block.set_terminator(Return([Physical({ index: 0, class: Int })]))

  // Emit machine code
  let mc = emit_function(func)

  // Should have: ADD + RET = 2 instructions = 8 bytes
  inspect(mc.size(), content="44")
}

///|
test "emit: hex dump" {
  let mc = MachineCode::new()
  emit_nop(mc)
  let hex = mc.hex_dump()
  // NOP bytes in hex
  inspect(hex.length() > 0, content="true")
}

///|
test "emit: mul/div" {
  let mc = MachineCode::new()
  emit_mul(mc, 0, 1, 2) // MUL X0, X1, X2
  emit_sdiv(mc, 3, 4, 5) // SDIV X3, X4, X5
  emit_udiv(mc, 6, 7, 8) // UDIV X6, X7, X8
  inspect(mc.size(), content="12")
}

///|
test "emit: bitwise" {
  let mc = MachineCode::new()
  emit_and_reg(mc, 0, 1, 2) // AND X0, X1, X2
  emit_orr_reg(mc, 0, 1, 2) // ORR X0, X1, X2
  emit_eor_reg(mc, 0, 1, 2) // EOR X0, X1, X2
  inspect(mc.size(), content="12")
}

///|
test "emit: shifts" {
  let mc = MachineCode::new()
  emit_lsl_reg(mc, 0, 1, 2) // LSL X0, X1, X2
  emit_lsr_reg(mc, 0, 1, 2) // LSR X0, X1, X2
  emit_asr_reg(mc, 0, 1, 2) // ASR X0, X1, X2
  inspect(mc.size(), content="12")
}

///|
test "emit: various loads" {
  let mc = MachineCode::new()
  emit_ldrb_imm(mc, 0, 1, 0) // LDRB W0, [X1]
  emit_ldrh_imm(mc, 0, 1, 0) // LDRH W0, [X1]
  emit_ldr_w_imm(mc, 0, 1, 0) // LDR W0, [X1]
  emit_ldr_imm(mc, 0, 1, 0) // LDR X0, [X1]
  inspect(mc.size(), content="16")
}

///|
test "emit: various stores" {
  let mc = MachineCode::new()
  emit_strb_imm(mc, 0, 1, 0) // STRB W0, [X1]
  emit_strh_imm(mc, 0, 1, 0) // STRH W0, [X1]
  emit_str_w_imm(mc, 0, 1, 0) // STR W0, [X1]
  emit_str_imm(mc, 0, 1, 0) // STR X0, [X1]
  inspect(mc.size(), content="16")
}

///|
test "emit: float operations" {
  let mc = MachineCode::new()
  emit_fadd_d(mc, 0, 1, 2)
  emit_fsub_d(mc, 0, 1, 2)
  emit_fmul_d(mc, 0, 1, 2)
  emit_fdiv_d(mc, 0, 1, 2)
  emit_fmov_d(mc, 0, 1)
  emit_fcmp_d(mc, 0, 1)
  inspect(mc.size(), content="24")
}

///|
test "emit: branch with link" {
  let mc = MachineCode::new()
  mc.define_label(0)
  emit_bl(mc, 0) // BL to self (for testing)
  mc.resolve_fixups()
  let bytes = mc.get_bytes()
  // BL instruction
  inspect(bytes[3], content="148") // 0x94
}

///|
test "machine code: label and fixup" {
  let mc = MachineCode::new()

  // Block 0: jump to block 1
  mc.define_label(0)
  emit_b(mc, 1)

  // Block 1: return
  mc.define_label(1)
  emit_ret(mc, 30)
  mc.resolve_fixups()

  // The branch should now point to block 1
  // B instruction at offset 0 should jump forward 1 instruction
  let bytes = mc.get_bytes()
  inspect(bytes.length(), content="8")
}

///|
test "machine code: alignment" {
  let mc = MachineCode::new()

  // Emit a single instruction (4 bytes)
  emit_nop(mc)
  inspect(mc.size(), content="4")

  // Align to 16 bytes - should pad with 3 more NOPs
  mc.align(16)
  inspect(mc.size(), content="16")

  // Already aligned, should do nothing
  mc.align(16)
  inspect(mc.size(), content="16")

  // Emit one more instruction
  emit_nop(mc)
  inspect(mc.size(), content="20")

  // Align to 8 bytes - should pad with 1 NOP
  mc.align(8)
  inspect(mc.size(), content="24")
}

///|
test "machine code: align_function" {
  let mc = MachineCode::new()

  // Emit 2 instructions (8 bytes)
  emit_nop(mc)
  emit_nop(mc)
  inspect(mc.size(), content="8")

  // Align to function boundary (16 bytes)
  mc.align_function()
  inspect(mc.size(), content="16")
}

///|
test "machine code: align with invalid alignment" {
  let mc = MachineCode::new()
  emit_nop(mc)
  inspect(mc.size(), content="4")

  // Invalid alignment (not power of 2) should do nothing
  mc.align(3)
  inspect(mc.size(), content="4")

  // Zero alignment should do nothing
  mc.align(0)
  inspect(mc.size(), content="4")
}
