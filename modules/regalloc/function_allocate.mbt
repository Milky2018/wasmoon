///|
priv struct RegisterClobberIndex {
  points_by_reg : Map[(Int, Int), Array[ProgramPoint]]
  block_order : Array[Int]
}

///|
fn[F : FunctionView] build_register_clobber_index(
  function : F,
  block_order : Array[Int],
) -> RegisterClobberIndex {
  let points_by_reg : Map[(Int, Int), Array[ProgramPoint]] = Map([])
  fn record(
    points_by_reg : Map[(Int, Int), Array[ProgramPoint]],
    reg : PhysicalReg,
    point : ProgramPoint,
  ) -> Unit {
    let key = physical_reg_key(reg)
    match points_by_reg.get(key) {
      Some(points) => points.push(point)
      None => points_by_reg[key] = [point]
    }
  }
  for block in 0..<function.block_count() {
    for instruction_index, instruction in function.block_instructions(block) {
      let point = ProgramPoint(block, instruction_index * 2 + 1)
      for clobber in function.instruction_clobbers(instruction) {
        record(points_by_reg, clobber, point)
      }
      for operand in function.instruction_operands(instruction) {
        if operand.constraint is FixedReg(reg) {
          record(
            points_by_reg,
            reg,
            operand_program_point(block, instruction_index, operand.timing),
          )
        }
      }
    }
  }
  for _, points in points_by_reg {
    points.sort_by(fn(left, right) {
      left.compare_with_order(right, block_order)
    })
  }
  { points_by_reg, block_order: block_order.copy() }
}

///|
fn RegisterClobberIndex::query(
  self : RegisterClobberIndex,
  reg : PhysicalReg,
  range : ProgramRange,
) -> (ProgramPoint?, Int) {
  guard self.points_by_reg.get(physical_reg_key(reg)) is Some(points) else {
    return (None, 0)
  }
  let mut comparisons = 0
  let mut lo = 0
  let mut hi = points.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    comparisons = comparisons + 1
    if points[mid].compare_with_order(range.start, self.block_order) <= 0 {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  if lo < points.length() {
    comparisons = comparisons + 1
    if points[lo].compare_with_order(range.end, self.block_order) < 0 {
      return (Some(points[lo]), comparisons)
    }
  }
  (None, comparisons)
}

///|
fn find_scratch_reg(
  environment : MachineEnv,
  class : RegClass,
  used : Array[PhysicalReg],
) -> PhysicalReg? {
  for reg in environment.operand_scratch_regs {
    if reg.class == class && !used.contains(reg) {
      return Some(reg)
    }
  }
  None
}

///|
fn add_use_transfer(
  plan : AllocationPlan,
  instruction : Int,
  operand : Operand,
  home : Location,
  selected : Location,
) -> Unit {
  if home == selected {
    return
  }
  plan.add_edit({
    value: operand.vreg,
    from: home,
    to: selected,
    position: Before(instruction),
  })
}

///|
fn segment_in_block(
  segments : Array[AllocationSegment],
  segments_by_value : Array[Array[Int]],
  value : VirtualReg,
  block : Int,
) -> Int? {
  if value.id < 0 || value.id >= segments_by_value.length() {
    return None
  }
  for segment_id in segments_by_value[value.id] {
    if segments[segment_id].range.start.block == block {
      return Some(segment_id)
    }
  }
  None
}

///|
fn segment_location(
  plan : AllocationPlan,
  segments : Array[AllocationSegment],
  segments_by_value : Array[Array[Int]],
  value : VirtualReg,
  block : Int,
) -> Location? {
  guard segment_in_block(segments, segments_by_value, value, block)
    is Some(segment_id) else {
    return plan.value_location(value.id)
  }
  match segments[segment_id].location {
    Some(SegmentReg(reg)) if segments[segment_id].defer_home => Some(Reg(reg))
    Some(SegmentSpill) | None => plan.value_location(value.id)
    Some(SegmentReg(_)) => plan.value_location(value.id)
  }
}

///|
fn edge_source_location(
  plan : AllocationPlan,
  segments : Array[AllocationSegment],
  segments_by_value : Array[Array[Int]],
  resident_segments_by_block : Array[Array[Bool]],
  value : VirtualReg,
  block : Int,
) -> Location? {
  guard segment_in_block(segments, segments_by_value, value, block)
    is Some(segment_id) else {
    return plan.value_location(value.id)
  }
  match segments[segment_id].location {
    Some(SegmentReg(reg)) if segments[segment_id].defer_home =>
      if block >= 0 &&
        block < resident_segments_by_block.length() &&
        segment_id < resident_segments_by_block[block].length() &&
        resident_segments_by_block[block][segment_id] {
        Some(Reg(reg))
      } else {
        plan.value_location(value.id)
      }
    _ => plan.value_location(value.id)
  }
}

///|
fn[F : FunctionView] value_is_live_out_of_block(
  function : F,
  segments : Array[AllocationSegment],
  segments_by_value : Array[Array[Int]],
  value : Int,
  block : Int,
) -> Bool {
  if value < 0 || value >= segments_by_value.length() {
    return false
  }
  for segment_id in segments_by_value[value] {
    if segments[segment_id].range.start.block == block &&
      segments[segment_id].range.end.inst ==
      function.block_instructions(block).length() * 2 {
      return true
    }
  }
  false
}

///|
fn value_is_live_into_block(
  segments : Array[AllocationSegment],
  segments_by_value : Array[Array[Int]],
  value : Int,
  block : Int,
) -> Bool {
  if value < 0 || value >= segments_by_value.length() {
    return false
  }
  for segment_id in segments_by_value[value] {
    if segments[segment_id].range.start.block == block &&
      segments[segment_id].range.start.inst == -1 {
      return true
    }
  }
  false
}

///|
fn[F : FunctionView] assign_edge_transfers(
  plan : AllocationPlan,
  function : F,
  segments : Array[AllocationSegment],
  segments_by_value : Array[Array[Int]],
  resident_segments_by_block : Array[Array[Bool]],
) -> Unit raise VerifyError {
  for block_index in 0..<function.block_count() {
    let successors = function.block_successors(block_index)
    for successor_index, target in successors {
      let arguments = function.edge_arguments(block_index, successor_index)
      let parameters = function.block_parameters(target)
      let transferred_arguments = Array::make(function.value_count(), false)
      for argument_index, argument in arguments {
        if argument_index >= parameters.length() {
          break
        }
        let parameter = parameters[argument_index]
        if argument.id >= 0 && argument.id < transferred_arguments.length() {
          transferred_arguments[argument.id] = true
        }
        guard edge_source_location(
            plan, segments, segments_by_value, resident_segments_by_block, argument,
            block_index,
          )
          is Some(from) else {
          raise Unassigned(vreg=argument)
        }
        guard plan.value_location(parameter.id) is Some(to) else {
          raise Unassigned(vreg=parameter)
        }
        if from != to {
          plan.add_edit({
            value: argument,
            from,
            to,
            position: Edge(
              source_block=function.block_id_at(block_index),
              successor_index~,
            ),
          })
        }
      }
      for value in 0..<function.value_count() {
        if transferred_arguments[value] ||
          !value_is_live_out_of_block(
            function, segments, segments_by_value, value, block_index,
          ) ||
          !value_is_live_into_block(segments, segments_by_value, value, target) {
          continue
        }
        let vreg : VirtualReg = {
          id: value,
          class: function.value_class(value),
        }
        guard edge_source_location(
            plan, segments, segments_by_value, resident_segments_by_block, vreg,
            block_index,
          )
          is Some(from) &&
          segment_location(plan, segments, segments_by_value, vreg, target)
          is Some(to) else {
          raise Unassigned(vreg~)
        }
        if from != to {
          plan.add_edit({
            value: vreg,
            from,
            to,
            position: Edge(
              source_block=function.block_id_at(block_index),
              successor_index~,
            ),
          })
        }
      }
    }
  }
}

///|
fn[F : FunctionView] verify_operand_preferences(
  function : F,
  environment : MachineEnv,
) -> Unit raise VerifyError {
  for block in 0..<function.block_count() {
    for instruction in function.block_instructions(block) {
      for operand in function.instruction_operands(instruction) {
        if operand.preference is Some(preferred) &&
          (
            preferred.class != operand.vreg.class ||
            !environment.allocatable_regs.contains(preferred)
          ) {
          raise InvalidPreference(vreg=operand.vreg, preferred~)
        }
      }
    }
  }
}

///|
/// Allocate directly from a read-only machine-function view.
pub fn[F : FunctionView] allocate_function(
  function : F,
  environment : MachineEnv,
  config? : RegallocConfig = RegallocConfig(),
) -> AllocationPlan raise VerifyError {
  verify_operand_preferences(function, environment)
  let plan = allocate_bundle_plan(function, environment, config.strategy())
  resolve_instruction_edits(plan, environment)
  if config.verify() {
    verify_function_allocation(function, environment, plan)
  }
  plan
}
