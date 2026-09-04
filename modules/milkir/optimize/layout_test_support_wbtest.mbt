///|
fn test_block_instructions(
  func : @milkir.Function,
  block : @milkir.Block,
) -> Array[@milkir.Inst] {
  let instructions : Array[@milkir.Inst] = []
  for inst_id in block.instruction_ids() {
    instructions.push(func.instruction_by_id(inst_id).unwrap())
  }
  instructions
}
