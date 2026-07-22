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
  mut location : SegmentLocation?
}

///|
fn use_weight(use_position : UsePosition) -> Int {
  let role_weight = match use_position.kind {
    LiveUse => 1000
    LiveDef => 1500
    LiveUseDef => 2500
  }
  let constraint_weight = match use_position.constraint {
    AnyLocation => 0
    AnyReg => 500
    FixedReg(_) => 1500
  }
  role_weight + constraint_weight
}

///|
/// Rank a fragment by spill cost per program point. This keeps a sparse,
/// long-lived value from evicting short-lived values used at every instruction.
fn segment_weight(range : LiveRange, fragment : ProgramRange) -> Int {
  let mut use_cost = 0
  for use_position in range.uses {
    if fragment.contains(use_position.point, []) {
      use_cost = use_cost + use_weight(use_position)
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
fn build_allocation_segments(
  ranges : LiveRangeSet,
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
    let has_fixed_constraint = range.has_fixed_constraint()
    for fragment in range.ranges {
      let weight = segment_weight(range, fragment)
      let id = segments.length()
      segments.push({
        id,
        value: range.vreg,
        range: fragment,
        weight,
        has_fixed_constraint,
        location: None,
      })
      segments_by_value[range.vreg.id].push(id)
    }
  }
  (segments, segments_by_value)
}

///|
fn remove_occupied_segment(
  occupied : Array[Array[Int]],
  register : Int,
  segment : Int,
) -> Unit {
  let mut index = 0
  while index < occupied[register].length() {
    if occupied[register][index] == segment {
      occupied[register].remove(index) |> ignore
    } else {
      index = index + 1
    }
  }
}

///|
fn conflicting_segments(
  segments : Array[AllocationSegment],
  occupied : Array[Int],
  current : AllocationSegment,
  block_order : Array[Int],
) -> Array[Int] {
  let conflicts : Array[Int] = []
  let mut lo = 0
  let mut hi = occupied.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if segments[occupied[mid]].range.end.compare_with_order(
        current.range.start,
        block_order,
      ) <
      0 {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  // Segments already assigned to one register are pairwise disjoint. Therefore
  // their end order is also their start order, and no later segment can
  // overlap once this segment starts after the current range ends.
  for index in lo..<occupied.length() {
    let segment = occupied[index]
    if segments[segment].range.start.compare_with_order(
        current.range.end,
        block_order,
      ) >
      0 {
      break
    }
    if segments[segment].range.overlaps(current.range, block_order) {
      conflicts.push(segment)
    }
  }
  conflicts
}

///|
fn insert_occupied_segment(
  segments : Array[AllocationSegment],
  occupied : Array[Int],
  segment : Int,
  block_order : Array[Int],
) -> Unit {
  let mut lo = 0
  let mut hi = occupied.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let by_end = segments[occupied[mid]].range.end.compare_with_order(
      segments[segment].range.end,
      block_order,
    )
    if by_end < 0 || (by_end == 0 && occupied[mid] < segment) {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  occupied.insert(lo, segment)
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
fn add_edge_affinity(
  affinities : Array[Array[Int]],
  value : VirtualReg,
  related : VirtualReg,
) -> Unit {
  if value.id >= 0 &&
    value.id < affinities.length() &&
    !affinities[value.id].contains(related.id) {
    affinities[value.id].push(related.id)
  }
}

///|
fn[F : FunctionView] build_edge_affinities(
  function : F,
) -> (Array[Array[Int]], Array[Bool], Array[Bool]) {
  let affinities : Array[Array[Int]] = Array::makei(function.value_count(), _ => {
    []
  })
  let is_edge_argument = Array::make(function.value_count(), false)
  let is_edge_target = Array::make(function.value_count(), false)
  for block in 0..<function.block_count() {
    let successors = function.block_successors(block)
    for successor_index, target in successors {
      let arguments = function.edge_arguments(block, successor_index)
      let parameters = function.block_parameters(target)
      let count = arguments.length().min(parameters.length())
      for index in 0..<count {
        let argument = arguments[index]
        let parameter = parameters[index]
        is_edge_argument[argument.id] = true
        is_edge_target[parameter.id] = true
        add_edge_affinity(affinities, argument, parameter)
        add_edge_affinity(affinities, parameter, argument)
      }
    }
  }
  (affinities, is_edge_argument, is_edge_target)
}

///|
fn[F : FunctionView] allocate_segments_backtracking(
  function : F,
  environment : MachineEnv,
  ranges : LiveRangeSet,
  enable_eviction : Bool,
) -> (
  Array[AllocationSegment],
  Array[Array[Int]],
  Array[AllocationBundle],
  Array[Int],
) {
  let (segments, segments_by_value) = build_allocation_segments(ranges)
  let bundle_plan = build_production_bundle_plan(function, ranges, segments)
  let (bundles, segment_owner) = allocate_production_bundles(
    function, environment, ranges, segments, bundle_plan, enable_eviction,
  )
  (segments, segments_by_value, bundles, segment_owner)
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
fn[F : FunctionView] assign_backtracking_homes(
  plan : AllocationPlan,
  function : F,
  environment : MachineEnv,
  ranges : LiveRangeSet,
  segments : Array[AllocationSegment],
  segments_by_value : Array[Array[Int]],
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
  for value in 0..<function.value_count() {
    let vreg : VirtualReg = { id: value, class: function.value_class(value) }
    if !needs_spill[value] {
      plan.assign_value(vreg, Reg(register_homes[value].unwrap()))
      continue
    }
    let mut selected = -1
    for slot, occupants in slot_values {
      if occupants.is_empty() {
        continue
      }
      let mut compatible = true
      for occupant in occupants {
        if !function.values_share_spill_slot(value, occupant.id) ||
          !spill_homes_can_share(ranges, vreg, occupant) {
          compatible = false
          break
        }
      }
      if compatible {
        selected = slot
        break
      }
    }
    if selected < 0 {
      selected = plan.create_spill_slot(
        function.value_spill_size(value),
        function.value_spill_alignment(value),
      )
      slot_values.push([])
    }
    slot_values[selected].push(vreg)
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
fn live_register_home_value_at(
  register_home_values : Map[(Int, Int), Array[VirtualReg]],
  segments : Array[AllocationSegment],
  segments_by_value : Array[Array[Int]],
  reg : PhysicalReg,
  point : ProgramPoint,
) -> VirtualReg? {
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
      live_register_home_value_at(
        register_home_values, segments, segments_by_value, reg, point,
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
fn[F : FunctionView] assign_backtracking_operands(
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
  for block in 0..<function.block_count() {
    let resident_segments = Array::make(segments.length(), false)
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
        let reserved = match operand.constraint {
          FixedReg(reg) => Some(reg)
          AnyLocation =>
            match home {
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
              AnyLocation => home
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
          if home != selected && operand.constraint != AnyLocation {
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
      for reg in borrowed_temps {
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

///|
fn[F : FunctionView] allocate_fragmented(
  function : F,
  environment : MachineEnv,
  enable_eviction : Bool,
) -> AllocationPlan raise VerifyError {
  let ranges = build_function_live_ranges(function)
  let (segments, segments_by_value, _, _) = allocate_segments_backtracking(
    function, environment, ranges, enable_eviction,
  )
  let plan = AllocationPlan::new(function.value_count())
  assign_backtracking_homes(
    plan, function, environment, ranges, segments, segments_by_value,
  )
  assign_backtracking_operands(
    plan, function, environment, segments, segments_by_value,
  )
  assign_edge_transfers(plan, function)
  plan
}
