///|
fn leaf_cost(function : @milkir.Function) -> Int32? {
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
  for id in function.block_instruction_ids(block) {
    let inst = function.instruction_by_id(id).unwrap()
    cost += match inst.opcode {
      Scalar(IntBinary(SignedDiv | UnsignedDiv | SignedRem | UnsignedRem)) => 12
      Scalar(_) => 1
      Vector(_) => 4
      Ext(_, _) =>
        match @wasm_milkir.decode_opcode(inst.opcode) {
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
    if !(inst.results is [_]) || inst.args.any(value => value == environment) {
      return None
    }
    if cost > 24 {
      return None
    }
  }
  if block.terminator is Some(Return([result])) && result == environment {
    return None
  }
  Some(cost.max(1))
}

///|
fn inline_leaf_calls(
  function : @milkir.Function,
  callees : Map[Int32, @milkir.Function],
  context : @wasm_milkir.WasmValidationContext,
) -> Bool raise @milkir.VerifyError {
  let templates : Map[Int32, @milkir.Function] = Map([])
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
          if leaf_cost(callee) is Some(_) {
            @wasm_milkir.verify_function_with_context(callee, context)
            templates[index] = callee
          }
        }
      }
    }
  }
  if templates.is_empty() {
    return false
  }
  let mut expanded = 0
  for block in function.blocks {
    let instructions : Array[@milkir.Inst] = []
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      if expanded < 256 &&
        @wasm_milkir.decode_opcode(inst.opcode) is Some(WasmCall(index)) &&
        templates.get(index) is Some(callee) &&
        leaf_cost(callee) is Some(cost) &&
        expanded + cost <= 256 &&
        inst.results is [result] &&
        result.ty == callee.results[0] &&
        inst.args.length() + 1 == callee.params.length() {
        let values : Map[Int32, @milkir.Value] = Map([])
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
            let value = function.new_value(original.results[0].ty)
            let cloned = function.new_inst(
              original.opcode,
              original.args.map(argument => values[argument.id]),
              [value],
            )
            for metadata in inst.metadata {
              if metadata is (SourceLoc(_) | SourceByteOffset(_)) {
                cloned.add_metadata(metadata)
              }
            }
            instructions.push(cloned)
            values[original.results[0].id] = value
          }
          if body.terminator is Some(Return([returned])) {
            inst.args.clear()
            inst.args.push(values[returned.id])
            inst.set_opcode(Scalar(Copy))
            expanded += cost
          }
        }
      }
      instructions.push(inst)
    }
    block.set_instructions(instructions)
  }
  expanded > 0
}
