///|
fn build_public_diamond() -> @milkir.Function raise @milkir.VerifyError {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("diamond")
  let condition = builder.add_param(I32)
  let left = builder.create_block()
  let right = builder.create_block()
  let exit = builder.create_block()
  builder.brnz(condition, left, right)
  builder.switch_to_block(left)
  builder.jump(exit, [])
  builder.switch_to_block(right)
  builder.jump(exit, [])
  builder.switch_to_block(exit)
  builder.return_([])
  builder.finalize()
}

///|
test "public CFG reports diamond edges" {
  let cfg = @milkir.CFG::build(build_public_diamond())
  inspect(cfg.num_blocks, content="4")
  debug_inspect(cfg.get_successors(0), content="[1, 2]")
  debug_inspect(cfg.get_predecessors(3), content="[1, 2]")
  inspect(cfg.is_exit_block(3), content="true")
  inspect(cfg.is_valid(3), content="true")
}

///|
test "public CFG reports dominance and complete traversals" {
  let cfg = @milkir.CFG::build(build_public_diamond())
  inspect(cfg.dominates(0, 3), content="true")
  inspect(cfg.dominates(1, 3), content="false")
  inspect(cfg.dominates(2, 3), content="false")
  inspect(cfg.postorder().length(), content="4")
  inspect(cfg.reverse_postorder().length(), content="4")
}

///|
test "public CFG renders graphviz edges" {
  let dot = @milkir.CFG::build(build_public_diamond()).to_dot("diamond")
  inspect(dot.contains("digraph diamond"), content="true")
  inspect(dot.contains("block0 -> block1"), content="true")
  inspect(dot.contains("block0 -> block2"), content="true")
  inspect(dot.contains("block1 -> block3"), content="true")
}

///|
test "public CFG discovers a natural loop and its preheader" {
  let builder = @milkir.FunctionBuilder::FunctionBuilder("loop")
  let condition = builder.add_param(I32)
  let header = builder.create_block()
  let body = builder.create_block()
  let exit = builder.create_block()
  builder.jump(header, [])
  builder.switch_to_block(header)
  builder.brnz(condition, body, exit)
  builder.switch_to_block(body)
  builder.jump(header, [])
  builder.switch_to_block(exit)
  builder.return_([])
  let cfg = @milkir.CFG::build(builder.finalize())
  debug_inspect(cfg.find_back_edges(), content="[(2, 1)]")
  let loops = cfg.find_loops()
  inspect(loops.length(), content="1")
  inspect(loops[0].header, content="1")
  inspect(loops[0].contains(1), content="true")
  inspect(loops[0].contains(2), content="true")
  debug_inspect(cfg.get_loop_preheader(loops[0]), content="Some(0)")
}
