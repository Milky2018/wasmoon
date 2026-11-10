///|
fn loop_materialization_opcode(opcode : @milkir.Opcode) -> Bool {
  match opcode {
    Scalar(IntConst(_) | Convert(SignedExtend | UnsignedExtend | IntReduce)) =>
      true
    Scalar(
      IntBinary(
        Add
        | Sub
        | Mul
        | And
        | Or
        | Xor
        | ShiftLeft
        | SignedShiftRight
        | UnsignedShiftRight
        | RotateLeft
        | RotateRight
      )
    ) => true
    _ => false
  }
}

///|
/// Localize bounded total integer expressions at call-free memory-loop entry.
/// This is the final placement step, after scalar commoning has finished.
pub fn localize_loop_materializations(function : @milkir.Function) -> OptResult {
  let result = OptResult::OptResult()
  if function.blocks.length() > 256 {
    return result
  }
  let cfg = @milkir.CFG::build(function)
  let dominance = cfg.compute_dominance()
  let loops = cfg.find_loops()
  let definitions = loop_definition_blocks(function)
  for loop_ in loops {
    if loops.any(inner => {
        inner.header != loop_.header && loop_.contains(inner.header)
      }) {
      continue
    }
    let body = function.blocks.filter(block => loop_.contains(block.id))
    let mut loads = false
    let mut has_boundary = false
    for block in body {
      for id in function.block_instruction_ids(block) {
        match function.instruction_by_id(id).unwrap().opcode {
          Memory(Load(_) | LoadNarrow(_, _, _)) => loads = true
          Call(_) | Ext(_, _) => has_boundary = true
          _ => ()
        }
      }
    }
    guard loads && !has_boundary else { continue }
    let entries = cfg
      .get_predecessors(loop_.header)
      .filter(id => !loop_.contains(id))
    guard entries is [entry] &&
      find_unroll_block(function, entry) is Some(preheader) else {
      continue
    }
    // Existing definitions after the final has_boundary operation are already resident.
    // Leaving them alone also makes this placement idempotent.
    let resident : Set[Int32] = Set([])
    for id in function.block_instruction_ids(preheader) {
      let inst = function.instruction_by_id(id).unwrap()
      if inst.opcode is (Call(_) | Ext(_, _)) {
        resident.clear()
      }
      for value in inst.results {
        resident.add(value.id)
      }
    }
    let plan : Array[@milkir.Inst] = []
    let planned : Set[Int32] = Set([])
    fn collect(value : @milkir.Value, depth : Int32) -> Bool {
      let definition = definitions.get(value.id).unwrap_or(-1)
      if loop_.contains(definition) ||
        !dominance.dominates(definition, preheader.id) ||
        resident.contains(value.id) ||
        planned.contains(value.id) ||
        !(value.ty is (I32 | I64)) {
        return true
      }
      guard function.defining_inst(value) is Some(inst) &&
        inst.results.length() == 1 &&
        loop_materialization_opcode(inst.opcode) else {
        return true
      }
      if depth >= 16 || plan.length() >= 16 {
        return false
      }
      for argument in inst.args {
        if !collect(argument, depth + 1) {
          return false
        }
      }
      if plan.length() >= 16 {
        return false
      }
      planned.add(value.id)
      plan.push(inst)
      true
    }
    let mut admitted = true
    for block in body {
      for id in function.block_instruction_ids(block) {
        for value in function.instruction_by_id(id).unwrap().args {
          admitted = admitted && collect(value, 0)
        }
      }
      rewrite_terminator_values(block.terminator.unwrap(), value => {
        admitted = admitted && collect(value, 0)
        value
      })
      |> ignore
    }
    if !admitted || plan.is_empty() {
      continue
    }
    let replacements : Map[Int32, @milkir.Value] = Map([])
    fn replace(value : @milkir.Value) -> @milkir.Value {
      replacements.get(value.id).unwrap_or(value)
    }
    for inst in plan {
      let fresh = function.new_value(inst.results[0].ty)
      let copy = function.new_inst(inst.opcode, inst.args.map(replace), [fresh])
      for metadata in inst.metadata {
        copy.add_metadata(metadata)
      }
      preheader.append_inst(copy)
      replacements[inst.results[0].id] = fresh
    }
    for block in body {
      for id in function.block_instruction_ids(block) {
        let inst = function.instruction_by_id(id).unwrap()
        for index, value in inst.args {
          inst.args[index] = replace(value)
        }
      }
      if rewrite_terminator_values(block.terminator.unwrap(), replace)
        is Some(term) {
        block.set_terminator(term, metadata=block.terminator_metadata())
      }
    }
    result.mark_changed()
  }
  result
}
