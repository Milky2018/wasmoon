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
) -> Unit raise SemanticLowerError {
  let operation = match instruction.opcode {
    Scalar(scalar) => lower_scalar_operation(scalar, instruction, block_id)
    Call(_) | Memory(_) | Vector(_) | Ext(_, _) =>
      raise UnsupportedOperation(
        block_id~,
        instruction_id=instruction.id,
        message="operation family \{instruction.opcode} is not in the first semantic lowering slice",
      )
  }
  let operands = mapped_values(values, instruction.args)
  let result_types = instruction.results.map(result => lower_type(result.ty))
  let lowered_results = builder.emit(operation, operands, result_types)
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
    Trap(reason) | TrapExit(reason) =>
      raise UnsupportedOperation(
        block_id~,
        instruction_id=-1,
        message="trap reason '\{reason}' requires an explicit lowering policy",
      )
  }
}

///|
/// Lower verified core MilkIR into target-neutral semantic MachV.
///
/// This initial producer deliberately rejects operation families that still
/// require an explicit semantic contract instead of consulting a target ISA or
/// silently routing them through the legacy backend.
pub fn lower_core_function(
  function : @milkir.Function,
) -> @semantic.Function raise SemanticLowerError {
  function.verify_core() catch {
    error => raise InvalidMilkIR(message=error.to_string())
  }
  let builder = @semantic.FunctionBuilder::new(
    function.name,
    Internal,
    function.params.map(param => lower_type(param.1)),
    function.results.map(lower_type),
  )
  let values : Array[@semantic.Value?] = Array::make(
    function.next_value_id,
    None,
  )
  let lowered_params = builder.parameters()
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
  for block in function.blocks {
    builder.switch_to_block(mapped_block(blocks, block.id))
    for instruction in block.instructions {
      lower_instruction(builder, values, instruction, block.id)
    }
    match block.terminator {
      Some(terminator) =>
        lower_terminator(builder, values, blocks, block.id, terminator)
      None =>
        raise InvalidMilkIR(
          message="block \{block.id} has no terminator after verification",
        )
    }
  }
  builder.finish() catch {
    error => raise InvalidMachV(message=error.to_string())
  }
}
