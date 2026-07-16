///|
pub suberror SemanticLowerError {
  InvalidMilkIR(message~ : String)
  UnsupportedOperation(
    block_id~ : Int,
    instruction_id~ : Int,
    message~ : String
  )
  MissingValue(value_id~ : Int)
  MissingBlock(block_id~ : Int)
  InvalidMachV(message~ : String)
} derive(Debug, Eq)

///|
pub impl Show for SemanticLowerError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
priv struct DialectLowering {
  name : String
  environment_parameters : Array[(Int, @semantic.ValueType)]
  lower : (@adapter.InstructionContext, @milkir.ExtOp) -> String?
}

///|
fn lower_type(ty : @milkir.Type) -> @semantic.ValueType {
  match ty {
    I32 => I32
    I64 => I64
    F32 => F32
    F64 => F64
    V128 => V128
    Ptr => Ptr64
    Ref | CallableRef | OpaqueRef => GcRef64
  }
}

///|
fn lower_integer_type(
  ty : @milkir.Type,
) -> @semantic.IntegerType raise SemanticLowerError {
  match ty {
    I32 => I32
    I64 => I64
    _ =>
      raise InvalidMilkIR(message="expected a verified integer type, got \{ty}")
  }
}

///|
fn lower_float_type(
  ty : @milkir.Type,
) -> @semantic.FloatType raise SemanticLowerError {
  match ty {
    F32 => F32
    F64 => F64
    _ =>
      raise InvalidMilkIR(message="expected a verified float type, got \{ty}")
  }
}

///|
fn lower_int_binary(op : @milkir.IntBinaryOp) -> @semantic.Operation {
  match op {
    Add => IntBinary(Add)
    Sub => IntBinary(Sub)
    Mul => IntBinary(Mul)
    SignedDiv => IntBinary(SignedDiv)
    UnsignedDiv => IntBinary(UnsignedDiv)
    SignedRem => IntBinary(SignedRem)
    UnsignedRem => IntBinary(UnsignedRem)
    And => IntBinary(And)
    Or => IntBinary(Or)
    Xor => IntBinary(Xor)
    ShiftLeft => IntBinary(ShiftLeft)
    SignedShiftRight => IntBinary(SignedShiftRight)
    UnsignedShiftRight => IntBinary(UnsignedShiftRight)
    RotateLeft => IntBinary(RotateLeft)
    RotateRight => IntBinary(RotateRight)
    SignedMulHigh => IntHighMultiply(Signed)
    UnsignedMulHigh => IntHighMultiply(Unsigned)
  }
}

///|
fn lower_int_unary(op : @milkir.IntUnaryOp) -> @semantic.IntUnaryOp {
  match op {
    Not => Not
    CountLeadingZeros => CountLeadingZeros
    CountTrailingZeros => CountTrailingZeros
    PopulationCount => PopulationCount
  }
}

///|
fn lower_int_comparison(op : @milkir.IntCC) -> @semantic.IntComparison {
  match op {
    Eq => Equal
    Ne => NotEqual
    Slt => SignedLessThan
    Sle => SignedLessOrEqual
    Sgt => SignedGreaterThan
    Sge => SignedGreaterOrEqual
    Ult => UnsignedLessThan
    Ule => UnsignedLessOrEqual
    Ugt => UnsignedGreaterThan
    Uge => UnsignedGreaterOrEqual
  }
}

///|
fn lower_float_binary(op : @milkir.FloatBinaryOp) -> @semantic.FloatBinaryOp {
  match op {
    Add => Add
    Sub => Sub
    Mul => Mul
    Div => Div
    Min => Min
    Max => Max
  }
}

///|
fn lower_float_unary(op : @milkir.FloatUnaryOp) -> @semantic.FloatUnaryOp {
  match op {
    Neg => Negate
    Abs => Absolute
    Sqrt => SquareRoot
    Ceil => Ceil
    Floor => Floor
    Trunc => Truncate
    Nearest => Nearest
  }
}

///|
fn lower_float_comparison(op : @milkir.FloatCC) -> @semantic.FloatComparison {
  match op {
    Eq => Equal
    Ne => NotEqual
    Lt => LessThan
    Le => LessOrEqual
    Gt => GreaterThan
    Ge => GreaterOrEqual
  }
}

///|
fn lower_width(bits : Int) -> @semantic.AccessWidth? {
  match bits {
    8 => Some(W8)
    16 => Some(W16)
    32 => Some(W32)
    64 => Some(W64)
    128 => Some(W128)
    _ => None
  }
}

///|
fn lower_conversion(
  conversion : @milkir.ConversionOp,
  source : @milkir.Type,
  result : @milkir.Type,
) -> @semantic.ConversionOp raise SemanticLowerError {
  match conversion {
    IntReduce => I32WrapI64
    SignedExtend => I64ExtendI32(Signed)
    UnsignedExtend => I64ExtendI32(Unsigned)
    FloatPromote => F64PromoteF32
    FloatDemote => F32DemoteF64
    FloatToSignedInt =>
      FloatToInt(
        lower_float_type(source),
        lower_integer_type(result),
        Signed,
        Trapping,
      )
    FloatToUnsignedInt =>
      FloatToInt(
        lower_float_type(source),
        lower_integer_type(result),
        Unsigned,
        Trapping,
      )
    FloatToSignedIntSaturating =>
      FloatToInt(
        lower_float_type(source),
        lower_integer_type(result),
        Signed,
        Saturating,
      )
    FloatToUnsignedIntSaturating =>
      FloatToInt(
        lower_float_type(source),
        lower_integer_type(result),
        Unsigned,
        Saturating,
      )
    SignedIntToFloat =>
      IntToFloat(lower_integer_type(source), lower_float_type(result), Signed)
    UnsignedIntToFloat =>
      IntToFloat(lower_integer_type(source), lower_float_type(result), Unsigned)
    Bitcast => Bitcast(lower_type(source), lower_type(result))
  }
}

///|
fn mapped_value(
  values : Array[@semantic.Value?],
  value : @milkir.Value,
) -> @semantic.Value raise SemanticLowerError {
  if value.id < 0 || value.id >= values.length() {
    raise MissingValue(value_id=value.id)
  }
  match values[value.id] {
    Some(mapped) => mapped
    None => raise MissingValue(value_id=value.id)
  }
}

///|
fn mapped_values(
  values : Array[@semantic.Value?],
  source : Array[@milkir.Value],
) -> Array[@semantic.Value] raise SemanticLowerError {
  let result : Array[@semantic.Value] = []
  for value in source {
    result.push(mapped_value(values, value))
  }
  result
}

///|
fn mapped_block(
  blocks : Array[@semantic.Block?],
  block_id : Int,
) -> @semantic.Block raise SemanticLowerError {
  if block_id < 0 || block_id >= blocks.length() {
    raise MissingBlock(block_id~)
  }
  match blocks[block_id] {
    Some(block) => block
    None => raise MissingBlock(block_id~)
  }
}

///|
fn instruction_source(instruction : @milkir.Inst) -> @semantic.SourceLocation? {
  for metadata in instruction.metadata {
    if metadata is SourceLoc(source) {
      // MilkIR stores an opaque source label rather than structured
      // coordinates. Preserve that label verbatim and mark coordinates as
      // unknown until the producer carries a structured location.
      return Some(@semantic.SourceLocation::new(source, 0, 0))
    }
  }
  None
}

///|
fn instruction_metadata(
  instruction : @milkir.Inst,
  live_gc_roots : Array[@semantic.Value],
) -> @semantic.InstructionMetadata {
  @semantic.InstructionMetadata::new(
    instruction_source(instruction),
    live_gc_roots,
  )
}

///|
fn emit_one(
  builder : @semantic.FunctionBuilder,
  operation : @semantic.Operation,
  operands : Array[@semantic.Value],
  result_type : @semantic.ValueType,
  source : @semantic.SourceLocation?,
  instruction_id : Int,
) -> @semantic.Value raise SemanticLowerError {
  let results = builder.emit_with_metadata(
    operation,
    operands,
    [result_type],
    @semantic.InstructionMetadata::new(source, []),
  )
  if results.length() != 1 {
    raise InvalidMachV(
      message="instruction \{instruction_id} failed semantic MachV construction",
    )
  }
  results[0]
}

///|
fn lower_pointer_value(
  builder : @semantic.FunctionBuilder,
  values : Array[@semantic.Value?],
  source : @milkir.Value,
  location : @semantic.SourceLocation?,
  instruction_id : Int,
) -> @semantic.Value raise SemanticLowerError {
  let mapped = mapped_value(values, source)
  match source.ty {
    Ptr => mapped
    I64 =>
      emit_one(
        builder,
        Convert(Bitcast(I64, Ptr64)),
        [mapped],
        Ptr64,
        location,
        instruction_id,
      )
    _ =>
      raise InvalidMilkIR(
        message="memory address must be ptr or i64, got \{source.ty}",
      )
  }
}

///|
fn lower_address(
  builder : @semantic.FunctionBuilder,
  values : Array[@semantic.Value?],
  base : @milkir.Value,
  offset : @milkir.Value,
  source : @semantic.SourceLocation?,
  instruction_id : Int,
) -> @semantic.Value raise SemanticLowerError {
  let pointer = lower_pointer_value(
    builder, values, base, source, instruction_id,
  )
  emit_one(
    builder,
    PointerOffset,
    [pointer, mapped_value(values, offset)],
    Ptr64,
    source,
    instruction_id,
  )
}

///|
fn access_width_for_type(ty : @semantic.ValueType) -> @semantic.AccessWidth {
  match ty {
    I32 | F32 => W32
    I64 | F64 | Ptr64 | GcRef64 => W64
    V128 => W128
  }
}

///|
fn assign_instruction_results(
  values : Array[@semantic.Value?],
  instruction : @milkir.Inst,
  lowered_results : Array[@semantic.Value],
) -> Unit raise SemanticLowerError {
  if lowered_results.length() != instruction.results.length() {
    raise InvalidMachV(
      message="instruction \{instruction.id} failed semantic MachV construction",
    )
  }
  for index, result in instruction.results {
    values[result.id] = Some(lowered_results[index])
  }
}

///|
fn lower_memory_instruction(
  builder : @semantic.FunctionBuilder,
  values : Array[@semantic.Value?],
  instruction : @milkir.Inst,
  memory : @milkir.MemoryOp,
) -> Unit raise SemanticLowerError {
  let source = instruction_source(instruction)
  let results = match memory {
    Load(result_type) => {
      let lowered_type = lower_type(result_type)
      let address = lower_address(
        builder,
        values,
        instruction.args[0],
        instruction.args[1],
        source,
        instruction.id,
      )
      builder.emit_with_metadata(
        Load(
          @semantic.LoadSpec::new(
            access_width_for_type(lowered_type),
            None,
            lowered_type,
            0UL,
            Little,
            None,
          ),
        ),
        [address],
        [lowered_type],
        instruction_metadata(instruction, []),
      )
    }
    Store(value_type) => {
      let lowered_type = lower_type(value_type)
      let address = lower_address(
        builder,
        values,
        instruction.args[0],
        instruction.args[2],
        source,
        instruction.id,
      )
      builder.emit_with_metadata(
        Store(
          @semantic.StoreSpec::new(
            access_width_for_type(lowered_type),
            lowered_type,
            0UL,
            Little,
            None,
          ),
        ),
        [address, mapped_value(values, instruction.args[1])],
        [],
        instruction_metadata(instruction, []),
      )
    }
    LoadNarrow(result_type, bits, signed) => {
      let width = match lower_width(bits) {
        Some(width) => width
        None =>
          raise InvalidMilkIR(
            message="invalid verified narrow load width \{bits}",
          )
      }
      let lowered_type = lower_type(result_type)
      let address = lower_address(
        builder,
        values,
        instruction.args[0],
        instruction.args[1],
        source,
        instruction.id,
      )
      builder.emit_with_metadata(
        Load(
          @semantic.LoadSpec::new(
            width,
            if signed {
              Signed
            } else {
              Unsigned
            },
            lowered_type,
            0UL,
            Little,
            None,
          ),
        ),
        [address],
        [lowered_type],
        instruction_metadata(instruction, []),
      )
    }
    StoreNarrow(bits) => {
      let width = match lower_width(bits) {
        Some(width) => width
        None =>
          raise InvalidMilkIR(
            message="invalid verified narrow store width \{bits}",
          )
      }
      let value_type = lower_type(instruction.args[1].ty)
      let address = lower_address(
        builder,
        values,
        instruction.args[0],
        instruction.args[2],
        source,
        instruction.id,
      )
      builder.emit_with_metadata(
        Store(@semantic.StoreSpec::new(width, value_type, 0UL, Little, None)),
        [address, mapped_value(values, instruction.args[1])],
        [],
        instruction_metadata(instruction, []),
      )
    }
    Vector(_) =>
      raise UnsupportedOperation(
        block_id=-1,
        instruction_id=instruction.id,
        message="vector memory lowering is not in the scalar memory slice",
      )
  }
  assign_instruction_results(values, instruction, results)
}

///|
fn lower_signature(signature : @milkir.Signature) -> @semantic.Signature {
  @semantic.Signature::new(
    signature.params.map(lower_type),
    signature.results.map(lower_type),
  )
}

///|
fn is_gc_reference_type(ty : @milkir.Type) -> Bool {
  match ty {
    Ref | CallableRef | OpaqueRef => true
    I32 | I64 | F32 | F64 | V128 | Ptr => false
  }
}

///|
fn clone_int_set(source : @hashset.HashSet[Int]) -> @hashset.HashSet[Int] {
  let result : @hashset.HashSet[Int] = HashSet([])
  for value in source {
    result.add(value)
  }
  result
}

///|
fn int_sets_equal(
  left : @hashset.HashSet[Int],
  right : @hashset.HashSet[Int],
) -> Bool {
  for value in left {
    if !right.contains(value) {
      return false
    }
  }
  for value in right {
    if !left.contains(value) {
      return false
    }
  }
  true
}

///|
fn add_gc_use(
  value : @milkir.Value,
  definitions : @hashset.HashSet[Int],
  uses : @hashset.HashSet[Int],
) -> Unit {
  if is_gc_reference_type(value.ty) && !definitions.contains(value.id) {
    uses.add(value.id)
  }
}

///|
fn terminator_values(terminator : @milkir.Terminator) -> Array[@milkir.Value] {
  match terminator {
    Jump(_, arguments) => arguments.copy()
    Branch(condition, _, true_arguments, _, false_arguments) => {
      let values = [condition]
      values.append(true_arguments)
      values.append(false_arguments)
      values
    }
    Brz(condition, _, _) | Brnz(condition, _, _) | BrTable(condition, _, _) =>
      [condition]
    Return(values) => values.copy()
    Trap(_) | TrapExit(_) => []
  }
}

///|
fn compute_gc_roots(
  function : @milkir.Function,
  cfg : @milkir.CFG,
) -> Array[Array[Int]] {
  let block_uses : Array[@hashset.HashSet[Int]] = []
  let block_definitions : Array[@hashset.HashSet[Int]] = []
  for block_index, block in function.blocks {
    let definitions : @hashset.HashSet[Int] = HashSet([])
    let uses : @hashset.HashSet[Int] = HashSet([])
    if block_index == 0 {
      for parameter in function.params {
        if is_gc_reference_type(parameter.1) {
          definitions.add(parameter.0.id)
        }
      }
    }
    for parameter in block.params {
      if is_gc_reference_type(parameter.1) {
        definitions.add(parameter.0.id)
      }
    }
    for instruction in block.instructions {
      for operand in instruction.args {
        add_gc_use(operand, definitions, uses)
      }
      for result in instruction.results {
        if is_gc_reference_type(result.ty) {
          definitions.add(result.id)
        }
      }
    }
    if block.terminator is Some(terminator) {
      for value in terminator_values(terminator) {
        add_gc_use(value, definitions, uses)
      }
    }
    block_uses.push(uses)
    block_definitions.push(definitions)
  }
  let live_in : Array[@hashset.HashSet[Int]] = []
  let live_out : Array[@hashset.HashSet[Int]] = []
  for _ in function.blocks {
    live_in.push(HashSet([]))
    live_out.push(HashSet([]))
  }
  let worklist : Array[Int] = []
  let queued = Array::make(function.blocks.length(), true)
  let mut block_index = function.blocks.length() - 1
  while block_index >= 0 {
    worklist.push(function.blocks[block_index].id)
    block_index -= 1
  }
  let mut cursor = 0
  while cursor < worklist.length() {
    let block_id = worklist[cursor]
    cursor += 1
    queued[block_id] = false
    let output : @hashset.HashSet[Int] = HashSet([])
    for successor in cfg.get_successors(block_id) {
      for value in live_in[successor] {
        output.add(value)
      }
    }
    let input = clone_int_set(block_uses[block_id])
    for value in output {
      if !block_definitions[block_id].contains(value) {
        input.add(value)
      }
    }
    let changed = !int_sets_equal(input, live_in[block_id])
    live_in[block_id] = input
    live_out[block_id] = output
    if changed {
      for predecessor in cfg.get_predecessors(block_id) {
        if !queued[predecessor] {
          worklist.push(predecessor)
          queued[predecessor] = true
        }
      }
    }
  }
  let roots = Array::makei(function.next_inst_id, _ => [])
  for block in function.blocks {
    let live = clone_int_set(live_out[block.id])
    if block.terminator is Some(terminator) {
      for value in terminator_values(terminator) {
        if is_gc_reference_type(value.ty) {
          live.add(value.id)
        }
      }
    }
    let mut position = block.instructions.length() - 1
    while position >= 0 {
      let instruction = block.instructions[position]
      for result in instruction.results {
        if is_gc_reference_type(result.ty) {
          live.remove(result.id)
        }
      }
      for operand in instruction.args {
        if is_gc_reference_type(operand.ty) {
          live.add(operand.id)
        }
      }
      let instruction_roots : Array[Int] = []
      for value in live {
        instruction_roots.push(value)
      }
      instruction_roots.sort()
      roots[instruction.id] = instruction_roots
      position -= 1
    }
  }
  roots
}

///|
fn lower_call_instruction(
  builder : @semantic.FunctionBuilder,
  values : Array[@semantic.Value?],
  instruction : @milkir.Inst,
  call : @milkir.CallOp,
  root_ids : Array[Int],
) -> Unit raise SemanticLowerError {
  let (semantic_call, operands) = match call {
    Direct(symbol, signature) =>
      (
        @semantic.SemanticCall::new(
          External(@semantic.ExternalSymbol::new(symbol.name)),
          lower_signature(signature),
          Platform,
          @semantic.CallBehavior::conservative(),
        ),
        mapped_values(values, instruction.args),
      )
    Pointer(_, _) => {
      let parameter_types = instruction.args[1:].map(value => {
        lower_type(value.ty)
      })
      let result_types = instruction.results.map(value => lower_type(value.ty))
      let call_operands = [
        lower_pointer_value(
          builder,
          values,
          instruction.args[0],
          instruction_source(instruction),
          instruction.id,
        ),
      ]
      for argument in instruction.args[1:] {
        call_operands.push(mapped_value(values, argument))
      }
      (
        @semantic.SemanticCall::new(
          Indirect,
          @semantic.Signature::new(parameter_types, result_types),
          Internal,
          @semantic.CallBehavior::conservative(),
        ),
        call_operands,
      )
    }
  }
  let result_types = instruction.results.map(value => lower_type(value.ty))
  let live_gc_roots : Array[@semantic.Value] = []
  for value_id in root_ids {
    match values[value_id] {
      Some(value) => live_gc_roots.push(value)
      None => raise MissingValue(value_id~)
    }
  }
  let lowered_results = builder.emit_with_metadata(
    Call(semantic_call),
    operands,
    result_types,
    instruction_metadata(instruction, live_gc_roots),
  )
  assign_instruction_results(values, instruction, lowered_results)
}

///|
fn mapped_gc_roots(
  values : Array[@semantic.Value?],
  root_ids : Array[Int],
) -> Array[@semantic.Value] raise SemanticLowerError {
  let roots : Array[@semantic.Value] = []
  for value_id in root_ids {
    match values[value_id] {
      Some(value) => roots.push(value)
      None => raise MissingValue(value_id~)
    }
  }
  roots
}

///|
fn lower_dialect_instruction(
  builder : @semantic.FunctionBuilder,
  values : Array[@semantic.Value?],
  environment : Array[@semantic.Value],
  instruction : @milkir.Inst,
  function_result_types : Array[@semantic.ValueType],
  ext : @milkir.ExtOp,
  block_id : Int,
  root_ids : Array[Int],
  lowering : DialectLowering,
) -> Bool raise SemanticLowerError {
  if ext.dialect != lowering.name {
    raise UnsupportedOperation(
      block_id~,
      instruction_id=instruction.id,
      message="dialect '\{ext.dialect}' does not match adapter '\{lowering.name}'",
    )
  }
  fn complete(results : Array[@semantic.Value]) -> Unit {
    for index, result in instruction.results {
      values[result.id] = Some(results[index])
    }
  }
  let context = @adapter.InstructionContext::new(
    builder,
    mapped_values(values, instruction.args),
    instruction.args.map(operand => lower_type(operand.ty)),
    instruction.results.map(result => lower_type(result.ty)),
    function_result_types,
    environment,
    instruction_source(instruction),
    mapped_gc_roots(values, root_ids),
    complete,
  )
  match (lowering.lower)(context, ext) {
    Some(message) =>
      raise UnsupportedOperation(
        block_id~,
        instruction_id=instruction.id,
        message~,
      )
    None => ()
  }
  if context.status() is Some(message) {
    raise UnsupportedOperation(
      block_id~,
      instruction_id=instruction.id,
      message~,
    )
  }
  context.terminates_block()
}

///|
fn lower_scalar_operation(
  scalar : @milkir.ScalarOp,
  instruction : @milkir.Inst,
  block_id : Int,
) -> @semantic.Operation raise SemanticLowerError {
  match scalar {
    IntConst(bits) =>
      match instruction.results[0].ty {
        I32 => I32Const(bits.to_int().reinterpret_as_uint())
        I64 => I64Const(bits.reinterpret_as_uint64())
        _ =>
          raise UnsupportedOperation(
            block_id~,
            instruction_id=instruction.id,
            message="integer constants require i32 or i64 results",
          )
      }
    FloatConst32(bits) => F32Const(bits)
    FloatConst64(bits) => F64Const(bits)
    IntBinary(op) => lower_int_binary(op)
    IntUnary(op) => IntUnary(lower_int_unary(op))
    IntCompare(op) =>
      match instruction.args[0].ty {
        Ptr | Ref | CallableRef | OpaqueRef =>
          match op {
            Eq => ReferenceCompare(Equal)
            Ne => ReferenceCompare(NotEqual)
            _ =>
              raise UnsupportedOperation(
                block_id~,
                instruction_id=instruction.id,
                message="ordered reference comparison is invalid",
              )
          }
        _ => IntCompare(lower_int_comparison(op))
      }
    FloatBinary(op) => FloatBinary(lower_float_binary(op))
    FloatUnary(op) => FloatUnary(lower_float_unary(op))
    FloatCompare(op) => FloatCompare(lower_float_comparison(op))
    Convert(op) =>
      Convert(
        lower_conversion(op, instruction.args[0].ty, instruction.results[0].ty),
      )
    SignExtendFrom(bits) =>
      match lower_width(bits) {
        Some(width) =>
          Convert(
            SignExtend(lower_integer_type(instruction.results[0].ty), width),
          )
        None =>
          raise UnsupportedOperation(
            block_id~,
            instruction_id=instruction.id,
            message="invalid sign-extension width \{bits}",
          )
      }
    Select => Select
    Copy => Copy
  }
}

///|
fn lower_instruction(
  builder : @semantic.FunctionBuilder,
  values : Array[@semantic.Value?],
  instruction : @milkir.Inst,
  block_id : Int,
  gc_roots : Array[Array[Int]],
  function_result_types : Array[@semantic.ValueType],
  environment : Array[@semantic.Value],
  dialect : DialectLowering?,
) -> Bool raise SemanticLowerError {
  match instruction.opcode {
    Call(call) => {
      lower_call_instruction(
        builder,
        values,
        instruction,
        call,
        gc_roots[instruction.id],
      )
      return false
    }
    Memory(Vector(operation)) => {
      lower_vector_memory_instruction(builder, values, instruction, operation)
      return false
    }
    Memory(memory) => {
      lower_memory_instruction(builder, values, instruction, memory)
      return false
    }
    Scalar(scalar) => {
      let operation = lower_scalar_operation(scalar, instruction, block_id)
      let operands = mapped_values(values, instruction.args)
      let result_types = instruction.results.map(result => lower_type(result.ty))
      let lowered_results = builder.emit_with_metadata(
        operation,
        operands,
        result_types,
        instruction_metadata(instruction, []),
      )
      assign_instruction_results(values, instruction, lowered_results)
      false
    }
    Vector(operation) => {
      lower_vector_instruction(builder, values, instruction, operation)
      false
    }
    Ext(ext, _) =>
      match dialect {
        Some(lowering) =>
          lower_dialect_instruction(
            builder,
            values,
            environment,
            instruction,
            function_result_types,
            ext,
            block_id,
            gc_roots[instruction.id],
            lowering,
          )
        None =>
          raise UnsupportedOperation(
            block_id~,
            instruction_id=instruction.id,
            message="operation family \{instruction.opcode} requires a dialect adapter",
          )
      }
  }
}

///|
fn lower_trap_reason(
  reason : String,
) -> @semantic.TrapReason raise SemanticLowerError {
  if reason.contains("unreachable") {
    return Unreachable
  }
  match reason {
    "integer divide by zero" | "integer division by zero" =>
      IntegerDivisionByZero
    "integer overflow" => IntegerOverflow
    "invalid conversion to integer" => InvalidConversionToInteger
    "memory out of bounds" => MemoryOutOfBounds
    "table out of bounds" | "out of bounds table access" => TableOutOfBounds
    "indirect call type mismatch" => IndirectCallTypeMismatch
    "null reference" | "null function reference" | "null i31 reference" =>
      NullReference
    "unaligned atomic" => UnalignedAtomic
    "unsupported atomic" => UnsupportedOperation
    "stack overflow" => StackOverflow
    _ =>
      raise UnsupportedOperation(
        block_id=-1,
        instruction_id=-1,
        message="unknown MilkIR trap reason '\{reason}'",
      )
  }
}

///|
fn lower_terminator(
  builder : @semantic.FunctionBuilder,
  values : Array[@semantic.Value?],
  blocks : Array[@semantic.Block?],
  block_id : Int,
  terminator : @milkir.Terminator,
) -> Unit raise SemanticLowerError {
  match terminator {
    Jump(target, arguments) =>
      builder.jump(
        mapped_block(blocks, target),
        mapped_values(values, arguments),
      )
    Branch(
      condition,
      true_target,
      true_arguments,
      false_target,
      false_arguments
    ) =>
      builder.branch(
        mapped_value(values, condition),
        mapped_block(blocks, true_target),
        mapped_values(values, true_arguments),
        mapped_block(blocks, false_target),
        mapped_values(values, false_arguments),
      )
    Brnz(condition, true_target, false_target) =>
      builder.branch(
        mapped_value(values, condition),
        mapped_block(blocks, true_target),
        [],
        mapped_block(blocks, false_target),
        [],
      )
    Brz(condition, true_target, false_target) =>
      builder.branch(
        mapped_value(values, condition),
        mapped_block(blocks, false_target),
        [],
        mapped_block(blocks, true_target),
        [],
      )
    BrTable(index, targets, default_target) => {
      let cases : Array[(UInt64, @semantic.Block, Array[@semantic.Value])] = []
      for case_index, target in targets {
        cases.push((case_index.to_uint64(), mapped_block(blocks, target), []))
      }
      builder.switch(
        mapped_value(values, index),
        cases,
        mapped_block(blocks, default_target),
        [],
      )
    }
    Return(results) => builder.return_(mapped_values(values, results))
    Trap(reason) => builder.trap(lower_trap_reason(reason))
    TrapExit(reason) =>
      raise UnsupportedOperation(
        block_id~,
        instruction_id=-1,
        message="product-specific trap_exit '\{reason}' is not core semantic MachV",
      )
  }
}

///|
fn lower_verified_function(
  function : @milkir.Function,
  protocol : @semantic.CallProtocol,
  dialect : DialectLowering?,
) -> @semantic.Function raise SemanticLowerError {
  let parameter_types : Array[@semantic.ValueType] = []
  for parameter_index, parameter in function.params {
    let mut parameter_type = lower_type(parameter.1)
    if dialect is Some(lowering) {
      for environment_parameter in lowering.environment_parameters {
        if environment_parameter.0 == parameter_index {
          parameter_type = environment_parameter.1
        }
      }
    }
    parameter_types.push(parameter_type)
  }
  let builder = @semantic.FunctionBuilder::new(
    function.name,
    protocol,
    parameter_types,
    function.results.map(lower_type),
  )
  let values : Array[@semantic.Value?] = Array::make(
    function.next_value_id,
    None,
  )
  let lowered_params = builder.parameters()
  let environment : Array[@semantic.Value] = []
  if dialect is Some(lowering) {
    for environment_parameter in lowering.environment_parameters {
      let parameter_index = environment_parameter.0
      if parameter_index < 0 || parameter_index >= lowered_params.length() {
        raise InvalidMilkIR(
          message="dialect environment parameter \{parameter_index} is outside the function signature",
        )
      }
      environment.push(lowered_params[parameter_index])
    }
  }
  for index, parameter in function.params {
    values[parameter.0.id] = Some(lowered_params[index])
  }
  let blocks : Array[@semantic.Block?] = Array::make(
    function.next_block_id,
    None,
  )
  for index, block in function.blocks {
    let lowered_block = if index == 0 {
      if !block.params.is_empty() {
        raise InvalidMilkIR(
          message="entry block must not declare block parameters",
        )
      }
      builder.entry_block()
    } else {
      builder.create_block(
        block.params.map(parameter => lower_type(parameter.1)),
      )
    }
    blocks[block.id] = Some(lowered_block)
    let lowered_block_params = builder.block_parameters(lowered_block)
    for parameter_index, parameter in block.params {
      values[parameter.0.id] = Some(lowered_block_params[parameter_index])
    }
  }
  let cfg = @milkir.CFG::build(function)
  let gc_roots = compute_gc_roots(function, cfg)
  let function_result_types = function.results.map(lower_type)
  for block_id in cfg.reverse_postorder() {
    let block = function.blocks[block_id]
    builder.switch_to_block(mapped_block(blocks, block.id))
    let mut terminator_replaced = false
    for instruction in block.instructions {
      if !terminator_replaced {
        terminator_replaced = lower_instruction(
          builder,
          values,
          instruction,
          block.id,
          gc_roots,
          function_result_types,
          environment,
          dialect,
        )
      }
    }
    if !terminator_replaced {
      match block.terminator {
        Some(terminator) =>
          lower_terminator(builder, values, blocks, block.id, terminator)
        None =>
          raise InvalidMilkIR(
            message="block \{block.id} has no terminator after verification",
          )
      }
    }
  }
  builder.finish() catch {
    error => raise InvalidMachV(message=error.to_string())
  }
}

///|
/// Lower verified core MilkIR into target-neutral semantic MachV.
///
/// Core lowering deliberately rejects extension operations instead of
/// consulting a target ISA or silently routing them through the legacy backend.
pub fn lower_core_function_with_protocol(
  function : @milkir.Function,
  protocol : @semantic.CallProtocol,
) -> @semantic.Function raise SemanticLowerError {
  function.verify_core() catch {
    error => raise InvalidMilkIR(message=error.to_string())
  }
  lower_verified_function(function, protocol, None)
}

///|
/// Lower an ordinary internally callable core MilkIR function.
pub fn lower_core_function(
  function : @milkir.Function,
) -> @semantic.Function raise SemanticLowerError {
  lower_core_function_with_protocol(function, Internal)
}

///|
/// Validate and lower one explicit MilkIR dialect through the safe semantic
/// construction adapter.
pub fn lower_dialect_function_with_protocol(
  function : @milkir.Function,
  protocol : @semantic.CallProtocol,
  dialect : String,
  validator : (@milkir.ExtensionInstView) -> String?,
  environment_parameters : Array[(Int, @semantic.ValueType)],
  lower : (@adapter.InstructionContext, @milkir.ExtOp) -> String?,
) -> @semantic.Function raise SemanticLowerError {
  function.verify_with_extension_validator(dialect, validator) catch {
    error => raise InvalidMilkIR(message=error.to_string())
  }
  lower_verified_function(
    function,
    protocol,
    Some({
      name: dialect,
      environment_parameters: environment_parameters.copy(),
      lower,
    }),
  )
}

///|
pub fn lower_dialect_function(
  function : @milkir.Function,
  dialect : String,
  validator : (@milkir.ExtensionInstView) -> String?,
  environment_parameters : Array[(Int, @semantic.ValueType)],
  lower : (@adapter.InstructionContext, @milkir.ExtOp) -> String?,
) -> @semantic.Function raise SemanticLowerError {
  lower_dialect_function_with_protocol(
    function,
    Internal,
    dialect,
    validator,
    environment_parameters,
    lower,
  )
}
