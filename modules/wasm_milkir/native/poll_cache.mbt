///|
#derive(Eq)
priv struct PollCacheLayout {
  execution : Int32
  controls : Int32
  callback : Int32
  budget : Int32
}

///|
#derive(Eq)
priv enum CachedPoll {
  Step(PollCacheLayout, Bool)
  Publish(PollCacheLayout)
}

///|
fn CachedPoll::opcode(self : CachedPoll) -> @milkir.ExtOp {
  let (name, layout) = match self {
    Step(layout, fresh) =>
      (
        if fresh {
          "native_acquire_poll_budget"
        } else {
          "native_cached_poll"
        },
        layout,
      )
    Publish(layout) => ("native_publish_poll_budget", layout)
  }
  ExtOp(@wasm_milkir.WASM_DIALECT, name, [
    layout.execution,
    layout.controls,
    layout.callback,
    layout.budget,
  ])
}

///|
fn decode_cached_poll(op : @milkir.ExtOp) -> CachedPoll? {
  guard op.immediates is [execution, controls, callback, budget] && budget >= 0 else {
    return None
  }
  let layout = { execution, controls, callback, budget, }
  let poll : CachedPoll = match op.opcode {
    "native_cached_poll" => Step(layout, false)
    "native_acquire_poll_budget" => Step(layout, true)
    "native_publish_poll_budget" => Publish(layout)
    _ => return None
  }
  if op == poll.opcode() {
    Some(poll)
  } else {
    None
  }
}

///|
fn cached_poll_source(opcode : @milkir.Opcode) -> PollCacheLayout? {
  match @wasm_milkir.decode_opcode(opcode) {
    Some(SafepointPoll(execution, controls, callback, budget)) if budget >= 0 =>
      Some({ execution, controls, callback, budget, })
    _ => None
  }
}

///|
/// Only these operations may execute with an unpublished countdown. In
/// particular, even a linear-memory load can fault into the runtime.
fn poll_cache_transparent(opcode : @milkir.Opcode) -> Bool {
  match opcode {
    Scalar(IntBinary(SignedDiv | UnsignedDiv | SignedRem | UnsignedRem)) =>
      false
    Scalar(IntConst(_) | IntBinary(_) | IntUnary(_) | IntCompare(_) | Copy) =>
      true
    _ => false
  }
}

///|
fn poll_cache_edges(
  term : @milkir.Terminator,
  map : (Int32, Array[@milkir.Value]) -> (Int32, Array[@milkir.Value]),
) -> @milkir.Terminator {
  match term {
    Jump(id, args) => {
      let (id, args) = map(id, args)
      Jump(id, args)
    }
    Branch(condition, yes, aa, no, ba) => {
      let (yes, aa) = map(yes, aa)
      let (no, ba) = map(no, ba)
      Branch(condition, yes, aa, no, ba)
    }
    Brnz(condition, yes, no) | Brz(condition, no, yes) => {
      let (yes, aa) = map(yes, [])
      let (no, ba) = map(no, [])
      Branch(condition, yes, aa, no, ba)
    }
    _ => term
  }
}

///|
/// Retain the first bounded, single-entry loop that can reuse a countdown
/// across multiple poll sites. Calls and potentially faulting instructions
/// are boundaries. Leave barrier-free loops on the existing poll path.
fn find_poll_cache_loop(
  function : @milkir.Function,
  cfg : @milkir.CFG,
  blocks : Map[Int32, @milkir.Block],
) -> (@milkir.Loop, PollCacheLayout)? {
  let loops = cfg.find_loops()
  for loop_ in loops {
    if loop_.header == function.blocks[0].id ||
      loop_.blocks.length() > 16 ||
      loops.any(other => {
        other.header != loop_.header && loop_.contains(other.header)
      }) {
      continue
    }
    let mut layout : PollCacheLayout? = None
    let mut size = 0
    let mut barriers = false
    let mut reused = false
    let mut eligible = true
    let prefix : Set[Int32] = Set([])
    let suffix : Set[Int32] = Set([])
    let transparent : Set[Int32] = Set([])
    for id in loop_.blocks {
      let block = blocks[id]
      if block.terminator is None || block.terminator is Some(BrTable(_, _, _)) {
        eligible = false
      }
      for pred in cfg.get_predecessors(id) {
        if !loop_.contains(pred) &&
          (
            id != loop_.header ||
            blocks[pred].terminator is Some(BrTable(_, _, _))
          ) {
          eligible = false
        }
      }
      let mut before_barrier = true
      let mut after_poll = false
      for inst_id in function.block_instruction_ids(block) {
        let opcode = function.instruction_by_id(inst_id).unwrap().opcode
        size += 1
        match cached_poll_source(opcode) {
          Some(poll) => {
            if layout is Some(previous) && previous != poll {
              eligible = false
            }
            layout = Some(poll)
            if before_barrier {
              prefix.add(id)
            }
            reused = reused || after_poll
            after_poll = true
          }
          None =>
            if !poll_cache_transparent(opcode) {
              // Keep control-changing dialect instructions in the original path.
              if opcode is Ext(_, _) &&
                !(@wasm_milkir.decode_opcode(opcode) is Some(WasmCall(_))) {
                eligible = false
              }
              before_barrier = false
              after_poll = false
              barriers = true
            }
        }
      }
      if after_poll {
        suffix.add(id)
      } else if before_barrier && !prefix.contains(id) {
        transparent.add(id)
      }
    }
    if !eligible || !barriers || size > 80 || layout is None {
      continue
    }
    // A latch may only update the induction variable before jumping to the
    // next poll. Include these intervening blocks in the reuse check.
    let pending = suffix.iter().collect()
    let visited : Set[Int32] = Set([])
    while !reused && !pending.is_empty() {
      let id = pending.pop().unwrap()
      for next in cfg.get_successors(id) {
        if prefix.contains(next) {
          reused = true
        } else if transparent.contains(next) && !visited.contains(next) {
          visited.add(next)
          pending.push(next)
        }
      }
    }
    if reused {
      return Some((loop_, layout.unwrap()))
    }
  }
  None
}

///|
fn emit_cached_poll(
  function : @milkir.Function,
  block : @milkir.Block,
  operations : Map[Int32, CachedPoll],
  poll : CachedPoll,
  budget : @milkir.Value,
  results : Array[@milkir.Value],
) -> @milkir.Inst {
  let args = if poll is Step(_, true) { [] } else { [budget] }
  let inst = function.new_inst(
    Ext(
      poll.opcode(),
      Signature(args.map(value => value.ty), results.map(value => value.ty)),
    ),
    args,
    results,
  )
  operations[inst.id] = poll
  block.append_inst(inst)
  inst
}

///|
/// Independently check the carried value and every edge of the generated loop.
/// A barrier may only observe published state. A nonzero value reaching an
/// exit must go through a dedicated publish block.
fn verify_poll_cache_loop(
  function : @milkir.Function,
  loop_ : @milkir.Loop,
  seed : @milkir.Block,
  zero : @milkir.Value,
  blocks : Map[Int32, @milkir.Block],
  exits : Map[Int32, @milkir.Block],
  operations : Map[Int32, CachedPoll],
) -> Bool {
  let cfg = @milkir.CFG::build(function)
  guard seed.instruction_count() == 1 &&
    function.defining_inst(zero) is Some(seed_inst) &&
    function.block_instruction_ids(seed)[0] == seed_inst.id &&
    seed_inst.opcode is Scalar(IntConst(0L)) &&
    seed_inst.args.is_empty() &&
    seed_inst.results == [zero] else {
    return false
  }
  if cfg.get_predecessors(seed.id).any(id => loop_.contains(id)) {
    return false
  }
  for id in loop_.blocks {
    let block = blocks[id]
    if cfg
      .get_predecessors(id)
      .any(pred => {
        !loop_.contains(pred) && (id != loop_.header || pred != seed.id)
      }) {
      return false
    }
    let mut budget = block.params[block.params.length() - 1].0
    for inst_id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(inst_id).unwrap()
      let operation = operations.get(inst_id)
      if operation is Some(op) &&
        !(inst.opcode is Ext(extension, _) &&
        decode_cached_poll(extension) == Some(op)) {
        return false
      }
      match operation {
        Some(Step(_, fresh)) => {
          let args = if fresh { [] } else { [budget] }
          if fresh != (budget == zero) ||
            inst.args != args ||
            !(inst.results is [_]) {
            return false
          }
          budget = inst.results[0]
        }
        Some(Publish(_)) => {
          if inst.args != [budget] || !inst.results.is_empty() {
            return false
          }
          budget = zero
        }
        None =>
          if budget != zero && !poll_cache_transparent(inst.opcode) {
            return false
          }
      }
    }
    let valid = Ref(true)
    let term = block.terminator.unwrap()
    poll_cache_edges(term, fn(target, args) {
      if loop_.contains(target) || exits.contains(target) {
        if args.is_empty() || args[args.length() - 1] != budget {
          valid.val = false
        }
      } else if budget != zero {
        valid.val = false
      }
      (target, args)
    })
    |> ignore
    if !valid.val || (term.targets().is_empty() && budget != zero) {
      return false
    }
  }
  for id, block in exits {
    let budget = block.params[block.params.length() - 1].0
    if cfg.get_predecessors(id).any(pred => !loop_.contains(pred)) ||
      block.instruction_count() != 1 {
      return false
    }
    let inst = function
      .instruction_by_id(function.block_instruction_ids(block)[0])
      .unwrap()
    if !(operations.get(inst.id) is Some(Publish(layout)) &&
      inst.opcode is Ext(extension, _) &&
      decode_cached_poll(extension) == Some(Publish(layout))) ||
      inst.args != [budget] ||
      !inst.results.is_empty() ||
      !(block.terminator is Some(Jump(target, args)) &&
      !loop_.contains(target) &&
      !exits.contains(target) &&
      args == block.params[:block.params.length() - 1].map(p => p.0)) {
      return false
    }
  }
  match seed.terminator {
    Some(Jump(target, args)) =>
      target == loop_.header && args == seed.params.map(p => p.0) + [zero]
    _ => false
  }
}

///|
priv struct PollCacheEdit {
  operations : Map[Int32, CachedPoll]
  restore : () -> Unit
}

///|
priv struct PollCacheOriginalBlock {
  block : @milkir.Block
  instructions : Array[@milkir.Inst]
  terminator : @milkir.Terminator
  metadata : Array[@milkir.Metadata]
  parameter_count : Int32
}

///|
fn prepare_poll_cache(
  function : @milkir.Function,
) -> PollCacheEdit? raise @milkir.VerifyError {
  // Every cycle has an edge to an equal or lower block ID. Skip the
  // common forward-only CFG before building a separate loop analysis.
  if function.blocks.length() < 2 ||
    !function.blocks.any(block => {
      block.terminator is Some(term) && term.targets().any(id => id <= block.id)
    }) ||
    !function.blocks.any(block => {
      function
      .block_instruction_ids(block)
      .any(id => {
        cached_poll_source(function.instruction_by_id(id).unwrap().opcode)
        is Some(_)
      })
    }) {
    return None
  }
  let cfg = @milkir.CFG::build(function)
  let sources = function.blocks.copy()
  let blocks : Map[Int32, @milkir.Block] = Map([])
  for block in sources {
    blocks[block.id] = block
  }
  guard find_poll_cache_loop(function, cfg, blocks) is Some((loop_, layout)) else {
    return None
  }
  let operations : Map[Int32, CachedPoll] = Map([])
  let original : Array[PollCacheOriginalBlock] = []
  for block in sources {
    let term = block.terminator.unwrap()
    if loop_.contains(block.id) || term.targets().contains(loop_.header) {
      original.push({
        block,
        instructions: function
        .block_instruction_ids(block)
        .map(id => function.instruction_by_id(id).unwrap()),
        terminator: term,
        metadata: block.terminator_metadata(),
        parameter_count: block.params.length(),
      })
    }
  }
  let header = blocks[loop_.header]
  let seed = function.new_block0()
  // Unchanged polls must retain an arena placement while the temporary
  // CFG is checked. The unreachable block never enters target lowering.
  let replaced_polls = function.new_block0()
  replaced_polls.set_terminator(Trap("original polls during native lowering"))
  let seed_args = header.params.map(p => function.append_block_param(seed, p.1))
  // This edit is local to target selection. Leave the caller's prepared
  // function reusable even if the verifier or target sink rejects lowering.
  fn restore() -> Unit {
    for saved in original {
      if saved.block.params.length() != saved.parameter_count {
        function.retain_block_params(
          saved.block,
          Array::makei(saved.parameter_count, i => i),
        )
      }
      saved.block.set_instructions(saved.instructions)
      saved.block.set_terminator(saved.terminator, metadata=saved.metadata)
    }
    for id in operations.keys() {
      function.discard_inst(function.instruction_by_id(id).unwrap())
    }
    replaced_polls.clear_instructions_for_move()
    function.retain_blocks(block => block.id < seed.id)
  }
  errdefer restore()
  let zero = function.new_value(I32)
  seed.append_inst(function.new_inst(Scalar(IntConst(0L)), [], [zero]))
  seed.set_terminator(Jump(header.id, seed_args + [zero]))
  let budgets : Map[Int32, @milkir.Value] = Map([])
  for id in loop_.blocks {
    budgets[id] = function.append_block_param(blocks[id], I32)
  }
  let exits : Map[Int32, @milkir.Block] = Map([])
  let exit_for_target : Map[Int32, @milkir.Block] = Map([])
  for block in sources {
    let term = block.terminator.unwrap()
    let metadata = block.terminator_metadata()
    if !loop_.contains(block.id) {
      if term.targets().contains(header.id) {
        block.set_terminator(
          poll_cache_edges(term, fn(target, args) {
            (if target == header.id { seed.id } else { target }, args)
          }),
          metadata~,
        )
      }
      continue
    }
    let mut budget = budgets[block.id]
    let instructions = function.block_instruction_ids(block).to_owned()
    block.clear_instructions_for_move()
    for id in instructions {
      let inst = function.instruction_by_id(id).unwrap()
      if cached_poll_source(inst.opcode) is Some(_) {
        let next = function.new_value(I32)
        let step = emit_cached_poll(
          function,
          block,
          operations,
          Step(layout, budget == zero),
          budget,
          [next],
        )
        for item in inst.metadata {
          step.add_metadata(item)
        }
        replaced_polls.append_inst(inst)
        budget = next
      } else {
        if budget != zero && !poll_cache_transparent(inst.opcode) {
          emit_cached_poll(
            function,
            block,
            operations,
            Publish(layout),
            budget,
            [],
          )
          |> ignore
          budget = zero
        }
        block.append_inst(inst)
      }
    }
    if term.targets().is_empty() && budget != zero {
      emit_cached_poll(function, block, operations, Publish(layout), budget, [])
      |> ignore
      budget = zero
    }
    let current = budget
    block.set_terminator(
      poll_cache_edges(term, fn(target, args) {
        if loop_.contains(target) {
          (target, args + [current])
        } else if current == zero {
          (target, args)
        } else {
          let exit = match exit_for_target.get(target) {
            Some(exit) => exit
            None => {
              let exit = function.new_block0()
              let forwarded = blocks[target].params.map(p => {
                function.append_block_param(exit, p.1)
              })
              let remaining = function.append_block_param(exit, I32)
              emit_cached_poll(
                function,
                exit,
                operations,
                Publish(layout),
                remaining,
                [],
              )
              |> ignore
              exit.set_terminator(Jump(target, forwarded))
              exit_for_target[target] = exit
              exits[exit.id] = exit
              exit
            }
          }
          (exit.id, args + [current])
        }
      }),
      metadata~,
    )
  }
  if !verify_poll_cache_loop(
      function, loop_, seed, zero, blocks, exits, operations,
    ) {
    raise @milkir.VerifyError::unverifiable_instruction(
      "invalid cached poll budget flow",
    )
  }
  Some({ operations, restore, })
}
