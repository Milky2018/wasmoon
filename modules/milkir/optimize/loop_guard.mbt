///|
/// Clone only a cheap, pure entry test. A zero-trip path still bypasses every
/// trapping body read. No body is cloned and no original trap is speculated.
fn guard_loop_entry(
  function : @milkir.Function,
  loop_ : @milkir.Loop,
  preheader : @milkir.Block,
  definitions : Array[Int32],
) -> @milkir.Block? {
  guard preheader.terminator is Some(Jump(target, arguments)) &&
    target == loop_.header else {
    return None
  }
  guard find_unroll_block(function, loop_.header) is Some(header) &&
    header.instruction_count() <= 8 &&
    arguments.length() == header.params.length() else {
    return None
  }
  for id in function.block_instruction_ids(header) {
    let inst = function.instruction_by_id(id).unwrap()
    if !(inst.opcode is Scalar(_)) ||
      opcode_semantics(inst.opcode).must_preserve_if_unused() {
      return None
    }
  }
  let (condition, a, aa, b, ba) = match header.terminator {
    Some(Branch(condition, a, aa, b, ba)) => (condition, a, aa, b, ba)
    Some(Brnz(condition, a, b)) => (condition, a, [], b, [])
    Some(Brz(condition, a, b)) => (condition, b, [], a, [])
    _ => return None
  }
  if loop_.contains(a) == loop_.contains(b) {
    return None
  }
  // Bypassing the header must preserve definitions used after the loop.
  // Unconditional pure invariants can move before the guard. Varying values
  // require explicit exit parameters; otherwise do not create a bypass edge.
  let invariant : Map[Int32, Bool] = Map([])
  let unconditional : Map[Int32, Bool] = Map([])
  let remaining : Map[Int32, Bool] = Map([])
  for parameter in header.params {
    remaining[parameter.0.id] = true
  }
  for id in function.block_instruction_ids(header) {
    let inst = function.instruction_by_id(id).unwrap()
    if inst.args.all(value => {
        invariant.contains(value.id) ||
        is_defined_outside_loop(value.id, loop_, definitions)
      }) {
      unconditional[id] = true
      for value in inst.results {
        invariant[value.id] = true
      }
    } else {
      for value in inst.results {
        remaining[value.id] = true
      }
    }
  }
  for block in function.blocks {
    if loop_.contains(block.id) {
      continue
    }
    for id in function.block_instruction_ids(block) {
      if function.instruction_by_id(id).unwrap().args.any(value => {
          remaining.contains(value.id)
        }) {
        return None
      }
    }
    if block.terminator is Some(terminator) {
      let values : Array[@milkir.Value] = match terminator {
        Jump(_, arguments) | Return(arguments) => arguments
        Branch(condition, _, a, _, b) => [condition] + a + b
        Brz(condition, _, _)
        | Brnz(condition, _, _)
        | BrTable(condition, _, _) => [condition]
        Trap(_) | TrapExit(_) => []
      }
      if values.any(value => remaining.contains(value.id)) {
        return None
      }
    }
  }
  let kept : Array[@milkir.Inst] = []
  for id in function.block_instruction_ids(header) {
    let inst = function.instruction_by_id(id).unwrap()
    if unconditional.contains(id) {
      preheader.append_inst(inst)
      for value in inst.results {
        definitions[value.id] = preheader.id
      }
    } else {
      kept.push(inst)
    }
  }
  header.set_instructions(kept)
  let values : Map[Int32, @milkir.Value] = Map([])
  for index, parameter in header.params {
    values[parameter.0.id] = arguments[index]
  }
  fn mapped(value : @milkir.Value) -> @milkir.Value {
    values.get(value.id).unwrap_or(value)
  }
  let guard_block = function.new_block0()
  let entered = function.new_block0()
  for id in function.block_instruction_ids(header) {
    let inst = function.instruction_by_id(id).unwrap()
    let results = inst.results.map(value => function.new_value(value.ty))
    let copy = function.new_inst(inst.opcode, inst.args.map(mapped), results)
    for metadata in inst.metadata {
      copy.add_metadata(metadata)
    }
    guard_block.append_inst(copy)
    for index, value in inst.results {
      values[value.id] = results[index]
    }
  }
  guard_block.set_terminator(
    Branch(
      mapped(condition),
      if loop_.contains(a) {
        entered.id
      } else {
        a
      },
      if loop_.contains(a) {
        []
      } else {
        aa.map(mapped)
      },
      if loop_.contains(b) {
        entered.id
      } else {
        b
      },
      if loop_.contains(b) {
        []
      } else {
        ba.map(mapped)
      },
    ),
  )
  entered.set_terminator(Jump(header.id, arguments))
  preheader.set_terminator(Jump(guard_block.id, []))
  Some(entered)
}

///|
/// The header always executes on an entered edge. The continuing body can
/// contribute reads only after the cloned entry test. Stop at an unmovable
/// trap or effect so that the first iteration retains its ordering.
fn first_iteration_invariants(
  function : @milkir.Function,
  loop_ : @milkir.Loop,
  definitions : Array[Int32],
  header_only~ : Bool = false,
) -> Map[Int32, Bool] {
  let result : Map[Int32, Bool] = Map([])
  guard loop_.header != function.blocks[0].id &&
    loop_.blocks.length() <= 64 &&
    find_unroll_block(function, loop_.header) is Some(header) else {
    return result
  }
  let next = if header_only {
    Some(header.id)
  } else {
    match header.terminator {
      Some(Branch(_, a, _, b, _) | Brz(_, a, b) | Brnz(_, a, b)) =>
        if loop_.contains(a) && !loop_.contains(b) {
          Some(a)
        } else if loop_.contains(b) && !loop_.contains(a) {
          Some(b)
        } else {
          None
        }
      _ => None
    }
  }
  guard next is Some(first) && (header_only || first != header.id) else {
    return result
  }
  let invariant : @hashmap.HashMap[Int32, Bool] = HashMap([])
  let memory = LoopMemoryFacts::new(function)
  let visited : Map[Int32, Bool] = Map([])
  let mut current = first
  let mut budget = 256
  while !visited.contains(current) && (header_only || current != header.id) {
    visited[current] = true
    guard find_unroll_block(function, current) is Some(block) else { break }
    for id in function.block_instruction_ids(block) {
      budget -= 1
      if budget < 0 {
        return result
      }
      let inst = function.instruction_by_id(id).unwrap()
      let movable = is_loop_invariant(
        inst,
        loop_,
        definitions,
        invariant,
        memory,
        function,
        first_iteration=true,
      )
      if movable {
        for value in inst.results {
          invariant.set(value.id, true)
        }
        if opcode_semantics(inst.opcode).may_trap {
          result[id] = true
        }
      } else if opcode_semantics(inst.opcode).must_preserve_if_unused() {
        return result
      }
    }
    if header_only {
      break
    }
    match block.terminator {
      Some(Jump(next, _)) if loop_.contains(next) => current = next
      _ => break
    }
  }
  result
}
