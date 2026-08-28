///|
pub suberror X64AllocationError {
  InvalidVCode(cause~ : TargetVCodeVerifyError)
  AllocatorFailure(cause~ : @vcode_regalloc.VCodeAllocationError)
  InvalidAllocation(cause~ : @vcode.AllocationVerifyError)
  IllegalRegister(reg~ : @vcode.PhysicalReg)
} derive(Debug)

///|
pub impl Show for X64AllocationError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
fn int_physical(index : Int) -> @vcode.PhysicalReg {
  @vcode.PhysicalReg::new(index, Int)
}

///|
fn fp_physical(index : Int) -> @vcode.PhysicalReg {
  @vcode.PhysicalReg::new(index, FpVector)
}

///|
fn int_transfer_scratch() -> @vcode.PhysicalReg {
  int_physical(15)
}

///|
fn fp_transfer_scratch() -> @vcode.PhysicalReg {
  fp_physical(13)
}

///|
priv enum AllocationRegisterRole {
  ValueHome
  SpillEdit
  FixedOperand
  SpillEditFixedOperand
  Transfer
  Emitter
  Reserved
}

///|
fn allocation_register_role(reg : @vcode.PhysicalReg) -> AllocationRegisterRole {
  match reg.class {
    Int =>
      if [0, 1, 2, 3, 6, 7, 8, 9, 12, 13, 14].contains(reg.id) {
        ValueHome
      } else if reg.id == 10 {
        SpillEditFixedOperand
      } else if reg.id == 11 {
        FixedOperand
      } else if reg.id == 15 {
        Transfer
      } else {
        Reserved
      }
    FpVector =>
      if reg.id >= 0 && reg.id < 13 {
        ValueHome
      } else if reg.id == 13 {
        Transfer
      } else if reg.id == 14 {
        SpillEdit
      } else if reg.id == 15 {
        Emitter
      } else {
        Reserved
      }
  }
}

///|
fn AllocationRegisterRole::allows_value_home(
  self : AllocationRegisterRole,
) -> Bool {
  match self {
    ValueHome => true
    SpillEdit
    | FixedOperand
    | SpillEditFixedOperand
    | Transfer
    | Emitter
    | Reserved => false
  }
}

///|
fn AllocationRegisterRole::allows_spill_edit(
  self : AllocationRegisterRole,
) -> Bool {
  match self {
    SpillEdit | SpillEditFixedOperand => true
    _ => false
  }
}

///|
fn AllocationRegisterRole::allows_fixed_operand(
  self : AllocationRegisterRole,
) -> Bool {
  match self {
    FixedOperand | SpillEditFixedOperand => true
    _ => false
  }
}

///|
fn is_allocatable(reg : @vcode.PhysicalReg) -> Bool {
  allocation_register_role(reg).allows_value_home()
}

///|
fn allocatable_physical_regs() -> Array[@vcode.PhysicalReg] {
  let regs : Array[@vcode.PhysicalReg] = []
  for index in 0..<16 {
    let reg = int_physical(index)
    if allocation_register_role(reg).allows_value_home() {
      regs.push(reg)
    }
  }
  for index in 0..<16 {
    let reg = fp_physical(index)
    if allocation_register_role(reg).allows_value_home() {
      regs.push(reg)
    }
  }
  regs
}

///|
fn spill_scratch_regs() -> Array[@vcode.PhysicalReg] {
  let regs : Array[@vcode.PhysicalReg] = []
  for index in 0..<16 {
    let reg = int_physical(index)
    if allocation_register_role(reg).allows_spill_edit() {
      regs.push(reg)
    }
  }
  for index in 0..<16 {
    let reg = fp_physical(index)
    if allocation_register_role(reg).allows_spill_edit() {
      regs.push(reg)
    }
  }
  regs
}

///|
fn fixed_operand_only_regs() -> Array[@vcode.PhysicalReg] {
  let regs : Array[@vcode.PhysicalReg] = []
  for index in 0..<16 {
    let reg = int_physical(index)
    if allocation_register_role(reg) is FixedOperand {
      regs.push(reg)
    }
  }
  regs
}

///|
fn require_legal_value_register(
  reg : @vcode.PhysicalReg,
) -> Unit raise X64AllocationError {
  if !allocation_register_role(reg).allows_value_home() {
    raise IllegalRegister(reg~)
  }
}

///|
fn require_legal_operand_register(
  function : @vcode.Function[X64Inst],
  instruction : @vcode.Instruction,
  operand_index : Int,
  reg : @vcode.PhysicalReg,
) -> Unit raise X64AllocationError {
  let role = allocation_register_role(reg)
  if role.allows_value_home() {
    return
  }
  let operand = function
    .instruction_operand_at(instruction, operand_index)
    .unwrap()
  if operand.constraint is Fixed(required) &&
    required == reg &&
    role.allows_fixed_operand() {
    return
  }
  raise IllegalRegister(reg~)
}

///|
fn require_legal_edit_register(
  function : @vcode.Function[X64Inst],
  edit : @vcode.Edit,
  reg : @vcode.PhysicalReg,
  source : Bool,
) -> Unit raise X64AllocationError {
  let role = allocation_register_role(reg)
  if role.allows_value_home() || role.allows_spill_edit() {
    return
  }
  if role.allows_fixed_operand() && edit.point() is Some(point) {
    let required_role = match (point.placement(), source) {
      (Before, false) => Some(@vcode.Use)
      (After, true) => Some(Def)
      _ => None
    }
    if required_role is Some(role) {
      let instruction = point.instruction()
      let edit_value = match edit.kind() {
        Spill(value~, ..)
        | Reload(value~, ..)
        | Move(value~, ..)
        | EdgeMove(value~, ..) => value
      }
      for operand in function.instruction_operands(instruction) {
        if operand.value == edit_value &&
          operand.role == role &&
          operand.constraint == Fixed(reg) {
          return
        }
      }
    }
  }
  raise IllegalRegister(reg~)
}

///|
pub fn verify_allocation(
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
) -> Unit raise X64AllocationError {
  verify_vcode(function) catch {
    error => raise InvalidVCode(cause=error)
  }
  @vcode.verify_allocated(function, allocation) catch {
    error => raise InvalidAllocation(cause=error)
  }
  verify_target_allocation(function, allocation)
}

///|
fn verify_target_allocation(
  function : @vcode.Function[X64Inst],
  allocation : @vcode.Allocation,
) -> Unit raise X64AllocationError {
  for index in 0..<function.value_count() {
    let value = function.value_at(index).unwrap()
    match allocation.value_location(value).unwrap() {
      Register(reg) => require_legal_value_register(reg)
      Stack(_) => ()
    }
  }
  for instruction_index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(instruction_index).unwrap()
    for operand_index in 0..<function.instruction_operand_count(instruction) {
      if allocation.operand_location(instruction, operand_index).unwrap()
        is Register(reg) {
        require_legal_operand_register(
          function, instruction, operand_index, reg,
        )
      }
    }
  }
  for edit in allocation.edits() {
    match edit.kind {
      Spill(reg~, ..) => require_legal_edit_register(function, edit, reg, true)
      Reload(reg~, ..) =>
        require_legal_edit_register(function, edit, reg, false)
      Move(from~, to~, ..) => {
        require_legal_edit_register(function, edit, from, true)
        require_legal_edit_register(function, edit, to, false)
      }
      EdgeMove(from~, to~, ..) => {
        if from is Register(reg) {
          require_legal_edit_register(function, edit, reg, true)
        }
        if to is Register(reg) {
          require_legal_edit_register(function, edit, reg, false)
        }
      }
    }
  }
}

///|
fn allocate_verified(
  function : @vcode.Function[X64Inst],
  on_phase? : ((String?) -> Unit)? = None,
  on_statistics? : ((@vcode.RegallocLoopStatistics) -> Unit)? = None,
  verify_allocation? : Bool = true,
) -> @vcode.Allocation raise X64AllocationError {
  let allocation = @vcode_regalloc.allocate_selected_vcode(
    function,
    @vcode_regalloc.VCodeAllocationEnvironment::new(
      allocatable_physical_regs(),
      spill_scratch_regs(),
    ).with_fixed_operand_regs(fixed_operand_only_regs()),
    on_phase~,
    on_statistics~,
    verify=verify_allocation,
  ) catch {
    error => raise AllocatorFailure(cause=error)
  }
  verify_target_allocation(function, allocation)
  allocation
}

///|
pub fn allocate(
  function : @vcode.Function[X64Inst],
) -> @vcode.Allocation raise X64AllocationError {
  verify_vcode(function) catch {
    error => raise InvalidVCode(cause=error)
  }
  allocate_verified(function)
}
