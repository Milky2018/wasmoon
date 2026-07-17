///|
pub suberror AArch64LowerError {
  InvalidSemantic(cause~ : @semantic.MachVVerifyError)
  MissingMappedValue(value_index~ : Int)
  UnsupportedOperation(
    block_index~ : Int,
    instruction_index~ : Int,
    operation~ : @semantic.Operation
  )
  UnsupportedTerminator(block_index~ : Int, terminator~ : @semantic.Terminator)
  UnsupportedAbi(message~ : String)
  BuildFailure(cause~ : @vcode.VCodeBuildError)
  InvalidTarget(cause~ : TargetVCodeVerifyError)
} derive(Debug)

///|
pub impl Show for AArch64LowerError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
fn align_up(value : Int, alignment : Int) -> Int {
  (value + alignment - 1) / alignment * alignment
}

///|
fn gpr_width(ty : @semantic.ValueType) -> GprWidth? {
  match ty {
    I32 => Some(W32)
    I64 => Some(W64)
    _ => None
  }
}

///|
fn optional_gpr_width(ty : @semantic.ValueType?) -> GprWidth? {
  match ty {
    Some(ty) => gpr_width(ty)
    None => None
  }
}

///|
fn lower_binary(operation : @semantic.IntBinaryOp) -> AArch64IntBinary? {
  match operation {
    Add => Some(Add)
    Sub => Some(Sub)
    Mul => Some(Mul)
    And => Some(And)
    Or => Some(Orr)
    Xor => Some(Eor)
    ShiftLeft => Some(Lsl)
    SignedShiftRight => Some(Asr)
    UnsignedShiftRight => Some(Lsr)
    RotateRight => Some(Ror)
    SignedDiv | UnsignedDiv | SignedRem | UnsignedRem | RotateLeft => None
  }
}

///|
fn lower_condition(comparison : @semantic.IntComparison) -> AArch64Condition {
  match comparison {
    Equal => Eq
    NotEqual => Ne
    SignedLessThan => Lt
    SignedLessOrEqual => Le
    SignedGreaterThan => Gt
    SignedGreaterOrEqual => Ge
    UnsignedLessThan => Lo
    UnsignedLessOrEqual => Ls
    UnsignedGreaterThan => Hi
    UnsignedGreaterOrEqual => Hs
  }
}

///|
fn map_value(
  function : @semantic.Function,
  values : Array[@vcode.Value?],
  value : @semantic.Value,
) -> @vcode.Value raise AArch64LowerError {
  let index = function.value_index(value).unwrap()
  match values[index] {
    Some(mapped) => mapped
    None => raise MissingMappedValue(value_index=index)
  }
}

///|
fn map_values(
  function : @semantic.Function,
  values : Array[@vcode.Value?],
  source : Array[@semantic.Value],
) -> Array[@vcode.Value] raise AArch64LowerError {
  source.map(value => map_value(function, values, value))
}

///|
fn append_body(
  builder : @vcode.Builder[AArch64Inst],
  block : @vcode.Block,
  instruction : AArch64Inst,
  inputs : Array[@vcode.Input],
  outputs : Array[@vcode.Output],
  metadata : @vcode.InstructionMetadata,
) -> Array[@vcode.Value] raise AArch64LowerError {
  let (_, results) = builder.append_body(
    block,
    instruction,
    inputs,
    outputs,
    [],
    metadata,
  ) catch {
    error => raise BuildFailure(cause=error)
  }
  results
}

///|
fn source_metadata(
  metadata : @semantic.InstructionMetadata,
  values : Array[@vcode.Value],
  semantics : @semantic.OperationSemantics,
) -> @vcode.InstructionMetadata {
  let safepoint : @semantic.SafepointKind? = match
    (semantics.gc_safepoint, semantics.cancellation_safepoint) {
    (true, true) => Some(GcAndCancellation)
    (true, false) => Some(Gc)
    (false, true) => Some(Cancellation)
    (false, false) => None
  }
  match metadata.source {
    Some(source) =>
      @vcode.InstructionMetadata::new(source~, safepoint?, live_gc_roots=values)
    None => @vcode.InstructionMetadata::new(safepoint?, live_gc_roots=values)
  }
}

///|
fn lower_direct_platform_call(
  builder : @vcode.Builder[AArch64Inst],
  block : @vcode.Block,
  call : @semantic.SemanticCall,
  operands : Array[@vcode.Value],
  result_types : Array[@semantic.ValueType],
  metadata : @vcode.InstructionMetadata,
) -> Array[@vcode.Value] raise AArch64LowerError {
  if call.protocol != Platform {
    raise UnsupportedAbi(message="direct internal call ABI is not selected yet")
  }
  if call.behavior.returns_twice {
    raise UnsupportedAbi(
      message="returns-twice platform calls are not supported",
    )
  }
  if result_types.length() > 1 {
    raise UnsupportedAbi(
      message="platform calls support at most one direct result",
    )
  }
  let target = match call.callee {
    External(symbol) => symbol
    _ =>
      raise UnsupportedAbi(
        message="platform calls require a direct external symbol",
      )
  }
  let result_registers = platform_result_registers(call.signature.results)
  let inputs = operands.map(@vcode.Input::any)
  let outputs = Array::makei(result_types.length(), index => {
    @vcode.Output::any(result_types[index])
  })
  (builder.append_body(
    block,
    PlatformCall(target, call.signature),
    inputs,
    [],
    platform_call_clobbers(),
    metadata,
  ) catch {
    error => raise BuildFailure(cause=error)
  })
  |> ignore
  let results : Array[@vcode.Value] = []
  for index, ty in result_types {
    let (_, materialized) = builder.append_body(
      block,
      IncomingCallResult(ty, result_registers[index]),
      [],
      [outputs[index]],
      [],
      @vcode.InstructionMetadata::empty(),
    ) catch {
      error => raise BuildFailure(cause=error)
    }
    results.push(materialized[0])
  }
  for root in metadata.live_gc_roots {
    (builder.append_body(
      block,
      KeepAlive(GcRef64),
      [@vcode.Input::any(root)],
      [],
      [],
      @vcode.InstructionMetadata::empty(),
    ) catch {
      error => raise BuildFailure(cause=error)
    })
    |> ignore
  }
  results
}

///|
fn lower_internal_call(
  context : LoweringContext,
  builder : @vcode.Builder[AArch64Inst],
  block : @vcode.Block,
  call : @semantic.SemanticCall,
  operands : Array[@vcode.Value],
  result_types : Array[@semantic.ValueType],
  metadata : @vcode.InstructionMetadata,
) -> Array[@vcode.Value] raise AArch64LowerError {
  if call.protocol != Internal {
    raise UnsupportedAbi(message="internal call requires the internal protocol")
  }
  if call.behavior.returns_twice {
    raise UnsupportedAbi(
      message="returns-twice internal calls are not supported",
    )
  }
  let target = match call.callee {
    Internal(symbol) => Some(symbol)
    Indirect => None
    External(_) =>
      raise UnsupportedAbi(
        message="internal calls require a code symbol or function pointer",
      )
  }
  let plan = context.internal_abi.call_plan(call.signature) catch {
    error => raise UnsupportedAbi(message=error.to_string())
  }
  (builder.append_body(
    block,
    match target {
      Some(target) => InternalCall(target, call.signature, plan)
      None => InternalCallIndirect(call.signature, plan)
    },
    operands.map(@vcode.Input::any),
    [],
    platform_call_clobbers(),
    metadata,
  ) catch {
    error => raise BuildFailure(cause=error)
  })
  |> ignore
  let results : Array[@vcode.Value] = []
  for index, ty in result_types {
    let (_, materialized) = builder.append_body(
      block,
      IncomingCallResult(ty, plan.results[index]),
      [],
      [@vcode.Output::any(ty)],
      [],
      @vcode.InstructionMetadata::empty(),
    ) catch {
      error => raise BuildFailure(cause=error)
    }
    results.push(materialized[0])
  }
  for root in metadata.live_gc_roots {
    (builder.append_body(
      block,
      KeepAlive(GcRef64),
      [@vcode.Input::any(root)],
      [],
      [],
      @vcode.InstructionMetadata::empty(),
    ) catch {
      error => raise BuildFailure(cause=error)
    })
    |> ignore
  }
  results
}

///|
fn lower_instruction(
  function : @semantic.Function,
  context : LoweringContext,
  builder : @vcode.Builder[AArch64Inst],
  block : @vcode.Block,
  block_index : Int,
  instruction : @semantic.Instruction,
  values : Array[@vcode.Value?],
) -> Unit raise AArch64LowerError {
  let instruction_index = function.instruction_index(instruction).unwrap()
  let operation = function.instruction_operation(instruction).unwrap()
  let semantic_operands = function.instruction_operands(instruction)
  let operands = map_values(function, values, semantic_operands)
  let semantic_results = function.instruction_results(instruction)
  let result_types = semantic_results.map(value => {
    function.value_type(value).unwrap()
  })
  let roots = map_values(
    function,
    values,
    function.instruction_metadata(instruction).unwrap().live_gc_roots,
  )
  if operation is Call(call) {
    let metadata = source_metadata(
      function.instruction_metadata(instruction).unwrap(),
      roots,
      operation.semantics(),
    )
    let results = match call.protocol {
      Platform =>
        lower_direct_platform_call(
          builder, block, call, operands, result_types, metadata,
        )
      Internal =>
        lower_internal_call(
          context, builder, block, call, operands, result_types, metadata,
        )
    }
    for index, result in semantic_results {
      values[function.value_index(result).unwrap()] = Some(results[index])
    }
    return
  }
  let selected = match operation {
    I32Const(bits) => Some(LoadConstant(W32, bits.to_uint64()))
    I64Const(bits) => Some(LoadConstant(W64, bits))
    Copy if result_types.length() == 1 => Some(Move(result_types[0]))
    IntUnary(Not) =>
      match optional_gpr_width(result_types.get(0)) {
        Some(width) => Some(IntUnary(width, Mvn))
        None => None
      }
    IntUnary(CountLeadingZeros) =>
      match optional_gpr_width(result_types.get(0)) {
        Some(width) => Some(IntUnary(width, Clz))
        None => None
      }
    IntBinary(binary) =>
      match (optional_gpr_width(result_types.get(0)), lower_binary(binary)) {
        (Some(width), Some(binary)) => Some(IntBinary(width, binary))
        _ => None
      }
    IntCompare(comparison) => {
      let operand_type = match semantic_operands.get(0) {
        Some(value) => function.value_type(value)
        None => None
      }
      match optional_gpr_width(operand_type) {
        Some(width) => Some(CompareSet(width, lower_condition(comparison)))
        None => None
      }
    }
    PointerOffset => Some(AddAddress)
    _ => None
  }
  let selected = match selected {
    Some(selected) => selected
    None =>
      raise UnsupportedOperation(block_index~, instruction_index~, operation~)
  }
  let results = append_body(
    builder,
    block,
    selected,
    operands.map(@vcode.Input::any),
    result_types.map(@vcode.Output::any),
    source_metadata(
      function.instruction_metadata(instruction).unwrap(),
      roots,
      operation.semantics(),
    ),
  )
  for index, result in semantic_results {
    values[function.value_index(result).unwrap()] = Some(results[index])
  }
}

///|
fn lower_parameters(
  function : @semantic.Function,
  context : LoweringContext,
  builder : @vcode.Builder[AArch64Inst],
  values : Array[@vcode.Value?],
) -> Unit raise AArch64LowerError {
  let entry = builder.entry_block()
  let signature = function.signature()
  let layout = match function.protocol() {
    Platform => platform_call_layout(signature.params)
    Internal =>
      context.internal_abi.call_layout(signature) catch {
        error => raise UnsupportedAbi(message=error.to_string())
      }
  }
  for index, parameter in function.parameters() {
    let ty = function.value_type(parameter).unwrap()
    let raw = builder.parameter(index) catch {
      error => raise BuildFailure(cause=error)
    }
    let selected = match layout.arguments[index] {
      CallRegister(reg) =>
        append_body(
          builder,
          entry,
          IncomingReg(ty, reg),
          [@vcode.Input::fixed(raw, reg)],
          [@vcode.Output::any(ty)],
          @vcode.InstructionMetadata::empty(),
        )[0]
      CallStack(offset) =>
        append_body(
          builder,
          entry,
          IncomingStack(ty, offset),
          [],
          [@vcode.Output::any(ty)],
          @vcode.InstructionMetadata::empty(),
        )[0]
    }
    values[function.value_index(parameter).unwrap()] = Some(selected)
  }
}

///|
fn lower_return_values(
  function : @semantic.Function,
  context : LoweringContext,
  builder : @vcode.Builder[AArch64Inst],
  block : @vcode.Block,
  values : Array[@vcode.Value],
  result_types : Array[@semantic.ValueType],
) -> Unit raise AArch64LowerError {
  let registers = match function.protocol() {
    Platform => {
      if result_types.length() > 1 {
        raise UnsupportedAbi(
          message="platform functions support at most one direct result",
        )
      }
      platform_result_registers(result_types)
    }
    Internal =>
      context.internal_abi.result_registers(result_types) catch {
        error => raise UnsupportedAbi(message=error.to_string())
      }
  }
  for index, value in values {
    let ty = result_types[index]
    let reg = registers[index]
    append_body(
      builder,
      block,
      OutgoingReg(ty, reg),
      [@vcode.Input::any(value)],
      [],
      @vcode.InstructionMetadata::empty(),
    )
    |> ignore
  }
}

///|
fn set_terminator(
  builder : @vcode.Builder[AArch64Inst],
  block : @vcode.Block,
  instruction : AArch64Inst,
  inputs : Array[@vcode.Input],
  successors : Array[@vcode.Edge],
  metadata : @vcode.InstructionMetadata,
) -> Unit raise AArch64LowerError {
  (builder.set_terminator(block, instruction, inputs, successors, [], metadata)
  |> ignore) catch {
    error => raise BuildFailure(cause=error)
  }
}

///|
pub fn lower(
  function : @semantic.Function,
  context : LoweringContext,
) -> @vcode.Function[AArch64Inst] raise AArch64LowerError {
  function.verify() catch {
    error => raise InvalidSemantic(cause=error)
  }
  let signature = function.signature()
  let builder : @vcode.Builder[AArch64Inst] = @vcode.Builder::new_with_results(
    function.name(),
    signature.params,
    signature.results,
  )
  let values : Array[@vcode.Value?] = Array::make(function.value_count(), None)
  lower_parameters(function, context, builder, values)
  let semantic_blocks = function.blocks()
  let blocks : Array[@vcode.Block] = []
  for index, semantic_block in semantic_blocks {
    let block = if index == 0 {
      builder.entry_block()
    } else {
      builder.create_block(
        function
        .block_parameters(semantic_block)
        .map(value => function.value_type(value).unwrap()),
      )
    }
    blocks.push(block)
    for parameter_index, parameter in function.block_parameters(semantic_block) {
      values[function.value_index(parameter).unwrap()] = Some(
        builder.block_parameter(block, parameter_index) catch {
          error => raise BuildFailure(cause=error)
        },
      )
    }
  }
  for block_index, semantic_block in semantic_blocks {
    let block = blocks[block_index]
    for instruction in function.block_instructions(semantic_block) {
      lower_instruction(
        function, context, builder, block, block_index, instruction, values,
      )
    }
    let record = function.block_terminator(semantic_block).unwrap()
    let metadata = match record.metadata.source {
      Some(source) => @vcode.InstructionMetadata::new(source~)
      None => @vcode.InstructionMetadata::empty()
    }
    match record.kind {
      Jump(edge) =>
        set_terminator(
          builder,
          block,
          Jump,
          [],
          [
            @vcode.Edge::new(
              blocks[function.block_index(edge.target).unwrap()],
              map_values(function, values, edge.arguments),
            ),
          ],
          metadata,
        )
      Branch(condition, true_edge, false_edge) =>
        set_terminator(
          builder,
          block,
          BranchNonZero32,
          [@vcode.Input::any(map_value(function, values, condition))],
          [
            @vcode.Edge::new(
              blocks[function.block_index(true_edge.target).unwrap()],
              map_values(function, values, true_edge.arguments),
            ),
            @vcode.Edge::new(
              blocks[function.block_index(false_edge.target).unwrap()],
              map_values(function, values, false_edge.arguments),
            ),
          ],
          metadata,
        )
      Return(return_values) => {
        let mapped = map_values(function, values, return_values)
        lower_return_values(
          function,
          context,
          builder,
          block,
          mapped,
          signature.results,
        )
        set_terminator(builder, block, Return, [], [], metadata)
      }
      terminator => raise UnsupportedTerminator(block_index~, terminator~)
    }
  }
  let lowered = builder.finish()
  verify_vcode(lowered) catch {
    error => raise InvalidTarget(cause=error)
  }
  lowered
}
