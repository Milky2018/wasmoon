///|
test "builder rejects a block owned by another function" {
  let first = FunctionBuilder::FunctionBuilder("first")
  let second = FunctionBuilder::FunctionBuilder("second")
  let own_block = first.current_block()
  first.switch_to_block(second.current_block())
  inspect(physical_equal(first.current_block(), own_block), content="true")
  try first.get_function().verify() catch {
    err => inspect(err, content="ForeignBlock(block_id=0)")
  } noraise {
    _ => fail("expected a foreign block error")
  }
}

///|
test "builder rejects a value owned by another function" {
  let first = FunctionBuilder::FunctionBuilder("first")
  let foreign = first.add_param(I32)
  let second = FunctionBuilder::FunctionBuilder("second")
  let own_value = second.add_param(I32)
  second.iadd(foreign, own_value) |> ignore
  inspect(second.current_block().instruction_count(), content="0")
  try second.get_function().verify() catch {
    err => inspect(err, content="ForeignValue(value_id=0)")
  } noraise {
    _ => fail("expected a foreign value error")
  }
}

///|
test "function rejects foreign block parameters before mutation" {
  let first = Function::new_empty("first")
  let foreign = first.add_param(I32)
  let second = Function::new_empty("second")
  let own = second.add_param(I32)
  let rejected = second.new_block([own, foreign])
  inspect(second.blocks.length(), content="0")
  inspect(rejected.params.length(), content="0")
  let entry = second.new_block([])
  inspect(entry.id, content="0")
  entry.set_terminator(Return([]))
  try second.verify() catch {
    err => inspect(err, content="ForeignValue(value_id=0)")
  } noraise {
    _ => fail("expected a foreign value error")
  }
}

///|
test "block parameter mutation rejects a foreign value" {
  let first = Function::new_empty("first")
  let foreign = first.add_param(I32)
  let second = Function::new_empty("second")
  let detached = Block(second.owner, 0)
  detached.add_param(foreign, I32)
  inspect(detached.params.length(), content="0")
  let entry = second.new_block([])
  entry.set_terminator(Return([]))
  try second.verify() catch {
    err => inspect(err, content="ForeignValue(value_id=0)")
  } noraise {
    _ => fail("expected a foreign value error")
  }
}

///|
test "function rejects foreign instruction arguments before ID allocation" {
  let first = Function::new_empty("first")
  let foreign = first.add_param(I32)
  let second = Function::new_empty("second")
  let result = second.new_value(I32)
  let rejected = second.new_inst(Scalar(Copy), [foreign], [result])
  inspect(rejected.args.length(), content="0")
  inspect(rejected.results.length(), content="0")
  let valid = second.new_inst(Scalar(IntConst(1L)), [], [result])
  inspect(valid.id, content="0")
  let entry = second.new_block([])
  entry.append_inst(valid)
  entry.set_terminator(Return([]))
  try second.verify() catch {
    err => inspect(err, content="ForeignValue(value_id=0)")
  } noraise {
    _ => fail("expected a foreign value error")
  }
}

///|
test "function rejects foreign instruction results before ID allocation" {
  let first = Function::new_empty("first")
  let foreign = first.new_value(I32)
  let second = Function::new_empty("second")
  let rejected = second.new_inst(Scalar(IntConst(1L)), [], [foreign])
  inspect(rejected.args.length(), content="0")
  inspect(rejected.results.length(), content="0")
  let result = second.new_value(I32)
  let valid = second.new_inst(Scalar(IntConst(1L)), [], [result])
  inspect(valid.id, content="0")
  let entry = second.new_block([])
  entry.append_inst(valid)
  entry.set_terminator(Return([]))
  try second.verify() catch {
    err => inspect(err, content="ForeignValue(value_id=0)")
  } noraise {
    _ => fail("expected a foreign value error")
  }
}

///|
test "block rejects a terminator with foreign values" {
  let first = Function::new_empty("first")
  let foreign = first.add_param(I32)
  let second = Function::new_empty("second")
  let entry = second.new_block([])
  entry.set_terminator(Trap("original"))
  entry.set_terminator(Return([foreign]))
  inspect(entry.terminator is Some(Trap("original")), content="true")
  try second.verify() catch {
    err => inspect(err, content="ForeignValue(value_id=0)")
  } noraise {
    _ => fail("expected a foreign value error")
  }
}

///|
test "block rejects an instruction with a foreign argument" {
  let first = Function::new_empty("first")
  let foreign = first.add_param(I32)
  let second = Function::new_empty("second")
  let own_value = second.add_param(I32)
  let result = second.new_value(I32)
  let entry = second.new_block([])
  let inst : Inst = {
    owner: second.owner,
    id: 0,
    results: [result],
    opcode: Scalar(IntBinary(Add)),
    args: [foreign, own_value],
    operands: [own_value, own_value],
    metadata: [],
  }
  entry.append_inst(inst)
  inspect(entry.instruction_count(), content="0")
  entry.set_terminator(Return([]))
  try second.verify() catch {
    err => inspect(err, content="ForeignValue(value_id=0)")
  } noraise {
    _ => fail("expected a foreign value error")
  }
}

///|
test "block rejects an instruction with a foreign operand" {
  let first = Function::new_empty("first")
  let foreign = first.add_param(I32)
  let second = Function::new_empty("second")
  let own_value = second.add_param(I32)
  let result = second.new_value(I32)
  let entry = second.new_block([])
  let inst : Inst = {
    owner: second.owner,
    id: 0,
    results: [result],
    opcode: Scalar(IntBinary(Add)),
    args: [own_value, own_value],
    operands: [foreign, own_value],
    metadata: [],
  }
  entry.append_inst(inst)
  inspect(entry.instruction_count(), content="0")
  entry.set_terminator(Return([]))
  try second.verify() catch {
    err => inspect(err, content="ForeignValue(value_id=0)")
  } noraise {
    _ => fail("expected a foreign value error")
  }
}

///|
test "block rejects an instruction with a foreign result" {
  let first = Function::new_empty("first")
  let foreign = first.new_value(I32)
  let second = Function::new_empty("second")
  let entry = second.new_block([])
  let inst : Inst = {
    owner: second.owner,
    id: 0,
    results: [foreign],
    opcode: Scalar(IntConst(1L)),
    args: [],
    operands: [],
    metadata: [],
  }
  entry.append_inst(inst)
  inspect(entry.instruction_count(), content="0")
  entry.set_terminator(Return([]))
  try second.verify() catch {
    err => inspect(err, content="ForeignValue(value_id=0)")
  } noraise {
    _ => fail("expected a foreign value error")
  }
}

///|
test "verify rejects a block owned by another function" {
  let first = Function::new_empty("first")
  let foreign = first.new_block([])
  foreign.set_terminator(Return([]))
  let second = Function::new_empty("second")
  second.blocks.push(foreign)
  try second.verify() catch {
    _ => ()
  } noraise {
    _ => fail("expected a foreign block error")
  }
}

///|
test "block rejects an instruction owned by another function" {
  let first = Function::new_empty("first")
  let symbol = first.declare_external_symbol("foreign")
  let foreign = first.new_inst(Call(Direct(symbol, Signature([], []))), [], [])
  let second = Function::new_empty("second")
  let entry = second.new_block([])
  entry.append_inst(foreign)
  inspect(entry.instruction_count(), content="0")
  entry.set_terminator(Return([]))
  try second.verify() catch {
    err => inspect(err, content="ForeignInstruction(inst_id=0)")
  } noraise {
    _ => fail("expected a foreign instruction error")
  }
}
