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
test "apply materializes aligned vector spill slots" {
  let func = @machv.Function::new("vector_spill")
  let entry = func.new_block()
  let v0 = func.new_vreg(Vector)
  let v1 = func.new_vreg(Vector)
  let inst = func.new_inst(Target("vector_pair"))
  inst.add_operand(@machv.Operand::def(Virtual(v0)))
  inst.add_operand(@machv.Operand::def(Virtual(v1)))
  entry.append(inst)
  let p0 : @machv.PReg = { index: 0, class: Vector }
  let result = allocate_and_apply(func, [p0])
  inspect(result.allocation.spill_count, content="1")
  inspect(result.spill_slots[0].size, content="16")
  inspect(result.spill_slots[0].align, content="16")
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

///|
test "apply preserves MachV float width classes when rewriting operands" {
  let func = @machv.Function::new("float_width")
  let entry = func.new_block()
  let f32_value = func.new_vreg(Float32)
  let f64_value = func.new_vreg(Float64)
  let inst = func.new_inst(Fpromote)
  inst.add_operand(@machv.Operand::use_reg(Virtual(f32_value)))
  inst.add_operand(@machv.Operand::def(Virtual(f64_value)))
  entry.append(inst)
  let f0_32 : @machv.PReg = { index: 0, class: Float32 }
  let f0_64 : @machv.PReg = { index: 0, class: Float64 }
  let f1_32 : @machv.PReg = { index: 1, class: Float32 }
  let f1_64 : @machv.PReg = { index: 1, class: Float64 }
  allocate_and_apply(func, [f0_32, f0_64, f1_32, f1_64]) |> ignore
  inspect(
    entry.instructions[0].operands[0].reg is Physical({ class: Float32, .. }),
    content="true",
  )
  inspect(
    entry.instructions[0].operands[1].reg is Physical({ class: Float64, .. }),
    content="true",
  )
}

///|
test "projected MachV constraints guide fixed register allocation" {
  let func = @machv.Function::new("fixed")
  let entry = func.new_block()
  let v0 = func.new_vreg(Int)
  let inst = func.new_inst(Target("fixed_def"))
  inst.add_operand(@machv.Operand::def(Virtual(v0)))
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  inst.add_constraint({ operand_index: 0, allowed_regs: [p1] })
  entry.append(inst)
  let allocation = allocate_function(func, [p0, p1])
  inspect(
    allocation.location_of({ id: v0.id, class: Int }) ==
    Some(Reg({ id: 1, class: Int })),
    content="true",
  )
}

///|
test "projected MachV ties co-locate use-def operands" {
  let func = @machv.Function::new("tied")
  let entry = func.new_block()
  let v0 = func.new_vreg(Int)
  let v1 = func.new_vreg(Int)
  let def_inst = func.new_inst(Target("def"))
  def_inst.add_operand(@machv.Operand::def(Virtual(v0)))
  entry.append(def_inst)
  let tied_inst = func.new_inst(Target("tied"))
  tied_inst.add_operand(@machv.Operand::use_reg(Virtual(v0)).with_tie(0))
  tied_inst.add_operand(@machv.Operand::def(Virtual(v1)).with_tie(0))
  entry.append(tied_inst)
  let use_inst = func.new_inst(Target("use"))
  use_inst.add_operand(@machv.Operand::use_reg(Virtual(v1)))
  entry.append(use_inst)
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  let allocation = allocate_function(func, [p0, p1])
  inspect(
    allocation.location_of({ id: v0.id, class: Int }) ==
    allocation.location_of({ id: v1.id, class: Int }),
    content="true",
  )
  allocate_and_apply(func, [p0, p1]) |> ignore
  inspect(entry.instructions[1].operands[0].reg, content="x0")
  inspect(entry.instructions[1].operands[1].reg, content="x0")
}

///|
test "allocate_function rejects unsatisfied projected fixed constraint" {
  let func = @machv.Function::new("fixed_reject")
  let entry = func.new_block()
  let v0 = func.new_vreg(Int)
  let inst = func.new_inst(Target("fixed_def"))
  inst.add_operand(@machv.Operand::def(Virtual(v0)))
  inst.add_constraint({
    operand_index: 0,
    allowed_regs: [{ index: 1, class: Int }],
  })
  entry.append(inst)
  let p0 : @machv.PReg = { index: 0, class: Int }
  try allocate_function(func, [p0]) catch {
    FixedConstraintViolation(_) => inspect("fixed", content="fixed")
    _ => fail("unexpected verifier error")
  } noraise {
    _ => fail("expected fixed constraint violation")
  }
}

///|
test "allocate_function avoids projected clobbered registers" {
  let func = @machv.Function::new("clobber")
  let entry = func.new_block()
  let v0 = func.new_vreg(Int)
  let def_inst = func.new_inst(Target("def"))
  def_inst.add_operand(@machv.Operand::def(Virtual(v0)))
  entry.append(def_inst)
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  let call_inst = func.new_inst(Target("call"))
  call_inst.add_clobber(p0)
  entry.append(call_inst)
  let use_inst = func.new_inst(Target("use"))
  use_inst.add_operand(@machv.Operand::use_reg(Virtual(v0)))
  entry.append(use_inst)
  let allocation = allocate_function(func, [p0, p1])
  inspect(
    allocation.location_of({ id: v0.id, class: Int }) ==
    Some(Reg({ id: 1, class: Int })),
    content="true",
  )
}

///|
test "projected MachV terminator return keeps result live" {
  let func = @machv.Function::new("return_live")
  let entry = func.new_block()
  let v0 = func.new_vreg(Int)
  let v1 = func.new_vreg(Int)
  let def_v0 = func.new_inst(Target("def_v0"))
  def_v0.add_operand(@machv.Operand::def(Virtual(v0)))
  entry.append(def_v0)
  let def_v1 = func.new_inst(Target("def_v1"))
  def_v1.add_operand(@machv.Operand::def(Virtual(v1)))
  def_v1.add_operand(@machv.Operand::use_reg(Virtual(v1)))
  entry.append(def_v1)
  entry.set_terminator(TermReturn([Virtual(v0)]))
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  let allocation = allocate_function(func, [p0, p1])
  inspect(
    allocation.location_of({ id: v0.id, class: Int }) !=
    allocation.location_of({ id: v1.id, class: Int }),
    content="true",
  )
}

///|
test "projected MachV successors extend live ranges across empty blocks" {
  let func = @machv.Function::new("successor_live")
  let entry = func.new_block()
  let middle = func.new_block()
  let exit = func.new_block()
  let v0 = func.new_vreg(Int)
  let v1 = func.new_vreg(Int)
  let def_v0 = func.new_inst(Target("def_v0"))
  def_v0.add_operand(@machv.Operand::def(Virtual(v0)))
  entry.append(def_v0)
  entry.set_terminator(TermJump(middle.id, []))
  let def_v1 = func.new_inst(Target("def_v1"))
  def_v1.add_operand(@machv.Operand::def(Virtual(v1)))
  def_v1.add_operand(@machv.Operand::use_reg(Virtual(v1)))
  middle.append(def_v1)
  middle.set_terminator(TermJump(exit.id, []))
  exit.set_terminator(TermReturn([Virtual(v0)]))
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  let allocation = allocate_function(func, [p0, p1])
  inspect(
    allocation.location_of({ id: v0.id, class: Int }) !=
    allocation.location_of({ id: v1.id, class: Int }),
    content="true",
  )
}

///|
test "apply inserts reloads and spills for stack allocated operands" {
  let func = @machv.Function::new("reload_spill")
  let entry = func.new_block()
  let v0 = func.new_vreg(Int)
  let v1 = func.new_vreg(Int)
  let v2 = func.new_vreg(Int)
  let seed = func.new_inst(Target("seed"))
  seed.add_operand(@machv.Operand::def(Virtual(v0)))
  seed.add_operand(@machv.Operand::def(Virtual(v1)))
  seed.add_operand(@machv.Operand::def(Virtual(v2)))
  entry.append(seed)
  let use_spilled = func.new_inst(Target("use_spilled"))
  use_spilled.add_operand(@machv.Operand::use_reg(Virtual(v2)))
  entry.append(use_spilled)
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  let result = allocate_and_apply(func, [p0, p1])
  let mut loads = 0
  let mut stores = 0
  let mut virtual_operands = 0
  for inst in entry.instructions {
    match inst.opcode {
      Load(_) => loads = loads + 1
      Store(_) => stores = stores + 1
      _ => ()
    }
    for operand in inst.operands {
      if operand.reg is Virtual(_) {
        virtual_operands = virtual_operands + 1
      }
    }
  }
  inspect(result.allocation.spill_count > 0, content="true")
  inspect(loads > 0, content="true")
  inspect(stores > 0, content="true")
  inspect(virtual_operands, content="0")
}
