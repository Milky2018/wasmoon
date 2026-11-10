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
  fn replace(inst : @milkir.Inst) -> (@milkir.Opcode, Array[@milkir.Value])? {
    if inst.results is [defined] && defined == reference {
      return Some((Scalar(Copy), [expected]))
    }
    if inst.opcode is Scalar(IntCompare(Eq | Ne)) &&
      inst.args is [a, b] &&
      (
        (a == reference && null_reference_constant(function, b)) ||
        (b == reference && null_reference_constant(function, a))
      ) {
      let truth = if inst.opcode is Scalar(IntCompare(Ne)) { 1L } else { 0L }
      return Some((Scalar(IntConst(truth)), []))
    }
    if inst.id == check.id {
      Some((Scalar(IntConst(1L)), []))
    } else {
      None
    }
  }
  let fast = @generic.clone_region(
    function,
    body,
    replace_instruction=replace,
    select_terminator=block => {
      if block.id == guard_block.id {
        Jump(hit, hit_args)
      } else {
        block.terminator.unwrap()
      }
    },
  )
  let first = @generic.clone_region(
    function,
    tail,
    replace_instruction=replace,
    redirect=id => if id == loop_.header { Some(fast[id].id) } else { None },
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
