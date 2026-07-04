///|
test "project and allocate MachV function" {
  let func = @machv.Function::new("copy")
  let entry = func.new_block()
  let v0 = func.new_vreg(Int)
  let v1 = func.new_vreg(Int)
  let mov = func.new_inst(Move)
  mov.add_operand(@machv.Operand::def(Virtual(v0)))
  mov.add_operand(@machv.Operand::use_reg(Virtual(v1)))
  entry.append(mov)
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  let allocation = allocate_function(func, [p0, p1])
  inspect(allocation.spill_count, content="0")
  inspect(allocation.assignments.length(), content="2")
}

///|
test "apply materializes MachV spill slots" {
  let func = @machv.Function::new("spill")
  let entry = func.new_block()
  let v0 = func.new_vreg(Int)
  let v1 = func.new_vreg(Int)
  let inst = func.new_inst(Target("pair"))
  inst.add_operand(@machv.Operand::def(Virtual(v0)))
  inst.add_operand(@machv.Operand::def(Virtual(v1)))
  entry.append(inst)
  let p0 : @machv.PReg = { index: 0, class: Int }
  let result = allocate_and_apply(func, [p0])
  inspect(result.allocation.spill_count, content="1")
  inspect(result.spill_slots.length(), content="1")
  inspect(func.stack_slots.length(), content="1")
}

///|
test "apply rewrites allocated virtual operands to physical registers" {
  let func = @machv.Function::new("rewrite")
  let entry = func.new_block()
  let v0 = func.new_vreg(Int)
  let v1 = func.new_vreg(Int)
  let inst = func.new_inst(Move)
  inst.add_operand(@machv.Operand::def(Virtual(v0)))
  inst.add_operand(@machv.Operand::use_reg(Virtual(v1)))
  entry.append(inst)
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  allocate_and_apply(func, [p0, p1]) |> ignore
  inspect(entry.instructions[0].operands[0].reg is Physical(_), content="true")
  inspect(entry.instructions[0].operands[1].reg is Physical(_), content="true")
}
