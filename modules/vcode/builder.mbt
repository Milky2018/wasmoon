///|
pub struct Builder[Inst] {
  priv function : Function[Inst]
}

///|
pub fn[Inst] Builder::new(
  name : String,
  parameter_types : Array[ValueType],
) -> Builder[Inst] {
  { function: Function::new(name, Platform, parameter_types, []), }
}

///|
pub fn[Inst] Builder::new_with_results(
  name : String,
  parameter_types : Array[ValueType],
  result_types : Array[ValueType],
) -> Builder[Inst] {
  { function: Function::new(name, Platform, parameter_types, result_types), }
}

///|
pub fn[Inst] Builder::new_with_protocol(
  name : String,
  protocol : @native.CallProtocol,
  parameter_types : Array[ValueType],
  result_types : Array[ValueType],
) -> Builder[Inst] {
  { function: Function::new(name, protocol, parameter_types, result_types), }
}

///|
pub fn[Inst] Builder::entry_block(self : Builder[Inst]) -> Block {
  self.function.entry_block()
}

///|
pub fn[Inst] Builder::parameter(
  self : Builder[Inst],
  index : Int,
) -> Value raise VCodeBuildError {
  match self.function.parameter_at(index) {
    Some(value) => value
    None => raise InvalidParameter(index~)
  }
}

///|
pub fn[Inst] Builder::create_block(
  self : Builder[Inst],
  parameter_types : Array[ValueType],
) -> Block {
  let block = self.function.allocate_block(parameter_types)
  self.function.blocks[block.id].layout_index = self.function.layout.length()
  self.function.layout.push(block)
  block
}

///|
pub fn[Inst] Builder::block_parameter(
  self : Builder[Inst],
  block : Block,
  index : Int,
) -> Value raise VCodeBuildError {
  if !self.function.owns_block(block) {
    raise ForeignBlock(block~)
  }
  match self.function.blocks[block.id].parameters.get(index) {
    Some(value) => value
    None => raise InvalidBlockParameter(block~, index~)
  }
}

///|
fn[Inst] Builder::validate_inputs(
  self : Builder[Inst],
  inputs : Array[Input],
  metadata : InstructionMetadata,
) -> Unit raise VCodeBuildError {
  for input in inputs {
    if !self.function.owns_value(input.value) {
      raise ForeignValue(value=input.value)
    }
  }
  for root in metadata.live_gc_roots {
    if !self.function.owns_value(root) {
      raise ForeignValue(value=root)
    }
  }
}

///|
fn[Inst] Builder::validate_instruction(
  self : Builder[Inst],
  inputs : Array[Input],
  outputs : Array[Output],
  successors : Array[Edge],
  metadata : InstructionMetadata,
) -> Array[Int]? raise VCodeBuildError {
  self.validate_inputs(inputs, metadata)
  for input in inputs {
    let expected = reg_class_for_value_type(
      self.function.value_type(input.value).unwrap(),
    )
    if input.constraint is Fixed(reg) && reg.class != expected {
      raise InvalidOperandConstraint
    }
    if input.constraint is TiedTo(_) {
      raise InvalidOperandConstraint
    }
    if input.preference is Some(preference) && preference.class != expected {
      raise InvalidOperandConstraint
    }
  }
  let mut input_tie_ids : Array[Int]? = None
  for output in outputs {
    let expected = reg_class_for_value_type(output.ty)
    match output.constraint {
      Fixed(reg) => if reg.class != expected { raise InvalidOperandConstraint }
      TiedTo(tied_to) =>
        if tied_to < 0 ||
          tied_to >= inputs.length() ||
          (input_tie_ids is Some(ids) && ids[tied_to] >= 0) ||
          self.function.value_type(inputs[tied_to].value) != Some(output.ty) {
          raise InvalidOperandConstraint
        } else {
          if input_tie_ids is None {
            input_tie_ids = Some(Array::make(inputs.length(), -1))
          }
          input_tie_ids.unwrap()[tied_to] = tied_to
        }
      AnyLocation | Any => ()
    }
    if output.preference is Some(preference) && preference.class != expected {
      raise InvalidOperandConstraint
    }
  }
  for edge in successors {
    if !self.function.owns_block(edge.target) {
      raise ForeignBlock(block=edge.target)
    }
    for argument in edge.arguments {
      if !self.function.owns_value(argument) {
        raise ForeignValue(value=argument)
      }
    }
  }
  input_tie_ids
}

///|
fn[Inst] Builder::require_body_open(
  self : Builder[Inst],
  block : Block,
) -> Unit raise VCodeBuildError {
  if !self.function.owns_block(block) {
    raise ForeignBlock(block~)
  }
  if self.function.blocks[block.id].terminator is Some(_) {
    raise BlockAlreadyTerminated(block~)
  }
}

///|
fn[Inst] Builder::require_terminator_open(
  self : Builder[Inst],
  block : Block,
) -> Unit raise VCodeBuildError {
  if !self.function.owns_block(block) {
    raise ForeignBlock(block~)
  }
  if self.function.blocks[block.id].terminator is Some(_) {
    raise DuplicateTerminator(block~)
  }
}

///|
fn[Inst] Builder::commit_instruction(
  self : Builder[Inst],
  block : Block,
  inst : Inst,
  role : InstructionRole,
  inputs : Array[Input],
  outputs : Array[Output],
  successors : Array[Edge],
  clobbers : Array[PhysicalReg],
  metadata : InstructionMetadata,
  input_tie_ids : Array[Int]?,
) -> (Instruction, Array[Value]) raise VCodeBuildError {
  let instruction = Instruction::new(
    self.function.owner,
    self.function.instructions.length(),
  )
  let results : Array[Value] = []
  for output in outputs {
    results.push(
      self.function.allocate_value(output.ty, InstructionResult(instruction)),
    )
  }
  let operand_start = self.function.operands.length()
  for input_index, input in inputs {
    let constraint : AllocationConstraint = match input.constraint {
      Any => AnyReg
      AnyLocation => AnyLocation
      Fixed(reg) => FixedReg(reg)
      TiedTo(_) => raise InvalidOperandConstraint
    }
    self.function.operands.push({
      vreg: {
        id: input.value.id,
        class: reg_class_for_value_type(self.function.values[input.value.id].ty),
      },
      role: Use,
      constraint,
      preference: input.preference,
      timing: input.timing,
      tie_id: match input_tie_ids {
        Some(ids) => ids[input_index]
        None => -1
      },
    })
  }
  for index, output in outputs {
    let tie_id = match output.constraint {
      TiedTo(tied_to) => tied_to
      _ => -1
    }
    let constraint : AllocationConstraint = match output.constraint {
      Any | TiedTo(_) => AnyReg
      AnyLocation => AnyLocation
      Fixed(reg) => FixedReg(reg)
    }
    self.function.operands.push({
      vreg: {
        id: results[index].id,
        class: reg_class_for_value_type(output.ty),
      },
      role: Def,
      constraint,
      preference: output.preference,
      timing: output.timing,
      tie_id,
    })
  }
  for root in metadata.live_gc_roots {
    self.function.operands.push({
      vreg: {
        id: root.id,
        class: reg_class_for_value_type(self.function.values[root.id].ty),
      },
      role: Use,
      constraint: PreservedHome,
      preference: None,
      timing: Late,
      tie_id: -1,
    })
  }
  let clobber_start = self.function.clobbers.length()
  self.function.clobbers.push_iter(clobbers.iter())
  self.function.instructions.push({
    inst,
    parent: block,
    role,
    operand_start,
    operand_count: inputs.length() + outputs.length(),
    allocation_operand_count: inputs.length() +
    outputs.length() +
    metadata.live_gc_roots.length(),
    clobber_start,
    clobber_count: clobbers.length(),
    results,
    successors: successors.map(edge => edge.copy()),
    metadata: metadata.copy(),
  })
  match role {
    Body => self.function.blocks[block.id].body.push(instruction)
    Terminator => self.function.blocks[block.id].terminator = Some(instruction)
  }
  (instruction, results)
}

///|
pub fn[Inst] Builder::append_body(
  self : Builder[Inst],
  block : Block,
  inst : Inst,
  inputs : Array[Input],
  outputs : Array[Output],
  clobbers : Array[PhysicalReg],
  metadata : InstructionMetadata,
) -> (Instruction, Array[Value]) raise VCodeBuildError {
  self.require_body_open(block)
  let input_tie_ids = self.validate_instruction(inputs, outputs, [], metadata)
  self.commit_instruction(
    block,
    inst,
    Body,
    inputs,
    outputs,
    [],
    clobbers,
    metadata,
    input_tie_ids,
  )
}

///|
pub fn[Inst] Builder::set_terminator(
  self : Builder[Inst],
  block : Block,
  inst : Inst,
  inputs : Array[Input],
  successors : Array[Edge],
  clobbers : Array[PhysicalReg],
  metadata : InstructionMetadata,
) -> Instruction raise VCodeBuildError {
  self.require_terminator_open(block)
  let input_tie_ids = self.validate_instruction(
    inputs,
    [],
    successors,
    metadata,
  )
  self.commit_instruction(
    block,
    inst,
    Terminator,
    inputs,
    [],
    successors,
    clobbers,
    metadata,
    input_tie_ids,
  ).0
}

///|
pub fn[Inst] Builder::finish(self : Builder[Inst]) -> Function[Inst] {
  self.function
}
