///|
test "shift/rotate immediate disasm" {
  let mc = MachineCode::new()

  // 64-bit immediate forms
  mc.emit_lsl_imm(0, 1, 3)
  mc.emit_lsr_imm(2, 3, 5)
  mc.emit_asr_imm(4, 5, 7)
  mc.emit_ror_imm(6, 7, 11)

  // 32-bit immediate forms
  mc.emit_lsl_imm32(8, 9, 3)
  mc.emit_lsr_imm32(10, 11, 5)
  mc.emit_asr_imm32(12, 13, 7)
  mc.emit_ror_imm32(14, 15, 11)
  mc.resolve_fixups()
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: 20f07dd3  lsl x0, x1, #3
      #|  0004: 62fc45d3  lsr x2, x3, #5
      #|  0008: a4fc4793  asr x4, x5, #7
      #|  000c: e62cc793  ror x6, x7, #11
      #|  0010: 28711d53  lsl w8, w9, #3
      #|  0014: 6a7d0553  lsr w10, w11, #5
      #|  0018: ac7d0713  asr w12, w13, #7
      #|  001c: ee2d8f13  ror w14, w15, #11
      #|
    ),
  )
}
