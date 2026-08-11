///|
priv enum SegmentLocation {
  SegmentReg(PhysicalReg)
  SegmentSpill
}

///|
priv struct AllocationSegment {
  id : Int
  value : VirtualReg
  mut range : ProgramRange
  mut weight : Int
  mut has_fixed_constraint : Bool
  mut location : SegmentLocation?
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
fn segment_weight(
  range : LiveRange,
  fragment : ProgramRange,
  loop_depths : Array[Int],
) -> Int {
  let mut use_cost = 0
  for use_position in range.uses {
    if fragment.contains(use_position.point, []) {
      use_cost = use_cost + use_weight(use_position, loop_depths)
    }
  }
  if use_cost == 0 {
    return 1
  }
  let length = if fragment.start.block == fragment.end.block {
    (fragment.end.inst - fragment.start.inst).abs() + 1
  } else {
    1
  }
  ((use_cost + length - 1) / length).max(1)
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
fn fragment_has_fixed_constraint(
  range : LiveRange,
  fragment : ProgramRange,
) -> Bool {
  for use_position in range.uses {
    if fragment.contains(use_position.point, []) &&
      use_position.constraint is FixedReg(_) {
      return true
    }
  }
  false
}

///|
fn build_allocation_segments(
  ranges : LiveRangeSet,
  loop_depths? : Array[Int] = [],
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
    for fragment in range.ranges {
      let weight = segment_weight(range, fragment, loop_depths)
      let id = segments.length()
      segments.push({
        id,
        value: range.vreg,
        range: fragment,
        weight,
        has_fixed_constraint: fragment_has_fixed_constraint(range, fragment),
        location: None,
      })
      segments_by_value[range.vreg.id].push(id)
    }
  }
  (segments, segments_by_value)
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
fn segment_fixed_hint(
  ranges : LiveRangeSet,
  segment : AllocationSegment,
) -> PhysicalReg? {
  if !segment.has_fixed_constraint {
    return None
  }
  guard ranges.get_by_vreg(segment.value) is Some(range) else { return None }
  for use_position in range.uses {
    if segment.range.contains(use_position.point, ranges.block_order) &&
      use_position.constraint is FixedReg(reg) {
      return Some(reg)
    }
  }
  None
}

///|
fn segment_preference_hint(
  ranges : LiveRangeSet,
  segment : AllocationSegment,
  allocatable : Array[PhysicalReg],
) -> PhysicalReg? {
  guard ranges.get_by_vreg(segment.value) is Some(range) else { return None }
  let preferences : Array[PhysicalReg] = []
  for use_position in range.uses {
    if segment.range.contains(use_position.point, ranges.block_order) &&
      use_position.preference is Some(preference) {
      preferences.push(preference)
    }
  }
  let mut selected : PhysicalReg? = None
  let mut selected_count = 0
  for candidate in allocatable {
    let mut count = 0
    for preference in preferences {
      if preference == candidate {
        count = count + 1
      }
    }
    if count > selected_count {
      selected = Some(candidate)
      selected_count = count
    }
  }
  selected
}

///|
fn push_register_candidate(order : Array[Int], candidate : Int?) -> Unit {
  if candidate is Some(index) && !order.contains(index) {
    order.push(index)
  }
}

///|
fn[F : FunctionView] allocate_segments_with_bundles(
  function : F,
  environment : MachineEnv,
  ranges : LiveRangeSet,
  config? : RegallocConfig = RegallocConfig(),
) -> (
  Array[AllocationSegment],
  Array[Array[Int]],
  Array[AllocationBundle],
  Array[Int],
  Array[SpillSet],
  Array[Int],
) raise VerifyError {
  config.enter_phase(Some(SegmentConstruction))
  let loop_depths = compute_allocator_loop_depths(function)
  let (segments, segments_by_value) = build_allocation_segments(
    ranges,
    loop_depths~,
  )
  config.enter_phase(Some(BundleFormation))
  let bundle_plan = build_production_bundle_plan(function, ranges, segments)
  config.enter_phase(Some(BundleAllocation))
  let (bundles, segment_owner, spill_sets, segment_spill_set) = allocate_bundles(
    function, environment, ranges, segments, segments_by_value, loop_depths, bundle_plan,
  )
  (
    segments, segments_by_value, bundles, segment_owner, spill_sets, segment_spill_set,
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
    let vreg : VirtualReg = { id: value, class: function.value_class(value) }
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
  for segment in segments_by_value[value.id] {
    if segments[segment].range.contains(point, []) {
      return Some(segment)
    }
  }
  None
}

///|
fn segment_location_at(
  segments : Array[AllocationSegment],
  segments_by_value : Array[Array[Int]],
  value : VirtualReg,
  point : ProgramPoint,
) -> SegmentLocation? {
  segment_at(segments, segments_by_value, value, point).bind(segment => {
    segments[segment].location
  })
}

///|
fn live_register_value_at(
  register_home_values : Map[(Int, Int), Array[VirtualReg]],
  register_segments : Map[(Int, Int), Array[Int]],
  resident_segments : Array[Bool],
  segments : Array[AllocationSegment],
  segments_by_value : Array[Array[Int]],
  reg : PhysicalReg,
  point : ProgramPoint,
) -> VirtualReg? {
  match register_segments.get(physical_reg_key(reg)) {
    Some(segment_ids) =>
      for segment_id in segment_ids {
        if resident_segments[segment_id] &&
          segments[segment_id].range.contains(point, []) {
          return Some(segments[segment_id].value)
        }
      }
    None => ()
  }
  guard register_home_values.get(physical_reg_key(reg)) is Some(values) else {
    return None
  }
  for vreg in values {
    if segment_location_at(segments, segments_by_value, vreg, point) is Some(_) {
      return Some(vreg)
    }
  }
  None
}

///|
fn[F : FunctionView] borrow_allocatable_register(
  plan : AllocationPlan,
  function : F,
  environment : MachineEnv,
  register_home_values : Map[(Int, Int), Array[VirtualReg]],
  register_segments : Map[(Int, Int), Array[Int]],
  resident_segments : Array[Bool],
  segments : Array[AllocationSegment],
  segments_by_value : Array[Array[Int]],
  borrow_slots : Array[Int?],
  instruction : Int,
  point : ProgramPoint,
  class : RegClass,
  used : Array[PhysicalReg],
) -> PhysicalReg? {
  let clobbers = function.instruction_clobbers(instruction)
  let mut occupied_candidate : (PhysicalReg, VirtualReg)? = None
  for reg in environment.allocatable_regs {
    if reg.class != class || used.contains(reg) || clobbers.contains(reg) {
      continue
    }
    match
      live_register_value_at(
        register_home_values, register_segments, resident_segments, segments, segments_by_value,
        reg, point,
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
) -> Unit raise VerifyError {
  let borrow_slots : Array[Int?] = Array::make(function.value_count(), None)
  let register_home_values : Map[(Int, Int), Array[VirtualReg]] = Map([])
  let register_segments : Map[(Int, Int), Array[Int]] = Map([])
  for segment in segments {
    if segment.location is Some(SegmentReg(reg)) {
      let key = physical_reg_key(reg)
      match register_segments.get(key) {
        Some(segment_ids) => segment_ids.push(segment.id)
        None => register_segments[key] = [segment.id]
      }
    }
  }
  for value in 0..<function.value_count() {
    if plan.value_location(value) is Some(Reg(reg)) {
      let vreg : VirtualReg = { id: value, class: function.value_class(value) }
      let key = physical_reg_key(reg)
      match register_home_values.get(key) {
        Some(values) => values.push(vreg)
        None => register_home_values[key] = [vreg]
      }
    }
  }
  let has_predecessor = Array::make(function.block_count(), false)
  for block in 0..<function.block_count() {
    for successor in function.block_successors(block) {
      if successor >= 0 && successor < function.block_count() {
        has_predecessor[successor] = true
      }
    }
  }
  for block in 0..<function.block_count() {
    let resident_segments = Array::make(segments.length(), false)
    if has_predecessor[block] {
      for segment in segments {
        if segment.range.start.block == block &&
          segment.range.start.inst == -1 &&
          segment.location is Some(SegmentReg(reg)) {
          let home_matches = plan.value_location(segment.value.id) ==
            Some(Reg(reg))
          if home_matches {
            resident_segments[segment.id] = true
          }
        }
      }
    }
    for instruction_index, instruction in function.block_instructions(block) {
      let operands = function.instruction_operands(instruction)
      let assigned : Array[Location?] = Array::make(operands.length(), None)
      let natural_locations : Array[Location] = []
      let operand_segments : Array[Int?] = []
      let used_temps : Array[PhysicalReg] = []
      let borrowed_temps : Array[PhysicalReg] = []
      for operand in operands {
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
        let reserved = match operand.constraint {
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
        if reserved is Some(reg) && !used_temps.contains(reg) {
          used_temps.push(reg)
        }
      }
      for operand_index, operand in operands {
        let home = plan.value_location(operand.vreg.id).unwrap()
        let tied_location : Location? = if operand.tie_id < 0 {
          None
        } else {
          let mut location : Location? = None
          for earlier in 0..<operand_index {
            if operands[earlier].tie_id == operand.tie_id &&
              assigned[earlier] is Some(previous) {
              location = Some(previous)
              break
            }
          }
          location
        }
        let selected = match tied_location {
          Some(location) => location
          None =>
            match operand.constraint {
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
                          register_home_values,
                          register_segments,
                          resident_segments,
                          segments,
                          segments_by_value,
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
        plan.assign_operand(instruction, operand_index, selected)
      }
      let resident_operand_segments : Array[Int?] = []
      for operand_index, _ in operands {
        resident_operand_segments.push(
          match operand_segments[operand_index] {
            Some(segment) if natural_locations[operand_index] ==
              assigned[operand_index].unwrap() => Some(segment)
            _ => None
          },
        )
      }
      for timing in [Early, Late] {
        for operand_index, operand in operands {
          if operand.timing != timing {
            continue
          }
          let home = plan.value_location(operand.vreg.id).unwrap()
          let selected = assigned[operand_index].unwrap()
          if operand.role is Use || operand.role is UseDef {
            match resident_operand_segments[operand_index] {
              Some(segment) =>
                if !resident_segments[segment] {
                  if selected is Reg(reg) {
                    match register_segments.get(physical_reg_key(reg)) {
                      Some(segment_ids) =>
                        for segment_id in segment_ids {
                          resident_segments[segment_id] = false
                        }
                      None => ()
                    }
                  }
                  add_use_transfer(plan, instruction, operand, home, selected)
                  resident_segments[segment] = true
                }
              None => {
                add_use_transfer(plan, instruction, operand, home, selected)
                if selected is Reg(reg) && !borrowed_temps.contains(reg) {
                  match register_segments.get(physical_reg_key(reg)) {
                    Some(segment_ids) =>
                      for segment_id in segment_ids {
                        resident_segments[segment_id] = false
                      }
                    None => ()
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
            match register_segments.get(physical_reg_key(reg)) {
              Some(segment_ids) =>
                for segment_id in segment_ids {
                  resident_segments[segment_id] = false
                }
              None => ()
            }
            resident_segments[segment] = true
          } else if selected is Reg(reg) && !borrowed_temps.contains(reg) {
            match register_segments.get(physical_reg_key(reg)) {
              Some(segment_ids) =>
                for segment_id in segment_ids {
                  resident_segments[segment_id] = false
                }
              None => ()
            }
          }
        }
        if timing == Early {
          for clobber in function.instruction_clobbers(instruction) {
            match register_segments.get(physical_reg_key(clobber)) {
              Some(segment_ids) =>
                for segment_id in segment_ids {
                  resident_segments[segment_id] = false
                }
              None => ()
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
  config : RegallocConfig,
) -> AllocationPlan raise VerifyError {
  config.enter_phase(Some(LiveRanges))
  let ranges = build_function_live_ranges(function)
  let (segments, segments_by_value, _, _, spill_sets, segment_spill_set) = allocate_segments_with_bundles(
    function,
    environment,
    ranges,
    config~,
  )
  let plan = AllocationPlan::new(function.value_count())
  config.enter_phase(Some(HomeAssignment))
  assign_backtracking_homes(
    plan, function, environment, ranges, segments, segments_by_value, spill_sets,
    segment_spill_set,
  )
  config.enter_phase(Some(OperandAssignment))
  assign_segment_operands(
    plan, function, environment, segments, segments_by_value,
  )
  config.enter_phase(Some(EdgeTransfers))
  assign_edge_transfers(plan, function)
  plan
}
