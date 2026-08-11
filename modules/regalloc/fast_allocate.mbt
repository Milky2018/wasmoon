///|
fn[F : FunctionView] allocate_fast_segments(
  function : F,
  environment : MachineEnv,
  ranges : LiveRangeSet,
  segments : Array[AllocationSegment],
) -> Unit {
  let ending : Array[Array[Array[Int]]] = Array::makei(function.block_count(), block => {
    Array::makei(function.block_instructions(block).length() * 2 + 2, _ => [])
  })
  for segment in segments {
    ending[segment.range.end.block][segment.range.end.inst + 1].push(segment.id)
  }
  let clobbers = build_register_clobber_index(function, ranges.block_order)
  let active : Array[Int?] = Array::make(
    environment.allocatable_regs.length(),
    None,
  )
  let mut block = function.block_count()
  while block > 0 {
    block = block - 1
    active.fill(None)
    let mut point = function.block_instructions(block).length() * 2
    while point >= -1 {
      for register in 0..<active.length() {
        if active[register] is Some(segment_id) &&
          segments[segment_id].range.start.inst > point {
          active[register] = None
        }
      }
      for segment_id in ending[block][point + 1] {
        let segment = segments[segment_id]
        let mut selected = -1
        let mut victim = -1
        for register in 0..<environment.allocatable_regs.length() {
          let reg = environment.allocatable_regs[register]
          if reg.class != segment.value.class ||
            first_clobber_point(segment, reg, clobbers) is Some(_) {
            continue
          }
          match active[register] {
            None => {
              selected = register
              break
            }
            Some(occupant) =>
              if !segments[occupant].has_fixed_constraint &&
                segments[occupant].weight < segment.weight &&
                (
                  victim < 0 ||
                  segments[occupant].weight <
                  segments[active[victim].unwrap()].weight
                ) {
                victim = register
              }
          }
        }
        if selected < 0 {
          selected = victim
        }
        if selected < 0 {
          segment.location = Some(SegmentSpill)
        } else {
          if active[selected] is Some(occupant) {
            segments[occupant].location = Some(SegmentSpill)
          }
          let reg = environment.allocatable_regs[selected]
          segment.location = Some(SegmentReg(reg))
          active[selected] = Some(segment_id)
        }
      }
      point = point - 1
    }
  }
}

///|
fn[F : FunctionView] assign_fast_homes(
  plan : AllocationPlan,
  function : F,
  environment : MachineEnv,
  segments : Array[AllocationSegment],
  segments_by_value : Array[Array[Int]],
) -> Unit {
  for value in 0..<function.value_count() {
    let vreg : VirtualReg = { id: value, class: function.value_class(value) }
    let mut home : PhysicalReg? = None
    let mut spill = false
    if value < segments_by_value.length() {
      for segment_id in segments_by_value[value] {
        match segments[segment_id].location {
          Some(SegmentReg(reg)) =>
            match home {
              None => home = Some(reg)
              Some(previous) => if previous != reg { spill = true }
            }
          Some(SegmentSpill) | None => spill = true
        }
      }
    }
    if !spill && home is Some(reg) {
      plan.assign_value(vreg, Reg(reg))
      continue
    }
    if segments_by_value.get(value) is Some(value_segments) &&
      value_segments.is_empty() {
      for reg in environment.allocatable_regs {
        if reg.class == vreg.class {
          home = Some(reg)
          break
        }
      }
      if home is Some(reg) {
        plan.assign_value(vreg, Reg(reg))
        continue
      }
    }
    plan.assign_value(
      vreg,
      Spill(
        plan.create_spill_slot(
          function.value_spill_size(value),
          function.value_spill_alignment(value),
        ),
      ),
    )
  }
}

///|
fn[F : FunctionView] allocate_fast_plan(
  function : F,
  environment : MachineEnv,
  config : RegallocConfig,
) -> AllocationPlan raise VerifyError {
  config.enter_phase(Some(LiveRanges))
  let ranges = build_function_live_ranges(function)
  config.enter_phase(Some(SegmentConstruction))
  let (segments, segments_by_value) = build_allocation_segments(
    ranges,
    loop_depths=compute_allocator_loop_depths(function),
    allocatable=environment.allocatable_regs,
  )
  config.enter_phase(Some(FastAllocation))
  allocate_fast_segments(function, environment, ranges, segments)
  let plan = AllocationPlan::new(function.value_count())
  config.enter_phase(Some(HomeAssignment))
  assign_fast_homes(plan, function, environment, segments, segments_by_value)
  config.enter_phase(Some(OperandAssignment))
  assign_segment_operands(
    plan, function, environment, segments, segments_by_value,
  )
  config.enter_phase(Some(EdgeTransfers))
  assign_edge_transfers(plan, function)
  plan
}
