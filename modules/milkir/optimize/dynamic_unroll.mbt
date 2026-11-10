///|
fn dynamic_unroll_target(
  term : @milkir.Terminator,
  target : (Int32) -> Int32,
) -> @milkir.Terminator {
  match term {
    Jump(id, args) => Jump(target(id), args)
    Branch(condition, yes, aa, no, ba) =>
      Branch(condition, target(yes), aa, target(no), ba)
    Brz(condition, yes, no) => Brz(condition, target(yes), target(no))
    Brnz(condition, yes, no) => Brnz(condition, target(yes), target(no))
    BrTable(index, targets, default_) =>
      BrTable(index, targets.map(target), target(default_))
    Return(_) | Trap(_) | TrapExit(_) => term
  }
}

///|
/// Perform one bounded unrolling step after memory placement. Each copied
/// header retains its condition, so dynamic bounds and early exits need no
/// trip-count speculation. Callers apply this step once per prepared body.
pub fn unroll_dynamic_memory_loop(function : @milkir.Function) -> OptResult {
  let result = OptResult::OptResult()
  if function.blocks.length() > 256 {
    return result
  }
  let cfg = @milkir.CFG::build(function)
  let loops = cfg.find_loops()
  let definitions = loop_definition_blocks(function)
  let mut selected : (@milkir.Loop, Array[@milkir.Block], @milkir.Block)? = None
  let mut selected_size = 0
  let mut selected_pure = false
  for loop_ in loops {
    guard loop_.blocks.length() <= 24 &&
      loop_.back_edges is [(latch_id, _)] &&
      find_unroll_block(function, latch_id) is Some(latch) &&
      latch.terminator is Some(Jump(target, _)) &&
      target == loop_.header else {
      continue
    }
    if loops.any(inner => {
        inner.header != loop_.header && loop_.contains(inner.header)
      }) {
      continue
    }
    let body = function.blocks.filter(block => loop_.contains(block.id))
    if body.any(block => {
        block.id != loop_.header &&
        cfg.get_predecessors(block.id).any(id => !loop_.contains(id))
      }) {
      continue
    }
    let mut size = 0
    let mut loads = 0
    let mut admitted = true
    let mut pure = true
    for block in body {
      for id in function.block_instruction_ids(block) {
        let opcode = function.instruction_by_id(id).unwrap().opcode
        size += 1
        if opcode is Memory(Load(_) | LoadNarrow(_, _, _)) {
          loads += 1
        }
        if opcode is Ext(_, _) {
          pure = false
        }
        if opcode is Call(_) ||
          (
            opcode is Ext(op, _) &&
            (op.effects is None || op.effects.unwrap().invalidates_addresses)
          ) {
          admitted = false
        }
      }
    }
    if !admitted ||
      loads == 0 ||
      size < 8 ||
      size > 80 ||
      (!pure && selected_pure) ||
      (pure == selected_pure && size <= selected_size) {
      continue
    }
    // Exit parameters carry each iteration's state. A direct use outside the
    // loop would otherwise keep the first copy's value on a second-copy exit.
    let escapes = function.blocks.any(block => {
      if loop_.contains(block.id) {
        return false
      }
      let mut escapes = false
      rewrite_terminator_values(block.terminator.unwrap(), value => {
        escapes = escapes ||
          is_defined_in_unroll_loop(loop_, value.id, definitions)
        value
      })
      |> ignore
      escapes ||
      function
      .block_instruction_ids(block)
      .any(id => {
        function.instruction_by_id(id).unwrap().args.any(value => {
          is_defined_in_unroll_loop(loop_, value.id, definitions)
        })
      })
    })
    if escapes {
      continue
    }
    selected = Some((loop_, body, latch))
    selected_size = size
    selected_pure = pure
  }
  guard selected is Some((loop_, body, latch)) else { return result }
  let copies : Map[Int32, @milkir.Block] = Map([])
  let values : Map[Int32, @milkir.Value] = Map([])
  for block in body {
    let copy = function.new_block0()
    copies[block.id] = copy
    for (value, type_) in block.params {
      values[value.id] = function.append_block_param(copy, type_)
    }
    for id in function.block_instruction_ids(block) {
      for value in function.instruction_by_id(id).unwrap().results {
        values[value.id] = function.new_value(value.ty)
      }
    }
  }
  fn value(v : @milkir.Value) -> @milkir.Value {
    values.get(v.id).unwrap_or(v)
  }
  for block in body {
    let copy = copies[block.id]
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      let cloned = function.new_inst(
        inst.opcode,
        inst.args.map(value),
        inst.results.map(value),
      )
      for metadata in inst.metadata {
        cloned.add_metadata(metadata)
      }
      copy.append_inst(cloned)
    }
    let term = block.terminator.unwrap()
    copy.set_terminator(
      dynamic_unroll_target(
        rewrite_terminator_values(term, value).unwrap_or(term),
        id => {
          if id == loop_.header {
            id
          } else {
            copies.get(id).map(block => block.id).unwrap_or(id)
          }
        },
      ),
      metadata=block.terminator_metadata(),
    )
  }
  let term = latch.terminator.unwrap()
  latch.set_terminator(
    dynamic_unroll_target(term, id => {
      if id == loop_.header {
        copies[id].id
      } else {
        id
      }
    }),
    metadata=latch.terminator_metadata(),
  )
  result.mark_changed()
  result
}
