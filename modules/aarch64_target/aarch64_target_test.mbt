///|
test "AArch64 target owns ABI policy" {
  let abi = abi_policy()
  inspect(abi.pointer_size, content="8")
  inspect(abi.stack_alignment, content="16")
  inspect(abi.int_argument_regs.length(), content="8")
  inspect(abi.float_argument_regs.length(), content="8")
}

///|
test "AArch64 allocatable regs include floating point registers" {
  let regs = allocatable_regs()
  inspect(regs.any(fn(r) { r.class == Float64 }), content="true")
  inspect(regs.any(fn(r) { r.class == Vector }), content="true")
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
  inspect(lowered.blocks[0].instructions.length(), content="1")
  inspect(lowered.blocks[0].instructions[0].opcode == IntAdd, content="true")
  inspect(lowered.blocks[0].terminator is Some(TermReturn(_)), content="true")
  inspect(lowered.verify(), content="()")
}

///|
test "AArch64 lowers extended MilkIR ops into structured MachV opcodes" {
  let func = @milkir.Function::new_empty("extended")
  let lhs = func.new_value(I64)
  let rhs = func.new_value(I64)
  let bits = func.new_value(I64)
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(Band, [lhs, rhs], [bits]))
  entry.append_inst(func.new_inst(Ushr, [bits, rhs], [func.new_value(I64)]))
  entry.append_inst(
    func.new_inst(Fsqrt, [func.new_value(F64)], [func.new_value(F64)]),
  )
  entry.set_terminator(Return([]))
  let lowered = lower_function(func)
  inspect(lowered.blocks[0].instructions[0].opcode == IntAnd, content="true")
  inspect(
    lowered.blocks[0].instructions[1].opcode == IntShr(false),
    content="true",
  )
  inspect(lowered.blocks[0].instructions[2].opcode == FloatSqrt, content="true")
}

///|
test "AArch64 lowers integer remainder to generic arithmetic sequence" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let func = @milkir.Function::new("rem64", signature)
  let lhs = func.new_value(I64)
  let rhs = func.new_value(I64)
  let rem = func.new_value(I64)
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(Urem, [lhs, rhs], [rem]))
  entry.set_terminator(Return([rem]))
  let lowered = lower_function(func)
  inspect(lowered.blocks[0].instructions.length(), content="3")
  inspect(
    lowered.blocks[0].instructions[0].opcode == IntDiv(false),
    content="true",
  )
  inspect(lowered.blocks[0].instructions[1].opcode == IntMul, content="true")
  inspect(lowered.blocks[0].instructions[2].opcode == IntSub, content="true")
}

///|
test "AArch64 lowers integer bitcount ops into structured MachV opcodes" {
  let func = @milkir.Function::new_empty("bitcount")
  let value = func.new_value(I64)
  let leading = func.new_value(I64)
  let trailing = func.new_value(I64)
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(Clz, [value], [leading]))
  entry.append_inst(func.new_inst(Ctz, [value], [trailing]))
  entry.set_terminator(Return([leading, trailing]))
  let lowered = lower_function(func)
  inspect(lowered.blocks[0].instructions[0].opcode == IntClz, content="true")
  inspect(lowered.blocks[0].instructions[1].opcode == IntCtz, content="true")
}

///|
test "AArch64 folds constant pointer offsets into MachV memory opcodes" {
  let builder = @milkir.IRBuilder::new("mem")
  let ptr = builder.add_param(Ptr)
  builder.add_result(I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let load_offset = builder.iconst_i64(4L)
  let loaded = builder.load_ptr(I32, ptr, load_offset)
  let store_offset = builder.iconst_i64(16L)
  builder.store_ptr(I64, ptr, builder.iconst_i64(99L), store_offset)
  builder.return_([loaded])
  let lowered = lower_function(builder.get_function())
  inspect(
    lowered.blocks[0].instructions[1].opcode == LoadPtr(MemI32, 4),
    content="true",
  )
  inspect(lowered.blocks[0].instructions[1].operands.length(), content="2")
  inspect(
    lowered.blocks[0].instructions[4].opcode == StorePtr(MemI64, 16),
    content="true",
  )
  inspect(lowered.blocks[0].instructions[4].operands.length(), content="2")
}

///|
test "AArch64 lowers direct calls with AAPCS64 ABI constraints" {
  let func = @milkir.Function::new_empty("call")
  let int0 = func.new_value(I64)
  let float0 = func.new_value(F64)
  let int1 = func.new_value(I64)
  let result0 = func.new_value(I64)
  let result1 = func.new_value(F64)
  let entry = func.new_block([])
  entry.append_inst(
    func.new_inst(
      Call(@milkir.ExternalSymbol::new("callee")),
      [int0, float0, int1],
      [result0, result1],
    ),
  )
  entry.set_terminator(Return([result0, result1]))
  let lowered = lower_function(func)
  let call = lowered.blocks[0].instructions[0]
  inspect(call.opcode == Call("callee"), content="true")
  inspect(call.constraints.length(), content="5")
  inspect(
    call.constraints[0].allowed_regs[0] == { index: 0, class: Int },
    content="true",
  )
  inspect(
    call.constraints[1].allowed_regs[0] == { index: 0, class: Float64 },
    content="true",
  )
  inspect(
    call.constraints[2].allowed_regs[0] == { index: 1, class: Int },
    content="true",
  )
  inspect(
    call.constraints[3].allowed_regs[0] == { index: 0, class: Int },
    content="true",
  )
  inspect(
    call.constraints[4].allowed_regs[0] == { index: 0, class: Float64 },
    content="true",
  )
  inspect(call.clobbers.length() > 0, content="true")
}
