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
  inspect(second.current_block().instructions.length(), content="0")
  try second.get_function().verify() catch {
    err => inspect(err, content="ForeignValue(value_id=0)")
  } noraise {
    _ => fail("expected a foreign value error")
  }
}

///|
test "verify rejects a foreign value despite matching id and type" {
  let first = Function::new_empty("first")
  let foreign = first.add_param(I32)
  let second = Function::new_empty("second")
  let own_value = second.add_param(I32)
  second.add_result(I32)
  let result = second.new_value(I32)
  let entry = second.new_block([])
  entry.append_inst(
    second.new_inst(
      Scalar(ScalarOp::IntBinary(IntBinaryOp::Add)),
      [foreign, own_value],
      [result],
    ),
  )
  entry.set_terminator(Return([result]))
  try second.verify() catch {
    _ => ()
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
test "verify rejects an instruction owned by another function" {
  let first = Function::new_empty("first")
  let symbol = first.declare_external_symbol("foreign")
  let foreign = first.new_inst(
    Call(CallOp::Direct(symbol, Signature([], []))),
    [],
    [],
  )
  let second = Function::new_empty("second")
  let entry = second.new_block([])
  entry.append_inst(foreign)
  entry.set_terminator(Return([]))
  try second.verify() catch {
    err => inspect(err, content="ForeignInstruction(inst_id=0)")
  } noraise {
    _ => fail("expected a foreign instruction error")
  }
}
