///|
fn leaf_cost(function : @milkir.Function) -> (Int32, Bool)? {
  if function.blocks.length() != 1 ||
    function.params.is_empty() ||
    function.results.length() != 1 {
    return None
  }
  let block = function.blocks[0]
  if !block.params.is_empty() || !(block.terminator is Some(Return([_]))) {
    return None
  }
  let environment = function.params[0].0
  let mut cost = 0
  let mut loads = 0
  let mut references_heap = false
  for id in function.block_instruction_ids(block) {
    let inst = function.instruction_by_id(id).unwrap()
    cost += match inst.opcode {
      Scalar(IntBinary(SignedDiv | UnsignedDiv | SignedRem | UnsignedRem)) => 12
      Scalar(_) => 1
      Vector(_) => 4
      Memory(Load(_) | LoadNarrow(_, _, _)) => {
        loads += 1
        3
      }
      GlobalValue(global) if function.global_value_data(global)
        is Some(ContextField(_, _, Heap(_))) => {
        references_heap = true
        1
      }
      Ext(_, _) =>
        match @wasm_milkir.decode_opcode(inst.opcode) {
          // The late expansion has seven side/continuation blocks. Charge it
          // against both the leaf and per-caller budgets despite its compact IR.
          Some(SafepointPoll(_, _, _, _)) => 8
          Some(
            StructNew(_)
            | StructGet(_, _)
            | StructGetS(_, _, _)
            | StructGetU(_, _, _)
            | ArrayGet(_)
            | ArrayGetS(_, _)
            | ArrayGetU(_, _)
            | ArrayLen
          ) => 2
          _ => return None
        }
      _ => return None
    }
    let poll = inst.results.is_empty() &&
      @wasm_milkir.decode_opcode(inst.opcode) is Some(SafepointPoll(_, _, _, _))
    if (!(inst.results is [_]) && !poll) ||
      (
        !(inst.opcode is GlobalValue(_)) &&
        inst.args.any(value => value == environment)
      ) {
      return None
    }
    if cost > 24 {
      return None
    }
  }
  if block.terminator is Some(Return([result])) && result == environment {
    return None
  }
  let reads_memory = loads != 0
  if (references_heap || reads_memory) &&
    (
      !references_heap ||
      loads != 1 ||
      function.params.length() != 2 ||
      function.params[1].1 != I32 ||
      block.instruction_count() > 12
    ) {
    return None
  }
  Some((cost.max(1), reads_memory))
}

///|
fn inline_leaf_calls(
  function : @milkir.Function,
  callees : Map[Int32, @milkir.Function],
  context : @wasm_milkir.WasmValidationContext,
) -> Bool raise @milkir.VerifyError {
  let templates : Map[Int32, (@milkir.Function, Int32, Bool)] = Map([])
  let mut has_memory_leaf = false
  // Inspect only callees used by this function, rather than scanning every
  // module template once per caller. Validate them before mutating the caller.
  let seen : Map[Int32, Bool] = Map([])
  for block in function.blocks {
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      if @wasm_milkir.decode_opcode(inst.opcode) is Some(WasmCall(index)) &&
        !seen.contains(index) {
        seen[index] = true
        if callees.get(index) is Some(callee) {
          callee.verify()
          if leaf_cost(callee) is Some((cost, reads_memory)) &&
            (
              !reads_memory ||
              (
                !function.params.is_empty() &&
                function.params[0].1 == I64 &&
                context.admits_function_body(index, callee)
              )
            ) {
            @wasm_milkir.verify_function_with_context(callee, context)
            templates[index] = (callee, cost, reads_memory)
            has_memory_leaf = has_memory_leaf || reads_memory
          }
        }
      }
    }
  }
  if templates.is_empty() {
    return false
  }
  // A checked memory operation keeps its original order and fault behavior.
  // Charge the extra instructions only at call sites inside natural loops.
  let loops = if has_memory_leaf {
    @milkir.CFG::build(function).find_loops()
  } else {
    []
  }
  let mut expanded = 0
  let mut inlined_load = false
  for block in function.blocks {
    let in_loop = loops.any(loop_ => {
      loop_.blocks.length() <= 8 && loop_.contains(block.id)
    })
    let instructions : Array[@milkir.Inst] = []
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      if expanded < 256 &&
        @wasm_milkir.decode_opcode(inst.opcode) is Some(WasmCall(index)) &&
        templates.get(index) is Some((callee, cost, reads_memory)) &&
        (!reads_memory || (in_loop && !inlined_load)) &&
        expanded + cost <= 256 &&
        inst.results is [result] &&
        result.ty == callee.results[0] &&
        inst.args.length() + 1 == callee.params.length() {
        let values : Map[Int32, @milkir.Value] = Map([])
        if reads_memory {
          values[callee.params[0].0.id] = function.params[0].0
        }
        let mut matches = true
        for i, argument in inst.args {
          let (parameter, ty) = callee.params[i + 1]
          if argument.ty != ty {
            matches = false
          }
          values[parameter.id] = argument
        }
        if matches {
          let body = callee.blocks[0]
          for callee_id in callee.block_instruction_ids(body) {
            let original = callee.instruction_by_id(callee_id).unwrap()
            let results = if original.results is [result] {
              [function.new_value(result.ty)]
            } else {
              []
            }
            let opcode : @milkir.Opcode = match original.opcode {
              GlobalValue(global) =>
                GlobalValue(
                  function.declare_global_value(
                    callee.global_value_data(global).unwrap(),
                  ),
                )
              _ => original.opcode
            }
            let cloned = function.new_inst(
              opcode,
              original.args.map(argument => values[argument.id]),
              results,
            )
            for metadata in inst.metadata {
              if metadata is (SourceLoc(_) | SourceByteOffset(_)) {
                cloned.add_metadata(metadata)
              }
            }
            instructions.push(cloned)
            if original.results is [result] {
              values[result.id] = results[0]
            }
          }
          if body.terminator is Some(Return([returned])) {
            inst.args.clear()
            inst.args.push(values[returned.id])
            inst.set_opcode(Scalar(Copy))
            expanded += cost
            inlined_load = inlined_load || reads_memory
          }
        }
      }
      instructions.push(inst)
    }
    block.set_instructions(instructions)
  }
  if inlined_load {
    @wasm_milkir.verify_function_with_context(function, context)
  }
  expanded > 0
}
