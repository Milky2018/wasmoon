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
