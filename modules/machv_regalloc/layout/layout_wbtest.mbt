///|
test "preserving-edge layout does not thread jump-only edge-copy blocks" {
  let func = @machv.Function::Function("edge_copy_layout")
  let entry = func.new_block()
  let copy_block = func.new_block()
  let merge = func.new_block()
  let exit = func.new_block()
  let cond : @abi.Reg = Physical({ index: 0, class: Int })
  let arg = func.new_vreg(Int)
  let param = func.new_vreg(Int)
  merge.params.push(param)
  entry.set_terminator(BranchZero(cond, true, false, exit.id, copy_block.id))
  copy_block.set_terminator(Jump(merge.id, [Virtual(arg)]))
  merge.set_terminator(Return([]))
  exit.set_terminator(Return([]))
  let optimized = optimize_layout_preserving_edges(func)
  let entry_after = optimized.blocks[0]
  guard entry_after.terminator is Some(BranchZero(_, _, _, _, false_target)) else {
    inspect(false, content="true")
    return
  }
  inspect(false_target, content=copy_block.id.to_string())
}

///|
test "natural loops preserve header and body discovery order" {
  let func = @machv.Function::Function("two_loops")
  let entry = func.new_block()
  let first_header = func.new_block()
  let first_body = func.new_block()
  let between = func.new_block()
  let second_header = func.new_block()
  let second_body = func.new_block()
  let exit = func.new_block()
  let cond : @abi.Reg = Physical({ index: 0, class: Int })
  entry.set_terminator(Jump(first_header.id, []))
  first_header.set_terminator(
    BranchZero(cond, true, false, between.id, first_body.id),
  )
  first_body.set_terminator(Jump(first_header.id, []))
  between.set_terminator(Jump(second_header.id, []))
  second_header.set_terminator(
    BranchZero(cond, true, false, exit.id, second_body.id),
  )
  second_body.set_terminator(Jump(second_header.id, []))
  exit.set_terminator(Return([]))
  let loops = MachVCFG::build(func).find_loops()
  let summary = loops.map(fn(loop_) { (loop_.header, loop_.body, loop_.latch) })
  debug_inspect(summary, content="[(1, [1, 2], 2), (4, [4, 5], 5)]")
}
