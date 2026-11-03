///|
fn following_reference_read(
  function : @milkir.Function,
  id : Int32,
  view : @milkir.Value,
) -> Bool {
  let inst = function.instruction_by_id(id).unwrap()
  inst.opcode is Ext(field, _) &&
  decode_projection(field) is Some(FieldData(_, _, _, 1, true)) &&
  inst.args is [base] &&
  base.id == view.id
}

///|
priv struct InlineProjectionSites {
  eligible : Map[Int32, Bool]
  reserved_struct : Int32?
}

///|
/// Expand bounded loops, successful budget-guard regions and small acyclic
/// accessors. Larger CFGs retain shared accessors to bound code growth.
fn inline_projection_sites(
  function : @milkir.Function,
  reserve_struct~ : Bool = false,
) -> InlineProjectionSites {
  let sites : Map[Int32, Bool] = Map([])
  let empty = { eligible: sites, reserved_struct: None, }
  if function.blocks.length() > 64 {
    return empty
  }
  let candidates : Array[(Int32, Int32, Bool)] = []
  for block in function.blocks {
    let ids = function.block_instruction_ids(block)
    for i in 0..<ids.length() {
      let id = ids[i]
      let inst = function.instruction_by_id(id).unwrap()
      if inst.opcode is Ext(op, _) &&
        decode_projection(op) is Some(StructData(_) | ArrayData(0)) {
        let reference_read = reserve_struct &&
          decode_projection(op) is Some(StructData(_)) &&
          i + 1 < ids.length() &&
          inst.results is [view] &&
          following_reference_read(function, ids[i + 1], view)
        candidates.push((block.id, id, reference_read))
      }
    }
  }
  if candidates.is_empty() {
    return empty
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
  let mut reserved_struct = None
  let mut smallest_loop = function.blocks.length() + 1
  for (block, id, reference_read) in candidates {
    let mut in_loop = false
    for loop_ in loops {
      if loop_.contains(block) {
        in_loop = true
        // Traversal order often reaches outer loops first. Reserve one of
        // the existing slots for a reference load in the smallest loop.
        if reference_read && loop_.blocks.length() < smallest_loop {
          reserved_struct = Some(id)
          smallest_loop = loop_.blocks.length()
        }
      }
    }
    if small_accessor ||
      in_loop ||
      fast_regions.any(entry => dominance.dominates(entry, block)) {
      sites[id] = true
    }
  }
  { eligible: sites, reserved_struct, }
}
