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
fn preg_from_regalloc_for_class(
  preg : @regalloc.PhysicalReg,
  class : @machv.RegClass,
) -> @machv.PReg {
  { index: preg.id, class }
}

///|
fn constraint_for_operand(
  inst : @machv.Instruction,
  operand_index : Int,
  include_fixed_constraints : Bool,
) -> @regalloc.OperandConstraint {
  if !include_fixed_constraints {
    return AnyReg
  }
  for constraint in inst.constraints {
    if constraint.operand_index == operand_index {
      if constraint.allowed_regs.length() == 1 {
        return FixedReg(preg_to_regalloc(constraint.allowed_regs[0]))
      }
    }
  }
  AnyReg
}

///|
fn operand_to_regalloc(
  inst : @machv.Instruction,
  operand_index : Int,
  operand : @machv.Operand,
  include_fixed_constraints : Bool,
) -> @regalloc.Operand? {
  match operand.reg {
    Virtual(vreg) => {
      let base = match operand.role {
        Use => @regalloc.Operand::use_reg(vreg_to_regalloc(vreg))
        Def => @regalloc.Operand::def(vreg_to_regalloc(vreg))
        UseDef => {
          let out = @regalloc.Operand::use_reg(vreg_to_regalloc(vreg))
          {
            vreg: out.vreg,
            role: UseDef,
            constraint: out.constraint,
            tie_id: out.tie_id,
          }
        }
      }
      Some(
        base
        .with_constraint(
          constraint_for_operand(inst, operand_index, include_fixed_constraints),
        )
        .with_tie(operand.tie_id),
      )
    }
    Physical(_) => None
  }
}

///|
fn instruction_to_regalloc(
  inst : @machv.Instruction,
  include_fixed_constraints : Bool,
) -> @regalloc.Instruction {
  let out = @regalloc.Instruction::new(inst.id)
  for i, operand in inst.operands {
    if operand_to_regalloc(inst, i, operand, include_fixed_constraints)
      is Some(regalloc_operand) {
      out.add_operand(regalloc_operand)
    }
  }
  for clobber in inst.clobbers {
    out.add_clobber(preg_to_regalloc(clobber))
  }
  out
}

///|
fn materialize_fixed_constraints_for_opcode(opcode : @machv.Opcode) -> Bool {
  match opcode {
    Call(_) => true
    _ => false
  }
}

///|
fn block_params_to_regalloc(block : @machv.Block) -> @regalloc.Instruction? {
  if block.params.length() == 0 {
    return None
  }
  let out = @regalloc.Instruction::new(-10_000 - block.id)
  for param in block.params {
    out.add_operand(@regalloc.Operand::def(vreg_to_regalloc(param)))
  }
  Some(out)
}

///|
fn function_params_to_regalloc(
  func : @machv.Function,
) -> @regalloc.Instruction? {
  if func.params.length() == 0 {
    return None
  }
  let out = @regalloc.Instruction::new(-20_000)
  for param in func.params {
    out.add_operand(@regalloc.Operand::def(vreg_to_regalloc(param)))
  }
  Some(out)
}

///|
fn add_terminator_use(out : @regalloc.Instruction, reg : @machv.Reg) -> Unit {
  if reg is Virtual(vreg) {
    out.add_operand(@regalloc.Operand::use_reg(vreg_to_regalloc(vreg)))
  }
}

///|
fn add_terminator_uses(
  out : @regalloc.Instruction,
  regs : Array[@machv.Reg],
) -> Unit {
  for reg in regs {
    add_terminator_use(out, reg)
  }
}

///|
fn terminator_to_regalloc(
  block_id : Int,
  term : @machv.Terminator,
) -> @regalloc.Instruction {
  let out = @regalloc.Instruction::new(-1 - block_id)
  match term {
    TermJump(_, args) => add_terminator_uses(out, args)
    TermBranch(cond, _, true_args, _, false_args) => {
      add_terminator_use(out, cond)
      add_terminator_uses(out, true_args)
      add_terminator_uses(out, false_args)
    }
    TermBranchCmp(lhs, rhs, _, _, _, true_args, _, false_args) => {
      add_terminator_use(out, lhs)
      add_terminator_use(out, rhs)
      add_terminator_uses(out, true_args)
      add_terminator_uses(out, false_args)
    }
    TermBranchZero(value, _, _, _, true_args, _, false_args) => {
      add_terminator_use(out, value)
      add_terminator_uses(out, true_args)
      add_terminator_uses(out, false_args)
    }
    TermBranchCmpImm(value, _, _, _, _, true_args, _, false_args) => {
      add_terminator_use(out, value)
      add_terminator_uses(out, true_args)
      add_terminator_uses(out, false_args)
    }
    TermReturn(results) => add_terminator_uses(out, results)
    TermTrap(_) => ()
    TermBrTable(value, _, _) => add_terminator_use(out, value)
  }
  out
}

///|
pub fn project_function(
  func : @machv.Function,
  physical_regs : Array[@machv.PReg],
) -> @regalloc.Program {
  project_function_impl(func, physical_regs, true)
}

///|
fn project_function_impl(
  func : @machv.Function,
  physical_regs : Array[@machv.PReg],
  include_fixed_constraints : Bool,
) -> @regalloc.Program {
  let regs = physical_regs.map(preg_to_regalloc)
  let program = @regalloc.Program::new(regs)
  for block in func.blocks {
    let out_block = @regalloc.Block::new(block.id)
    if block.id == 0 && function_params_to_regalloc(func) is Some(param_defs) {
      out_block.append(param_defs)
    }
    if block_params_to_regalloc(block) is Some(param_defs) {
      out_block.append(param_defs)
    }
    for inst in block.instructions {
      let include_inst_constraints = include_fixed_constraints &&
        !materialize_fixed_constraints_for_opcode(inst.opcode)
      out_block.append(instruction_to_regalloc(inst, include_inst_constraints))
    }
    if block.terminator is Some(term) {
      out_block.append(terminator_to_regalloc(block.id, term))
    }
    for succ in block.successors {
      out_block.add_successor(succ)
    }
    program.add_block(out_block)
  }
  program
}

///|
/// Project a small MachV function into `regalloc.Program` and run the simple
/// linear-scan allocator. This is not the production VCode backtracking path.
pub fn allocate_function_linear_scan(
  func : @machv.Function,
  physical_regs : Array[@machv.PReg],
) -> @regalloc.Allocation raise @regalloc.VerifyError {
  let program = project_function(func, physical_regs)
  let allocation = @regalloc.allocate_linear_scan(program)
  @regalloc.verify_allocation(program, allocation)
  allocation
}

///|
fn allocate_function_linear_scan_for_apply(
  func : @machv.Function,
  physical_regs : Array[@machv.PReg],
) -> @regalloc.Allocation raise @regalloc.VerifyError {
  let program = project_function_impl(func, physical_regs, true)
  let allocation = @regalloc.allocate_linear_scan(program)
  @regalloc.verify_allocation(program, allocation)
  allocation
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
fn same_reg_bank(lhs : @machv.PReg, rhs : @machv.PReg) -> Bool {
  lhs.index == rhs.index &&
  class_to_regalloc(lhs.class) == class_to_regalloc(rhs.class)
}

///|
fn scratch_is_used(
  used_scratch : Array[@machv.PReg],
  candidate : @machv.PReg,
) -> Bool {
  for used in used_scratch {
    if same_reg_bank(used, candidate) {
      return true
    }
  }
  false
}

///|
fn find_scratch_reg_excluding(
  physical_regs : Array[@machv.PReg],
  class : @machv.RegClass,
  used_scratch : Array[@machv.PReg],
) -> @machv.PReg? {
  for offset in 0..<physical_regs.length() {
    let i = physical_regs.length() - 1 - offset
    let preg = physical_regs[i]
    if preg.class == class && !scratch_is_used(used_scratch, preg) {
      return Some(preg)
    }
  }
  for offset in 0..<physical_regs.length() {
    let i = physical_regs.length() - 1 - offset
    let preg = physical_regs[i]
    let candidate : @machv.PReg = { index: preg.index, class }
    if class_to_regalloc(preg.class) == class_to_regalloc(class) &&
      !scratch_is_used(used_scratch, candidate) {
      return Some(candidate)
    }
  }
  None
}

///|
fn is_reserved_scratch(
  physical_regs : Array[@machv.PReg],
  preg : @machv.PReg,
) -> Bool {
  if count_regs_in_class(physical_regs, preg.class) <= 1 {
    return false
  }
  for candidate in physical_regs {
    if class_to_regalloc(candidate.class) == class_to_regalloc(preg.class) {
      return candidate != preg
    }
  }
  false
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
struct ScratchBinding {
  slot : Int
  class : @machv.RegClass
  scratch : @machv.PReg
} derive(Eq, Debug)

///|
fn bound_scratch(
  bindings : Array[ScratchBinding],
  slot : Int,
  class : @machv.RegClass,
) -> @machv.PReg? {
  for binding in bindings {
    if binding.slot == slot && binding.class == class {
      return Some(binding.scratch)
    }
  }
  None
}

///|
fn used_scratch_regs(bindings : Array[ScratchBinding]) -> Array[@machv.PReg] {
  let out : Array[@machv.PReg] = []
  for binding in bindings {
    out.push(binding.scratch)
  }
  out
}

///|
fn reserve_scratch(
  physical_regs : Array[@machv.PReg],
  bindings : Array[ScratchBinding],
  slot : Int,
  class : @machv.RegClass,
) -> @machv.PReg? {
  if bound_scratch(bindings, slot, class) is Some(scratch) {
    return Some(scratch)
  }
  match
    find_scratch_reg_excluding(
      physical_regs,
      class,
      used_scratch_regs(bindings),
    ) {
    Some(scratch) => {
      bindings.push({ slot, class, scratch })
      Some(scratch)
    }
    None => None
  }
}

///|
fn allocate_with_optional_scratch(
  func : @machv.Function,
  physical_regs : Array[@machv.PReg],
) -> @regalloc.Allocation raise @regalloc.VerifyError {
  let first = allocate_function_linear_scan_for_apply(func, physical_regs)
  if has_spills(first) {
    let allocatable = allocatable_regs_for_spills(physical_regs)
    if allocatable.length() != physical_regs.length() {
      return allocate_function_linear_scan_for_apply(func, allocatable)
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
          {
            reg: Physical(preg_from_regalloc_for_class(preg, vreg.class)),
            role: operand.role,
            tie_id: operand.tie_id,
          }
        Some(Spill(_)) | None => operand
      }
    Physical(_) => operand
  }
}

///|
fn rewrite_allocated_reg(
  allocation : @regalloc.Allocation,
  reg : @machv.Reg,
) -> @machv.Reg {
  match reg {
    Virtual(vreg) =>
      match allocation.location_of(vreg_to_regalloc(vreg)) {
        Some(Reg(preg)) =>
          Physical(preg_from_regalloc_for_class(preg, vreg.class))
        _ => reg
      }
    Physical(_) => reg
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
  scratch_bindings : Array[ScratchBinding],
) -> @machv.Operand raise @regalloc.VerifyError {
  match operand.reg {
    Virtual(vreg) =>
      match allocation.location_of(vreg_to_regalloc(vreg)) {
        Some(Spill(slot)) =>
          match
            reserve_scratch(physical_regs, scratch_bindings, slot, vreg.class) {
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
              { reg: physical, role: operand.role, tie_id: operand.tie_id }
            }
            None => {
              @regalloc.raise_scratch_register_unavailable(
                message="no scratch register available for spilled MachV operand",
              )
              abort("unreachable")
            }
          }
        _ => rewrite_allocated_operand(allocation, operand)
      }
    Physical(_) => operand
  }
}

///|
fn rewrite_spilled_reg(
  func : @machv.Function,
  allocation : @regalloc.Allocation,
  spill_slots : Array[@machv.StackSlot],
  physical_regs : Array[@machv.PReg],
  reg : @machv.Reg,
  before : Array[@machv.Instruction],
  scratch_bindings : Array[ScratchBinding],
) -> @machv.Reg raise @regalloc.VerifyError {
  match reg {
    Virtual(vreg) =>
      match allocation.location_of(vreg_to_regalloc(vreg)) {
        Some(Spill(slot)) =>
          match
            reserve_scratch(physical_regs, scratch_bindings, slot, vreg.class) {
            Some(scratch) => {
              let physical : @machv.Reg = Physical(scratch)
              let reload = func.new_inst(Load(spill_slots[slot]))
              reload.add_operand(@machv.Operand::def(physical))
              before.push(reload)
              physical
            }
            None => {
              @regalloc.raise_scratch_register_unavailable(
                message="no scratch register available for spilled MachV terminator operand",
              )
              abort("unreachable")
            }
          }
        _ => rewrite_allocated_reg(allocation, reg)
      }
    Physical(_) => reg
  }
}

///|
fn rewrite_reg_array(
  func : @machv.Function,
  allocation : @regalloc.Allocation,
  spill_slots : Array[@machv.StackSlot],
  physical_regs : Array[@machv.PReg],
  regs : Array[@machv.Reg],
  before : Array[@machv.Instruction],
  scratch_bindings : Array[ScratchBinding],
) -> Array[@machv.Reg] raise @regalloc.VerifyError {
  let out : Array[@machv.Reg] = []
  for reg in regs {
    out.push(
      rewrite_spilled_reg(
        func, allocation, spill_slots, physical_regs, reg, before, scratch_bindings,
      ),
    )
  }
  out
}

///|
fn rewrite_terminator(
  func : @machv.Function,
  allocation : @regalloc.Allocation,
  spill_slots : Array[@machv.StackSlot],
  physical_regs : Array[@machv.PReg],
  term : @machv.Terminator,
  before : Array[@machv.Instruction],
) -> @machv.Terminator raise @regalloc.VerifyError {
  let scratch_bindings : Array[ScratchBinding] = []
  match term {
    TermJump(target, args) =>
      TermJump(
        target,
        rewrite_reg_array(
          func, allocation, spill_slots, physical_regs, args, before, scratch_bindings,
        ),
      )
    TermBranch(cond, true_target, true_args, false_target, false_args) =>
      TermBranch(
        rewrite_spilled_reg(
          func, allocation, spill_slots, physical_regs, cond, before, scratch_bindings,
        ),
        true_target,
        rewrite_reg_array(
          func, allocation, spill_slots, physical_regs, true_args, before, scratch_bindings,
        ),
        false_target,
        rewrite_reg_array(
          func, allocation, spill_slots, physical_regs, false_args, before, scratch_bindings,
        ),
      )
    TermBranchCmp(
      lhs,
      rhs,
      cond,
      is_64,
      true_target,
      true_args,
      false_target,
      false_args
    ) =>
      TermBranchCmp(
        rewrite_spilled_reg(
          func, allocation, spill_slots, physical_regs, lhs, before, scratch_bindings,
        ),
        rewrite_spilled_reg(
          func, allocation, spill_slots, physical_regs, rhs, before, scratch_bindings,
        ),
        cond,
        is_64,
        true_target,
        rewrite_reg_array(
          func, allocation, spill_slots, physical_regs, true_args, before, scratch_bindings,
        ),
        false_target,
        rewrite_reg_array(
          func, allocation, spill_slots, physical_regs, false_args, before, scratch_bindings,
        ),
      )
    TermBranchZero(
      value,
      is_nonzero,
      is_64,
      true_target,
      true_args,
      false_target,
      false_args
    ) =>
      TermBranchZero(
        rewrite_spilled_reg(
          func, allocation, spill_slots, physical_regs, value, before, scratch_bindings,
        ),
        is_nonzero,
        is_64,
        true_target,
        rewrite_reg_array(
          func, allocation, spill_slots, physical_regs, true_args, before, scratch_bindings,
        ),
        false_target,
        rewrite_reg_array(
          func, allocation, spill_slots, physical_regs, false_args, before, scratch_bindings,
        ),
      )
    TermBranchCmpImm(
      value,
      imm,
      cond,
      is_64,
      true_target,
      true_args,
      false_target,
      false_args
    ) =>
      TermBranchCmpImm(
        rewrite_spilled_reg(
          func, allocation, spill_slots, physical_regs, value, before, scratch_bindings,
        ),
        imm,
        cond,
        is_64,
        true_target,
        rewrite_reg_array(
          func, allocation, spill_slots, physical_regs, true_args, before, scratch_bindings,
        ),
        false_target,
        rewrite_reg_array(
          func, allocation, spill_slots, physical_regs, false_args, before, scratch_bindings,
        ),
      )
    TermReturn(results) =>
      TermReturn(
        rewrite_reg_array(
          func, allocation, spill_slots, physical_regs, results, before, scratch_bindings,
        ),
      )
    TermTrap(_) => term
    TermBrTable(value, targets, default_target) =>
      TermBrTable(
        rewrite_spilled_reg(
          func, allocation, spill_slots, physical_regs, value, before, scratch_bindings,
        ),
        targets,
        default_target,
      )
  }
}

///|
fn find_block(func : @machv.Function, block_id : Int) -> @machv.Block? {
  for block in func.blocks {
    if block.id == block_id {
      return Some(block)
    }
  }
  None
}

///|
fn source_location(
  reg : @machv.Reg,
  allocation : @regalloc.Allocation,
) -> @regalloc.Location? {
  match reg {
    Physical(preg) => Some(Reg(preg_to_regalloc(preg)))
    Virtual(vreg) => allocation.location_of(vreg_to_regalloc(vreg))
  }
}

///|
fn scratch_regs_for_class(
  physical_regs : Array[@machv.PReg],
  class : @regalloc.RegClass,
) -> Array[@regalloc.PhysicalReg] {
  let out : Array[@regalloc.PhysicalReg] = []
  for preg in physical_regs {
    let reg = preg_to_regalloc(preg)
    if reg.class == class {
      out.push(reg)
    }
  }
  out
}

///|
fn scratch_regs_for_class_excluding(
  physical_regs : Array[@machv.PReg],
  class : @regalloc.RegClass,
  avoid : Array[@machv.PReg],
) -> Array[@regalloc.PhysicalReg] {
  let out : Array[@regalloc.PhysicalReg] = []
  for preg in physical_regs {
    if preg_to_regalloc(preg).class != class {
      continue
    }
    let mut blocked = false
    for reserved in avoid {
      if same_reg_bank(preg, reserved) {
        blocked = true
        break
      }
    }
    if !blocked {
      out.push(preg_to_regalloc(preg))
    }
  }
  out
}

///|
fn class_tag_for_machv(class : @machv.RegClass) -> Int {
  match class {
    Int => 0
    Float32 => 1
    Float64 => 2
    Vector => 3
  }
}

///|
fn class_from_fixed_constraint_tag(tag : Int) -> @machv.RegClass {
  match tag {
    0 => Int
    1 => Float32
    2 => Float64
    3 => Vector
    _ => Int
  }
}

///|
fn fixed_constraint_operand(
  operand : @machv.Operand,
  allocation : @regalloc.Allocation,
) -> @regalloc.FixedConstraintOperand {
  let class_tag = class_tag_for_machv(operand_class(operand))
  match operand.reg {
    Virtual(vreg) =>
      Virtual(allocation.location_of(vreg_to_regalloc(vreg)), class_tag)
    Physical(preg) => Physical(preg_to_regalloc(preg), class_tag)
  }
}

///|
fn fixed_constraint_inst_edits(
  block_index : Int,
  inst_index : Int,
  inst : @machv.Instruction,
  allocation : @regalloc.Allocation,
) -> @regalloc.FixedConstraintInstEdits? {
  let uses : Array[@regalloc.FixedConstraint] = []
  let defs : Array[@regalloc.FixedConstraint] = []
  for constraint in inst.constraints {
    guard constraint.allowed_regs.length() == 1 else { continue }
    guard constraint.operand_index >= 0 &&
      constraint.operand_index < inst.operands.length() else {
      continue
    }
    let operand = inst.operands[constraint.operand_index]
    let fixed : @regalloc.FixedConstraint = {
      operand: fixed_constraint_operand(operand, allocation),
      required: preg_to_regalloc(constraint.allowed_regs[0]),
    }
    if operand.role == Use || operand.role == UseDef {
      uses.push(fixed)
    }
    if operand.role == Def || operand.role == UseDef {
      defs.push(fixed)
    }
  }
  let edits = @regalloc.plan_fixed_constraint_edits([
    { block_index, inst_index, uses, defs },
  ])
  if edits.length() == 0 {
    None
  } else {
    Some(edits[0])
  }
}

///|
fn append_fixed_constraint_moves(
  func : @machv.Function,
  spill_slots : Array[@machv.StackSlot],
  physical_regs : Array[@machv.PReg],
  class : @machv.RegClass,
  avoid : Array[@machv.PReg],
  edits : Array[@regalloc.FixedConstraintMove],
  out : Array[@machv.Instruction],
) -> Unit raise @regalloc.VerifyError {
  if edits.length() == 0 {
    return
  }
  let moves : Array[@regalloc.ParallelMove] = []
  for edit in edits {
    moves.push({
      from: edit.from,
      to: edit.to,
      class: class_to_regalloc(class_from_fixed_constraint_tag(edit.class_tag)),
    })
  }
  let scratch_int = scratch_regs_for_class_excluding(physical_regs, Int, avoid)
  let scratch_float = scratch_regs_for_class_excluding(
    physical_regs,
    if class == Vector {
      Vector
    } else {
      Float
    },
    avoid,
  )
  let resolved = @regalloc.resolve_parallel_moves(
    moves, scratch_int, scratch_float,
  )
  for mv in resolved {
    append_location_move(func, spill_slots, class, mv.from, mv.to, out)
  }
}

///|
fn append_location_move(
  func : @machv.Function,
  spill_slots : Array[@machv.StackSlot],
  class : @machv.RegClass,
  from : @regalloc.Location,
  to : @regalloc.Location,
  out : Array[@machv.Instruction],
) -> Unit raise @regalloc.VerifyError {
  match (from, to) {
    (Reg(src), Reg(dst)) => {
      let src_reg = preg_from_regalloc_for_class(src, class)
      let dst_reg = preg_from_regalloc_for_class(dst, class)
      if src_reg == dst_reg {
        return
      }
      let move_inst = func.new_inst(Move)
      move_inst.add_operand(@machv.Operand::def(Physical(dst_reg)))
      move_inst.add_operand(@machv.Operand::use_reg(Physical(src_reg)))
      out.push(move_inst)
    }
    (Spill(slot), Reg(dst)) => {
      let load = func.new_inst(Load(spill_slots[slot]))
      load.add_operand(
        @machv.Operand::def(Physical(preg_from_regalloc_for_class(dst, class))),
      )
      out.push(load)
    }
    (Reg(src), Spill(slot)) => {
      let store = func.new_inst(Store(spill_slots[slot]))
      store.add_operand(
        @machv.Operand::use_reg(
          Physical(preg_from_regalloc_for_class(src, class)),
        ),
      )
      out.push(store)
    }
    (Spill(_), Spill(_)) =>
      @regalloc.raise_scratch_register_unavailable(
        message="unresolved spill-to-spill MachV edge copy; missing scratch register",
      )
  }
}

///|
fn operand_class(operand : @machv.Operand) -> @machv.RegClass {
  match operand.reg {
    Virtual(vreg) => vreg.class
    Physical(preg) => preg.class
  }
}

///|
fn operand_with_physical(
  operand : @machv.Operand,
  preg : @machv.PReg,
) -> @machv.Operand {
  let reg : @machv.Reg = Physical(preg)
  let out = match operand.role {
    Use => @machv.Operand::use_reg(reg)
    Def => @machv.Operand::def(reg)
    UseDef => @machv.Operand::use_def(reg)
  }
  out.with_tie(operand.tie_id)
}

///|
fn materialize_fixed_constraint_moves(
  func : @machv.Function,
  allocation : @regalloc.Allocation,
  spill_slots : Array[@machv.StackSlot],
  physical_regs : Array[@machv.PReg],
) -> Unit raise @regalloc.VerifyError {
  for block_index, block in func.blocks {
    let rewritten : Array[@machv.Instruction] = []
    for inst_index, inst in block.instructions {
      let before : Array[@machv.Instruction] = []
      let after : Array[@machv.Instruction] = []
      let before_int : Array[@regalloc.FixedConstraintMove] = []
      let before_f32 : Array[@regalloc.FixedConstraintMove] = []
      let before_f64 : Array[@regalloc.FixedConstraintMove] = []
      let before_vector : Array[@regalloc.FixedConstraintMove] = []
      let after_int : Array[@regalloc.FixedConstraintMove] = []
      let after_f32 : Array[@regalloc.FixedConstraintMove] = []
      let after_f64 : Array[@regalloc.FixedConstraintMove] = []
      let after_vector : Array[@regalloc.FixedConstraintMove] = []
      let before_avoid : Array[@machv.PReg] = []
      let after_avoid : Array[@machv.PReg] = []
      if fixed_constraint_inst_edits(block_index, inst_index, inst, allocation)
        is Some(edits) {
        for mv in edits.before {
          match class_from_fixed_constraint_tag(mv.class_tag) {
            Int => before_int.push(mv)
            Float32 => before_f32.push(mv)
            Float64 => before_f64.push(mv)
            Vector => before_vector.push(mv)
          }
        }
        for mv in edits.after {
          match class_from_fixed_constraint_tag(mv.class_tag) {
            Int => after_int.push(mv)
            Float32 => after_f32.push(mv)
            Float64 => after_f64.push(mv)
            Vector => after_vector.push(mv)
          }
        }
      }
      for constraint in inst.constraints {
        guard constraint.allowed_regs.length() == 1 else { continue }
        guard constraint.operand_index >= 0 &&
          constraint.operand_index < inst.operands.length() else {
          continue
        }
        let required = constraint.allowed_regs[0]
        let operand = inst.operands[constraint.operand_index]
        if operand.role == Use || operand.role == UseDef {
          before_avoid.push(required)
        }
        if operand.role == Def || operand.role == UseDef {
          after_avoid.push(required)
        }
        inst.operands[constraint.operand_index] = operand_with_physical(
          operand, required,
        )
      }
      append_fixed_constraint_moves(
        func,
        spill_slots,
        physical_regs,
        Int,
        before_avoid,
        before_int,
        before,
      )
      append_fixed_constraint_moves(
        func,
        spill_slots,
        physical_regs,
        Float32,
        before_avoid,
        before_f32,
        before,
      )
      append_fixed_constraint_moves(
        func,
        spill_slots,
        physical_regs,
        Float64,
        before_avoid,
        before_f64,
        before,
      )
      append_fixed_constraint_moves(
        func,
        spill_slots,
        physical_regs,
        Vector,
        before_avoid,
        before_vector,
        before,
      )
      append_fixed_constraint_moves(
        func,
        spill_slots,
        physical_regs,
        Int,
        after_avoid,
        after_int,
        after,
      )
      append_fixed_constraint_moves(
        func,
        spill_slots,
        physical_regs,
        Float32,
        after_avoid,
        after_f32,
        after,
      )
      append_fixed_constraint_moves(
        func,
        spill_slots,
        physical_regs,
        Float64,
        after_avoid,
        after_f64,
        after,
      )
      append_fixed_constraint_moves(
        func,
        spill_slots,
        physical_regs,
        Vector,
        after_avoid,
        after_vector,
        after,
      )
      for mov in before {
        rewritten.push(mov)
      }
      rewritten.push(inst)
      for mov in after {
        rewritten.push(mov)
      }
    }
    block.instructions.clear()
    for inst in rewritten {
      block.instructions.push(inst)
    }
  }
}

///|
fn resolve_edge_moves(
  func : @machv.Function,
  spill_slots : Array[@machv.StackSlot],
  physical_regs : Array[@machv.PReg],
  class : @machv.RegClass,
  moves : Array[@regalloc.ParallelMove],
  out : Array[@machv.Instruction],
) -> Unit raise @regalloc.VerifyError {
  if moves.length() == 0 {
    return
  }
  let scratch_int = scratch_regs_for_class(physical_regs, Int)
  let scratch_float = scratch_regs_for_class(
    physical_regs,
    if class == Vector {
      Vector
    } else {
      Float
    },
  )
  let resolved = @regalloc.resolve_parallel_moves(
    moves, scratch_int, scratch_float,
  )
  for mv in resolved {
    append_location_move(func, spill_slots, class, mv.from, mv.to, out)
  }
}

///|
fn edge_transfer_insts(
  func : @machv.Function,
  allocation : @regalloc.Allocation,
  spill_slots : Array[@machv.StackSlot],
  physical_regs : Array[@machv.PReg],
  target_id : Int,
  args : Array[@machv.Reg],
) -> Array[@machv.Instruction] raise @regalloc.VerifyError {
  let out : Array[@machv.Instruction] = []
  if args.length() == 0 {
    return out
  }
  guard find_block(func, target_id) is Some(target) else { return out }
  guard target.params.length() == args.length() else { return out }
  let int_moves : Array[@regalloc.ParallelMove] = []
  let f32_moves : Array[@regalloc.ParallelMove] = []
  let f64_moves : Array[@regalloc.ParallelMove] = []
  let vector_moves : Array[@regalloc.ParallelMove] = []
  for i in 0..<args.length() {
    let param = target.params[i]
    guard source_location(args[i], allocation) is Some(from) else { continue }
    guard allocation.location_of(vreg_to_regalloc(param)) is Some(to) else {
      continue
    }
    let edge_move : @regalloc.ParallelMove = {
      from,
      to,
      class: class_to_regalloc(param.class),
    }
    match param.class {
      Int => int_moves.push(edge_move)
      Float32 => f32_moves.push(edge_move)
      Float64 => f64_moves.push(edge_move)
      Vector => vector_moves.push(edge_move)
    }
  }
  resolve_edge_moves(func, spill_slots, physical_regs, Int, int_moves, out)
  resolve_edge_moves(func, spill_slots, physical_regs, Float32, f32_moves, out)
  resolve_edge_moves(func, spill_slots, physical_regs, Float64, f64_moves, out)
  resolve_edge_moves(
    func,
    spill_slots,
    physical_regs,
    Vector,
    vector_moves,
    out,
  )
  out
}

///|
fn append_edge_transfers(
  func : @machv.Function,
  allocation : @regalloc.Allocation,
  spill_slots : Array[@machv.StackSlot],
  physical_regs : Array[@machv.PReg],
  block : @machv.Block,
  target_id : Int,
  args : Array[@machv.Reg],
) -> Unit raise @regalloc.VerifyError {
  for
    inst in edge_transfer_insts(
      func, allocation, spill_slots, physical_regs, target_id, args,
    ) {
    block.instructions.push(inst)
  }
}

///|
fn make_edge_transfer_block(
  func : @machv.Function,
  allocation : @regalloc.Allocation,
  spill_slots : Array[@machv.StackSlot],
  physical_regs : Array[@machv.PReg],
  target_id : Int,
  args : Array[@machv.Reg],
) -> Int raise @regalloc.VerifyError {
  let edge = func.new_block()
  for
    inst in edge_transfer_insts(
      func, allocation, spill_slots, physical_regs, target_id, args,
    ) {
    edge.append(inst)
  }
  edge.set_terminator(TermJump(target_id, []))
  edge.id
}

///|
fn materialize_edge_transfers(
  func : @machv.Function,
  allocation : @regalloc.Allocation,
  spill_slots : Array[@machv.StackSlot],
  physical_regs : Array[@machv.PReg],
) -> Unit raise @regalloc.VerifyError {
  let original_blocks = func.blocks.length()
  for block_index in 0..<original_blocks {
    let block = func.blocks[block_index]
    guard block.terminator is Some(term) else { continue }
    match term {
      TermJump(target, args) => {
        append_edge_transfers(
          func, allocation, spill_slots, physical_regs, block, target, args,
        )
        block.set_terminator(TermJump(target, []))
      }
      TermBranch(cond, true_target, true_args, false_target, false_args) => {
        let next_true = if true_args.length() == 0 {
          true_target
        } else {
          make_edge_transfer_block(
            func, allocation, spill_slots, physical_regs, true_target, true_args,
          )
        }
        let next_false = if false_args.length() == 0 {
          false_target
        } else {
          make_edge_transfer_block(
            func, allocation, spill_slots, physical_regs, false_target, false_args,
          )
        }
        block.set_terminator(TermBranch(cond, next_true, [], next_false, []))
      }
      TermBranchCmp(
        lhs,
        rhs,
        cond,
        is_64,
        true_target,
        true_args,
        false_target,
        false_args
      ) => {
        let next_true = if true_args.length() == 0 {
          true_target
        } else {
          make_edge_transfer_block(
            func, allocation, spill_slots, physical_regs, true_target, true_args,
          )
        }
        let next_false = if false_args.length() == 0 {
          false_target
        } else {
          make_edge_transfer_block(
            func, allocation, spill_slots, physical_regs, false_target, false_args,
          )
        }
        block.set_terminator(
          TermBranchCmp(lhs, rhs, cond, is_64, next_true, [], next_false, []),
        )
      }
      TermBranchZero(
        value,
        is_nonzero,
        is_64,
        true_target,
        true_args,
        false_target,
        false_args
      ) => {
        let next_true = if true_args.length() == 0 {
          true_target
        } else {
          make_edge_transfer_block(
            func, allocation, spill_slots, physical_regs, true_target, true_args,
          )
        }
        let next_false = if false_args.length() == 0 {
          false_target
        } else {
          make_edge_transfer_block(
            func, allocation, spill_slots, physical_regs, false_target, false_args,
          )
        }
        block.set_terminator(
          TermBranchZero(value, is_nonzero, is_64, next_true, [], next_false, []),
        )
      }
      TermBranchCmpImm(
        value,
        imm,
        cond,
        is_64,
        true_target,
        true_args,
        false_target,
        false_args
      ) => {
        let next_true = if true_args.length() == 0 {
          true_target
        } else {
          make_edge_transfer_block(
            func, allocation, spill_slots, physical_regs, true_target, true_args,
          )
        }
        let next_false = if false_args.length() == 0 {
          false_target
        } else {
          make_edge_transfer_block(
            func, allocation, spill_slots, physical_regs, false_target, false_args,
          )
        }
        block.set_terminator(
          TermBranchCmpImm(value, imm, cond, is_64, next_true, [], next_false, []),
        )
      }
      _ => ()
    }
  }
}

///|
fn rewrite_operands_and_spills(
  func : @machv.Function,
  allocation : @regalloc.Allocation,
  spill_slots : Array[@machv.StackSlot],
  physical_regs : Array[@machv.PReg],
) -> Unit raise @regalloc.VerifyError {
  for block in func.blocks {
    let rewritten : Array[@machv.Instruction] = []
    for inst in block.instructions {
      let before : Array[@machv.Instruction] = []
      let after : Array[@machv.Instruction] = []
      let scratch_bindings : Array[ScratchBinding] = []
      for i, operand in inst.operands {
        inst.operands[i] = rewrite_spilled_operand(
          func, allocation, spill_slots, physical_regs, operand, before, after, scratch_bindings,
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
    if block.terminator is Some(term) {
      let before : Array[@machv.Instruction] = []
      block.terminator = Some(
        rewrite_terminator(
          func, allocation, spill_slots, physical_regs, term, before,
        ),
      )
      for reload in before {
        rewritten.push(reload)
      }
    }
    block.instructions.clear()
    for inst in rewritten {
      block.instructions.push(inst)
    }
  }
}

///|
fn materialize_entry_param_transfers(
  func : @machv.Function,
  allocation : @regalloc.Allocation,
  spill_slots : Array[@machv.StackSlot],
  physical_regs : Array[@machv.PReg],
) -> Unit raise @regalloc.VerifyError {
  if func.blocks.length() == 0 || func.params.length() == 0 {
    return
  }
  let entry = func.blocks[0]
  let int_moves : Array[@regalloc.ParallelMove] = []
  let f32_moves : Array[@regalloc.ParallelMove] = []
  let f64_moves : Array[@regalloc.ParallelMove] = []
  let vector_moves : Array[@regalloc.ParallelMove] = []
  for i, param in func.params {
    if i >= func.param_pregs.length() {
      continue
    }
    guard func.param_pregs[i] is Some(src_preg) else {
      // TODO(machv_regalloc): materialize stack-passed function-entry
      // parameters once MachV target lowering records incoming stack slots.
      continue
    }
    guard allocation.location_of(vreg_to_regalloc(param)) is Some(to) else {
      continue
    }
    let transfer : @regalloc.ParallelMove = {
      from: Reg(preg_to_regalloc(src_preg)),
      to,
      class: class_to_regalloc(param.class),
    }
    match param.class {
      Int => int_moves.push(transfer)
      Float32 => f32_moves.push(transfer)
      Float64 => f64_moves.push(transfer)
      Vector => vector_moves.push(transfer)
    }
  }
  let resolved : Array[@machv.Instruction] = []
  resolve_edge_moves(func, spill_slots, physical_regs, Int, int_moves, resolved)
  resolve_edge_moves(
    func,
    spill_slots,
    physical_regs,
    Float32,
    f32_moves,
    resolved,
  )
  resolve_edge_moves(
    func,
    spill_slots,
    physical_regs,
    Float64,
    f64_moves,
    resolved,
  )
  resolve_edge_moves(
    func,
    spill_slots,
    physical_regs,
    Vector,
    vector_moves,
    resolved,
  )
  if resolved.length() == 0 {
    return
  }
  let old = entry.instructions.copy()
  entry.instructions.clear()
  for inst in resolved {
    entry.instructions.push(inst)
  }
  for inst in old {
    entry.instructions.push(inst)
  }
}

///|
/// Run the simple linear-scan adapter and materialize its result into the small
/// MachV function model. Production VCode allocation uses
/// `allocate_registers_backtracking_output`.
pub fn allocate_and_apply_linear_scan(
  func : @machv.Function,
  physical_regs : Array[@machv.PReg],
) -> ApplyResult raise @regalloc.VerifyError {
  let allocation = allocate_with_optional_scratch(func, physical_regs)
  let spill_slots = ensure_spill_slots(func, allocation)
  materialize_edge_transfers(func, allocation, spill_slots, physical_regs)
  materialize_fixed_constraint_moves(
    func, allocation, spill_slots, physical_regs,
  )
  rewrite_operands_and_spills(func, allocation, spill_slots, physical_regs)
  materialize_entry_param_transfers(
    func, allocation, spill_slots, physical_regs,
  )
  { allocation, spill_slots }
}
