///|
fn predicated_successors(
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
fn induction_step(
  function : @milkir.Function,
  next : @milkir.Value,
  previous : @milkir.Value,
  increasing : Bool,
) -> Bool {
  guard function.defining_inst(next) is Some(inst) && inst.args is [a, b] else {
    return false
  }
  let (step, expected) = match inst.opcode {
    Scalar(IntBinary(Add)) => {
      let step = if a == previous {
        b
      } else if b == previous {
        a
      } else {
        return false
      }
      (step, if increasing { 1L } else { -1L })
    }
    Scalar(IntBinary(Sub)) if !increasing && a == previous => (b, 1L)
    _ => return false
  }
  function
  .defining_inst(step)
  .map(inst => inst.opcode is Scalar(IntConst(value)) && value == expected)
  .unwrap_or(false)
}

///|
fn bounds_induction(
  function : @milkir.Function,
  index : @milkir.Value,
  inductions : Map[Int32, @milkir.Value],
  increasing : Bool,
) -> (@milkir.Value, Int32)? {
  if inductions.get(index.id) is Some(initial) {
    return Some((initial, 0))
  }
  if increasing {
    return None
  }
  guard function.defining_inst(index) is Some(inst) &&
    inst.opcode is Scalar(IntBinary(Sub)) &&
    inst.args is [base, step] &&
    inductions.get(base.id) is Some(initial) &&
    function.defining_inst(step) is Some(constant) &&
    constant.opcode is Scalar(IntConst(1L)) else {
    return None
  }
  Some((initial, -1))
}

///|
fn predication_value(
  function : @milkir.Function,
  block : @milkir.Block,
  opcode : @milkir.ScalarOp,
  args : Array[@milkir.Value],
) -> @milkir.Value {
  let value = function.new_value(I32)
  block.append_inst(function.new_inst(Scalar(opcode), args, [value]))
  value
}

///|
fn predication_term(
  block : @milkir.Block,
  guards : Map[Int32, (Int32, Array[@milkir.Value])],
) -> @milkir.Terminator {
  match guards.get(block.id) {
    Some((target, args)) => Jump(target, args)
    None => block.terminator.unwrap()
  }
}

///|
fn predication_reached(
  loop_ : @milkir.Loop,
  body : Array[@milkir.Block],
  guards : Map[Int32, (Int32, Array[@milkir.Value])],
) -> Map[Int32, Bool] {
  let blocks : Map[Int32, @milkir.Block] = Map([])
  for block in body {
    blocks[block.id] = block
  }
  let reached : Map[Int32, Bool] = Map([])
  let pending = [loop_.header]
  while !pending.is_empty() {
    let id = pending.pop().unwrap()
    if !loop_.contains(id) || reached.contains(id) {
      continue
    }
    reached[id] = true
    pending.append(predication_term(blocks[id], guards).targets())
  }
  reached
}

///|
fn predication_resolve(
  value : @milkir.Value,
  aliases : Map[Int32, @milkir.Value],
) -> @milkir.Value {
  let mut current = value
  for _ in 0..<=aliases.length() {
    guard aliases.get(current.id) is Some(next) && next != current else {
      return current
    }
    current = next
  }
  value
}

///|
/// Analyze only the selected edges. Header parameters remain varying, while
/// a compatibility join can become one identity after an invariant guard.
fn predication_aliases(
  header : Int32,
  body : Array[@milkir.Block],
  reached : Map[Int32, Bool],
  guards : Map[Int32, (Int32, Array[@milkir.Value])],
) -> Map[Int32, @milkir.Value] {
  let blocks : Map[Int32, @milkir.Block] = Map([])
  for block in body {
    blocks[block.id] = block
  }
  let aliases : Map[Int32, @milkir.Value] = Map([])
  for _ in 0..<body.length() {
    let incoming : Map[Int32, @milkir.Value] = Map([])
    let conflicts : Map[Int32, Bool] = Map([])
    for block in body {
      if !reached.contains(block.id) {
        continue
      }
      let edges = match predication_term(block, guards) {
        Jump(target, args) => [(target, args)]
        Branch(_, yes, aa, no, ba) => [(yes, aa), (no, ba)]
        _ => []
      }
      for (target, args) in edges {
        if target == header || !reached.contains(target) {
          continue
        }
        for i, (parameter, _) in blocks[target].params {
          let actual = predication_resolve(args[i], aliases)
          if incoming.get(parameter.id) is Some(old) && old != actual {
            conflicts[parameter.id] = true
          }
          incoming[parameter.id] = actual
        }
      }
    }
    let mut changed = false
    for id, actual in incoming {
      if !conflicts.contains(id) &&
        id != actual.id &&
        aliases.get(id) != Some(actual) {
        aliases[id] = actual
        changed = true
      }
    }
    if !changed {
      break
    }
  }
  aliases
}

///|
/// Version a unit-step i32 loop when its entry values prove repeated
/// signed and unsigned bounds checks. The original loop remains the complete fallback.
pub fn predicate_counted_loop_bounds(function : @milkir.Function) -> OptResult {
  let result = OptResult::OptResult()
  if function.blocks.length() > 256 || function.next_block_id > 512 {
    return result
  }
  let cfg = @milkir.CFG::build(function)
  let loops = cfg.find_loops()
  if loops.is_empty() {
    return result
  }
  let dominance = cfg.compute_dominance()
  let definitions = loop_definition_blocks(function)
  let sources = function.blocks.copy()
  for loop_ in loops {
    guard loop_.blocks.length() <= 48 &&
      loop_.back_edges is [(latch_id, _)] &&
      cfg.get_loop_preheader(loop_) is Some(preheader_id) &&
      find_unroll_block(function, preheader_id) is Some(preheader) &&
      preheader.terminator is Some(Jump(header_id, initial)) &&
      header_id == loop_.header &&
      find_unroll_block(function, header_id) is Some(header) &&
      find_unroll_block(function, latch_id) is Some(latch) &&
      latch.terminator is Some(Jump(back, next)) &&
      back == header_id &&
      header.params.length() == initial.length() &&
      next.length() == initial.length() else {
      continue
    }
    if loops.any(inner => {
        inner.header != header_id && loop_.contains(inner.header)
      }) {
      continue
    }
    let (condition, body_entry) = match header.terminator {
      Some(Branch(condition, yes, _, no, _)) if loop_.contains(yes) &&
        !loop_.contains(no) => (condition, yes)
      _ => continue
    }
    guard function.defining_inst(condition) is Some(comparison) &&
      comparison.opcode is Scalar(IntCompare(predicate)) &&
      comparison.args is [primary, limit] &&
      primary.ty == I32 &&
      limit.ty == I32 &&
      !loop_.contains(definitions[limit.id]) &&
      (
        definitions[limit.id] < 0 ||
        dominance.dominates(definitions[limit.id], preheader.id)
      ) else {
      continue
    }
    let increasing = match predicate {
      Slt => true
      Sge if function
        .defining_inst(limit)
        .map(inst => inst.opcode is Scalar(IntConst(0L)))
        .unwrap_or(false) => false
      _ => continue
    }
    let inductions : Map[Int32, @milkir.Value] = Map([])
    for index, (parameter, type_) in header.params {
      if type_ == I32 &&
        induction_step(function, next[index], parameter, increasing) {
        inductions[parameter.id] = initial[index]
      }
    }
    guard inductions.get(primary.id) is Some(start) else { continue }
    let body = sources.filter(block => loop_.contains(block.id))
    let size = body.fold(init=0, fn(total, block) {
      total + block.instruction_count()
    })
    if size < 8 ||
      size > 160 ||
      body.any(block => {
        block.id != header_id &&
        cfg.get_predecessors(block.id).any(id => !loop_.contains(id))
      }) {
      continue
    }
    let guards : Map[Int32, (Int32, Array[@milkir.Value])] = Map([])
    let invariant_guards : Map[Int32, @milkir.Value] = Map([])
    for block in body {
      if block.id == header_id || invariant_guards.length() == 4 {
        continue
      }
      if block.terminator is Some(Branch(condition, yes, args, _, _)) &&
        !loop_.contains(definitions[condition.id]) &&
        (
          definitions[condition.id] < 0 ||
          dominance.dominates(definitions[condition.id], preheader.id)
        ) {
        guards[block.id] = (yes, args)
        invariant_guards[block.id] = condition
      }
    }
    let provisional = predication_reached(loop_, body, guards)
    let aliases = predication_aliases(header_id, body, provisional, guards)
    let lengths : Map[Int32, @milkir.Value] = Map([])
    let secondaries : Map[Int32, @milkir.Value] = Map([])
    let decreasing_bounds : Array[(@milkir.Value, Int32, @milkir.Value)] = []
    let mut bounds_count = 0
    for block in body {
      if !provisional.contains(block.id) ||
        !dominance.dominates(body_entry, block.id) {
        continue
      }
      guard block.terminator is Some(Branch(bounds_condition, yes, aa, _, _)) &&
        function.defining_inst(bounds_condition) is Some(check) &&
        check.opcode is Scalar(IntCompare(Ult | Slt)) &&
        check.args is [index, raw_length] &&
        bounds_count < 4 else {
        continue
      }
      let length = predication_resolve(raw_length, aliases)
      if length.ty == I32 &&
        bounds_induction(function, index, inductions, increasing)
        is Some((initial_index, offset)) &&
        !loop_.contains(definitions[length.id]) &&
        (
          definitions[length.id] < 0 ||
          dominance.dominates(definitions[length.id], preheader.id)
        ) {
        guards[block.id] = (yes, aa)
        bounds_count += 1
        lengths[length.id] = length
        if increasing {
          if index != primary {
            secondaries[index.id] = initial_index
          }
        } else {
          decreasing_bounds.push((initial_index, offset, length))
        }
      }
    }
    if bounds_count < 2 {
      continue
    }
    let mut valid = true
    for block in sources {
      if loop_.contains(block.id) {
        continue
      }
      let used : Array[@milkir.Value] = []
      rewrite_terminator_values(block.terminator.unwrap(), value => {
        used.push(value)
        value
      })
      |> ignore
      for id in function.block_instruction_ids(block) {
        used.append(function.instruction_by_id(id).unwrap().args)
      }
      if used.any(value => loop_.contains(definitions[value.id])) {
        valid = false
      }
    }
    if !valid {
      continue
    }
    let reached = predication_reached(loop_, body, guards)
    if !reached.contains(latch_id) {
      continue
    }
    let fast_body = body.filter(block => reached.contains(block.id))
    // The fast region must contain no moving/reentrant operation. Original
    // collecting or trapping fallback operations remain on the general path.
    if fast_body.any(block => {
        function
        .block_instruction_ids(block)
        .any(id => {
          let opcode = function.instruction_by_id(id).unwrap().opcode
          opcode is Call(_) ||
          (
            opcode is Ext(op, _) &&
            (op.effects is None || op.effects.unwrap().invalidates_addresses)
          )
        })
      }) {
      continue
    }
    let copies : Map[Int32, @milkir.Block] = Map([])
    let values : Map[Int32, @milkir.Value] = Map([])
    for block in fast_body {
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
    for block in fast_body {
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
      let term = predication_term(block, guards)
      copy.set_terminator(
        predicated_successors(
          rewrite_terminator_values(term, value).unwrap_or(term),
          id => copies.get(id).map(block => block.id).unwrap_or(id),
        ),
        metadata=block.terminator_metadata(),
      )
    }
    let zero = predication_value(function, preheader, IntConst(0L), [])
    let checks = [
      predication_value(function, preheader, IntCompare(Sge), [start, zero]),
    ]
    for id, condition in invariant_guards {
      if reached.contains(id) {
        checks.push(condition)
      }
    }
    // Signed guards can share the same proof only in the nonnegative domain.
    // Every rejected domain retains the complete original loop.
    for _, length in lengths {
      checks.push(
        predication_value(function, preheader, IntCompare(Sge), [length, zero]),
      )
    }
    if increasing {
      checks.push(
        predication_value(function, preheader, IntCompare(Sge), [limit, zero]),
      )
      for _, length in lengths {
        checks.push(
          predication_value(function, preheader, IntCompare(Ule), [
            limit, length,
          ]),
        )
      }
      for _, initial_index in secondaries {
        checks.push(
          predication_value(function, preheader, IntCompare(Sge), [
            initial_index, zero,
          ]),
        )
        checks.push(
          predication_value(function, preheader, IntCompare(Ule), [
            initial_index, start,
          ]),
        )
      }
    } else {
      for (initial_index, offset, length) in decreasing_bounds {
        checks.push(
          predication_value(
            function,
            preheader,
            IntCompare(if offset == 0 { Sge } else { Sgt }),
            [initial_index, zero],
          ),
        )
        let first = if offset == 0 {
          initial_index
        } else {
          let one = predication_value(function, preheader, IntConst(1L), [])
          predication_value(function, preheader, IntBinary(Sub), [
            initial_index, one,
          ])
        }
        checks.push(
          predication_value(function, preheader, IntCompare(Sge), [first, start]),
        )
        checks.push(
          predication_value(function, preheader, IntCompare(Ult), [
            first, length,
          ]),
        )
      }
    }
    let mut dispatch = preheader
    for check in checks {
      let next = function.new_block0()
      dispatch.set_terminator(Branch(check, next.id, [], header_id, initial))
      dispatch = next
    }
    dispatch.set_terminator(Jump(copies[header_id].id, initial))
    result.mark_changed()
    return result
  }
  result
}
