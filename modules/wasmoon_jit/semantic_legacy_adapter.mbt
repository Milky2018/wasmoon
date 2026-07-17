///|
priv suberror SemanticLegacyAdapterError {
  MissingValue(value_id~ : Int)
  UnsupportedOperation(message~ : String)
  InvalidLegacyFunction(message~ : String)
} derive(Debug)

///|
impl Show for SemanticLegacyAdapterError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
fn legacy_reg_class(ty : @semantic_machv.ValueType) -> @abi.RegClass {
  match ty {
    I32 | I64 | Ptr64 | GcRef64 => Int
    F32 => Float32
    F64 => Float64
    V128 => Vector
  }
}

///|
fn legacy_value_kind(ty : @semantic_machv.ValueType) -> @machv.ValueKind {
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
  function : @semantic_machv.Function,
  values : Array[@abi.VReg?],
  value : @semantic_machv.Value,
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
  function : @semantic_machv.Function,
  results : Array[@semantic_machv.Value],
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
  function : @semantic_machv.Function,
  operation : @semantic_machv.IntBinaryOp,
  results : Array[@semantic_machv.Value],
) -> @instr.Opcode raise SemanticLegacyAdapterError {
  let is_64 = semantic_integer_width(function, results)
  match operation {
    Add => Add(is_64)
    Sub => Sub(is_64)
    Mul => Mul(is_64)
    And => And(is_64)
    Or => Or(is_64)
    Xor => Xor(is_64)
    ShiftLeft => Shl(is_64)
    SignedShiftRight => AShr(is_64)
    UnsignedShiftRight => LShr(is_64)
    RotateRight => Rotr(is_64)
    SignedDiv | UnsignedDiv | SignedRem | UnsignedRem =>
      raise UnsupportedOperation(
        message="division and remainder require explicit trap legalization",
      )
    RotateLeft =>
      raise UnsupportedOperation(
        message="rotate-left requires explicit legalization",
      )
  }
}

///|
fn semantic_operand_is_64(
  function : @semantic_machv.Function,
  operands : Array[@semantic_machv.Value],
) -> Bool raise SemanticLegacyAdapterError {
  if operands.is_empty() {
    raise UnsupportedOperation(
      message="operation has no width-carrying operand",
    )
  }
  match function.value_type(operands[0]) {
    Some(I32) => false
    Some(I64 | Ptr64 | GcRef64) => true
    Some(ty) =>
      raise UnsupportedOperation(
        message="operation has non-integer operand type \{ty}",
      )
    None => raise UnsupportedOperation(message="operand is not function-owned")
  }
}

///|
fn lower_semantic_int_unary(
  function : @semantic_machv.Function,
  operation : @semantic_machv.IntUnaryOp,
  operands : Array[@semantic_machv.Value],
) -> @instr.Opcode raise SemanticLegacyAdapterError {
  let is_64 = semantic_operand_is_64(function, operands)
  match operation {
    Not => Not(is_64)
    CountLeadingZeros => Clz(is_64)
    PopulationCount => Popcnt(is_64)
    CountTrailingZeros =>
      raise UnsupportedOperation(
        message="count-trailing-zeros requires explicit legalization",
      )
  }
}

///|
fn lower_semantic_int_comparison(
  function : @semantic_machv.Function,
  comparison : @semantic_machv.IntComparison,
  operands : Array[@semantic_machv.Value],
) -> @instr.Opcode raise SemanticLegacyAdapterError {
  let kind : @instr.CmpKind = match comparison {
    Equal => Eq
    NotEqual => Ne
    SignedLessThan => Slt
    SignedLessOrEqual => Sle
    SignedGreaterThan => Sgt
    SignedGreaterOrEqual => Sge
    UnsignedLessThan => Ult
    UnsignedLessOrEqual => Ule
    UnsignedGreaterThan => Ugt
    UnsignedGreaterOrEqual => Uge
  }
  Cmp(kind, semantic_operand_is_64(function, operands))
}

///|
fn lower_semantic_float_unary(
  function : @semantic_machv.Function,
  operation : @semantic_machv.FloatUnaryOp,
  results : Array[@semantic_machv.Value],
) -> @instr.Opcode raise SemanticLegacyAdapterError {
  if results.length() != 1 {
    raise UnsupportedOperation(
      message="float unary operation must have exactly one result",
    )
  }
  let is_f32 = function.value_type(results[0]) is Some(F32)
  match operation {
    Negate => FNeg(is_f32)
    Absolute => FAbs(is_f32)
    SquareRoot => FSqrt(is_f32)
    Ceil => FCeil(is_f32)
    Floor => FFloor(is_f32)
    Truncate => FTrunc(is_f32)
    Nearest => FNearest(is_f32)
  }
}

///|
fn lower_semantic_float_binary(
  function : @semantic_machv.Function,
  operation : @semantic_machv.FloatBinaryOp,
  results : Array[@semantic_machv.Value],
) -> @instr.Opcode raise SemanticLegacyAdapterError {
  if results.length() != 1 {
    raise UnsupportedOperation(
      message="float binary operation must have exactly one result",
    )
  }
  let is_f32 = function.value_type(results[0]) is Some(F32)
  match operation {
    Add => FAdd(is_f32)
    Sub => FSub(is_f32)
    Mul => FMul(is_f32)
    Div => FDiv(is_f32)
    Min => FMin(is_f32)
    Max => FMax(is_f32)
    CopySign =>
      raise UnsupportedOperation(
        message="float copy-sign requires explicit legalization",
      )
  }
}

///|
fn lower_semantic_float_comparison(
  comparison : @semantic_machv.FloatComparison,
) -> @instr.Opcode raise SemanticLegacyAdapterError {
  let kind : @instr.FCmpKind = match comparison {
    Equal => Eq
    NotEqual => Ne
    LessThan => Lt
    LessOrEqual => Le
    GreaterThan => Gt
    GreaterOrEqual => Ge
    Ordered | Unordered =>
      raise UnsupportedOperation(
        message="ordered/unordered float comparison requires legalization",
      )
  }
  FCmp(kind)
}

///|
fn lower_semantic_conversion(
  conversion : @semantic_machv.ConversionOp,
) -> @instr.Opcode raise SemanticLegacyAdapterError {
  match conversion {
    I32WrapI64 => Truncate
    I64ExtendI32(Signed) => Extend(Signed32To64)
    I64ExtendI32(Unsigned) => Extend(Unsigned32To64)
    F32DemoteF64 => FDemote
    F64PromoteF32 => FPromote
    SignExtend(I32, W8) => Extend(Signed8To32)
    SignExtend(I32, W16) => Extend(Signed16To32)
    SignExtend(I64, W8) => Extend(Signed8To64)
    SignExtend(I64, W16) => Extend(Signed16To64)
    SignExtend(I64, W32) => Extend(Signed32To64)
    Bitcast(_, _) => Bitcast
    IntToFloat(I32, F32, Signed) => IntToFloat(I32SToF32)
    IntToFloat(I32, F32, Unsigned) => IntToFloat(I32UToF32)
    IntToFloat(I64, F32, Signed) => IntToFloat(I64SToF32)
    IntToFloat(I64, F32, Unsigned) => IntToFloat(I64UToF32)
    IntToFloat(I32, F64, Signed) => IntToFloat(I32SToF64)
    IntToFloat(I32, F64, Unsigned) => IntToFloat(I32UToF64)
    IntToFloat(I64, F64, Signed) => IntToFloat(I64SToF64)
    IntToFloat(I64, F64, Unsigned) => IntToFloat(I64UToF64)
    FloatToInt(_, _, _, _) =>
      raise UnsupportedOperation(
        message="float-to-int conversion requires trap or saturation legalization",
      )
    SignExtend(_, _) =>
      raise UnsupportedOperation(message="invalid sign-extension shape")
  }
}

///|
fn semantic_float_to_int_bounds(
  is_f32 : Bool,
  is_i64 : Bool,
  signed : Bool,
) -> (Int64, Int64, Bool) {
  match (is_f32, is_i64, signed) {
    (true, false, true) => (0xCF000000L, 0x4F000000L, false)
    (true, false, false) => (0xBF800000L, 0x4F800000L, true)
    (true, true, true) => (0xDF000000L, 0x5F000000L, false)
    (true, true, false) => (0xBF800000L, 0x5F800000L, true)
    (false, false, true) => (0xC1E0000000200000L, 0x41E0000000000000L, true)
    (false, false, false) => (0xBFF0000000000000L, 0x41F0000000000000L, true)
    (false, true, true) => (0xC3E0000000000000L, 0x43E0000000000000L, false)
    (false, true, false) => (0xBFF0000000000000L, 0x43F0000000000000L, true)
  }
}

///|
fn legacy_memory_type(ty : @semantic_machv.ValueType) -> @instr.MemType {
  match ty {
    I32 => I32
    I64 | Ptr64 | GcRef64 => I64
    F32 => F32
    F64 => F64
    V128 => V128
  }
}

///|
fn access_width_bits(width : @semantic_machv.AccessWidth) -> Int {
  match width {
    W8 => 8
    W16 => 16
    W32 => 32
    W64 => 64
    W128 => 128
  }
}

///|
fn semantic_type_width(
  ty : @semantic_machv.ValueType,
) -> @semantic_machv.AccessWidth {
  match ty {
    I32 | F32 => W32
    I64 | F64 | Ptr64 | GcRef64 => W64
    V128 => W128
  }
}

///|
fn lower_semantic_load(
  spec : @semantic_machv.LoadSpec,
) -> @instr.Opcode raise SemanticLegacyAdapterError {
  if spec.endianness != Little || spec.trap is Some(_) {
    raise UnsupportedOperation(
      message="non-native-endian or trapping load requires legalization",
    )
  }
  let offset = spec.offset.to_int()
  if spec.width == semantic_type_width(spec.result_type) &&
    spec.extension is None {
    return LoadPtr(legacy_memory_type(spec.result_type), offset)
  }
  match spec.extension {
    Signed => LoadPtrNarrow(access_width_bits(spec.width), true, offset)
    Unsigned => LoadPtrNarrow(access_width_bits(spec.width), false, offset)
    None =>
      raise UnsupportedOperation(message="narrow load must define extension")
  }
}

///|
fn lower_semantic_store(
  spec : @semantic_machv.StoreSpec,
) -> @instr.Opcode raise SemanticLegacyAdapterError {
  if spec.endianness != Little || spec.trap is Some(_) {
    raise UnsupportedOperation(
      message="non-native-endian or trapping store requires legalization",
    )
  }
  let offset = spec.offset.to_int()
  if spec.width == semantic_type_width(spec.value_type) {
    return StorePtr(legacy_memory_type(spec.value_type), offset)
  }
  StorePtrNarrow(access_width_bits(spec.width), offset)
}

///|
fn append_semantic_division_or_remainder(
  isa : @isa.ISA,
  legacy_function : @machv.Function,
  block : @block.Block,
  operation : @semantic_machv.IntBinaryOp,
  operands : Array[@abi.Reg],
  definitions : Array[@abi.Writable],
  is_64 : Bool,
  trap_payload : (@semantic_machv.TrapReason) -> Int,
) -> Unit raise SemanticLegacyAdapterError {
  if operands.length() != 2 || definitions.length() != 1 {
    raise UnsupportedOperation(
      message="division and remainder require two operands and one result",
    )
  }
  let lhs = operands[0]
  let rhs = operands[1]
  let destination = definitions[0]
  let signed = operation is (SignedDiv | SignedRem)
  let remainder = operation is (SignedRem | UnsignedRem)
  let zero_trap = @instr.Inst(
    TrapIfZero(is_64, trap_payload(IntegerDivisionByZero)),
  )
  if remainder && isa is AMD64 {
    zero_trap.add_use_fixed(rhs, {
      index: isa.scratch_reg_1_index(),
      class: Int,
    })
  } else {
    zero_trap.add_use(rhs)
  }
  block.add_inst(zero_trap)
  if operation is SignedDiv {
    let overflow_trap = @instr.Inst(
      TrapIfDivOverflow(is_64, trap_payload(IntegerOverflow)),
    )
    overflow_trap.add_use(lhs)
    overflow_trap.add_use(rhs)
    block.add_inst(overflow_trap)
  }
  if !remainder {
    let opcode : @instr.Opcode = if signed { SDiv(is_64) } else { UDiv(is_64) }
    let division = @instr.Inst(opcode)
    division.add_def(destination)
    division.add_use(lhs)
    division.add_use(rhs)
    block.add_inst(division)
    return
  }
  if isa is AMD64 {
    let opcode : @instr.Opcode = if signed { SRem(is_64) } else { URem(is_64) }
    let remainder_instruction = @instr.Inst(opcode)
    remainder_instruction.add_def_fixed(destination, { index: 2, class: Int })
    remainder_instruction.add_use_fixed(lhs, { index: 0, class: Int })
    remainder_instruction.add_use_fixed(rhs, {
      index: isa.scratch_reg_1_index(),
      class: Int,
    })
    remainder_instruction.add_def({ reg: Physical({ index: 0, class: Int }) })
    remainder_instruction.add_def({ reg: Physical({ index: 2, class: Int }) })
    block.add_inst(remainder_instruction)
    return
  }
  let quotient = legacy_function.new_vreg(Int)
  let division = @instr.Inst(if signed { SDiv(is_64) } else { UDiv(is_64) })
  division.add_def(legacy_def(quotient))
  division.add_use(lhs)
  division.add_use(rhs)
  block.add_inst(division)
  if is_64 {
    let remainder_instruction = @instr.Inst(Msub)
    remainder_instruction.add_def(destination)
    remainder_instruction.add_use(lhs)
    remainder_instruction.add_use(Virtual(quotient))
    remainder_instruction.add_use(rhs)
    block.add_inst(remainder_instruction)
  } else {
    let product = legacy_function.new_vreg(Int)
    let multiply = @instr.Inst(Mul(false))
    multiply.add_def(legacy_def(product))
    multiply.add_use(Virtual(quotient))
    multiply.add_use(rhs)
    block.add_inst(multiply)
    let subtract = @instr.Inst(Sub(false))
    subtract.add_def(destination)
    subtract.add_use(lhs)
    subtract.add_use(Virtual(product))
    block.add_inst(subtract)
  }
}

///|
fn append_semantic_rotate_left(
  isa : @isa.ISA,
  legacy_function : @machv.Function,
  block : @block.Block,
  operands : Array[@abi.Reg],
  definitions : Array[@abi.Writable],
  is_64 : Bool,
  constant_amount : Int64?,
) -> Unit raise SemanticLegacyAdapterError {
  if operands.length() != 2 || definitions.length() != 1 {
    raise UnsupportedOperation(
      message="rotate-left requires two operands and one result",
    )
  }
  if constant_amount is Some(amount) {
    let mask = if is_64 { 63 } else { 31 }
    let left_amount = amount.to_int() & mask
    if left_amount == 0 {
      let copy = @instr.Inst(Move)
      copy.add_def(definitions[0])
      copy.add_use(operands[0])
      block.add_inst(copy)
      return
    }
    let width = if is_64 { 64 } else { 32 }
    let rotate = @instr.Inst(RotrImm((width - left_amount) & mask, is_64))
    rotate.add_def(definitions[0])
    rotate.add_use(operands[0])
    block.add_inst(rotate)
    return
  }
  let negated_amount = legacy_function.new_vreg(Int)
  let negate = @instr.Inst(Sub(is_64))
  negate.add_def(legacy_def(negated_amount))
  if isa is AArch64 {
    negate.add_use(Physical({ index: 31, class: Int }))
  } else {
    let zero = legacy_function.new_vreg(Int)
    let load_zero = @instr.Inst(LoadConst(0L))
    load_zero.add_def(legacy_def(zero))
    block.add_inst(load_zero)
    negate.add_use(Virtual(zero))
  }
  negate.add_use(operands[1])
  block.add_inst(negate)
  let rotate = @instr.Inst(Rotr(is_64))
  if isa is AMD64 {
    let data_register : @abi.PReg = {
      index: isa.scratch_reg_1_index(),
      class: Int,
    }
    rotate.add_def_fixed(definitions[0], data_register)
    rotate.add_use_fixed(operands[0], data_register)
    rotate.add_use_fixed(Virtual(negated_amount), { index: 1, class: Int })
  } else {
    rotate.add_def(definitions[0])
    rotate.add_use(operands[0])
    rotate.add_use(Virtual(negated_amount))
  }
  block.add_inst(rotate)
}

///|
fn append_semantic_shift_or_rotate_right(
  isa : @isa.ISA,
  block : @block.Block,
  operation : @semantic_machv.IntBinaryOp,
  operands : Array[@abi.Reg],
  definitions : Array[@abi.Writable],
  is_64 : Bool,
  constant_amount : Int64?,
) -> Unit raise SemanticLegacyAdapterError {
  if operands.length() != 2 || definitions.length() != 1 {
    raise UnsupportedOperation(
      message="shift or rotate requires two operands and one result",
    )
  }
  if constant_amount is Some(amount) {
    let shift = amount.to_int() & (if is_64 { 63 } else { 31 })
    let opcode : @instr.Opcode = match operation {
      ShiftLeft => ShlImm(shift, is_64)
      SignedShiftRight => AShrImm(shift, is_64)
      UnsignedShiftRight => LShrImm(shift, is_64)
      RotateRight => RotrImm(shift, is_64)
      _ =>
        raise UnsupportedOperation(
          message="operation is not a shift or rotate-right",
        )
    }
    let instruction = @instr.Inst(opcode)
    instruction.add_def(definitions[0])
    instruction.add_use(operands[0])
    block.add_inst(instruction)
    return
  }
  let opcode : @instr.Opcode = match operation {
    ShiftLeft => Shl(is_64)
    SignedShiftRight => AShr(is_64)
    UnsignedShiftRight => LShr(is_64)
    RotateRight => Rotr(is_64)
    _ =>
      raise UnsupportedOperation(
        message="operation is not a shift or rotate-right",
      )
  }
  let instruction = @instr.Inst(opcode)
  if isa is AMD64 {
    let data_register : @abi.PReg = {
      index: isa.scratch_reg_1_index(),
      class: Int,
    }
    instruction.add_def_fixed(definitions[0], data_register)
    instruction.add_use_fixed(operands[0], data_register)
    instruction.add_use_fixed(operands[1], { index: 1, class: Int })
  } else {
    instruction.add_def(definitions[0])
    instruction.add_use(operands[0])
    instruction.add_use(operands[1])
  }
  block.add_inst(instruction)
}

///|
fn append_semantic_count_trailing_zeros(
  legacy_function : @machv.Function,
  block : @block.Block,
  operands : Array[@abi.Reg],
  definitions : Array[@abi.Writable],
  is_64 : Bool,
) -> Unit raise SemanticLegacyAdapterError {
  if operands.length() != 1 || definitions.length() != 1 {
    raise UnsupportedOperation(
      message="count-trailing-zeros requires one operand and one result",
    )
  }
  let reversed = legacy_function.new_vreg(Int)
  let reverse = @instr.Inst(Rbit(is_64))
  reverse.add_def(legacy_def(reversed))
  reverse.add_use(operands[0])
  block.add_inst(reverse)
  let count = @instr.Inst(Clz(is_64))
  count.add_def(definitions[0])
  count.add_use(Virtual(reversed))
  block.add_inst(count)
}

///|
fn append_semantic_high_multiply(
  isa : @isa.ISA,
  block : @block.Block,
  signedness : @semantic_machv.Signedness,
  operands : Array[@abi.Reg],
  definitions : Array[@abi.Writable],
) -> Unit raise SemanticLegacyAdapterError {
  if operands.length() != 2 || definitions.length() != 1 {
    raise UnsupportedOperation(
      message="high multiply requires two operands and one result",
    )
  }
  let multiply = @instr.Inst(if signedness is Signed { Smulh } else { Umulh })
  if isa is AMD64 {
    multiply.add_def_fixed(definitions[0], { index: 2, class: Int })
    multiply.add_def({ reg: Physical({ index: 0, class: Int }) })
  } else {
    multiply.add_def(definitions[0])
  }
  multiply.add_use(operands[0])
  multiply.add_use(operands[1])
  block.add_inst(multiply)
}

///|
fn append_semantic_float_to_int(
  isa : @isa.ISA,
  legacy_function : @machv.Function,
  block : @block.Block,
  source_type : @semantic_machv.FloatType,
  result_type : @semantic_machv.IntegerType,
  signedness : @semantic_machv.Signedness,
  mode : @semantic_machv.ConversionMode,
  operands : Array[@abi.Reg],
  definitions : Array[@abi.Writable],
  trap_payload : (@semantic_machv.TrapReason) -> Int,
) -> Unit raise SemanticLegacyAdapterError {
  if operands.length() != 1 || definitions.length() != 1 {
    raise UnsupportedOperation(
      message="float-to-int requires one operand and one result",
    )
  }
  let is_f32 = source_type is F32
  let is_i64 = result_type is I64
  let signed = signedness is Signed
  if mode is Saturating {
    let convert = @instr.Inst(FcvtToInt(is_f32, is_i64, signed))
    convert.add_def(definitions[0])
    convert.add_use(operands[0])
    block.add_inst(convert)
    return
  }
  let compare_nan = @instr.Inst(FpuCmp(is_f32))
  compare_nan.add_use(operands[0])
  compare_nan.add_use(operands[0])
  block.add_inst(compare_nan)
  block.add_inst(
    Inst(
      TrapIf(
        if isa is AMD64 {
          Ps
        } else {
          Vs
        },
        trap_payload(InvalidConversionToInteger),
      ),
    ),
  )
  let (minimum_bits, maximum_bits, inclusive_minimum) = semantic_float_to_int_bounds(
    is_f32, is_i64, signed,
  )
  let float_class = if is_f32 { @abi.RegClass::Float32 } else { Float64 }
  let minimum = legacy_function.new_vreg(float_class)
  let load_minimum = if is_f32 {
    @instr.Inst(LoadConstF32(minimum_bits.to_int()))
  } else {
    Inst(LoadConstF64(minimum_bits))
  }
  load_minimum.add_def(legacy_def(minimum))
  block.add_inst(load_minimum)
  let compare_minimum = @instr.Inst(FpuCmp(is_f32))
  compare_minimum.add_use(operands[0])
  compare_minimum.add_use(Virtual(minimum))
  block.add_inst(compare_minimum)
  block.add_inst(
    Inst(
      TrapIf(
        if isa is AMD64 {
          if inclusive_minimum {
            Ls
          } else {
            Lo
          }
        } else if inclusive_minimum {
          Le
        } else {
          Lt
        },
        trap_payload(InvalidConversionToInteger),
      ),
    ),
  )
  let maximum = legacy_function.new_vreg(float_class)
  let load_maximum = if is_f32 {
    @instr.Inst(LoadConstF32(maximum_bits.to_int()))
  } else {
    Inst(LoadConstF64(maximum_bits))
  }
  load_maximum.add_def(legacy_def(maximum))
  block.add_inst(load_maximum)
  let compare_maximum = @instr.Inst(FpuCmp(is_f32))
  compare_maximum.add_use(operands[0])
  compare_maximum.add_use(Virtual(maximum))
  block.add_inst(compare_maximum)
  block.add_inst(
    Inst(
      TrapIf(
        if isa is AMD64 {
          Hs
        } else {
          Ge
        },
        trap_payload(InvalidConversionToInteger),
      ),
    ),
  )
  let convert = @instr.Inst(FcvtToInt(is_f32, is_i64, signed))
  convert.add_def(definitions[0])
  convert.add_use(operands[0])
  block.add_inst(convert)
}

///|
fn add_adapter_call_clobbers(
  isa : @isa.ISA,
  call : @instr.Inst,
  foreign : Bool,
) -> Unit {
  for register in isa.call_clobbered_gprs() {
    call.add_def({ reg: Physical(register) })
  }
  let float_registers = if foreign {
    isa.call_clobbered_fprs()
  } else {
    isa.call_clobbered_fprs_same_abi()
  }
  for register in float_registers {
    call.add_def({ reg: Physical(register) })
  }
}

///|
fn adapter_c_argument_registers(isa : @isa.ISA) -> Array[Int] {
  match isa {
    AArch64 => [0, 1, 2, 3, 4, 5, 6, 7]
    AMD64 => [7, 6, 2, 1, 8, 9]
  }
}

///|
fn call_result_vregs(
  definitions : Array[@abi.Writable],
) -> Array[@abi.VReg] raise SemanticLegacyAdapterError {
  let results : Array[@abi.VReg] = []
  for definition in definitions {
    match definition.reg {
      Virtual(result) => results.push(result)
      Physical(_) =>
        raise UnsupportedOperation(
          message="semantic call result mapped to a physical register",
        )
    }
  }
  results
}

///|
fn emit_platform_call(
  isa : @isa.ISA,
  legacy_function : @machv.Function,
  block : @block.Block,
  call : @semantic_machv.SemanticCall,
  operands : Array[@abi.Reg],
  definitions : Array[@abi.Writable],
) -> Unit raise SemanticLegacyAdapterError {
  let symbol = match call.callee {
    External(symbol) => @instr.ExternalName(symbol.name)
    _ =>
      raise UnsupportedOperation(
        message="platform call requires a known external symbol",
      )
  }
  for operand in operands {
    match operand {
      Virtual(vreg) =>
        if vreg.class != Int {
          raise UnsupportedOperation(
            message="legacy platform call requires integer carriers",
          )
        }
      Physical(_) =>
        raise UnsupportedOperation(
          message="semantic platform argument mapped to a physical register",
        )
    }
  }
  let results = call_result_vregs(definitions)
  if results.length() > 1 || (results.length() == 1 && results[0].class != Int) {
    raise UnsupportedOperation(
      message="legacy platform call supports at most one integer result",
    )
  }
  let argument_registers = adapter_c_argument_registers(isa)
  if operands.length() > argument_registers.length() {
    let overflow_count = operands.length() - argument_registers.length()
    legacy_function.update_max_outgoing_args_size(overflow_count * 8)
    for index in 0..<overflow_count {
      let store = @instr.Inst(StoreToStack(index * 8))
      store.add_use(operands[argument_registers.length() + index])
      block.add_inst(store)
    }
  }
  let instruction = @instr.Inst(
    CallExternal(
      symbol,
      operands.length(),
      results.map(result => result.class),
      Foreign,
    ),
  )
  let register_argument_count = if operands.length() <
    argument_registers.length() {
    operands.length()
  } else {
    argument_registers.length()
  }
  for index in 0..<register_argument_count {
    instruction.add_use_fixed(operands[index], {
      index: argument_registers[index],
      class: Int,
    })
  }
  if results is [result] {
    instruction.add_def_fixed(legacy_def(result), { index: 0, class: Int })
  }
  add_adapter_call_clobbers(isa, instruction, true)
  block.add_inst(instruction)
}

///|
fn classify_internal_arguments(
  arguments : Array[@abi.Reg],
) -> (Array[@abi.VReg], Array[@abi.VReg]) raise SemanticLegacyAdapterError {
  let integers : Array[@abi.VReg] = []
  let floats : Array[@abi.VReg] = []
  for argument in arguments {
    match argument {
      Virtual(vreg) =>
        match vreg.class {
          Int => integers.push(vreg)
          Float32 | Float64 | Vector => floats.push(vreg)
        }
      Physical(_) =>
        raise UnsupportedOperation(
          message="semantic internal argument mapped to a physical register",
        )
    }
  }
  (integers, floats)
}

///|
fn adapter_reg_slice(values : Array[@abi.Reg], start : Int) -> Array[@abi.Reg] {
  let result : Array[@abi.Reg] = []
  for index in start..<values.length() {
    result.push(values[index])
  }
  result
}

///|
fn emit_internal_overflow_arguments(
  legacy_function : @machv.Function,
  block : @block.Block,
  call_conv : @abi.CallConventionLayout,
  integer_arguments : Array[@abi.VReg],
  float_arguments : Array[@abi.VReg],
) -> Int {
  let integer_overflow = if integer_arguments.length() >
    call_conv.user_arg_gprs.length() {
    integer_arguments.length() - call_conv.user_arg_gprs.length()
  } else {
    0
  }
  let float_overflow_classes : Array[@abi.RegClass] = []
  for index in call_conv.arg_fprs.length()..<float_arguments.length() {
    float_overflow_classes.push(float_arguments[index].class)
  }
  let (integer_offsets, float_offsets, total_bytes) = call_conv.layout_overflow_stack(
    integer_overflow, float_overflow_classes,
  )
  legacy_function.update_max_outgoing_args_size(total_bytes)
  for index in 0..<integer_overflow {
    let store = @instr.Inst(StoreToStack(integer_offsets[index]))
    store.add_use(
      Virtual(integer_arguments[call_conv.user_arg_gprs.length() + index]),
    )
    block.add_inst(store)
  }
  for index in 0..<float_offsets.length() {
    let store = @instr.Inst(StoreToStack(float_offsets[index]))
    store.add_use(Virtual(float_arguments[call_conv.arg_fprs.length() + index]))
    block.add_inst(store)
  }
  total_bytes
}

///|
fn emit_internal_call(
  isa : @isa.ISA,
  embedding_abi : @abi.EmbeddingABI,
  legacy_function : @machv.Function,
  block : @block.Block,
  call : @semantic_machv.SemanticCall,
  operands : Array[@abi.Reg],
  definitions : Array[@abi.Writable],
  code_symbol_resolver : ((@semantic_machv.CodeSymbol) -> @instr.CodeSymbol)?,
) -> Unit raise SemanticLegacyAdapterError {
  let indirect = call.callee is Indirect
  let (callee, arguments) = if indirect {
    if operands.length() < 2 {
      raise UnsupportedOperation(
        message="indirect call requires callee and context operands",
      )
    }
    (Some(operands[0]), adapter_reg_slice(operands, 1))
  } else {
    (None, operands.copy())
  }
  if arguments.is_empty() {
    raise UnsupportedOperation(
      message="internal call requires an execution environment",
    )
  }
  let context = arguments[0]
  let user_arguments = adapter_reg_slice(arguments, 1)
  let (integer_arguments, float_arguments) = classify_internal_arguments(
    user_arguments,
  )
  let call_conv = embedding_abi.call_conv
  emit_internal_overflow_arguments(
    legacy_function, block, call_conv, integer_arguments, float_arguments,
  )
  |> ignore
  let results = call_result_vregs(definitions)
  let instruction : @instr.Inst = match call.callee {
    Internal(symbol) => {
      let resolver = match code_symbol_resolver {
        Some(resolver) => resolver
        None =>
          raise UnsupportedOperation(
            message="direct internal call requires a code-symbol resolver",
          )
      }
      Inst(
        CallDirect(
          resolver(symbol),
          user_arguments.length(),
          results.map(result => result.class),
          Internal,
        ),
      )
    }
    Indirect =>
      Inst(
        CallPtr(
          user_arguments.length(),
          results.map(result => result.class),
          Internal,
        ),
      )
    External(_) =>
      raise UnsupportedOperation(
        message="internal protocol cannot target an external symbol",
      )
  }
  if callee is Some(callee) {
    instruction.add_use_fixed(callee, {
      index: isa.scratch_reg_2_index(),
      class: Int,
    })
  }
  instruction.add_use_fixed(context, call_conv.context_arg)
  let integer_register_count = if integer_arguments.length() <
    call_conv.user_arg_gprs.length() {
    integer_arguments.length()
  } else {
    call_conv.user_arg_gprs.length()
  }
  for index in 0..<integer_register_count {
    instruction.add_use_fixed(
      Virtual(integer_arguments[index]),
      call_conv.user_arg_gprs[index],
    )
  }
  let float_register_count = if float_arguments.length() <
    call_conv.arg_fprs.length() {
    float_arguments.length()
  } else {
    call_conv.arg_fprs.length()
  }
  for index in 0..<float_register_count {
    instruction.add_use_fixed(Virtual(float_arguments[index]), {
      index: call_conv.arg_fprs[index].index,
      class: float_arguments[index].class,
    })
  }
  let mut integer_result_index = 0
  let mut float_result_index = 0
  for result in results {
    match result.class {
      Int => {
        if integer_result_index >= call_conv.ret_gprs.length() {
          raise UnsupportedOperation(
            message="internal call requires an extra-results area",
          )
        }
        instruction.add_def_fixed(legacy_def(result), {
          index: call_conv.ret_gprs[integer_result_index].index,
          class: Int,
        })
        integer_result_index += 1
      }
      Float32 | Float64 | Vector => {
        if float_result_index >= call_conv.ret_fprs.length() {
          raise UnsupportedOperation(
            message="internal call requires an extra-results area",
          )
        }
        instruction.add_def_fixed(legacy_def(result), {
          index: call_conv.ret_fprs[float_result_index].index,
          class: result.class,
        })
        float_result_index += 1
      }
    }
  }
  add_adapter_call_clobbers(isa, instruction, false)
  block.add_inst(instruction)
}

///|
fn emit_internal_tail_call(
  isa : @isa.ISA,
  embedding_abi : @abi.EmbeddingABI,
  legacy_function : @machv.Function,
  block : @block.Block,
  call : @semantic_machv.SemanticCall,
  operands : Array[@abi.Reg],
  code_symbol_resolver : ((@semantic_machv.CodeSymbol) -> @instr.CodeSymbol)?,
) -> Unit raise SemanticLegacyAdapterError {
  let indirect = call.callee is Indirect
  let (callee, arguments) = if indirect {
    if operands.length() < 2 {
      raise UnsupportedOperation(
        message="indirect tail call requires callee and context operands",
      )
    }
    (operands[0], adapter_reg_slice(operands, 1))
  } else {
    let resolver = match code_symbol_resolver {
      Some(resolver) => resolver
      None =>
        raise UnsupportedOperation(
          message="direct internal tail call requires a code-symbol resolver",
        )
    }
    let symbol = match call.callee {
      Internal(symbol) => symbol
      _ =>
        raise UnsupportedOperation(
          message="internal tail call requires an internal or indirect callee",
        )
    }
    let target = legacy_function.new_vreg(Int)
    let load = @instr.Inst(LoadCodeAddr(resolver(symbol)))
    load.add_def(legacy_def(target))
    block.add_inst(load)
    (Virtual(target), operands.copy())
  }
  if arguments.is_empty() {
    raise UnsupportedOperation(
      message="internal tail call requires an execution environment",
    )
  }
  let context = arguments[0]
  let user_arguments = adapter_reg_slice(arguments, 1)
  let (integer_arguments, float_arguments) = classify_internal_arguments(
    user_arguments,
  )
  let call_conv = embedding_abi.call_conv
  let stack_arg_bytes = emit_internal_overflow_arguments(
    legacy_function, block, call_conv, integer_arguments, float_arguments,
  )
  let instruction = @instr.Inst(ReturnCallIndirect(stack_arg_bytes, 0))
  instruction.add_use_fixed(callee, {
    index: isa.scratch_reg_2_index(),
    class: Int,
  })
  instruction.add_use_fixed(context, call_conv.context_arg)
  let integer_register_count = if integer_arguments.length() <
    call_conv.user_arg_gprs.length() {
    integer_arguments.length()
  } else {
    call_conv.user_arg_gprs.length()
  }
  for index in 0..<integer_register_count {
    instruction.add_use_fixed(
      Virtual(integer_arguments[index]),
      call_conv.user_arg_gprs[index],
    )
  }
  let float_register_count = if float_arguments.length() <
    call_conv.arg_fprs.length() {
    float_arguments.length()
  } else {
    call_conv.arg_fprs.length()
  }
  for index in 0..<float_register_count {
    instruction.add_use_fixed(Virtual(float_arguments[index]), {
      index: call_conv.arg_fprs[index].index,
      class: float_arguments[index].class,
    })
  }
  add_adapter_call_clobbers(isa, instruction, false)
  block.add_inst(instruction)
}

///|
fn call_requires_hidden_safepoint_id(
  call : @semantic_machv.SemanticCall,
  requires_hidden_safepoint_id : ((@semantic_machv.ExternalSymbol) -> Bool)?,
) -> Bool {
  match (call.callee, requires_hidden_safepoint_id) {
    (External(symbol), Some(requires_hidden_safepoint_id)) =>
      requires_hidden_safepoint_id(symbol)
    _ => false
  }
}

///|
fn call_root_scope_context(
  call : @semantic_machv.SemanticCall,
  operands : Array[@abi.Reg],
) -> @abi.Reg raise SemanticLegacyAdapterError {
  let index = match call.protocol {
    Internal => if call.callee is Indirect { 1 } else { 0 }
    Platform => {
      if call.signature.params.is_empty() || call.signature.params[0] != Ptr64 {
        raise UnsupportedOperation(
          message="Platform root scope requires a leading ptr64 execution environment",
        )
      }
      0
    }
  }
  if operands.length() <= index {
    raise UnsupportedOperation(
      message="call is missing its execution environment",
    )
  }
  operands[index]
}

///|
fn hidden_safepoint_root_count(
  function : @semantic_machv.Function,
  call : @semantic_machv.SemanticCall,
  semantic_operands : Array[@semantic_machv.Value],
  integer_constants : Array[Int64?],
) -> Int raise SemanticLegacyAdapterError {
  match call.signature.params {
    [Ptr64, I32, I32, I64] => 1
    [Ptr64, I32, Ptr64, I32] => {
      if semantic_operands.length() != 4 {
        raise UnsupportedOperation(
          message="allocation safepoint call has an invalid operand count",
        )
      }
      let count_value = semantic_operands[3]
      let count = match
        integer_constants[function.value_index(count_value).unwrap()] {
        Some(count) => count
        None =>
          raise UnsupportedOperation(
            message="allocation safepoint root count must be a compile-time constant",
          )
      }
      if count < 0L || count > @types.I32_MAX.to_int64() {
        raise UnsupportedOperation(
          message="allocation safepoint root count is outside the i32 range",
        )
      }
      count.to_int()
    }
    _ =>
      raise UnsupportedOperation(
        message="hidden safepoint ID call has an unsupported allocation ABI",
      )
  }
}

///|
fn append_caller_root_scope_push(
  isa : @isa.ISA,
  legacy_function : @machv.Function,
  block : @block.Block,
  context : @abi.Reg,
  live_gc_roots : Array[@abi.Reg],
  symbol : @semantic_machv.ExternalSymbol,
) -> Unit raise SemanticLegacyAdapterError {
  for index, root in live_gc_roots {
    let store = @instr.Inst(StoreToStack(index * 8))
    store.add_use(root)
    block.add_inst(store)
  }
  let root_buffer = legacy_function.new_vreg(Int)
  let load_buffer = @instr.Inst(LoadSP)
  load_buffer.add_def(legacy_def(root_buffer))
  block.add_inst(load_buffer)
  let root_count = legacy_function.new_vreg(Int)
  let load_count = @instr.Inst(LoadConst(live_gc_roots.length().to_int64()))
  load_count.add_def(legacy_def(root_count))
  block.add_inst(load_count)
  emit_platform_call(
    isa,
    legacy_function,
    block,
    @semantic_machv.SemanticCall::new(
      External(symbol),
      @semantic_machv.Signature::new([Ptr64, Ptr64, I32], []),
      Platform,
      @semantic_machv.CallBehavior::new(ReadWrite, true, false, false, false),
    ),
    [context, Virtual(root_buffer), Virtual(root_count)],
    [],
  )
}

///|
fn append_caller_root_scope_pop(
  isa : @isa.ISA,
  legacy_function : @machv.Function,
  block : @block.Block,
  context : @abi.Reg,
  symbol : @semantic_machv.ExternalSymbol,
) -> Unit raise SemanticLegacyAdapterError {
  emit_platform_call(
    isa,
    legacy_function,
    block,
    @semantic_machv.SemanticCall::new(
      External(symbol),
      @semantic_machv.Signature::new([Ptr64], []),
      Platform,
      @semantic_machv.CallBehavior::new(ReadWrite, true, false, false, false),
    ),
    [context],
    [],
  )
}

///|
fn append_semantic_call(
  isa : @isa.ISA,
  embedding_abi : @abi.EmbeddingABI?,
  function : @semantic_machv.Function,
  legacy_function : @machv.Function,
  block : @block.Block,
  call : @semantic_machv.SemanticCall,
  semantic_operands : Array[@semantic_machv.Value],
  operands : Array[@abi.Reg],
  definitions : Array[@abi.Writable],
  live_gc_roots : Array[@abi.Reg],
  integer_constants : Array[Int64?],
  requires_hidden_safepoint_id : ((@semantic_machv.ExternalSymbol) -> Bool)?,
  caller_root_scope_symbols : (
    @semantic_machv.ExternalSymbol,
    @semantic_machv.ExternalSymbol,
  )?,
  code_symbol_resolver : ((@semantic_machv.CodeSymbol) -> @instr.CodeSymbol)?,
) -> Unit raise SemanticLegacyAdapterError {
  let hidden_safepoint = call_requires_hidden_safepoint_id(
    call, requires_hidden_safepoint_id,
  )
  let mut root_scope_context : @abi.Reg? = None
  if !live_gc_roots.is_empty() {
    let (push_symbol, _) = match caller_root_scope_symbols {
      Some(symbols) => symbols
      None =>
        raise UnsupportedOperation(
          message="precise GC roots require caller root-scope symbols",
        )
    }
    let context = call_root_scope_context(call, operands)
    append_caller_root_scope_push(
      isa, legacy_function, block, context, live_gc_roots, push_symbol,
    )
    root_scope_context = Some(context)
  }
  if hidden_safepoint {
    if call.protocol != Platform || !call.behavior.gc_safepoint {
      raise UnsupportedOperation(
        message="hidden safepoint ID requires a Platform GC-safepoint call",
      )
    }
    let allocation_root_count = hidden_safepoint_root_count(
      function, call, semantic_operands, integer_constants,
    )
    let safepoint = legacy_function.new_vreg(Int)
    let load = @instr.Inst(LoadSafepointId(allocation_root_count))
    load.add_def(legacy_def(safepoint))
    block.add_inst(load)
    let augmented_operands = operands.copy()
    augmented_operands.push(Virtual(safepoint))
    emit_platform_call(
      isa, legacy_function, block, call, augmented_operands, definitions,
    )
    if root_scope_context is Some(context) {
      let (_, pop_symbol) = caller_root_scope_symbols.unwrap()
      append_caller_root_scope_pop(
        isa, legacy_function, block, context, pop_symbol,
      )
    }
    return
  }
  if !live_gc_roots.is_empty() {
    match call.protocol {
      Platform =>
        emit_platform_call(
          isa, legacy_function, block, call, operands, definitions,
        )
      Internal => {
        let embedding_abi = match embedding_abi {
          Some(embedding_abi) => embedding_abi
          None =>
            raise UnsupportedOperation(
              message="internal call requires an embedding ABI",
            )
        }
        emit_internal_call(
          isa, embedding_abi, legacy_function, block, call, operands, definitions,
          code_symbol_resolver,
        )
      }
    }
    let context = root_scope_context.unwrap()
    let (_, pop_symbol) = caller_root_scope_symbols.unwrap()
    append_caller_root_scope_pop(
      isa, legacy_function, block, context, pop_symbol,
    )
    return
  }
  match call.protocol {
    Platform =>
      emit_platform_call(
        isa, legacy_function, block, call, operands, definitions,
      )
    Internal => {
      let embedding_abi = match embedding_abi {
        Some(embedding_abi) => embedding_abi
        None =>
          raise UnsupportedOperation(
            message="internal call requires an embedding ABI",
          )
      }
      emit_internal_call(
        isa, embedding_abi, legacy_function, block, call, operands, definitions,
        code_symbol_resolver,
      )
    }
  }
}

///|
fn semantic_call_overflow_bytes(
  function : @semantic_machv.Function,
  call : @semantic_machv.SemanticCall,
  operands : Array[@semantic_machv.Value],
  isa : @isa.ISA,
  embedding_abi : @abi.EmbeddingABI?,
  hidden_safepoint : Bool,
) -> Int raise SemanticLegacyAdapterError {
  if call.protocol is Platform {
    let register_count = adapter_c_argument_registers(isa).length()
    let argument_count = operands.length() +
      (if hidden_safepoint { 1 } else { 0 })
    return if argument_count > register_count {
      (argument_count - register_count) * 8
    } else {
      0
    }
  }
  let call_conv = match embedding_abi {
    Some(embedding_abi) => embedding_abi.call_conv
    None =>
      raise UnsupportedOperation(
        message="internal call requires an embedding ABI",
      )
  }
  let argument_start = if call.callee is Indirect { 2 } else { 1 }
  if operands.length() < argument_start {
    raise UnsupportedOperation(
      message="internal call is missing callee or context operands",
    )
  }
  let mut integer_count = 0
  let float_classes : Array[@abi.RegClass] = []
  for index in argument_start..<operands.length() {
    let ty = function.value_type(operands[index]).unwrap()
    match legacy_reg_class(ty) {
      Int => integer_count += 1
      class => float_classes.push(class)
    }
  }
  let integer_overflow = if integer_count > call_conv.user_arg_gprs.length() {
    integer_count - call_conv.user_arg_gprs.length()
  } else {
    0
  }
  let float_overflow_classes : Array[@abi.RegClass] = []
  for index in call_conv.arg_fprs.length()..<float_classes.length() {
    float_overflow_classes.push(float_classes[index])
  }
  let (_, _, total_bytes) = call_conv.layout_overflow_stack(
    integer_overflow, float_overflow_classes,
  )
  total_bytes
}

///|
fn semantic_call_temporary_stack_bytes(
  function : @semantic_machv.Function,
  call : @semantic_machv.SemanticCall,
  operands : Array[@semantic_machv.Value],
  root_count : Int,
  isa : @isa.ISA,
  embedding_abi : @abi.EmbeddingABI?,
  requires_hidden_safepoint_id : ((@semantic_machv.ExternalSymbol) -> Bool)?,
  caller_root_scope_symbols : (
    @semantic_machv.ExternalSymbol,
    @semantic_machv.ExternalSymbol,
  )?,
) -> Int raise SemanticLegacyAdapterError {
  let hidden_safepoint = call_requires_hidden_safepoint_id(
    call, requires_hidden_safepoint_id,
  )
  let overflow_bytes = semantic_call_overflow_bytes(
    function, call, operands, isa, embedding_abi, hidden_safepoint,
  )
  if !hidden_safepoint && root_count == 0 {
    return overflow_bytes
  }
  let root_bytes = root_count * 8
  if root_count > 0 {
    if caller_root_scope_symbols is None {
      raise UnsupportedOperation(
        message="precise GC roots require caller root-scope symbols",
      )
    }
  }
  if root_bytes > overflow_bytes {
    root_bytes
  } else {
    overflow_bytes
  }
}

///|
fn maximum_semantic_temporary_stack_bytes(
  function : @semantic_machv.Function,
  isa : @isa.ISA,
  embedding_abi : @abi.EmbeddingABI?,
  requires_hidden_safepoint_id : ((@semantic_machv.ExternalSymbol) -> Bool)?,
  caller_root_scope_symbols : (
    @semantic_machv.ExternalSymbol,
    @semantic_machv.ExternalSymbol,
  )?,
) -> Int raise SemanticLegacyAdapterError {
  let mut maximum = 0
  for block in function.blocks() {
    for instruction in function.block_instructions(block) {
      if function.instruction_operation(instruction) is Some(Call(call)) {
        let bytes = semantic_call_temporary_stack_bytes(
          function,
          call,
          function.instruction_operands(instruction),
          function.instruction_metadata(instruction).unwrap().live_gc_roots.length(),
          isa,
          embedding_abi,
          requires_hidden_safepoint_id,
          caller_root_scope_symbols,
        )
        if bytes > maximum {
          maximum = bytes
        }
      }
    }
    let terminator = function.block_terminator(block).unwrap()
    match terminator.kind {
      TailCall(call, operands) => {
        let bytes = semantic_call_temporary_stack_bytes(
          function, call, operands, 0, isa, embedding_abi, requires_hidden_safepoint_id,
          caller_root_scope_symbols,
        )
        if bytes > maximum {
          maximum = bytes
        }
      }
      NoReturnCall(call, operands) => {
        let bytes = semantic_call_temporary_stack_bytes(
          function,
          call,
          operands,
          terminator.metadata.live_gc_roots.length(),
          isa,
          embedding_abi,
          requires_hidden_safepoint_id,
          caller_root_scope_symbols,
        )
        if bytes > maximum {
          maximum = bytes
        }
      }
      _ => ()
    }
  }
  maximum
}

///|
fn plan_semantic_stack_objects(
  function : @semantic_machv.Function,
  base : Int,
) -> (Array[@semantic_machv.StackObject], Array[Int], Int) {
  let objects = function.stack_objects()
  let offsets : Array[Int] = []
  let mut cursor = base
  for object in objects {
    let alignment = function.stack_object_alignment(object).unwrap()
    cursor = @abi.align_up(cursor, alignment)
    offsets.push(cursor)
    cursor += function.stack_object_size(object).unwrap()
  }
  (objects, offsets, @abi.align_up(cursor, 16))
}

///|
fn semantic_stack_object_offset(
  objects : Array[@semantic_machv.StackObject],
  offsets : Array[Int],
  object : @semantic_machv.StackObject,
) -> Int raise SemanticLegacyAdapterError {
  for index, candidate in objects {
    if candidate == object {
      return offsets[index]
    }
  }
  raise UnsupportedOperation(message="stack object is not function-owned")
}

///|
fn append_stack_address(
  legacy_function : @machv.Function,
  block : @block.Block,
  definitions : Array[@abi.Writable],
  offset : Int,
) -> Unit raise SemanticLegacyAdapterError {
  if definitions.length() != 1 {
    raise UnsupportedOperation(
      message="stack address must have exactly one result",
    )
  }
  if offset == 0 {
    let load = @instr.Inst(LoadSP)
    load.add_def(definitions[0])
    block.add_inst(load)
    return
  }
  let base = legacy_function.new_vreg(Int)
  let load = @instr.Inst(LoadSP)
  load.add_def(legacy_def(base))
  block.add_inst(load)
  if offset <= 4095 || ((offset & 0xFFF) == 0 && offset >> 12 <= 4095) {
    let add = @instr.Inst(AddImm(offset, true))
    add.add_def(definitions[0])
    add.add_use(Virtual(base))
    block.add_inst(add)
    return
  }
  let immediate = legacy_function.new_vreg(Int)
  let materialize = @instr.Inst(LoadConst(offset.to_int64()))
  materialize.add_def(legacy_def(immediate))
  block.add_inst(materialize)
  let add = @instr.Inst(Add(true))
  add.add_def(definitions[0])
  add.add_use(Virtual(base))
  add.add_use(Virtual(immediate))
  block.add_inst(add)
}

///|
fn append_environment_field(
  legacy_function : @machv.Function,
  block : @block.Block,
  operands : Array[@abi.Reg],
  definitions : Array[@abi.Writable],
  field : @semantic_machv.EnvironmentField,
  offsets : Array[Int],
) -> Unit raise SemanticLegacyAdapterError {
  if operands.length() != 1 || definitions.length() != 1 {
    raise UnsupportedOperation(
      message="environment field requires one base and one result",
    )
  }
  if offsets.is_empty() {
    raise UnsupportedOperation(
      message="environment field access path must not be empty",
    )
  }
  let mut base = operands[0]
  for index, offset in offsets {
    let last = index == offsets.length() - 1
    let destination = if last {
      definitions[0]
    } else {
      legacy_def(legacy_function.new_vreg(Int))
    }
    let load = @instr.Inst(
      Load(
        if last {
          legacy_memory_type(field.value_type)
        } else {
          I64
        },
        offset,
      ),
    )
    load.add_def(destination)
    load.add_use(base)
    block.add_inst(load)
    base = destination.reg
  }
}

///|
fn append_semantic_instruction(
  isa : @isa.ISA,
  embedding_abi : @abi.EmbeddingABI?,
  function : @semantic_machv.Function,
  legacy_block : @block.Block,
  instruction : @semantic_machv.Instruction,
  values : Array[@abi.VReg?],
  integer_constants : Array[Int64?],
  legacy_function : @machv.Function,
  stack_objects : Array[@semantic_machv.StackObject],
  stack_offsets : Array[Int],
  trap_payload : (@semantic_machv.TrapReason) -> Int,
  requires_hidden_safepoint_id : ((@semantic_machv.ExternalSymbol) -> Bool)?,
  caller_root_scope_symbols : (
    @semantic_machv.ExternalSymbol,
    @semantic_machv.ExternalSymbol,
  )?,
  environment_field_path : ((@semantic_machv.EnvironmentField) -> Array[Int]?)?,
  code_symbol_resolver : ((@semantic_machv.CodeSymbol) -> @instr.CodeSymbol)?,
) -> Unit raise SemanticLegacyAdapterError {
  let operands : Array[@abi.Reg] = []
  for operand in function.instruction_operands(instruction) {
    operands.push(legacy_use(require_legacy_value(function, values, operand)))
  }
  let semantic_results = function.instruction_results(instruction)
  let definitions : Array[@abi.Writable] = []
  for result in semantic_results {
    let index = function.value_index(result).unwrap()
    let mapped = match values[index] {
      Some(mapped) => mapped
      None => raise MissingValue(value_id=index)
    }
    definitions.push(legacy_def(mapped))
  }
  let operation = function.instruction_operation(instruction).unwrap()
  if semantic_results is [result] {
    let result_index = function.value_index(result).unwrap()
    integer_constants[result_index] = match operation {
      I32Const(bits) => Some(bits.reinterpret_as_int().to_int64() & 0xFFFFFFFFL)
      I64Const(bits) => Some(bits.reinterpret_as_int64())
      Copy =>
        match function.instruction_operands(instruction) {
          [source] => integer_constants[function.value_index(source).unwrap()]
          _ => None
        }
      _ => None
    }
  }
  if operation is EnvironmentField(field) {
    let offsets = match environment_field_path {
      Some(environment_field_path) =>
        match environment_field_path(field) {
          Some(offsets) => offsets
          None =>
            raise UnsupportedOperation(
              message="embedding did not resolve environment field '\{field.name}'",
            )
        }
      None =>
        raise UnsupportedOperation(
          message="environment field requires an embedding resolver",
        )
    }
    append_environment_field(
      legacy_function, legacy_block, operands, definitions, field, offsets,
    )
    return
  }
  if operation is StackAddress(object) {
    append_stack_address(
      legacy_function,
      legacy_block,
      definitions,
      semantic_stack_object_offset(stack_objects, stack_offsets, object),
    )
    return
  }
  if operation is Call(call) {
    let semantic_operands = function.instruction_operands(instruction)
    let live_gc_roots : Array[@abi.Reg] = []
    for
      root in function.instruction_metadata(instruction).unwrap().live_gc_roots {
      live_gc_roots.push(
        legacy_use(require_legacy_value(function, values, root)),
      )
    }
    append_semantic_call(
      isa, embedding_abi, function, legacy_function, legacy_block, call, semantic_operands,
      operands, definitions, live_gc_roots, integer_constants, requires_hidden_safepoint_id,
      caller_root_scope_symbols, code_symbol_resolver,
    )
    return
  }
  if operation is IntBinary(SignedDiv | UnsignedDiv | SignedRem | UnsignedRem) {
    append_semantic_division_or_remainder(
      isa,
      legacy_function,
      legacy_block,
      match operation {
        IntBinary(binary) => binary
        _ => abort("matched integer division above")
      },
      operands,
      definitions,
      semantic_integer_width(function, semantic_results),
      trap_payload,
    )
    return
  }
  if operation is IntBinary(RotateLeft) {
    append_semantic_rotate_left(
      isa,
      legacy_function,
      legacy_block,
      operands,
      definitions,
      semantic_integer_width(function, semantic_results),
      match function.instruction_operands(instruction) {
        [_, amount] => integer_constants[function.value_index(amount).unwrap()]
        _ => None
      },
    )
    return
  }
  if operation
    is IntBinary(
      ShiftLeft
      | SignedShiftRight
      | UnsignedShiftRight
      | RotateRight
    ) {
    append_semantic_shift_or_rotate_right(
      isa,
      legacy_block,
      match operation {
        IntBinary(binary) => binary
        _ => abort("matched integer shift above")
      },
      operands,
      definitions,
      semantic_integer_width(function, semantic_results),
      match function.instruction_operands(instruction) {
        [_, amount] => integer_constants[function.value_index(amount).unwrap()]
        _ => None
      },
    )
    return
  }
  if operation is IntUnary(CountTrailingZeros) {
    append_semantic_count_trailing_zeros(
      legacy_function,
      legacy_block,
      operands,
      definitions,
      semantic_operand_is_64(
        function,
        function.instruction_operands(instruction),
      ),
    )
    return
  }
  if operation is IntHighMultiply(signedness) {
    append_semantic_high_multiply(
      isa, legacy_block, signedness, operands, definitions,
    )
    return
  }
  if operation
    is Convert(FloatToInt(source_type, result_type, signedness, mode)) {
    append_semantic_float_to_int(
      isa, legacy_function, legacy_block, source_type, result_type, signedness, mode,
      operands, definitions, trap_payload,
    )
    return
  }
  if operation is Convert(Bitcast(_, _)) {
    if operands.length() != 1 || definitions.length() != 1 {
      raise UnsupportedOperation(
        message="bitcast requires one operand and one result",
      )
    }
    let source_class = match operands[0] {
      Virtual(register) => register.class
      Physical(register) => register.class
    }
    let result_class = match definitions[0].reg {
      Virtual(register) => register.class
      Physical(register) => register.class
    }
    let bitcast = @instr.Inst(
      if source_class == result_class {
        Move
      } else {
        Bitcast
      },
    )
    bitcast.add_use(operands[0])
    bitcast.add_def(definitions[0])
    legacy_block.add_inst(bitcast)
    return
  }
  if operation is V128Const(low, high) {
    require_semantic_vector_shape(operands, definitions, 0, 1, "v128 constant")
    append_semantic_vector_opcode(
      legacy_function,
      legacy_block,
      LoadConstV128(semantic_v128_bytes(low, high)),
      operands,
      definitions,
      0,
    )
    return
  }
  if operation is Vector(vector_operation) {
    append_semantic_vector_operation(
      legacy_function, legacy_block, vector_operation, operands, definitions,
    )
    return
  }
  if operation is VectorLoad(spec) {
    append_semantic_vector_load(
      legacy_function, legacy_block, spec, operands, definitions,
    )
    return
  }
  if operation is VectorStoreLane(spec) {
    append_semantic_vector_store_lane(
      legacy_function, legacy_block, spec, operands, definitions,
    )
    return
  }
  let opcode = match operation {
    I32Const(bits) =>
      @instr.LoadConst(bits.reinterpret_as_int().to_int64() & 0xFFFFFFFFL)
    I64Const(bits) => LoadConst(bits.reinterpret_as_int64())
    F32Const(bits) => LoadConstF32(bits.reinterpret_as_int())
    F64Const(bits) => LoadConstF64(bits.reinterpret_as_int64())
    NullPtr | NullGcRef => LoadConst(0L)
    Copy => Move
    Select => Select
    PointerOffset => Add(true)
    GcRefAddress | GcRefFromBits => Move
    ReferenceCompare(Equal) => Cmp(Eq, true)
    ReferenceCompare(NotEqual) => Cmp(Ne, true)
    IntUnary(unary) =>
      lower_semantic_int_unary(
        function,
        unary,
        function.instruction_operands(instruction),
      )
    IntBinary(binary) =>
      lower_semantic_int_binary(function, binary, semantic_results)
    IntCompare(comparison) =>
      lower_semantic_int_comparison(
        function,
        comparison,
        function.instruction_operands(instruction),
      )
    FloatUnary(unary) =>
      lower_semantic_float_unary(function, unary, semantic_results)
    FloatBinary(binary) =>
      lower_semantic_float_binary(function, binary, semantic_results)
    FloatCompare(comparison) => lower_semantic_float_comparison(comparison)
    Convert(conversion) => lower_semantic_conversion(conversion)
    Load(spec) => lower_semantic_load(spec)
    Store(spec) => lower_semantic_store(spec)
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
  function : @semantic_machv.Function,
  values : Array[@abi.VReg?],
  edge : @semantic_machv.Edge,
) -> Array[@abi.Reg] raise SemanticLegacyAdapterError {
  edge.arguments.map(argument => {
    legacy_use(require_legacy_value(function, values, argument))
  })
}

///|
fn branch_edge_target(
  function : @semantic_machv.Function,
  values : Array[@abi.VReg?],
  edge : @semantic_machv.Edge,
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
  isa : @isa.ISA,
  embedding_abi : @abi.EmbeddingABI?,
  function : @semantic_machv.Function,
  semantic_block : @semantic_machv.Block,
  legacy_block : @block.Block,
  values : Array[@abi.VReg?],
  block_ids : Array[Int],
  legacy_function : @machv.Function,
  trap_payload : (@semantic_machv.TrapReason) -> Int,
  requires_hidden_safepoint_id : ((@semantic_machv.ExternalSymbol) -> Bool)?,
  caller_root_scope_symbols : (
    @semantic_machv.ExternalSymbol,
    @semantic_machv.ExternalSymbol,
  )?,
  code_symbol_resolver : ((@semantic_machv.CodeSymbol) -> @instr.CodeSymbol)?,
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
    Switch(index, cases, default_edge) => {
      let targets : Array[Int] = []
      for case_index, case in cases {
        if case.bits != case_index.to_uint64() {
          raise UnsupportedOperation(
            message="legacy branch tables require dense zero-based cases",
          )
        }
        targets.push(
          branch_edge_target(
            function,
            values,
            case.edge,
            block_ids,
            legacy_function,
          ),
        )
      }
      BrTable(
        legacy_use(require_legacy_value(function, values, index)),
        targets,
        branch_edge_target(
          function, values, default_edge, block_ids, legacy_function,
        ),
      )
    }
    Return(results) =>
      Return(
        results.map(result => {
          legacy_use(require_legacy_value(function, values, result))
        }),
      )
    TailCall(call, semantic_operands) => {
      if call.protocol != Internal {
        raise UnsupportedOperation(
          message="only Internal tail calls are adapted",
        )
      }
      let embedding_abi = match embedding_abi {
        Some(embedding_abi) => embedding_abi
        None =>
          raise UnsupportedOperation(
            message="internal tail call requires an embedding ABI",
          )
      }
      let operands : Array[@abi.Reg] = []
      for operand in semantic_operands {
        operands.push(
          legacy_use(require_legacy_value(function, values, operand)),
        )
      }
      emit_internal_tail_call(
        isa, embedding_abi, legacy_function, legacy_block, call, operands, code_symbol_resolver,
      )
      Trap(trap_payload(Unreachable))
    }
    NoReturnCall(call, semantic_operands) => {
      let operands : Array[@abi.Reg] = []
      for operand in semantic_operands {
        operands.push(
          legacy_use(require_legacy_value(function, values, operand)),
        )
      }
      let roots : Array[@abi.Reg] = []
      for root in record.metadata.live_gc_roots {
        roots.push(legacy_use(require_legacy_value(function, values, root)))
      }
      append_semantic_call(
        isa,
        embedding_abi,
        function,
        legacy_function,
        legacy_block,
        call,
        semantic_operands,
        operands,
        [],
        roots,
        Array::make(function.value_count(), None),
        requires_hidden_safepoint_id,
        caller_root_scope_symbols,
        code_symbol_resolver,
      )
      Trap(trap_payload(Unreachable))
    }
    Trap(reason) => Trap(trap_payload(reason))
  }
  legacy_block.set_terminator(terminator)
}

///|
fn adapt_semantic_to_legacy(
  function : @semantic_machv.Function,
  isa : @isa.ISA,
  embedding_abi? : @abi.EmbeddingABI? = None,
  trap_payload? : (@semantic_machv.TrapReason) -> Int = fn(_) { 0 },
  requires_hidden_safepoint_id? : ((@semantic_machv.ExternalSymbol) -> Bool)? = None,
  caller_root_scope_symbols? : (
    @semantic_machv.ExternalSymbol,
    @semantic_machv.ExternalSymbol,
  )? = None,
  environment_field_path? : ((@semantic_machv.EnvironmentField) -> Array[Int]?)? = None,
  code_symbol_resolver? : ((@semantic_machv.CodeSymbol) -> @instr.CodeSymbol)? = None,
) -> @machv.Function raise SemanticLegacyAdapterError {
  function.verify() catch {
    error => raise InvalidLegacyFunction(message=error.to_string())
  }
  let legacy = @machv.Function(function.name())
  let stack_base = maximum_semantic_temporary_stack_bytes(
    function, isa, embedding_abi, requires_hidden_safepoint_id, caller_root_scope_symbols,
  )
  let (stack_objects, stack_offsets, outgoing_size) = plan_semantic_stack_objects(
    function, stack_base,
  )
  legacy.update_max_outgoing_args_size(outgoing_size)
  let values : Array[@abi.VReg?] = Array::make(function.value_count(), None)
  let integer_constants : Array[Int64?] = Array::make(
    function.value_count(),
    None,
  )
  let integer_stack_parameters : Array[@abi.VReg] = []
  let float_stack_parameters : Array[@abi.VReg] = []
  let float_stack_classes : Array[@abi.RegClass] = []
  let mut integer_register_count = 0
  let mut float_register_count = 0
  for parameter in function.parameters() {
    let index = function.value_index(parameter).unwrap()
    let ty = function.value_type(parameter).unwrap()
    let class = legacy_reg_class(ty)
    let mapped = match embedding_abi {
      Some(embedding_abi) =>
        match class {
          Int => {
            let register_capacity = 1 +
              embedding_abi.call_conv.user_arg_gprs.length()
            if integer_register_count < register_capacity {
              integer_register_count += 1
              legacy.add_param(class)
            } else {
              let value = legacy.new_vreg(class)
              integer_stack_parameters.push(value)
              value
            }
          }
          Float32 | Float64 | Vector =>
            if float_register_count < embedding_abi.call_conv.arg_fprs.length() {
              float_register_count += 1
              legacy.add_param(class)
            } else {
              let value = legacy.new_vreg(class)
              float_stack_parameters.push(value)
              float_stack_classes.push(class)
              value
            }
        }
      None => legacy.add_param(class)
    }
    values[index] = Some(mapped)
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
  if embedding_abi is Some(embedding_abi) &&
    (!integer_stack_parameters.is_empty() || !float_stack_parameters.is_empty()) {
    let (integer_offsets, float_offsets, _) = embedding_abi.call_conv.layout_overflow_stack(
      integer_stack_parameters.length(),
      float_stack_classes,
    )
    let stack_argument_base = if isa is AMD64 { 8 } else { 0 }
    let entry = legacy.get_blocks()[block_ids[0]]
    for index, parameter in integer_stack_parameters {
      let load = @instr.Inst(
        LoadStackParam(integer_offsets[index] + stack_argument_base, Int),
      )
      load.add_def(legacy_def(parameter))
      entry.add_inst(load)
    }
    for index, parameter in float_stack_parameters {
      let class = float_stack_classes[index]
      let load = @instr.Inst(
        LoadStackParam(float_offsets[index] + stack_argument_base, class),
      )
      load.add_def(legacy_def(parameter))
      entry.add_inst(load)
    }
    legacy.set_int_stack_params(integer_stack_parameters.length())
  }
  for block in semantic_blocks {
    for instruction in function.block_instructions(block) {
      for result in function.instruction_results(instruction) {
        let index = function.value_index(result).unwrap()
        let ty = function.value_type(result).unwrap()
        values[index] = Some(legacy.new_vreg(legacy_reg_class(ty)))
      }
    }
  }
  for block in semantic_blocks {
    let block_index = function.block_index(block).unwrap()
    let legacy_block = legacy.get_blocks()[block_ids[block_index]]
    for instruction in function.block_instructions(block) {
      append_semantic_instruction(
        isa, embedding_abi, function, legacy_block, instruction, values, integer_constants,
        legacy, stack_objects, stack_offsets, trap_payload, requires_hidden_safepoint_id,
        caller_root_scope_symbols, environment_field_path, code_symbol_resolver,
      )
    }
    set_semantic_terminator(
      isa, embedding_abi, function, block, legacy_block, values, block_ids, legacy,
      trap_payload, requires_hidden_safepoint_id, caller_root_scope_symbols, code_symbol_resolver,
    )
  }
  legacy.verify_for_isa(isa) catch {
    error => raise InvalidLegacyFunction(message=error.to_string())
  }
  legacy
}

///|
fn adapter_test_embedding_abi(isa : @isa.ISA) -> @abi.EmbeddingABI {
  let (context_index, user_indices) = match isa {
    AArch64 => (0, [1, 2, 3, 4, 5, 6, 7])
    AMD64 => (7, [6, 2, 1, 8, 9])
  }
  EmbeddingABI(
    {
      context_arg: { index: context_index, class: Int },
      user_arg_gprs: user_indices.map(index => { index, class: Int }),
      arg_fprs: Array::makei(8, index => { index, class: Float64 }),
      ret_gprs: [{ index: 0, class: Int }, { index: 2, class: Int }],
      ret_fprs: [{ index: 0, class: Float64 }, { index: 1, class: Float64 }],
    },
    reserve_context_role=false,
  )
}

///|
test "semantic-to-legacy adapter lowers scalar SSA directly" {
  let builder = @semantic_machv.FunctionBuilder::new(
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
  let builder = @semantic_machv.FunctionBuilder::new(
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

///|
test "semantic-to-legacy adapter lowers nontrapping scalar families" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_scalars",
    Internal,
    [I32, F32, F32],
    [I64, F32, I32],
  )
  let parameters = builder.parameters()
  let extended = builder.emit(Convert(I64ExtendI32(Signed)), [parameters[0]], [
      I64,
    ])[0]
  let float_sum = builder.emit(
      FloatBinary(Add),
      [parameters[1], parameters[2]],
      [F32],
    )[0]
  let compared = builder.emit(
      IntCompare(SignedGreaterThan),
      [parameters[0], parameters[0]],
      [I32],
    )[0]
  builder.return_([extended, float_sum, compared])
  inspect(
    adapt_semantic_to_legacy(builder.finish(), AMD64),
    content=(
      #|machv semantic_adapter_scalars(v0:int, f1:float, f2:float) -> (int, float, int) {
      #|block0:
      #|    v3 = extend.s32_64 v0
      #|    f4 = fadd.s f1, f2
      #|    v5 = cmp32.sgt v0, v0
      #|    ret v3, f4, v5
      #|}
      #|
    ),
  )
}

///|
test "semantic-to-legacy adapter legalizes remaining producer integers" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_integer_legalizations",
    Internal,
    [I64, I64],
    [I64, I64, I64, I64, I64],
  )
  let parameters = builder.parameters()
  let rotated = builder.emit(IntBinary(RotateLeft), parameters, [I64])[0]
  let trailing = builder.emit(IntUnary(CountTrailingZeros), [parameters[0]], [
      I64,
    ])[0]
  let signed_high = builder.emit(IntHighMultiply(Signed), parameters, [I64])[0]
  let unsigned_high = builder.emit(IntHighMultiply(Unsigned), parameters, [I64])[0]
  let constant_amount = builder.emit(I64Const(8UL), [], [I64])[0]
  let constant_rotated = builder.emit(
      IntBinary(RotateLeft),
      [parameters[0], constant_amount],
      [I64],
    )[0]
  builder.return_([
    rotated, trailing, signed_high, unsigned_high, constant_rotated,
  ])
  let function = builder.finish()
  inspect(
    adapt_semantic_to_legacy(function, AMD64),
    content=(
      #|machv semantic_adapter_integer_legalizations(v0:int, v1:int) -> (int, int, int, int, int) {
      #|block0:
      #|    v9 = ldi 0
      #|    v8 = sub v9, v1
      #|    v2 = rotr v0, v8
      #|    v10 = rbit v0
      #|    v3 = clz v10
      #|    v4, x0 = smulh v0, v1
      #|    v5, x0 = umulh v0, v1
      #|    v6 = ldi 8
      #|    v7 = rotr #56 v0
      #|    ret v2, v3, v4, v5, v7
      #|}
      #|
    ),
  )
  inspect(
    adapt_semantic_to_legacy(function, AArch64),
    content=(
      #|machv semantic_adapter_integer_legalizations(v0:int, v1:int) -> (int, int, int, int, int) {
      #|block0:
      #|    v8 = sub x31, v1
      #|    v2 = rotr v0, v8
      #|    v9 = rbit v0
      #|    v3 = clz v9
      #|    v4 = smulh v0, v1
      #|    v5 = umulh v0, v1
      #|    v6 = ldi 8
      #|    v7 = rotr #56 v0
      #|    ret v2, v3, v4, v5, v7
      #|}
      #|
    ),
  )
}

///|
test "semantic-to-legacy adapter legalizes trapping and saturating float conversion" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_float_to_int",
    Internal,
    [F64, F32],
    [I32, I64],
  )
  let parameters = builder.parameters()
  let trapping = builder.emit(
      Convert(FloatToInt(F64, I32, Signed, Trapping)),
      [parameters[0]],
      [I32],
    )[0]
  let saturating = builder.emit(
      Convert(FloatToInt(F32, I64, Unsigned, Saturating)),
      [parameters[1]],
      [I64],
    )[0]
  builder.return_([trapping, saturating])
  let function = builder.finish()
  inspect(
    adapt_semantic_to_legacy(function, AMD64, trap_payload=fn(reason) {
      if reason is InvalidConversionToInteger {
        37
      } else {
        0
      }
    }),
    content=(
      #|machv semantic_adapter_float_to_int(f0:double, f1:float) -> (int, int) {
      #|block0:
      #|    fcmp.d f0, f0
      #|    trap_if.ps #37
      #|    f4 = ldf -2147483649
      #|    fcmp.d f0, f4
      #|    trap_if.ls #37
      #|    f5 = ldf 2147483648
      #|    fcmp.d f0, f5
      #|    trap_if.hs #37
      #|    v2 = fcvt.f64_i32_s f0
      #|    v3 = fcvt.f32_i64_u f1
      #|    ret v2, v3
      #|}
      #|
    ),
  )
  inspect(
    adapt_semantic_to_legacy(function, AArch64, trap_payload=fn(reason) {
      if reason is InvalidConversionToInteger {
        37
      } else {
        0
      }
    }),
    content=(
      #|machv semantic_adapter_float_to_int(f0:double, f1:float) -> (int, int) {
      #|block0:
      #|    fcmp.d f0, f0
      #|    trap_if.vs #37
      #|    f4 = ldf -2147483649
      #|    fcmp.d f0, f4
      #|    trap_if.le #37
      #|    f5 = ldf 2147483648
      #|    fcmp.d f0, f5
      #|    trap_if.ge #37
      #|    v2 = fcvt.f64_i32_s f0
      #|    v3 = fcvt.f32_i64_u f1
      #|    ret v2, v3
      #|}
      #|
    ),
  )
}

///|
test "semantic-to-legacy adapter lowers dense switches" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_switch",
    Internal,
    [I32],
    [I64],
  )
  let zero = builder.create_block([])
  let one = builder.create_block([])
  let fallback = builder.create_block([])
  builder.switch(
    builder.parameters()[0],
    [(0UL, zero, []), (1UL, one, [])],
    fallback,
    [],
  )
  builder.switch_to_block(zero)
  let zero_value = builder.emit(I64Const(10UL), [], [I64])[0]
  builder.return_([zero_value])
  builder.switch_to_block(one)
  let one_value = builder.emit(I64Const(20UL), [], [I64])[0]
  builder.return_([one_value])
  builder.switch_to_block(fallback)
  let fallback_value = builder.emit(I64Const(30UL), [], [I64])[0]
  builder.return_([fallback_value])
  inspect(
    adapt_semantic_to_legacy(builder.finish(), AArch64),
    content=(
      #|machv semantic_adapter_switch(v0:int) -> int {
      #|block0:
      #|    br_table v0, [block1, block2], default block3
      #|block1:
      #|    v1 = ldi 10
      #|    ret v1
      #|block2:
      #|    v2 = ldi 20
      #|    ret v2
      #|block3:
      #|    v3 = ldi 30
      #|    ret v3
      #|}
      #|
    ),
  )
}

///|
test "semantic-to-legacy adapter lowers explicit pointer memory effects" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_memory",
    Internal,
    [Ptr64, I64],
    [I64],
  )
  let parameters = builder.parameters()
  builder.emit(
    Store(@semantic_machv.StoreSpec::new(W64, I64, 8UL, Little, None)),
    parameters,
    [],
  )
  |> ignore
  let loaded = builder.emit(
      Load(@semantic_machv.LoadSpec::new(W64, None, I64, 8UL, Little, None)),
      [parameters[0]],
      [I64],
    )[0]
  builder.return_([loaded])
  inspect(
    adapt_semantic_to_legacy(builder.finish(), AArch64),
    content=(
      #|machv semantic_adapter_memory(v0:int, v1:int) -> int {
      #|block0:
      #|    store_ptr.i64 +8 v0, v1
      #|    v2 = load_ptr.i64 +8 v0
      #|    ret v2
      #|}
      #|
    ),
  )
}

///|
test "semantic-to-legacy adapter preserves division traps" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_div",
    Internal,
    [I64, I64],
    [I64],
  )
  let result = builder.emit(IntBinary(SignedDiv), builder.parameters(), [I64])[0]
  builder.return_([result])
  inspect(
    adapt_semantic_to_legacy(builder.finish(), AMD64, trap_payload=fn(reason) {
      match reason {
        IntegerDivisionByZero => 4
        IntegerOverflow => 5
        _ => 0
      }
    }),
    content=(
      #|machv semantic_adapter_div(v0:int, v1:int) -> int {
      #|block0:
      #|    trap_if_zero #4 v1
      #|    trap_if_div_overflow #5 v0, v1
      #|    v2 = sdiv v0, v1
      #|    ret v2
      #|}
      #|
    ),
  )
}

///|
test "semantic-to-legacy adapter lowers platform call ABI" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_platform_call",
    Internal,
    [GcRef64],
    [I32],
  )
  let call = @semantic_machv.SemanticCall::new(
    External(@semantic_machv.ExternalSymbol::new("runtime.array_len")),
    @semantic_machv.Signature::new([GcRef64], [I32]),
    Platform,
    @semantic_machv.CallBehavior::new(Read, true, false, false, false),
  )
  let result = builder.emit(Call(call), builder.parameters(), [I32])[0]
  builder.return_([result])
  inspect(
    adapt_semantic_to_legacy(builder.finish(), AMD64),
    content=(
      #|machv semantic_adapter_platform_call(v0:int) -> int {
      #|block0:
      #|    v1 = call_external[Foreign].runtime.array_len(1) -> 1 results v0
      #|    ret v1
      #|}
      #|
    ),
  )
}

///|
test "semantic-to-legacy adapter lowers direct internal call ABI" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_internal_call",
    Internal,
    [Ptr64, I32],
    [I64],
  )
  let call = @semantic_machv.SemanticCall::new(
    Internal(@semantic_machv.CodeSymbol::new("wasm.func.7")),
    @semantic_machv.Signature::new([Ptr64, I32], [I64]),
    Internal,
    @semantic_machv.CallBehavior::conservative(),
  )
  let result = builder.emit(Call(call), builder.parameters(), [I64])[0]
  builder.return_([result])
  inspect(
    adapt_semantic_to_legacy(
      builder.finish(),
      AMD64,
      embedding_abi=Some(adapter_test_embedding_abi(AMD64)),
      code_symbol_resolver=Some(fn(_) { CodeSymbol("wasm.func", 7) }),
    ),
    content=(
      #|machv semantic_adapter_internal_call(v0:int, v1:int) -> int {
      #|block0:
      #|    v2 = call_direct[Internal].wasm.func.7(1) -> 1 results v0, v1
      #|    ret v2
      #|}
      #|
    ),
  )
}

///|
test "semantic-to-legacy adapter preserves precise roots across ordinary calls" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_roots",
    Internal,
    [Ptr64, GcRef64],
    [I64],
  )
  let parameters = builder.parameters()
  let call = @semantic_machv.SemanticCall::new(
    Internal(@semantic_machv.CodeSymbol::new("wasm.func.7")),
    @semantic_machv.Signature::new([Ptr64], [I64]),
    Internal,
    @semantic_machv.CallBehavior::conservative(),
  )
  let result = builder.emit_with_metadata(
      Call(call),
      [parameters[0]],
      [I64],
      @semantic_machv.InstructionMetadata::new(None, [parameters[1]]),
    )[0]
  builder.return_([result])
  let legacy = adapt_semantic_to_legacy(
    builder.finish(),
    AMD64,
    embedding_abi=Some(adapter_test_embedding_abi(AMD64)),
    caller_root_scope_symbols=Some(
      (
        @semantic_machv.ExternalSymbol::new(
          "wasmoon.runtime.gc.push_root_scope",
        ),
        @semantic_machv.ExternalSymbol::new("wasmoon.runtime.gc.pop_root_scope"),
      ),
    ),
    code_symbol_resolver=Some(fn(_) { CodeSymbol("wasm.func", 7) }),
  )
  inspect(
    legacy,
    content=(
      #|machv semantic_adapter_roots(v0:int, v1:int) -> int {
      #|block0:
      #|    str [sp+0] v1
      #|    v3 = mov rd, outgoing_args_base
      #|    v4 = ldi 1
      #|    call_external[Foreign].wasmoon.runtime.gc.push_root_scope(3) -> 0 results v0, v3, v4
      #|    v2 = call_direct[Internal].wasm.func.7(0) -> 1 results v0
      #|    call_external[Foreign].wasmoon.runtime.gc.pop_root_scope(1) -> 0 results v0
      #|    ret v2
      #|}
      #|
    ),
  )
  inspect(legacy.get_max_outgoing_args_size(), content="16")
}

///|
test "semantic caller roots are copied before call overflow reuses the stack" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_roots_with_overflow",
    Internal,
    [Ptr64, GcRef64, I64, I64, I64, I64, I64, I64],
    [],
  )
  let parameters = builder.parameters()
  let call = @semantic_machv.SemanticCall::new(
    Internal(@semantic_machv.CodeSymbol::new("wasm.func.8")),
    @semantic_machv.Signature::new([Ptr64, I64, I64, I64, I64, I64, I64], []),
    Internal,
    @semantic_machv.CallBehavior::conservative(),
  )
  builder.emit_with_metadata(
    Call(call),
    [
      parameters[0],
      parameters[2],
      parameters[3],
      parameters[4],
      parameters[5],
      parameters[6],
      parameters[7],
    ],
    [],
    @semantic_machv.InstructionMetadata::new(None, [parameters[1]]),
  )
  |> ignore
  builder.return_([])
  let legacy = adapt_semantic_to_legacy(
    builder.finish(),
    AMD64,
    embedding_abi=Some(adapter_test_embedding_abi(AMD64)),
    caller_root_scope_symbols=Some(
      (
        @semantic_machv.ExternalSymbol::new(
          "wasmoon.runtime.gc.push_root_scope",
        ),
        @semantic_machv.ExternalSymbol::new("wasmoon.runtime.gc.pop_root_scope"),
      ),
    ),
    code_symbol_resolver=Some(fn(_) { CodeSymbol("wasm.func", 8) }),
  )
  inspect(
    legacy,
    content=(
      #|machv semantic_adapter_roots_with_overflow(v0:int, v1:int, v2:int, v3:int, v4:int, v5:int) {
      #|block0:
      #|    v6 = load_stack_param +8 (int)
      #|    v7 = load_stack_param +16 (int)
      #|    str [sp+0] v1
      #|    v8 = mov rd, outgoing_args_base
      #|    v9 = ldi 1
      #|    call_external[Foreign].wasmoon.runtime.gc.push_root_scope(3) -> 0 results v0, v8, v9
      #|    str [sp+0] v7
      #|    call_direct[Internal].wasm.func.8(6) -> 0 results v0, v2, v3, v4, v5, v6
      #|    call_external[Foreign].wasmoon.runtime.gc.pop_root_scope(1) -> 0 results v0
      #|    ret
      #|}
      #|
    ),
  )
  inspect(legacy.get_max_outgoing_args_size(), content="16")
}

///|
test "semantic ordinary call roots require runtime scope symbols" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_missing_root_scope",
    Internal,
    [Ptr64, GcRef64],
    [],
  )
  let parameters = builder.parameters()
  let call = @semantic_machv.SemanticCall::new(
    Internal(@semantic_machv.CodeSymbol::new("wasm.func.7")),
    @semantic_machv.Signature::new([Ptr64], []),
    Internal,
    @semantic_machv.CallBehavior::conservative(),
  )
  builder.emit_with_metadata(
    Call(call),
    [parameters[0]],
    [],
    @semantic_machv.InstructionMetadata::new(None, [parameters[1]]),
  )
  |> ignore
  builder.return_([])
  try
    adapt_semantic_to_legacy(
      builder.finish(),
      AMD64,
      embedding_abi=Some(adapter_test_embedding_abi(AMD64)),
      code_symbol_resolver=Some(fn(_) { CodeSymbol("wasm.func", 7) }),
    )
    |> ignore
  catch {
    error =>
      inspect(
        error,
        content=(
          #|UnsupportedOperation(message="precise GC roots require caller root-scope symbols")
        ),
      )
  } noraise {
    _ => fail("expected missing caller root-scope symbols to be rejected")
  }
}

///|
test "semantic-to-legacy adapter lays out address-visible stack objects" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_stack_objects",
    Internal,
    [I64],
    [],
  )
  let parameter = builder.parameters()[0]
  let first = builder.create_stack_object(8, 8)
  let second = builder.create_stack_object(16, 16)
  let first_address = builder.emit(StackAddress(first), [], [Ptr64])[0]
  builder.emit(
    Store(@semantic_machv.StoreSpec::new(W64, I64, 0UL, Little, None)),
    [first_address, parameter],
    [],
  )
  |> ignore
  let second_address = builder.emit(StackAddress(second), [], [Ptr64])[0]
  builder.emit(
    Store(@semantic_machv.StoreSpec::new(W64, I64, 0UL, Little, None)),
    [second_address, parameter],
    [],
  )
  |> ignore
  builder.return_([])
  let legacy = adapt_semantic_to_legacy(builder.finish(), AArch64)
  inspect(
    legacy,
    content=(
      #|machv semantic_adapter_stack_objects(v0:int) {
      #|block0:
      #|    v1 = mov rd, outgoing_args_base
      #|    store_ptr.i64 +0 v1, v0
      #|    v3 = mov rd, outgoing_args_base
      #|    v2 = add #16 v3
      #|    store_ptr.i64 +0 v2, v0
      #|    ret
      #|}
      #|
    ),
  )
  inspect(legacy.get_max_outgoing_args_size(), content="32")
}

///|
test "semantic stack objects do not overlap internal call overflow arguments" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_stack_after_call",
    Internal,
    [Ptr64, I64, I64, I64, I64, I64, I64],
    [],
  )
  let object = builder.create_stack_object(8, 8)
  let call = @semantic_machv.SemanticCall::new(
    Internal(@semantic_machv.CodeSymbol::new("wasm.func.9")),
    @semantic_machv.Signature::new([Ptr64, I64, I64, I64, I64, I64, I64], []),
    Internal,
    @semantic_machv.CallBehavior::conservative(),
  )
  builder.emit(Call(call), builder.parameters(), []) |> ignore
  let address = builder.emit(StackAddress(object), [], [Ptr64])[0]
  builder.emit(
    Store(@semantic_machv.StoreSpec::new(W64, I64, 0UL, Little, None)),
    [address, builder.parameters()[1]],
    [],
  )
  |> ignore
  builder.return_([])
  let legacy = adapt_semantic_to_legacy(
    builder.finish(),
    AMD64,
    embedding_abi=Some(adapter_test_embedding_abi(AMD64)),
    code_symbol_resolver=Some(fn(_) { CodeSymbol("wasm.func", 9) }),
  )
  inspect(
    legacy,
    content=(
      #|machv semantic_adapter_stack_after_call(v0:int, v1:int, v2:int, v3:int, v4:int, v5:int) {
      #|block0:
      #|    v6 = load_stack_param +8 (int)
      #|    str [sp+0] v6
      #|    call_direct[Internal].wasm.func.9(6) -> 0 results v0, v1, v2, v3, v4, v5
      #|    v8 = mov rd, outgoing_args_base
      #|    v7 = add #16 v8
      #|    store_ptr.i64 +0 v7, v1
      #|    ret
      #|}
      #|
    ),
  )
  inspect(legacy.get_max_outgoing_args_size(), content="32")
}

///|
test "semantic allocation calls spill precise roots and append safepoint ID" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_allocation_safepoint",
    Internal,
    [Ptr64, GcRef64, GcRef64],
    [I64],
  )
  let parameters = builder.parameters()
  let fields = builder.create_stack_object(8, 8)
  let type_index = builder.emit(I32Const(7U), [], [I32])[0]
  let fields_address = builder.emit(StackAddress(fields), [], [Ptr64])[0]
  let field_count = builder.emit(I32Const(1U), [], [I32])[0]
  let call = @semantic_machv.SemanticCall::new(
    External(
      @semantic_machv.ExternalSymbol::new("wasm.runtime.gc.alloc_struct_slow"),
    ),
    @semantic_machv.Signature::new([Ptr64, I32, Ptr64, I32], [I64]),
    Platform,
    @semantic_machv.CallBehavior::new(ReadWrite, true, false, true, false),
  )
  let result = builder.emit_with_metadata(
      Call(call),
      [parameters[0], type_index, fields_address, field_count],
      [I64],
      @semantic_machv.InstructionMetadata::new(None, [
        parameters[1],
        parameters[2],
      ]),
    )[0]
  builder.return_([result])
  let legacy = adapt_semantic_to_legacy(
    builder.finish(),
    AMD64,
    caller_root_scope_symbols=Some(
      (
        @semantic_machv.ExternalSymbol::new(
          "wasmoon.runtime.gc.push_root_scope",
        ),
        @semantic_machv.ExternalSymbol::new("wasmoon.runtime.gc.pop_root_scope"),
      ),
    ),
    requires_hidden_safepoint_id=Some(fn(symbol) {
      symbol.name == "wasm.runtime.gc.alloc_struct_slow"
    }),
  )
  inspect(
    legacy,
    content=(
      #|machv semantic_adapter_allocation_safepoint(v0:int, v1:int, v2:int) -> int {
      #|block0:
      #|    v3 = ldi 7
      #|    v7 = mov rd, outgoing_args_base
      #|    v4 = add #16 v7
      #|    v5 = ldi 1
      #|    str [sp+0] v1
      #|    str [sp+8] v2
      #|    v8 = mov rd, outgoing_args_base
      #|    v9 = ldi 2
      #|    call_external[Foreign].wasmoon.runtime.gc.push_root_scope(3) -> 0 results v0, v8, v9
      #|    v10 = load_safepoint_id roots=1
      #|    v6 = call_external[Foreign].wasm.runtime.gc.alloc_struct_slow(5) -> 1 results v0, v3, v4, v5, v10
      #|    call_external[Foreign].wasmoon.runtime.gc.pop_root_scope(1) -> 0 results v0
      #|    ret v6
      #|}
      #|
    ),
  )
  inspect(legacy.get_max_outgoing_args_size(), content="32")
}

///|
test "semantic allocation calls append safepoint ID without live roots" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_rootless_allocation",
    Internal,
    [Ptr64],
    [I64],
  )
  let fields = builder.create_stack_object(8, 8)
  let type_index = builder.emit(I32Const(7U), [], [I32])[0]
  let fields_address = builder.emit(StackAddress(fields), [], [Ptr64])[0]
  let field_count = builder.emit(I32Const(0U), [], [I32])[0]
  let call = @semantic_machv.SemanticCall::new(
    External(@semantic_machv.ExternalSymbol::new("runtime.alloc")),
    @semantic_machv.Signature::new([Ptr64, I32, Ptr64, I32], [I64]),
    Platform,
    @semantic_machv.CallBehavior::new(ReadWrite, true, false, true, false),
  )
  let result = builder.emit(
      Call(call),
      [builder.parameters()[0], type_index, fields_address, field_count],
      [I64],
    )[0]
  builder.return_([result])
  inspect(
    adapt_semantic_to_legacy(
      builder.finish(),
      AMD64,
      requires_hidden_safepoint_id=Some(fn(symbol) {
        symbol.name == "runtime.alloc"
      }),
    ),
    content=(
      #|machv semantic_adapter_rootless_allocation(v0:int) -> int {
      #|block0:
      #|    v1 = ldi 7
      #|    v2 = mov rd, outgoing_args_base
      #|    v3 = ldi 0
      #|    v5 = load_safepoint_id roots=0
      #|    v4 = call_external[Foreign].runtime.alloc(5) -> 1 results v0, v1, v2, v3, v5
      #|    ret v4
      #|}
      #|
    ),
  )
}

///|
test "semantic Platform caller roots are copied before overflow arguments" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_overlapping_roots",
    Internal,
    [Ptr64, I64, I64, I64, I64, I64, I64, GcRef64],
    [],
  )
  let parameters = builder.parameters()
  let call = @semantic_machv.SemanticCall::new(
    External(@semantic_machv.ExternalSymbol::new("runtime.observe")),
    @semantic_machv.Signature::new([Ptr64, I64, I64, I64, I64, I64, I64], []),
    Platform,
    @semantic_machv.CallBehavior::conservative(),
  )
  builder.emit_with_metadata(
    Call(call),
    [
      parameters[0],
      parameters[1],
      parameters[2],
      parameters[3],
      parameters[4],
      parameters[5],
      parameters[6],
    ],
    [],
    @semantic_machv.InstructionMetadata::new(None, [parameters[7]]),
  )
  |> ignore
  builder.return_([])
  inspect(
    adapt_semantic_to_legacy(
      builder.finish(),
      AMD64,
      caller_root_scope_symbols=Some(
        (
          @semantic_machv.ExternalSymbol::new(
            "wasmoon.runtime.gc.push_root_scope",
          ),
          @semantic_machv.ExternalSymbol::new(
            "wasmoon.runtime.gc.pop_root_scope",
          ),
        ),
      ),
    ),
    content=(
      #|machv semantic_adapter_overlapping_roots(v0:int, v1:int, v2:int, v3:int, v4:int, v5:int, v6:int, v7:int) {
      #|block0:
      #|    str [sp+0] v7
      #|    v8 = mov rd, outgoing_args_base
      #|    v9 = ldi 1
      #|    call_external[Foreign].wasmoon.runtime.gc.push_root_scope(3) -> 0 results v0, v8, v9
      #|    str [sp+0] v6
      #|    call_external[Foreign].runtime.observe(7) -> 0 results v0, v1, v2, v3, v4, v5
      #|    call_external[Foreign].wasmoon.runtime.gc.pop_root_scope(1) -> 0 results v0
      #|    ret
      #|}
      #|
    ),
  )
}

///|
test "semantic environment fields lower through embedding-owned access paths" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_environment_fields",
    Internal,
    [Ptr64],
    [Ptr64, Ptr64],
  )
  let environment = builder.parameters()[0]
  let function_table_field = @semantic_machv.EnvironmentField::new(
    "runtime.function_table",
    Ptr64,
  )
  let memory_two_base_field = @semantic_machv.EnvironmentField::new(
    "runtime.memory.2.base",
    Ptr64,
  )
  let function_table = builder.emit(
      EnvironmentField(function_table_field),
      [environment],
      [Ptr64],
    )[0]
  let memory_two_base = builder.emit(
      EnvironmentField(memory_two_base_field),
      [environment],
      [Ptr64],
    )[0]
  builder.return_([function_table, memory_two_base])
  inspect(
    adapt_semantic_to_legacy(
      builder.finish(),
      AArch64,
      environment_field_path=Some(fn(field) {
        match field.name {
          "runtime.function_table" => Some([24])
          "runtime.memory.2.base" => Some([88, 16, 0])
          _ => None
        }
      }),
    ),
    content=(
      #|machv semantic_adapter_environment_fields(v0:int) -> (int, int) {
      #|block0:
      #|    v1 = load.i64 +24 v0
      #|    v3 = load.i64 +88 v0
      #|    v4 = load.i64 +16 v3
      #|    v2 = load.i64 +0 v4
      #|    ret v1, v2
      #|}
      #|
    ),
  )
}

///|
test "semantic environment fields require an embedding resolver" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_unresolved_environment",
    Internal,
    [Ptr64],
    [Ptr64],
  )
  let field = @semantic_machv.EnvironmentField::new("runtime.field", Ptr64)
  let result = builder.emit(EnvironmentField(field), builder.parameters(), [
      Ptr64,
    ])[0]
  builder.return_([result])
  try adapt_semantic_to_legacy(builder.finish(), AMD64) |> ignore catch {
    error =>
      inspect(
        error,
        content=(
          #|UnsupportedOperation(message="environment field requires an embedding resolver")
        ),
      )
  } noraise {
    _ => fail("expected unresolved environment field to be rejected")
  }
}

///|
test "semantic direct tail calls lower to legacy tail-call control" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_direct_tail",
    Internal,
    [Ptr64, I32],
    [I64],
  )
  let call = @semantic_machv.SemanticCall::new(
    Internal(@semantic_machv.CodeSymbol::new("wasm.func.4")),
    @semantic_machv.Signature::new([Ptr64, I32], [I64]),
    Internal,
    @semantic_machv.CallBehavior::conservative(),
  )
  builder.tail_call(call, builder.parameters())
  inspect(
    adapt_semantic_to_legacy(
      builder.finish(),
      AMD64,
      embedding_abi=Some(adapter_test_embedding_abi(AMD64)),
      code_symbol_resolver=Some(fn(_) { CodeSymbol("wasm.func", 4) }),
    ),
    content=(
      #|machv semantic_adapter_direct_tail(v0:int, v1:int) -> int {
      #|block0:
      #|    v2 = load_code_addr.wasm.func.4
      #|    return_call_indirect(stack=0) -> 0 results v2
      #|    trap #0
      #|}
      #|
    ),
  )
}

///|
test "semantic indirect tail overflow precedes address-visible stack objects" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_indirect_tail",
    Internal,
    [Ptr64, Ptr64, I64, I64, I64, I64, I64, I64],
    [],
  )
  let object = builder.create_stack_object(8, 8)
  let object_address = builder.emit(StackAddress(object), [], [Ptr64])[0]
  builder.emit(
    Store(@semantic_machv.StoreSpec::new(W64, I64, 0UL, Little, None)),
    [object_address, builder.parameters()[2]],
    [],
  )
  |> ignore
  let call = @semantic_machv.SemanticCall::new(
    Indirect,
    @semantic_machv.Signature::new([Ptr64, I64, I64, I64, I64, I64, I64], []),
    Internal,
    @semantic_machv.CallBehavior::conservative(),
  )
  builder.tail_call(call, builder.parameters())
  let legacy = adapt_semantic_to_legacy(
    builder.finish(),
    AMD64,
    embedding_abi=Some(adapter_test_embedding_abi(AMD64)),
  )
  inspect(
    legacy,
    content=(
      #|machv semantic_adapter_indirect_tail(v0:int, v1:int, v2:int, v3:int, v4:int, v5:int) {
      #|block0:
      #|    v6 = load_stack_param +8 (int)
      #|    v7 = load_stack_param +16 (int)
      #|    v9 = mov rd, outgoing_args_base
      #|    v8 = add #16 v9
      #|    store_ptr.i64 +0 v8, v2
      #|    str [sp+0] v7
      #|    return_call_indirect(stack=16) -> 0 results v0
      #|    trap #0
      #|}
      #|
    ),
  )
  inspect(legacy.get_max_outgoing_args_size(), content="32")
}

///|
test "semantic noreturn calls trap if the helper unexpectedly returns" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_noreturn",
    Internal,
    [Ptr64, I32],
    [],
  )
  let call = @semantic_machv.SemanticCall::new(
    External(@semantic_machv.ExternalSymbol::new("runtime.throw")),
    @semantic_machv.Signature::new([Ptr64, I32], []),
    Platform,
    @semantic_machv.CallBehavior::new(ReadWrite, true, false, false, false),
  )
  builder.noreturn_call(call, builder.parameters())
  inspect(
    adapt_semantic_to_legacy(builder.finish(), AArch64, trap_payload=fn(
      reason,
    ) {
      if reason is Unreachable {
        99
      } else {
        0
      }
    }),
    content=(
      #|machv semantic_adapter_noreturn(v0:int, v1:int) {
      #|block0:
      #|    call_external[Foreign].runtime.throw(2) -> 0 results v0, v1
      #|    trap #99
      #|}
      #|
    ),
  )
}

///|
test "semantic tail calls do not retain dead caller roots" {
  let builder = @semantic_machv.FunctionBuilder::new(
    "semantic_adapter_tail_roots",
    Internal,
    [Ptr64, GcRef64],
    [],
  )
  let parameters = builder.parameters()
  let call = @semantic_machv.SemanticCall::new(
    Internal(@semantic_machv.CodeSymbol::new("wasm.func.5")),
    @semantic_machv.Signature::new([Ptr64, GcRef64], []),
    Internal,
    @semantic_machv.CallBehavior::conservative(),
  )
  builder.tail_call_with_metadata(
    call,
    parameters,
    @semantic_machv.TerminatorMetadata::new(None, [parameters[1]]),
  )
  inspect(
    adapt_semantic_to_legacy(
      builder.finish(),
      AMD64,
      embedding_abi=Some(adapter_test_embedding_abi(AMD64)),
      code_symbol_resolver=Some(fn(_) { CodeSymbol("wasm.func", 5) }),
    ),
    content=(
      #|machv semantic_adapter_tail_roots(v0:int, v1:int) {
      #|block0:
      #|    v2 = load_code_addr.wasm.func.5
      #|    return_call_indirect(stack=0) -> 0 results v2
      #|    trap #0
      #|}
      #|
    ),
  )
}
