///|
/// Expand only bounded loop sites. Leaf getters and large CFGs retain the
/// shared cache accessor, avoiding speculative cold code and lowering growth.
fn loop_projection_sites(function : @milkir.Function) -> Map[Int32, Bool] {
  let sites : Map[Int32, Bool] = Map([])
  if function.blocks.length() <= 1 || function.blocks.length() > 64 {
    return sites
  }
  let candidates : Array[(Int32, Int32)] = []
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      if function.instruction_by_id(id).unwrap().opcode is Ext(op, _) &&
        decode_projection(op) is Some(StructData(_) | ArrayData(0)) {
        candidates.push((block.id, id))
      }
    }
  }
  if candidates.is_empty() {
    return sites
  }
  let loops = @milkir.CFG::build(function).find_loops()
  for (block, id) in candidates {
    if loops.any(loop_ => loop_.contains(block)) {
      sites[id] = true
    }
  }
  sites
}
