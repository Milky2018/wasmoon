///|
test "verify rejects duplicate value definitions" {
  let func = Function::new_empty("duplicate_value")
  let original = func.add_param(I32)
  let duplicate = Value::new(func.owner, original.id, I32)
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(Scalar(IntConst(1L)), [], [duplicate]))
  entry.set_terminator(Return([]))
  try func.verify() catch {
    err => inspect(err, content="DuplicateValueDefinition(value_id=0)")
  } noraise {
    _ => fail("expected duplicate value definition")
  }
}

///|
test "verify rejects duplicate instruction ids" {
  let func = Function::new_empty("duplicate_instruction")
  let symbol = func.declare_external_symbol("effect")
  let entry = func.new_block([])
  let inst = func.new_inst(Call(Direct(symbol, Signature([], []))), [], [])
  entry.append_inst(inst)
  entry.append_inst(inst)
  entry.set_terminator(Return([]))
  try func.verify() catch {
    err => inspect(err, content="DuplicateInstructionId(inst_id=0)")
  } noraise {
    _ => fail("expected duplicate instruction id")
  }
}

///|
test "verify rejects same-block use before definition" {
  let func = Function::new_empty("use_before_definition")
  let defined_later = func.new_value(I32)
  let copied = func.new_value(I32)
  let entry = func.new_block([])
  entry.append_inst(func.new_inst(Scalar(Copy), [defined_later], [copied]))
  entry.append_inst(func.new_inst(Scalar(IntConst(1L)), [], [defined_later]))
  entry.set_terminator(Return([]))
  try func.verify() catch {
    err => inspect(err, content="UseBeforeDefinition(value_id=0)")
  } noraise {
    _ => fail("expected use before definition")
  }
}

///|
test "verify rejects cross-block non-dominating uses" {
  let func = Function::new_empty("non_dominating_use")
  let cond = func.add_param(I32)
  let defined_on_left = func.new_value(I32)
  let copied_on_right = func.new_value(I32)
  let entry = func.new_block([])
  let left = func.new_block([])
  let right = func.new_block([])
  entry.set_terminator(Branch(cond, left.id, [], right.id, []))
  left.append_inst(func.new_inst(Scalar(IntConst(1L)), [], [defined_on_left]))
  left.set_terminator(Return([]))
  right.append_inst(
    func.new_inst(Scalar(Copy), [defined_on_left], [copied_on_right]),
  )
  right.set_terminator(Return([]))
  try func.verify() catch {
    err =>
      inspect(
        err,
        content=(
          #|NonDominatingUse(value_id=1, defining_block=1, use_block=2)
        ),
      )
  } noraise {
    _ => fail("expected non-dominating use")
  }
}

///|
test "verify accepts function and dominating block parameters" {
  let func = Function::new_empty("parameter_dominance")
  let argument = func.add_param(I32)
  func.add_result(I32)
  let entry = func.new_block([])
  let block_param = func.new_value(I32)
  let target = func.new_block([block_param])
  entry.set_terminator(Jump(target.id, [argument]))
  target.set_terminator(Return([block_param]))
  inspect(func.verify(), content="()")
}

///|
test "verify rejects divergent instruction operand views" {
  let func = Function::new_empty("divergent_operands")
  let argument = func.add_param(I32)
  let copied = func.new_value(I32)
  let entry = func.new_block([])
  let malformed : Inst = {
    owner: func.owner,
    id: 0,
    results: [copied],
    opcode: Scalar(Copy),
    args: [argument],
    operands: [],
    metadata: [],
  }
  entry.append_inst(malformed)
  entry.set_terminator(Return([]))
  try func.verify() catch {
    err => inspect(err, content="InstructionOperandMismatch(inst_id=0)")
  } noraise {
    _ => fail("expected divergent instruction operands")
  }
}
