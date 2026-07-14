///|
pub suberror VerifyError {
  MissingTerminator(block_id~ : Int)
  EmptyFunction
  UndefinedValue(value_id~ : Int)
  ForeignValue(value_id~ : Int)
  ForeignBlock(block_id~ : Int)
  ForeignInstruction(inst_id~ : Int)
  DuplicateBlockId(block_id~ : Int)
  DuplicateValueDefinition(value_id~ : Int)
  DuplicateInstructionId(inst_id~ : Int)
  UseBeforeDefinition(value_id~ : Int)
  NonDominatingUse(value_id~ : Int, defining_block~ : Int, use_block~ : Int)
  InstructionOperandMismatch(inst_id~ : Int)
  InvalidBlockTarget(block_id~ : Int)
  ArityMismatch(message~ : String)
  TypeMismatch(message~ : String)
  UnverifiableInstruction(message~ : String)
} derive(Debug, Eq)

///|
priv enum ValueDefinition {
  FunctionParameter(Type)
  BlockParameter(Type, Int)
  InstructionResult(Type, Int, Int)
}

///|
pub impl Show for VerifyError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
pub fn Function::verify(self : Function) -> Unit raise VerifyError {
  if self.owner.val.construction_error is Some(error) {
    raise error
  }
  if self.blocks.is_empty() {
    raise EmptyFunction
  }
  let mut max_block_id = -1
  for block in self.blocks {
    if !self.owns_block(block) {
      raise ForeignBlock(block_id=block.id)
    }
    if block.id < 0 {
      raise InvalidBlockTarget(block_id=block.id)
    }
    if block.id > max_block_id {
      max_block_id = block.id
    }
  }
  let blocks : Array[Block?] = Array::make(max_block_id + 1, None)
  for block in self.blocks {
    if blocks[block.id] is Some(_) {
      raise DuplicateBlockId(block_id=block.id)
    }
    blocks[block.id] = Some(block)
    if block.terminator is None {
      raise MissingTerminator(block_id=block.id)
    }
  }
  let definitions : @hashmap.HashMap[Int, ValueDefinition] = HashMap([])
  for item in self.params {
    let (param, ty) = item
    require_owned_value(self, param)
    record_definition(param, ty, FunctionParameter(ty), definitions)
  }
  let instruction_ids : @hashset.HashSet[Int] = HashSet([])
  for block in self.blocks {
    for item in block.params {
      let (param, ty) = item
      require_owned_value(self, param)
      record_definition(param, ty, BlockParameter(ty, block.id), definitions)
    }
    for inst_index, inst in block.instructions {
      if !self.owns_inst(inst) {
        raise ForeignInstruction(inst_id=inst.id)
      }
      for operand in inst.args {
        require_owned_value(self, operand)
      }
      for operand in inst.operands {
        require_owned_value(self, operand)
      }
      for result in inst.results {
        require_owned_value(self, result)
      }
      if instruction_ids.contains(inst.id) {
        raise DuplicateInstructionId(inst_id=inst.id)
      }
      instruction_ids.add(inst.id)
      verify_instruction_operands(inst)
      for result in inst.results {
        record_definition(
          result,
          result.ty,
          InstructionResult(result.ty, block.id, inst_index),
          definitions,
        )
      }
    }
    if block.terminator is Some(term) {
      require_owned_terminator_values(self, term)
    }
  }
  let idom = CFG::build(self).compute_dominators()
  for block in self.blocks {
    for inst_index, inst in block.instructions {
      verify_inst(self, inst, definitions, block.id, inst_index, idom)
    }
    if block.terminator is Some(term) {
      verify_terminator(
        term,
        definitions,
        blocks,
        self.results,
        block.id,
        block.instructions.length(),
        idom,
      )
    }
  }
}

///|
fn require_owned_value(
  func : Function,
  value : Value,
) -> Unit raise VerifyError {
  if !func.owns_value(value) {
    raise ForeignValue(value_id=value.id)
  }
}

///|
fn require_owned_values(
  func : Function,
  values : Array[Value],
) -> Unit raise VerifyError {
  for value in values {
    require_owned_value(func, value)
  }
}

///|
fn require_owned_terminator_values(
  func : Function,
  term : Terminator,
) -> Unit raise VerifyError {
  match term {
    Jump(_, values) | Return(values) => require_owned_values(func, values)
    Branch(cond, _, true_args, _, false_args) => {
      require_owned_value(func, cond)
      require_owned_values(func, true_args)
      require_owned_values(func, false_args)
    }
    Brz(cond, _, _) | Brnz(cond, _, _) | BrTable(cond, _, _) =>
      require_owned_value(func, cond)
    Trap(_) | TrapExit(_) => ()
  }
}

///|
/// Verify that a function is self-contained core MilkIR. Dialect-bearing
/// instructions must be validated and lowered by their owning adapter.
pub fn Function::verify_core(self : Function) -> Unit raise VerifyError {
  self.verify()
  for block in self.blocks {
    for inst in block.instructions {
      if inst.opcode is Ext(ext, _) {
        raise UnverifiableInstruction(
          message="unresolved dialect operation \{ext.dialect}.\{ext.opcode} is not core MilkIR",
        )
      }
    }
  }
}

///|
/// Verify the function and apply an owning adapter's validator to every
/// extension operation before crossing the adapter boundary.
pub fn Function::verify_with_extension_validator(
  self : Function,
  validate : (ExtOp) -> String?,
) -> Unit raise VerifyError {
  self.verify()
  for block in self.blocks {
    for inst in block.instructions {
      if inst.opcode is Ext(ext, _) {
        if validate(ext) is Some(message) {
          raise UnverifiableInstruction(message~)
        }
      }
    }
  }
}

///|
fn record_definition(
  value : Value,
  declared_type : Type,
  definition : ValueDefinition,
  definitions : @hashmap.HashMap[Int, ValueDefinition],
) -> Unit raise VerifyError {
  if value.ty != declared_type {
    raise TypeMismatch(
      message="value \{value.id} has type \{value.ty}, but its declaration has type \{declared_type}",
    )
  }
  if definitions.get(value.id) is Some(_) {
    raise DuplicateValueDefinition(value_id=value.id)
  }
  definitions.set(value.id, definition)
}

///|
fn definition_type(definition : ValueDefinition) -> Type {
  match definition {
    FunctionParameter(ty)
    | BlockParameter(ty, _)
    | InstructionResult(ty, _, _) => ty
  }
}

///|
fn verify_defined(
  value : Value,
  definitions : @hashmap.HashMap[Int, ValueDefinition],
  use_block : Int,
  use_position : Int,
  idom : Array[Int],
) -> Unit raise VerifyError {
  match definitions.get(value.id) {
    None => raise UndefinedValue(value_id=value.id)
    Some(definition) => {
      let defined_type = definition_type(definition)
      if value.ty != defined_type {
        raise TypeMismatch(
          message="value \{value.id} has type \{value.ty}, but its definition has type \{defined_type}",
        )
      }
      match definition {
        FunctionParameter(_) => ()
        BlockParameter(_, defining_block) =>
          if defining_block != use_block &&
            !dominates_with_idom(idom, defining_block, use_block) {
            raise NonDominatingUse(
              value_id=value.id,
              defining_block~,
              use_block~,
            )
          }
        InstructionResult(_, defining_block, defining_position) =>
          if defining_block == use_block {
            if defining_position >= use_position {
              raise UseBeforeDefinition(value_id=value.id)
            }
          } else if !dominates_with_idom(idom, defining_block, use_block) {
            raise NonDominatingUse(
              value_id=value.id,
              defining_block~,
              use_block~,
            )
          }
      }
    }
  }
}

///|
fn verify_instruction_operands(inst : Inst) -> Unit raise VerifyError {
  if inst.args.length() != inst.operands.length() {
    raise InstructionOperandMismatch(inst_id=inst.id)
  }
  for i in 0..<inst.args.length() {
    if inst.args[i] != inst.operands[i] {
      raise InstructionOperandMismatch(inst_id=inst.id)
    }
  }
}

///|
fn require_arity(
  actual : Int,
  expected : Int,
  context : String,
) -> Unit raise VerifyError {
  if actual != expected {
    raise ArityMismatch(
      message="\{context} expects \{expected} operands, got \{actual}",
    )
  }
}

///|
fn require_same_type(
  a : Value,
  b : Value,
  context : String,
) -> Unit raise VerifyError {
  if a.ty != b.ty {
    raise TypeMismatch(message="\{context} operands have mismatched types")
  }
}

///|
fn require_block(
  block_id : Int,
  blocks : Array[Block?],
) -> Block raise VerifyError {
  if block_id < 0 || block_id >= blocks.length() {
    raise InvalidBlockTarget(block_id~)
  }
  match blocks[block_id] {
    Some(block) => block
    None => raise InvalidBlockTarget(block_id~)
  }
}

///|
fn verify_block_args(
  block_id : Int,
  args : Array[Value],
  blocks : Array[Block?],
  definitions : @hashmap.HashMap[Int, ValueDefinition],
  edge : String,
  use_block : Int,
  use_position : Int,
  idom : Array[Int],
) -> Unit raise VerifyError {
  let block = require_block(block_id, blocks)
  for arg in args {
    verify_defined(arg, definitions, use_block, use_position, idom)
  }
  if args.length() != block.params.length() {
    raise ArityMismatch(
      message="\{edge} to block \{block_id} expects \{block.params.length()} arguments, got \{args.length()}",
    )
  }
  for i, arg in args {
    let (_, expected_type) = block.params[i]
    if arg.ty != expected_type {
      raise TypeMismatch(
        message="\{edge} to block \{block_id} argument \{i} has type \{arg.ty}, expected \{expected_type}",
      )
    }
  }
}

///|
fn verify_i32(value : Value, context : String) -> Unit raise VerifyError {
  if value.ty != I32 {
    raise TypeMismatch(message="\{context} must be i32, got \{value.ty}")
  }
}

///|
fn verify_inst(
  func : Function,
  inst : Inst,
  definitions : @hashmap.HashMap[Int, ValueDefinition],
  use_block : Int,
  use_position : Int,
  idom : Array[Int],
) -> Unit raise VerifyError {
  for arg in inst.args {
    verify_defined(arg, definitions, use_block, use_position, idom)
  }
  verify_opcode_contract(inst)
  if inst.opcode is Ext(ext, _) {
    verify_extension(func, ext)
  }
}

///|
fn verify_extension(func : Function, ext : ExtOp) -> Unit raise VerifyError {
  for registered in func.extension_validators {
    if registered.dialect == ext.dialect {
      if (registered.validate)(ext) is Some(message) {
        raise UnverifiableInstruction(message~)
      }
      return
    }
  }
  raise UnverifiableInstruction(
    message="extension dialect '\{ext.dialect}' has no registered validator",
  )
}

///|
fn verify_terminator(
  term : Terminator,
  definitions : @hashmap.HashMap[Int, ValueDefinition],
  blocks : Array[Block?],
  result_types : Array[Type],
  use_block : Int,
  use_position : Int,
  idom : Array[Int],
) -> Unit raise VerifyError {
  match term {
    Return(values) => {
      for value in values {
        verify_defined(value, definitions, use_block, use_position, idom)
      }
      if values.length() != result_types.length() {
        raise ArityMismatch(
          message="return expects \{result_types.length()} values, got \{values.length()}",
        )
      }
      for i, value in values {
        let expected_type = result_types[i]
        if value.ty != expected_type {
          raise TypeMismatch(
            message="return value \{i} has type \{value.ty}, expected \{expected_type}",
          )
        }
      }
    }
    Jump(target, values) =>
      verify_block_args(
        target, values, blocks, definitions, "jump", use_block, use_position, idom,
      )
    Branch(cond, true_target, true_args, false_target, false_args) => {
      verify_defined(cond, definitions, use_block, use_position, idom)
      verify_i32(cond, "branch condition")
      verify_block_args(
        true_target, true_args, blocks, definitions, "branch", use_block, use_position,
        idom,
      )
      verify_block_args(
        false_target, false_args, blocks, definitions, "branch", use_block, use_position,
        idom,
      )
    }
    Brz(cond, true_target, false_target)
    | Brnz(cond, true_target, false_target) => {
      verify_defined(cond, definitions, use_block, use_position, idom)
      verify_i32(cond, "branch condition")
      verify_block_args(
        true_target,
        [],
        blocks,
        definitions,
        "branch",
        use_block,
        use_position,
        idom,
      )
      verify_block_args(
        false_target,
        [],
        blocks,
        definitions,
        "branch",
        use_block,
        use_position,
        idom,
      )
    }
    BrTable(index, targets, default_target) => {
      verify_defined(index, definitions, use_block, use_position, idom)
      verify_i32(index, "branch table index")
      for target in targets {
        verify_block_args(
          target,
          [],
          blocks,
          definitions,
          "branch table",
          use_block,
          use_position,
          idom,
        )
      }
      verify_block_args(
        default_target,
        [],
        blocks,
        definitions,
        "branch table",
        use_block,
        use_position,
        idom,
      )
    }
    Trap(_) | TrapExit(_) => ()
  }
}
