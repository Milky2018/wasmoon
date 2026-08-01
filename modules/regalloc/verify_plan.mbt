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
/// Plan edits bucketed by position.
///
/// Verification walks every instruction of every block, and a block may be
/// re-processed when dataflow refines its incoming state. Filtering the
/// function-wide edit array at each step made verification quadratic in
/// practice — a deeply nested function multiplied thousands of instructions
/// by thousands of edits on every visit. One bucketing pass keeps each
/// lookup proportional to the edits that actually apply, and bucket order
/// preserves the plan's edit order.
fn index_plan_edits(
  edits : Array[AllocationEdit],
) -> Map[EditPosition, Array[AllocationEdit]] {
  let index : Map[EditPosition, Array[AllocationEdit]] = Map([])
  for edit in edits {
    match index.get(edit.position) {
      Some(bucket) => bucket.push(edit)
      None => index[edit.position] = [edit]
    }
  }
  index
}

///|
fn apply_position_edits(
  state : PlanState,
  edits_at : Map[EditPosition, Array[AllocationEdit]],
  position : EditPosition,
) -> Unit raise VerifyError {
  guard edits_at.get(position) is Some(bucket) else { return }
  for edit in bucket {
    apply_plan_edit(state, edit)
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
  edits_at : Map[EditPosition, Array[AllocationEdit]],
) -> PlanState raise VerifyError {
  let current = state.copy()
  for instruction in function.block_instructions(block) {
    apply_position_edits(current, edits_at, Before(instruction))
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
    apply_position_edits(current, edits_at, After(instruction))
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
  target : Int,
  edits_at : Map[EditPosition, Array[AllocationEdit]],
) -> PlanState raise VerifyError {
  let state = output.copy()
  let source_id = function.block_id_at(block)
  let edge_position = Edge(source_block=source_id, successor_index=successor)
  if edits_at.get(edge_position) is Some(bucket) {
    let original = state.copy()
    for edit in bucket {
      require_value_at(original, edit.value, edit.from)
      state.values[location_key(edit.to)] = edit.value
    }
  }
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
  let edits_at = index_plan_edits(plan.edits())
  let block_count = function.block_count()
  let successors = Array::makei(block_count, block => {
    function.block_successors(block)
  })
  let has_predecessor = Array::make(block_count, false)
  for source_successors in successors {
    for target in source_successors {
      if target >= 0 && target < block_count {
        has_predecessor[target] = true
      }
    }
  }
  // Process pending blocks in reverse postorder. A plain stack revisits a
  // join-dense region once per refinement, and nested blocks lower to long
  // chains of forward joins, so verification cost grew with nesting depth.
  // In reverse postorder every acyclic region converges in a single pass;
  // loops add one pass per refinement round. Blocks unreachable from any
  // root keep their index order at the end, matching the staged seeding
  // below.
  let priority = Array::make(block_count, block_count)
  let postorder : Array[Int] = []
  let visited = Array::make(block_count, false)
  for root in 0..<block_count {
    if root != 0 && has_predecessor[root] {
      continue
    }
    if visited[root] {
      continue
    }
    // Iterative depth-first search; the explicit stack carries the next
    // successor index to visit for each open block.
    let stack : Array[(Int, Int)] = [(root, 0)]
    visited[root] = true
    while stack.length() > 0 {
      let (block, next_successor) = stack[stack.length() - 1]
      let block_successors = successors[block]
      if next_successor < block_successors.length() {
        stack[stack.length() - 1] = (block, next_successor + 1)
        let target = block_successors[next_successor]
        if target >= 0 && target < block_count && !visited[target] {
          visited[target] = true
          stack.push((target, 0))
        }
      } else {
        postorder.push(block)
        stack.pop() |> ignore
      }
    }
  }
  for index in 0..<postorder.length() {
    priority[postorder[postorder.length() - 1 - index]] = index
  }
  let order = Array::makei(block_count, block => block)
  order.sort_by((left, right) => {
    let by_priority = priority[left] - priority[right]
    if by_priority != 0 {
      by_priority
    } else {
      left - right
    }
  })
  let incoming : Array[PlanState?] = Array::make(block_count, None)
  let pending = Array::make(block_count, false)
  for block in 0..<block_count {
    if block == 0 || !has_predecessor[block] {
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
      pending[block] = true
    }
  }
  let mut next_unreachable_root = 0
  while true {
    let mut processed_any = true
    while processed_any {
      processed_any = false
      for order_index in 0..<block_count {
        let block = order[order_index]
        if !pending[block] {
          continue
        }
        pending[block] = false
        processed_any = true
        let output = process_plan_block(
          incoming[block].unwrap(),
          function,
          environment,
          plan,
          block,
          edits_at,
        )
        for successor, target in successors[block] {
          let next = prepare_successor_state(
            output, function, plan, block, successor, target, edits_at,
          )
          match incoming[target] {
            None => {
              incoming[target] = Some(next)
              pending[target] = true
            }
            Some(previous) => {
              let merged = previous.copy()
              merged.meet_with(next)
              if !merged.equals(previous) {
                incoming[target] = Some(merged)
                pending[target] = true
              }
            }
          }
        }
      }
    }
    while next_unreachable_root < block_count &&
          incoming[next_unreachable_root] is Some(_) {
      next_unreachable_root = next_unreachable_root + 1
    }
    if next_unreachable_root >= block_count {
      break
    }
    let state = PlanState::new()
    initialize_block_parameters(state, function, plan, next_unreachable_root)
    incoming[next_unreachable_root] = Some(state)
    pending[next_unreachable_root] = true
  }
}
