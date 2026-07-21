///|
fn[F : FunctionView] collect_function_clobber_points(
  function : F,
) -> Map[(Int, Int), Array[ProgramPoint]] {
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
  points_by_reg
}

///|
fn find_scratch_reg(
  environment : MachineEnv,
  class : RegClass,
  used : Array[PhysicalReg],
) -> PhysicalReg? {
  for reg in environment.scratch_regs {
    if reg.class == class && !used.contains(reg) {
      return Some(reg)
    }
  }
  None
}

///|
fn add_home_transfer(
  plan : AllocationPlan,
  instruction : Int,
  operand : Operand,
  home : Location,
  selected : Location,
) -> Unit {
  if home == selected || operand.constraint == AnyLocation {
    return
  }
  if operand.role is Use || operand.role is UseDef {
    plan.add_edit({
      value: operand.vreg,
      from: home,
      to: selected,
      position: Before(instruction),
    })
  }
  if operand.role is Def || operand.role is UseDef {
    plan.add_edit({
      value: operand.vreg,
      from: selected,
      to: home,
      position: After(instruction),
    })
  }
}

///|
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
/// Allocate directly from a read-only machine-function view.
pub fn[F : FunctionView] allocate_function(
  function : F,
  environment : MachineEnv,
  config? : RegallocConfig = RegallocConfig(),
) -> AllocationPlan raise VerifyError {
  verify_operand_preferences(function, environment)
  let plan = allocate_fragmented(
    function,
    environment,
    config.strategy() is Backtracking,
  )
  resolve_instruction_edits(plan, environment)
  if config.verify() {
    verify_function_allocation(function, environment, plan)
  }
  plan
}
