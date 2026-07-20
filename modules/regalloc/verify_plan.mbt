///|
priv struct PlanState {
  values : Map[(Int, Int), VirtualReg]
}

///|
fn PlanState::new() -> PlanState {
  { values: Map([]) }
}

///|
fn PlanState::copy(self : PlanState) -> PlanState {
  let values : Map[(Int, Int), VirtualReg] = Map([])
  for key, value in self.values {
    values[key] = value
  }
  { values, }
}

///|
fn PlanState::equals(self : PlanState, other : PlanState) -> Bool {
  let mut count = 0
  for key, value in self.values {
    count = count + 1
    if other.values.get(key) != Some(value) {
      return false
    }
  }
  let mut other_count = 0
  for _ in other.values {
    other_count = other_count + 1
  }
  count == other_count
}

///|
fn PlanState::meet_with(self : PlanState, other : PlanState) -> Unit {
  let removed : Array[(Int, Int)] = []
  for key, value in self.values {
    if other.values.get(key) != Some(value) {
      removed.push(key)
    }
  }
  for key in removed {
    self.values.remove(key)
  }
}

///|
fn PlanState::remove_value(self : PlanState, value : VirtualReg) -> Unit {
  let removed : Array[(Int, Int)] = []
  for key, existing in self.values {
    if existing == value {
      removed.push(key)
    }
  }
  for key in removed {
    self.values.remove(key)
  }
}

///|
fn PlanState::remove_register(self : PlanState, register : PhysicalReg) -> Unit {
  self.values.remove(physical_reg_key(register))
}

///|
fn plan_location_is_legal(
  environment : MachineEnv,
  plan : AllocationPlan,
  value : VirtualReg,
  location : Location,
) -> Bool {
  match location {
    Reg(reg) =>
      reg.class == value.class &&
      (
        environment.allocatable_regs.contains(reg) ||
        environment.scratch_regs.contains(reg)
      )
    Spill(slot) =>
      if plan.spill_slot(slot) is Some(spec) {
        spec.size > 0 && spec.alignment > 0
      } else {
        false
      }
  }
}

///|
fn require_plan_location(
  environment : MachineEnv,
  plan : AllocationPlan,
  value : VirtualReg,
  location : Location,
) -> Unit raise VerifyError {
  if !plan_location_is_legal(environment, plan, value, location) {
    raise InvalidPlan(message="illegal allocation location for v\{value.id}")
  }
}

///|
fn require_value_at(
  state : PlanState,
  value : VirtualReg,
  location : Location,
) -> Unit raise VerifyError {
  if state.values.get(location_key(location)) != Some(value) {
    raise IncorrectValue(vreg=value, location~)
  }
}

///|
fn apply_plan_edit(
  state : PlanState,
  edit : AllocationEdit,
) -> Unit raise VerifyError {
  require_value_at(state, edit.value, edit.from)
  if edit.from is Spill(_) && edit.to is Spill(_) {
    raise InvalidPlan(message="stack-to-stack allocation edit")
  }
  state.values[location_key(edit.to)] = edit.value
}

///|
fn apply_position_edits(
  state : PlanState,
  edits : Array[AllocationEdit],
  position : EditPosition,
) -> Unit raise VerifyError {
  for edit in edits {
    if edit.position == position {
      apply_plan_edit(state, edit)
    }
  }
}

///|
fn[F : FunctionView] process_operand_phase(
  state : PlanState,
  function : F,
  environment : MachineEnv,
  plan : AllocationPlan,
  instruction : Int,
  timing : OperandTiming,
) -> Unit raise VerifyError {
  for operand_index, operand in function.instruction_operands(instruction) {
    if operand.timing != timing {
      continue
    }
    guard plan.operand_location(instruction, operand_index) is Some(location) else {
      raise InvalidPlan(
        message="missing allocation for instruction \{instruction} operand \{operand_index}",
      )
    }
    require_plan_location(environment, plan, operand.vreg, location)
    if operand.constraint is FixedReg(required) && location != Reg(required) {
      raise FixedConstraintViolation(
        vreg=operand.vreg,
        required~,
        actual=location,
      )
    }
    if operand.role is Use || operand.role is UseDef {
      require_value_at(state, operand.vreg, location)
    }
    if operand.role is Def || operand.role is UseDef {
      state.remove_value(operand.vreg)
      state.values[location_key(location)] = operand.vreg
    }
  }
}

///|
fn[F : FunctionView] process_plan_block(
  state : PlanState,
  function : F,
  environment : MachineEnv,
  plan : AllocationPlan,
  block : Int,
  edits : Array[AllocationEdit],
) -> PlanState raise VerifyError {
  let current = state.copy()
  for instruction in function.block_instructions(block) {
    apply_position_edits(current, edits, Before(instruction))
    process_operand_phase(
      current,
      function,
      environment,
      plan,
      instruction,
      Early,
    )
    for clobber in function.instruction_clobbers(instruction) {
      current.remove_register(clobber)
    }
    process_operand_phase(
      current,
      function,
      environment,
      plan,
      instruction,
      Late,
    )
    apply_position_edits(current, edits, After(instruction))
  }
  current
}

///|
fn[F : FunctionView] initialize_block_parameters(
  state : PlanState,
  function : F,
  plan : AllocationPlan,
  block : Int,
) -> Unit raise VerifyError {
  for parameter in function.block_parameters(block) {
    guard plan.value_location(parameter.id) is Some(location) else {
      raise Unassigned(vreg=parameter)
    }
    state.remove_value(parameter)
    state.values[location_key(location)] = parameter
  }
}

///|
fn[F : FunctionView] prepare_successor_state(
  output : PlanState,
  function : F,
  plan : AllocationPlan,
  block : Int,
  successor : Int,
  edits : Array[AllocationEdit],
) -> PlanState raise VerifyError {
  let state = output.copy()
  let source_id = function.block_id_at(block)
  let edge_position = Edge(source_block=source_id, successor_index=successor)
  let original = state.copy()
  for edit in edits {
    if edit.position == edge_position {
      require_value_at(original, edit.value, edit.from)
      state.values[location_key(edit.to)] = edit.value
    }
  }
  let target = function.block_successors(block)[successor]
  let arguments = function.edge_arguments(block, successor)
  let parameters = function.block_parameters(target)
  if arguments.length() != parameters.length() {
    raise InvalidPlan(
      message="edge argument count does not match block parameters",
    )
  }
  for index, argument in arguments {
    let parameter = parameters[index]
    guard plan.value_location(parameter.id) is Some(parameter_home) else {
      raise Unassigned(vreg=parameter)
    }
    require_value_at(state, argument, parameter_home)
    state.remove_value(parameter)
    state.values[location_key(parameter_home)] = parameter
  }
  state
}

///|
fn[F : FunctionView] verify_function_allocation(
  function : F,
  environment : MachineEnv,
  plan : AllocationPlan,
) -> Unit raise VerifyError {
  for value in 0..<function.value_count() {
    let vreg : VirtualReg = { id: value, class: function.value_class(value) }
    guard plan.value_location(value) is Some(location) else {
      raise Unassigned(vreg~)
    }
    require_plan_location(environment, plan, vreg, location)
    if location is Spill(slot) {
      let spec = plan.spill_slot(slot).unwrap()
      if spec.size < function.value_spill_size(value) ||
        spec.alignment < function.value_spill_alignment(value) {
        raise InvalidPlan(message="spill slot is too small for v\{value}")
      }
    }
  }
  let edits = plan.edits()
  let incoming : Array[PlanState?] = Array::make(function.block_count(), None)
  let worklist : Array[Int] = []
  for block in 0..<function.block_count() {
    let mut has_predecessor = false
    for predecessor in 0..<function.block_count() {
      if function.block_successors(predecessor).contains(block) {
        has_predecessor = true
        break
      }
    }
    if block == 0 || !has_predecessor {
      let state = PlanState::new()
      if block == 0 {
        for parameter in function.entry_values() {
          guard plan.value_location(parameter.id) is Some(location) else {
            raise Unassigned(vreg=parameter)
          }
          state.values[location_key(location)] = parameter
        }
      }
      initialize_block_parameters(state, function, plan, block)
      incoming[block] = Some(state)
      worklist.push(block)
    }
  }
  let mut next_unreachable_root = 0
  while true {
    while worklist.pop() is Some(block) {
      let output = process_plan_block(
        incoming[block].unwrap(),
        function,
        environment,
        plan,
        block,
        edits,
      )
      for successor in 0..<function.block_successors(block).length() {
        let target = function.block_successors(block)[successor]
        let next = prepare_successor_state(
          output, function, plan, block, successor, edits,
        )
        match incoming[target] {
          None => {
            incoming[target] = Some(next)
            worklist.push(target)
          }
          Some(previous) => {
            let merged = previous.copy()
            merged.meet_with(next)
            if !merged.equals(previous) {
              incoming[target] = Some(merged)
              worklist.push(target)
            }
          }
        }
      }
    }
    while next_unreachable_root < function.block_count() &&
          incoming[next_unreachable_root] is Some(_) {
      next_unreachable_root = next_unreachable_root + 1
    }
    if next_unreachable_root >= function.block_count() {
      break
    }
    let state = PlanState::new()
    initialize_block_parameters(state, function, plan, next_unreachable_root)
    incoming[next_unreachable_root] = Some(state)
    worklist.push(next_unreachable_root)
  }
}
