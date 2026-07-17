///|
fn[Inst] Function::instruction_position(
  self : Function[Inst],
  instruction : Instruction,
) -> Int {
  let data = self.instructions[instruction.id]
  let body = self.blocks[data.parent.id].body
  for index, candidate in body {
    if candidate == instruction {
      return index
    }
  }
  body.length()
}

///|
fn[Inst] Function::definition_dominates(
  self : Function[Inst],
  value : Value,
  use_instruction : Instruction,
  dominators : Array[Array[Bool]],
) -> Bool {
  let use_data = self.instructions[use_instruction.id]
  match self.values[value.id].definition {
    FunctionParameter => true
    BlockParameter(block) => dominators[use_data.parent.id][block.id]
    InstructionResult(definition) => {
      let definition_data = self.instructions[definition.id]
      if definition_data.parent == use_data.parent {
        self.instruction_position(definition) <
        self.instruction_position(use_instruction)
      } else {
        dominators[use_data.parent.id][definition_data.parent.id]
      }
    }
  }
}

///|
fn[Inst] Function::predecessors(self : Function[Inst]) -> Array[Array[Int]] {
  let predecessors : Array[Array[Int]] = Array::makei(self.blocks.length(), _ => {
    []
  })
  for block_index, block in self.blocks {
    match block.terminator {
      Some(terminator) =>
        for edge in self.instructions[terminator.id].successors {
          if self.owns_block(edge.target) {
            predecessors[edge.target.id].push(block_index)
          }
        }
      None => ()
    }
  }
  predecessors
}

///|
fn[Inst] Function::compute_dominators(
  self : Function[Inst],
  predecessors : Array[Array[Int]],
) -> Array[Array[Bool]] {
  let count = self.blocks.length()
  let dominators = Array::makei(count, block => {
    if block == 0 {
      Array::makei(count, index => index == 0)
    } else {
      Array::make(count, true)
    }
  })
  let mut changed = true
  while changed {
    changed = false
    for block in 1..<count {
      let next = Array::make(count, true)
      for index in 0..<count {
        for predecessor in predecessors[block] {
          if !dominators[predecessor][index] {
            next[index] = false
            break
          }
        }
      }
      next[block] = true
      if next != dominators[block] {
        dominators[block] = next
        changed = true
      }
    }
  }
  dominators
}

///|
fn[Inst] Function::verify_layout(
  self : Function[Inst],
) -> Unit raise VCodeVerifyError {
  if self.layout.length() != self.blocks.length() {
    raise InvalidLayout
  }
  let seen = Array::make(self.blocks.length(), false)
  for block in self.layout {
    if !self.owns_block(block) || seen[block.id] {
      raise InvalidLayout
    }
    seen[block.id] = true
  }
}

///|
fn[Inst] Function::verify_instruction(
  self : Function[Inst],
  instruction : Instruction,
  dominators : Array[Array[Bool]],
) -> Unit raise VCodeVerifyError {
  let data = self.instructions[instruction.id]
  let operands = self.instruction_operands(instruction)
  for index, operand in operands {
    if !self.owns_value(operand.value) {
      raise ForeignValue(instruction~, value=operand.value)
    }
    let ty = self.values[operand.value.id].ty
    match operand.constraint {
      Fixed(reg) =>
        if reg.class != reg_class_for_value_type(ty) {
          raise FixedRegisterClassMismatch(instruction~, operand=index)
        }
      TiedTo(tied_to) => {
        if tied_to < 0 || tied_to >= operands.length() || tied_to == index {
          raise InvalidTie(instruction~, operand=index, tied_to~)
        }
        let tied = operands[tied_to]
        if tied.role == operand.role ||
          self.values[tied.value.id].ty != ty ||
          tied.tie_id != operand.tie_id ||
          operand.tie_id < 0 {
          raise InvalidTie(instruction~, operand=index, tied_to~)
        }
      }
      AnyLocation =>
        if operand.role != Use {
          raise InvalidAnyLocationConstraint(instruction~, operand=index)
        }
      Any => ()
    }
    if operand.role == Use &&
      !self.definition_dominates(operand.value, instruction, dominators) {
      let definition = self.values[operand.value.id].definition
      match definition {
        InstructionResult(definition) => {
          let definition_data = self.instructions[definition.id]
          if definition_data.parent == data.parent {
            raise UseBeforeDefinition(instruction~, value=operand.value)
          }
        }
        _ => ()
      }
      raise DefinitionDoesNotDominate(instruction~, value=operand.value)
    }
  }
  for index, reg in self.instruction_clobbers(instruction) {
    for earlier in 0..<index {
      if self.clobbers[data.clobber_start + earlier] == reg {
        raise DuplicateClobber(instruction~, reg~)
      }
    }
  }
  let metadata = data.metadata
  if metadata.live_gc_roots.length() > 0 && metadata.safepoint is None {
    raise InvalidSafepointRoot(instruction~, value=metadata.live_gc_roots[0])
  }
  for root in metadata.live_gc_roots {
    if !self.owns_value(root) ||
      self.values[root.id].ty != GcRef64 ||
      !self.definition_dominates(root, instruction, dominators) {
      raise InvalidSafepointRoot(instruction~, value=root)
    }
  }
  if data.role == Terminator {
    for edge in data.successors {
      if !self.owns_block(edge.target) {
        raise ForeignBlock(instruction~, block=edge.target)
      }
      let parameters = self.blocks[edge.target.id].parameters
      if edge.arguments.length() != parameters.length() {
        raise InvalidEdgeArity(instruction~, block=edge.target)
      }
      for index, argument in edge.arguments {
        if !self.owns_value(argument) {
          raise ForeignValue(instruction~, value=argument)
        }
        if self.values[argument.id].ty != self.values[parameters[index].id].ty {
          raise EdgeClassMismatch(instruction~, block=edge.target, index~)
        }
        if !self.definition_dominates(argument, instruction, dominators) {
          raise DefinitionDoesNotDominate(instruction~, value=argument)
        }
      }
    }
  }
}

///|
pub fn[Inst] verify_selected(
  function : Function[Inst],
) -> Unit raise VCodeVerifyError {
  if function.blocks.is_empty() {
    raise EmptyFunction
  }
  function.verify_layout()
  for index, block in function.blocks {
    if block.terminator is None {
      raise MissingTerminator(block=Block::new(function.owner, index))
    }
  }
  let predecessors = function.predecessors()
  let reachable = Array::make(function.blocks.length(), false)
  let worklist = [0]
  reachable[0] = true
  while worklist.length() > 0 {
    let block = worklist.pop().unwrap()
    let terminator = function.blocks[block].terminator.unwrap()
    for edge in function.instructions[terminator.id].successors {
      if function.owns_block(edge.target) && !reachable[edge.target.id] {
        reachable[edge.target.id] = true
        worklist.push(edge.target.id)
      }
    }
  }
  for index, is_reachable in reachable {
    if !is_reachable {
      raise UnreachableBlock(block=Block::new(function.owner, index))
    }
  }
  let dominators = function.compute_dominators(predecessors)
  for index in 0..<function.instructions.length() {
    function.verify_instruction(
      Instruction::new(function.owner, index),
      dominators,
    )
  }
}

///|
fn is_power_of_two(value : Int) -> Bool {
  value > 0 && (value & (value - 1)) == 0
}

///|
fn Allocation::assignment_for(
  self : Allocation,
  instruction : Instruction,
  operand_index : Int,
) -> Location? {
  self.operand_location(instruction, operand_index)
}

///|
fn Allocation::location_class(
  self : Allocation,
  location : Location,
) -> RegClass? {
  match location {
    Register(reg) => Some(reg.class)
    Stack(slot) =>
      if self.owns_slot(slot) {
        Some(reg_class_for_value_type(self.stack_slots[slot.id].ty))
      } else {
        None
      }
  }
}

///|
fn Allocation::location_matches(
  self : Allocation,
  location : Location,
  ty : ValueType,
) -> Bool {
  match location {
    Register(reg) => reg.class == reg_class_for_value_type(ty)
    Stack(slot) => self.owns_slot(slot) && self.stack_slots[slot.id].ty == ty
  }
}

///|
fn Allocation::has_reload(
  self : Allocation,
  function_owner : Ref[Unit],
  instruction : Instruction,
  value : Value,
  slot : StackSlot,
  reg : PhysicalReg,
) -> Bool {
  for edit in self.edits {
    match (edit.point, edit.kind) {
      (Some(point), Reload(value=edit_value, slot=edit_slot, reg=edit_reg)) =>
        if physical_equal(point.owner, function_owner) &&
          point.instruction == instruction &&
          point.placement == Before &&
          edit_value == value &&
          edit_slot == slot &&
          edit_reg == reg {
          return true
        }
      _ => ()
    }
  }
  false
}

///|
fn Allocation::has_spill(
  self : Allocation,
  function_owner : Ref[Unit],
  instruction : Instruction,
  value : Value,
  reg : PhysicalReg,
  slot : StackSlot,
) -> Bool {
  for edit in self.edits {
    match (edit.point, edit.kind) {
      (Some(point), Spill(value=edit_value, reg=edit_reg, slot=edit_slot)) =>
        if physical_equal(point.owner, function_owner) &&
          point.instruction == instruction &&
          point.placement == After &&
          edit_value == value &&
          edit_slot == slot &&
          edit_reg == reg {
          return true
        }
      _ => ()
    }
  }
  false
}

///|
fn Allocation::has_edge_move(
  self : Allocation,
  source : Block,
  successor_index : Int,
  value : Value,
  from : Location,
  to : Location,
) -> Bool {
  for edit in self.edits {
    match edit.kind {
      EdgeMove(
        source=edit_source,
        successor_index=edit_successor,
        value=edit_value,
        from=edit_from,
        to=edit_to
      ) =>
        if edit_source == source &&
          edit_successor == successor_index &&
          edit_value == value &&
          edit_from == from &&
          edit_to == to {
          return true
        }
      _ => ()
    }
  }
  false
}

///|
fn[Inst] verify_allocation_edits(
  function : Function[Inst],
  allocation : Allocation,
) -> Unit raise AllocationVerifyError {
  for index, edit in allocation.edits {
    match edit.kind {
      Spill(value~, reg~, slot~) | Reload(value~, slot~, reg~) => {
        if !allocation.owns_value(value) ||
          !allocation.owns_slot(slot) ||
          allocation.stack_slots[slot.id].ty !=
          function.value_type(value).unwrap() ||
          reg_class_for_value_type(function.value_type(value).unwrap()) !=
          reg.class {
          raise InvalidEdit(index~)
        }
        match edit.point {
          Some(point) =>
            if !physical_equal(point.owner, function.owner) ||
              !function.owns_instruction(point.instruction) {
              raise InvalidEdit(index~)
            }
          None => raise InvalidEdit(index~)
        }
      }
      Move(value~, from~, to~) =>
        if !allocation.owns_value(value) ||
          from.class != to.class ||
          reg_class_for_value_type(function.value_type(value).unwrap()) !=
          from.class ||
          edit.point is None {
          raise InvalidEdit(index~)
        }
      EdgeMove(source~, successor_index~, value~, from~, to~) => {
        if !function.owns_block(source) ||
          !allocation.owns_value(value) ||
          !allocation.location_matches(
            from,
            function.value_type(value).unwrap(),
          ) ||
          !allocation.location_matches(to, function.value_type(value).unwrap()) {
          raise InvalidEdgeMove(index~)
        }
        let terminator = function.block_terminator(source)
        if terminator is None ||
          successor_index < 0 ||
          successor_index >=
          function.instruction_successors(terminator.unwrap()).length() {
          raise InvalidEdgeMove(index~)
        }
        let edge = function.instruction_successors(terminator.unwrap())[successor_index]
        let mut found = false
        for argument in edge.arguments {
          if argument == value {
            found = true
          }
        }
        if !found || allocation.value_location(value) != Some(from) {
          raise InvalidEdgeMove(index~)
        }
      }
    }
  }
}

///|
fn[Inst] Function::allocation_live_after(
  self : Function[Inst],
) -> Array[Array[Bool]] {
  let value_count = self.value_count()
  let block_count = self.block_count()
  let live_in = Array::makei(block_count, _ => Array::make(value_count, false))
  let live_out = Array::makei(block_count, _ => Array::make(value_count, false))
  let mut changed = true
  while changed {
    changed = false
    for reverse_index in 0..<block_count {
      let block_index = block_count - reverse_index - 1
      let next_out = Array::make(value_count, false)
      let terminator = self.blocks[block_index].terminator.unwrap()
      for edge in self.instructions[terminator.id].successors {
        for value in 0..<value_count {
          if live_in[edge.target.id][value] {
            next_out[value] = true
          }
        }
        for argument in edge.arguments {
          next_out[argument.id] = true
        }
      }
      let next_in = next_out.copy()
      let instructions = self.blocks[block_index].body.copy()
      instructions.push(terminator)
      for reverse_inst in 0..<instructions.length() {
        let instruction = instructions[instructions.length() - reverse_inst - 1]
        let data = self.instructions[instruction.id]
        for result in data.results {
          next_in[result.id] = false
        }
        for operand in self.instruction_operands(instruction) {
          if operand.role == Use {
            next_in[operand.value.id] = true
          }
        }
        for root in data.metadata.live_gc_roots {
          next_in[root.id] = true
        }
      }
      for parameter in self.blocks[block_index].parameters {
        next_in[parameter.id] = false
      }
      if next_out != live_out[block_index] || next_in != live_in[block_index] {
        live_out[block_index] = next_out
        live_in[block_index] = next_in
        changed = true
      }
    }
  }
  let after = Array::makei(self.instruction_count(), _ => {
    Array::make(value_count, false)
  })
  for block_index in 0..<block_count {
    let live = live_out[block_index].copy()
    let terminator = self.blocks[block_index].terminator.unwrap()
    let instructions = self.blocks[block_index].body.copy()
    instructions.push(terminator)
    for reverse_inst in 0..<instructions.length() {
      let instruction = instructions[instructions.length() - reverse_inst - 1]
      after[instruction.id] = live.copy()
      let data = self.instructions[instruction.id]
      for result in data.results {
        live[result.id] = false
      }
      for operand in self.instruction_operands(instruction) {
        if operand.role == Use {
          live[operand.value.id] = true
        }
      }
      for root in data.metadata.live_gc_roots {
        live[root.id] = true
      }
    }
  }
  after
}

///|
priv enum LocationKey {
  RegisterKey(Int, RegClass)
  StackKey(Int)
} derive(Eq, Hash)

///|
fn location_key(location : Location) -> LocationKey {
  match location {
    Register(reg) => RegisterKey(reg.id, reg.class)
    Stack(slot) => StackKey(slot.id)
  }
}

///|
fn[Inst] verify_live_locations(
  function : Function[Inst],
  allocation : Allocation,
  live : Array[Bool],
) -> Unit raise AllocationVerifyError {
  let occupied : Map[LocationKey, Value] = Map([])
  for index, is_live in live {
    if !is_live {
      continue
    }
    let value = function.value_at(index).unwrap()
    let location = allocation.value_location(value).unwrap()
    let key = location_key(location)
    match occupied.get(key) {
      Some(left) => raise Interference(left~, right=value, location~)
      None => occupied.set(key, value)
    }
  }
}

///|
fn[Inst] verify_allocation_interference(
  function : Function[Inst],
  allocation : Allocation,
  live_after : Array[Array[Bool]],
) -> Unit raise AllocationVerifyError {
  for instruction_index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(instruction_index).unwrap()
    verify_live_locations(function, allocation, live_after[instruction_index])
    let before = live_after[instruction_index].copy()
    let middle = live_after[instruction_index].copy()
    for operand in function.instruction_operands(instruction) {
      if operand.role == Def {
        before[operand.value.id] = false
        if operand.timing == Late {
          middle[operand.value.id] = false
        }
      } else {
        before[operand.value.id] = true
        if operand.timing == Late {
          middle[operand.value.id] = true
        }
      }
    }
    let metadata = function.instruction_metadata(instruction).unwrap()
    for root in metadata.live_gc_roots {
      before[root.id] = true
      middle[root.id] = true
    }
    for edge in function.instruction_successors(instruction) {
      for argument in edge.arguments {
        before[argument.id] = true
      }
    }
    verify_live_locations(function, allocation, before)
    verify_live_locations(function, allocation, middle)
  }
}

///|
pub fn[Inst] verify_allocated(
  function : Function[Inst],
  allocation : Allocation,
) -> Unit raise AllocationVerifyError {
  verify_selected(function) catch {
    error => raise SelectedFailure(cause=error)
  }
  if !physical_equal(function.owner, allocation.source_owner) ||
    function.value_count() != allocation.source_value_count ||
    function.instruction_count() != allocation.source_instruction_count {
    raise SourceMismatch
  }
  for index, slot in allocation.stack_slots {
    if slot.size <= 0 || !is_power_of_two(slot.alignment) {
      raise InvalidStackSlotLayout(slot=StackSlot::new(allocation.owner, index))
    }
  }
  for index in 0..<function.value_count() {
    let value = function.value_at(index).unwrap()
    match allocation.value_locations[index] {
      None => raise MissingValueLocation(value~)
      Some(location) =>
        match allocation.location_class(location) {
          None => raise ForeignLocation(value~)
          Some(_) =>
            if !allocation.location_matches(location, function.values[index].ty) {
              raise LocationClassMismatch(value~)
            }
        }
    }
  }
  for instruction_index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(instruction_index).unwrap()
    let operands = function.instruction_operands(instruction)
    for operand_index, operand in operands {
      let assignment = match
        allocation.assignment_for(instruction, operand_index) {
        Some(assignment) => assignment
        None =>
          raise MissingOperandLocation(instruction~, operand=operand_index)
      }
      if allocation.location_class(assignment) !=
        Some(reg_class_for_value_type(function.values[operand.value.id].ty)) {
        raise OperandClassMismatch(instruction~, operand=operand_index)
      }
      match operand.constraint {
        Fixed(required) =>
          if assignment != Register(required) {
            raise FixedConstraintViolation(instruction~, operand=operand_index)
          }
        TiedTo(tied_to) => {
          let tied = allocation.assignment_for(instruction, tied_to)
          if tied is None || tied.unwrap() != assignment {
            raise TiedConstraintViolation(instruction~, operand=operand_index)
          }
        }
        Any =>
          if assignment is Stack(_) {
            raise RegisterConstraintViolation(
              instruction~,
              operand=operand_index,
            )
          }
        AnyLocation =>
          if operand.role != Use ||
            assignment != allocation.value_locations[operand.value.id].unwrap() {
            raise AnyLocationConstraintViolation(
              instruction~,
              operand=operand_index,
            )
          }
      }
      match allocation.value_locations[operand.value.id].unwrap() {
        Stack(slot) =>
          match assignment {
            Stack(_) => ()
            Register(reg) =>
              if operand.role == Use {
                if !allocation.has_reload(
                    function.owner,
                    instruction,
                    operand.value,
                    slot,
                    reg,
                  ) {
                  raise MissingReload(instruction~, operand=operand_index)
                }
              } else if !allocation.has_spill(
                  function.owner,
                  instruction,
                  operand.value,
                  reg,
                  slot,
                ) {
                raise MissingSpill(instruction~, operand=operand_index)
              }
          }
        Register(_) => ()
      }
    }
  }
  verify_allocation_edits(function, allocation)
  for block in function.layout() {
    let terminator = function.block_terminator(block).unwrap()
    for successor_index, edge in function.instruction_successors(terminator) {
      let parameters = function.block_parameters(edge.target)
      for index, argument in edge.arguments {
        let from = allocation.value_location(argument).unwrap()
        let to = allocation.value_location(parameters[index]).unwrap()
        if from != to &&
          !allocation.has_edge_move(block, successor_index, argument, from, to) {
          raise InvalidEdgeMove(index=allocation.edits.length())
        }
      }
    }
  }
  let live_after = function.allocation_live_after()
  verify_allocation_interference(function, allocation, live_after)
  for instruction_index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(instruction_index).unwrap()
    let clobbers = function.instruction_clobbers(instruction)
    for value_index in 0..<function.value_count() {
      if !live_after[instruction_index][value_index] {
        continue
      }
      match allocation.value_locations[value_index].unwrap() {
        Register(reg) =>
          if clobbers.contains(reg) {
            raise ClobberViolation(
              instruction~,
              value=function.value_at(value_index).unwrap(),
            )
          }
        Stack(_) => ()
      }
    }
  }
  for instruction_index in 0..<function.instruction_count() {
    let instruction = function.instruction_at(instruction_index).unwrap()
    let metadata = function.instructions[instruction_index].metadata
    for root in metadata.live_gc_roots {
      let expected = allocation.value_locations[root.id].unwrap()
      let mut found = false
      for entry in allocation.safepoint_roots {
        if entry.instruction == instruction &&
          entry.value == root &&
          entry.location == expected {
          found = true
        }
      }
      if !found {
        raise MissingSafepointRoot(instruction~, value=root)
      }
    }
  }
  for root in allocation.safepoint_roots {
    if !function.owns_instruction(root.instruction) ||
      !function.instructions[root.instruction.id].metadata.live_gc_roots.contains(
        root.value,
      ) {
      raise UnexpectedSafepointRoot(
        instruction=root.instruction,
        value=root.value,
      )
    }
  }
}

///|
pub fn[Inst] verify_framed(
  function : Function[Inst],
  allocation : Allocation,
  frame : FrameLayout,
) -> Unit raise FrameVerifyError {
  verify_allocated(function, allocation) catch {
    error => raise AllocationFailure(cause=error)
  }
  if !physical_equal(frame.source_owner, function.owner) {
    raise SourceMismatch
  }
  if !physical_equal(frame.allocation_owner, allocation.owner) ||
    frame.source_slot_count != allocation.stack_slot_count() {
    raise SourceMismatch
  }
  if frame.frame_size < 0 || frame.frame_size % frame.alignment != 0 {
    raise InvalidFrameSize(size=frame.frame_size)
  }
  if !is_power_of_two(frame.alignment) {
    raise InvalidFrameAlignment(alignment=frame.alignment)
  }
  for index, slot in allocation.stack_slots {
    let handle = StackSlot::new(allocation.owner, index)
    if index >= frame.slot_offsets.length() || frame.slot_offsets[index] is None {
      raise MissingStackSlot(slot=handle)
    }
    let offset = frame.slot_offsets[index].unwrap()
    if offset % slot.alignment != 0 {
      raise MisalignedStackSlot(slot=handle)
    }
    if offset < 0 || offset + slot.size > frame.frame_size {
      raise StackSlotOutOfFrame(slot=handle)
    }
    for earlier in 0..<index {
      let earlier_offset = frame.slot_offsets[earlier].unwrap()
      let earlier_slot = allocation.stack_slots[earlier]
      if offset < earlier_offset + earlier_slot.size &&
        earlier_offset < offset + slot.size {
        raise OverlappingStackSlots(
          left=StackSlot::new(allocation.owner, earlier),
          right=handle,
        )
      }
    }
  }
}

///|
pub fn[Inst] verify_emission_input(
  function : Function[Inst],
  allocation : Allocation,
  frame : FrameLayout,
) -> Unit raise EmissionVerifyError {
  verify_framed(function, allocation, frame) catch {
    error => raise FrameFailure(cause=error)
  }
}
