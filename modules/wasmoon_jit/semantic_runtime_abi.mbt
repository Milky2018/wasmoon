///|
fn require_mapped_value(
  function : @semantic_machv.Function,
  values : Array[@semantic_machv.Value?],
  value : @semantic_machv.Value,
) -> @semantic_machv.Value raise JitPipelineError {
  guard function.value_index(value) is Some(index) else {
    raise PipelineFailure(
      message="\{function.name()}: runtime ABI elaboration used an unmapped value",
    )
  }
  match values[index] {
    Some(mapped) => mapped
    None =>
      raise PipelineFailure(
        message="\{function.name()}: runtime ABI elaboration used an unmapped value",
      )
  }
}

///|
fn mapped_values(
  function : @semantic_machv.Function,
  values : Array[@semantic_machv.Value?],
  source : Array[@semantic_machv.Value],
) -> Array[@semantic_machv.Value] raise JitPipelineError {
  source.map(value => require_mapped_value(function, values, value))
}

///|
fn mapped_block(
  function : @semantic_machv.Function,
  blocks : Array[@semantic_machv.Block],
  block : @semantic_machv.Block,
) -> @semantic_machv.Block raise JitPipelineError {
  guard function.block_index(block) is Some(index) else {
    raise PipelineFailure(
      message="\{function.name()}: runtime ABI elaboration used an unmapped block",
    )
  }
  blocks[index]
}

///|
fn allocation_argument_root_count(
  function : @semantic_machv.Function,
  call : @semantic_machv.SemanticCall,
  operands : Array[@semantic_machv.Value],
  integer_constants : Array[Int64?],
) -> Int raise JitPipelineError {
  match call.signature.params {
    [Ptr64, I32, I32, I64] => 1
    [Ptr64, I32, Ptr64, I32] => {
      guard operands.length() == 4 else {
        raise PipelineFailure(
          message="\{function.name()}: allocation root count must be a compile-time i32 constant",
        )
      }
      guard function.value_index(operands[3]) is Some(index) else {
        raise PipelineFailure(
          message="\{function.name()}: allocation root count must be a compile-time i32 constant",
        )
      }
      guard integer_constants[index] is Some(count) &&
        count >= 0L &&
        count <= @types.I32_MAX.to_int64() else {
        raise PipelineFailure(
          message="\{function.name()}: allocation root count must be a compile-time i32 constant",
        )
      }
      count.to_int()
    }
    _ =>
      raise PipelineFailure(
        message="\{function.name()}: allocation helper has an unsupported ABI",
      )
  }
}

///|
fn call_context(
  function : @semantic_machv.Function,
  call : @semantic_machv.SemanticCall,
  operands : Array[@semantic_machv.Value],
) -> @semantic_machv.Value raise JitPipelineError {
  let index = match call.protocol {
    Internal => if call.callee is Indirect { 1 } else { 0 }
    Platform => 0
  }
  guard operands.length() > index &&
    function.value_type(operands[index]) == Some(Ptr64) else {
    raise PipelineFailure(
      message="\{function.name()}: precise roots require a ptr64 execution environment",
    )
  }
  operands[index]
}

///|
fn emit_root_scope_push(
  builder : @semantic_machv.FunctionBuilder,
  context : @semantic_machv.Value,
  roots : Array[@semantic_machv.Value],
  symbol : @semantic_machv.ExternalSymbol,
) -> Unit {
  let object = builder.create_stack_object(roots.length() * 8, 16)
  let address = builder.emit(StackAddress(object), [], [Ptr64])[0]
  for index, root in roots {
    builder.emit(
      Store(
        @semantic_machv.StoreSpec::new(
          W64,
          GcRef64,
          (index * 8).to_uint64(),
          Little,
          None,
        ),
      ),
      [address, root],
      [],
    )
    |> ignore
  }
  let count = builder.emit(I32Const(roots.length().reinterpret_as_uint()), [], [
      I32,
    ])[0]
  builder.emit(
    Call(
      @semantic_machv.SemanticCall::new(
        External(symbol),
        @semantic_machv.Signature::new([Ptr64, Ptr64, I32], []),
        Platform,
        @semantic_machv.CallBehavior::new(ReadWrite, true, false, false, false),
      ),
    ),
    [context, address, count],
    [],
  )
  |> ignore
}

///|
fn emit_root_scope_pop(
  builder : @semantic_machv.FunctionBuilder,
  context : @semantic_machv.Value,
  symbol : @semantic_machv.ExternalSymbol,
) -> Unit {
  builder.emit(
    Call(
      @semantic_machv.SemanticCall::new(
        External(symbol),
        @semantic_machv.Signature::new([Ptr64], []),
        Platform,
        @semantic_machv.CallBehavior::new(ReadWrite, true, false, false, false),
      ),
    ),
    [context],
    [],
  )
  |> ignore
}

///|
fn copy_terminator(
  function : @semantic_machv.Function,
  builder : @semantic_machv.FunctionBuilder,
  blocks : Array[@semantic_machv.Block],
  values : Array[@semantic_machv.Value?],
  record : @semantic_machv.TerminatorRecord,
) -> Unit raise JitPipelineError {
  match record.kind {
    Jump(edge) =>
      builder.jump(
        mapped_block(function, blocks, edge.target),
        mapped_values(function, values, edge.arguments),
      )
    Branch(condition, true_edge, false_edge) =>
      builder.branch(
        require_mapped_value(function, values, condition),
        mapped_block(function, blocks, true_edge.target),
        mapped_values(function, values, true_edge.arguments),
        mapped_block(function, blocks, false_edge.target),
        mapped_values(function, values, false_edge.arguments),
      )
    Switch(index, cases, default_edge) => {
      let mapped_cases = cases.map(case => {
        (
          case.bits,
          mapped_block(function, blocks, case.edge.target),
          mapped_values(function, values, case.edge.arguments),
        )
      })
      builder.switch(
        require_mapped_value(function, values, index),
        mapped_cases,
        mapped_block(function, blocks, default_edge.target),
        mapped_values(function, values, default_edge.arguments),
      )
    }
    Return(returned) =>
      builder.return_(mapped_values(function, values, returned))
    TailCall(call, operands) =>
      builder.tail_call_with_metadata(
        call,
        mapped_values(function, values, operands),
        @semantic_machv.TerminatorMetadata::new(
          record.metadata.source,
          mapped_values(function, values, record.metadata.live_gc_roots),
        ),
      )
    NoReturnCall(call, operands) =>
      builder.noreturn_call_with_metadata(
        call,
        mapped_values(function, values, operands),
        @semantic_machv.TerminatorMetadata::new(
          record.metadata.source,
          mapped_values(function, values, record.metadata.live_gc_roots),
        ),
      )
    Trap(reason) => builder.trap(reason)
  }
  if record.metadata.source is Some(source) &&
    !(record.kind is TailCall(_, _) || record.kind is NoReturnCall(_, _)) {
    builder.set_terminator_source(source)
  }
}

///|
fn elaborate_wasmoon_runtime_abi(
  function : @semantic_machv.Function,
  allocation_symbols : Array[@semantic_machv.ExternalSymbol],
  root_scope_symbols : (
    @semantic_machv.ExternalSymbol,
    @semantic_machv.ExternalSymbol,
  ),
) -> @semantic_machv.Function raise JitPipelineError {
  function.verify() catch {
    error =>
      raise PipelineFailure(
        message="\{function.name()}: invalid semantic MachV before runtime ABI elaboration: \{error.to_string()}",
      )
  }
  let signature = function.signature()
  let builder = @semantic_machv.FunctionBuilder::new(
    function.name(),
    function.protocol(),
    signature.params,
    signature.results,
  )
  let values : Array[@semantic_machv.Value?] = Array::make(
    function.value_count(),
    None,
  )
  for index, parameter in function.parameters() {
    values[function.value_index(parameter).unwrap()] = Some(
      builder.parameters()[index],
    )
  }
  let blocks : Array[@semantic_machv.Block] = [builder.entry_block()]
  for index, block in function.blocks() {
    if index > 0 {
      let types = function
        .block_parameters(block)
        .map(value => function.value_type(value).unwrap())
      blocks.push(builder.create_block(types))
    }
    for parameter_index, parameter in function.block_parameters(block) {
      values[function.value_index(parameter).unwrap()] = Some(
        builder.block_parameters(blocks[index])[parameter_index],
      )
    }
  }
  let stack_objects : Array[@semantic_machv.StackObject] = []
  for object in function.stack_objects() {
    stack_objects.push(
      builder.create_stack_object(
        function.stack_object_size(object).unwrap(),
        function.stack_object_alignment(object).unwrap(),
      ),
    )
  }
  let integer_constants : Array[Int64?] = Array::make(
    function.value_count(),
    None,
  )
  let mut next_stack_map_id = 0
  for block in function.blocks() {
    for instruction in function.block_instructions(block) {
      if function.instruction_metadata(instruction).unwrap().stack_map
        is Some(_) {
        next_stack_map_id += 1
      }
    }
  }
  let (push_symbol, pop_symbol) = root_scope_symbols
  for block in function.blocks_in_cfg_order() {
    let block_index = function.block_index(block).unwrap()
    builder.switch_to_block(blocks[block_index])
    for instruction in function.block_instructions(block) {
      let operation = function.instruction_operation(instruction).unwrap()
      let old_operands = function.instruction_operands(instruction)
      let operands = mapped_values(function, values, old_operands)
      let old_results = function.instruction_results(instruction)
      let result_types = old_results.map(value => {
        function.value_type(value).unwrap()
      })
      let old_metadata = function.instruction_metadata(instruction).unwrap()
      let roots = mapped_values(function, values, old_metadata.live_gc_roots)
      let mut copied_operation = match operation {
        StackAddress(object) => {
          let index = function.stack_objects().search(object).unwrap()
          @semantic_machv.StackAddress(stack_objects[index])
        }
        _ => operation
      }
      let copied_operands = operands
      let mut stack_map = old_metadata.stack_map
      let mut root_scope_context : @semantic_machv.Value? = None
      if operation is Call(call) {
        if !roots.is_empty() {
          if call.behavior.returns_twice {
            raise PipelineFailure(
              message="\{function.name()}: returns-twice calls cannot use a caller root scope",
            )
          }
          let context = call_context(function, call, old_operands)
          let mapped_context = require_mapped_value(function, values, context)
          emit_root_scope_push(builder, mapped_context, roots, push_symbol)
          root_scope_context = Some(mapped_context)
        }
        let hidden_safepoint = match call.callee {
          External(symbol) => allocation_symbols.contains(symbol)
          _ => false
        }
        if hidden_safepoint {
          if call.protocol != Platform || !call.behavior.gc_safepoint {
            raise PipelineFailure(
              message="\{function.name()}: allocation helper must be a platform GC safepoint",
            )
          }
          if stack_map is Some(_) {
            raise PipelineFailure(
              message="\{function.name()}: allocation helper already has stack-map metadata",
            )
          }
          let argument_root_count = allocation_argument_root_count(
            function, call, old_operands, integer_constants,
          )
          let id_value = builder.emit(
              I32Const(next_stack_map_id.reinterpret_as_uint()),
              [],
              [I32],
            )[0]
          copied_operands.push(id_value)
          let parameters = call.signature.params.copy()
          parameters.push(I32)
          copied_operation = Call(
            @semantic_machv.SemanticCall::new(
              call.callee,
              @semantic_machv.Signature::new(parameters, call.signature.results),
              call.protocol,
              call.behavior,
            ),
          )
          stack_map = Some(
            @semantic_machv.StackMapMetadata::new(
              next_stack_map_id,
              argument_root_count~,
            ),
          )
          next_stack_map_id += 1
        }
      }
      let new_results = builder.emit_with_metadata(
        copied_operation,
        copied_operands,
        result_types,
        @semantic_machv.InstructionMetadata::new(
          old_metadata.source,
          roots,
          stack_map?,
        ),
      )
      for index, old_result in old_results {
        let value_index = function.value_index(old_result).unwrap()
        values[value_index] = Some(new_results[index])
        integer_constants[value_index] = match operation {
          I32Const(bits) =>
            Some(bits.reinterpret_as_int().to_int64() & 0xFFFFFFFFL)
          I64Const(bits) => Some(bits.reinterpret_as_int64())
          Copy if old_operands is [source] =>
            integer_constants[function.value_index(source).unwrap()]
          _ => None
        }
      }
      if root_scope_context is Some(context) {
        emit_root_scope_pop(builder, context, pop_symbol)
      }
    }
    copy_terminator(
      function,
      builder,
      blocks,
      values,
      function.block_terminator(block).unwrap(),
    )
  }
  builder.finish() catch {
    error =>
      raise PipelineFailure(
        message="\{function.name()}: invalid semantic MachV after runtime ABI elaboration: \{error.to_string()}",
      )
  }
}
