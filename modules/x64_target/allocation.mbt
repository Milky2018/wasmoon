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
fn allocatable_physical_regs() -> Array[@vcode.PhysicalReg] {
  let regs : Array[@vcode.PhysicalReg] = []
  for index in [0, 1, 2, 3, 6, 7, 8, 9, 12, 13, 14, 15] {
    regs.push(int_physical(index))
  }
  for index in 0..<14 {
    regs.push(fp_physical(index))
  }
  regs
}

///|
fn spill_scratch_regs() -> Array[@vcode.PhysicalReg] {
  [int_physical(10), int_physical(11), fp_physical(14), fp_physical(15)]
}

///|
fn is_allocatable(reg : @vcode.PhysicalReg) -> Bool {
  match reg.class {
    Int => [0, 1, 2, 3, 6, 7, 8, 9, 12, 13, 14, 15].contains(reg.id)
    FpVector => reg.id >= 0 && reg.id < 14
  }
}

///|
fn is_scratch(reg : @vcode.PhysicalReg) -> Bool {
  match reg.class {
    Int => reg.id == 10 || reg.id == 11
    FpVector => reg.id == 14 || reg.id == 15
  }
}

///|
fn require_legal_register(
  reg : @vcode.PhysicalReg,
  allow_scratch : Bool,
) -> Unit raise X64AllocationError {
  if !is_allocatable(reg) && !(allow_scratch && is_scratch(reg)) {
    raise IllegalRegister(reg~)
  }
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
  function : @vcode.Function[X64Inst],
  on_phase? : ((String?) -> Unit)? = None,
  verify_allocation? : Bool = true,
) -> @vcode.Allocation raise X64AllocationError {
  let allocation = @vcode_regalloc.allocate_selected_vcode(
    function,
    @vcode_regalloc.VCodeAllocationEnvironment::new(
      allocatable_physical_regs(),
      spill_scratch_regs(),
    ),
    on_phase~,
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
