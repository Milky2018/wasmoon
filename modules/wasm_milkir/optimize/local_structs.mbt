///|
priv struct LocalStruct {
  object : @milkir.Value
  type_index : Int32
  initial : @milkir.Value
}

///|
fn terminator_values(term : @milkir.Terminator) -> Array[@milkir.Value] {
  match term {
    Jump(_, args) | Return(args) => args
    Branch(condition, _, left, _, right) => [condition] + left + right
    Brz(condition, _, _) | Brnz(condition, _, _) => [condition]
    BrTable(index, _, _) => [index]
    Trap(_) | TrapExit(_) => []
  }
}

///|
/// Scalarize private integer boxes, keeping their effectful allocation.
/// Only entry allocations with direct field-zero uses are admitted. Passing
/// the reference through a call, copy, phi, return or any other operation
/// rejects the candidate; no alias or interprocedural assumptions are needed.
fn promote_local_structs(function : @milkir.Function) -> Bool {
  guard function.blocks.get(0) is Some(entry) else { return false }
  let cfg = @milkir.CFG::build(function)
  if !cfg.get_predecessors(entry.id).is_empty() ||
    cfg.reverse_postorder().length() != function.blocks.length() {
    return false
  }
  // Do not amplify arbitrary CFGs with an unbounded number of SSA parameters.
  // BrTable has no edge arguments; leave those functions to a future pass.
  for block in function.blocks {
    if block.terminator is Some(BrTable(_, _, _)) {
      return false
    }
  }
  let candidates : Array[LocalStruct] = []
  for id in function.block_instruction_ids(entry) {
    let inst = function.instruction_by_id(id).unwrap()
    if @wasm_milkir.decode_opcode(inst.opcode) is Some(StructNew(type_index)) &&
      inst.args is [initial] &&
      initial.ty is (I32 | I64) &&
      inst.results is [object] {
      candidates.push({ object, type_index, initial, })
      if candidates.length() == 16 {
        break
      }
    }
  }
  if candidates.is_empty() ||
    function.blocks.length() > 4096 / candidates.length() {
    return false
  }
  let indexes : Map[Int32, Int32] = Map([])
  for index, candidate in candidates {
    indexes[candidate.object.id] = index
  }
  let eligible = Array::make(candidates.length(), true)
  let reads = Array::make(candidates.length(), false)
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      for operand_index, operand in inst.args {
        if indexes.get(operand.id) is Some(index) {
          let candidate = candidates[index]
          if operand_index != 0 {
            eligible[index] = false
            continue
          }
          match @wasm_milkir.decode_opcode(inst.opcode) {
            Some(StructGet(type_index, 0)) =>
              if type_index == candidate.type_index &&
                inst.results is [result] &&
                result.ty == candidate.initial.ty {
                reads[index] = true
              } else {
                eligible[index] = false
              }
            Some(StructSet(type_index, 0)) =>
              if type_index != candidate.type_index {
                eligible[index] = false
              }
            _ => eligible[index] = false
          }
        }
      }
    }
    if block.terminator is Some(term) {
      for value in terminator_values(term) {
        if indexes.get(value.id) is Some(index) {
          eligible[index] = false
        }
      }
    }
  }
  let locals : Array[LocalStruct] = []
  indexes.clear()
  for index, candidate in candidates {
    if eligible[index] && reads[index] {
      indexes[candidate.object.id] = locals.length()
      locals.push(candidate)
    }
  }
  if locals.is_empty() {
    return false
  }
  let parameters : Map[Int32, Array[@milkir.Value]] = Map([])
  for block in function.blocks {
    if block.id != entry.id {
      parameters[block.id] = locals.map(candidate => {
        function.append_block_param(block, candidate.initial.ty)
      })
    }
  }
  for block in function.blocks {
    let current = if block.id == entry.id {
      locals.map(candidate => candidate.initial)
    } else {
      parameters[block.id].copy()
    }
    let removed : Map[Int32, Bool] = Map([])
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      if inst.args.get(0) is Some(object) &&
        indexes.get(object.id) is Some(index) {
        match @wasm_milkir.decode_opcode(inst.opcode) {
          Some(StructGet(_, 0)) => {
            inst.args.clear()
            inst.args.push(current[index])
            inst.set_opcode(Scalar(Copy))
          }
          Some(StructSet(_, 0)) => {
            current[index] = inst.args[1]
            removed[id] = true
          }
          _ => ()
        }
      }
    }
    block.retain_instruction_ids(id => !removed.contains(id))
    if block.terminator is Some(term) {
      let rewritten : @milkir.Terminator = match term {
        Jump(target, args) => Jump(target, args + current)
        Branch(condition, left, left_args, right, right_args) =>
          Branch(
            condition,
            left,
            left_args + current,
            right,
            right_args + current,
          )
        Brz(condition, left, right) =>
          Branch(condition, right, current.copy(), left, current.copy())
        Brnz(condition, left, right) =>
          Branch(condition, left, current.copy(), right, current.copy())
        _ => term
      }
      block.set_terminator(rewritten)
    }
  }
  true
}
