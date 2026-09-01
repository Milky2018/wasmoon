///|
pub suberror NativeLowerError {
  InvalidMilkIR(message~ : String)
  UnsupportedOperation(
    block_id~ : Int,
    instruction_id~ : Int,
    message~ : String
  )
  MissingValue(value_id~ : Int)
  MissingBlock(block_id~ : Int)
  InvalidTargetLowering(message~ : String)
} derive(Debug, Eq)

///|
pub impl Show for NativeLowerError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
priv struct DialectLowering {
  name : String
  environment_parameters : Array[(Int, @native.ValueType)]
  lower : (@adapter.InstructionContext, @milkir.ExtOp) -> String?
  resolve_context_field : (@milkir.ContextField) -> @native.EnvironmentField?
}

///|
fn lower_type(ty : @milkir.Type) -> @native.ValueType {
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
pub fn function_signature(
  function : @milkir.Function,
  environment_parameters? : Array[(Int, @native.ValueType)] = [],
) -> @native.Signature {
  let parameters = function.params.map(parameter => lower_type(parameter.1))
  for binding in environment_parameters {
    if binding.0 >= 0 && binding.0 < parameters.length() {
      parameters[binding.0] = binding.1
    }
  }
  @native.Signature::new(parameters, function.results.map(lower_type))
}

///|
fn lower_integer_type(
  ty : @milkir.Type,
) -> @native.IntegerType raise NativeLowerError {
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
) -> @native.FloatType raise NativeLowerError {
  match ty {
    F32 => F32
    F64 => F64
    _ =>
      raise InvalidMilkIR(message="expected a verified float type, got \{ty}")
  }
}

///|
fn lower_int_binary(op : @milkir.IntBinaryOp) -> @lowering.Operation {
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
fn lower_int_unary(op : @milkir.IntUnaryOp) -> @lowering.IntUnaryOp {
  match op {
    Not => Not
    CountLeadingZeros => CountLeadingZeros
    CountTrailingZeros => CountTrailingZeros
    PopulationCount => PopulationCount
  }
}

///|
fn lower_int_comparison(op : @milkir.IntCC) -> @lowering.IntComparison {
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
fn lower_float_binary(op : @milkir.FloatBinaryOp) -> @lowering.FloatBinaryOp {
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
fn lower_float_unary(op : @milkir.FloatUnaryOp) -> @lowering.FloatUnaryOp {
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
fn lower_float_comparison(op : @milkir.FloatCC) -> @lowering.FloatComparison {
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
fn lower_width(bits : Int) -> @native.AccessWidth? {
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
) -> @lowering.ConversionOp raise NativeLowerError {
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
  values : Array[@lowering.Value?],
  value : @milkir.Value,
) -> @lowering.Value raise NativeLowerError {
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
  values : Array[@lowering.Value?],
  source : Array[@milkir.Value],
) -> Array[@lowering.Value] raise NativeLowerError {
  let result : Array[@lowering.Value] = []
  for value in source {
    result.push(mapped_value(values, value))
  }
  result
}

///|
fn mapped_block(
  blocks : Array[@lowering.Block?],
  block_id : Int,
) -> @lowering.Block raise NativeLowerError {
  if block_id < 0 || block_id >= blocks.length() {
    raise MissingBlock(block_id~)
  }
  match blocks[block_id] {
    Some(block) => block
    None => raise MissingBlock(block_id~)
  }
}

///|
fn instruction_source(instruction : @milkir.Inst) -> @native.SourceLocation? {
  for metadata in instruction.metadata {
    if metadata is SourceLoc(source) {
      // MilkIR stores an opaque source label rather than structured
      // coordinates. Preserve that label verbatim and mark coordinates as
      // unknown until the producer carries a structured location.
      return Some(@native.SourceLocation::new(source, 0, 0))
    }
  }
  None
}

///|
fn instruction_metadata(
  instruction : @milkir.Inst,
  live_gc_roots : Array[@lowering.Value],
) -> @lowering.InstructionMetadata {
  @lowering.InstructionMetadata::new(
    instruction_source(instruction),
    live_gc_roots,
  )
}

///|
fn emit_one(
  builder : @lowering.DirectBuilder,
  operation : @lowering.Operation,
  operands : Array[@lowering.Value],
  result_type : @native.ValueType,
  source : @native.SourceLocation?,
  instruction_id : Int,
) -> @lowering.Value raise NativeLowerError {
  let results = builder.emit_with_metadata(
    operation,
    operands,
    [result_type],
    @lowering.InstructionMetadata::new(source, []),
  )
  if results.length() != 1 {
    raise InvalidTargetLowering(
      message="instruction \{instruction_id} failed native target selector construction",
    )
  }
  results[0]
}

///|
fn lower_bitcast_value(
  builder : @lowering.DirectBuilder,
  operand : @lowering.Value,
  source_type : @milkir.Type,
  result_type : @milkir.Type,
  source : @native.SourceLocation?,
  instruction_id : Int,
) -> @lowering.Value raise NativeLowerError {
  let from = lower_type(source_type)
  let to = lower_type(result_type)
  if from == to {
    return operand
  }
  if from == GcRef64 {
    let address = emit_one(
      builder,
      GcRefAddress,
      [operand],
      Ptr64,
      source,
      instruction_id,
    )
    if to == Ptr64 {
      return address
    }
    let bits = emit_one(
      builder,
      Convert(Bitcast(Ptr64, I64)),
      [address],
      I64,
      source,
      instruction_id,
    )
    if to == I64 {
      return bits
    }
    return emit_one(
      builder,
      Convert(Bitcast(I64, to)),
      [bits],
      to,
      source,
      instruction_id,
    )
  }
  if to == GcRef64 {
    let bits = if from == I64 {
      operand
    } else {
      emit_one(
        builder,
        Convert(Bitcast(from, I64)),
        [operand],
        I64,
        source,
        instruction_id,
      )
    }
    return emit_one(
      builder,
      GcRefFromBits,
      [bits],
      GcRef64,
      source,
      instruction_id,
    )
  }
  emit_one(
    builder,
    Convert(Bitcast(from, to)),
    [operand],
    to,
    source,
    instruction_id,
  )
}

///|
fn lower_pointer_value(
  builder : @lowering.DirectBuilder,
  values : Array[@lowering.Value?],
  value_types : Array[@native.ValueType?],
  source : @milkir.Value,
  location : @native.SourceLocation?,
  instruction_id : Int,
) -> @lowering.Value raise NativeLowerError {
  let mapped = mapped_value(values, source)
  match value_types[source.id] {
    Some(Ptr64) => mapped
    Some(I64) =>
      emit_one(
        builder,
        Convert(Bitcast(I64, Ptr64)),
        [mapped],
        Ptr64,
        location,
        instruction_id,
      )
    Some(ty) =>
      raise InvalidMilkIR(
        message="memory address must be ptr64 or i64, got \{ty}",
      )
    None => raise MissingValue(value_id=source.id)
  }
}

///|
fn lower_address(
  builder : @lowering.DirectBuilder,
  values : Array[@lowering.Value?],
  value_types : Array[@native.ValueType?],
  base : @milkir.Value,
  offset : @milkir.Value,
  source : @native.SourceLocation?,
  instruction_id : Int,
) -> @lowering.Value raise NativeLowerError {
  let pointer = lower_pointer_value(
    builder, values, value_types, base, source, instruction_id,
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
fn access_width_for_type(ty : @native.ValueType) -> @native.AccessWidth {
  match ty {
    I32 | F32 => W32
    I64 | F64 | Ptr64 | GcRef64 => W64
    V128 => W128
  }
}

///|
fn assign_instruction_results(
  values : Array[@lowering.Value?],
  instruction : @milkir.Inst,
  lowered_results : Array[@lowering.Value],
) -> Unit raise NativeLowerError {
  if lowered_results.length() != instruction.results.length() {
    raise InvalidTargetLowering(
      message="instruction \{instruction.id} (\{instruction.opcode}) produced \{lowered_results.length()} results, expected \{instruction.results.length()}",
    )
  }
  for index, result in instruction.results {
    values[result.id] = Some(lowered_results[index])
  }
}

///|
fn lower_memory_instruction(
  builder : @lowering.DirectBuilder,
  values : Array[@lowering.Value?],
  value_types : Array[@native.ValueType?],
  instruction : @milkir.Inst,
  memory : @milkir.MemoryOp,
  analysis : LoweringAnalysis,
) -> Unit raise NativeLowerError {
  let source = instruction_source(instruction)
  let selected_address = fn(
    base : @milkir.Value,
    offset : @milkir.Value,
  ) -> (Array[@lowering.Value], UInt64, Int?) raise NativeLowerError {
    match analysis.memory_addresses[instruction.id] {
      Some(selected) => {
        let operands = [
          lower_pointer_value(
            builder,
            values,
            value_types,
            selected.base,
            source,
            instruction.id,
          ),
        ]
        match selected.index {
          Some(index) => {
            operands.push(mapped_value(values, index))
            (operands, selected.offset, Some(selected.shift))
          }
          None => (operands, selected.offset, None)
        }
      }
      None =>
        (
          [
            lower_address(
              builder,
              values,
              value_types,
              base,
              offset,
              source,
              instruction.id,
            ),
          ],
          0UL,
          None,
        )
    }
  }
  let results = match memory {
    Load(result_type) => {
      let lowered_type = lower_type(result_type)
      let (address, offset, shift) = selected_address(
        instruction.args[0],
        instruction.args[1],
      )
      let spec = @lowering.LoadSpec::new(
        access_width_for_type(lowered_type),
        None,
        lowered_type,
        offset,
        Little,
        None,
      )
      builder.emit_with_metadata(
        match shift {
          Some(shift) => LoadIndexed(spec, shift)
          None => Load(spec)
        },
        address,
        [lowered_type],
        instruction_metadata(instruction, []),
      )
    }
    Store(value_type) => {
      let lowered_type = lower_type(value_type)
      let (address, offset, shift) = selected_address(
        instruction.args[0],
        instruction.args[2],
      )
      address.push(mapped_value(values, instruction.args[1]))
      let spec = @lowering.StoreSpec::new(
        access_width_for_type(lowered_type),
        lowered_type,
        offset,
        Little,
        None,
      )
      builder.emit_with_metadata(
        match shift {
          Some(shift) => StoreIndexed(spec, shift)
          None => Store(spec)
        },
        address,
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
      let (address, offset, shift) = selected_address(
        instruction.args[0],
        instruction.args[1],
      )
      let spec = @lowering.LoadSpec::new(
        width,
        if signed {
          Signed
        } else {
          Unsigned
        },
        lowered_type,
        offset,
        Little,
        None,
      )
      builder.emit_with_metadata(
        match shift {
          Some(shift) => LoadIndexed(spec, shift)
          None => Load(spec)
        },
        address,
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
      let (address, offset, shift) = selected_address(
        instruction.args[0],
        instruction.args[2],
      )
      address.push(mapped_value(values, instruction.args[1]))
      let spec = @lowering.StoreSpec::new(
        width,
        value_type,
        offset,
        Little,
        None,
      )
      builder.emit_with_metadata(
        match shift {
          Some(shift) => StoreIndexed(spec, shift)
          None => Store(spec)
        },
        address,
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
  let block_uses : Array[@hashset.HashSet[Int]] = Array::makei(
    function.next_block_id,
    _ => HashSet([]),
  )
  let block_definitions : Array[@hashset.HashSet[Int]] = Array::makei(
    function.next_block_id,
    _ => HashSet([]),
  )
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
    block_uses[block.id] = uses
    block_definitions[block.id] = definitions
  }
  let live_in : Array[@hashset.HashSet[Int]] = Array::makei(
    function.next_block_id,
    _ => HashSet([]),
  )
  let live_out : Array[@hashset.HashSet[Int]] = Array::makei(
    function.next_block_id,
    _ => HashSet([]),
  )
  let worklist : Array[Int] = []
  let queued = Array::make(function.next_block_id, false)
  let mut block_index = function.blocks.length() - 1
  while block_index >= 0 {
    let block_id = function.blocks[block_index].id
    worklist.push(block_id)
    queued[block_id] = true
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
fn gc_roots_for_instruction(
  roots : Array[Array[Int]]?,
  instruction : Int,
) -> Array[Int] {
  match roots {
    Some(roots) => roots[instruction]
    None => []
  }
}

///|
fn lower_call_instruction(
  builder : @lowering.DirectBuilder,
  values : Array[@lowering.Value?],
  value_types : Array[@native.ValueType?],
  instruction : @milkir.Inst,
  call : @milkir.CallOp,
  root_ids : Array[Int],
) -> Unit raise NativeLowerError {
  let (semantic_call, operands) = match call {
    Direct(symbol, signature) =>
      (
        @native.NativeCall::new(
          External(@native.ExternalSymbol::new(symbol.name)),
          @native.Signature::new(
            instruction.args.map(argument => value_types[argument.id].unwrap()),
            signature.results.map(lower_type),
          ),
          Platform,
          @native.CallBehavior::conservative(),
        ),
        mapped_values(values, instruction.args),
      )
    Pointer(_, _) => {
      let parameter_types = instruction.args[1:].map(value => {
        value_types[value.id].unwrap()
      })
      let result_types = instruction.results.map(value => lower_type(value.ty))
      let call_operands = [
        lower_pointer_value(
          builder,
          values,
          value_types,
          instruction.args[0],
          instruction_source(instruction),
          instruction.id,
        ),
      ]
      for argument in instruction.args[1:] {
        call_operands.push(mapped_value(values, argument))
      }
      (
        @native.NativeCall::new(
          Indirect,
          @native.Signature::new(parameter_types, result_types),
          Internal,
          @native.CallBehavior::conservative(),
        ),
        call_operands,
      )
    }
  }
  let result_types = instruction.results.map(value => lower_type(value.ty))
  let live_gc_roots : Array[@lowering.Value] = []
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
  values : Array[@lowering.Value?],
  root_ids : Array[Int],
) -> Array[@lowering.Value] raise NativeLowerError {
  let roots : Array[@lowering.Value] = []
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
  builder : @lowering.DirectBuilder,
  values : Array[@lowering.Value?],
  value_types : Array[@native.ValueType?],
  environment : Array[@lowering.Value],
  instruction : @milkir.Inst,
  function_result_types : Array[@native.ValueType],
  ext : @milkir.ExtOp,
  block_id : Int,
  root_ids : Array[Int],
  lowering : DialectLowering,
) -> Bool raise NativeLowerError {
  if ext.dialect != lowering.name {
    raise UnsupportedOperation(
      block_id~,
      instruction_id=instruction.id,
      message="dialect '\{ext.dialect}' does not match adapter '\{lowering.name}'",
    )
  }
  fn complete(results : Array[@lowering.Value]) -> Unit {
    for index, result in instruction.results {
      values[result.id] = Some(results[index])
    }
  }
  let context = @adapter.InstructionContext::new(
    builder,
    mapped_values(values, instruction.args),
    instruction.args.map(operand => value_types[operand.id].unwrap()),
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
) -> @lowering.Operation raise NativeLowerError {
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
  function : @milkir.Function,
  builder : @lowering.DirectBuilder,
  values : Array[@lowering.Value?],
  value_types : Array[@native.ValueType?],
  instruction : @milkir.Inst,
  block_id : Int,
  analysis : LoweringAnalysis,
  gc_roots : Array[Array[Int]]?,
  function_result_types : Array[@native.ValueType],
  environment : Array[@lowering.Value],
  dialect : DialectLowering?,
) -> Bool raise NativeLowerError {
  if !instruction.results.is_empty() &&
    instruction.results.all(result => analysis.skip_results[result.id]) {
    return false
  }
  match instruction.opcode {
    Call(call) => {
      lower_call_instruction(
        builder,
        values,
        value_types,
        instruction,
        call,
        gc_roots_for_instruction(gc_roots, instruction.id),
      )
      return false
    }
    Memory(Vector(operation)) => {
      lower_vector_memory_instruction(
        builder, values, value_types, instruction, operation,
      )
      return false
    }
    Memory(memory) => {
      lower_memory_instruction(
        builder, values, value_types, instruction, memory, analysis,
      )
      return false
    }
    GlobalValue(global_value) => {
      guard function.global_value_data(global_value) is Some(data) else {
        raise UnsupportedOperation(
          block_id~,
          instruction_id=instruction.id,
          message="global value \{global_value.id} has no declaration",
        )
      }
      let lowering = match dialect {
        Some(lowering) => lowering
        None =>
          raise UnsupportedOperation(
            block_id~,
            instruction_id=instruction.id,
            message="global value \{global_value.id} requires a dialect adapter",
          )
      }
      match data {
        ContextField(field, stability, _) => {
          guard (lowering.resolve_context_field)(field) is Some(lowered_field) else {
            raise UnsupportedOperation(
              block_id~,
              instruction_id=instruction.id,
              message="dialect '\{lowering.name}' cannot resolve context field \{field.dialect}:\{field.key}",
            )
          }
          let expected_type = lower_type(field.ty)
          if lowered_field.value_type != expected_type {
            raise UnsupportedOperation(
              block_id~,
              instruction_id=instruction.id,
              message="context field \{field.dialect}:\{field.key} resolved as \{lowered_field.value_type}, expected \{expected_type}",
            )
          }
          let lowered_results = builder.emit_with_metadata(
            EnvironmentField(
              lowered_field,
              match stability {
                Stable => Stable
                Mutable => Mutable
              },
            ),
            mapped_values(values, instruction.args),
            [expected_type],
            instruction_metadata(instruction, []),
          )
          assign_instruction_results(values, instruction, lowered_results)
          return false
        }
      }
    }
    Scalar(scalar) => {
      if scalar is Copy &&
        instruction.args is [argument] &&
        instruction.results is [result] {
        let source = mapped_value(values, argument)
        guard value_types[argument.id] == Some(lower_type(result.ty)) else {
          raise InvalidMilkIR(
            message="copy result type does not match its verified operand",
          )
        }
        // MilkIR copies are aliases, not semantic machine operations. Keeping
        // them as owned native lowering instructions forced mandatory cleanup to scan
        // the complete function only to recover this mapping.
        values[result.id] = Some(source)
        return false
      }
      if scalar is Convert(Bitcast) &&
        instruction.args is [argument] &&
        instruction.results is [result] {
        values[result.id] = Some(
          lower_bitcast_value(
            builder,
            mapped_value(values, argument),
            argument.ty,
            result.ty,
            instruction_source(instruction),
            instruction.id,
          ),
        )
        return false
      }
      if scalar is IntConst(bits) &&
        instruction.results is [result] &&
        (
          result.ty is Ptr ||
          result.ty is Ref ||
          result.ty is CallableRef ||
          result.ty is OpaqueRef
        ) {
        let source = instruction_source(instruction)
        let lowered = match result.ty {
          Ptr => {
            let raw = emit_one(
              builder,
              I64Const(bits.reinterpret_as_uint64()),
              [],
              I64,
              source,
              instruction.id,
            )
            emit_one(
              builder,
              Convert(Bitcast(I64, Ptr64)),
              [raw],
              Ptr64,
              source,
              instruction.id,
            )
          }
          Ref | CallableRef | OpaqueRef =>
            if bits == 0L {
              emit_one(builder, NullGcRef, [], GcRef64, source, instruction.id)
            } else {
              let raw = emit_one(
                builder,
                I64Const(bits.reinterpret_as_uint64()),
                [],
                I64,
                source,
                instruction.id,
              )
              emit_one(
                builder,
                GcRefFromBits,
                [raw],
                GcRef64,
                source,
                instruction.id,
              )
            }
          _ => abort("matched pointer or reference carrier above")
        }
        values[result.id] = Some(lowered)
        return false
      }
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
            value_types,
            environment,
            instruction,
            function_result_types,
            ext,
            block_id,
            gc_roots_for_instruction(gc_roots, instruction.id),
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
) -> @native.TrapReason raise NativeLowerError {
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
  builder : @lowering.DirectBuilder,
  values : Array[@lowering.Value?],
  blocks : Array[@lowering.Block?],
  block_id : Int,
  terminator : @milkir.Terminator,
) -> Unit raise NativeLowerError {
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
      let cases : Array[(UInt64, @lowering.Block, Array[@lowering.Value])] = []
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
        message="product-specific trap_exit '\{reason}' is not core native target selector",
      )
  }
}

///|
fn lower_verified_construction(
  function : @milkir.Function,
  dialect : DialectLowering?,
  sink : @lowering.TargetSink,
  call_abi : @lowering.CallAbiElaboration?,
  on_event : (NativeLowerEvent) -> Unit,
) -> @lowering.DirectBuilder raise NativeLowerError {
  on_event(TargetConstructionStarted)
  let parameter_types : Array[@native.ValueType] = []
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
  let values : Array[@lowering.Value?] = Array::make(
    function.next_value_id,
    None,
  )
  let value_types : Array[@native.ValueType?] = Array::make(
    function.next_value_id,
    None,
  )
  let mut has_gc_references = false
  for index, parameter in function.params {
    value_types[parameter.0.id] = Some(parameter_types[index])
    has_gc_references = has_gc_references || is_gc_reference_type(parameter.1)
  }
  for block in function.blocks {
    for parameter in block.params {
      value_types[parameter.0.id] = Some(lower_type(parameter.1))
      has_gc_references = has_gc_references || is_gc_reference_type(parameter.1)
    }
    for instruction in block.instructions {
      for result in instruction.results {
        value_types[result.id] = Some(lower_type(result.ty))
        has_gc_references = has_gc_references || is_gc_reference_type(result.ty)
      }
    }
  }
  let cfg = @milkir.CFG::build(function)
  let analysis = analyze_lowering(function)
  let gc_roots = if has_gc_references {
    Some(compute_gc_roots(function, cfg))
  } else {
    None
  }
  let mut root_scope_capacity = 0
  if gc_roots is Some(roots) {
    for instruction_roots in roots {
      if instruction_roots.length() > root_scope_capacity {
        root_scope_capacity = instruction_roots.length()
      }
    }
  }
  let builder = @lowering.DirectBuilder::new(
    parameter_types,
    sink,
    call_abi?,
    root_scope_capacity~,
  )
  let lowered_params = builder.parameters()
  let environment : Array[@lowering.Value] = []
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
  let blocks : Array[@lowering.Block?] = Array::make(
    function.next_block_id,
    None,
  )
  let source_blocks : Array[@milkir.Block?] = Array::make(
    function.next_block_id,
    None,
  )
  for block in function.blocks {
    source_blocks[block.id] = Some(block)
  }
  let function_result_types = function.results.map(lower_type)
  let block_order = cfg.reverse_postorder()
  let reachable = Array::make(function.next_block_id, false)
  for block_id in block_order {
    reachable[block_id] = true
  }
  for block in function.blocks {
    if !reachable[block.id] {
      continue
    }
    let lowered_block = if block.id == function.blocks[0].id {
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
  for block_id in block_order {
    let block = source_blocks[block_id].unwrap()
    builder.switch_to_block(mapped_block(blocks, block.id))
    let mut terminator_replaced = false
    for instruction in block.instructions {
      if !terminator_replaced {
        terminator_replaced = lower_instruction(
          function,
          builder,
          values,
          value_types,
          instruction,
          block.id,
          analysis,
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
  builder
}

///|

///|
/// Verify and stream core MilkIR directly into a native target selector.
pub fn lower_core_to_sink(
  function : @milkir.Function,
  sink : @lowering.TargetSink,
  call_abi? : @lowering.CallAbiElaboration,
  on_event? : (NativeLowerEvent) -> Unit = fn(_) { () },
) -> Unit raise NativeLowerError {
  on_event(InputValidationStarted)
  function.verify_core() catch {
    error => raise InvalidMilkIR(message=error.to_string())
  }
  let builder = lower_verified_construction(
    function,
    None,
    sink,
    call_abi,
    on_event,
  )
  builder.finish() catch {
    error => raise InvalidTargetLowering(message=error.to_string())
  }
  on_event(NativeLoweringFinished)
}

///|
/// Verify one MilkIR dialect and stream it directly into a native target
/// selector. No target-neutral function or instruction graph is materialized.
pub fn lower_dialect_to_sink(
  function : @milkir.Function,
  dialect : String,
  validator : (@milkir.ExtensionInstView) -> String?,
  global_value_validator : (@milkir.GlobalValueData) -> String?,
  environment_parameters : Array[(Int, @native.ValueType)],
  lower : (@adapter.InstructionContext, @milkir.ExtOp) -> String?,
  resolve_context_field : (@milkir.ContextField) -> @native.EnvironmentField?,
  sink : @lowering.TargetSink,
  call_abi? : @lowering.CallAbiElaboration,
  on_event? : (NativeLowerEvent) -> Unit = fn(_) { () },
) -> Unit raise NativeLowerError {
  on_event(InputValidationStarted)
  function.verify_with_dialect_validator(
    dialect, validator, global_value_validator,
  ) catch {
    error => raise InvalidMilkIR(message=error.to_string())
  }
  let builder = lower_verified_construction(
    function,
    Some({
      name: dialect,
      environment_parameters: environment_parameters.copy(),
      lower,
      resolve_context_field,
    }),
    sink,
    call_abi,
    on_event,
  )
  builder.finish() catch {
    error => raise InvalidTargetLowering(message=error.to_string())
  }
  on_event(NativeLoweringFinished)
}
