///|
test "egraph does not mark unchanged iconst as changed" {
  let builder = IRBuilder::new("iconst_stable")
  builder.add_result(Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let c = builder.iconst_i32(7)
  builder.return_([c])
  let func = builder.get_function()
  let stats = optimize_function_with_stats(func)
  inspect(stats.changed, content="false")
}

///|
test "optimize o1 converges on second run" {
  let builder = IRBuilder::new("o1_converges")
  builder.add_result(Type::I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let c1 = builder.iconst_i32(40)
  let c2 = builder.iconst_i32(2)
  let sum = builder.iadd(c1, c2)
  builder.return_([sum])
  let func = builder.get_function()
  let first = optimize_with_level(func, OptLevel::O1)
  let second = optimize_with_level(func, OptLevel::O1)
  inspect(first.changed, content="true")
  inspect(second.changed, content="false")
}
