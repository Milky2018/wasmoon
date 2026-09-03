///|
fn test_block_instructions(func : Function, block : Block) -> Array[Inst] {
  func.block_instruction_snapshot(block)
}

///|
test "block layout keeps stable instruction arena IDs after deletion" {
  let builder = FunctionBuilder::FunctionBuilder("stable_layout_ids")
  builder.add_result(I32)
  builder.iconst_i32(1) |> ignore
  let live = builder.iconst_i32(2)
  builder.return_([live])
  let func = builder.get_function()
  let block = func.blocks[0]
  debug_inspect(block.instructions, content="[0, 1]")
  eliminate_dead_code(func) |> ignore
  debug_inspect(block.instructions, content="[1]")
  inspect(func.owner.val.instruction_is_deleted(0), content="true")
  inspect(func.owner.val.instruction_is_deleted(1), content="false")
  inspect(func.instruction_by_id(0).unwrap().id, content="0")
  inspect(func.block_instruction_at(block, 0).unwrap().id, content="1")
  inspect(func.verify(), content="()")
}
