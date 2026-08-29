///|
test "call ABI elaboration preserves existing instruction and value handles" {
  let builder = FunctionBuilder::new(
    "call_abi_identity",
    Internal,
    [Ptr64, GcRef64],
    [I64],
  )
  let parameters = builder.parameters()
  let result = builder.emit_with_metadata(
      Call(
        SemanticCall::new(
          External(ExternalSymbol::new("host.call")),
          Signature::new([Ptr64], [I64]),
          Platform,
          CallBehavior::new(ReadWrite, true, false, true, false),
        ),
      ),
      [parameters[0]],
      [I64],
      InstructionMetadata::new(None, [parameters[1]]),
    )[0]
  builder.return_([result])
  let function = builder.finish()
  let call_instruction = function.block_instructions(function.blocks()[0])[0]
  let elaborated = function.elaborate_call_abi(
    CallAbiElaboration::new(
      root_scope=CallerRootScopeAbi::new(
        ExternalSymbol::new("runtime.push_roots"),
        ExternalSymbol::new("runtime.pop_roots"),
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
  let builder = FunctionBuilder::new("call_abi_noop", Internal, [], [I32])
  let result = builder.emit(I32Const(42U), [], [I32])[0]
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
    [Ptr64, GcRef64],
    [I64],
  )
  let parameters = builder.parameters()
  let result = builder.emit_with_metadata(
      Call(
        SemanticCall::new(
          External(ExternalSymbol::new("host.call")),
          Signature::new([Ptr64], [I64]),
          Platform,
          CallBehavior::new(ReadWrite, true, false, true, false),
        ),
      ),
      [parameters[0]],
      [I64],
      InstructionMetadata::new(None, [parameters[1]]),
    )[0]
  builder.return_([result])
  let plan = builder
    .finish_selection_plan()
    .elaborate_call_abi(
      CallAbiElaboration::new(
        root_scope=CallerRootScopeAbi::new(
          ExternalSymbol::new("runtime.push_roots"),
          ExternalSymbol::new("runtime.pop_roots"),
        ),
      ),
    )
  plan.require_verified()
  assert_eq(plan.stack_objects().length(), 1)
  let entry = plan.block_at(0).unwrap()
  assert_eq(plan.block_instruction_count(entry), Some(6))
  let operations = Array::makei(6, index => {
    match plan.block_instruction_at(entry, index) {
      Some(instruction) => plan.instruction_operation(instruction)
      None => None
    }
  })
  assert_true(operations[0] is Some(StackAddress(_)))
  assert_true(operations[1] is Some(Store(_)))
  assert_true(operations[2] is Some(I32Const(1U)))
  assert_true(operations[3] is Some(Call(_)))
  assert_true(operations[4] is Some(Call(_)))
  assert_true(operations[5] is Some(Call(_)))
}
