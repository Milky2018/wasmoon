///|
/// These operations cannot reenter the embedding, collect, replace the heap,
/// or mutate struct fields except through the explicit StructSet case.
fn gc_loop_local(inst : @milkir.Inst) -> Bool {
  match @wasm_milkir.decode_opcode(inst.opcode) {
    Some(
      StructGet(_, _)
      | StructGetS(_, _, _)
      | StructGetU(_, _, _)
      | StructSet(_, _)
      | ArrayLen
      | ArrayGet(_)
      | ArrayGetS(_, _)
      | ArrayGetU(_, _)
      | ArraySet(_)
      | ArrayFill(_)
      | ArrayCopy(_, _)
      | ArrayInitData(_, _)
      | ArrayInitElem(_, _)
      | I31New
      | I31GetS
      | I31GetU
    ) => true
    _ =>
      match inst.opcode {
        Scalar(_) | Vector(_) | GlobalValue(_) => true
        Memory(Load(_) | LoadNarrow(_, _, _)) => true
        _ => false
      }
  }
}

///|
fn checked_gc_object(inst : @milkir.Inst) -> @milkir.Value? {
  match @wasm_milkir.decode_opcode(inst.opcode) {
    Some(
      StructGet(_, _)
      | StructGetS(_, _, _)
      | StructGetU(_, _, _)
      | StructSet(_, _)
      | ArrayLen
      | ArrayGet(_)
      | ArrayGetS(_, _)
      | ArrayGetU(_, _)
      | ArraySet(_)
      | ArrayFill(_)
      | ArrayCopy(_, _)
    ) => inst.args.get(0)
    _ => None
  }
}

///|
/// A prior successful access proves that a loop-invariant reference is not
/// null in the same heap. Forget this proof at reentrancy/allocation barriers.
fn checked_gc_objects(
  function : @milkir.Function,
  cfg : @milkir.CFG,
) -> Map[Int32, Map[Int32, Bool]] {
  let outgoing : Map[Int32, Map[Int32, Bool]] = Map([])
  let blocks : Map[Int32, @milkir.Block] = Map([])
  for block in function.blocks {
    blocks[block.id] = block
  }
  for id in cfg.reverse_postorder() {
    let checked : Map[Int32, Bool] = Map([])
    if cfg.get_predecessors(id) is [previous] &&
      outgoing.get(previous) is Some(inherited) {
      for object, value in inherited {
        checked[object] = value
      }
    }
    for inst_id in function.block_instruction_ids(blocks[id]) {
      let inst = function.instruction_by_id(inst_id).unwrap()
      // A successful allocation cannot turn an existing SSA reference into
      // null. Its failure traps before the loop, and success establishes an
      // active heap. Addresses are not cached by this logical proof.
      let allocation = match @wasm_milkir.decode_opcode(inst.opcode) {
        Some(
          StructNew(_)
          | StructNewDefault(_)
          | ArrayNew(_)
          | ArrayNewDefault(_)
          | ArrayNewFixed(_, _)
          | ArrayNewData(_, _)
          | ArrayNewElem(_, _)
        ) => true
        _ => false
      }
      if !gc_loop_local(inst) && !allocation {
        checked.clear()
      }
      if checked_gc_object(inst) is Some(object) {
        if checked.length() >= 128 {
          checked.clear()
        }
        checked[canonical_value(function, object).id] = true
      }
    }
    outgoing[id] = checked
  }
  outgoing
}

///|
/// Hoist only reads that cannot introduce a new trap, and whose field cannot
/// change in the loop. Alias invalidation uses field index, not declared type
/// or SSA reference identity. No call/allocation/poll is allowed in the loop.
fn hoist_checked_gc_reads(function : @milkir.Function) -> Bool {
  if function.blocks.length() > 4096 {
    return false
  }
  let cfg = @milkir.CFG::build(function)
  let loops = cfg.find_loops()
  if loops.length() > 64 {
    return false
  }
  let checked = checked_gc_objects(function, cfg)
  let definitions : Map[Int32, Int32] = Map([])
  let blocks : Map[Int32, @milkir.Block] = Map([])
  for block in function.blocks {
    blocks[block.id] = block
    for (param, _) in block.params {
      definitions[param.id] = block.id
    }
    for id in function.block_instruction_ids(block) {
      for result in function.instruction_by_id(id).unwrap().results {
        definitions[result.id] = block.id
      }
    }
  }
  let mut changed = false
  let mut work = 0
  for loop_ in loops {
    guard cfg.get_loop_preheader(loop_) is Some(preheader_id) &&
      checked.get(preheader_id) is Some(proofs) else {
      continue
    }
    let writes : Map[Int32, Bool] = Map([])
    let mut safe = true
    for id in loop_.blocks {
      for inst_id in function.block_instruction_ids(blocks[id]) {
        work += 1
        if work > 100000 {
          return changed
        }
        let inst = function.instruction_by_id(inst_id).unwrap()
        if !gc_loop_local(inst) {
          safe = false
          break
        }
        if @wasm_milkir.decode_opcode(inst.opcode) is Some(StructSet(_, field)) {
          writes[field] = true
        }
      }
      if !safe {
        break
      }
    }
    if !safe {
      continue
    }
    let preheader = blocks[preheader_id]
    for id in loop_.blocks {
      let block = blocks[id]
      let removed : Map[Int32, Bool] = Map([])
      for inst_id in function.block_instruction_ids(block) {
        let inst = function.instruction_by_id(inst_id).unwrap()
        let field = match @wasm_milkir.decode_opcode(inst.opcode) {
          Some(
            StructGet(_, field)
            | StructGetS(_, field, _)
            | StructGetU(_, field, _)
          ) => Some(field)
          _ => None
        }
        guard field is Some(field) &&
          !writes.contains(field) &&
          inst.args is [argument] else {
          continue
        }
        let object = canonical_value(function, argument)
        if proofs.contains(object.id) &&
          !(definitions.get(object.id) is Some(defined) &&
          loop_.contains(defined)) {
          inst.args[0] = object
          preheader.append_inst(inst)
          for result in inst.results {
            definitions[result.id] = preheader_id
          }
          removed[inst_id] = true
          changed = true
        }
      }
      block.set_instructions(
        function
        .block_instruction_ids(block)
        .to_owned()
        .filter(id => !removed.contains(id))
        .map(id => function.instruction_by_id(id).unwrap()),
      )
    }
  }
  changed
}
