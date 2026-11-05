///|
/// Index live definitions in layout order. Function parameters have no block
/// definition (-2), and detached or unknown values have no layout entry (-1).
/// LICM updates the index when moving instructions. A graph rewrite discards
/// it before another loop is analyzed.
fn loop_definition_blocks(func : @milkir.Function) -> Array[Int32] {
  let blocks = Array::make(func.next_value_id, -1)
  for param in func.params {
    blocks[param.0.id] = -2
  }
  for block in func.blocks {
    for param in block.params {
      blocks[param.0.id] = block.id
    }
    for id in func.block_instruction_ids(block) {
      let inst = func.instruction_by_id(id).unwrap()
      for value in inst.results {
        blocks[value.id] = block.id
      }
    }
  }
  blocks
}
