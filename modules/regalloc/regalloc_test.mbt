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
