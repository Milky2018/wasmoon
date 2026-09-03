///|
fn is_cheap_rematerializable_constant(inst : Inst) -> Bool {
  guard inst.operands.is_empty() && inst.results is [result] else {
    return false
  }
  guard inst.opcode is Scalar(IntConst(raw)) else { return false }
  let (bits, lane_count) = match result.ty {
    I32 => (raw.reinterpret_as_uint64() & 0xFFFFFFFFUL, 2)
    I64 => (raw.reinterpret_as_uint64(), 4)
    _ => return false
  }
  let mut nonzero_lanes = 0
  for lane in 0..<lane_count {
    if ((bits >> (lane * 16)) & 0xFFFFUL) != 0UL {
      nonzero_lanes += 1
    }
  }
  nonzero_lanes <= 1
}

///|
fn is_cheap_rematerializable_value(func : Function, value : Value) -> Bool {
  guard func.defining_inst(value) is Some(inst) else { return false }
  if is_cheap_rematerializable_constant(inst) {
    return true
  }
  match (inst.opcode, inst.operands) {
    (Scalar(Convert(UnsignedExtend)), [source]) =>
      match func.defining_inst(source) {
        Some(source_inst) => is_cheap_rematerializable_constant(source_inst)
        None => false
      }
    _ => false
  }
}

///|
fn sink_single_use_materializations(func : Function) -> OptResult {
  let result = OptResult::OptResult()
  if func.blocks.length() < 2 {
    return result
  }
  let original_value_count = func.next_value_id
  let defining_blocks = Array::make(original_value_count, -1)
  let uses = compute_use_counts(func)
  for block in func.blocks {
    for inst_id in block.instructions {
      let inst = func.instructions[inst_id]
      if inst.results is [value] {
        defining_blocks[value.id] = block.id
      }
    }
  }

  for block in func.blocks {
    let rewritten : Array[Inst] = []
    fn sink(value : Value) -> Value {
      if value.id < 0 ||
        value.id >= original_value_count ||
        uses[value.id] != 1 ||
        defining_blocks[value.id] < 0 ||
        defining_blocks[value.id] == block.id ||
        !is_cheap_rematerializable_value(func, value) {
        return value
      }
      guard func.defining_inst(value) is Some(definition) else { return value }
      let localized = func.new_value(value.ty)
      let clone = func.new_inst(definition.opcode, definition.operands.copy(), [
        localized,
      ])
      for metadata in definition.metadata {
        clone.add_metadata(metadata)
      }
      rewritten.push(clone)
      result.mark_changed()
      localized
    }

    for inst_id in block.instructions {
      let inst = func.instructions[inst_id]
      for index, operand in inst.operands {
        inst.operands[index] = sink(operand)
      }
      rewritten.push(inst)
    }
    if block.terminator is Some(term) {
      block.terminator = Some(
        match term {
          Jump(target, args) => Jump(target, args.map(value => sink(value)))
          Branch(cond, true_target, true_args, false_target, false_args) =>
            Branch(
              sink(cond),
              true_target,
              true_args.map(value => sink(value)),
              false_target,
              false_args.map(value => sink(value)),
            )
          Brz(cond, true_target, false_target) =>
            Brz(sink(cond), true_target, false_target)
          Brnz(cond, true_target, false_target) =>
            Brnz(sink(cond), true_target, false_target)
          BrTable(index, targets, default_target) =>
            BrTable(sink(index), targets, default_target)
          Return(values) => Return(values.map(value => sink(value)))
          Trap(_) | TrapExit(_) => term
        },
      )
    }
    block.replace_instructions(rewritten)
  }
  result
}
