///|
fn poll_term_values(term : @milkir.Terminator) -> Array[@milkir.Value] {
  match term {
    Jump(_, args) | Return(args) => args
    Branch(condition, _, a, _, b) => [condition] + a + b
    Brz(condition, _, _) | Brnz(condition, _, _) | BrTable(condition, _, _) =>
      [condition]
    Trap(_) | TrapExit(_) => []
  }
}

///|
fn version_poll_loops(
  function : @milkir.Function,
  context : @wasm_milkir.WasmValidationContext,
) -> Unit {
  if !function.blocks.any(block => {
      function
      .block_instruction_ids(block)
      .any(id => {
        @wasm_milkir.decode_opcode(
          function.instruction_by_id(id).unwrap().opcode,
        )
        is Some(SafepointPoll(_, _, _, _))
      })
    }) {
    return
  }
  let cfg = @milkir.CFG::build(function)
  let loops = cfg.find_loops()
  let source_blocks = function.blocks.copy()
  let blocks : Map[Int32, @milkir.Block] = Map([])
  let mut total = 0
  for block in function.blocks {
    blocks[block.id] = block
    total += block.instruction_count()
  }
  let mut versions = 0
  for loop_ in loops {
    if versions >= 2 ||
      loop_.blocks.length() > 32 ||
      loops.any(other => {
        other.header != loop_.header && loop_.contains(other.header)
      }) {
      continue
    }
    // Each source poll is charged at most once before the header is revisited.
    // Reject an internal cycle rather than relying on a placement heuristic.
    let degrees : Map[Int32, Int32] = Map([])
    let ready : Array[Int32] = []
    for id in loop_.blocks {
      let degree = if id == loop_.header {
        0
      } else {
        cfg.get_predecessors(id).filter(pred => loop_.contains(pred)).length()
      }
      degrees[id] = degree
      if degree == 0 {
        ready.push(id)
      }
    }
    let mut visited = 0
    while visited < ready.length() {
      let id = ready[visited]
      visited += 1
      for next in cfg.get_successors(id) {
        if next != loop_.header && loop_.contains(next) {
          degrees[next] = degrees[next] - 1
          if degrees[next] == 0 {
            ready.push(next)
          }
        }
      }
    }
    if visited != loop_.blocks.length() {
      continue
    }
    let defined : Map[Int32, Bool] = Map([])
    let mut instructions = 0
    let mut layout : FixedArray[Int32]? = None
    let mut polls = 0
    let mut eligible = true
    for id in loop_.blocks {
      let block = blocks[id]
      if block.terminator is Some(BrTable(_, _, _)) ||
        (
          id != loop_.header &&
          cfg.get_predecessors(id).any(pred => !loop_.contains(pred))
        ) {
        eligible = false
      }
      for param in block.params {
        defined[param.0.id] = true
      }
      for inst_id in function.block_instruction_ids(block) {
        instructions += 1
        let inst = function.instruction_by_id(inst_id).unwrap()
        for value in inst.results {
          defined[value.id] = true
        }
        match @wasm_milkir.decode_opcode(inst.opcode) {
          Some(SafepointPoll(a, b, c, d)) => {
            let offsets : FixedArray[Int32] = [a, b, c, d]
            if layout is Some(previous) && previous != offsets {
              eligible = false
            }
            layout = Some(offsets)
            polls += 1
          }
          _ => {
            let effects = @effects.analyze(inst.opcode)
            if (
                inst.opcode is Ext(_, _) && memory_access(inst, context) is None
              ) ||
              !effects.preserves_physical_addresses() ||
              effects.write is Some(Unknown) {
              eligible = false
            }
          }
        }
      }
    }
    if !eligible ||
      instructions > 96 ||
      total + instructions > 1200 ||
      polls == 0 ||
      polls > 256 {
      continue
    }
    // Frontend exits can use an empty forwarding block before the actual
    // scalar/reference phi. Clone these exits too; keep the final phi shared.
    let region_blocks = loop_.blocks.copy()
    let region_set : Map[Int32, Bool] = Map([])
    for id in region_blocks {
      region_set[id] = true
    }
    let mut added = true
    while added && region_blocks.length() < 40 {
      added = false
      for block in source_blocks {
        if region_blocks.length() >= 40 {
          break
        }
        let predecessors = cfg.get_predecessors(block.id)
        if !region_set.contains(block.id) &&
          block.instruction_count() == 0 &&
          block.terminator is Some(Jump(_, args)) &&
          args.any(value => defined.contains(value.id)) &&
          !predecessors.is_empty() &&
          predecessors.all(pred => region_set.contains(pred)) {
          region_blocks.push(block.id)
          region_set[block.id] = true
          for param in block.params {
            defined[param.0.id] = true
          }
          added = true
        }
      }
    }
    // Other exit uses require a complete scalar/reference phi repair and are
    // deliberately outside this bounded transformation.
    for block in function.blocks {
      if region_set.contains(block.id) {
        continue
      }
      for id in function.block_instruction_ids(block) {
        if function.instruction_by_id(id).unwrap().args.any(value => {
            defined.contains(value.id)
          }) {
          eligible = false
        }
      }
      if block.terminator is Some(term) &&
        poll_term_values(term).any(value => defined.contains(value.id)) {
        eligible = false
      }
    }
    if !eligible {
      continue
    }
    let repeated : Map[(Int32, Int32), Int32] = Map([])
    for id in region_blocks {
      for inst_id in function.block_instruction_ids(blocks[id]) {
        let inst = function.instruction_by_id(inst_id).unwrap()
        if @wasm_milkir.decode_opcode(inst.opcode)
          is Some(
            StructGet(type_, _)
            | StructGetS(type_, _, _)
            | StructGetU(type_, _, _)
          ) &&
          inst.args.get(0) is Some(source) &&
          !defined.contains(source.id) {
          let key = (source.id, type_)
          repeated[key] = repeated.get(key).unwrap_or(0) + 1
        }
      }
    }
    if !repeated.values().any(count => count >= 2) {
      continue
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
    let header = blocks[loop_.header]
    let guard_block = function.new_block0()
    let guard_args = header.params.map(param => {
      function.append_block_param(guard_block, param.1)
    })
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
    for id in region_blocks {
      let copy = function.new_block0()
      copies[id] = copy
      for param in blocks[id].params {
        values[param.0.id] = function.append_block_param(copy, param.1)
      }
      for inst_id in function.block_instruction_ids(blocks[id]) {
        for value in function.instruction_by_id(inst_id).unwrap().results {
          values[value.id] = function.new_value(value.ty)
        }
      }
    }
    fn mapped(value : @milkir.Value) -> @milkir.Value {
      values.get(value.id).unwrap_or(value)
    }
    fn target(id : Int32) -> Int32 {
      if id == loop_.header {
        guard_block.id
      } else {
        copies.get(id).map(block => block.id).unwrap_or(id)
      }
    }
    fn clone_term(term : @milkir.Terminator) -> @milkir.Terminator {
      match term {
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
        BrTable(_, _, _) =>
          abort("poll loop eligibility admitted a branch table")
      }
    }
    for id in region_blocks {
      let source = blocks[id]
      let copy = copies[id]
      for inst_id in function.block_instruction_ids(source) {
        let inst = function.instruction_by_id(inst_id).unwrap()
        let opcode = if @wasm_milkir.decode_opcode(inst.opcode)
          is Some(SafepointPoll(_, _, _, _)) {
          @milkir.Opcode::Ext(
            poll_region_opcode(region, false),
            Signature([Ptr], []),
          )
        } else {
          inst.opcode
        }
        let cloned = function.new_inst(
          opcode,
          if @wasm_milkir.decode_opcode(inst.opcode)
            is Some(SafepointPoll(_, _, _, _)) {
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
      copy.set_terminator(
        clone_term(source.terminator.unwrap()),
        metadata=source.terminator_metadata(),
      )
    }
    guard_block.set_terminator(
      Branch(
        condition,
        copies[loop_.header].id,
        guard_args.copy(),
        header.id,
        guard_args,
      ),
    )
    for id in region_blocks {
      let source = blocks[id]
      let term = source.terminator.unwrap()
      fn edge(next : Int32) -> Int32 {
        if next == loop_.header {
          guard_block.id
        } else {
          next
        }
      }
      source.set_terminator(
        match term {
          Jump(next, args) => Jump(edge(next), args)
          Branch(condition, a, aa, b, ba) =>
            Branch(condition, edge(a), aa, edge(b), ba)
          Brz(condition, a, b) => Brz(condition, edge(a), edge(b))
          Brnz(condition, a, b) => Brnz(condition, edge(a), edge(b))
          _ => term
        },
        metadata=source.terminator_metadata(),
      )
    }
    versions += 1
    total += instructions
  }
}
