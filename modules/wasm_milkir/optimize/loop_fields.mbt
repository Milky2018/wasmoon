///|
fn append_loop_field_argument(
  block : @milkir.Block,
  header : Int32,
  value : @milkir.Value,
) -> Unit {
  let term : @milkir.Terminator = match block.terminator.unwrap() {
    Jump(target, args) => Jump(target, args + [value])
    Branch(condition, yes, yes_args, no, no_args) =>
      Branch(
        condition,
        yes,
        if yes == header {
          yes_args + [value]
        } else {
          yes_args
        },
        no,
        if no == header {
          no_args + [value]
        } else {
          no_args
        },
      )
    Brz(condition, yes, no) =>
      Branch(
        condition,
        no,
        if no == header {
          [value]
        } else {
          []
        },
        yes,
        if yes == header {
          [value]
        } else {
          []
        },
      )
    Brnz(condition, yes, no) =>
      Branch(
        condition,
        yes,
        if yes == header {
          [value]
        } else {
          []
        },
        no,
        if no == header {
          [value]
        } else {
          []
        },
      )
    _ => abort("loop field edge was not admitted")
  }
  block.set_terminator(term, metadata=block.terminator_metadata())
}

///|
/// Carry an always-read scalar field from its dominating backedge store.
/// Stores keep their original positions and traps. Unknown writes, calls,
/// aliased receivers and conditional loop entries prevent the transformation.
fn forward_loop_fields(function : @milkir.Function) -> Bool {
  if function.blocks.length() > 256 {
    return false
  }
  let cfg = @milkir.CFG::build(function)
  let (dominance, loops) = cfg.analyze_loops()
  let blocks : Map[Int32, @milkir.Block] = Map([])
  let definitions : Map[Int32, Int32] = Map([])
  for block in function.blocks {
    blocks[block.id] = block
    for (value, _) in block.params {
      definitions[value.id] = block.id
    }
    for id in function.block_instruction_ids(block) {
      for value in function.instruction_by_id(id).unwrap().results {
        definitions[value.id] = block.id
      }
    }
  }
  let mut changed = false
  for loop_ in loops {
    guard loop_.back_edges is [(latch_id, _)] &&
      cfg.get_loop_preheader(loop_) is Some(preheader_id) else {
      continue
    }
    let header = blocks[loop_.header]
    let preheader = blocks[preheader_id]
    let latch = blocks[latch_id]
    guard preheader.terminator is Some(Jump(target, _)) &&
      target == header.id &&
      latch.terminator
      is Some(Jump(_, _) | Branch(_, _, _, _, _) | Brz(_, _, _) | Brnz(_, _, _)) else {
      continue
    }
    let mut read : @milkir.Inst? = None
    for id in function.block_instruction_ids(header) {
      let inst = function.instruction_by_id(id).unwrap()
      if @wasm_milkir.decode_opcode(inst.opcode) is Some(StructGet(_, _)) &&
        inst.results is [result] &&
        result.ty is (I32 | I64 | F32 | F64) {
        read = Some(inst)
        break
      }
      let effects = @effects.analyze(inst.opcode)
      if effects.may_trap ||
        effects.write is Some(_) ||
        effects.may_collect ||
        effects.may_reenter ||
        effects.may_suspend ||
        effects.may_replace_heap {
        break
      }
    }
    guard read is Some(read) &&
      @wasm_milkir.decode_opcode(read.opcode)
      is Some(StructGet(type_index, field)) &&
      read.args is [receiver] &&
      !loop_.contains(definitions.get(receiver.id).unwrap_or(-1)) else {
      continue
    }
    let mut store : (@milkir.Value, Int32)? = None
    let mut valid = true
    for block_id in loop_.blocks {
      let block = blocks[block_id]
      for id in function.block_instruction_ids(block) {
        let inst = function.instruction_by_id(id).unwrap()
        let effects = @effects.analyze(inst.opcode)
        if effects.may_collect ||
          effects.may_reenter ||
          effects.may_suspend ||
          effects.may_replace_heap {
          valid = false
        }
        match effects.write {
          None | Some(ArrayElements | ArrayLength) => ()
          Some(StructField(_, written_field)) if written_field != field => ()
          Some(StructField(written_type, _)) if written_type == type_index &&
            inst.args is [object, value] &&
            object == receiver &&
            value.ty == read.results[0].ty &&
            store is None => store = Some((value, block_id))
          _ => valid = false
        }
      }
    }
    guard valid &&
      store is Some((stored, store_block)) &&
      dominance.dominates(store_block, latch_id) else {
      continue
    }
    let initial = function.new_value(read.results[0].ty)
    let seed = function.new_inst(read.opcode, read.args.copy(), [initial])
    for metadata in read.metadata {
      seed.add_metadata(metadata)
    }
    preheader.append_inst(seed)
    let carried = function.append_block_param(header, initial.ty)
    read.set_opcode(Scalar(Copy))
    read.operands.clear()
    read.operands.push(carried)
    append_loop_field_argument(preheader, header.id, initial)
    append_loop_field_argument(latch, header.id, stored)
    if store_block == latch_id &&
      cfg
      .get_successors(latch_id)
      .all(next => next == header.id || !loop_.contains(next)) {
      for block_id in loop_.blocks {
        let mut current = carried
        for id in function.block_instruction_ids(blocks[block_id]) {
          let inst = function.instruction_by_id(id).unwrap()
          if @wasm_milkir.decode_opcode(inst.opcode) is Some(StructSet(t, f)) &&
            t == type_index &&
            f == field &&
            inst.args.get(0) == Some(receiver) {
            current = stored
          }
          if @wasm_milkir.decode_opcode(inst.opcode) is Some(StructGet(t, f)) &&
            t == type_index &&
            f == field &&
            inst.args == [receiver] {
            inst.set_opcode(Scalar(Copy))
            inst.operands.clear()
            inst.operands.push(current)
          }
        }
      }
    }
    changed = true
  }
  changed
}
