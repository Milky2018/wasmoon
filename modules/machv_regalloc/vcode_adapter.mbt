///|
pub struct VCodeAllocationEnvironment {
  allocatable_regs : Array[@vcode.PhysicalReg]
  spill_scratch_regs : Array[@vcode.PhysicalReg]
  fixed_operand_regs : Array[@vcode.PhysicalReg]
}

///|
pub fn VCodeAllocationEnvironment::new(
  allocatable_regs : Array[@vcode.PhysicalReg],
  spill_scratch_regs : Array[@vcode.PhysicalReg],
) -> VCodeAllocationEnvironment {
  {
    allocatable_regs: allocatable_regs.copy(),
    spill_scratch_regs: spill_scratch_regs.copy(),
    fixed_operand_regs: [],
  }
}

///|
/// Declare reserved registers that selected VCode may name only through fixed
/// operand constraints.
pub fn VCodeAllocationEnvironment::with_fixed_operand_regs(
  self : VCodeAllocationEnvironment,
  fixed_operand_regs : Array[@vcode.PhysicalReg],
) -> VCodeAllocationEnvironment {
  { ..self, fixed_operand_regs: fixed_operand_regs.copy(), }
}

///|
pub suberror VCodeAllocationError {
  InvalidSelected(cause~ : @vcode.VCodeVerifyError)
  RegallocFailure(cause~ : @regalloc.VerifyError)
  AllocationConstructionRejected
  InvalidAllocation(cause~ : @vcode.AllocationVerifyError)
} derive(Debug)

///|
pub impl Show for VCodeAllocationError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
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
  { id: reg.id, class: to_regalloc_class(reg.class), }
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
fn require_allocation_mutation(
  accepted : Bool,
) -> Unit raise VCodeAllocationError {
  if !accepted {
    raise AllocationConstructionRejected
  }
}

///|
fn[Inst] materialize_plan_location(
  function : @vcode.Function[Inst],
  allocation : @vcode.Allocation,
  plan : @regalloc.AllocationPlan,
  spill_slots : Array[@vcode.StackSlot?],
  value : @vcode.Value,
  location : @regalloc.Location,
) -> @vcode.Location {
  match location {
    Reg(reg) => Register(vcode_reg_for_value(function, value, reg))
    Spill(index) => {
      let slot = match spill_slots[index] {
        Some(slot) => slot
        None => {
          let ty = function.value_type(value).unwrap()
          let spec = plan.spill_slot(index).unwrap()
          let slot = allocation.create_stack_slot(ty, spec.size, spec.alignment)
          spill_slots[index] = Some(slot)
          slot
        }
      }
      Stack(slot)
    }
  }
}

///|
fn add_materialized_transfer(
  allocation : @vcode.Allocation,
  point : @vcode.ProgramPoint,
  value : @vcode.Value,
  from : @vcode.Location,
  to : @vcode.Location,
) -> Unit raise VCodeAllocationError {
  let edit = match (from, to) {
    (Register(from_reg), Register(to_reg)) =>
      @vcode.Edit::register_move(point, value, from_reg, to_reg)
    (Register(reg), Stack(slot)) => @vcode.Edit::spill(point, value, reg, slot)
    (Stack(slot), Register(reg)) => @vcode.Edit::reload(point, value, slot, reg)
    (Stack(_), Stack(_)) => raise AllocationConstructionRejected
  }
  require_allocation_mutation(allocation.add_edit(edit))
}

///|
/// Allocates VCode that has already passed `@vcode.verify_selected`.
///
/// The caller must not mutate `function` between validation and this call.
/// Prefer `allocate_vcode` unless validation is owned by an aggregate compile
/// pipeline.
pub fn[Inst] allocate_selected_vcode(
  function : @vcode.Function[Inst],
  environment : VCodeAllocationEnvironment,
  on_phase? : ((String?) -> Unit)? = None,
  on_statistics? : ((@vcode.RegallocLoopStatistics) -> Unit)? = None,
  verify? : Bool = true,
) -> @vcode.Allocation raise VCodeAllocationError {
  // Translate the allocator's phase enum to a name here so neither the
  // allocator nor the event enum has to know about the other (ISS-371).
  let observer : ((@regalloc.RegallocPhase?) -> Unit)? = match on_phase {
    Some(notify) =>
      Some(phase => {
        notify(
          match phase {
            Some(p) => Some("\{p}")
            None => None
          },
        )
      })
    None => None
  }
  let statistics_observer : ((@regalloc.BundleAllocationStatistics) -> Unit)? = match
    on_statistics {
    Some(notify) =>
      Some(statistics => {
        notify({
          queue_pops: statistics.queue_pops(),
          register_probes: statistics.register_probes(),
          occupied_segments_scanned: statistics.occupied_segments_scanned(),
          conflicts: statistics.conflicts(),
          evictions: statistics.evictions(),
          bundle_splits: statistics.bundle_splits(),
          second_chance_attempts: statistics.second_chance_attempts(),
          max_queue_length: statistics.max_queue_length(),
        })
      })
    None => None
  }
  if on_phase is Some(notify) {
    notify(Some("function_view"))
  }
  let function_view = VCodeFunctionView::new(function)
  let plan = @regalloc.allocate_function(
    function_view,
    @regalloc.MachineEnv::new(
      environment.allocatable_regs.map(reg => to_regalloc_preg(reg)),
      environment.spill_scratch_regs.map(reg => to_regalloc_preg(reg)),
    )
    .with_operand_scratch_regs([])
    .with_fixed_operand_regs(
      environment.fixed_operand_regs.map(reg => to_regalloc_preg(reg)),
    ),
    config=RegallocConfig(verify~, observer~, statistics_observer~),
  ) catch {
    error => raise RegallocFailure(cause=error)
  }
  let allocation = @vcode.Allocation::for_function(function)
  let spill_slots : Array[@vcode.StackSlot?] = Array::make(
    plan.spill_count(),
    None,
  )
  for value_index in 0..<function.value_count() {
    let value = function.value_at(value_index).unwrap()
    guard plan.value_location(value_index) is Some(location) else {
      raise AllocationConstructionRejected
    }
    require_allocation_mutation(
      allocation.assign_value(
        value,
        materialize_plan_location(
          function, allocation, plan, spill_slots, value, location,
        ),
      ),
    )
  }
  for assignment in plan.operand_assignments() {
    let instruction = function.instruction_at(assignment.instruction).unwrap()
    let operand = function
      .instruction_operand_at(instruction, assignment.operand)
      .unwrap()
    require_allocation_mutation(
      allocation.assign_operand_location(
        instruction,
        assignment.operand,
        materialize_plan_location(
          function,
          allocation,
          plan,
          spill_slots,
          operand.value,
          assignment.location,
        ),
      ),
    )
  }
  for edit in plan.edits() {
    let value = function.value_at(edit.value.id).unwrap()
    let from = materialize_plan_location(
      function,
      allocation,
      plan,
      spill_slots,
      value,
      edit.from,
    )
    let to = materialize_plan_location(
      function,
      allocation,
      plan,
      spill_slots,
      value,
      edit.to,
    )
    match edit.position {
      Before(instruction_id) =>
        add_materialized_transfer(
          allocation,
          function
          .before(function.instruction_at(instruction_id).unwrap())
          .unwrap(),
          value,
          from,
          to,
        )
      After(instruction_id) =>
        add_materialized_transfer(
          allocation,
          function
          .after(function.instruction_at(instruction_id).unwrap())
          .unwrap(),
          value,
          from,
          to,
        )
      Edge(source_block~, successor_index~) =>
        require_allocation_mutation(
          allocation.add_edit(
            @vcode.Edit::edge_move(
              function.block_at(source_block).unwrap(),
              successor_index,
              value,
              from,
              to,
            ),
          ),
        )
    }
  }
  for block in function.layout() {
    let instructions = function.block_body(block)
    instructions.push(function.block_terminator(block).unwrap())
    for instruction in instructions {
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
  }
  if verify {
    @vcode.verify_allocation_invariants(function, allocation) catch {
      error => raise InvalidAllocation(cause=error)
    }
  }
  allocation
}

///|
pub fn[Inst] allocate_vcode(
  function : @vcode.Function[Inst],
  environment : VCodeAllocationEnvironment,
) -> @vcode.Allocation raise VCodeAllocationError {
  @vcode.verify_selected(function) catch {
    error => raise InvalidSelected(cause=error)
  }
  allocate_selected_vcode(function, environment)
}
