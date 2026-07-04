///|
test "AArch64 target owns ABI policy" {
  let abi = abi_policy()
  inspect(abi.pointer_size, content="8")
  inspect(abi.stack_alignment, content="16")
  inspect(abi.int_argument_regs.length(), content="8")
  inspect(abi.float_argument_regs.length(), content="8")
}

///|
test "AArch64 lowers MilkIR arithmetic into MachV" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let func = @milkir.Function::new("add64", signature)
  let lhs = func.new_value(I64)
  let rhs = func.new_value(I64)
  let sum = func.new_value(I64)
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(Iadd, [lhs, rhs], [sum]))
  entry.set_terminator(Return([sum]))
  let lowered = lower_function(func)
  inspect(lowered.blocks.length(), content="1")
  inspect(lowered.blocks[0].instructions.length(), content="2")
  inspect(
    lowered.blocks[0].instructions[0].opcode == Target("aarch64.iadd"),
    content="true",
  )
  inspect(lowered.blocks[0].instructions[1].opcode == Return, content="true")
  inspect(lowered.verify(), content="()")
}
