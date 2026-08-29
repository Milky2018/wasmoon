///|
pub suberror AArch64AllocationError {
  InvalidVCode(cause~ : TargetVCodeVerifyError)
  AllocatorFailure(cause~ : @vcode_regalloc.VCodeAllocationError)
  InvalidAllocation(cause~ : @vcode.AllocationVerifyError)
  IllegalRegister(reg~ : @vcode.PhysicalReg)
} derive(Debug)

///|
pub impl Show for AArch64AllocationError with fn output(self, logger) {
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
/// IP0 is excluded from allocation so late emission can finalize arbitrary
/// stack offsets without changing the allocation.
fn stack_address_scratch() -> @vcode.PhysicalReg {
  int_physical(16)
}

///|
/// X15 is reserved exclusively for target-level parallel transfers.
fn int_transfer_scratch() -> @vcode.PhysicalReg {
  int_physical(15)
}

///|
fn fp_transfer_scratch() -> @vcode.PhysicalReg {
  fp_physical(18)
}

///|
/// IP1 carries allocator-inserted integer transfers and instruction-local
/// temporary values.
fn int_instruction_scratch() -> @vcode.PhysicalReg {
  int_physical(17)
}

///|
fn int_transfer_scratch_regs() -> Array[@vcode.PhysicalReg] {
  [int_transfer_scratch()]
}

///|
fn fp_transfer_scratch_regs() -> Array[@vcode.PhysicalReg] {
  [fp_transfer_scratch()]
}

///|
fn transfer_scratch_for_type(ty : @semantic.ValueType) -> @vcode.PhysicalReg {
  match @vcode.reg_class_for_value_type(ty) {
    Int => int_transfer_scratch()
    Float | Vector | FpVector => fp_transfer_scratch()
  }
}

///|
priv enum AllocationRegisterRole {
  ValueHome
  SpillEdit
  Transfer
  StackAddress
  Reserved
}

///|
fn allocation_register_role(reg : @vcode.PhysicalReg) -> AllocationRegisterRole {
  match reg.class {
    Int =>
      if (reg.id >= 0 && reg.id < 15) || (reg.id >= 19 && reg.id < 29) {
        ValueHome
      } else if reg.id == 15 {
        Transfer
      } else if reg.id == 16 {
        StackAddress
      } else if reg.id == 17 {
        SpillEdit
      } else {
        Reserved
      }
    Float | Vector | FpVector =>
      if (reg.id >= 0 && reg.id < 16) || (reg.id >= 19 && reg.id < 32) {
        ValueHome
      } else if reg.id == 16 || reg.id == 17 {
        SpillEdit
      } else if reg.id == 18 {
        Transfer
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
    SpillEdit | Transfer | StackAddress | Reserved => false
  }
}

///|
fn AllocationRegisterRole::allows_spill_edit(
  self : AllocationRegisterRole,
) -> Bool {
  self is SpillEdit
}

///|
fn is_allocatable(reg : @vcode.PhysicalReg) -> Bool {
  allocation_register_role(reg).allows_value_home()
}

///|
fn allocatable_physical_regs() -> Array[@vcode.PhysicalReg] {
  let regs : Array[@vcode.PhysicalReg] = []
  for index in 0..<32 {
    let reg = int_physical(index)
    if allocation_register_role(reg).allows_value_home() {
      regs.push(reg)
    }
  }
  for index in 0..<32 {
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
  for index in 0..<32 {
    let reg = int_physical(index)
    if allocation_register_role(reg).allows_spill_edit() {
      regs.push(reg)
    }
  }
  for index in 0..<32 {
    let reg = fp_physical(index)
    if allocation_register_role(reg).allows_spill_edit() {
      regs.push(reg)
    }
  }
  regs
}

///|
fn require_legal_value_register(
  reg : @vcode.PhysicalReg,
) -> Unit raise AArch64AllocationError {
  if !allocation_register_role(reg).allows_value_home() {
    raise IllegalRegister(reg~)
  }
}

///|
fn require_legal_operand_register(
  reg : @vcode.PhysicalReg,
) -> Unit raise AArch64AllocationError {
  if !allocation_register_role(reg).allows_value_home() {
    raise IllegalRegister(reg~)
  }
}

///|
fn require_legal_edit_register(
  reg : @vcode.PhysicalReg,
) -> Unit raise AArch64AllocationError {
  let role = allocation_register_role(reg)
  if !role.allows_value_home() && !role.allows_spill_edit() {
    raise IllegalRegister(reg~)
  }
}

///|
pub fn verify_allocation(
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
) -> Unit raise AArch64AllocationError {
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
  function : @vcode.Function[AArch64Inst],
  allocation : @vcode.Allocation,
) -> Unit raise AArch64AllocationError {
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
        require_legal_operand_register(reg)
      }
    }
  }
  for edit in allocation.edits() {
    match edit.kind {
      Spill(reg~, ..) | Reload(reg~, ..) => require_legal_edit_register(reg)
      Move(from~, to~, ..) => {
        require_legal_edit_register(from)
        require_legal_edit_register(to)
      }
      EdgeMove(from~, to~, ..) => {
        if from is Register(reg) {
          require_legal_edit_register(reg)
        }
        if to is Register(reg) {
          require_legal_edit_register(reg)
        }
      }
    }
  }
}

///|
fn allocate_verified(
  function : @vcode.Function[AArch64Inst],
  on_phase? : ((String?) -> Unit)? = None,
  on_statistics? : ((@vcode.RegallocLoopStatistics) -> Unit)? = None,
  verify_allocation? : Bool = true,
  allocation_session? : @vcode_regalloc.AllocationSession = @vcode_regalloc.AllocationSession::new(),
  allocation_environment? : @vcode_regalloc.VCodeAllocationEnvironment = @vcode_regalloc.VCodeAllocationEnvironment::new(
    allocatable_physical_regs(),
    spill_scratch_regs(),
  ),
) -> @vcode.Allocation raise AArch64AllocationError {
  let allocation = allocation_session.allocate_selected_vcode(
    function,
    allocation_environment,
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
  function : @vcode.Function[AArch64Inst],
) -> @vcode.Allocation raise AArch64AllocationError {
  verify_vcode(function) catch {
    error => raise InvalidVCode(cause=error)
  }
  allocate_verified(function)
}
