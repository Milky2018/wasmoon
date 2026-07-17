///|
pub struct VCodeAllocationEnvironment {
  allocatable_regs : Array[@vcode.PhysicalReg]
  spill_scratch_regs : Array[@vcode.PhysicalReg]
}

///|
pub fn VCodeAllocationEnvironment::new(
  allocatable_regs : Array[@vcode.PhysicalReg],
  spill_scratch_regs : Array[@vcode.PhysicalReg],
) -> VCodeAllocationEnvironment {
  {
    allocatable_regs: allocatable_regs.copy(),
    spill_scratch_regs: spill_scratch_regs.copy(),
  }
}

///|
pub suberror VCodeAllocationError {
  InvalidSelected(cause~ : @vcode.VCodeVerifyError)
  RegallocFailure(cause~ : @regalloc.VerifyError)
  MissingRegisterClass(class~ : @vcode.RegClass)
  MissingSpillScratch(class~ : @vcode.RegClass)
  AllocationConstructionRejected
  InvalidAllocation(cause~ : @vcode.AllocationVerifyError)
} derive(Debug)

///|
pub impl Show for VCodeAllocationError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
fn to_regalloc_class(class : @vcode.RegClass) -> @regalloc.RegClass {
  match class {
    Int => Int
    FpVector => Float
  }
}

///|
fn to_regalloc_preg(reg : @vcode.PhysicalReg) -> @regalloc.PhysicalReg {
  { id: reg.id, class: to_regalloc_class(reg.class) }
}

///|
fn[Inst] to_regalloc_vreg(
  function : @vcode.Function[Inst],
  value : @vcode.Value,
) -> @regalloc.VirtualReg {
  {
    id: function.value_index(value).unwrap(),
    class: to_regalloc_class(
      @vcode.reg_class_for_value_type(function.value_type(value).unwrap()),
    ),
  }
}

///|
fn[Inst] project_operand(
  function : @vcode.Function[Inst],
  operand : @vcode.Operand,
) -> @regalloc.Operand {
  let vreg = to_regalloc_vreg(function, operand.value)
  let projected = match operand.role {
    Use => @regalloc.Operand::use_reg(vreg)
    Def => @regalloc.Operand::def(vreg)
  }
  match operand.constraint {
    Any | TiedTo(_) => projected
    Fixed(reg) => projected.with_constraint(FixedReg(to_regalloc_preg(reg)))
  }
}

///|
fn[Inst] project_instruction(
  function : @vcode.Function[Inst],
  instruction : @vcode.Instruction,
) -> @regalloc.Instruction {
  let projected = @regalloc.Instruction::Instruction(
    function.instruction_index(instruction).unwrap(),
  )
  let operand_count = function.instruction_operand_count(instruction)
  for index in 0..<operand_count {
    let operand = function.instruction_operand_at(instruction, index).unwrap()
    let projected_operand = project_operand(function, operand)
    if operand.tie_id >= 0 {
      projected.add_operand(projected_operand.with_tie(operand.tie_id))
    } else {
      projected.add_operand(projected_operand)
    }
  }
  for successor_index in 0..<function.instruction_successor_count(instruction) {
    let edge = function
      .instruction_successor_at(instruction, successor_index)
      .unwrap()
    for argument in edge.arguments {
      projected.add_operand(
        @regalloc.Operand::use_reg(to_regalloc_vreg(function, argument)),
      )
    }
  }
  for index in 0..<function.instruction_clobber_count(instruction) {
    projected.add_clobber(
      to_regalloc_preg(
        function.instruction_clobber_at(instruction, index).unwrap(),
      ),
    )
  }
  projected
}

///|
fn[Inst] project_program(
  function : @vcode.Function[Inst],
  environment : VCodeAllocationEnvironment,
) -> @regalloc.Program {
  let physical_regs : Array[@regalloc.PhysicalReg] = []
  for reg in environment.allocatable_regs {
    let projected = to_regalloc_preg(reg)
    if !physical_regs.contains(projected) {
      physical_regs.push(projected)
    }
  }
  let program = @regalloc.Program::Program(physical_regs)
  for block_handle in function.layout() {
    let block = @regalloc.Block::Block(
      function.block_index(block_handle).unwrap(),
    )
    for instruction in function.block_body(block_handle) {
      block.append(project_instruction(function, instruction))
    }
    let terminator = function.block_terminator(block_handle).unwrap()
    block.append(project_instruction(function, terminator))
    for successor_index in 0..<function.instruction_successor_count(terminator) {
      let edge = function
        .instruction_successor_at(terminator, successor_index)
        .unwrap()
      block.add_successor(function.block_index(edge.target).unwrap())
    }
    program.add_block(block)
  }
  program
}

///|
fn value_size(ty : @semantic.ValueType) -> Int {
  match ty {
    I32 | F32 => 4
    I64 | F64 | Ptr64 | GcRef64 => 8
    V128 => 16
  }
}

///|
fn[Inst] vcode_reg_for_value(
  function : @vcode.Function[Inst],
  value : @vcode.Value,
  reg : @regalloc.PhysicalReg,
) -> @vcode.PhysicalReg {
  @vcode.PhysicalReg::new(
    reg.id,
    @vcode.reg_class_for_value_type(function.value_type(value).unwrap()),
  )
}

///|
fn find_environment_reg(
  environment : VCodeAllocationEnvironment,
  class : @vcode.RegClass,
) -> @vcode.PhysicalReg? {
  for reg in environment.allocatable_regs {
    if reg.class == class {
      return Some(reg)
    }
  }
  None
}

///|
fn find_spill_scratch(
  environment : VCodeAllocationEnvironment,
  class : @vcode.RegClass,
  used : Array[@vcode.PhysicalReg],
) -> @vcode.PhysicalReg? {
  for reg in environment.spill_scratch_regs {
    if reg.class == class && !used.contains(reg) {
      return Some(reg)
    }
  }
  None
}

///|
fn require_allocation_mutation(
  accepted : Bool,
) -> Unit raise VCodeAllocationError {
  if !accepted {
    raise AllocationConstructionRejected
  }
}

///|
pub fn[Inst] allocate_vcode(
  function : @vcode.Function[Inst],
  environment : VCodeAllocationEnvironment,
) -> @vcode.Allocation raise VCodeAllocationError {
  @vcode.verify_selected(function) catch {
    error => raise InvalidSelected(cause=error)
  }
  let program = project_program(function, environment)
  let raw = @regalloc.allocate(program) catch {
    error => raise RegallocFailure(cause=error)
  }
  let allocation = @vcode.Allocation::for_function(function)
  let spill_slots : Array[@vcode.StackSlot?] = Array::make(
    raw.spill_count(),
    None,
  )
  for value_index in 0..<function.value_count() {
    let value = function.value_at(value_index).unwrap()
    let ty = function.value_type(value).unwrap()
    let class = @vcode.reg_class_for_value_type(ty)
    let raw_vreg = to_regalloc_vreg(function, value)
    match raw.location_of(raw_vreg) {
      Some(Reg(reg)) =>
        require_allocation_mutation(
          allocation.assign_value(
            value,
            Register(vcode_reg_for_value(function, value, reg)),
          ),
        )
      Some(Spill(index)) => {
        let slot = match spill_slots[index] {
          Some(slot) => slot
          None => {
            let size = value_size(ty)
            let slot = allocation.create_stack_slot(ty, size, size)
            spill_slots[index] = Some(slot)
            slot
          }
        }
        require_allocation_mutation(allocation.assign_value(value, Stack(slot)))
      }
      None =>
        match find_environment_reg(environment, class) {
          Some(reg) =>
            require_allocation_mutation(
              allocation.assign_value(value, Register(reg)),
            )
          None => raise MissingRegisterClass(class~)
        }
    }
  }
  for block in function.layout() {
    let instructions = function.block_body(block)
    instructions.push(function.block_terminator(block).unwrap())
    for instruction in instructions {
      let operand_count = function.instruction_operand_count(instruction)
      let assigned : Array[@vcode.PhysicalReg?] = Array::make(
        operand_count,
        None,
      )
      let used_scratch : Array[@vcode.PhysicalReg] = []
      for operand_index in 0..<operand_count {
        let operand = function
          .instruction_operand_at(instruction, operand_index)
          .unwrap()
        let class = @vcode.reg_class_for_value_type(
          function.value_type(operand.value).unwrap(),
        )
        let reg = match operand.constraint {
          Fixed(required) => required
          TiedTo(tied_to) => assigned[tied_to].unwrap()
          Any =>
            match allocation.value_location(operand.value).unwrap() {
              Register(home) => home
              Stack(_) =>
                match find_spill_scratch(environment, class, used_scratch) {
                  Some(scratch) => {
                    used_scratch.push(scratch)
                    scratch
                  }
                  None => raise MissingSpillScratch(class~)
                }
            }
        }
        assigned[operand_index] = Some(reg)
        require_allocation_mutation(
          allocation.assign_operand(instruction, operand_index, reg),
        )
        match allocation.value_location(operand.value).unwrap() {
          Stack(slot) =>
            if operand.role == Use {
              require_allocation_mutation(
                allocation.add_edit(
                  @vcode.Edit::reload(
                    function.before(instruction).unwrap(),
                    operand.value,
                    slot,
                    reg,
                  ),
                ),
              )
            } else {
              require_allocation_mutation(
                allocation.add_edit(
                  @vcode.Edit::spill(
                    function.after(instruction).unwrap(),
                    operand.value,
                    reg,
                    slot,
                  ),
                ),
              )
            }
          Register(home) =>
            if home != reg {
              let point = if operand.role == Use {
                function.before(instruction).unwrap()
              } else {
                function.after(instruction).unwrap()
              }
              require_allocation_mutation(
                allocation.add_edit(
                  @vcode.Edit::register_move(
                    point,
                    operand.value,
                    if operand.role == Use {
                      home
                    } else {
                      reg
                    },
                    if operand.role == Use {
                      reg
                    } else {
                      home
                    },
                  ),
                ),
              )
            }
        }
      }
      let metadata = function.instruction_metadata(instruction).unwrap()
      for root in metadata.live_gc_roots {
        require_allocation_mutation(
          allocation.add_safepoint_root(
            instruction,
            root,
            allocation.value_location(root).unwrap(),
          ),
        )
      }
    }
    let terminator = function.block_terminator(block).unwrap()
    for successor_index in 0..<function.instruction_successor_count(terminator) {
      let edge = function
        .instruction_successor_at(terminator, successor_index)
        .unwrap()
      let parameters = function.block_parameters(edge.target)
      for index, argument in edge.arguments {
        let from = allocation.value_location(argument).unwrap()
        let to = allocation.value_location(parameters[index]).unwrap()
        if from != to {
          require_allocation_mutation(
            allocation.add_edit(
              @vcode.Edit::edge_move(block, successor_index, argument, from, to),
            ),
          )
        }
      }
    }
  }
  @vcode.verify_allocated(function, allocation) catch {
    error => raise InvalidAllocation(cause=error)
  }
  allocation
}
