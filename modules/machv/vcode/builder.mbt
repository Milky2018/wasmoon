///|
pub struct Builder[Inst] {
  priv function : Function[Inst]
}

///|
pub fn[Inst] Builder::new(
  name : String,
  parameter_types : Array[ValueType],
) -> Builder[Inst] {
  { function: Function::new(name, Platform, parameter_types, []) }
}

///|
pub fn[Inst] Builder::new_with_results(
  name : String,
  parameter_types : Array[ValueType],
  result_types : Array[ValueType],
) -> Builder[Inst] {
  { function: Function::new(name, Platform, parameter_types, result_types) }
}

///|
pub fn[Inst] Builder::new_with_protocol(
  name : String,
  protocol : @semantic.CallProtocol,
  parameter_types : Array[ValueType],
  result_types : Array[ValueType],
) -> Builder[Inst] {
  { function: Function::new(name, protocol, parameter_types, result_types) }
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
fn[Inst] Builder::append_instruction(
  self : Builder[Inst],
  block : Block,
  inst : Inst,
  role : InstructionRole,
  inputs : Array[Input],
  outputs : Array[Output],
  successors : Array[Edge],
  clobbers : Array[PhysicalReg],
  metadata : InstructionMetadata,
) -> (Instruction, Array[Value]) raise VCodeBuildError {
  if !self.function.owns_block(block) {
    raise ForeignBlock(block~)
  }
  self.validate_inputs(inputs, metadata)
  for input in inputs {
    let expected = reg_class_for_value_type(
      self.function.value_type(input.value).unwrap(),
    )
    if input.constraint is Fixed(reg) && reg.class != expected {
      raise InvalidOperandConstraint
    }
    if input.preference is Some(preference) && preference.class != expected {
      raise InvalidOperandConstraint
    }
  }
  for output in outputs {
    match output.constraint {
      Fixed(reg) =>
        if reg.class != reg_class_for_value_type(output.ty) {
          raise InvalidOperandConstraint
        }
      TiedTo(tied_to) =>
        if tied_to < 0 ||
          tied_to >= inputs.length() ||
          self.function.value_type(inputs[tied_to].value) != Some(output.ty) {
          raise InvalidOperandConstraint
        }
      AnyLocation => raise InvalidOperandConstraint
      Any => ()
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
  for input in inputs {
    self.function.operands.push({
      value: input.value,
      role: Use,
      constraint: input.constraint,
      preference: input.preference,
      timing: input.timing,
      tie_id: -1,
    })
  }
  for index, output in outputs {
    let operand_index = inputs.length() + index
    let tie_id = match output.constraint {
      TiedTo(tied_to) => {
        self.function.operands[operand_start + tied_to].tie_id = operand_index
        operand_index
      }
      _ => -1
    }
    self.function.operands.push({
      value: results[index],
      role: Def,
      constraint: output.constraint,
      preference: None,
      timing: output.timing,
      tie_id,
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
    clobber_start,
    clobber_count: clobbers.length(),
    results,
    successors: successors.map(edge => edge.copy()),
    metadata: metadata.copy(),
  })
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
  if !self.function.owns_block(block) {
    raise ForeignBlock(block~)
  }
  if self.function.blocks[block.id].terminator is Some(_) {
    raise BlockAlreadyTerminated(block~)
  }
  let result = self.append_instruction(
    block,
    inst,
    Body,
    inputs,
    outputs,
    [],
    clobbers,
    metadata,
  )
  self.function.blocks[block.id].body.push(result.0)
  result
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
  if !self.function.owns_block(block) {
    raise ForeignBlock(block~)
  }
  if self.function.blocks[block.id].terminator is Some(_) {
    raise DuplicateTerminator(block~)
  }
  let result = self.append_instruction(
    block,
    inst,
    Terminator,
    inputs,
    [],
    successors,
    clobbers,
    metadata,
  )
  self.function.blocks[block.id].terminator = Some(result.0)
  result.0
}

///|
pub fn[Inst] Builder::finish(self : Builder[Inst]) -> Function[Inst] {
  self.function
}
