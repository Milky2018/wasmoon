///|
/// Plan only on final borrow-verified IR. A checked object's logical layout
/// survives collection, while each physical projection retains its own epoch.
/// Unknown writes, reentry, suspension and heap replacement revoke the fact.
fn checked_struct_projection_sites(
  function : @milkir.Function,
) -> Map[Int32, Bool] {
  let selected : Map[Int32, Bool] = Map([])
  if function.blocks.is_empty() || function.blocks.length() > 256 {
    return selected
  }
  let keys : Map[(Int32, Int32), Int32] = Map([])
  let queries : Map[Int32, Int32] = Map([])
  let definitions : Map[Int32, UInt64] = Map([])
  let borrowed : Set[Int32] = Set([])
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      if inst.opcode is Ext(extension, _) &&
        decode_projection(extension) is Some(projection) {
        if inst.results is [result] && result.ty == Ptr {
          borrowed.add(result.id)
        }
        if projection is StructData(type_) && inst.args is [object] {
          let key = (object.id, type_)
          if !keys.contains(key) && keys.length() < 64 {
            let bit = keys.length()
            keys[key] = bit
            definitions[object.id] = definitions.get(object.id).unwrap_or(0UL) |
              (1UL << bit)
          }
          if keys.get(key) is Some(bit) {
            queries[id] = bit
          }
        }
      }
    }
  }
  if queries.length() <= keys.length() {
    return selected
  }
  let mut work = 0
  let mut changed = true
  while changed {
    changed = false
    for block in function.blocks {
      for id in function.block_instruction_ids(block) {
        work += 1
        if work > 262144 {
          return selected
        }
        let inst = function.instruction_by_id(id).unwrap()
        if inst.opcode is Scalar(Copy | Convert(Bitcast)) &&
          inst.args is [source] &&
          inst.results is [result] &&
          borrowed.contains(source.id) &&
          !borrowed.contains(result.id) {
          borrowed.add(result.id)
          changed = true
        }
      }
    }
  }
  fn preserves(inst : @milkir.Inst) -> Bool {
    if inst.opcode is Ext(extension, _) &&
      (
        decode_projection(extension) is Some(_) ||
        decode_allocation_admission(extension) is Some(_) ||
        decode_cached_poll(extension) is Some(Publish(_))
      ) {
      return true
    }
    if inst.opcode is Memory(Store(_) | StoreNarrow(_)) {
      return inst.args
        .get(0)
        .map(base => borrowed.contains(base.id))
        .unwrap_or(false)
    }
    @effects.analyze(inst.opcode).preserves_struct_values()
  }
  fn before_instruction(state : UInt64, inst : @milkir.Inst) -> UInt64 {
    if !preserves(inst) {
      return 0UL
    }
    let mut state = state
    for result in inst.results {
      if definitions.get(result.id) is Some(mask) {
        state = state & (0xFFFFFFFFFFFFFFFFUL ^ mask)
      }
    }
    state
  }
  let cfg = @milkir.CFG::build(function)
  let entry = function.blocks[0].id
  if cfg.reverse_postorder().length() != function.blocks.length() ||
    !cfg.get_predecessors(entry).is_empty() {
    return selected
  }
  let all = if keys.length() == 64 {
    0xFFFFFFFFFFFFFFFFUL
  } else {
    (1UL << keys.length()) - 1UL
  }
  let outputs = Array::make(cfg.size, all)
  fn incoming(block : @milkir.Block) -> UInt64 {
    let id = block.id
    let predecessors = cfg.get_predecessors(id)
    if id == entry || predecessors.is_empty() {
      return 0UL
    }
    let mut state = outputs[predecessors[0]]
    for predecessor in predecessors[1:] {
      state = state & outputs[predecessor]
    }
    for (parameter, _) in block.params {
      if definitions.get(parameter.id) is Some(mask) {
        state = state & (0xFFFFFFFFFFFFFFFFUL ^ mask)
      }
    }
    state
  }
  let mut converged = false
  for _ in 0..<(function.blocks.length() + 1) {
    let mut changed = false
    for block in function.blocks {
      let mut state = incoming(block)
      for id in function.block_instruction_ids(block) {
        work += 1
        if work > 262144 {
          return selected
        }
        state = before_instruction(
          state,
          function.instruction_by_id(id).unwrap(),
        )
        if queries.get(id) is Some(bit) {
          state = state | (1UL << bit)
        }
      }
      if outputs[block.id] != state {
        outputs[block.id] = state
        changed = true
      }
    }
    if !changed {
      converged = true
      break
    }
  }
  if !converged {
    return selected
  }
  for block in function.blocks {
    let mut state = incoming(block)
    for id in function.block_instruction_ids(block) {
      state = before_instruction(state, function.instruction_by_id(id).unwrap())
      if queries.get(id) is Some(bit) {
        if (state & (1UL << bit)) != 0UL {
          selected[id] = true
        }
        state = state | (1UL << bit)
      }
    }
  }
  selected
}
