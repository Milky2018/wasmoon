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
) -> @regalloc.OperandConstraint {
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
        .with_constraint(constraint_for_operand(inst, operand_index))
        .with_tie(operand.tie_id),
      )
    }
    Physical(_) => None
  }
}

///|
fn instruction_to_regalloc(inst : @machv.Instruction) -> @regalloc.Instruction {
  let out = @regalloc.Instruction::new(inst.id)
  for i, operand in inst.operands {
    if operand_to_regalloc(inst, i, operand) is Some(regalloc_operand) {
      out.add_operand(regalloc_operand)
    }
  }
  for clobber in inst.clobbers {
    out.add_clobber(preg_to_regalloc(clobber))
  }
  out
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
  let regs = physical_regs.map(preg_to_regalloc)
  let program = @regalloc.Program::new(regs)
  for block in func.blocks {
    let out_block = @regalloc.Block::new(block.id)
    if block_params_to_regalloc(block) is Some(param_defs) {
      out_block.append(param_defs)
    }
    for inst in block.instructions {
      out_block.append(instruction_to_regalloc(inst))
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
pub fn allocate_function(
  func : @machv.Function,
  physical_regs : Array[@machv.PReg],
) -> @regalloc.Allocation raise @regalloc.VerifyError {
  let program = project_function(func, physical_regs)
  let allocation = @regalloc.allocate(program)
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
fn find_scratch_reg(
  physical_regs : Array[@machv.PReg],
  class : @machv.RegClass,
) -> @machv.PReg? {
  for offset in 0..<physical_regs.length() {
    let i = physical_regs.length() - 1 - offset
    let preg = physical_regs[i]
    if preg.class == class {
      return Some(preg)
    }
  }
  for offset in 0..<physical_regs.length() {
    let i = physical_regs.length() - 1 - offset
    let preg = physical_regs[i]
    if class_to_regalloc(preg.class) == class_to_regalloc(class) {
      return Some({ index: preg.index, class })
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
) -> @regalloc.Allocation raise @regalloc.VerifyError {
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
              { reg: physical, role: operand.role, tie_id: operand.tie_id }
            }
            None => operand
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
) -> @machv.Reg {
  match reg {
    Virtual(vreg) =>
      match allocation.location_of(vreg_to_regalloc(vreg)) {
        Some(Spill(slot)) =>
          match find_scratch_reg(physical_regs, vreg.class) {
            Some(scratch) => {
              // TODO(machv_regalloc): reserve distinct terminator reload
              // temporaries when multiple spilled terminator operands of the
              // same register class are live at the same edge.
              let physical : @machv.Reg = Physical(scratch)
              let reload = func.new_inst(Load(spill_slots[slot]))
              reload.add_operand(@machv.Operand::def(physical))
              before.push(reload)
              physical
            }
            None => reg
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
) -> Array[@machv.Reg] {
  let out : Array[@machv.Reg] = []
  for reg in regs {
    out.push(
      rewrite_spilled_reg(
        func, allocation, spill_slots, physical_regs, reg, before,
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
) -> @machv.Terminator {
  match term {
    TermJump(target, args) =>
      TermJump(
        target,
        rewrite_reg_array(
          func, allocation, spill_slots, physical_regs, args, before,
        ),
      )
    TermBranch(cond, true_target, true_args, false_target, false_args) =>
      TermBranch(
        rewrite_spilled_reg(
          func, allocation, spill_slots, physical_regs, cond, before,
        ),
        true_target,
        rewrite_reg_array(
          func, allocation, spill_slots, physical_regs, true_args, before,
        ),
        false_target,
        rewrite_reg_array(
          func, allocation, spill_slots, physical_regs, false_args, before,
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
          func, allocation, spill_slots, physical_regs, lhs, before,
        ),
        rewrite_spilled_reg(
          func, allocation, spill_slots, physical_regs, rhs, before,
        ),
        cond,
        is_64,
        true_target,
        rewrite_reg_array(
          func, allocation, spill_slots, physical_regs, true_args, before,
        ),
        false_target,
        rewrite_reg_array(
          func, allocation, spill_slots, physical_regs, false_args, before,
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
          func, allocation, spill_slots, physical_regs, value, before,
        ),
        is_nonzero,
        is_64,
        true_target,
        rewrite_reg_array(
          func, allocation, spill_slots, physical_regs, true_args, before,
        ),
        false_target,
        rewrite_reg_array(
          func, allocation, spill_slots, physical_regs, false_args, before,
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
          func, allocation, spill_slots, physical_regs, value, before,
        ),
        imm,
        cond,
        is_64,
        true_target,
        rewrite_reg_array(
          func, allocation, spill_slots, physical_regs, true_args, before,
        ),
        false_target,
        rewrite_reg_array(
          func, allocation, spill_slots, physical_regs, false_args, before,
        ),
      )
    TermReturn(results) =>
      TermReturn(
        rewrite_reg_array(
          func, allocation, spill_slots, physical_regs, results, before,
        ),
      )
    TermTrap(_) => term
    TermBrTable(value, targets, default_target) =>
      TermBrTable(
        rewrite_spilled_reg(
          func, allocation, spill_slots, physical_regs, value, before,
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
fn machv_class_for_move(class : @regalloc.RegClass) -> @machv.RegClass {
  match class {
    Int => Int
    Float =>
      // TODO(machv_regalloc): preserve Float32 vs Float64 lane width through
      // the pure regalloc move resolver instead of defaulting edge copies to F64.
      Float64
    Vector => Vector
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
) -> Unit {
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
      // TODO(machv_regalloc): route stack-to-stack edge copies through a
      // reserved scratch register that is proven dead on the edge.
      ()
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
) -> Array[@machv.Instruction] {
  let out : Array[@machv.Instruction] = []
  if args.length() == 0 {
    return out
  }
  guard find_block(func, target_id) is Some(target) else { return out }
  guard target.params.length() == args.length() else { return out }
  let moves : Array[@regalloc.ParallelMove] = []
  for i in 0..<args.length() {
    let param = target.params[i]
    guard source_location(args[i], allocation) is Some(from) else { continue }
    guard allocation.location_of(vreg_to_regalloc(param)) is Some(to) else {
      continue
    }
    moves.push({ from, to, class: class_to_regalloc(param.class) })
  }
  if moves.length() == 0 {
    return out
  }
  let scratch_int = scratch_regs_for_class(physical_regs, Int)
  let scratch_float = scratch_regs_for_class(physical_regs, Float)
  let resolved = @regalloc.resolve_parallel_moves(
    moves, scratch_int, scratch_float,
  )
  for mv in resolved {
    append_location_move(
      func,
      spill_slots,
      machv_class_for_move(mv.class),
      mv.from,
      mv.to,
      out,
    )
  }
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
) -> Unit {
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
) -> Int {
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
) -> Unit {
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
pub fn allocate_and_apply(
  func : @machv.Function,
  physical_regs : Array[@machv.PReg],
) -> ApplyResult raise @regalloc.VerifyError {
  let allocation = allocate_with_optional_scratch(func, physical_regs)
  let spill_slots = ensure_spill_slots(func, allocation)
  rewrite_operands_and_spills(func, allocation, spill_slots, physical_regs)
  materialize_edge_transfers(func, allocation, spill_slots, physical_regs)
  { allocation, spill_slots }
}
