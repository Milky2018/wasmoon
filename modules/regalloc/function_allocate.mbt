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
) -> Unit raise VerifyError {
  for block_index in 0..<function.block_count() {
    let successors = function.block_successors(block_index)
    for successor_index, target in successors {
      let arguments = function.edge_arguments(block_index, successor_index)
      let parameters = function.block_parameters(target)
      for argument_index, argument in arguments {
        if argument_index >= parameters.length() {
          break
        }
        let parameter = parameters[argument_index]
        guard plan.value_location(argument.id) is Some(from) else {
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
        if !value_is_live_out_of_block(
            function, segments, segments_by_value, value, block_index,
          ) ||
          !value_is_live_into_block(segments, segments_by_value, value, target) {
          continue
        }
        let vreg : VirtualReg = {
          id: value,
          class: function.value_class(value),
        }
        guard plan.value_location(vreg.id) is Some(from) &&
          plan.value_location(vreg.id) is Some(to) else {
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
/// The phases proper: everything from the first `enter_phase` onwards.
///
/// Split out so the terminating event can be attached to every way this
/// returns. A single body cannot express that — MoonBit has no `finally`,
/// and a `raise` runs straight past a trailing call.
fn[F : FunctionView] run_allocation_phases(
  function : F,
  environment : MachineEnv,
  config : RegallocConfig,
) -> AllocationPlan raise VerifyError {
  let plan = allocate_bundle_plan(function, environment, config)
  config.enter_phase(Some(EditResolution))
  resolve_instruction_edits(plan, environment)
  if config.verify() {
    config.enter_phase(Some(Verification))
    verify_function_allocation(function, environment, plan)
  }
  plan
}

///|
/// Allocate directly from a read-only machine-function view.
///
/// The observer sees `Some(phase)` as each phase begins and exactly one
/// `None` once the last one ends, *including when allocation fails*. A raise
/// used to skip that `None`, leaving whoever was measuring with a phase that
/// never ended — `Verification` most often, since verifying the finished
/// plan is both the likeliest raise and the last phase to open.
pub fn[F : FunctionView] allocate_function(
  function : F,
  environment : MachineEnv,
  config? : RegallocConfig = RegallocConfig(),
) -> AllocationPlan raise VerifyError {
  // Ahead of the first phase on purpose: this raises before any phase has
  // opened, so there is no sequence to terminate, and an observer that has
  // heard nothing is owed nothing.
  verify_operand_preferences(function, environment)
  let plan = run_allocation_phases(function, environment, config) catch {
    error => {
      config.enter_phase(None)
      raise error
    }
  }
  config.enter_phase(None)
  plan
}
