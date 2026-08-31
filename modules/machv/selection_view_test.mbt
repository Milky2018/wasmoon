///|
test "sealed selection view exposes dense borrowed semantic input" {
  let builder = @machv.FunctionBuilder::new_selection_plan(
    "selection_view",
    Internal,
    [I32],
    [I32],
  )
  let parameter = builder.parameters()[0]
  let one = builder.emit(I32Const(1U), [], [I32])[0]
  let sum = builder.emit(IntBinary(Add), [parameter, one], [I32])[0]
  builder.return_([sum])
  let view = builder.finish_selection_plan().view()
  inspect(view.name(), content="selection_view")
  inspect(view.value_count(), content="3")
  inspect(view.block_count(), content="1")
  inspect(view.layout().length(), content="1")
  inspect(view.parameter_types().length(), content="1")
  inspect(view.result_types().length(), content="1")
  let block = view.block(0)
  inspect(block.index(), content="0")
  inspect(block.parameters().length(), content="0")
  inspect(block.instructions().length(), content="2")
  let instruction = view.instruction(block.instructions()[1])
  inspect(instruction.index(), content="1")
  inspect(instruction.operands().length(), content="2")
  inspect(instruction.results().length(), content="1")
  inspect(view.value_index(instruction.results()[0]), content="2")
  assert_eq(view.value_type(instruction.results()[0]), I32)
  assert_true(instruction.operation() is IntBinary(Add))
  assert_true(block.terminator().kind() is SelectionReturn(_))
}
