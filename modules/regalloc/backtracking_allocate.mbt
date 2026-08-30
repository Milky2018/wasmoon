///|
priv enum SegmentLocation {
  SegmentReg(PhysicalReg)
  SegmentSpill
}

///|
priv struct AllocationSegment {
  id : Int
  value : VirtualReg
  range : ProgramRange
  weight : Int
  has_fixed_constraint : Bool
  fixed_hint : PhysicalReg?
  preference_hint : PhysicalReg?
  mut location : SegmentLocation?
}

///|
priv struct SegmentMetadata {
  weight : Int
  has_fixed_constraint : Bool
  fixed_hint : PhysicalReg?
  preference_hint : PhysicalReg?
}

///|
fn use_weight(use_position : UsePosition, loop_depths : Array[Int]) -> Int {
  let mut depth = if use_position.point.block >= 0 &&
    use_position.point.block < loop_depths.length() {
    loop_depths[use_position.point.block]
  } else {
    0
  }
  if depth < 0 {
    depth = 0
  }
  if depth > 10 {
    depth = 10
  }
  let mut hot_bonus = 1000
  for _ in 0..<depth {
    hot_bonus = hot_bonus * 4
  }
  let def_bonus = match use_position.kind {
    LiveDef | LiveUseDef => 2000
    LiveUse => 0
  }
  let constraint_weight = match use_position.constraint {
    AnyLocation => 0
    AnyReg => 1000
    FixedReg(_) => 2000
  }
  hot_bonus + def_bonus + constraint_weight
}

///|
/// Rank a fragment by spill cost per program point. This keeps a sparse,
/// long-lived value from evicting short-lived values used at every instruction.
fn segment_metadata(
  range : LiveRange,
  fragment : ProgramRange,
  loop_depths : Array[Int],
  block_order : Array[Int],
  allocatable : Array[PhysicalReg],
  use_start? : Int = 0,
  use_end? : Int = -1,
) -> SegmentMetadata {
  let mut use_cost = 0
  let mut has_fixed_constraint = false
  let mut fixed_hint : PhysicalReg? = None
  let mut preference_regs : Array[PhysicalReg]? = None
  let mut preference_counts : Array[Int]? = None
  let end = if use_end < 0 { range.uses.length() } else { use_end }
  for use_index in use_start..<end {
    let use_position = range.uses[use_index]
    if fragment.contains(use_position.point, block_order) {
      use_cost = use_cost + use_weight(use_position, loop_depths)
      if use_position.constraint is FixedReg(_) {
        has_fixed_constraint = true
      }
      if fixed_hint is None && use_position.constraint is FixedReg(reg) {
        fixed_hint = Some(reg)
      }
      if use_position.preference is Some(preference) &&
        allocatable.contains(preference) {
        if preference_regs is None {
          preference_regs = Some([])
          preference_counts = Some([])
        }
        let regs = preference_regs.unwrap()
        let counts = preference_counts.unwrap()
        let mut index = -1
        for candidate_index, candidate in regs {
          if candidate == preference {
            index = candidate_index
            break
          }
        }
        if index >= 0 {
          counts[index] = counts[index] + 1
        } else {
          regs.push(preference)
          counts.push(1)
        }
      }
    }
  }
  let length = if fragment.start.block == fragment.end.block {
    (fragment.end.inst - fragment.start.inst).abs() + 1
  } else {
    1
  }
  let weight = if use_cost == 0 {
    1
  } else {
    ((use_cost + length - 1) / length).max(1)
  }
  let mut preference_hint : PhysicalReg? = None
  let mut selected_count = 0
  if preference_counts is Some(counts) && preference_regs is Some(regs) {
    for index, count in counts {
      if count > selected_count {
        preference_hint = Some(regs[index])
        selected_count = count
      }
    }
  }
  if !has_fixed_constraint {
    fixed_hint = None
  }
  { weight, has_fixed_constraint, fixed_hint, preference_hint, }
}

///|
fn AllocationSegment::with_range(
  self : AllocationSegment,
  range : ProgramRange,
  live_range : LiveRange,
  loop_depths : Array[Int],
  block_order : Array[Int],
  allocatable : Array[PhysicalReg],
) -> AllocationSegment {
  let metadata = segment_metadata(
    live_range, range, loop_depths, block_order, allocatable,
  )
  {
    ..self,
    range,
    weight: metadata.weight,
    has_fixed_constraint: metadata.has_fixed_constraint,
    fixed_hint: metadata.fixed_hint,
    preference_hint: metadata.preference_hint,
  }
}

///|
fn build_allocation_segments(
  ranges : LiveRangeSet,
  loop_depths? : Array[Int] = [],
  allocatable? : Array[PhysicalReg] = [],
  preordered? : Bool = false,
) -> (Array[AllocationSegment], Array[Array[Int]]) {
  let segments : Array[AllocationSegment] = []
  let segments_by_value : Array[Array[Int]] = []
  let mut max_value = -1
  for range in ranges.ranges {
    if range.vreg.id > max_value {
      max_value = range.vreg.id
    }
  }
  for _ in 0..<(max_value + 1) {
    segments_by_value.push([])
  }
  for range in ranges.ranges {
    if !preordered {
      range.sort_ranges(ranges.block_order)
      range.uses.sort_by(fn(left, right) {
        left.point.compare_with_order(right.point, ranges.block_order)
      })
    }
    let mut use_start = 0
    for fragment in range.ranges {
      while use_start < range.uses.length() &&
            range.uses[use_start].point.compare_with_order(
              fragment.start,
              ranges.block_order,
            ) <
            0 {
        use_start = use_start + 1
      }
      let mut use_end = use_start
      while use_end < range.uses.length() &&
            range.uses[use_end].point.compare_with_order(
              fragment.end,
              ranges.block_order,
            ) <=
            0 {
        use_end = use_end + 1
      }
      let metadata = segment_metadata(
        range,
        fragment,
        loop_depths,
        ranges.block_order,
        allocatable,
        use_start~,
        use_end~,
      )
      let id = segments.length()
      segments.push({
        id,
        value: range.vreg,
        range: fragment,
        weight: metadata.weight,
        has_fixed_constraint: metadata.has_fixed_constraint,
        fixed_hint: metadata.fixed_hint,
        preference_hint: metadata.preference_hint,
        location: None,
      })
      segments_by_value[range.vreg.id].push(id)
    }
  }
  (segments, segments_by_value)
}

///|
fn segment_has_use(range : LiveRange, fragment : ProgramRange) -> Bool {
  for use_position in range.uses {
    if fragment.contains(use_position.point, []) {
      return true
    }
  }
  false
}

///|
fn[F : FunctionView] compute_allocator_loop_depths(function : F) -> Array[Int] {
  let block_count = function.block_count()
  let backedge_in = Array::make(block_count, 0)
  let backedge_out = Array::make(block_count, 0)
  for block in 0..<block_count {
    for successor in function.block_successors(block) {
      if successor >= 0 && successor < block_count && successor <= block {
        backedge_in[successor] = backedge_in[successor] + 1
        backedge_out[block] = backedge_out[block] + 1
      }
    }
  }
  let depths : Array[Int] = []
  let backedge_stack : Array[Int] = []
  let mut current_depth = 0
  for block in 0..<block_count {
    if backedge_in[block] > 0 {
      current_depth = current_depth + 1
      backedge_stack.push(backedge_in[block])
    }
    depths.push(current_depth)
    let mut outgoing = backedge_out[block]
    while !backedge_stack.is_empty() && outgoing > 0 {
      outgoing = outgoing - 1
      let last = backedge_stack.length() - 1
      backedge_stack[last] = backedge_stack[last] - 1
      if backedge_stack[last] == 0 {
        current_depth = current_depth - 1
        backedge_stack.pop() |> ignore
      }
    }
  }
  depths
}

///|
fn register_index(registers : Array[PhysicalReg], target : PhysicalReg) -> Int? {
  for index, reg in registers {
    if reg == target {
      return Some(index)
    }
  }
  None
}

///|
fn[F : FunctionView] allocate_segments_with_context(
  function : F,
  environment : MachineEnv,
  ranges : LiveRangeSet,
  session : AllocationSession,
  config? : RegallocConfig = RegallocConfig(),
) -> (
  Array[AllocationSegment],
  Array[Array[Int]],
  AllocationContext,
  Array[Int],
  Array[SpillSet],
  Array[Int],
) raise VerifyError {
  config.enter_phase(Some(SegmentConstruction))
  let loop_depths = compute_allocator_loop_depths(function)
  let (segments, segments_by_value) = build_allocation_segments(
    ranges,
    loop_depths~,
    allocatable=environment.allocatable_regs,
    preordered=true,
  )
  config.enter_phase(Some(BundleFormation))
  let bundle_plan = build_production_bundle_plan(
    function,
    ranges,
    segments,
    verify=config.verify(),
  )
  config.enter_phase(Some(BundleAllocation))
  let (context, segment_owner, spill_sets, segment_spill_set, statistics) = allocate_bundles(
    function,
    environment,
    ranges,
    segments,
    segments_by_value,
    loop_depths,
    bundle_plan,
    session,
    verify=config.verify(),
  )
  config.report_bundle_statistics(statistics)
  (
    segments, segments_by_value, context, segment_owner, spill_sets, segment_spill_set,
  )
}

///|
fn spill_homes_can_share(
  ranges : LiveRangeSet,
  lhs : VirtualReg,
  rhs : VirtualReg,
) -> Bool {
  // A value has one stable spill home. Fragment liveness alone does not prove
  // the stored value across CFG edges, so compact only linear lifetimes in one
  // block until cross-block spill-slot contents are modeled explicitly.
  match (ranges.get_by_vreg(lhs), ranges.get_by_vreg(rhs)) {
    (Some(left), Some(right)) => {
      guard left.range_count() == 1 && right.range_count() == 1 else { false }
      let left_range = left.range_at(0).unwrap()
      let right_range = right.range_at(0).unwrap()
      left_range.start.block == right_range.start.block &&
      !left_range.overlaps(right_range, ranges.block_order)
    }
    _ => false
  }
}

///|
fn[F : FunctionView] spill_home_types_match(
  function : F,
  lhs : VirtualReg,
  rhs : VirtualReg,
) -> Bool {
  function.values_share_spill_slot(lhs.id, rhs.id) &&
  function.values_share_spill_slot(rhs.id, lhs.id) &&
  function.value_spill_size(lhs.id) == function.value_spill_size(rhs.id) &&
  function.value_spill_alignment(lhs.id) ==
  function.value_spill_alignment(rhs.id)
}

///|
fn[F : FunctionView] build_spill_home_groups(
  function : F,
  segments : Array[AllocationSegment],
  spill_sets : Array[SpillSet],
  segment_spill_set : Array[Int],
  needs_spill : Array[Bool],
) -> (Array[Int], Array[Array[VirtualReg]]) {
  let group_by_value = Array::make(function.value_count(), -1)
  let groups : Array[Array[VirtualReg]] = []
  let values_by_spill_set : Array[Array[VirtualReg]] = []
  for _ in spill_sets {
    values_by_spill_set.push([])
  }
  for segment in segments {
    let spill_set = segment_spill_set[segment.id]
    if spill_set >= 0 && !values_by_spill_set[spill_set].contains(segment.value) {
      values_by_spill_set[spill_set].push(segment.value)
    }
  }
  for values in values_by_spill_set {
    let compatible_groups : Array[Array[VirtualReg]] = []
    for value in values {
      if !needs_spill[value.id] {
        continue
      }
      let mut selected = -1
      for index, group in compatible_groups {
        let mut compatible = true
        for grouped_value in group {
          if !spill_home_types_match(function, value, grouped_value) {
            compatible = false
            break
          }
        }
        if compatible {
          selected = index
          break
        }
      }
      if selected < 0 {
        compatible_groups.push([value])
      } else {
        compatible_groups[selected].push(value)
      }
    }
    for group in compatible_groups {
      if group.length() < 2 {
        continue
      }
      let group_id = groups.length()
      groups.push(group)
      for value in group {
        group_by_value[value.id] = group_id
      }
    }
  }
  (group_by_value, groups)
}

///|
fn[F : FunctionView] spill_home_candidates_can_share(
  function : F,
  ranges : LiveRangeSet,
  group_by_value : Array[Int],
  candidates : Array[VirtualReg],
  occupants : Array[VirtualReg],
) -> Bool {
  for candidate in candidates {
    for occupant in occupants {
      if !spill_home_types_match(function, candidate, occupant) {
        return false
      }
      let same_affinity_group = group_by_value[candidate.id] >= 0 &&
        group_by_value[candidate.id] == group_by_value[occupant.id]
      if !same_affinity_group &&
        !spill_homes_can_share(ranges, candidate, occupant) {
        return false
      }
    }
  }
  true
}

///|
fn[F : FunctionView] assign_backtracking_homes(
  plan : AllocationPlan,
  function : F,
  environment : MachineEnv,
  ranges : LiveRangeSet,
  segments : Array[AllocationSegment],
  segments_by_value : Array[Array[Int]],
  spill_sets : Array[SpillSet],
  segment_spill_set : Array[Int],
) -> Unit {
  let needs_spill = Array::make(function.value_count(), false)
  let register_homes : Array[PhysicalReg?] = Array::make(
    function.value_count(),
    None,
  )
  for value in 0..<function.value_count() {
    let mut common : PhysicalReg? = None
    let mut split = false
    if value < segments_by_value.length() {
      for segment_id in segments_by_value[value] {
        match segments[segment_id].location {
          Some(SegmentReg(reg)) =>
            match common {
              None => common = Some(reg)
              Some(previous) => if previous != reg { split = true }
            }
          Some(SegmentSpill) | None => split = true
        }
      }
    }
    if split {
      needs_spill[value] = true
    } else if common is Some(reg) {
      register_homes[value] = Some(reg)
    } else {
      for reg in environment.allocatable_regs {
        if reg.class == function.value_class(value) {
          register_homes[value] = Some(reg)
          break
        }
      }
      if register_homes[value] is None {
        needs_spill[value] = true
      }
    }
  }

  let slot_values : Array[Array[VirtualReg]] = []
  let (group_by_value, spill_home_groups) = build_spill_home_groups(
    function, segments, spill_sets, segment_spill_set, needs_spill,
  )
  let group_slots : Array[Int?] = Array::make(spill_home_groups.length(), None)
  for value in 0..<function.value_count() {
    let vreg : VirtualReg = { id: value, class: function.value_class(value), }
    if !needs_spill[value] {
      plan.assign_value(vreg, Reg(register_homes[value].unwrap()))
      continue
    }
    let group = group_by_value[value]
    let candidates = if group >= 0 { spill_home_groups[group] } else { [vreg] }
    let mut selected = if group >= 0 {
      group_slots[group].unwrap_or(-1)
    } else {
      -1
    }
    if selected < 0 {
      for slot, occupants in slot_values {
        if occupants.is_empty() {
          continue
        }
        if spill_home_candidates_can_share(
            function, ranges, group_by_value, candidates, occupants,
          ) {
          selected = slot
          break
        }
      }
    }
    if selected < 0 {
      selected = plan.create_spill_slot(
        function.value_spill_size(value),
        function.value_spill_alignment(value),
      )
      slot_values.push([])
    }
    if group >= 0 {
      if group_slots[group] is None {
        group_slots[group] = Some(selected)
        for grouped_value in candidates {
          slot_values[selected].push(grouped_value)
        }
      }
    } else {
      slot_values[selected].push(vreg)
    }
    plan.assign_value(vreg, Spill(selected))
  }
}

///|
fn segment_at(
  segments : Array[AllocationSegment],
  segments_by_value : Array[Array[Int]],
  value : VirtualReg,
  point : ProgramPoint,
) -> Int? {
  if value.id < 0 || value.id >= segments_by_value.length() {
    return None
  }
  let value_segments = segments_by_value[value.id]
  let mut lo = 0
  let mut hi = value_segments.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if segments[value_segments[mid]].range.end.compare_with_order(point, []) < 0 {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  if lo < value_segments.length() &&
    segments[value_segments[lo]].range.contains(point, []) {
    Some(value_segments[lo])
  } else {
    None
  }
}

///|
fn live_home_value_at(
  register_home_segments : Array[Array[Int]],
  segments : Array[AllocationSegment],
  register_index : Int,
  point : ProgramPoint,
) -> VirtualReg? {
  let home_segments = register_home_segments[register_index]
  let mut lo = 0
  let mut hi = home_segments.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if segments[home_segments[mid]].range.end.compare_with_order(point, []) < 0 {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  if lo < home_segments.length() &&
    segments[home_segments[lo]].range.contains(point, []) {
    return Some(segments[home_segments[lo]].value)
  }
  None
}

///|
fn live_register_value_at(
  register_home_segments : Array[Array[Int]],
  resident_by_register : Array[Int],
  segments : Array[AllocationSegment],
  register_index : Int,
  point : ProgramPoint,
) -> VirtualReg? {
  let resident = resident_by_register[register_index]
  if resident >= 0 && segments[resident].range.contains(point, []) {
    return Some(segments[resident].value)
  }
  live_home_value_at(register_home_segments, segments, register_index, point)
}

///|
fn[F : FunctionView] borrow_allocatable_register(
  plan : AllocationPlan,
  function : F,
  environment : MachineEnv,
  register_home_segments : Array[Array[Int]],
  resident_by_register : Array[Int],
  segments : Array[AllocationSegment],
  borrow_slots : Array[Int?],
  instruction : Int,
  point : ProgramPoint,
  class : RegClass,
  used : Array[PhysicalReg],
) -> PhysicalReg? {
  let clobbers = function.instruction_clobbers(instruction)
  let mut occupied_candidate : (PhysicalReg, VirtualReg)? = None
  for register_index, reg in environment.allocatable_regs {
    if reg.class != class || used.contains(reg) || clobbers.contains(reg) {
      continue
    }
    match
      live_register_value_at(
        register_home_segments, resident_by_register, segments, register_index, point,
      ) {
      None => return Some(reg)
      Some(value) =>
        if occupied_candidate is None {
          occupied_candidate = Some((reg, value))
        }
    }
  }
  guard occupied_candidate is Some((reg, occupant)) else { return None }
  let slot = match borrow_slots[occupant.id] {
    Some(slot) => slot
    None => {
      let slot = plan.create_spill_slot(
        function.value_spill_size(occupant.id),
        function.value_spill_alignment(occupant.id),
      )
      borrow_slots[occupant.id] = Some(slot)
      slot
    }
  }
  plan.add_edit({
    value: occupant,
    from: Reg(reg),
    to: Spill(slot),
    position: Before(instruction),
  })
  plan.add_edit({
    value: occupant,
    from: Spill(slot),
    to: Reg(reg),
    position: After(instruction),
  })
  Some(reg)
}

///|
fn[F : FunctionView] assign_segment_operands(
  plan : AllocationPlan,
  function : F,
  environment : MachineEnv,
  segments : Array[AllocationSegment],
  segments_by_value : Array[Array[Int]],
  session? : AllocationSession = AllocationSession::new(),
) -> Unit raise VerifyError {
  let borrow_slots : Array[Int?] = Array::make(function.value_count(), None)
  let register_indexes = PhysicalRegisterIndex::for_session(
    session,
    environment.allocatable_regs,
  )
  let register_home_segments : Array[Array[Int]] = []
  for _ in environment.allocatable_regs {
    register_home_segments.push([])
  }
  let block_entry_segments : Array[Array[Int]] = []
  for _ in 0..<function.block_count() {
    block_entry_segments.push([])
  }
  for segment in segments {
    if segment.location is Some(_) &&
      plan.value_location(segment.value.id) is Some(Reg(home_reg)) &&
      register_indexes.find(environment.allocatable_regs, home_reg)
      is Some(index) {
      register_home_segments[index].push(segment.id)
    }
    if segment.range.start.inst == -1 &&
      segment.range.start.block >= 0 &&
      segment.range.start.block < function.block_count() &&
      segment.location is Some(SegmentReg(reg)) &&
      plan.value_location(segment.value.id) == Some(Reg(reg)) {
      block_entry_segments[segment.range.start.block].push(segment.id)
    }
  }
  for home_segments in register_home_segments {
    home_segments.sort_by(fn(left, right) {
      let left_range = segments[left].range
      let right_range = segments[right].range
      let end_order = left_range.end.compare_with_order(right_range.end, [])
      if end_order != 0 {
        end_order
      } else {
        left_range.start.compare_with_order(right_range.start, [])
      }
    })
  }
  let assigned : Array[Location?] = []
  let natural_locations : Array[Location] = []
  let operand_segments : Array[Int?] = []
  let used_temps : Array[PhysicalReg] = []
  let borrowed_temps : Array[PhysicalReg] = []
  let tie_slot_by_id : Map[Int, Int] = Map([])
  let operand_tie_slots : Array[Int?] = []
  let tied_constraints : Array[OperandConstraint?] = []
  let tied_locations : Array[Location?] = []
  let resident_operand_segments : Array[Int?] = []
  let has_predecessor = Array::make(function.block_count(), false)
  for block in 0..<function.block_count() {
    for successor in function.block_successors(block) {
      if successor >= 0 && successor < function.block_count() {
        has_predecessor[successor] = true
      }
    }
  }
  for block in 0..<function.block_count() {
    let resident_by_register = Array::make(
      environment.allocatable_regs.length(),
      -1,
    )
    if has_predecessor[block] {
      for segment_id in block_entry_segments[block] {
        guard segments[segment_id].location is Some(SegmentReg(reg)) else {
          continue
        }
        if register_indexes.find(environment.allocatable_regs, reg)
          is Some(index) {
          resident_by_register[index] = segment_id
        }
      }
    }
    for instruction_index, instruction in function.block_instructions(block) {
      let operands = function.instruction_operands(instruction)
      assigned.clear()
      natural_locations.clear()
      operand_segments.clear()
      used_temps.clear()
      borrowed_temps.clear()
      tie_slot_by_id.clear()
      operand_tie_slots.clear()
      tied_constraints.clear()
      tied_locations.clear()
      resident_operand_segments.clear()
      for operand in operands {
        assigned.push(None)
        let tie_slot = if operand.tie_id < 0 {
          None
        } else {
          match tie_slot_by_id.get(operand.tie_id) {
            Some(slot) => Some(slot)
            None => {
              let slot = tied_constraints.length()
              tie_slot_by_id[operand.tie_id] = slot
              tied_constraints.push(None)
              tied_locations.push(None)
              Some(slot)
            }
          }
        }
        operand_tie_slots.push(tie_slot)
        if tie_slot is Some(slot) {
          let constraint = match tied_constraints[slot] {
            None => operand.constraint
            Some(FixedReg(required)) =>
              match operand.constraint {
                FixedReg(other) if other != required =>
                  raise InvalidPlan(
                    message="tied operands require different fixed registers",
                  )
                _ => FixedReg(required)
              }
            Some(AnyReg) =>
              match operand.constraint {
                FixedReg(required) => FixedReg(required)
                _ => AnyReg
              }
            Some(AnyLocation) => operand.constraint
          }
          tied_constraints[slot] = Some(constraint)
        }
      }
      for operand_index, operand in operands {
        let home = plan.value_location(operand.vreg.id).unwrap()
        let segment = segment_at(
          segments,
          segments_by_value,
          operand.vreg,
          operand_program_point(block, instruction_index, operand.timing),
        )
        operand_segments.push(segment)
        let natural = match segment {
          Some(segment) =>
            match segments[segment].location {
              Some(SegmentReg(reg)) => Reg(reg)
              Some(SegmentSpill) | None => home
            }
          None => home
        }
        natural_locations.push(natural)
        let any_location = if operand.role is Def { home } else { natural }
        let tie_slot = operand_tie_slots[operand_index]
        let constraint = match tie_slot {
          Some(slot) => tied_constraints[slot].unwrap_or(operand.constraint)
          None => operand.constraint
        }
        let reserved = match constraint {
          FixedReg(reg) => Some(reg)
          AnyLocation =>
            match any_location {
              Reg(reg) => Some(reg)
              Spill(_) => None
            }
          AnyReg =>
            match natural {
              Reg(reg) => Some(reg)
              Spill(_) => None
            }
        }
        if tie_slot is Some(slot) &&
          constraint is AnyReg &&
          reserved is Some(reg) &&
          tied_locations[slot] is None {
          tied_locations[slot] = Some(Reg(reg))
        }
        if reserved is Some(reg) && !used_temps.contains(reg) {
          used_temps.push(reg)
        }
      }
      for operand_index, operand in operands {
        let home = plan.value_location(operand.vreg.id).unwrap()
        let tie_slot = operand_tie_slots[operand_index]
        let tied_location : Location? = match tie_slot {
          Some(slot) => tied_locations[slot]
          None => None
        }
        let selected = match tied_location {
          Some(location) => location
          None =>
            match
              (match tie_slot {
                Some(slot) =>
                  tied_constraints[slot].unwrap_or(operand.constraint)
                None => operand.constraint
              }) {
              FixedReg(reg) => Reg(reg)
              AnyLocation =>
                if operand.role is Def {
                  home
                } else {
                  natural_locations[operand_index]
                }
              AnyReg =>
                match natural_locations[operand_index] {
                  Reg(reg) => Reg(reg)
                  Spill(_) => {
                    let point = operand_program_point(
                      block,
                      instruction_index,
                      operand.timing,
                    )
                    let temporary = match
                      find_scratch_reg(
                        environment,
                        operand.vreg.class,
                        used_temps,
                      ) {
                      Some(reg) => Some(reg)
                      None => {
                        let borrowed = borrow_allocatable_register(
                          plan,
                          function,
                          environment,
                          register_home_segments,
                          resident_by_register,
                          segments,
                          borrow_slots,
                          instruction,
                          point,
                          operand.vreg.class,
                          used_temps,
                        )
                        if borrowed is Some(reg) {
                          borrowed_temps.push(reg)
                        }
                        borrowed
                      }
                    }
                    guard temporary is Some(reg) else {
                      raise ScratchRegisterUnavailable(
                        message="no register for spilled operand",
                      )
                    }
                    used_temps.push(reg)
                    Reg(reg)
                  }
                }
            }
        }
        assigned[operand_index] = Some(selected)
        if tie_slot is Some(slot) {
          tied_locations[slot] = Some(selected)
        }
        resident_operand_segments.push(
          match operand_segments[operand_index] {
            Some(segment) if natural_locations[operand_index] == selected =>
              Some(segment)
            _ => None
          },
        )
        plan.assign_operand(instruction, operand_index, selected)
      }
      for timing in [OperandTiming::Early, Late] {
        for operand_index, operand in operands {
          if operand.timing != timing {
            continue
          }
          let home = plan.value_location(operand.vreg.id).unwrap()
          let selected = assigned[operand_index].unwrap()
          if operand.role is Use || operand.role is UseDef {
            match resident_operand_segments[operand_index] {
              Some(segment) => {
                let register = match selected {
                  Reg(reg) =>
                    register_indexes.find(environment.allocatable_regs, reg)
                  Spill(_) => None
                }
                match register {
                  Some(index) if resident_by_register[index] != segment => {
                    add_use_transfer(plan, instruction, operand, home, selected)
                    resident_by_register[index] = segment
                  }
                  None =>
                    add_use_transfer(plan, instruction, operand, home, selected)
                  _ => ()
                }
              }
              None => {
                add_use_transfer(plan, instruction, operand, home, selected)
                if selected is Reg(reg) && !borrowed_temps.contains(reg) {
                  if register_indexes.find(environment.allocatable_regs, reg)
                    is Some(index) {
                    resident_by_register[index] = -1
                  }
                }
              }
            }
          }
        }
        for operand_index, operand in operands {
          if operand.timing != timing ||
            !(operand.role is Def || operand.role is UseDef) {
            continue
          }
          let home = plan.value_location(operand.vreg.id).unwrap()
          let selected = assigned[operand_index].unwrap()
          if home != selected {
            plan.add_edit({
              value: operand.vreg,
              from: selected,
              to: home,
              position: After(instruction),
            })
          }
          if resident_operand_segments[operand_index] is Some(segment) &&
            selected is Reg(reg) {
            if register_indexes.find(environment.allocatable_regs, reg)
              is Some(index) {
              resident_by_register[index] = segment
            }
          } else if selected is Reg(reg) && !borrowed_temps.contains(reg) {
            if register_indexes.find(environment.allocatable_regs, reg)
              is Some(index) {
              resident_by_register[index] = -1
            }
          }
        }
        if timing == Early {
          for clobber in function.instruction_clobbers(instruction) {
            if register_indexes.find(environment.allocatable_regs, clobber)
              is Some(index) {
              resident_by_register[index] = -1
            }
          }
        }
      }
    }
  }
}

///|
fn[F : FunctionView] allocate_bundle_plan(
  function : F,
  environment : MachineEnv,
  session : AllocationSession,
  config : RegallocConfig,
) -> AllocationPlan raise VerifyError {
  config.enter_phase(Some(LiveRanges))
  let ranges = build_function_live_ranges(function)
  let (segments, segments_by_value, _, _, spill_sets, segment_spill_set) = allocate_segments_with_context(
    function,
    environment,
    ranges,
    session,
    config~,
  )
  for value_segments in segments_by_value {
    value_segments.sort_by(fn(left, right) {
      let by_start = segments[left].range.start.compare_with_order(
        segments[right].range.start,
        ranges.block_order,
      )
      if by_start != 0 {
        by_start
      } else {
        left - right
      }
    })
  }
  let plan = AllocationPlan::new(function.value_count())
  config.enter_phase(Some(HomeAssignment))
  assign_backtracking_homes(
    plan, function, environment, ranges, segments, segments_by_value, spill_sets,
    segment_spill_set,
  )
  config.enter_phase(Some(OperandAssignment))
  assign_segment_operands(
    plan,
    function,
    environment,
    segments,
    segments_by_value,
    session~,
  )
  config.enter_phase(Some(EdgeTransfers))
  assign_edge_transfers(plan, function)
  plan
}
