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
fn has_spills(allocation : @regalloc.Allocation) -> Bool {
  allocation.spill_count > 0
}

///|
fn count_regs_in_class(
  physical_regs : Array[@machv.PReg],
  class : @machv.RegClass,
) -> Int {
  let mut count = 0
  for preg in physical_regs {
    if class_to_regalloc(preg.class) == class_to_regalloc(class) {
      count = count + 1
    }
  }
  count
}

///|
fn find_scratch_reg(
  physical_regs : Array[@machv.PReg],
  class : @machv.RegClass,
) -> @machv.PReg? {
  for offset in 0..<physical_regs.length() {
    let i = physical_regs.length() - 1 - offset
    let preg = physical_regs[i]
    if class_to_regalloc(preg.class) == class_to_regalloc(class) {
      return Some(preg)
    }
  }
  None
}

///|
fn is_reserved_scratch(
  physical_regs : Array[@machv.PReg],
  preg : @machv.PReg,
) -> Bool {
  count_regs_in_class(physical_regs, preg.class) > 1 &&
  find_scratch_reg(physical_regs, preg.class) == Some(preg)
}

///|
fn allocatable_regs_for_spills(
  physical_regs : Array[@machv.PReg],
) -> Array[@machv.PReg] {
  let out : Array[@machv.PReg] = []
  for preg in physical_regs {
    if !is_reserved_scratch(physical_regs, preg) {
      out.push(preg)
    }
  }
  out
}

///|
fn allocate_with_optional_scratch(
  func : @machv.Function,
  physical_regs : Array[@machv.PReg],
) -> @regalloc.Allocation {
  let first = allocate_function(func, physical_regs)
  if has_spills(first) {
    let allocatable = allocatable_regs_for_spills(physical_regs)
    if allocatable.length() != physical_regs.length() {
      return allocate_function(func, allocatable)
    }
  }
  first
}

///|
fn slot_size(class : @regalloc.RegClass) -> Int {
  match class {
    Int | Float => 8
    Vector => 16
  }
}

///|
fn ensure_spill_slots(
  func : @machv.Function,
  allocation : @regalloc.Allocation,
) -> Array[@machv.StackSlot] {
  let spill_slots : Array[@machv.StackSlot?] = []
  for _ in 0..<allocation.spill_count {
    spill_slots.push(None)
  }
  for assignment in allocation.assignments {
    if assignment.location is Spill(slot) {
      let size = slot_size(assignment.vreg.class)
      if spill_slots[slot] is None {
        spill_slots[slot] = Some(func.new_stack_slot(size, size))
      }
    }
  }
  let out : Array[@machv.StackSlot] = []
  for slot in spill_slots {
    match slot {
      Some(stack_slot) => out.push(stack_slot)
      None => out.push(func.new_stack_slot(8, 8))
    }
  }
  out
}

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
fn rewrite_spilled_operand(
  func : @machv.Function,
  allocation : @regalloc.Allocation,
  spill_slots : Array[@machv.StackSlot],
  physical_regs : Array[@machv.PReg],
  operand : @machv.Operand,
  before : Array[@machv.Instruction],
  after : Array[@machv.Instruction],
) -> @machv.Operand {
  match operand.reg {
    Virtual(vreg) =>
      match allocation.location_of(vreg_to_regalloc(vreg)) {
        Some(Spill(slot)) =>
          match find_scratch_reg(physical_regs, vreg.class) {
            Some(scratch) => {
              let physical : @machv.Reg = Physical(scratch)
              let stack_slot = spill_slots[slot]
              if operand.role == Use || operand.role == UseDef {
                let reload = func.new_inst(Load(stack_slot))
                reload.add_operand(@machv.Operand::def(physical))
                before.push(reload)
              }
              if operand.role == Def || operand.role == UseDef {
                let spill = func.new_inst(Store(stack_slot))
                spill.add_operand(@machv.Operand::use_reg(physical))
                after.push(spill)
              }
              { reg: physical, role: operand.role }
            }
            None => operand
          }
        _ => rewrite_allocated_operand(allocation, operand)
      }
    Physical(_) => operand
  }
}

///|
fn rewrite_operands_and_spills(
  func : @machv.Function,
  allocation : @regalloc.Allocation,
  spill_slots : Array[@machv.StackSlot],
  physical_regs : Array[@machv.PReg],
) -> Unit {
  for block in func.blocks {
    let rewritten : Array[@machv.Instruction] = []
    for inst in block.instructions {
      let before : Array[@machv.Instruction] = []
      let after : Array[@machv.Instruction] = []
      for i, operand in inst.operands {
        inst.operands[i] = rewrite_spilled_operand(
          func, allocation, spill_slots, physical_regs, operand, before, after,
        )
      }
      for reload in before {
        rewritten.push(reload)
      }
      rewritten.push(inst)
      for spill in after {
        rewritten.push(spill)
      }
    }
    block.instructions.clear()
    for inst in rewritten {
      block.instructions.push(inst)
    }
  }
}

///|
pub fn allocate_and_apply(
  func : @machv.Function,
  physical_regs : Array[@machv.PReg],
) -> ApplyResult {
  let allocation = allocate_with_optional_scratch(func, physical_regs)
  let spill_slots = ensure_spill_slots(func, allocation)
  rewrite_operands_and_spills(func, allocation, spill_slots, physical_regs)
  { allocation, spill_slots }
}
