///|
test "public layout edits preserve instruction identity and definitions" {
  let func = @milkir.Function::new_empty("relocate")
  func.add_result(I32)
  let entry = func.new_block0()
  let exit = func.new_block0()
  let value = func.new_value(I32)
  let inst = func.new_inst(Scalar(IntConst(42L)), [], [value])
  entry.append_inst(inst)
  entry.set_terminator(Jump(exit.id, []))
  exit.set_terminator(Return([value]))
  inspect(func.defining_inst(value).unwrap().id, content="0")
  inspect(func.instruction_by_id(0).unwrap().id, content="0")
  debug_inspect(entry.instruction_ids(), content="<ArrayView: [0]>")
  inspect(entry.take_inst_at(0).unwrap(), content="0")
  exit.append_inst(inst)
  debug_inspect(entry.instruction_ids(), content="<ArrayView: []>")
  debug_inspect(exit.instruction_ids(), content="<ArrayView: [0]>")
  inspect(func.defining_inst(value).unwrap().id, content="0")
  inst.set_opcode(Scalar(IntConst(43L)))
  debug_inspect(
    func.defining_inst(value).unwrap().opcode,
    content="Scalar(IntConst(43))",
  )
  func.verify()
}

///|
test "public discard handles unplaced candidates and rejects placed ones" {
  let func = @milkir.Function::new_empty("discard_candidate")
  let entry = func.new_block0()
  entry.set_terminator(Return([]))
  let candidate = func.new_inst(Scalar(IntConst(1L)), [], [func.new_value(I32)])
  func.discard_inst(candidate)
  func.verify()
  let next = func.new_inst(Scalar(IntConst(2L)), [], [func.new_value(I32)])
  inspect(next.id, content="1")
  entry.append_inst(next)
  func.discard_inst(next)
  try func.verify() catch {
    error =>
      debug_inspect(error, content="InstructionPlacementMismatch(inst_id=1)")
  } noraise {
    _ =>
      fail("discarding a placed instruction must not hide it from verification")
  }
}

///|
test "public discard rejects a foreign instruction without deleting owned IDs" {
  let owned = @milkir.Function::new_empty("owned")
  let foreign = @milkir.Function::new_empty("foreign")
  let entry = owned.new_block0()
  entry.set_terminator(Return([]))
  let local_inst = owned.new_inst(Scalar(IntConst(1L)), [], [
    owned.new_value(I32),
  ])
  entry.append_inst(local_inst)
  let foreign_inst = foreign.new_inst(Scalar(IntConst(2L)), [], [
    foreign.new_value(I32),
  ])
  owned.discard_inst(foreign_inst)
  debug_inspect(
    owned.instruction_by_id(0).unwrap().opcode,
    content="Scalar(IntConst(1))",
  )
  debug_inspect(entry.instruction_ids(), content="<ArrayView: [0]>")
  try owned.verify() catch {
    error => debug_inspect(error, content="ForeignInstruction(inst_id=0)")
  } noraise {
    _ => fail("expected foreign instruction rejection")
  }
}

///|
test "public opcode replacement rejects foreign global values atomically" {
  let owned = @milkir.Function::new_empty("owned")
  let foreign = @milkir.Function::new_empty("foreign")
  let global = foreign.declare_global_value(
    @milkir.GlobalValueData::context_field(
      @milkir.ContextField::new("test", 0, [], I32),
      Stable,
      Context,
    ),
  )
  let entry = owned.new_block0()
  let inst = owned.new_inst(Scalar(IntConst(1L)), [], [owned.new_value(I32)])
  entry.append_inst(inst)
  entry.set_terminator(Return([]))
  inst.set_opcode(GlobalValue(global))
  debug_inspect(inst.opcode, content="Scalar(IntConst(1))")
  try owned.verify() catch {
    error =>
      debug_inspect(error, content="ForeignGlobalValue(global_value_id=0)")
  } noraise {
    _ => fail("expected foreign global rejection")
  }
}

///|
test "public layout replacement rejects foreign instructions atomically" {
  let owned = @milkir.Function::new_empty("owned")
  let foreign = @milkir.Function::new_empty("foreign")
  let entry = owned.new_block0()
  let inst = owned.new_inst(Scalar(IntConst(1L)), [], [owned.new_value(I32)])
  entry.append_inst(inst)
  entry.set_terminator(Return([]))
  let other = foreign.new_inst(Scalar(IntConst(2L)), [], [
    foreign.new_value(I32),
  ])
  entry.set_instructions([other])
  debug_inspect(entry.instruction_ids(), content="<ArrayView: [0]>")
  debug_inspect(
    owned.block_instruction_at(entry, 0).unwrap().opcode,
    content="Scalar(IntConst(1))",
  )
  try owned.verify() catch {
    error => debug_inspect(error, content="ForeignInstruction(inst_id=0)")
  } noraise {
    _ => fail("expected foreign layout rejection")
  }
}

///|
test "public layout replacement never infers deletion from layout length" {
  for replacement_count in [0, 1, 2] {
    let func = @milkir.Function::new_empty("replace_layout")
    let entry = func.new_block0()
    let old = func.new_inst(Scalar(IntConst(1L)), [], [func.new_value(I32)])
    entry.append_inst(old)
    entry.set_terminator(Return([]))
    let replacements = Array::makei(replacement_count, i => {
      func.new_inst(Scalar(IntConst(i.to_int64())), [], [func.new_value(I32)])
    })
    entry.set_instructions(replacements)
    try func.verify() catch {
      error => debug_inspect(error, content="UnplacedInstruction(inst_id=0)")
    } noraise {
      _ =>
        fail("omitted instructions must require explicit discard or relocation")
    }
    func.discard_inst(old)
    func.verify()
  }
}
