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
  mut location : SegmentLocation?
}

///|
priv struct SegmentQueue {
  segments : Array[AllocationSegment]
  items : Array[Int]
  in_queue : Array[Bool]
}

///|
fn SegmentQueue::new(segments : Array[AllocationSegment]) -> SegmentQueue {
  { segments, items: [], in_queue: Array::make(segments.length(), false) }
}

///|
fn SegmentQueue::higher(self : SegmentQueue, lhs : Int, rhs : Int) -> Bool {
  self.segments[lhs].id < self.segments[rhs].id
}

///|
fn SegmentQueue::push(self : SegmentQueue, segment : Int) -> Unit {
  if self.in_queue[segment] {
    return
  }
  self.in_queue[segment] = true
  self.items.push(segment)
  let mut index = self.items.length() - 1
  while index > 0 {
    let parent = (index - 1) / 2
    if !self.higher(self.items[index], self.items[parent]) {
      break
    }
    let temporary = self.items[index]
    self.items[index] = self.items[parent]
    self.items[parent] = temporary
    index = parent
  }
}

///|
fn SegmentQueue::pop(self : SegmentQueue) -> Int? {
  if self.items.is_empty() {
    return None
  }
  let first = self.items[0]
  self.in_queue[first] = false
  let last = self.items.pop().unwrap()
  if !self.items.is_empty() {
    self.items[0] = last
    let mut index = 0
    while true {
      let left = index * 2 + 1
      if left >= self.items.length() {
        break
      }
      let right = left + 1
      let mut higher = left
      if right < self.items.length() &&
        self.higher(self.items[right], self.items[left]) {
        higher = right
      }
      if !self.higher(self.items[higher], self.items[index]) {
        break
      }
      let temporary = self.items[index]
      self.items[index] = self.items[higher]
      self.items[higher] = temporary
      index = higher
    }
  }
  Some(first)
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
fn segment_weight(range : LiveRange, fragment : ProgramRange) -> Int {
  let mut weight = 1
  for use_position in range.uses {
    if fragment.contains(use_position.point, []) {
      weight = weight + use_weight(use_position)
    }
  }
  weight
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
    for fragment in range.ranges {
      let id = segments.length()
      segments.push({
        id,
        value: range.vreg,
        range: fragment,
        weight: segment_weight(range, fragment),
        location: None,
      })
      segments_by_value[range.vreg.id].push(id)
    }
  }
  (segments, segments_by_value)
}

///|
fn segment_uses_clobbered_register(
  segment : AllocationSegment,
  reg : PhysicalReg,
  clobbers : Map[(Int, Int), Array[ProgramPoint]],
) -> Bool {
  match clobbers.get(physical_reg_key(reg)) {
    Some(points) =>
      for point in points {
        if segment.range.start.compare_with_order(point, []) < 0 &&
          point.compare_with_order(segment.range.end, []) < 0 {
          return true
        }
      }
    None => ()
  }
  false
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
) -> Array[Int] {
  let conflicts : Array[Int] = []
  for segment in occupied {
    if segments[segment].range.overlaps(current.range, []) {
      conflicts.push(segment)
    }
  }
  conflicts
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
  guard ranges.get_by_vreg(segment.value) is Some(range) else { return None }
  for use_position in range.uses {
    if segment.range.contains(use_position.point, []) &&
      use_position.constraint is FixedReg(reg) {
      return Some(reg)
    }
  }
  None
}

///|
fn push_register_candidate(order : Array[Int], candidate : Int?) -> Unit {
  if candidate is Some(index) && !order.contains(index) {
    order.push(index)
  }
}

///|
fn[F : FunctionView] allocate_segments_backtracking(
  function : F,
  environment : MachineEnv,
  ranges : LiveRangeSet,
  enable_eviction : Bool,
) -> (Array[AllocationSegment], Array[Array[Int]]) {
  let (segments, segments_by_value) = build_allocation_segments(ranges)
  let occupied : Array[Array[Int]] = []
  for _ in environment.allocatable_regs {
    occupied.push([])
  }
  let clobbers = collect_function_clobber_points(function)
  let preferred_by_value : Array[PhysicalReg?] = Array::make(
    function.value_count(),
    None,
  )
  let queue = SegmentQueue::new(segments)
  for segment in segments {
    queue.push(segment.id)
  }
  while queue.pop() is Some(segment_id) {
    let segment = segments[segment_id]
    if segment.location is Some(_) {
      continue
    }
    let mut free_register = -1
    let mut eviction_register = -1
    let eviction_conflicts : Array[Int] = []
    let mut eviction_cost : Int? = None
    let register_order : Array[Int] = []
    if segment_fixed_hint(ranges, segment) is Some(fixed) {
      push_register_candidate(
        register_order,
        register_index(environment.allocatable_regs, fixed),
      )
    }
    if preferred_by_value[segment.value.id] is Some(preferred) {
      push_register_candidate(
        register_order,
        register_index(environment.allocatable_regs, preferred),
      )
    }
    for index in 0..<environment.allocatable_regs.length() {
      push_register_candidate(register_order, Some(index))
    }
    for register_index in register_order {
      let reg = environment.allocatable_regs[register_index]
      if reg.class != segment.value.class ||
        segment_uses_clobbered_register(segment, reg, clobbers) {
        continue
      }
      let conflicts = conflicting_segments(
        segments,
        occupied[register_index],
        segment,
      )
      if conflicts.is_empty() {
        free_register = register_index
        break
      }
      let mut cost = 0
      for conflict in conflicts {
        cost = cost + segments[conflict].weight
      }
      if enable_eviction &&
        cost < segment.weight &&
        (eviction_cost is None || cost < eviction_cost.unwrap()) {
        eviction_register = register_index
        eviction_cost = Some(cost)
        eviction_conflicts.clear()
        for conflict in conflicts {
          eviction_conflicts.push(conflict)
        }
      }
    }
    let selected = if free_register >= 0 {
      free_register
    } else {
      eviction_register
    }
    if selected < 0 {
      segment.location = Some(SegmentSpill)
      continue
    }
    for conflict in eviction_conflicts {
      remove_occupied_segment(occupied, selected, conflict)
      segments[conflict].location = None
      queue.push(conflict)
    }
    let reg = environment.allocatable_regs[selected]
    segment.location = Some(SegmentReg(reg))
    preferred_by_value[segment.value.id] = Some(reg)
    occupied[selected].push(segment_id)
  }
  (segments, segments_by_value)
}

///|
fn values_overlap(
  ranges : LiveRangeSet,
  lhs : VirtualReg,
  rhs : VirtualReg,
) -> Bool {
  match (ranges.get_by_vreg(lhs), ranges.get_by_vreg(rhs)) {
    (Some(left), Some(right)) => left.overlaps(right, ranges.block_order)
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
          values_overlap(ranges, vreg, occupant) {
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
fn segment_location_at(
  segments : Array[AllocationSegment],
  segments_by_value : Array[Array[Int]],
  value : VirtualReg,
  point : ProgramPoint,
) -> SegmentLocation? {
  if value.id < 0 || value.id >= segments_by_value.length() {
    return None
  }
  for segment in segments_by_value[value.id] {
    if segments[segment].range.contains(point, []) {
      return segments[segment].location
    }
  }
  None
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
    for instruction_index, instruction in function.block_instructions(block) {
      let operands = function.instruction_operands(instruction)
      let assigned : Array[Location?] = Array::make(operands.length(), None)
      let natural_locations : Array[Location] = []
      let used_temps : Array[PhysicalReg] = []
      for operand in operands {
        let home = plan.value_location(operand.vreg.id).unwrap()
        let natural = match
          segment_location_at(
            segments,
            segments_by_value,
            operand.vreg,
            operand_program_point(block, instruction_index, operand.timing),
          ) {
          Some(SegmentReg(reg)) => Reg(reg)
          Some(SegmentSpill) | None => home
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
                      None =>
                        borrow_allocatable_register(
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
        add_home_transfer(plan, instruction, operand, home, selected)
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
  let (segments, segments_by_value) = allocate_segments_backtracking(
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
