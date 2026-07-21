///|
pub suberror AArch64AllocationError {
  InvalidVCode(cause~ : TargetVCodeVerifyError)
  AllocatorFailure(cause~ : @vcode_regalloc.VCodeAllocationError)
  InvalidAllocation(cause~ : @vcode.AllocationVerifyError)
  IllegalRegister(reg~ : @vcode.PhysicalReg)
} derive(Debug)

///|
pub impl Show for AArch64AllocationError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
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
fn allocatable_physical_regs() -> Array[@vcode.PhysicalReg] {
  let regs : Array[@vcode.PhysicalReg] = []
  for index in 0..<16 {
    regs.push(int_physical(index))
  }
  for index in 19..<29 {
    regs.push(int_physical(index))
  }
  for index in 0..<16 {
    regs.push(fp_physical(index))
  }
  for index in 18..<32 {
    regs.push(fp_physical(index))
  }
  regs
}

///|
fn spill_scratch_regs() -> Array[@vcode.PhysicalReg] {
  [int_physical(16), int_physical(17), fp_physical(16), fp_physical(17)]
}

///|
fn is_allocatable(reg : @vcode.PhysicalReg) -> Bool {
  match reg.class {
    Int => (reg.id >= 0 && reg.id < 16) || (reg.id >= 19 && reg.id < 29)
    FpVector => (reg.id >= 0 && reg.id < 16) || (reg.id >= 18 && reg.id < 32)
  }
}

///|
fn is_scratch(reg : @vcode.PhysicalReg) -> Bool {
  (reg.id == 16 || reg.id == 17) && (reg.class == Int || reg.class == FpVector)
}

///|
fn require_legal_register(
  reg : @vcode.PhysicalReg,
  allow_scratch : Bool,
) -> Unit raise AArch64AllocationError {
  if !is_allocatable(reg) && !(allow_scratch && is_scratch(reg)) {
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
      Register(reg) => require_legal_register(reg, false)
      Stack(_) => ()
    }
  }
  for instruction_index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(instruction_index).unwrap()
    for operand_index in 0..<function.instruction_operand_count(instruction) {
      if allocation.operand_location(instruction, operand_index).unwrap()
        is Register(reg) {
        require_legal_register(reg, true)
      }
    }
  }
  for edit in allocation.edits() {
    match edit.kind {
      Spill(reg~, ..) | Reload(reg~, ..) => require_legal_register(reg, true)
      Move(from~, to~, ..) => {
        require_legal_register(from, true)
        require_legal_register(to, true)
      }
      EdgeMove(from~, to~, ..) => {
        if from is Register(reg) {
          require_legal_register(reg, true)
        }
        if to is Register(reg) {
          require_legal_register(reg, true)
        }
      }
    }
  }
}

///|
fn allocate_verified(
  function : @vcode.Function[AArch64Inst],
) -> @vcode.Allocation raise AArch64AllocationError {
  let allocation = @vcode_regalloc.allocate_selected_vcode(
    function,
    @vcode_regalloc.VCodeAllocationEnvironment::new(
      allocatable_physical_regs(),
      spill_scratch_regs(),
    ),
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
