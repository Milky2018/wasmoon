///|
suberror SemanticLegacyAdapterError {
  MissingValue(value_id~ : Int)
  UnsupportedOperation(message~ : String)
  InvalidLegacyFunction(message~ : String)
} derive(Debug, Eq)

///|
impl Show for SemanticLegacyAdapterError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
fn legacy_reg_class(ty : @semantic.ValueType) -> @abi.RegClass {
  match ty {
    I32 | I64 | Ptr64 | GcRef64 => Int
    F32 => Float32
    F64 => Float64
    V128 => Vector
  }
}

///|
fn legacy_value_kind(ty : @semantic.ValueType) -> @machv.ValueKind {
  match ty {
    I32 => I32
    I64 => I64
    F32 => F32
    F64 => F64
    V128 => V128
    Ptr64 | GcRef64 => Ptr
  }
}

///|
fn legacy_use(value : @abi.VReg) -> @abi.Reg {
  Virtual(value)
}

///|
fn legacy_def(value : @abi.VReg) -> @abi.Writable {
  { reg: Virtual(value) }
}

///|
fn require_legacy_value(
  function : @semantic.Function,
  values : Array[@abi.VReg?],
  value : @semantic.Value,
) -> @abi.VReg raise SemanticLegacyAdapterError {
  match function.value_index(value) {
    Some(index) =>
      match values[index] {
        Some(mapped) => mapped
        None => raise MissingValue(value_id=index)
      }
    None => raise MissingValue(value_id=-1)
  }
}

///|
fn semantic_integer_width(
  function : @semantic.Function,
  results : Array[@semantic.Value],
) -> Bool raise SemanticLegacyAdapterError {
  if results.length() != 1 {
    raise UnsupportedOperation(
      message="integer operation must have exactly one result",
    )
  }
  match function.value_type(results[0]) {
    Some(I32) => false
    Some(I64 | Ptr64 | GcRef64) => true
    Some(ty) =>
      raise UnsupportedOperation(
        message="integer operation has non-integer result type \{ty}",
      )
    None =>
      raise UnsupportedOperation(message="integer result is not function-owned")
  }
}

///|
fn lower_semantic_int_binary(
  function : @semantic.Function,
  operation : @semantic.IntBinaryOp,
  results : Array[@semantic.Value],
) -> @instr.Opcode raise SemanticLegacyAdapterError {
  let is_64 = semantic_integer_width(function, results)
  match operation {
    Add => Add(is_64)
    Sub => Sub(is_64)
    Mul => Mul(is_64)
    SignedDiv => SDiv(is_64)
    UnsignedDiv => UDiv(is_64)
    SignedRem => SRem(is_64)
    UnsignedRem => URem(is_64)
    And => And(is_64)
    Or => Or(is_64)
    Xor => Xor(is_64)
    ShiftLeft => Shl(is_64)
    SignedShiftRight => AShr(is_64)
    UnsignedShiftRight => LShr(is_64)
    RotateRight => Rotr(is_64)
    RotateLeft =>
      raise UnsupportedOperation(
        message="rotate-left requires target-aware legalization",
      )
  }
}

///|
fn append_semantic_instruction(
  function : @semantic.Function,
  legacy_block : @block.Block,
  instruction : @semantic.Instruction,
  values : Array[@abi.VReg?],
  legacy_function : @machv.Function,
) -> Unit raise SemanticLegacyAdapterError {
  let operands : Array[@abi.Reg] = []
  for operand in function.instruction_operands(instruction) {
    operands.push(legacy_use(require_legacy_value(function, values, operand)))
  }
  let semantic_results = function.instruction_results(instruction)
  let definitions : Array[@abi.Writable] = []
  for result in semantic_results {
    let index = function.value_index(result).unwrap()
    let ty = function.value_type(result).unwrap()
    let mapped = legacy_function.new_vreg(legacy_reg_class(ty))
    values[index] = Some(mapped)
    definitions.push(legacy_def(mapped))
  }
  let operation = function.instruction_operation(instruction).unwrap()
  let opcode = match operation {
    I32Const(bits) =>
      @instr.LoadConst(bits.reinterpret_as_int().to_int64() & 0xFFFFFFFFL)
    I64Const(bits) => LoadConst(bits.reinterpret_as_int64())
    Copy => Move
    IntBinary(binary) =>
      lower_semantic_int_binary(function, binary, semantic_results)
    _ =>
      raise UnsupportedOperation(
        message="semantic operation is not yet adapted: \{to_repr(operation)}",
      )
  }
  let legacy_instruction = @instr.Inst(opcode)
  for operand in operands {
    legacy_instruction.add_use(operand)
  }
  for definition in definitions {
    legacy_instruction.add_def(definition)
  }
  legacy_block.add_inst(legacy_instruction)
}

///|
fn legacy_edge_arguments(
  function : @semantic.Function,
  values : Array[@abi.VReg?],
  edge : @semantic.Edge,
) -> Array[@abi.Reg] raise SemanticLegacyAdapterError {
  edge.arguments.map(argument => {
    legacy_use(require_legacy_value(function, values, argument))
  })
}

///|
fn branch_edge_target(
  function : @semantic.Function,
  values : Array[@abi.VReg?],
  edge : @semantic.Edge,
  block_ids : Array[Int],
  legacy_function : @machv.Function,
) -> Int raise SemanticLegacyAdapterError {
  let target_index = function.block_index(edge.target).unwrap()
  let target = block_ids[target_index]
  if edge.arguments.is_empty() {
    return target
  }
  let forwarding = legacy_function.new_block()
  forwarding.set_terminator(
    Jump(target, legacy_edge_arguments(function, values, edge)),
  )
  forwarding.id
}

///|
fn set_semantic_terminator(
  function : @semantic.Function,
  semantic_block : @semantic.Block,
  legacy_block : @block.Block,
  values : Array[@abi.VReg?],
  block_ids : Array[Int],
  legacy_function : @machv.Function,
  trap_payload : (@semantic.TrapReason) -> Int,
) -> Unit raise SemanticLegacyAdapterError {
  let record = function.block_terminator(semantic_block).unwrap()
  let terminator = match record.kind {
    Jump(edge) =>
      @instr.Jump(
        block_ids[function.block_index(edge.target).unwrap()],
        legacy_edge_arguments(function, values, edge),
      )
    Branch(condition, true_edge, false_edge) =>
      Branch(
        legacy_use(require_legacy_value(function, values, condition)),
        branch_edge_target(
          function, values, true_edge, block_ids, legacy_function,
        ),
        branch_edge_target(
          function, values, false_edge, block_ids, legacy_function,
        ),
      )
    Return(results) =>
      Return(
        results.map(result => {
          legacy_use(require_legacy_value(function, values, result))
        }),
      )
    Trap(reason) => Trap(trap_payload(reason))
    _ =>
      raise UnsupportedOperation(
        message="semantic terminator is not yet adapted: \{to_repr(record.kind)}",
      )
  }
  legacy_block.set_terminator(terminator)
}

///|
fn adapt_semantic_to_legacy(
  function : @semantic.Function,
  isa : @isa.ISA,
  trap_payload? : (@semantic.TrapReason) -> Int = fn(_) { 0 },
) -> @machv.Function raise SemanticLegacyAdapterError {
  function.verify() catch {
    error => raise InvalidLegacyFunction(message=error.to_string())
  }
  let legacy = @machv.Function(function.name())
  let values : Array[@abi.VReg?] = Array::make(function.value_count(), None)
  for parameter in function.parameters() {
    let index = function.value_index(parameter).unwrap()
    let ty = function.value_type(parameter).unwrap()
    values[index] = Some(legacy.add_param(legacy_reg_class(ty)))
  }
  for result in function.signature().results {
    legacy.add_result_kind(legacy_value_kind(result))
  }
  let semantic_blocks = function.blocks()
  let block_ids : Array[Int] = []
  for block in semantic_blocks {
    let legacy_block = legacy.new_block()
    block_ids.push(legacy_block.id)
    for parameter in function.block_parameters(block) {
      let index = function.value_index(parameter).unwrap()
      let ty = function.value_type(parameter).unwrap()
      let mapped = legacy.new_vreg(legacy_reg_class(ty))
      values[index] = Some(mapped)
      legacy_block.params.push(mapped)
    }
  }
  for block in semantic_blocks {
    let block_index = function.block_index(block).unwrap()
    let legacy_block = legacy.get_blocks()[block_ids[block_index]]
    for instruction in function.block_instructions(block) {
      append_semantic_instruction(
        function, legacy_block, instruction, values, legacy,
      )
    }
    set_semantic_terminator(
      function, block, legacy_block, values, block_ids, legacy, trap_payload,
    )
  }
  legacy.verify_for_isa(isa) catch {
    error => raise InvalidLegacyFunction(message=error.to_string())
  }
  legacy
}

///|
test "semantic-to-legacy adapter lowers scalar SSA directly" {
  let builder = @semantic.FunctionBuilder::new(
    "semantic_adapter_add",
    Internal,
    [I64, I64],
    [I64],
  )
  let parameters = builder.parameters()
  let sum = builder.emit(IntBinary(Add), parameters, [I64])[0]
  builder.return_([sum])
  inspect(
    adapt_semantic_to_legacy(builder.finish(), AMD64),
    content=(
      #|machv semantic_adapter_add(v0:int, v1:int) -> int {
      #|block0:
      #|    v2 = add v0, v1
      #|    ret v2
      #|}
      #|
    ),
  )
}

///|
test "semantic-to-legacy adapter preserves conditional edge arguments" {
  let builder = @semantic.FunctionBuilder::new(
    "semantic_adapter_branch",
    Internal,
    [I32, I64, I64],
    [I64],
  )
  let parameters = builder.parameters()
  let true_block = builder.create_block([I64])
  let false_block = builder.create_block([I64])
  builder.branch(parameters[0], true_block, [parameters[1]], false_block, [
    parameters[2],
  ])
  builder.switch_to_block(true_block)
  builder.return_([builder.block_parameters(true_block)[0]])
  builder.switch_to_block(false_block)
  builder.return_([builder.block_parameters(false_block)[0]])
  inspect(
    adapt_semantic_to_legacy(builder.finish(), AMD64),
    content=(
      #|machv semantic_adapter_branch(v0:int, v1:int, v2:int) -> int {
      #|block0:
      #|    branch v0, block3, block4
      #|block1(v3:int):
      #|    ret v3
      #|block2(v4:int):
      #|    ret v4
      #|block3:
      #|    jump block1 (v1)
      #|block4:
      #|    jump block2 (v2)
      #|}
      #|
    ),
  )
}
