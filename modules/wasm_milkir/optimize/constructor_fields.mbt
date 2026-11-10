///|
/// Carry immutable constructor fields through a call-free loop. The original
/// ordered checked header prefix seeds the state once, and exact constructor
/// arguments supply every changed backedge. Reentry, suspension and heap
/// replacement exclude the entire loop, even when a checked anchor remains.
fn forward_constructor_fields(
  function : @milkir.Function,
  context : @wasm_milkir.WasmValidationContext,
) -> Bool {
  if function.blocks.length() > 256 {
    return false
  }
  let cfg = @milkir.CFG::build(function)
  let blocks : Map[Int32, @milkir.Block] = Map([])
  for block in function.blocks {
    blocks[block.id] = block
  }
  let mut changed = false
  for loop_ in cfg.find_loops() {
    guard loop_.blocks.length() <= 64 &&
      cfg.get_loop_preheader(loop_) is Some(preheader_id) else {
      continue
    }
    let header = blocks[loop_.header]
    let preheader = blocks[preheader_id]
    guard preheader.terminator is Some(Jump(target, entry_args)) &&
      target == header.id else {
      continue
    }
    let reads : Array[@milkir.Inst] = []
    for id in function.block_instruction_ids(header) {
      let inst = function.instruction_by_id(id).unwrap()
      if @wasm_milkir.decode_opcode(inst.opcode) is Some(StructGet(t, _)) {
        if reads.get(0) is Some(first) &&
          @wasm_milkir.decode_opcode(first.opcode)
          is Some(StructGet(first_type, _)) &&
          (inst.args != first.args || t != first_type) {
          break
        }
        reads.push(inst)
        if reads.length() == 4 {
          break
        }
      } else {
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
    }
    guard reads.get(0) is Some(anchor) &&
      @wasm_milkir.decode_opcode(anchor.opcode)
      is Some(StructGet(type_index, anchor_field)) &&
      anchor.args is [receiver] else {
      continue
    }
    let mut parameter = -1
    for index, (value, _) in header.params {
      if value == receiver {
        parameter = index
      }
    }
    if parameter < 0 {
      continue
    }
    let incoming : Array[(@milkir.Block, @milkir.Inst?)] = []
    let mut admitted = true
    let mut has_constructor = false
    for (latch, _) in loop_.back_edges {
      let block = blocks[latch]
      guard block.terminator is Some(Jump(target, args)) && target == header.id else {
        admitted = false
        break
      }
      if args[parameter] == receiver {
        incoming.push((block, None))
      } else if function.defining_inst(args[parameter]) is Some(allocation) &&
        @wasm_milkir.decode_opcode(allocation.opcode) is Some(StructNew(t)) &&
        t == type_index {
        incoming.push((block, Some(allocation)))
        has_constructor = true
      } else {
        admitted = false
        break
      }
    }
    if !admitted || !has_constructor {
      continue
    }
    if loop_.blocks.any(block => {
        function
        .block_instruction_ids(blocks[block])
        .any(id => {
          !@effects.analyze(function.instruction_by_id(id).unwrap().opcode).preserves_checked_references()
        })
      }) {
      continue
    }
    // A successful checked header read establishes the complete earlier
    // field prefix. Immutable fields in that prefix cannot add a new trap,
    // even when their first use is conditional on entering the loop body.
    let fields : Map[Int32, Bool] = Map([])
    for read in reads {
      if @wasm_milkir.decode_opcode(read.opcode) is Some(StructGet(_, field)) {
        fields[field] = true
      }
    }
    for block_id in loop_.blocks {
      for id in function.block_instruction_ids(blocks[block_id]) {
        let inst = function.instruction_by_id(id).unwrap()
        if inst.args == [receiver] &&
          @wasm_milkir.decode_opcode(inst.opcode) is Some(StructGet(t, field)) &&
          t == type_index &&
          field <= anchor_field &&
          !fields.contains(field) {
          reads.push(inst)
          fields[field] = true
        }
      }
    }
    let anchor_opcode = anchor.opcode
    let mut seeded_anchor : @milkir.Value? = None
    for read in reads {
      guard @wasm_milkir.decode_opcode(read.opcode) is Some(StructGet(t, field)) &&
        t == type_index &&
        field <= anchor_field &&
        read.args == [receiver] &&
        context.struct_field(type_index, field) is Some(contract) &&
        !contract.mutable_ &&
        contract.storage is Value(I32 | I64 | F32 | F64 | Ref) else {
        continue
      }
      if incoming.any(entry => {
          entry.1 is Some(allocation) &&
          (
            field >= allocation.args.length() ||
            allocation.args[field].ty != read.results[0].ty
          )
        }) {
        continue
      }
      if seeded_anchor is None {
        let checked = function.new_value(anchor.results[0].ty)
        let seed = function.new_inst(anchor_opcode, [entry_args[parameter]], [
          checked,
        ])
        for metadata in anchor.metadata {
          seed.add_metadata(metadata)
        }
        preheader.append_inst(seed)
        seeded_anchor = Some(checked)
      }
      let initial = if read.id == anchor.id {
        seeded_anchor.unwrap()
      } else {
        let initial = function.new_value(read.results[0].ty)
        let seed = function.new_inst(read.opcode, [entry_args[parameter]], [
          initial,
        ])
        for metadata in read.metadata {
          seed.add_metadata(metadata)
        }
        preheader.append_inst(seed)
        initial
      }
      let carried = function.append_block_param(header, initial.ty)
      append_loop_field_argument(preheader, header.id, initial)
      for (block, allocation) in incoming {
        append_loop_field_argument(
          block,
          header.id,
          match allocation {
            Some(allocation) => allocation.args[field]
            None => carried
          },
        )
      }
      for block_id in loop_.blocks {
        for id in function.block_instruction_ids(blocks[block_id]) {
          let inst = function.instruction_by_id(id).unwrap()
          if inst.args == [receiver] &&
            @wasm_milkir.decode_opcode(inst.opcode) is Some(StructGet(t, f)) &&
            t == type_index &&
            f == field {
            inst.set_opcode(Scalar(Copy))
            inst.operands.clear()
            inst.operands.push(carried)
          }
        }
      }
      changed = true
    }
  }
  changed
}
