///|
fn same_borrows(a : Array[UInt64], b : Array[UInt64]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for index in 0..<a.length() {
    if a[index] != b[index] {
      return false
    }
  }
  true
}

///|
fn borrow_present(words : Array[UInt64], bit : Int32) -> Bool {
  (words[bit / 64] & (1UL << (bit % 64))) != 0UL
}

///|
fn invalidates_borrows(
  inst : @milkir.Inst,
  aliases : Map[Int32, Int32],
) -> Bool {
  if inst.opcode is Ext(extension, _) && decode_projection(extension) is Some(_) {
    return false
  }
  if inst.opcode is Memory(Store(_) | StoreNarrow(_)) &&
    inst.args.get(0) is Some(base) &&
    aliases.contains(base.id) {
    return false
  }
  !@effects.analyze(inst.opcode).preserves_physical_addresses()
}

///|
/// Must-analysis independent of placement/hoisting. It checks every CFG route,
/// including backedges and side entries, rather than trusting planner labels.
/// A missing or incomplete proof fails closed before selection.
fn gc_borrow_error(function : @milkir.Function) -> String? {
  let origins : Map[Int32, Int32] = Map([])
  let shapes : Map[Int32, Projection] = Map([])
  let aliases : Map[Int32, Int32] = Map([])
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      if inst.opcode is Ext(extension, _) &&
        decode_projection(extension)
        is Some(
          ArrayData(_)
          | ArrayElements(_)
          | StructData(_)
          | FieldData(_, _, _, _, _)
        ) &&
        inst.results is [value] {
        origins[value.id] = origins.length()
        aliases[value.id] = value.id
        if inst.opcode is Ext(extension, _) {
          shapes[value.id] = decode_projection(extension).unwrap()
        }
      }
    }
  }
  let mut changed = true
  while changed {
    changed = false
    for block in function.blocks {
      for id in function.block_instruction_ids(block) {
        let inst = function.instruction_by_id(id).unwrap()
        if inst.opcode is Scalar(Copy | Convert(Bitcast)) &&
          inst.args is [source] &&
          inst.results is [value] &&
          aliases.get(source.id) is Some(origin) &&
          !aliases.contains(value.id) {
          aliases[value.id] = origin
          changed = true
        }
      }
    }
  }
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      if inst.opcode is Ext(extension, _) &&
        decode_projection(extension) is Some(projection) {
        if projection is FieldData(type_, _, _, _, _) {
          guard inst.args is [argument] &&
            aliases.get(argument.id) is Some(origin) &&
            shapes.get(origin) is Some(StructData(source_type)) &&
            source_type == type_ else {
            return Some(
              "instruction \{id}: projection lacks a checked object source",
            )
          }
        } else if projection is ArrayElements(_) {
          guard inst.args is [argument] &&
            aliases.get(argument.id) is Some(origin) &&
            shapes.get(origin) is Some(ArrayData(_)) else {
            return Some("instruction \{id}: element view lacks array metadata")
          }
        } else if projection is ArrayLength {
          guard inst.args is [argument] &&
            aliases.get(argument.id) is Some(origin) &&
            shapes.get(origin) is Some(ArrayData(_) | ArrayElements(_)) else {
            return Some(
              "instruction \{id}: projection lacks a checked object source",
            )
          }
        }
      }
    }
  }
  if origins.is_empty() {
    return None
  }
  let cfg = @milkir.CFG::build(function)
  // Number only actual projections; sparse SSA IDs do not enlarge the lattice.
  let all = Array::make((origins.length() + 63) / 64, 0xFFFFFFFFFFFFFFFFUL)
  if origins.length() % 64 != 0 {
    all[all.length() - 1] = (1UL << (origins.length() % 64)) - 1UL
  }
  let outputs : Map[Int32, Array[UInt64]] = Map([])
  let blocks : Map[Int32, @milkir.Block] = Map([])
  for block in function.blocks {
    blocks[block.id] = block
    outputs[block.id] = if block.id == 0 {
      Array::make(all.length(), 0UL)
    } else {
      all.copy()
    }
  }
  fn incoming(block : @milkir.Block) -> Array[UInt64] {
    if block.id == 0 {
      return Array::make(all.length(), 0UL)
    }
    let predecessors = cfg.get_predecessors(block.id)
    if predecessors.is_empty() {
      return Array::make(all.length(), 0UL)
    }
    let live = outputs[predecessors[0]].copy()
    for index in 1..<predecessors.length() {
      let predecessor = outputs[predecessors[index]]
      for word in 0..<live.length() {
        live[word] = live[word] & predecessor[word]
      }
    }
    live
  }
  // Revisit only successors whose predecessor output changed. The transfer
  // and final use checks stay independent, including backedges and side entries.
  let queue = function.blocks.copy()
  let queued : Map[Int32, Bool] = Map([])
  for block in queue {
    queued[block.id] = true
  }
  let mut work = 0
  let mut cursor = 0
  while cursor < queue.length() {
    let block = queue[cursor]
    cursor += 1
    queued[block.id] = false
    let live = incoming(block)
    for id in function.block_instruction_ids(block) {
      work += 1
      if work > 1000000 {
        return Some("physical borrow analysis budget exhausted")
      }
      let inst = function.instruction_by_id(id).unwrap()
      if invalidates_borrows(inst, aliases) {
        for word in 0..<live.length() {
          live[word] = 0UL
        }
      }
      for value in inst.results {
        if origins.get(value.id) is Some(bit) {
          live[bit / 64] = live[bit / 64] | (1UL << (bit % 64))
        }
      }
    }
    if !same_borrows(live, outputs[block.id]) {
      outputs[block.id] = live
      for successor in cfg.get_successors(block.id) {
        if !queued[successor] {
          queue.push(blocks[successor])
          queued[successor] = true
        }
      }
    }
  }
  for block in function.blocks {
    let live = incoming(block)
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      for index, argument in inst.args {
        if aliases.get(argument.id) is Some(origin) {
          if !borrow_present(live, origins[origin]) {
            return Some(
              "instruction \{id}: value \{argument.id} outlived projection \{origin}",
            )
          }
          let permitted = match inst.opcode {
            Memory(Load(_) | LoadNarrow(_, _, _) | Store(_) | StoreNarrow(_)) =>
              index == 0 && valid_borrow_access(inst, shapes[origin])
            Scalar(Copy | Convert(Bitcast) | IntCompare(_)) => true
            Ext(extension, _) =>
              match decode_projection(extension) {
                Some(ArrayLength | ArrayElements(_)) => true
                Some(FieldData(type_, _, _, _, _)) =>
                  shapes.get(origin) is Some(StructData(source_type)) &&
                  source_type == type_
                _ => false
              }
            _ => false
          }
          if !permitted {
            return Some(
              "instruction \{id}: projected value \{argument.id} cannot be operand \{index} of \{inst.opcode}",
            )
          }
        }
      }
      if invalidates_borrows(inst, aliases) {
        for word in 0..<live.length() {
          live[word] = 0UL
        }
      }
      for value in inst.results {
        if origins.get(value.id) is Some(bit) {
          live[bit / 64] = live[bit / 64] | (1UL << (bit % 64))
        }
      }
    }
    let arguments : Array[@milkir.Value] = match block.terminator.unwrap() {
      Jump(_, args) | Return(args) => args
      Branch(condition, _, a, _, b) => [condition] + a + b
      Brz(condition, _, _) | Brnz(condition, _, _) | BrTable(condition, _, _) =>
        [condition]
      Trap(_) | TrapExit(_) => []
    }
    if arguments.any(value => aliases.contains(value.id)) {
      return Some(
        "block \{block.id}: projected address escaped through a terminator",
      )
    }
  }
  None
}

///|
fn valid_borrow_access(inst : @milkir.Inst, shape : Projection) -> Bool {
  let (width, reference, writable) = match shape {
    FieldData(_, _, width, reference, read) => (width, reference == 1, !read)
    ArrayData(width) | ArrayElements(width) if width > 0 => (width, false, true)
    _ => return false
  }
  match inst.opcode {
    Memory(Load(Ref)) => reference && width == 8
    Memory(Store(Ref)) => false // A raw store must never bypass a reference barrier.
    Memory(Load(I32 | F32)) => !reference && width == 4
    Memory(Load(I64 | F64)) => !reference && width == 8
    Memory(LoadNarrow(I32, bits, _)) => !reference && bits == width * 8
    Memory(Store(I32 | F32)) => writable && !reference && width == 4
    Memory(Store(I64 | F64)) => writable && !reference && width == 8
    Memory(StoreNarrow(bits)) => writable && !reference && bits == width * 8
    _ => false
  }
}
