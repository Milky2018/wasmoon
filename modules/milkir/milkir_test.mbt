///|
test "build and verify minimal MilkIR function" {
  let signature = Signature::new([I32, I32], [I32])
  let func = Function::new("add", signature)
  let lhs = func.new_value(I32)
  let rhs = func.new_value(I32)
  let sum = func.new_value(I32)
  let entry = func.new_block([])
  let add = func.new_inst(Iadd, [lhs, rhs], [sum])
  add.add_metadata(Comment("lowered from frontend add"))
  entry.append_inst(add)
  entry.set_terminator(Return([sum]))
  inspect(func.blocks.length(), content="1")
  inspect(entry.instructions.length(), content="1")
  inspect(func.verify(), content="()")
}

///|
test "verify catches missing terminator" {
  let func = Function::new("bad", Signature::new([], []))
  func.new_block([]) |> ignore
  try func.verify() catch {
    err => inspect(err, content="MissingTerminator(block_id=0)")
  } noraise {
    _ => fail("expected missing terminator")
  }
}
