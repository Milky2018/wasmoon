///|
type AllocationState = @allocation_types.AllocationContents[Value]

///|
fn Allocation::edit_index(self : Allocation, edit : Edit) -> Int32 {
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
  let (value, from, to) : (Value, AllocationLocation, AllocationLocation) = match
    edit.kind {
    Spill(value~, reg~, slot~) =>
      (value, AllocationLocation::reg(reg), AllocationLocation::spill(slot.id))
    Reload(value~, slot~, reg~) =>
      (value, AllocationLocation::spill(slot.id), AllocationLocation::reg(reg))
    Move(value~, from~, to~) =>
      (value, AllocationLocation::reg(from), AllocationLocation::reg(to))
    EdgeMove(value~, from~, to~, ..) =>
      (
        value,
        allocation.import_location(from).unwrap(),
        allocation.import_location(to).unwrap(),
      )
  }
  if !state.contains(value, from) {
    raise InvalidEdit(index=allocation.edit_index(edit))
  }
  state.copy_location_from(state, from, to)
}

///|
fn apply_instruction_state_edits(
  state : AllocationState,
  allocation : Allocation,
  instruction : Instruction,
  placement : PointPlacement,
) -> Unit raise AllocationVerifyError {
  for edit in allocation.edits_at(instruction, placement) {
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
  successor_index : Int32,
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
        if !original.contains(value, allocation.import_location(from).unwrap()) {
          raise InvalidEdit(index=allocation.edit_index(edit))
        }
        state.copy_location_from(
          original,
          allocation.import_location(from).unwrap(),
          allocation.import_location(to).unwrap(),
        )
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
  }
  // Phi arguments are checked in the incoming state, before parallel rename.
  for parameter in parameters {
    state.remove_value(parameter)
  }
  for parameter in parameters {
    state.add_alias(
      parameter,
      allocation.value_locations[parameter.id].unwrap(),
    )
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
  let worklist : Array[Int32] = []
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
