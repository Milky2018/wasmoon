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
  let copies = clone_region(function, body, redirect=id => {
    if id == loop_.header {
      Some(id)
    } else {
      None
    }
  })
  latch.set_terminator(
    remap_terminator(latch.terminator.unwrap(), id => {
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
