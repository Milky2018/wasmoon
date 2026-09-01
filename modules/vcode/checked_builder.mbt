///|
/// A production builder that establishes local VCode invariants before every
/// mutation. The permissive `Builder` remains available for external tools and
/// verifier negative tests; target selectors use this type so sealing does not
/// need to rediscover local facts by scanning the completed instruction list.
pub struct CheckedBuilder[Inst] {
  priv builder : Builder[Inst]
  priv stack_map_ids : Array[Bool]
  priv mut stack_map_count : Int
}

///|
pub fn[Inst] CheckedBuilder::new(
  name : String,
  parameter_types : Array[ValueType],
) -> CheckedBuilder[Inst] {
  CheckedBuilder::new_with_protocol(name, Platform, parameter_types, [])
}

///|
pub fn[Inst] CheckedBuilder::new_with_results(
  name : String,
  parameter_types : Array[ValueType],
  result_types : Array[ValueType],
) -> CheckedBuilder[Inst] {
  CheckedBuilder::new_with_protocol(
    name,
    Platform,
    parameter_types,
    result_types,
  )
}

///|
pub fn[Inst] CheckedBuilder::new_with_protocol(
  name : String,
  protocol : @semantic.CallProtocol,
  parameter_types : Array[ValueType],
  result_types : Array[ValueType],
) -> CheckedBuilder[Inst] {
  {
    builder: Builder::new_with_protocol(
      name, protocol, parameter_types, result_types,
    ),
    stack_map_ids: [],
    stack_map_count: 0,
  }
}

///|
pub fn[Inst] CheckedBuilder::entry_block(self : CheckedBuilder[Inst]) -> Block {
  self.builder.entry_block()
}

///|
pub fn[Inst] CheckedBuilder::parameter(
  self : CheckedBuilder[Inst],
  index : Int,
) -> Value raise VCodeBuildError {
  self.builder.parameter(index)
}

///|
pub fn[Inst] CheckedBuilder::create_block(
  self : CheckedBuilder[Inst],
  parameter_types : Array[ValueType],
) -> Block {
  self.builder.create_block(parameter_types)
}

///|
pub fn[Inst] CheckedBuilder::block_parameter(
  self : CheckedBuilder[Inst],
  block : Block,
  index : Int,
) -> Value raise VCodeBuildError {
  self.builder.block_parameter(block, index)
}

///|
fn[Inst] CheckedBuilder::validate_local_facts(
  self : CheckedBuilder[Inst],
  successors : Array[Edge],
  clobbers : Array[PhysicalReg],
  metadata : InstructionMetadata,
) -> Int? raise VCodeBuildError {
  let function = self.builder.function
  for index, reg in clobbers {
    for earlier in 0..<index {
      if clobbers[earlier] == reg {
        raise DuplicateClobber(reg~)
      }
    }
  }
  for edge in successors {
    let parameters = function.blocks[edge.target.id].parameters
    if edge.arguments.length() != parameters.length() {
      raise InvalidEdgeArity(block=edge.target)
    }
    for index, argument in edge.arguments {
      if function.values[argument.id].ty !=
        function.values[parameters[index].id].ty {
        raise EdgeClassMismatch(block=edge.target, index~)
      }
    }
  }
  if metadata.live_gc_roots.length() > 0 && metadata.safepoint is None {
    raise InvalidSafepointRoot(value=metadata.live_gc_roots[0])
  }
  for root in metadata.live_gc_roots {
    if function.values[root.id].ty != GcRef64 {
      raise InvalidSafepointRoot(value=root)
    }
  }
  match metadata.stack_map {
    Some(stack_map) => {
      if metadata.safepoint is None ||
        stack_map.id < 0 ||
        stack_map.argument_root_count < 0 ||
        (
          stack_map.id < self.stack_map_ids.length() &&
          self.stack_map_ids[stack_map.id]
        ) {
        raise InvalidStackMap
      }
      Some(stack_map.id)
    }
    None => None
  }
}

///|
fn[Inst] CheckedBuilder::record_stack_map(
  self : CheckedBuilder[Inst],
  stack_map_id : Int?,
) -> Unit {
  if stack_map_id is Some(id) {
    while self.stack_map_ids.length() <= id {
      self.stack_map_ids.push(false)
    }
    self.stack_map_ids[id] = true
    self.stack_map_count += 1
  }
}

///|
pub fn[Inst] CheckedBuilder::append_body(
  self : CheckedBuilder[Inst],
  block : Block,
  inst : Inst,
  inputs : Array[Input],
  outputs : Array[Output],
  clobbers : Array[PhysicalReg],
  metadata : InstructionMetadata,
) -> (Instruction, Array[Value]) raise VCodeBuildError {
  self.builder.require_body_open(block)
  let input_tie_ids = self.builder.validate_instruction(
    inputs,
    outputs,
    [],
    metadata,
  )
  let stack_map_id = self.validate_local_facts([], clobbers, metadata)
  let result = self.builder.commit_instruction(
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
  self.record_stack_map(stack_map_id)
  result
}

///|
pub fn[Inst] CheckedBuilder::set_terminator(
  self : CheckedBuilder[Inst],
  block : Block,
  inst : Inst,
  inputs : Array[Input],
  successors : Array[Edge],
  clobbers : Array[PhysicalReg],
  metadata : InstructionMetadata,
) -> Instruction raise VCodeBuildError {
  self.builder.require_terminator_open(block)
  let input_tie_ids = self.builder.validate_instruction(
    inputs,
    [],
    successors,
    metadata,
  )
  let stack_map_id = self.validate_local_facts(successors, clobbers, metadata)
  let instruction = self.builder.commit_instruction(
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
  self.record_stack_map(stack_map_id)
  instruction
}

///|
pub fn[Inst] CheckedBuilder::finish(
  self : CheckedBuilder[Inst],
) -> Function[Inst] raise VCodeBuildError {
  let function = self.builder.function
  for index, block in function.blocks {
    if block.terminator is None {
      raise MissingTerminator(block=Block::new(function.owner, index))
    }
  }
  if self.stack_map_count != self.stack_map_ids.length() {
    raise InvalidStackMap
  }
  function
}
