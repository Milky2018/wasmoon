///|
fn test_builder(
  parameter_types : Array[@native.ValueType],
  call_abi? : @lowering.CallAbiElaboration,
) -> @lowering.DirectBuilder {
  let next = Ref(parameter_types.length())
  let sink = @lowering.TargetSink::new(
    fn() { Array::makei(parameter_types.length(), i => i) },
    fn() { 0 },
    fn(types) {
      (
        1,
        types.map(_ => {
          let value = next.val
          next.val += 1
          value
        }),
      )
    },
    fn(_, _) { 0 },
    fn(_) { () },
    fn(_, _, _, types, _, _, _) {
      types.map(_ => {
        let value = next.val
        next.val += 1
        value
      })
    },
    fn(_, _, _) { () },
    fn() { () },
  )
  @lowering.DirectBuilder::new(parameter_types, sink, call_abi?)
}

///|
test "adapter completion keeps the first result contract and invokes its callback once" {
  let builder = test_builder([])
  let completed = Ref(0)
  let context = @adapter.InstructionContext::new(
    builder,
    [],
    [],
    [I32],
    [],
    [],
    None,
    [],
    fn(_) { completed.val += 1 },
  )
  context.finish_operation(I32Const(42U), [])
  assert_true(context.status() is None)
  assert_eq(context.results().length(), 1)
  context.finish_operation(I32Const(43U), [])
  assert_eq(
    context.status(),
    Some("dialect instruction completed more than once"),
  )
  assert_eq(completed.val, 1)
  builder.return_([])
  builder.finish()
}

///|
test "adapter calls preserve deferred hidden-safepoint ABI errors at builder finish" {
  let symbol = @native.ExternalSymbol::new("runtime.allocate")
  let builder = test_builder(
    [I32],
    call_abi=@lowering.CallAbiElaboration::new(hidden_safepoints=[
      @lowering.HiddenSafepointAbi::new(symbol, I32ConstantOperand(0)),
    ]),
  )
  let context = @adapter.InstructionContext::new(
    builder,
    [],
    [],
    [],
    [],
    [],
    None,
    [],
    fn(_) { () },
  )
  let call = @native.NativeCall::new(
    External(symbol),
    @native.Signature::new([I32], []),
    Platform,
    @native.CallBehavior::new(ReadWrite, true, false, true, false),
  )
  context.finish_call(call, builder.parameters())
  assert_true(context.status() is None)
  builder.return_([])
  try builder.finish() catch {
    InvalidCallAbi(message~) =>
      assert_true(message.contains("supported compile-time constant"))
  } noraise {
    _ => fail("dynamic hidden root count escaped final ABI validation")
  }
}
