///|
priv struct SinkTrace {
  operations : Array[Operation]
  operands : Array[Array[Int]]
  roots : Array[Array[Int]]
  stack_maps : Array[@native.StackMapMetadata?]
  stack_objects : Array[(Int, Int)]
  terminated_blocks : Array[Int]
  terminators : Array[TargetTerminator]
  mut next_value : Int
  mut finished : Bool
}

///|
fn traced_sink(
  parameters : Array[Int],
  entry_block : Int,
) -> (TargetSink, SinkTrace) {
  let trace : SinkTrace = {
    operations: [],
    operands: [],
    roots: [],
    stack_maps: [],
    stack_objects: [],
    terminated_blocks: [],
    terminators: [],
    next_value: 1001,
    finished: false,
  }
  let sink = TargetSink::new(
    fn() { parameters.copy() },
    fn() { entry_block },
    fn(parameter_types) {
      let block = 701 + trace.terminated_blocks.length() * 13
      let values = parameter_types.map(_ => {
        let value = trace.next_value
        trace.next_value += 17
        value
      })
      (block, values)
    },
    fn(size, alignment) {
      let id = trace.stack_objects.length()
      trace.stack_objects.push((size, alignment))
      id
    },
    fn(_) { () },
    fn(_, operation, operands, result_types, _, roots, stack_map) {
      trace.operations.push(operation)
      trace.operands.push(operands.copy())
      trace.roots.push(roots.copy())
      trace.stack_maps.push(stack_map)
      result_types.map(_ => {
        let value = trace.next_value
        trace.next_value += 17
        value
      })
    },
    fn(block, terminator, _) {
      trace.terminated_blocks.push(block)
      trace.terminators.push(terminator)
    },
    fn() { trace.finished = true },
  )
  (sink, trace)
}

///|
fn platform_call(
  symbol : String,
  parameters : Array[@native.ValueType],
  results : Array[@native.ValueType],
  gc_safepoint? : Bool = false,
) -> @native.NativeCall {
  @native.NativeCall::new(
    External(@native.ExternalSymbol::new(symbol)),
    @native.Signature::new(parameters, results),
    Platform,
    @native.CallBehavior::new(ReadWrite, true, false, gc_safepoint, false),
  )
}

///|
test "direct builder maps transient handles to non-dense target ids" {
  let (sink, trace) = traced_sink([101, 303], 509)
  let builder = DirectBuilder::new([I64, I64], sink)
  let parameters = builder.parameters()
  let result = builder.emit_with_metadata(
      IntBinary(Add),
      parameters,
      [I64],
      InstructionMetadata::empty(),
    )[0]
  builder.return_([result])
  builder.finish()
  debug_inspect(trace.operands, content="[[101, 303]]")
  debug_inspect(trace.terminated_blocks, content="[509]")
  guard trace.terminators[0] is Return(returned) else {
    fail("expected return terminator")
  }
  debug_inspect(returned, content="[1001]")
  inspect(trace.finished, content="true")
}

///|
test "direct builder elaborates caller roots in the lowering stream" {
  let (sink, trace) = traced_sink([11, 22], 509)
  let builder = DirectBuilder::new(
    [Ptr64, GcRef64],
    sink,
    call_abi=CallAbiElaboration::new(
      root_scope=CallerRootScopeAbi::new(
        @native.ExternalSymbol::new("runtime.push_roots"),
        @native.ExternalSymbol::new("runtime.pop_roots"),
      ),
    ),
    root_scope_capacity=1,
  )
  let parameters = builder.parameters()
  let result = builder.emit_with_metadata(
      Call(platform_call("host.call", [Ptr64], [I64])),
      [parameters[0]],
      [I64],
      InstructionMetadata::new(None, [parameters[1]]),
    )[0]
  builder.return_([result])
  builder.finish()
  debug_inspect(trace.stack_objects, content="[(8, 16)]")
  inspect(trace.operations.length(), content="6")
  assert_true(trace.operations[0] is StackAddress(_))
  assert_true(trace.operations[1] is Store(_))
  assert_true(trace.operations[2] is I32Const(1U))
  guard trace.operations[3] is Call(push) else {
    fail("expected caller-root push")
  }
  guard trace.operations[4] is Call(actual) else {
    fail("expected original call")
  }
  guard trace.operations[5] is Call(pop) else {
    fail("expected caller-root pop")
  }
  guard push.callee is External(push_symbol) else {
    fail("expected external caller-root push")
  }
  guard actual.callee is External(actual_symbol) else {
    fail("expected external original call")
  }
  guard pop.callee is External(pop_symbol) else {
    fail("expected external caller-root pop")
  }
  inspect(push_symbol.name, content="runtime.push_roots")
  inspect(actual_symbol.name, content="host.call")
  inspect(pop_symbol.name, content="runtime.pop_roots")
  inspect(trace.operands[1][1], content="22")
  debug_inspect(trace.roots[4], content="[22]")
}

///|
test "direct builder does not reserve an unused caller-root stack object" {
  let (sink, trace) = traced_sink([], 509)
  let builder = DirectBuilder::new(
    [],
    sink,
    call_abi=CallAbiElaboration::new(
      root_scope=CallerRootScopeAbi::new(
        @native.ExternalSymbol::new("runtime.push_roots"),
        @native.ExternalSymbol::new("runtime.pop_roots"),
      ),
    ),
    root_scope_capacity=4,
  )
  inspect(trace.stack_objects.length(), content="0")
  let object = builder.create_stack_object(16, 16)
  let address = builder.emit_with_metadata(
      StackAddress(object),
      [],
      [Ptr64],
      InstructionMetadata::empty(),
    )[0]
  builder.return_([address])
  builder.finish()
  debug_inspect(trace.stack_objects, content="[(16, 16)]")
  assert_true(trace.operations[0] is StackAddress({ id: 0, }))
}

///|
test "direct builder assigns hidden allocation stack maps monotonically" {
  let (sink, trace) = traced_sink([11, 22, 33, 44], 509)
  let allocation_symbol = @native.ExternalSymbol::new("runtime.allocate")
  let builder = DirectBuilder::new(
    [Ptr64, I32, I32, I64],
    sink,
    call_abi=CallAbiElaboration::new(hidden_safepoints=[
      HiddenSafepointAbi::new(allocation_symbol, AllocationOperands),
    ]),
  )
  let parameters = builder.parameters()
  let call = platform_call(
    "runtime.allocate",
    [Ptr64, I32, I32, I64],
    [GcRef64],
    gc_safepoint=true,
  )
  let first = builder.emit_with_metadata(
      Call(call),
      parameters,
      [GcRef64],
      InstructionMetadata::empty(),
    )[0]
  let second = builder.emit_with_metadata(
      Call(call),
      parameters,
      [GcRef64],
      InstructionMetadata::empty(),
    )[0]
  builder.return_([first, second])
  builder.finish()
  inspect(trace.operations.length(), content="4")
  assert_true(trace.operations[0] is I32Const(0U))
  assert_true(trace.operations[2] is I32Const(1U))
  guard trace.operations[1] is Call(first_call) else {
    fail("expected first allocation call")
  }
  guard trace.operations[3] is Call(second_call) else {
    fail("expected second allocation call")
  }
  inspect(first_call.signature.params.length(), content="5")
  inspect(second_call.signature.params.length(), content="5")
  debug_inspect(trace.operands[1], content="[11, 22, 33, 44, 1001]")
  guard trace.stack_maps[1] is Some(first_map) else {
    fail("expected first hidden stack map")
  }
  guard trace.stack_maps[3] is Some(second_map) else {
    fail("expected second hidden stack map")
  }
  inspect(first_map.id, content="0")
  inspect(first_map.argument_root_count, content="1")
  inspect(second_map.id, content="1")
  inspect(second_map.argument_root_count, content="1")
}
