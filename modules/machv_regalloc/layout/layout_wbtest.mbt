///|
test "preserving-edge layout does not thread jump-only edge-copy blocks" {
  let func = @machv.Function::new("edge_copy_layout")
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
