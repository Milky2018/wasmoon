///|
fn reference_loop_invariant(
  value : @milkir.Value,
  loop_ : @milkir.Loop,
  definitions : Map[Int32, Int32],
  producers : Map[Int32, @milkir.Inst],
  context : @wasm_milkir.WasmValidationContext,
  writes : Array[@effects.Location],
) -> Bool {
  let mut current = value
  for _ in 0..<8 {
    if !loop_.contains(definitions.get(current.id).unwrap_or(-1)) {
      return true
    }
    guard producers.get(current.id) is Some(inst) else { return false }
    match @wasm_milkir.decode_opcode(inst.opcode) {
      Some(StructGet(type_, field)) => {
        guard context.struct_field(type_, field) is Some(contract) &&
          inst.args is [receiver] &&
          (
            !contract.mutable_ ||
            !writes.any(write => {
              match write {
                StructField(_, written) => written == field
                Unknown => true
                _ => false
              }
            })
          ) else {
          return false
        }
        current = receiver
      }
      _ => {
        guard inst.opcode is Scalar(Copy) && inst.args is [source] else {
          return false
        }
        current = source
      }
    }
  }
  !loop_.contains(definitions.get(current.id).unwrap_or(-1))
}

///|
fn reference_region_targets(
  term : @milkir.Terminator,
  target : (Int32) -> Int32,
  value : (@milkir.Value) -> @milkir.Value,
) -> @milkir.Terminator {
  match term {
    Jump(next, args) => Jump(target(next), args.map(value))
    Branch(condition, yes, aa, no, ba) =>
      Branch(
        value(condition),
        target(yes),
        aa.map(value),
        target(no),
        ba.map(value),
      )
    Brz(condition, yes, no) => Brz(value(condition), target(yes), target(no))
    Brnz(condition, yes, no) => Brnz(value(condition), target(yes), target(no))
    BrTable(index, targets, default_) =>
      BrTable(value(index), targets.map(target), target(default_))
    Return(args) => Return(args.map(value))
    Trap(_) | TrapExit(_) => term
  }
}

///|
fn null_reference_constant(
  function : @milkir.Function,
  value : @milkir.Value,
) -> Bool {
  match function.defining_inst(value) {
    Some(inst) => inst.opcode is Scalar(IntConst(0L))
    None => false
  }
}

///|
fn clone_reference_region(
  function : @milkir.Function,
  body : Array[@milkir.Block],
  guard_block : Int32,
  guard_instruction : Int32,
  hit : Int32,
  hit_args : Array[@milkir.Value],
  header : Int32,
  next_header : Int32?,
  checked_reference : @milkir.Value,
  expected_reference : @milkir.Value,
) -> Map[Int32, @milkir.Block] {
  let blocks : Map[Int32, @milkir.Block] = Map([])
  let values : Map[Int32, @milkir.Value] = Map([])
  for block in body {
    let copy = function.new_block0()
    blocks[block.id] = copy
    for parameter in block.params {
      values[parameter.0.id] = function.append_block_param(copy, parameter.1)
    }
    for id in function.block_instruction_ids(block) {
      for result in function.instruction_by_id(id).unwrap().results {
        values[result.id] = function.new_value(result.ty)
      }
    }
  }
  fn value(original : @milkir.Value) -> @milkir.Value {
    values.get(original.id).unwrap_or(original)
  }
  fn target(original : Int32) -> Int32 {
    if original == header && next_header is Some(next) {
      next
    } else {
      blocks.get(original).map(block => block.id).unwrap_or(original)
    }
  }
  for block in body {
    let copy = blocks[block.id]
    for id in function.block_instruction_ids(block) {
      let original = function.instruction_by_id(id).unwrap()
      let nullable = original.opcode is Scalar(IntCompare(Eq | Ne)) &&
        original.args.length() == 2 &&
        (
          (
            original.args[0] == checked_reference &&
            null_reference_constant(function, original.args[1])
          ) ||
          (
            original.args[1] == checked_reference &&
            null_reference_constant(function, original.args[0])
          )
        )
      let cloned = if original.results is [defined] &&
        defined == checked_reference {
        function.new_inst(
          Scalar(Copy),
          [expected_reference],
          original.results.map(value),
        )
      } else if nullable {
        let truth = if original.opcode is Scalar(IntCompare(Ne)) {
          1L
        } else {
          0L
        }
        function.new_inst(
          Scalar(IntConst(truth)),
          [],
          original.results.map(value),
        )
      } else if id == guard_instruction {
        function.new_inst(Scalar(IntConst(1L)), [], original.results.map(value))
      } else {
        function.new_inst(
          original.opcode,
          original.args.map(value),
          original.results.map(value),
        )
      }
      for metadata in original.metadata {
        cloned.add_metadata(metadata)
      }
      copy.append_inst(cloned)
    }
    let term = if block.id == guard_block {
      @milkir.Terminator::Jump(hit, hit_args)
    } else {
      block.terminator.unwrap()
    }
    copy.set_terminator(
      reference_region_targets(term, target, value),
      metadata=block.terminator_metadata(),
    )
  }
  blocks
}

///|
fn specialize_reference_loop_at(
  function : @milkir.Function,
  context : @wasm_milkir.WasmValidationContext,
  cfg : @milkir.CFG,
  dominance : @milkir.Dominance,
  sources : Array[@milkir.Block],
  definitions : Map[Int32, Int32],
  producers : Map[Int32, @milkir.Inst],
  loop_ : @milkir.Loop,
  guard_block : @milkir.Block,
) -> Bool {
  guard loop_.contains(guard_block.id) &&
    guard_block.terminator
    is Some(Branch(condition, hit, hit_args, miss, miss_args)) &&
    producers.get(condition.id) is Some(check) &&
    @wasm_milkir.decode_opcode(check.opcode) is Some(ExecutableFuncRefEq) &&
    check.args is [reference, expected] &&
    !loop_.contains(definitions.get(expected.id).unwrap_or(-1)) else {
    return false
  }
  let reached : Map[Int32, Bool] = Map([])
  let work = [loop_.header]
  let mut valid = true
  while !work.is_empty() {
    let id = work.pop().unwrap()
    if reached.contains(id) {
      continue
    }
    if !dominance.dominates(loop_.header, id) {
      valid = false
      break
    }
    reached[id] = true
    if id == guard_block.id {
      work.push(hit)
    } else {
      work.append(cfg.get_successors(id))
    }
  }
  let body = sources.filter(block => reached.contains(block.id))
  let size = body.fold(init=0, fn(total, block) {
    total + block.instruction_count()
  })
  if !valid || body.length() > 48 || size > 192 {
    return false
  }
  // Collection preserves logical fields and executable records.
  // Reentry, heap replacement, suspension or any remaining callback does not.
  let writes : Array[@effects.Location] = []
  for block in body {
    for id in function.block_instruction_ids(block) {
      let effects = @effects.analyze(
        function.instruction_by_id(id).unwrap().opcode,
      )
      if !effects.preserves_checked_references() {
        valid = false
      }
      if effects.write is Some(write) {
        writes.push(write)
      }
    }
  }
  if !reference_loop_invariant(
      reference, loop_, definitions, producers, context, writes,
    ) {
    valid = false
  }
  if !valid {
    return false
  }
  let tail_ids : Map[Int32, Bool] = Map([])
  let pending = [hit]
  while !pending.is_empty() {
    let id = pending.pop().unwrap()
    if id == loop_.header || tail_ids.contains(id) {
      continue
    }
    if !reached.contains(id) {
      valid = false
      break
    }
    tail_ids[id] = true
    for next in cfg.get_successors(id) {
      if next != loop_.header && dominance.dominates(next, id) {
        valid = false
      }
      pending.push(next)
    }
  }
  let tail = sources.filter(block => tail_ids.contains(block.id))
  let tail_size = tail.fold(init=0, fn(total, block) {
    total + block.instruction_count()
  })
  if !valid ||
    tail_ids.contains(guard_block.id) ||
    size + tail_size > 256 ||
    body.length() + tail.length() > 64 {
    return false
  }
  let fast = clone_reference_region(
    function,
    body,
    guard_block.id,
    check.id,
    hit,
    hit_args,
    loop_.header,
    None,
    reference,
    expected,
  )
  let first = clone_reference_region(
    function,
    tail,
    guard_block.id,
    check.id,
    hit,
    hit_args,
    loop_.header,
    Some(fast[loop_.header].id),
    reference,
    expected,
  )
  guard_block.set_terminator(
    Branch(condition, first[hit].id, hit_args, miss, miss_args),
    metadata=guard_block.terminator_metadata(),
  )
  let reachable : Map[Int32, Bool] = Map([])
  for id in @milkir.CFG::build(function).reverse_postorder() {
    reachable[id] = true
  }
  function.retain_blocks(block => reachable.contains(block.id))
  return true
}

///|
/// The original iteration checks executable identity before entering a private
/// loop version. Its first hit tail is copied separately, so entry never repeats
/// an allocation or an earlier trap. Only the following iterations omit that
/// check, and only while target identity and backend state survive.
fn specialize_reference_loops(
  function : @milkir.Function,
  context : @wasm_milkir.WasmValidationContext,
) -> Bool {
  if function.blocks.length() > 128 {
    return false
  }
  let cfg = @milkir.CFG::build(function)
  let dominance = cfg.compute_dominance()
  let sources = function.blocks.copy()
  let definitions : Map[Int32, Int32] = Map([])
  let producers : Map[Int32, @milkir.Inst] = Map([])
  for block in sources {
    for parameter in block.params {
      definitions[parameter.0.id] = block.id
    }
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      for result in inst.results {
        definitions[result.id] = block.id
        producers[result.id] = inst
      }
    }
  }
  for loop_ in cfg.find_loops() {
    if loop_.blocks.length() > 32 {
      continue
    }
    for guard_block in sources {
      if specialize_reference_loop_at(
          function, context, cfg, dominance, sources, definitions, producers, loop_,
          guard_block,
        ) {
        return true
      }
    }
  }
  false
}
