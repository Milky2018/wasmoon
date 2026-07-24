///|
test "environment analysis groups semantic uses without choosing materialization" {
  let stable_field = @machv.EnvironmentField::new("runtime.memory.base", I64)
  let mutable_field = @machv.EnvironmentField::new("runtime.table.base", I64)
  let builder = @machv.FunctionBuilder::new(
    "environment_use_groups",
    Internal,
    [Ptr64, Ptr64],
    [I64, I64, I64, I64, I64, I64],
  )
  let parameters = builder.parameters()
  let stable_first = builder.emit(
      EnvironmentField(stable_field, Stable),
      [parameters[0]],
      [I64],
    )[0]
  let stable_second = builder.emit(
      EnvironmentField(stable_field, Stable),
      [parameters[0]],
      [I64],
    )[0]
  builder.emit(
    Call(
      @machv.SemanticCall::new(
        External(@machv.ExternalSymbol::new("runtime.observe")),
        @machv.Signature::new([], []),
        Platform,
        @machv.CallBehavior::conservative(),
      ),
    ),
    [],
    [],
  )
  |> ignore
  let stable_after_call = builder.emit(
      EnvironmentField(stable_field, Stable),
      [parameters[0]],
      [I64],
    )[0]
  let mutable_first = builder.emit(
      EnvironmentField(mutable_field, Mutable),
      [parameters[1]],
      [I64],
    )[0]
  let continuation = builder.create_block([])
  builder.jump(continuation, [])
  builder.switch_to_block(continuation)
  let stable_in_successor = builder.emit(
      EnvironmentField(stable_field, Stable),
      [parameters[0]],
      [I64],
    )[0]
  let mutable_in_successor = builder.emit(
      EnvironmentField(mutable_field, Mutable),
      [parameters[1]],
      [I64],
    )[0]
  builder.return_([
    stable_first, stable_second, stable_after_call, stable_in_successor, mutable_first,
    mutable_in_successor,
  ])
  let function = builder.finish()
  debug_inspect(
    function.environment_field_use_groups(),
    content=(
      #|[
      #|  {
      #|    field: { name: "runtime.memory.base", value_type: I64 },
      #|    stability: Stable,
      #|    context: v0,
      #|    occurrences: [inst0, inst1, inst3, inst5],
      #|    call_free_regions: [
      #|      { block: block0, segment_index: 0, occurrences: [inst0, inst1] },
      #|      { block: block0, segment_index: 1, occurrences: [inst3] },
      #|      { block: block1, segment_index: 0, occurrences: [inst5] },
      #|    ],
      #|    context_use_count: 4,
      #|    can_replace_context_carrier: true,
      #|  },
      #|  {
      #|    field: { name: "runtime.table.base", value_type: I64 },
      #|    stability: Mutable,
      #|    context: v1,
      #|    occurrences: [inst4, inst6],
      #|    call_free_regions: [
      #|      { block: block0, segment_index: 1, occurrences: [inst4] },
      #|      { block: block1, segment_index: 0, occurrences: [inst6] },
      #|    ],
      #|    context_use_count: 2,
      #|    can_replace_context_carrier: false,
      #|  },
      #|]
    ),
  )
}

///|
test "environment analysis rejects carrier replacement for other context uses" {
  let field = @machv.EnvironmentField::new("runtime.memory.base", Ptr64)
  let builder = @machv.FunctionBuilder::new(
    "non_exclusive_environment_context",
    Internal,
    [Ptr64],
    [Ptr64, Ptr64],
  )
  let context = builder.parameters()[0]
  let first = builder.emit(EnvironmentField(field, Stable), [context], [Ptr64])[0]
  builder.emit(
    Call(
      @machv.SemanticCall::new(
        External(@machv.ExternalSymbol::new("runtime.observe_context")),
        @machv.Signature::new([Ptr64], []),
        Platform,
        @machv.CallBehavior::conservative(),
      ),
    ),
    [context],
    [],
  )
  |> ignore
  let second = builder.emit(EnvironmentField(field, Stable), [context], [Ptr64])[0]
  builder.return_([first, second])
  let function = builder.finish()
  debug_inspect(
    function.environment_field_use_groups(),
    content=(
      #|[
      #|  {
      #|    field: { name: "runtime.memory.base", value_type: Ptr64 },
      #|    stability: Stable,
      #|    context: v0,
      #|    occurrences: [inst0, inst2],
      #|    call_free_regions: [
      #|      { block: block0, segment_index: 0, occurrences: [inst0] },
      #|      { block: block0, segment_index: 1, occurrences: [inst2] },
      #|    ],
      #|    context_use_count: 3,
      #|    can_replace_context_carrier: false,
      #|  },
      #|]
    ),
  )
}
