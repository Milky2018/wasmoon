///|
pub suberror VerifyError {
  MissingTerminator(block_id~ : Int)
  EmptyFunction
  UndefinedValue(value_id~ : Int)
  ForeignValue(value_id~ : Int)
  ForeignBlock(block_id~ : Int)
  ForeignInstruction(inst_id~ : Int)
  ForeignGlobalValue(global_value_id~ : Int)
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
priv struct InstructionPlacement {
  block_id : Int
  position : Int
}

///|
pub impl Show for VerifyError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
/// Construct a structured error for a consumer seam that cannot validate or
/// lower an otherwise well-formed MilkIR function.
pub fn VerifyError::unverifiable_instruction(message : String) -> VerifyError {
  UnverifiableInstruction(message~)
}

///|
pub fn Function::verify(self : Function) -> Unit raise VerifyError {
  if self.owner.val.construction_error is Some(error) {
    raise error
  }
  if self.blocks.is_empty() {
    raise EmptyFunction
  }
  for index, entry in self.global_values {
    let (global_value, data) = entry
    if !self.owns_global_value(global_value) || global_value.id != index {
      raise ForeignGlobalValue(global_value_id=global_value.id)
    }
    verify_global_value_data(data)
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
  if self.values.length() != self.next_value_id {
    raise UndefinedValue(value_id=self.next_value_id)
  }
  if self.instructions.length() != self.next_inst_id {
    raise ForeignInstruction(inst_id=self.next_inst_id)
  }
  for param_index, item in self.params {
    let (param, ty) = item
    verify_value_definition(self, param, ty, FunctionParameter(param_index))
  }
  let placements : Array[InstructionPlacement?] = Array::make(
    self.instructions.length(),
    None,
  )
  for block in self.blocks {
    for param_index, item in block.params {
      let (param, ty) = item
      verify_value_definition(
        self,
        param,
        ty,
        BlockParameter(block.id, param_index),
      )
    }
    for inst_index, inst in block.instructions {
      if !physical_equal(self.owner, inst.owner) {
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
      verify_instruction_operands(inst)
      if !self.owns_inst(inst) {
        raise ForeignInstruction(inst_id=inst.id)
      }
      if placements[inst.id] is Some(_) {
        raise DuplicateInstructionId(inst_id=inst.id)
      }
      placements[inst.id] = Some({ block_id: block.id, position: inst_index, })
      for result_index, result in inst.results {
        verify_value_definition(
          self,
          result,
          result.ty,
          InstructionResult(inst.id, result_index),
        )
      }
    }
    if block.terminator is Some(term) {
      require_owned_terminator_values(self, term)
    }
  }
  let dominance = CFG::build(self).compute_dominance()
  for block in self.blocks {
    for inst_index, inst in block.instructions {
      verify_inst(self, inst, placements, block.id, inst_index, dominance)
    }
    if block.terminator is Some(term) {
      verify_terminator(
        term,
        self,
        placements,
        blocks,
        self.results,
        block.id,
        block.instructions.length(),
        dominance,
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
  if !self.global_values.is_empty() {
    raise UnverifiableInstruction(
      message="context global values require a dialect adapter",
    )
  }
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
/// Verify generic MilkIR structure, require every extension and context global
/// to belong to the owning dialect, and apply that adapter's validators before
/// crossing its seam.
pub fn Function::verify_with_dialect_validator(
  self : Function,
  dialect : String,
  validate_extension : (ExtensionInstView) -> String?,
  validate_global_value : (GlobalValueData) -> String?,
) -> Unit raise VerifyError {
  self.verify()
  for entry in self.global_values {
    if entry.1 is ContextField(field, _, _) {
      if field.dialect != dialect {
        raise UnverifiableInstruction(
          message="context field dialect '\{field.dialect}' is not owned by adapter '\{dialect}'",
        )
      }
      if validate_global_value(entry.1) is Some(message) {
        raise UnverifiableInstruction(message~)
      }
    }
  }
  for block in self.blocks {
    for inst in block.instructions {
      if inst.opcode is Ext(_, _) {
        let view = extension_inst_view(inst)
        if view.op.dialect != dialect {
          raise UnverifiableInstruction(
            message="extension dialect '\{view.op.dialect}' is not owned by adapter '\{dialect}'",
          )
        }
        if validate_extension(view) is Some(message) {
          raise UnverifiableInstruction(message~)
        }
      }
    }
  }
}

///|
fn verify_value_definition(
  func : Function,
  value : Value,
  declared_type : Type,
  expected : ValueDefinition,
) -> Unit raise VerifyError {
  require_owned_value(func, value)
  if value.id < 0 || value.id >= func.values.length() {
    raise UndefinedValue(value_id=value.id)
  }
  let data = func.values[value.id]
  if value.ty != declared_type || data.ty != declared_type {
    raise TypeMismatch(
      message="value \{value.id} has type \{value.ty}, but its declaration has type \{declared_type}",
    )
  }
  match data.definition {
    None => raise UndefinedValue(value_id=value.id)
    Some(actual) =>
      if actual != expected {
        raise DuplicateValueDefinition(value_id=value.id)
      }
  }
}

///|
fn verify_defined(
  value : Value,
  func : Function,
  placements : Array[InstructionPlacement?],
  use_block : Int,
  use_position : Int,
  dominance : Dominance,
) -> Unit raise VerifyError {
  require_owned_value(func, value)
  if value.id < 0 || value.id >= func.values.length() {
    raise UndefinedValue(value_id=value.id)
  }
  let data = func.values[value.id]
  match data.definition {
    None => raise UndefinedValue(value_id=value.id)
    Some(definition) => {
      if value.ty != data.ty {
        raise TypeMismatch(
          message="value \{value.id} has type \{value.ty}, but its definition has type \{data.ty}",
        )
      }
      match definition {
        FunctionParameter(_) => ()
        BlockParameter(defining_block, _) =>
          if defining_block != use_block &&
            !dominance.dominates(defining_block, use_block) {
            raise NonDominatingUse(
              value_id=value.id,
              defining_block~,
              use_block~,
            )
          }
        InstructionResult(inst_id, _) => {
          if inst_id < 0 || inst_id >= placements.length() {
            raise UndefinedValue(value_id=value.id)
          }
          guard placements[inst_id] is Some(placement) else {
            raise UndefinedValue(value_id=value.id)
          }
          if placement.block_id == use_block {
            if placement.position >= use_position {
              raise UseBeforeDefinition(value_id=value.id)
            }
          } else if !dominance.dominates(placement.block_id, use_block) {
            raise NonDominatingUse(
              value_id=value.id,
              defining_block=placement.block_id,
              use_block~,
            )
          }
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
  func : Function,
  placements : Array[InstructionPlacement?],
  edge : String,
  use_block : Int,
  use_position : Int,
  dominance : Dominance,
) -> Unit raise VerifyError {
  let block = require_block(block_id, blocks)
  for arg in args {
    verify_defined(arg, func, placements, use_block, use_position, dominance)
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
  placements : Array[InstructionPlacement?],
  use_block : Int,
  use_position : Int,
  dominance : Dominance,
) -> Unit raise VerifyError {
  for arg in inst.args {
    verify_defined(arg, func, placements, use_block, use_position, dominance)
  }
  verify_opcode_contract(func, inst)
}

///|
fn verify_global_value_data(data : GlobalValueData) -> Unit raise VerifyError {
  match data {
    ContextField(field, _, region) => {
      if field.dialect == "" {
        raise UnverifiableInstruction(
          message="context fields require a dialect name",
        )
      }
      if field.key < 0 {
        raise UnverifiableInstruction(
          message="context field keys must be non-negative",
        )
      }
      match region {
        Heap(index) | Table(index) =>
          if index < 0 {
            raise UnverifiableInstruction(
              message="context field alias-region indices must be non-negative",
            )
          }
        Context | Other => ()
      }
    }
  }
}

///|
fn extension_inst_view(inst : Inst) -> ExtensionInstView {
  let op = match inst.opcode {
    Ext(op, _) => op
    _ => abort("extension_inst_view requires an extension instruction")
  }
  {
    op,
    operand_types: ReadOnlyArray::makei(inst.args.length(), i => inst.args[i].ty),
    result_types: ReadOnlyArray::makei(inst.results.length(), i => {
      inst.results[i].ty
    }),
  }
}

///|
fn verify_terminator(
  term : Terminator,
  func : Function,
  placements : Array[InstructionPlacement?],
  blocks : Array[Block?],
  result_types : Array[Type],
  use_block : Int,
  use_position : Int,
  dominance : Dominance,
) -> Unit raise VerifyError {
  match term {
    Return(values) => {
      for value in values {
        verify_defined(
          value, func, placements, use_block, use_position, dominance,
        )
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
        target, values, blocks, func, placements, "jump", use_block, use_position,
        dominance,
      )
    Branch(cond, true_target, true_args, false_target, false_args) => {
      verify_defined(cond, func, placements, use_block, use_position, dominance)
      verify_i32(cond, "branch condition")
      verify_block_args(
        true_target, true_args, blocks, func, placements, "branch", use_block, use_position,
        dominance,
      )
      verify_block_args(
        false_target, false_args, blocks, func, placements, "branch", use_block,
        use_position, dominance,
      )
    }
    Brz(cond, true_target, false_target)
    | Brnz(cond, true_target, false_target) => {
      verify_defined(cond, func, placements, use_block, use_position, dominance)
      verify_i32(cond, "branch condition")
      verify_block_args(
        true_target,
        [],
        blocks,
        func,
        placements,
        "branch",
        use_block,
        use_position,
        dominance,
      )
      verify_block_args(
        false_target,
        [],
        blocks,
        func,
        placements,
        "branch",
        use_block,
        use_position,
        dominance,
      )
    }
    BrTable(index, targets, default_target) => {
      verify_defined(
        index, func, placements, use_block, use_position, dominance,
      )
      verify_i32(index, "branch table index")
      for target in targets {
        verify_block_args(
          target,
          [],
          blocks,
          func,
          placements,
          "branch table",
          use_block,
          use_position,
          dominance,
        )
      }
      verify_block_args(
        default_target,
        [],
        blocks,
        func,
        placements,
        "branch table",
        use_block,
        use_position,
        dominance,
      )
    }
    Trap(_) | TrapExit(_) => ()
  }
}
