///|
/// Admit only small acyclic numeric functions whose control or memory reads
/// exclude them from the scalar inliner. Their polls, checked loads and traps
/// remain in the original order and control flow.
fn checked_leaf_cost(function : @milkir.Function) -> Int32 {
  guard function.results.is_empty() &&
    function.blocks.length() >= 2 &&
    function.blocks.length() <= 8 &&
    function.blocks[0].params.is_empty() &&
    function.params.length() >= 2 &&
    function.params.all(p => p.1 is (I32 | I64)) else {
    return -1
  }
  let cfg = @milkir.CFG::build(function)
  let order = cfg.reverse_postorder()
  if order.length() != function.blocks.length() {
    return -1
  }
  let positions : Map[Int32, Int32] = Map([])
  for i, id in order {
    positions[id] = i
  }
  let mut checked = false
  let mut cost = 0
  for block in function.blocks {
    if cfg
      .get_successors(block.id)
      .any(next => positions[next] <= positions[block.id]) {
      return -1
    }
    match block.terminator {
      Some(Trap(_)) => checked = true
      Some(
        Jump(_, _)
        | Branch(_, _, _, _, _)
        | Brz(_, _, _)
        | Brnz(_, _, _)
        | Return(_)
      ) => ()
      _ => return -1
    }
    cost += 1
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      cost += match inst.opcode {
        Scalar(IntBinary(SignedDiv | UnsignedDiv | SignedRem | UnsignedRem)) =>
          return -1
        Scalar(_) => 1
        Ext(_, _) if @wasm_milkir.decode_opcode(inst.opcode)
          is Some(SafepointPoll(_, _, _, _)) => 8
        _ => return -1
      }
    }
    if cost > 32 {
      return -1
    }
  }
  if checked {
    cost
  } else {
    -1
  }
}

///|
fn clone_checked_leaf_call(
  function : @milkir.Function,
  caller : @milkir.Block,
  call : @milkir.Inst,
  callee : @milkir.Function,
) -> @milkir.Block {
  let continuation = function.new_block0()
  let copies : Map[Int32, @milkir.Block] = Map([])
  let values : Map[Int32, @milkir.Value] = Map([])
  values[callee.params[0].0.id] = function.params[0].0
  for i, arg in call.args {
    values[callee.params[i + 1].0.id] = arg
  }
  for block in callee.blocks {
    let copy = function.new_block0()
    copies[block.id] = copy
    for param in block.params {
      values[param.0.id] = function.append_block_param(copy, param.1)
    }
    for id in callee.block_instruction_ids(block) {
      for result in callee.instruction_by_id(id).unwrap().results {
        values[result.id] = function.new_value(result.ty)
      }
    }
  }
  fn value(v : @milkir.Value) -> @milkir.Value {
    values[v.id]
  }
  fn target(block : Int32) -> Int32 {
    copies[block].id
  }
  for block in callee.blocks {
    let copy = copies[block.id]
    for id in callee.block_instruction_ids(block) {
      let inst = callee.instruction_by_id(id).unwrap()
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
    let term : @milkir.Terminator = match block.terminator.unwrap() {
      Jump(next, args) => Jump(target(next), args.map(value))
      Branch(cond, yes, yes_args, no, no_args) =>
        Branch(
          value(cond),
          target(yes),
          yes_args.map(value),
          target(no),
          no_args.map(value),
        )
      Brz(cond, yes, no) => Brz(value(cond), target(yes), target(no))
      Brnz(cond, yes, no) => Brnz(value(cond), target(yes), target(no))
      Trap(reason) => Trap(reason)
      Return(_) => Jump(continuation.id, [])
      _ => abort("checked leaf contains an unadmitted terminator")
    }
    copy.set_terminator(term, metadata=block.terminator_metadata())
  }
  caller.set_terminator(
    Jump(copies[callee.blocks[0].id].id, []),
    metadata=call.metadata.copy(),
  )
  continuation
}

///|
fn inline_checked_leaf_calls(
  function : @milkir.Function,
  templates : Map[Int32, @milkir.Function],
  context : @wasm_milkir.WasmValidationContext,
) -> Bool raise @milkir.VerifyError {
  if function.params.is_empty() || function.params[0].1 != I64 {
    return false
  }
  if templates.is_empty() ||
    !function.blocks.any(block => {
      function
      .block_instruction_ids(block)
      .any(id => {
        match
          @wasm_milkir.decode_opcode(
            function.instruction_by_id(id).unwrap().opcode,
          ) {
          Some(WasmCall(index)) =>
            templates.get(index) is Some(callee) && callee.results.is_empty()
          _ => false
        }
      })
    }) {
    return false
  }
  let loops = @milkir.CFG::build(function).find_loops()
  if loops.is_empty() {
    return false
  }
  let costs : Map[Int32, Int32] = Map([])
  let mut budget = 24
  let blocks = function.blocks.copy()
  for block in blocks {
    if budget <= 0 {
      break
    }
    if !loops.any(loop_ => {
        loop_.blocks.length() <= 8 && loop_.contains(block.id)
      }) {
      continue
    }
    let ids = function.block_instruction_ids(block).to_owned()
    let mut cursor = 0
    let mut current = block
    for i, id in ids {
      let call = function.instruction_by_id(id).unwrap()
      guard @wasm_milkir.decode_opcode(call.opcode) is Some(WasmCall(index)) &&
        templates.get(index) is Some(callee) &&
        call.args is [_, lower, _] &&
        function.defining_inst(lower) is Some(lower_inst) &&
        lower_inst.opcode is Scalar(IntConst(_)) else {
        continue
      }
      if !costs.contains(index) {
        let cost = checked_leaf_cost(callee)
        if cost >= 0 && context.admits_function_body(index, callee) {
          @wasm_milkir.verify_function_with_context(callee, context)
          costs[index] = cost
        } else {
          costs[index] = -1
        }
      }
      let cost = costs[index]
      if cost < 0 || cost > budget {
        continue
      }
      let term = current.terminator.unwrap()
      let metadata = current.terminator_metadata()
      let prefix = ids[cursor:i]
        .to_owned()
        .map(id => function.instruction_by_id(id).unwrap())
      let suffix = ids[i + 1:]
        .to_owned()
        .map(id => function.instruction_by_id(id).unwrap())
      current.set_instructions(prefix)
      current = clone_checked_leaf_call(function, current, call, callee)
      function.discard_inst(call)
      current.set_instructions(suffix)
      current.set_terminator(term, metadata~)
      cursor = i + 1
      budget -= cost
    }
  }
  budget < 24
}
