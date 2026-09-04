///|
test "DCE removes a dead chain across forward-ordered blocks" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("dce_block_chain")
  let mut value = builder.iconst_i32(0)
  for _ in 0..<512 {
    let next = builder.create_block()
    builder.jump(next, [])
    builder.switch_to_block(next)
    value = builder.copy(value)
  }
  builder.return_([])
  let func = builder.get_function()
  func.verify()
  inspect(eliminate_dead_code(func).changed, content="true")
  inspect(instruction_count(func), content="0")
  func.verify()
}
