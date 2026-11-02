///|
/// Expand bounded loops and successful budget-guard regions. Other getters
/// and large CFGs retain shared accessors, bounding speculative code growth.
fn inline_projection_sites(function : @milkir.Function) -> Map[Int32, Bool] {
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
  let cfg = @milkir.CFG::build(function)
  let loops = cfg.find_loops()
  let fast_regions : Array[Int32] = []
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      if inst.opcode is Ext(op, _) && decode_poll_region(op) is Some((_, true)) {
        let guard_value = inst.results[0]
        match block.terminator {
          Some(Branch(condition, yes, _, _, _) | Brnz(condition, yes, _)) if condition.id ==
            guard_value.id => fast_regions.push(yes)
          Some(Brz(condition, _, yes)) if condition.id == guard_value.id =>
            fast_regions.push(yes)
          _ => ()
        }
      }
    }
  }
  let dominance = cfg.compute_dominance()
  for (block, id) in candidates {
    if loops.any(loop_ => loop_.contains(block)) ||
      fast_regions.any(entry => dominance.dominates(entry, block)) {
      sites[id] = true
    }
  }
  sites
}
