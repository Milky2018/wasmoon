///|
fn poll_checked_store(function : @milkir.Function, inst : @milkir.Inst) -> Bool {
  guard inst.opcode is Memory(Store(_) | StoreNarrow(_)) &&
    inst.args.get(0) is Some(base) else {
    return false
  }
  let mut value = base
  for _ in 0..<32 {
    guard function.defining_inst(value) is Some(definition) else {
      return false
    }
    if definition.opcode is Ext(op, _) && decode_projection(op) is Some(_) {
      return true
    }
    if definition.opcode is Scalar(Copy | Convert(Bitcast)) &&
      definition.args is [source] {
      value = source
    } else {
      return false
    }
  }
  false
}

///|
fn poll_invalidates_credit(
  function : @milkir.Function,
  inst : @milkir.Inst,
) -> Bool {
  if poll_checked_store(function, inst) {
    return false
  }
  if inst.opcode is Ext(op, _) && decode_projection(op) is Some(_) {
    return false
  }
  let effects = @effects.analyze(inst.opcode)
  !effects.preserves_physical_addresses() || effects.write is Some(Unknown)
}

///|
/// Independently prove a finite number of charges after a successful guard.
/// Joins use the least remaining credit. Unknown/control mutations revoke it;
/// a cycle without rechecking its guard eventually exhausts the proof.
fn poll_region_error(function : @milkir.Function) -> String? {
  let guards : Map[Int32, PollRegion] = Map([])
  let controls : Map[Int32, Int32] = Map([])
  let guard_values : Map[Int32, (Int32, Int32)] = Map([])
  for block in function.blocks {
    let mut pending : Int32? = None
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      if pending is Some(_) &&
        (
          poll_invalidates_credit(function, inst) ||
          (
            inst.opcode is Ext(op, _) &&
            decode_poll_region(op) is Some((_, false))
          )
        ) {
        return Some("native poll guard invalidated before its branch")
      }
      if inst.opcode is Ext(op, _) &&
        decode_poll_region(op) is Some((region, true)) {
        if guards.contains(region.key) ||
          !(inst.results is [condition, token] &&
          condition.ty == I32 &&
          token.ty == Ptr) {
          return Some("duplicate native poll guard")
        }
        guards[region.key] = region
        controls[region.key] = inst.results[1].id
        guard_values[inst.results[0].id] = (region.key, block.id)
        pending = Some(inst.results[0].id)
      }
    }
    if pending is Some(result) {
      let branches_on_guard = match block.terminator {
        Some(
          Branch(condition, _, _, _, _)
          | Brz(condition, _, _)
          | Brnz(condition, _, _)
        ) => condition.id == result
        _ => false
      }
      if !branches_on_guard {
        return Some("native poll guard must branch in its defining block")
      }
    }
  }
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      if inst.opcode is Ext(op, _) &&
        decode_poll_region(op) is Some((region, false)) {
        if guards.get(region.key) != Some(region) ||
          !(inst.args is [token] && controls.get(region.key) == Some(token.id)) {
          return Some("native poll charge has no matching guarded controls")
        }
      }
    }
  }
  if guards.is_empty() {
    return None
  }
  let cfg = @milkir.CFG::build(function)
  let blocks : Map[Int32, @milkir.Block] = Map([])
  for block in function.blocks {
    blocks[block.id] = block
  }
  for key, region in guards {
    let outputs : Map[Int32, Int32] = Map([])
    for block in function.blocks {
      outputs[block.id] = region.limit
    }
    fn incoming(block : @milkir.Block) -> Int32 {
      let predecessors = cfg.get_predecessors(block.id)
      if block.id == function.blocks[0].id || predecessors.is_empty() {
        return -1
      }
      let mut result = region.limit
      for pred in predecessors {
        let credit = match blocks[pred].terminator.unwrap() {
          Branch(condition, yes, _, no, _) if guard_values.get(condition.id) ==
            Some((key, pred)) =>
            if block.id == yes && block.id != no {
              region.limit
            } else {
              -1
            }
          Brnz(condition, yes, no) if guard_values.get(condition.id) ==
            Some((key, pred)) =>
            if block.id == yes && block.id != no {
              region.limit
            } else {
              -1
            }
          Brz(condition, no, yes) if guard_values.get(condition.id) ==
            Some((key, pred)) =>
            if block.id == yes && block.id != no {
              region.limit
            } else {
              -1
            }
          _ => outputs[pred]
        }
        result = result.min(credit)
      }
      result
    }
    fn after(inst : @milkir.Inst, credit : Int32) -> Int32 {
      if inst.opcode is Ext(op, _) &&
        decode_poll_region(op) is Some((charge, guard_)) {
        if guard_ {
          return credit
        }
        if charge == region {
          return (-1).max(credit - 1)
        }
        return -1
      }
      if poll_invalidates_credit(function, inst) {
        -1
      } else {
        credit
      }
    }
    let mut changed = true
    let mut work = 0
    while changed {
      changed = false
      for block in function.blocks {
        let mut credit = incoming(block)
        for id in function.block_instruction_ids(block) {
          work += 1
          if work > 1000000 {
            return Some("native poll budget analysis exhausted")
          }
          credit = after(function.instruction_by_id(id).unwrap(), credit)
        }
        if outputs[block.id] != credit {
          outputs[block.id] = credit
          changed = true
        }
      }
    }
    for block in function.blocks {
      let mut credit = incoming(block)
      for id in function.block_instruction_ids(block) {
        let inst = function.instruction_by_id(id).unwrap()
        if inst.opcode is Ext(op, _) &&
          decode_poll_region(op) is Some((charge, false)) &&
          charge == region &&
          credit < 1 {
          return Some("native poll charge exceeds its guarded budget")
        }
        credit = after(inst, credit)
      }
    }
  }
  None
}
