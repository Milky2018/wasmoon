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

///|
test "optimize cse vmctx load_ptr in block" {
  let builder = IRBuilder::new("vmctx_load_ptr_cse")
  let vmctx = builder.add_param(Type::I64)
  builder.add_result(Type::I64)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  let off32 = builder.iconst_i32(32)
  let off0 = builder.iconst_i32(0)
  let p0 = builder.load_ptr(Type::I64, vmctx, off32)
  // Keep an intervening memory read to ensure load-ptr CSE still works when
  // no memory-writing side effect occurs.
  builder.load_ptr(Type::I32, p0, off0) |> ignore
  let p1 = builder.load_ptr(Type::I64, vmctx, off32)
  let sum = builder.iadd(p0, p1)
  builder.return_([sum])
  let func = builder.get_function()
  optimize(func) |> ignore

  let mut load_i64_count = 0
  for inst in func.blocks[0].instructions {
    if inst.opcode is LoadPtr(Type::I64) {
      load_i64_count = load_i64_count + 1
    }
  }
  inspect(load_i64_count, content="1")
}
