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
      // A clobber happens after Early operands and before Late operands. Place
      // it at the Early boundary: ranges ending in an Early use may occupy the
      // register, Late definitions start after it, and live-through ranges
      // cross it. Recording the clobber at the Late point made a split spill
      // gap end exactly on an open intersection boundary and allowed the gap
      // to be recolored into the clobbered register.
      let point = ProgramPoint(block, instruction_index * 2)
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
  { points_by_reg, block_order: block_order.copy(), }
}

///|
fn RegisterClobberIndex::first_intersection(
  self : RegisterClobberIndex,
  reg : PhysicalReg,
  segment_ids : Array[Int],
  segments : Array[AllocationSegment],
) -> ProgramPoint? {
  guard !segment_ids.is_empty() else { return None }
  guard self.points_by_reg.get(physical_reg_key(reg)) is Some(points) else {
    return None
  }
  let mut lo = 0
  let mut hi = points.length()
  let first_start = segments[segment_ids[0]].range.start
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    if points[mid].compare_with_order(first_start, self.block_order) < 0 {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  let mut segment_index = 0
  while lo < points.length() && segment_index < segment_ids.length() {
    let point = points[lo]
    let range = segments[segment_ids[segment_index]].range
    if point.compare_with_order(range.start, self.block_order) < 0 {
      lo = lo + 1
    } else if point.compare_with_order(range.end, self.block_order) < 0 {
      return Some(point)
    } else {
      segment_index = segment_index + 1
    }
  }
  None
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
/// Values keep one home for their complete live range, so live-through CFG
/// edges need no transfer. Only SSA block arguments can change value identity
/// and therefore location at an edge.
fn[F : FunctionView] assign_edge_transfers(
  plan : AllocationPlan,
  function : F,
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
  let plan = {
    errdefer config.enter_phase(None)
    run_allocation_phases(function, environment, config)
  }
  config.enter_phase(None)
  plan
}
