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
  function : @semantic.Function,
  operands : Array[@semantic.Value],
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
  function : @semantic.Function,
  operation : @semantic.IntUnaryOp,
  operands : Array[@semantic.Value],
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
  function : @semantic.Function,
  comparison : @semantic.IntComparison,
  operands : Array[@semantic.Value],
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
  function : @semantic.Function,
  operation : @semantic.FloatUnaryOp,
  results : Array[@semantic.Value],
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
  function : @semantic.Function,
  operation : @semantic.FloatBinaryOp,
  results : Array[@semantic.Value],
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
  comparison : @semantic.FloatComparison,
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
  conversion : @semantic.ConversionOp,
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
fn legacy_memory_type(ty : @semantic.ValueType) -> @instr.MemType {
  match ty {
    I32 => I32
    I64 | Ptr64 | GcRef64 => I64
    F32 => F32
    F64 => F64
    V128 => V128
  }
}

///|
fn access_width_bits(width : @semantic.AccessWidth) -> Int {
  match width {
    W8 => 8
    W16 => 16
    W32 => 32
    W64 => 64
    W128 => 128
  }
}

///|
fn semantic_type_width(ty : @semantic.ValueType) -> @semantic.AccessWidth {
  match ty {
    I32 | F32 => W32
    I64 | F64 | Ptr64 | GcRef64 => W64
    V128 => W128
  }
}

///|
fn lower_semantic_load(
  spec : @semantic.LoadSpec,
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
  spec : @semantic.StoreSpec,
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

///|
test "semantic-to-legacy adapter lowers nontrapping scalar families" {
  let builder = @semantic.FunctionBuilder::new(
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
test "semantic-to-legacy adapter lowers explicit pointer memory effects" {
  let builder = @semantic.FunctionBuilder::new(
    "semantic_adapter_memory",
    Internal,
    [Ptr64, I64],
    [I64],
  )
  let parameters = builder.parameters()
  builder.emit(
    Store(@semantic.StoreSpec::new(W64, I64, 8UL, Little, None)),
    parameters,
    [],
  )
  |> ignore
  let loaded = builder.emit(
      Load(@semantic.LoadSpec::new(W64, None, I64, 8UL, Little, None)),
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
test "semantic-to-legacy adapter rejects division before trap legalization" {
  let builder = @semantic.FunctionBuilder::new(
    "semantic_adapter_div",
    Internal,
    [I64, I64],
    [I64],
  )
  let result = builder.emit(IntBinary(SignedDiv), builder.parameters(), [I64])[0]
  builder.return_([result])
  try adapt_semantic_to_legacy(builder.finish(), AMD64) |> ignore catch {
    error =>
      inspect(
        error,
        content=(
          #|UnsupportedOperation(message="division and remainder require explicit trap legalization")
        ),
      )
  } noraise {
    _ => fail("expected trapping division to remain unsupported")
  }
}
