///|
/// Version small acyclic regions with repeated object reads. The guard proves
/// sufficient credit; each charge stays at its original position. The complete
/// polling path remains available for callbacks and quantum boundaries.
fn version_poll_acyclic(function : @milkir.Function) -> Bool {
  let sources = function.blocks.copy()
  if sources.is_empty() ||
    sources.length() > 24 ||
    !sources[0].params.is_empty() {
    return false
  }
  let cfg = @milkir.CFG::build(function)
  if sources[0].id != 0 || cfg.postorder().length() != sources.length() {
    return false
  }
  let blocks : Map[Int32, @milkir.Block] = Map([])
  let degrees : Map[Int32, Int32] = Map([])
  let ready : Array[Int32] = []
  for block in sources {
    if block.terminator is Some(BrTable(_, _, _)) {
      return false
    }
    blocks[block.id] = block
    let degree = cfg.get_predecessors(block.id).length()
    degrees[block.id] = degree
    if degree == 0 {
      ready.push(block.id)
    }
  }
  let mut cursor = 0
  while cursor < ready.length() {
    let id = ready[cursor]
    cursor += 1
    for next in cfg.get_successors(id) {
      degrees[next] = degrees[next] - 1
      if degrees[next] == 0 {
        ready.push(next)
      }
    }
  }
  if cursor != sources.length() {
    return false
  }
  let valid : Map[Int32, Bool] = Map([])
  let repeated : Map[(Int32, Int32, Bool), Int32] = Map([])
  let mut layout : FixedArray[Int32]? = None
  let mut polls = 0
  let mut instructions = 0
  for id in ready {
    let mut clean = cfg
      .get_predecessors(id)
      .all(pred => valid.get(pred).unwrap_or(false))
    for inst_id in function.block_instruction_ids(blocks[id]) {
      let inst = function.instruction_by_id(inst_id).unwrap()
      instructions += 1
      match @wasm_milkir.decode_opcode(inst.opcode) {
        Some(SafepointPoll(a, b, c, d)) => {
          if !clean {
            return false
          }
          let offsets : FixedArray[Int32] = [a, b, c, d]
          if layout is Some(previous) && previous != offsets {
            return false
          }
          layout = Some(offsets)
          polls += 1
        }
        Some(
          StructGet(type_, _)
          | StructGetS(type_, _, _)
          | StructGetU(type_, _, _)
        ) => {
          let key = (inst.args[0].id, type_, false)
          repeated[key] = repeated.get(key).unwrap_or(0) + 1
        }
        Some(ArrayGet(type_) | ArrayGetS(type_, _) | ArrayGetU(type_, _)) => {
          let key = (inst.args[0].id, type_, true)
          repeated[key] = repeated.get(key).unwrap_or(0) + 1
        }
        _ => ()
      }
      if !(@wasm_milkir.decode_opcode(inst.opcode)
        is Some(SafepointPoll(_, _, _, _))) &&
        poll_invalidates_credit(function, inst) {
        clean = false
      }
    }
    valid[id] = clean
  }
  if instructions > 64 ||
    polls < 2 ||
    polls > 8 ||
    !repeated.values().any(count => count >= 2) {
    return false
  }
  let offsets = layout.unwrap()
  let region = PollRegion::{
    execution: offsets[0],
    controls: offsets[1],
    callback: offsets[2],
    budget: offsets[3],
    limit: polls,
    key: function.next_inst_id,
  }
  // Block zero is the stable CFG entry. Move its original body to the slow
  // path and keep the dispatch in that existing entry, preserving all IDs.
  let guard_block = sources[0]
  let slow_entry = function.new_block0()
  let entry_ids = function.block_instruction_ids(guard_block).to_owned()
  let entry_term = guard_block.terminator.unwrap()
  let entry_metadata = guard_block.terminator_metadata()
  guard_block.clear_instructions_for_move()
  for id in entry_ids {
    slow_entry.append_inst(function.instruction_by_id(id).unwrap())
  }
  slow_entry.set_terminator(entry_term, metadata=entry_metadata)
  sources[0] = slow_entry
  let condition = function.new_value(I32)
  let controls = function.new_value(Ptr)
  guard_block.append_inst(
    function.new_inst(
      Ext(poll_region_opcode(region, true), Signature([], [I32, Ptr])),
      [],
      [condition, controls],
    ),
  )
  let copies : Map[Int32, @milkir.Block] = Map([])
  let values : Map[Int32, @milkir.Value] = Map([])
  for source in sources {
    let copy = function.new_block0()
    copies[source.id] = copy
    for param in source.params {
      values[param.0.id] = function.append_block_param(copy, param.1)
    }
    for id in function.block_instruction_ids(source) {
      for value in function.instruction_by_id(id).unwrap().results {
        values[value.id] = function.new_value(value.ty)
      }
    }
  }
  fn mapped(value : @milkir.Value) -> @milkir.Value {
    values.get(value.id).unwrap_or(value)
  }
  fn target(id : Int32) -> Int32 {
    copies[id].id
  }
  for source in sources {
    let copy = copies[source.id]
    for id in function.block_instruction_ids(source) {
      let inst = function.instruction_by_id(id).unwrap()
      let polled = @wasm_milkir.decode_opcode(inst.opcode)
        is Some(SafepointPoll(_, _, _, _))
      let cloned = function.new_inst(
        if polled {
          Ext(poll_region_opcode(region, false), Signature([Ptr], []))
        } else {
          inst.opcode
        },
        if polled {
          [controls]
        } else {
          inst.args.map(mapped)
        },
        inst.results.map(mapped),
      )
      for metadata in inst.metadata {
        cloned.add_metadata(metadata)
      }
      copy.append_inst(cloned)
    }
    let term : @milkir.Terminator = match source.terminator.unwrap() {
      Jump(next, args) => Jump(target(next), args.map(mapped))
      Branch(condition, a, aa, b, ba) =>
        Branch(
          mapped(condition),
          target(a),
          aa.map(mapped),
          target(b),
          ba.map(mapped),
        )
      Brz(condition, a, b) => Brz(mapped(condition), target(a), target(b))
      Brnz(condition, a, b) => Brnz(mapped(condition), target(a), target(b))
      Return(args) => Return(args.map(mapped))
      Trap(reason) => Trap(reason)
      TrapExit(reason) => TrapExit(reason)
      BrTable(_, _, _) => abort("acyclic poll region admitted a branch table")
    }
    copy.set_terminator(term, metadata=source.terminator_metadata())
  }
  guard_block.set_terminator(
    Branch(condition, copies[sources[0].id].id, [], sources[0].id, []),
  )
  true
}
