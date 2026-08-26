///|
priv struct AllocationState {
  values : Map[(Int, Int), Value]
}

///|
fn allocation_location_key(location : Location) -> (Int, Int) {
  match location {
    Register(reg) =>
      match reg.class {
        Int => (0, reg.id)
        FpVector => (1, reg.id)
      }
    Stack(slot) => (2, slot.id)
  }
}

///|
fn AllocationState::new() -> AllocationState {
  { values: Map([]), }
}

///|
fn AllocationState::copy(self : AllocationState) -> AllocationState {
  let values : Map[(Int, Int), Value] = Map([])
  for key, value in self.values {
    values[key] = value
  }
  { values, }
}

///|
fn AllocationState::equals(
  self : AllocationState,
  other : AllocationState,
) -> Bool {
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
fn AllocationState::meet_with(
  self : AllocationState,
  other : AllocationState,
) -> Unit {
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
fn AllocationState::remove_value(self : AllocationState, value : Value) -> Unit {
  let removed : Array[(Int, Int)] = []
  for key, current in self.values {
    if current == value {
      removed.push(key)
    }
  }
  for key in removed {
    self.values.remove(key)
  }
}

///|
fn AllocationState::remove_register(
  self : AllocationState,
  reg : PhysicalReg,
) -> Unit {
  self.values.remove(allocation_location_key(Register(reg)))
}

///|
fn AllocationState::contains(
  self : AllocationState,
  value : Value,
  location : Location,
) -> Bool {
  self.values.get(allocation_location_key(location)) == Some(value)
}

///|
fn AllocationState::set(
  self : AllocationState,
  value : Value,
  location : Location,
) -> Unit {
  self.values[allocation_location_key(location)] = value
}

///|
fn Allocation::edit_index(self : Allocation, edit : Edit) -> Int {
  for index, candidate in self.edits {
    if candidate.point == edit.point && candidate.kind == edit.kind {
      return index
    }
  }
  -1
}

///|
fn apply_state_edit(
  state : AllocationState,
  allocation : Allocation,
  edit : Edit,
) -> Unit raise AllocationVerifyError {
  let (value, from, to) = match edit.kind {
    Spill(value~, reg~, slot~) => (value, Register(reg), Stack(slot))
    Reload(value~, slot~, reg~) => (value, Stack(slot), Register(reg))
    Move(value~, from~, to~) => (value, Register(from), Register(to))
    EdgeMove(value~, from~, to~, ..) => (value, from, to)
  }
  if !state.contains(value, from) {
    raise InvalidEdit(index=allocation.edit_index(edit))
  }
  state.set(value, to)
}

///|
fn apply_instruction_state_edits(
  state : AllocationState,
  allocation : Allocation,
  instruction : Instruction,
  placement : PointPlacement,
) -> Unit raise AllocationVerifyError {
  let edits = match placement {
    Before => allocation.before_edits[instruction.id]
    After => allocation.after_edits[instruction.id]
  }
  for edit in edits {
    apply_state_edit(state, allocation, edit)
  }
}

///|
fn[Inst] process_allocation_operand_phase(
  state : AllocationState,
  function : Function[Inst],
  allocation : Allocation,
  instruction : Instruction,
  timing : OperandTiming,
) -> Unit raise AllocationVerifyError {
  for operand_index, operand in function.instruction_operands(instruction) {
    if operand.timing != timing {
      continue
    }
    let location = allocation.operand_locations[instruction.id][operand_index].unwrap()
    if operand.role is Use {
      if !state.contains(operand.value, location) {
        raise MissingReload(instruction~, operand=operand_index)
      }
    }
    if operand.role is Def {
      state.remove_value(operand.value)
      state.set(operand.value, location)
    }
  }
}

///|
fn[Inst] process_allocation_block(
  state : AllocationState,
  function : Function[Inst],
  allocation : Allocation,
  block : Block,
) -> AllocationState raise AllocationVerifyError {
  let current = state.copy()
  let instructions = function.block_body(block)
  instructions.push(function.block_terminator(block).unwrap())
  for instruction in instructions {
    apply_instruction_state_edits(current, allocation, instruction, Before)
    process_allocation_operand_phase(
      current,
      function,
      allocation,
      instruction,
      Early,
    )
    for clobber in function.instruction_clobbers(instruction) {
      current.remove_register(clobber)
    }
    process_allocation_operand_phase(
      current,
      function,
      allocation,
      instruction,
      Late,
    )
    apply_instruction_state_edits(current, allocation, instruction, After)
  }
  current
}

///|
fn[Inst] initialize_allocation_block_parameters(
  state : AllocationState,
  function : Function[Inst],
  allocation : Allocation,
  block : Block,
) -> Unit {
  for parameter in function.block_parameters(block) {
    let home = allocation.value_locations[parameter.id].unwrap()
    state.remove_value(parameter)
    state.set(parameter, home)
  }
}

///|
fn[Inst] prepare_allocation_successor_state(
  output : AllocationState,
  function : Function[Inst],
  allocation : Allocation,
  source : Block,
  successor_index : Int,
  edge : Edge,
) -> AllocationState raise AllocationVerifyError {
  let state = output.copy()
  let original = state.copy()
  match allocation.edge_edits.get((source.id, successor_index)) {
    Some(edits) =>
      for edit in edits {
        guard edit.kind is EdgeMove(value~, from~, to~, ..) else {
          raise InvalidEdit(index=allocation.edit_index(edit))
        }
        if !original.contains(value, from) {
          raise InvalidEdit(index=allocation.edit_index(edit))
        }
        state.set(value, to)
      }
    None => ()
  }
  let parameters = function.block_parameters(edge.target)
  for index, argument in edge.arguments {
    let parameter = parameters[index]
    let home = allocation.value_locations[parameter.id].unwrap()
    if !state.contains(argument, home) {
      raise InvalidEdgeMove(index=-1)
    }
    state.remove_value(parameter)
    state.set(parameter, home)
  }
  state
}

///|
fn[Inst] verify_allocation_state(
  function : Function[Inst],
  allocation : Allocation,
) -> Unit raise AllocationVerifyError {
  let predecessors = function.predecessors()
  let incoming : Array[AllocationState?] = Array::make(
    function.block_count(),
    None,
  )
  let worklist : Array[Int] = []
  for block_id in 0..<function.block_count() {
    if block_id == 0 || predecessors[block_id].is_empty() {
      let state = AllocationState::new()
      if block_id == 0 {
        for parameter in function.parameters {
          state.set(
            parameter,
            allocation.value_locations[parameter.id].unwrap(),
          )
        }
      }
      let block = function.block_at(block_id).unwrap()
      initialize_allocation_block_parameters(state, function, allocation, block)
      incoming[block_id] = Some(state)
      worklist.push(block_id)
    }
  }
  let mut next_unreachable_root = 0
  while true {
    while worklist.pop() is Some(block_id) {
      let block = function.block_at(block_id).unwrap()
      let output = process_allocation_block(
        incoming[block_id].unwrap(),
        function,
        allocation,
        block,
      )
      let terminator = function.block_terminator(block).unwrap()
      for successor_index, edge in function.instruction_successors(terminator) {
        let next = prepare_allocation_successor_state(
          output, function, allocation, block, successor_index, edge,
        )
        let target = edge.target.id
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
    let block = function.block_at(next_unreachable_root).unwrap()
    let state = AllocationState::new()
    initialize_allocation_block_parameters(state, function, allocation, block)
    incoming[next_unreachable_root] = Some(state)
    worklist.push(next_unreachable_root)
  }
}
