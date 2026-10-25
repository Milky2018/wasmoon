///|
priv struct SinkTrace {
  operations : Array[Operation]
  operands : Array[Array[Int32]]
  roots : Array[Array[Int32]]
  stack_maps : Array[@native.StackMapMetadata?]
  stack_objects : Array[(Int32, Int32)]
  terminated_blocks : Array[Int32]
  terminators : Array[TargetTerminator]
  mut next_block : Int32
  mut next_value : Int32
  mut finished : Bool
}

///|
fn traced_sink(
  parameters : Array[Int32],
  entry_block : Int32,
) -> (TargetSink, SinkTrace) {
  let trace : SinkTrace = {
    operations: [],
    operands: [],
    roots: [],
    stack_maps: [],
    stack_objects: [],
    terminated_blocks: [],
    terminators: [],
    next_block: 701,
    next_value: 1001,
    finished: false,
  }
  let sink = TargetSink::new(
    fn() { parameters.copy() },
    fn() { entry_block },
    fn(parameter_types) {
      let block = trace.next_block
      trace.next_block += 13
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
  gc_safepoint~ : Bool = false,
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

///|
test "immediate comparison contract requires one integer and boolean result" {
  for ty in [@native.ValueType::I32, I64] {
    inspect(
      verify_operation_contract(IntCompareImmediate(Equal, 42UL), [ty], [I32])
      is None,
      content="true",
    )
  }
  let malformed : Array[(Array[@native.ValueType], Array[@native.ValueType])] = [
    ([F64], [I32]),
    ([I32, I32], [I32]),
    ([I64], [I64]),
    ([], [I32]),
  ]
  for (inputs, outputs) in malformed {
    inspect(
      verify_operation_contract(
        IntCompareImmediate(Equal, 42UL),
        inputs,
        outputs,
      )
      is Some(_),
      content="true",
    )
  }
}

///|
test "function roots store definitions once and change precise masks at calls" {
  let (sink, trace) = traced_sink([11, 22], 0)
  let builder = DirectBuilder::new(
    [Ptr64, GcRef64],
    sink,
    call_abi=CallAbiElaboration::new(
      function_frame=FunctionRootFrameAbi::new(
        @native.ExternalSymbol::new("frame.enter"),
        @native.ExternalSymbol::new("frame.leave"),
      ),
    ),
  )
  builder.begin_function_roots(1)
  let parameters = builder.parameters()
  builder.define_function_root(parameters[1])
  for live in [[parameters[1]], []] {
    builder.emit_with_metadata(
      Call(platform_call("guest", [Ptr64], [], gc_safepoint=true)),
      [parameters[0]],
      [],
      InstructionMetadata::new(None, live),
    )
    |> ignore
  }
  builder.return_([])
  builder.finish()
  let calls = trace.operations.filter_map(operation => {
    match operation {
      Call(call) =>
        match call.callee {
          External(symbol) => Some(symbol.name)
          _ => None
        }
      _ => None
    }
  })
  debug_inspect(
    calls,
    content="[\"frame.enter\", \"guest\", \"guest\", \"frame.leave\"]",
  )
  assert_eq(
    trace.operations
    .filter(operation => operation is Store(spec) && spec.value_type == GcRef64)
    .length(),
    1,
  )
  debug_inspect(
    trace.operations.filter_map(operation => {
      match operation {
        I64Const(bits) => Some(bits)
        _ => None
      }
    }),
    content="[0, 1, 0]",
  )
}

///|
test "function root masks cross word boundaries without retaining dead slots" {
  let (sink, trace) = traced_sink(Array::makei(66, index => 100 + index), 0)
  let builder = DirectBuilder::new(
    [Ptr64] + Array::make(65, GcRef64),
    sink,
    call_abi=CallAbiElaboration::new(
      function_frame=FunctionRootFrameAbi::new(
        @native.ExternalSymbol::new("frame.enter"),
        @native.ExternalSymbol::new("frame.leave"),
      ),
    ),
  )
  builder.begin_function_roots(65)
  let parameters = builder.parameters()
  for value in parameters[1:] {
    builder.define_function_root(value)
  }
  builder.emit_with_metadata(
    Call(platform_call("collect", [Ptr64], [], gc_safepoint=true)),
    [parameters[0]],
    [],
    InstructionMetadata::new(None, [parameters[1], parameters[65]]),
  )
  |> ignore
  builder.emit_with_metadata(
    Call(platform_call("collect", [Ptr64], [], gc_safepoint=true)),
    [parameters[0]],
    [],
    InstructionMetadata::empty(),
  )
  |> ignore
  builder.return_([])
  builder.finish()
  debug_inspect(
    trace.operations.filter_map(operation => {
      match operation {
        I64Const(bits) => Some(bits)
        _ => None
      }
    }),
    content="[0, 0, 1, 1, 0, 0]",
  )
}

///|
test "sparse function roots bound mask code growth across safepoints" {
  let capacity = 8192
  let points = 64
  let (sink, trace) = traced_sink([100, 101], 0)
  let builder = DirectBuilder::new(
    [Ptr64, GcRef64],
    sink,
    call_abi=CallAbiElaboration::new(
      function_frame=FunctionRootFrameAbi::new(
        @native.ExternalSymbol::new("frame.enter"),
        @native.ExternalSymbol::new("frame.leave"),
      ),
    ),
  )
  builder.begin_function_roots(capacity)
  let parameters = builder.parameters()
  builder.define_function_root(parameters[1])
  for index in 0..<points {
    builder.emit_with_metadata(
      Call(platform_call("collect", [Ptr64], [], gc_safepoint=true)),
      [parameters[0]],
      [],
      InstructionMetadata::new(
        None,
        if index % 2 == 0 {
          [parameters[1]]
        } else {
          []
        },
      ),
    )
    |> ignore
  }
  builder.return_([])
  builder.finish()
  let mask_stores = trace.operations
    .filter(operation => {
      match operation {
        Store(spec) | StoreIndexed(spec, _) => spec.value_type == I64
        _ => false
      }
    })
    .length()
  // Entry zeroing and repeated sparse safepoints both keep bounded VCode.
  assert_true(mask_stores <= (points + 1) * 8)
  let mut initial_fill = None
  for operation in trace.operations {
    if operation is StoreRepeated64(offset, count, bits) {
      initial_fill = Some((offset, count, bits))
      break
    }
  }
  assert_eq(
    initial_fill,
    Some((0UL, (capacity / 64).reinterpret_as_uint(), 0UL)),
  )
  // Repeated mask writes must not multiply CFG cycles and liveness sets.
  assert_eq(trace.terminated_blocks.length(), 1)
}

///|
test "root aliases defined on sibling paths publish their slot on both paths" {
  let (sink, trace) = traced_sink([11, 22, 33], 0)
  let builder = DirectBuilder::new(
    [Ptr64, GcRef64, I32],
    sink,
    call_abi=CallAbiElaboration::new(
      function_frame=FunctionRootFrameAbi::new(
        @native.ExternalSymbol::new("frame.enter"),
        @native.ExternalSymbol::new("frame.leave"),
      ),
    ),
  )
  builder.begin_function_roots(2)
  let parameters = builder.parameters()
  let left = builder.create_block([])
  let right = builder.create_block([])
  builder.branch(parameters[2], left, [], right, [])
  for block in [left, right] {
    builder.switch_to_block(block)
    // MilkIR copies can forward the same native handle from two distinct SSA
    // binding sites. Neither sibling's store dominates the other sibling.
    builder.define_function_root(parameters[1])
    builder.emit_with_metadata(
      Call(platform_call("collect", [Ptr64], [], gc_safepoint=true)),
      [parameters[0]],
      [],
      InstructionMetadata::new(None, [parameters[1]]),
    )
    |> ignore
    builder.return_([])
  }
  builder.finish()
  assert_eq(
    trace.operations
    .filter(operation => operation is Store(spec) && spec.value_type == GcRef64)
    .length(),
    2,
  )
}

///|
test "registered function frames own roots without duplicate SSA call transport" {
  let (sink, trace) = traced_sink([11, 22], 0)
  let builder = DirectBuilder::new(
    [Ptr64, GcRef64],
    sink,
    call_abi=CallAbiElaboration::new(
      function_frame=FunctionRootFrameAbi::new(
        @native.ExternalSymbol::new("frame.enter"),
        @native.ExternalSymbol::new("frame.leave"),
      ),
    ),
  )
  builder.begin_function_roots(1)
  let parameters = builder.parameters()
  builder.define_function_root(parameters[1])
  builder.emit_with_metadata(
    Call(platform_call("guest", [Ptr64], [], gc_safepoint=true)),
    [parameters[0]],
    [],
    InstructionMetadata::new(
      None,
      [parameters[1]],
      stack_map=@native.StackMapMetadata::new(9, argument_root_count=0),
    ),
  )
  |> ignore
  builder.return_([])
  builder.finish()
  let mut observed = false
  for index, operation in trace.operations {
    if operation is Call(call) &&
      call.callee is External(symbol) &&
      symbol.name == "guest" {
      observed = true
      assert_eq(trace.roots[index], [])
      guard trace.stack_maps[index] is Some(site) else {
        fail("function-root admission lost call-site metadata")
      }
      assert_eq(site.id, 9)
      assert_eq(site.argument_root_count, 0)
      assert_true(call.behavior.gc_safepoint)
    }
  }
  assert_true(observed)
  assert_eq(
    trace.operations
    .filter(operation => operation is Store(spec) && spec.value_type == GcRef64)
    .length(),
    1,
  )
}

///|
test "repeated word stores enforce typed positive ranges without safepoints" {
  let operation = StoreRepeated64(24UL, 65U, 0xFEDCBA9876543210UL)
  assert_true(verify_operation_contract(operation, [Ptr64], []) is None)
  for
    invalid in [
      StoreRepeated64(0UL, 0U, 0UL),
      StoreRepeated64(0xFFFFFFFFFFFFFFF8UL, 2U, 0UL),
    ] {
    assert_true(verify_operation_contract(invalid, [Ptr64], []) is Some(_))
  }
  assert_true(verify_operation_contract(operation, [I64], []) is Some(_))
  assert_true(verify_operation_contract(operation, [Ptr64], [I64]) is Some(_))
  let semantics = operation.semantics()
  assert_eq(semantics.memory, Write)
  assert_false(semantics.gc_safepoint)
  assert_false(semantics.cancellation_safepoint)
  assert_false(semantics.may_trap)
}
