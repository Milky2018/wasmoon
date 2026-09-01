///|
test "call ABI elaboration preserves existing instruction and value handles" {
  let builder = FunctionBuilder::new(
    "call_abi_identity",
    Internal,
    [@native.Ptr64, @native.GcRef64],
    [@native.I64],
  )
  let parameters = builder.parameters()
  let result = builder.emit_with_metadata(
      Call(
        SemanticCall::new(
          External(@native.ExternalSymbol::new("host.call")),
          @native.Signature::new([@native.Ptr64], [@native.I64]),
          Platform,
          @native.CallBehavior::new(ReadWrite, true, false, true, false),
        ),
      ),
      [parameters[0]],
      [@native.I64],
      InstructionMetadata::new(None, [parameters[1]]),
    )[0]
  builder.return_([result])
  let function = builder.finish()
  let call_instruction = function.block_instructions(function.blocks()[0])[0]
  let elaborated = function.elaborate_call_abi(
    CallAbiElaboration::new(
      root_scope=CallerRootScopeAbi::new(
        @native.ExternalSymbol::new("runtime.push_roots"),
        @native.ExternalSymbol::new("runtime.pop_roots"),
      ),
    ),
  )
  assert_eq(elaborated.instruction_index(call_instruction), Some(0))
  assert_eq(elaborated.value_index(result), Some(2))
  assert_true(
    elaborated
    .block_instructions(elaborated.blocks()[0])
    .contains(call_instruction),
  )
}

///|
test "call ABI elaboration leaves no-op functions unchanged" {
  let builder = FunctionBuilder::new("call_abi_noop", Internal, [], [
    @native.I32,
  ])
  let result = builder.emit(I32Const(42U), [], [@native.I32])[0]
  builder.return_([result])
  let function = builder.finish()
  let instructions = function.block_instructions(function.blocks()[0])
  let elaborated = function.elaborate_call_abi(CallAbiElaboration::new())
  inspect(elaborated.instruction_count(), content="1")
  assert_eq(elaborated.instruction_index(instructions[0]), Some(0))
  assert_eq(elaborated.value_index(result), Some(0))
}

///|
test "selection plan elaborates caller GC roots without semantic Function" {
  let builder = FunctionBuilder::new(
    "selection_plan_call_abi",
    Internal,
    [@native.Ptr64, @native.GcRef64],
    [@native.I64],
  )
  let parameters = builder.parameters()
  let result = builder.emit_with_metadata(
      Call(
        SemanticCall::new(
          External(@native.ExternalSymbol::new("host.call")),
          @native.Signature::new([@native.Ptr64], [@native.I64]),
          Platform,
          @native.CallBehavior::new(ReadWrite, true, false, true, false),
        ),
      ),
      [parameters[0]],
      [@native.I64],
      InstructionMetadata::new(None, [parameters[1]]),
    )[0]
  builder.return_([result])
  let prepared = builder
    .finish_prepared_selection()
    .elaborate_call_abi(
      CallAbiElaboration::new(
        root_scope=CallerRootScopeAbi::new(
          @native.ExternalSymbol::new("runtime.push_roots"),
          @native.ExternalSymbol::new("runtime.pop_roots"),
        ),
      ),
    )
  let plan = prepared.seal()
  plan.require_verified()
  let view = plan.view()
  assert_eq(view.stack_object_count(), 1)
  let instructions = view.block(0).instructions()
  assert_eq(instructions.length(), 6)
  let operations = Array::makei(6, index => {
    view.instruction(instructions[index]).operation()
  })
  assert_true(operations[0] is StackAddress(_))
  assert_true(operations[1] is Store(_))
  assert_true(operations[2] is I32Const(1U))
  assert_true(operations[3] is Call(_))
  assert_true(operations[4] is Call(_))
  assert_true(operations[5] is Call(_))
}

///|
test "sealed selection plan rejects retained prepared aliases" {
  let builder = FunctionBuilder::new_selection_plan(
    "sealed_selection_plan",
    Internal,
    [],
    [@native.I32],
  )
  let result = builder.emit(I32Const(42U), [], [@native.I32])[0]
  builder.return_([result])
  let prepared = builder.finish_prepared_selection()
  prepared.seal() |> ignore
  try prepared.elaborate_call_abi(CallAbiElaboration::new()) catch {
    InvalidInput(cause=InvalidSelectionState(message~)) =>
      inspect(message, content="selection input has already been sealed")
    error => fail("unexpected error: \{error}")
  } noraise {
    _ => fail("expected sealed prepared input to reject elaboration")
  }
}
