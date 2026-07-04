///|
test "allocate abstract program registers" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let v1 : VirtualReg = { id: 1, class: Int }
  let program = Program::new([r0, r1])
  let block = Block::new(0)
  let inst = Instruction::new(0)
  inst.add_operand(Operand::def(v0))
  inst.add_operand(Operand::use_reg(v1))
  block.append(inst)
  program.add_block(block)
  let allocation = allocate(program)
  inspect(allocation.location_of(v0) == Some(Reg(r0)), content="true")
  inspect(allocation.location_of(v1) == Some(Reg(r1)), content="true")
  inspect(allocation.spill_count, content="0")
}

///|
test "allocate spills when class registers are exhausted" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let v1 : VirtualReg = { id: 1, class: Int }
  let program = Program::new([r0])
  let block = Block::new(0)
  let inst = Instruction::new(0)
  inst.add_operand(Operand::def(v0))
  inst.add_operand(Operand::def(v1))
  block.append(inst)
  program.add_block(block)
  let allocation = allocate(program)
  inspect(allocation.location_of(v1) == Some(Spill(0)), content="true")
  inspect(allocation.spill_count, content="1")
}

///|
test "linear scan reuses registers for non-overlapping intervals" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let v1 : VirtualReg = { id: 1, class: Int }
  let program = Program::new([r0])
  let block = Block::new(0)
  let first = Instruction::new(0)
  first.add_operand(Operand::def(v0))
  block.append(first)
  let second = Instruction::new(1)
  second.add_operand(Operand::def(v1))
  block.append(second)
  program.add_block(block)
  let allocation = allocate(program)
  inspect(allocation.location_of(v0) == Some(Reg(r0)), content="true")
  inspect(allocation.location_of(v1) == Some(Reg(r0)), content="true")
  inspect(allocation.spill_count, content="0")
}

///|
test "build_live_ranges records spans and uses" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let program = Program::new([r0])
  let block = Block::new(0)
  let def_inst = Instruction::new(0)
  def_inst.add_operand(Operand::def(v0))
  block.append(def_inst)
  let use_inst = Instruction::new(1)
  use_inst.add_operand(Operand::use_reg(v0))
  block.append(use_inst)
  program.add_block(block)
  let ranges = build_live_ranges(program)
  inspect(ranges.length(), content="1")
  let range = ranges.get_by_vreg(v0).unwrap()
  inspect(range.start() == Some(ProgramPoint::new(0, 0)), content="true")
  inspect(range.end() == Some(ProgramPoint::new(0, 1)), content="true")
  inspect(range.uses.length(), content="2")
  inspect(range.uses[0].kind == LiveDef, content="true")
  inspect(range.uses[1].kind == LiveUse, content="true")
}

///|
test "linear scan evicts longer active interval for shorter current interval" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let v1 : VirtualReg = { id: 1, class: Int }
  let program = Program::new([r0])
  let block = Block::new(0)
  let long_def = Instruction::new(0)
  long_def.add_operand(Operand::def(v0))
  block.append(long_def)
  let short_live = Instruction::new(1)
  short_live.add_operand(Operand::def(v1))
  short_live.add_operand(Operand::use_reg(v1))
  block.append(short_live)
  let long_use = Instruction::new(2)
  long_use.add_operand(Operand::use_reg(v0))
  block.append(long_use)
  program.add_block(block)
  let allocation = allocate(program)
  inspect(allocation.location_of(v0) == Some(Spill(0)), content="true")
  inspect(allocation.location_of(v1) == Some(Reg(r0)), content="true")
  inspect(allocation.spill_count, content="1")
}

///|
test "linear scan honors fixed register constraints by evicting active range" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let v1 : VirtualReg = { id: 1, class: Int }
  let program = Program::new([r0, r1])
  let block = Block::new(0)
  let long_def = Instruction::new(0)
  long_def.add_operand(Operand::def(v0))
  block.append(long_def)
  let fixed_inst = Instruction::new(1)
  fixed_inst.add_operand(Operand::def(v1).with_constraint(FixedReg(r0)))
  fixed_inst.add_operand(Operand::use_reg(v1).with_constraint(FixedReg(r0)))
  block.append(fixed_inst)
  let long_use = Instruction::new(2)
  long_use.add_operand(Operand::use_reg(v0))
  block.append(long_use)
  program.add_block(block)
  let allocation = allocate(program)
  inspect(allocation.location_of(v0) == Some(Spill(0)), content="true")
  inspect(allocation.location_of(v1) == Some(Reg(r0)), content="true")
}

///|
test "verify_allocation accepts allocator output" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let program = Program::new([r0])
  let block = Block::new(0)
  let inst = Instruction::new(0)
  inst.add_operand(Operand::def(v0))
  block.append(inst)
  program.add_block(block)
  let allocation = allocate(program)
  inspect(verify_allocation(program, allocation), content="()")
}

///|
test "verify_allocation rejects fixed register mismatch" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let r1 : PhysicalReg = { id: 1, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let program = Program::new([r0, r1])
  let block = Block::new(0)
  let inst = Instruction::new(0)
  inst.add_operand(Operand::def(v0).with_constraint(FixedReg(r1)))
  block.append(inst)
  program.add_block(block)
  let allocation = Allocation::new()
  allocation.assign(v0, Reg(r0))
  try verify_allocation(program, allocation) catch {
    FixedConstraintViolation(_) => inspect("fixed", content="fixed")
    _ => fail("unexpected verifier error")
  } noraise {
    _ => fail("expected fixed constraint violation")
  }
}

///|
test "verify_allocation rejects overlapping physical register assignments" {
  let r0 : PhysicalReg = { id: 0, class: Int }
  let v0 : VirtualReg = { id: 0, class: Int }
  let v1 : VirtualReg = { id: 1, class: Int }
  let program = Program::new([r0])
  let block = Block::new(0)
  let inst = Instruction::new(0)
  inst.add_operand(Operand::def(v0))
  inst.add_operand(Operand::def(v1))
  block.append(inst)
  program.add_block(block)
  let allocation = Allocation::new()
  allocation.assign(v0, Reg(r0))
  allocation.assign(v1, Reg(r0))
  try verify_allocation(program, allocation) catch {
    OverlappingAllocation(_) => inspect("overlap", content="overlap")
    _ => fail("unexpected verifier error")
  } noraise {
    _ => fail("expected overlap")
  }
}
