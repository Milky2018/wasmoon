///|
fn loop_cache_key(
  function : @milkir.Function,
  inst : @milkir.Inst,
) -> (GcRead, @milkir.Value)? {
  if inst.metadata.any(m => m is Comment("wasm.gc.loop.memoized")) ||
    inst.results.length() != 1 ||
    !(inst.results[0].ty is (I32 | I64 | Ref)) {
    return None
  }
  let key = match @wasm_milkir.decode_opcode(inst.opcode) {
    Some(ArrayLen) => Some((-1, -1, 0))
    Some(StructGet(t, f)) => Some((t, f, 0))
    Some(StructGetS(t, f, w)) => Some((t, f, w * 4 + 1))
    Some(StructGetU(t, f, w)) => Some((t, f, w * 4 + 2))
    _ => None
  }
  if key is Some((type_index, field_index, mode)) && inst.args is [reference] {
    let object = canonical_value(function, reference)
    Some(({ object: object.id, type_index, field_index, mode, }, object))
  } else {
    None
  }
}

///|
fn loop_cache_edge(
  term : @milkir.Terminator,
  loop_ : @milkir.Loop,
  state : Array[@milkir.Value],
) -> @milkir.Terminator {
  fn args(
    target : Int32,
    original : Array[@milkir.Value],
  ) -> Array[@milkir.Value] {
    if loop_.contains(target) {
      original + state
    } else {
      original
    }
  }
  match term {
    Jump(target, values) => Jump(target, args(target, values))
    Branch(condition, left, left_args, right, right_args) =>
      Branch(
        condition,
        left,
        args(left, left_args),
        right,
        args(right, right_args),
      )
    Brz(condition, left, right) =>
      Branch(condition, right, args(right, []), left, args(left, []))
    Brnz(condition, left, right) =>
      Branch(condition, left, args(left, []), right, args(right, []))
    _ => term
  }
}

///|
/// Keep the first query at its original execution point (and preserve
/// its trap). Later iterations carry that immutable result as ordinary SSA.
/// This does not speculate a null check on a zero-trip or conditional path.
fn cache_one_loop_gc_read(function : @milkir.Function) -> Bool {
  if function.blocks.length() > 1024 {
    return false
  }
  let cfg = @milkir.CFG::build(function)
  let dominance = cfg.compute_dominance()
  let definitions : Map[Int32, Int32] = Map([])
  let blocks : Map[Int32, @milkir.Block] = Map([])
  for block in function.blocks {
    blocks[block.id] = block
    for (value, _) in block.params {
      definitions[value.id] = block.id
    }
    for id in function.block_instruction_ids(block) {
      for value in function.instruction_by_id(id).unwrap().results {
        definitions[value.id] = block.id
      }
    }
  }
  let mut work = 0
  for loop_ in cfg.find_loops() {
    guard cfg.get_loop_preheader(loop_) is Some(preheader_id) else { continue }
    let mut safe = true
    let mut candidate : (GcRead, @milkir.Value, @milkir.Type)? = None
    let writes : Map[Int32, Bool] = Map([])
    for id in loop_.blocks {
      if cfg
        .get_predecessors(id)
        .any(pred => {
          !loop_.contains(pred) && (id != loop_.header || pred != preheader_id)
        }) {
        safe = false
        break
      }
      let block = blocks[id]
      if block.terminator is Some(BrTable(_, _, _)) {
        safe = false
        break
      }
      for inst_id in function.block_instruction_ids(block) {
        work += 1
        if work > 100000 {
          return false
        }
        let inst = function.instruction_by_id(inst_id).unwrap()
        if !gc_loop_local(inst) {
          safe = false
          break
        }
        if @wasm_milkir.decode_opcode(inst.opcode) is Some(StructSet(_, field)) {
          writes[field] = true
        }
        if loop_cache_key(function, inst) is Some((key, object)) {
          if !(definitions.get(object.id) is Some(defined) &&
            !dominance.dominates(defined, preheader_id)) &&
            (
              candidate is None ||
              (inst.results[0].ty is Ref && !(candidate.unwrap().2 is Ref))
            ) {
            candidate = Some((key, object, inst.results[0].ty))
          }
        }
      }
      if !safe {
        break
      }
    }
    guard safe &&
      candidate is Some((key, object, result_type)) &&
      !writes.contains(key.field_index) else {
      continue
    }
    let preheader = blocks[preheader_id]
    guard preheader.terminator is Some(incoming) else { continue }
    let zero = function.new_value(I32)
    let one = function.new_value(I32)
    let empty = function.new_value(result_type)
    preheader.append_inst(function.new_inst(Scalar(IntConst(0L)), [], [zero]))
    preheader.append_inst(function.new_inst(Scalar(IntConst(1L)), [], [one]))
    preheader.append_inst(function.new_inst(Scalar(IntConst(0L)), [], [empty]))
    preheader.set_terminator(loop_cache_edge(incoming, loop_, [zero, empty]))
    let parameters : Map[Int32, Array[@milkir.Value]] = Map([])
    for id in loop_.blocks {
      parameters[id] = [
        function.append_block_param(blocks[id], I32),
        function.append_block_param(blocks[id], result_type),
      ]
    }
    for id in loop_.blocks {
      let block = blocks[id]
      let original = function
        .block_instruction_ids(block)
        .to_owned()
        .map(id => function.instruction_by_id(id).unwrap())
      let term = block.terminator.unwrap()
      let mut current = block
      let mut state = parameters[id]
      let mut available = false
      let mut instructions : Array[@milkir.Inst] = []
      for inst in original {
        if loop_cache_key(function, inst) is Some((read_key, _)) &&
          read_key == key {
          if !available {
            let slow = function.new_block0()
            let value = function.new_value(result_type)
            let join = function.new_block([value])
            let loaded = function.new_value(result_type)
            let query = function.new_inst(inst.opcode, [object], [loaded])
            for metadata in inst.metadata {
              query.add_metadata(metadata)
            }
            query.add_metadata(Comment("wasm.gc.loop.memoized"))
            slow.append_inst(query)
            slow.set_terminator(Jump(join.id, [loaded]))
            current.set_instructions(instructions)
            current.set_terminator(
              Branch(state[0], join.id, [state[1]], slow.id, []),
            )
            current = join
            instructions = []
            state = [one, value]
            available = true
          }
          inst.args.clear()
          inst.args.push(state[1])
          inst.set_opcode(Scalar(Copy))
        }
        instructions.push(inst)
      }
      current.set_instructions(instructions)
      current.set_terminator(loop_cache_edge(term, loop_, state))
    }
    return true
  }
  false
}

///|
fn cache_loop_gc_reads(function : @milkir.Function) -> Bool {
  let mut changed = false
  // Rebuild the CFG after each split. A previous loop can contain the next
  // loop's preheader, whose terminator moves to a new continuation block.
  for _ in 0..<8 {
    if !cache_one_loop_gc_read(function) {
      break
    }
    changed = true
  }
  changed
}
