// Tests for AArch64 code emission

///|
test "emit: add register" {
  let mc = @emit.MachineCode::new()
  mc.emit_add_reg(0, 1, 2)
  let bytes = mc.get_bytes()
  // 64-bit ADD: 0x8B020020
  inspect(bytes[0], content="32") // 0x20 = rd=0 | (rn[2:0]=1)<<5
  inspect(bytes[1], content="0") // 0x00 = (rn >> 3) & 3 = 0
  inspect(bytes[2], content="2") // 0x02 = rm
  inspect(bytes[3], content="139") // 0x8B
}

///|
test "emit: sub register" {
  let mc = @emit.MachineCode::new()
  mc.emit_sub_reg(3, 4, 5) // SUB X3, X4, X5
  let bytes = mc.get_bytes()
  // 64-bit SUB: 0xCB050083
  inspect(bytes[0], content="131") // 0x83 = rd=3 | (rn[2:0]=4)<<5
  inspect(bytes[1], content="0") // 0x00 = (rn >> 3) & 3 = 0
  inspect(bytes[2], content="5") // 0x05 = rm
  inspect(bytes[3], content="203") // 0xCB
}

///|
test "emit: mov register" {
  let mc = @emit.MachineCode::new()
  mc.emit_mov_reg(0, 1) // MOV X0, X1 (ORR X0, XZR, X1)
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
  let mc = @emit.MachineCode::new()
  mc.emit_movz(0, 0x1234, 0) // MOVZ X0, #0x1234
  let bytes = mc.get_bytes()
  // MOVZ X0, #0x1234: 0xD2824680 (little-endian: 80 46 82 D2)
  inspect(bytes[3], content="210") // 0xD2
  inspect(bytes[2], content="130") // 0x82
}

///|
test "emit: movz immediate 42" {
  let mc = @emit.MachineCode::new()
  mc.emit_movz(0, 42, 0) // MOVZ X0, #42
  let bytes = mc.get_bytes()
  // MOVZ X0, #42: 0xD2800540 (little-endian: 40 05 80 D2)
  inspect(bytes[0], content="64") // 0x40
  inspect(bytes[1], content="5") // 0x05
  inspect(bytes[2], content="128") // 0x80
  inspect(bytes[3], content="210") // 0xD2
}

///|
test "emit: load immediate 64-bit" {
  let mc = @emit.MachineCode::new()
  mc.emit_load_imm64(0, 42L) // Load 42 into X0
  // Should emit MOVZ X0, #42
  inspect(mc.size() > 0, content="true")
}

///|
test "emit: ldr/str" {
  let mc = @emit.MachineCode::new()
  mc.emit_ldr_imm(0, 1, 8) // LDR X0, [X1, #8]
  mc.emit_str_imm(2, 3, 16) // STR X2, [X3, #16]
  inspect(mc.size(), content="8")
}

///|
test "emit: branch" {
  let mc = @emit.MachineCode::new()
  mc.define_label(0)
  mc.emit_nop() // Some code in block 0
  mc.define_label(1)
  mc.emit_nop() // Some code in block 1
  mc.emit_b(0) // B to block 0
  mc.resolve_fixups()
  // Should have 3 instructions = 12 bytes
  inspect(mc.size(), content="12")
}

///|
test "emit: conditional branch" {
  let mc = @emit.MachineCode::new()
  mc.define_label(0)
  mc.emit_cbz(0, 1) // CBZ X0, block1
  mc.define_label(1)
  mc.emit_nop()
  mc.resolve_fixups()
  inspect(mc.size(), content="8")
}

///|
test "emit: ret" {
  let mc = @emit.MachineCode::new()
  mc.emit_ret(30) // RET X30
  let bytes = mc.get_bytes()
  // RET X30: 0xD65F03C0 (little-endian: C0 03 5F D6)
  inspect(bytes[0], content="192") // 0xC0
  inspect(bytes[1], content="3") // 0x03
  inspect(bytes[2], content="95") // 0x5F
  inspect(bytes[3], content="214") // 0xD6
}

///|
test "emit: nop" {
  let mc = @emit.MachineCode::new()
  mc.emit_nop()
  let bytes = mc.get_bytes()
  // NOP: 0xD503201F
  inspect(bytes[0], content="31") // 0x1F
  inspect(bytes[1], content="32") // 0x20
  inspect(bytes[2], content="3") // 0x03
  inspect(bytes[3], content="213") // 0xD5
}

///|
test "emit: fadd" {
  let mc = @emit.MachineCode::new()
  mc.emit_fadd_d(0, 1, 2) // FADD D0, D1, D2
  let bytes = mc.get_bytes()
  // FADD (double): 0x1E622820
  inspect(bytes[3], content="30") // 0x1E
}

///|
test "emit: comparison" {
  let mc = @emit.MachineCode::new()
  mc.emit_cmp_reg(0, 1) // CMP X0, X1
  mc.emit_cset(2, @emit.EQ.to_int()) // CSET X2, EQ
  inspect(mc.size(), content="8")
}

///|
test "emit: full function" {
  // Create a simple add function: add(a, b) -> a + b
  let func = @lower.VCodeFunction::new("test_add")
  func.add_param(Int) |> ignore
  func.add_param(Int) |> ignore
  func.add_result(Int)
  let block = func.new_block()

  // X0 = X0 + X1 (assuming params in X0, X1)
  let add_inst = @instr.VCodeInst::new(Add(true))
  add_inst.add_def({ reg: @abi.Physical({ index: 0, class: Int }) })
  add_inst.add_use(@abi.Physical({ index: 0, class: Int }))
  add_inst.add_use(@abi.Physical({ index: 1, class: Int }))
  block.add_inst(add_inst)

  // Return X0
  block.set_terminator(Return([@abi.Physical({ index: 0, class: Int })]))

  // Emit machine code
  let mc = @emit.emit_function(func)

  // Cranelift-style prologue/epilogue:
  // Prologue: stp x29,x30 + mov x29,sp + str x19 + sub sp + mov x19,x0 = 5 inst
  // Body: add x0,x0,x1 = 1 inst
  // Epilogue: add sp + ldr x19 + ldp x29,x30 + ret = 4 inst
  // Total: 10 instructions = 40 bytes
  inspect(mc.size(), content="40")
}

///|
test "emit: hex dump" {
  let mc = @emit.MachineCode::new()
  mc.emit_nop()
  let hex = mc.hex_dump()
  // NOP bytes in hex
  inspect(hex.length() > 0, content="true")
}

///|
test "emit: mul/div" {
  let mc = @emit.MachineCode::new()
  mc.emit_mul(0, 1, 2) // MUL X0, X1, X2
  mc.emit_sdiv(3, 4, 5) // SDIV X3, X4, X5
  mc.emit_udiv(6, 7, 8) // UDIV X6, X7, X8
  inspect(mc.size(), content="12")
}

///|
test "emit: bitwise" {
  let mc = @emit.MachineCode::new()
  mc.emit_and_reg(0, 1, 2) // AND X0, X1, X2
  mc.emit_orr_reg(0, 1, 2) // ORR X0, X1, X2
  mc.emit_eor_reg(0, 1, 2) // EOR X0, X1, X2
  inspect(mc.size(), content="12")
}

///|
test "emit: shifts" {
  let mc = @emit.MachineCode::new()
  mc.emit_lsl_reg(0, 1, 2) // LSL X0, X1, X2
  mc.emit_lsr_reg(0, 1, 2) // LSR X0, X1, X2
  mc.emit_asr_reg(0, 1, 2) // ASR X0, X1, X2
  inspect(mc.size(), content="12")
}

///|
test "emit: various loads" {
  let mc = @emit.MachineCode::new()
  mc.emit_ldrb_imm(0, 1, 0) // LDRB W0, [X1]
  mc.emit_ldrh_imm(0, 1, 0) // LDRH W0, [X1]
  mc.emit_ldr_w_imm(0, 1, 0) // LDR W0, [X1]
  mc.emit_ldr_imm(0, 1, 0) // LDR X0, [X1]
  inspect(mc.size(), content="16")
}

///|
test "emit: various stores" {
  let mc = @emit.MachineCode::new()
  mc.emit_strb_imm(0, 1, 0) // STRB W0, [X1]
  mc.emit_strh_imm(0, 1, 0) // STRH W0, [X1]
  mc.emit_str_w_imm(0, 1, 0) // STR W0, [X1]
  mc.emit_str_imm(0, 1, 0) // STR X0, [X1]
  inspect(mc.size(), content="16")
}

///|
test "emit: float operations" {
  let mc = @emit.MachineCode::new()
  mc.emit_fadd_d(0, 1, 2)
  mc.emit_fsub_d(0, 1, 2)
  mc.emit_fmul_d(0, 1, 2)
  mc.emit_fdiv_d(0, 1, 2)
  mc.emit_fmov_d(0, 1)
  mc.emit_fcmp_d(0, 1)
  inspect(mc.size(), content="24")
}

///|
test "emit: branch with link" {
  let mc = @emit.MachineCode::new()
  mc.define_label(0)
  mc.emit_bl(0) // BL to self (for testing)
  mc.resolve_fixups()
  let bytes = mc.get_bytes()
  // BL instruction
  inspect(bytes[3], content="148") // 0x94
}

///|
test "machine code: label and fixup" {
  let mc = @emit.MachineCode::new()

  // Block 0: jump to block 1
  mc.define_label(0)
  mc.emit_b(1)

  // Block 1: return
  mc.define_label(1)
  mc.emit_ret(30)
  mc.resolve_fixups()

  // The branch should now point to block 1
  // B instruction at offset 0 should jump forward 1 instruction
  let bytes = mc.get_bytes()
  inspect(bytes.length(), content="8")
}

///|
test "machine code: alignment" {
  let mc = @emit.MachineCode::new()

  // Emit a single instruction (4 bytes)
  mc.emit_nop()
  inspect(mc.size(), content="4")

  // Align to 16 bytes - should pad with 3 more NOPs
  mc.align(16)
  inspect(mc.size(), content="16")

  // Already aligned, should do nothing
  mc.align(16)
  inspect(mc.size(), content="16")

  // Emit one more instruction
  mc.emit_nop()
  inspect(mc.size(), content="20")

  // Align to 8 bytes - should pad with 1 NOP
  mc.align(8)
  inspect(mc.size(), content="24")
}

///|
test "machine code: align_function" {
  let mc = @emit.MachineCode::new()

  // Emit 2 instructions (8 bytes)
  mc.emit_nop()
  mc.emit_nop()
  inspect(mc.size(), content="8")

  // Align to function boundary (16 bytes)
  mc.align_function()
  inspect(mc.size(), content="16")
}

///|
test "machine code: align with invalid alignment" {
  let mc = @emit.MachineCode::new()
  mc.emit_nop()
  inspect(mc.size(), content="4")

  // Invalid alignment (not power of 2) should do nothing
  mc.align(3)
  inspect(mc.size(), content="4")

  // Zero alignment should do nothing
  mc.align(0)
  inspect(mc.size(), content="4")
}

///|
test "emit: complete function with control flow" {
  // Test a function with conditional branch:
  // func max(a, b) -> int:
  //   if a > b:
  //     return a
  //   else:
  //     return b

  let func = @lower.VCodeFunction::new("max")
  func.add_result(Int)

  // Create blocks
  let block0 = func.new_block() // entry: compare and branch
  let block1 = func.new_block() // then: return a
  let block2 = func.new_block() // else: return b

  // block0: compare X3 (a) > X4 (b) and branch
  // CMP X3, X4; CSET X8, GT; CBNZ X8, block1; B block2
  let cmp_inst = @instr.VCodeInst::new(Cmp(Sgt, true))
  cmp_inst.add_def({ reg: @abi.Physical({ index: 8, class: Int }) })
  cmp_inst.add_use(@abi.Physical({ index: 3, class: Int }))
  cmp_inst.add_use(@abi.Physical({ index: 4, class: Int }))
  block0.add_inst(cmp_inst)
  block0.set_terminator(Branch(@abi.Physical({ index: 8, class: Int }), 1, 2))

  // block1: MOV X0, X3; RET
  let mov1 = @instr.VCodeInst::new(Move)
  mov1.add_def({ reg: @abi.Physical({ index: 0, class: Int }) })
  mov1.add_use(@abi.Physical({ index: 3, class: Int }))
  block1.add_inst(mov1)
  block1.set_terminator(Return([Physical({ index: 0, class: Int })]))

  // block2: MOV X0, X4; RET
  let mov2 = @instr.VCodeInst::new(Move)
  mov2.add_def({ reg: @abi.Physical({ index: 0, class: Int }) })
  mov2.add_use(@abi.Physical({ index: 4, class: Int }))
  block2.add_inst(mov2)
  block2.set_terminator(Return([@abi.Physical({ index: 0, class: Int })]))

  // Show VCode
  inspect(
    func.print(),
    content=(
      #|vcode max() -> int {
      #|block0:
      #|    x8 = cmp.sgt x3, x4
      #|    branch x8, block1, block2
      #|block1:
      #|    x0 = mov x3
      #|    ret x0
      #|block2:
      #|    x0 = mov x4
      #|    ret x0
      #|}
      #|
    ),
  )

  // Emit machine code
  let mc = @emit.emit_function(func)

  // Should have:
  // - prologue (STP, MOV X21, MOV X22, SUB SP)
  // - block0: CMP + CSET + CBNZ + B
  // - block1: MOV + epilogue + RET
  // - block2: MOV + epilogue + RET
  // Total size should be reasonable
  inspect(mc.size() > 0, content="true")

  // Show hex dump for debugging
  let hex = mc.hex_dump()
  inspect(hex.length() > 0, content="true")
}

///|
test "emit: arithmetic operations encoding verification" {
  // Test that arithmetic instructions are encoded correctly
  // by checking specific byte patterns

  let mc = @emit.MachineCode::new()

  // ADD X0, X1, X2 -> 0x8B020020
  mc.emit_add_reg(0, 1, 2)
  inspect(mc.get_bytes()[0], content="32") // 0x20
  inspect(mc.get_bytes()[1], content="0") // 0x00
  inspect(mc.get_bytes()[2], content="2") // 0x02
  inspect(mc.get_bytes()[3], content="139") // 0x8B

  // SUB X3, X4, X5 -> 0xCB050083
  mc.emit_sub_reg(3, 4, 5)
  inspect(mc.get_bytes()[4], content="131") // 0x83
  inspect(mc.get_bytes()[5], content="0") // 0x00
  inspect(mc.get_bytes()[6], content="5") // 0x05
  inspect(mc.get_bytes()[7], content="203") // 0xCB

  // Total: 2 instructions = 8 bytes
  inspect(mc.size(), content="8")
}

///|
test "emit: memory operations with offset" {
  // Test load/store with various offsets

  let mc = @emit.MachineCode::new()

  // LDR X0, [X1, #0]
  mc.emit_ldr_imm(0, 1, 0)
  inspect(mc.size(), content="4")

  // LDR X0, [X1, #8] - offset must be aligned to 8 bytes for X register
  mc.emit_ldr_imm(0, 1, 8)
  inspect(mc.size(), content="8")

  // STR X2, [X3, #16]
  mc.emit_str_imm(2, 3, 16)
  inspect(mc.size(), content="12")

  // LDR W0, [X1, #4] - 32-bit load with 4-byte aligned offset
  mc.emit_ldr_w_imm(0, 1, 4)
  inspect(mc.size(), content="16")

  // STR W2, [X3, #8] - 32-bit store
  mc.emit_str_w_imm(2, 3, 8)
  inspect(mc.size(), content="20")
}

///|
test "emit: float operations encoding" {
  // Test floating-point instruction encoding

  let mc = @emit.MachineCode::new()

  // FADD D0, D1, D2 - double-precision add
  mc.emit_fadd_d(0, 1, 2)
  let bytes = mc.get_bytes()
  inspect(bytes[3], content="30") // 0x1E - FP opcode

  // FMUL D3, D4, D5
  mc.emit_fmul_d(3, 4, 5)
  inspect(mc.size(), content="8")

  // FMOV D0, D1 - FP register move
  mc.emit_fmov_d(0, 1)
  inspect(mc.size(), content="12")

  // LDR D0, [X1, #0] - FP load
  mc.emit_ldr_d_imm(0, 1, 0)
  inspect(mc.size(), content="16")

  // STR D2, [X3, #8] - FP store
  mc.emit_str_d_imm(2, 3, 8)
  inspect(mc.size(), content="20")
}

///|
test "emit: branch fixup forward reference" {
  // Test that forward branch references are correctly resolved

  let mc = @emit.MachineCode::new()

  // block0: B block2 (forward reference)
  mc.define_label(0)
  mc.emit_b(2) // Jump forward to block2

  // block1: NOP
  mc.define_label(1)
  mc.emit_nop()

  // block2: RET
  mc.define_label(2)
  mc.emit_ret(30)

  // Resolve fixups
  mc.resolve_fixups()

  // Check sizes
  inspect(mc.size(), content="12") // 3 instructions

  // The branch at offset 0 should jump over 2 instructions (to offset 8)
  // PC-relative offset = (8 - 0) / 4 = 2
  let bytes = mc.get_bytes()
  // B instruction: imm26 = 2, opcode = 0x14
  // Byte 0 should have low bits of offset
  inspect(bytes[0], content="2") // imm26 low byte = 2
}

///|
test "emit: shifted register operations" {
  // Test AArch64-specific shifted operand instructions

  let mc = @emit.MachineCode::new()

  // ADD X0, X1, X2, LSL #3
  mc.emit_add_shifted(0, 1, 2, Lsl, 3)
  inspect(mc.size(), content="4")

  // SUB X3, X4, X5, LSR #2
  mc.emit_sub_shifted(3, 4, 5, Lsr, 2)
  inspect(mc.size(), content="8")

  // AND X6, X7, X8, ASR #1
  mc.emit_and_shifted(6, 7, 8, Asr, 1)
  inspect(mc.size(), content="12")

  // ORR X9, X10, X11, LSL #4
  mc.emit_orr_shifted(9, 10, 11, Lsl, 4)
  inspect(mc.size(), content="16")

  // EOR X12, X13, X14, LSL #0 (no shift)
  mc.emit_eor_shifted(12, 13, 14, Lsl, 0)
  inspect(mc.size(), content="20")
}

///|
test "emit: multiply-accumulate instructions" {
  // Test MADD, MSUB, MNEG instructions

  let mc = @emit.MachineCode::new()

  // MADD X0, X1, X2, X3 -> X0 = X3 + X1 * X2
  mc.emit_madd(0, 1, 2, 3)
  let bytes = mc.get_bytes()
  inspect(bytes[3], content="155") // 0x9B - MADD opcode
  inspect(mc.size(), content="4")

  // MSUB X4, X5, X6, X7 -> X4 = X7 - X5 * X6
  mc.emit_msub(4, 5, 6, 7)
  inspect(mc.size(), content="8")

  // MNEG X8, X9, X10 -> X8 = -(X9 * X10) = MSUB X8, X9, X10, XZR
  mc.emit_mneg(8, 9, 10)
  inspect(mc.size(), content="12")

  // MUL X11, X12, X13 -> X11 = X12 * X13 = MADD X11, X12, X13, XZR
  mc.emit_mul(11, 12, 13)
  inspect(mc.size(), content="16")
}

///|
test "emit: complete VCode instruction emission" {
  // Test emit_instruction for various VCodeOpcode values

  // Create a simple function to test instruction emission
  let func = @lower.VCodeFunction::new("test_insts")
  func.add_result(Int)
  let block = func.new_block()

  // Add various instructions using physical registers
  // LoadConst
  let ldi = @instr.VCodeInst::new(LoadConst(42L))
  ldi.add_def({ reg: @abi.Physical({ index: 0, class: Int }) })
  block.add_inst(ldi)

  // Add
  let add = @instr.VCodeInst::new(Add(true))
  add.add_def({ reg: @abi.Physical({ index: 1, class: Int }) })
  add.add_use(@abi.Physical({ index: 0, class: Int }))
  add.add_use(@abi.Physical({ index: 0, class: Int }))
  block.add_inst(add)

  // Mul
  let mul = @instr.VCodeInst::new(Mul(true))
  mul.add_def({ reg: @abi.Physical({ index: 2, class: Int }) })
  mul.add_use(@abi.Physical({ index: 1, class: Int }))
  mul.add_use(@abi.Physical({ index: 0, class: Int }))
  block.add_inst(mul)

  // Move
  let mov = @instr.VCodeInst::new(Move)
  mov.add_def({ reg: @abi.Physical({ index: 0, class: Int }) })
  mov.add_use(@abi.Physical({ index: 2, class: Int }))
  block.add_inst(mov)
  block.set_terminator(Return([@abi.Physical({ index: 0, class: Int })]))

  // Show VCode
  inspect(
    func.print(),
    content=(
      #|vcode test_insts() -> int {
      #|block0:
      #|    x0 = ldi 42
      #|    x1 = add x0, x0
      #|    x2 = mul x1, x0
      #|    x0 = mov x2
      #|    ret x0
      #|}
      #|
    ),
  )

  // Emit and verify
  let mc = @emit.emit_function(func)
  inspect(mc.size() > 0, content="true")
}

///|
test "emit_mul encoding verification" {
  // MUL Xd, Xn, Xm = MADD Xd, Xn, Xm, XZR
  // Encoding: sf=1 | 00 | 11011 | 000 | Rm[4:0] | 0 | Ra=11111 | Rn[4:0] | Rd[4:0]
  //
  // MUL X8, X23, X24:
  //   Rd=8 (01000), Rn=23 (10111), Rm=24 (11000), Ra=31 (11111)
  //   Bits 31-0: 1_00_11011_000_11000_0_11111_10111_01000
  //   = 0x9b187ee8
  //   Little endian bytes: e8 7e 18 9b

  let mc = @emit.MachineCode::new()
  mc.emit_mul(8, 23, 24)
  let bytes = mc.get_bytes()
  inspect(bytes.length(), content="4")
  inspect(bytes[0], content="232")
  inspect(bytes[1], content="126")
  inspect(bytes[2], content="24")
  inspect(bytes[3], content="155")
}

///|
test "emit: memory_grow instruction disasm" {
  // Test MemoryGrow instruction emission with disassembly dump
  // This verifies that annotations are not duplicated
  let func = @lower.VCodeFunction::new("test_memory_grow")
  func.add_param(Int) |> ignore // delta
  func.add_result(Int) // returns previous size
  let block = func.new_block()

  // MemoryGrow(max_pages)
  let grow_inst = @instr.VCodeInst::new(MemoryGrow(65536))
  grow_inst.add_def({ reg: @abi.Physical({ index: 0, class: Int }) })
  grow_inst.add_use(@abi.Physical({ index: 3, class: Int })) // delta in X3
  block.add_inst(grow_inst)
  block.set_terminator(Return([@abi.Physical({ index: 0, class: Int })]))
  let mc = @emit.emit_function(func)
  let disasm = mc.dump_disasm()

  // Should NOT have duplicate "blr x16" annotations
  // Count occurrences of "blr x16" - should be exactly 1
  let mut blr_count = 0
  let lines = disasm.split("\n")
  for line in lines {
    if line.contains("blr x16") {
      blr_count = blr_count + 1
    }
  }
  // If there are duplicate annotations, this will fail
  inspect(blr_count, content="1")
}

///|
test "emit: memory_size instruction disasm" {
  // Test MemorySize instruction emission
  let func = @lower.VCodeFunction::new("test_memory_size")
  func.add_result(Int)
  let block = func.new_block()
  let size_inst = @instr.VCodeInst::new(MemorySize)
  size_inst.add_def({ reg: @abi.Physical({ index: 0, class: Int }) })
  block.add_inst(size_inst)
  block.set_terminator(Return([@abi.Physical({ index: 0, class: Int })]))
  let mc = @emit.emit_function(func)
  let disasm = mc.dump_disasm()

  // Count "blr x16" - should be exactly 1
  let mut blr_count = 0
  let lines = disasm.split("\n")
  for line in lines {
    if line.contains("blr x16") {
      blr_count = blr_count + 1
    }
  }
  inspect(blr_count, content="1")
}

///|
test "emit: memory_fill instruction disasm" {
  // Test MemoryFill instruction emission
  let func = @lower.VCodeFunction::new("test_memory_fill")
  let block = func.new_block()
  let fill_inst = @instr.VCodeInst::new(MemoryFill)
  fill_inst.add_use(@abi.Physical({ index: 3, class: Int })) // dst
  fill_inst.add_use(@abi.Physical({ index: 4, class: Int })) // val
  fill_inst.add_use(@abi.Physical({ index: 5, class: Int })) // size
  block.add_inst(fill_inst)
  block.set_terminator(Return([]))
  let mc = @emit.emit_function(func)
  let disasm = mc.dump_disasm()

  // Count "blr x16" - should be exactly 1
  let mut blr_count = 0
  let lines = disasm.split("\n")
  for line in lines {
    if line.contains("blr x16") {
      blr_count = blr_count + 1
    }
  }
  inspect(blr_count, content="1")
}

///|
test "emit: memory_copy instruction disasm" {
  // Test MemoryCopy instruction emission
  let func = @lower.VCodeFunction::new("test_memory_copy")
  let block = func.new_block()
  let copy_inst = @instr.VCodeInst::new(MemoryCopy)
  copy_inst.add_use(@abi.Physical({ index: 3, class: Int })) // dst
  copy_inst.add_use(@abi.Physical({ index: 4, class: Int })) // src
  copy_inst.add_use(@abi.Physical({ index: 5, class: Int })) // size
  block.add_inst(copy_inst)
  block.set_terminator(Return([]))
  let mc = @emit.emit_function(func)
  let disasm = mc.dump_disasm()

  // Count "blr x16" - should be exactly 1
  let mut blr_count = 0
  let lines = disasm.split("\n")
  for line in lines {
    if line.contains("blr x16") {
      blr_count = blr_count + 1
    }
  }
  inspect(blr_count, content="1")
}
