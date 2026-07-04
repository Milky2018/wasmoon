///|
fn class_to_regalloc(class : @machv.RegClass) -> @regalloc.RegClass {
  match class {
    Int => Int
    Float32 | Float64 => Float
    Vector => Vector
  }
}

///|
fn vreg_to_regalloc(vreg : @machv.VReg) -> @regalloc.VirtualReg {
  { id: vreg.id, class: class_to_regalloc(vreg.class) }
}

///|
fn preg_to_regalloc(preg : @machv.PReg) -> @regalloc.PhysicalReg {
  { id: preg.index, class: class_to_regalloc(preg.class) }
}

///|
fn class_from_regalloc(class : @regalloc.RegClass) -> @machv.RegClass {
  match class {
    Int => Int
    Float => Float64
    Vector => Vector
  }
}

///|
fn preg_from_regalloc(preg : @regalloc.PhysicalReg) -> @machv.PReg {
  { index: preg.id, class: class_from_regalloc(preg.class) }
}

///|
fn role_to_regalloc(role : @machv.OperandRole) -> @regalloc.OperandRole {
  match role {
    Use => Use
    Def => Def
    UseDef => UseDef
  }
}

///|
fn operand_to_regalloc(operand : @machv.Operand) -> @regalloc.Operand? {
  match operand.reg {
    Virtual(vreg) =>
      Some({
        vreg: vreg_to_regalloc(vreg),
        role: role_to_regalloc(operand.role),
      })
    Physical(_) => None
  }
}

///|
fn instruction_to_regalloc(inst : @machv.Instruction) -> @regalloc.Instruction {
  let out = @regalloc.Instruction::new(inst.id)
  for operand in inst.operands {
    if operand_to_regalloc(operand) is Some(regalloc_operand) {
      out.add_operand(regalloc_operand)
    }
  }
  for clobber in inst.clobbers {
    out.add_clobber(preg_to_regalloc(clobber))
  }
  out
}

///|
pub fn project_function(
  func : @machv.Function,
  physical_regs : Array[@machv.PReg],
) -> @regalloc.Program {
  let regs = physical_regs.map(preg_to_regalloc)
  let program = @regalloc.Program::new(regs)
  for block in func.blocks {
    let out_block = @regalloc.Block::new(block.id)
    for inst in block.instructions {
      out_block.append(instruction_to_regalloc(inst))
    }
    program.add_block(out_block)
  }
  program
}

///|
pub fn allocate_function(
  func : @machv.Function,
  physical_regs : Array[@machv.PReg],
) -> @regalloc.Allocation {
  @regalloc.allocate(project_function(func, physical_regs))
}

///|
pub(all) struct ApplyResult {
  allocation : @regalloc.Allocation
  spill_slots : Array[@machv.StackSlot]
} derive(Debug)

///|
fn rewrite_allocated_operand(
  allocation : @regalloc.Allocation,
  operand : @machv.Operand,
) -> @machv.Operand {
  match operand.reg {
    Virtual(vreg) =>
      match allocation.location_of(vreg_to_regalloc(vreg)) {
        Some(Reg(preg)) =>
          { reg: Physical(preg_from_regalloc(preg)), role: operand.role }
        Some(Spill(_)) | None => operand
      }
    Physical(_) => operand
  }
}

///|
fn rewrite_allocated_operands(
  func : @machv.Function,
  allocation : @regalloc.Allocation,
) -> Unit {
  for block in func.blocks {
    for inst in block.instructions {
      for i, operand in inst.operands {
        inst.operands[i] = rewrite_allocated_operand(allocation, operand)
      }
    }
  }
}

///|
pub fn allocate_and_apply(
  func : @machv.Function,
  physical_regs : Array[@machv.PReg],
) -> ApplyResult {
  let allocation = allocate_function(func, physical_regs)
  let spill_slots : Array[@machv.StackSlot] = []
  rewrite_allocated_operands(func, allocation)
  // TODO(machv_regalloc): insert reload/spill moves around instruction
  // boundaries once MachV load/store pseudos are fully owned by machv_emit.
  for assignment in allocation.assignments {
    if assignment.location is Spill(_) {
      spill_slots.push(func.new_stack_slot(8, 8))
    }
  }
  { allocation, spill_slots }
}
