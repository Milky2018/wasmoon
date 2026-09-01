///|
test "x64 frame reserves the SysV setup area for calls" {
  let builder = @semantic.FunctionBuilder::new("framed_call", Platform, [I64], [
    I64,
  ])
  let parameters = builder.parameters()
  let call = @semantic.SemanticCall::new(
    External(@native.ExternalSymbol::new("runtime.helper")),
    @native.Signature::new([I64], [I64]),
    Platform,
    @native.CallBehavior::new(ReadWrite, true, true, false, false),
  )
  let result = builder.emit(Call(call), parameters, [I64])[0]
  builder.return_([result])
  let selected = lower(builder.finish_selection_plan(), test_lowering_context())
  let allocation = allocate(selected)
  inspect(
    plan_frame(selected, allocation).summary(),
    content=(
      #|x64 frame size=8 align=16
      #|
    ),
  )
}
