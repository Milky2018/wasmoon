///|
/// Expand bounded loops, successful budget-guard regions and small acyclic
/// accessors. Larger CFGs retain shared accessors to bound code growth.
fn inline_projection_sites(function : @milkir.Function) -> Map[Int32, Bool] {
  let sites : Map[Int32, Bool] = Map([])
  if function.blocks.length() > 64 {
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
  // Small acyclic accessors can be called repeatedly by an outer loop. Bound
  // their expansion independently of local loop detection and allocator work.
  let small_accessor = function.blocks.length() <= 12 &&
    candidates.length() <= 3 &&
    loops.is_empty() &&
    function.blocks.fold(init=0, fn(total, block) {
      total + block.instruction_count()
    }) <=
    64
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
    if small_accessor ||
      loops.any(loop_ => loop_.contains(block)) ||
      fast_regions.any(entry => dominance.dominates(entry, block)) {
      sites[id] = true
    }
  }
  sites
}
