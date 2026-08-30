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
fn[Inst] add_plan_transfer(
  builder : @vcode.AllocationBuilder[Inst],
  instruction : Int,
  placement : @vcode.PointPlacement,
  value : Int,
  from : @vcode.AllocationLocation,
  to : @vcode.AllocationLocation,
) -> Unit raise VCodeAllocationError {
  if !builder.add_transfer(instruction, placement, value, from, to) {
    raise AllocationConstructionRejected
  }
}

///|
/// Allocates VCode that has already passed `@vcode.verify_selected`.
///
/// The caller must not mutate `function` between validation and this call.
/// Prefer `allocate_vcode` unless validation is owned by an aggregate compile
/// pipeline.
pub struct AllocationSession {
  priv core : @regalloc.AllocationSession
}

///|
pub fn AllocationSession::new() -> AllocationSession {
  { core: @regalloc.AllocationSession::new(), }
}

///|
pub fn[Inst] AllocationSession::allocate_selected_vcode(
  self : AllocationSession,
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
  let plan = self.core.allocate_function(
    function_view,
    @regalloc.MachineEnv::new(
      environment.allocatable_regs,
      environment.spill_scratch_regs,
    )
    .with_operand_scratch_regs([])
    .with_fixed_operand_regs(environment.fixed_operand_regs),
    config=RegallocConfig(verify~, observer~, statistics_observer~),
  ) catch {
    error => raise RegallocFailure(cause=error)
  }
  let spill_owners : Array[Int] = []
  let spill_sizes : Array[Int] = []
  let spill_alignments : Array[Int] = []
  for slot in 0..<plan.spill_count() {
    let spec = plan.spill_slot(slot).unwrap()
    spill_owners.push(plan.spill_slot_owner(slot).unwrap())
    spill_sizes.push(spec.size)
    spill_alignments.push(spec.alignment)
  }
  guard @vcode.AllocationBuilder::from_plan_storage(
      function,
      plan.value_location_storage(),
      plan.operand_location_storage(),
      spill_owners,
      spill_sizes,
      spill_alignments,
    )
    is Some(builder) else {
    raise AllocationConstructionRejected
  }
  for edit_index in 0..<plan.edit_count() {
    let edit = plan.edit_at(edit_index).unwrap()
    match edit.position {
      Before(instruction_id) =>
        add_plan_transfer(
          builder,
          instruction_id,
          Before,
          edit.value.id,
          edit.from,
          edit.to,
        )
      After(instruction_id) =>
        add_plan_transfer(
          builder,
          instruction_id,
          After,
          edit.value.id,
          edit.from,
          edit.to,
        )
      Edge(source_block~, successor_index~) =>
        if !builder.add_edge_transfer(
            source_block,
            successor_index,
            edit.value.id,
            edit.from,
            edit.to,
          ) {
          raise AllocationConstructionRejected
        }
    }
  }
  if !builder.add_function_safepoint_roots() {
    raise AllocationConstructionRejected
  }
  let allocation = builder.finish()
  if verify {
    @vcode.verify_allocation_invariants(function, allocation) catch {
      error => raise InvalidAllocation(cause=error)
    }
  }
  allocation
}

///|
/// Allocate one selected function with an ephemeral session.
pub fn[Inst] allocate_selected_vcode(
  function : @vcode.Function[Inst],
  environment : VCodeAllocationEnvironment,
  on_phase? : ((String?) -> Unit)? = None,
  on_statistics? : ((@vcode.RegallocLoopStatistics) -> Unit)? = None,
  verify? : Bool = true,
) -> @vcode.Allocation raise VCodeAllocationError {
  AllocationSession::new().allocate_selected_vcode(
    function,
    environment,
    on_phase~,
    on_statistics~,
    verify~,
  )
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
