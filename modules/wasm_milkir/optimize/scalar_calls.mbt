///|
fn scalar_template(function : @milkir.Function) -> Bool {
  if function.blocks.length() != 1 ||
    function.params.is_empty() ||
    function.results.length() != 1 ||
    !(function.results[0] is (I32 | I64)) {
    return false
  }
  let block = function.blocks[0]
  if !block.params.is_empty() ||
    block.instruction_count() > 8 ||
    !(block.terminator is Some(Return([_]))) {
    return false
  }
  for (_, ty) in function.params[1:] {
    if !(ty is (I32 | I64)) {
      return false
    }
  }
  let environment = function.params[0].0
  for id in function.block_instruction_ids(block) {
    let inst = function.instruction_by_id(id).unwrap()
    // Integer-only scalar operations neither allocate nor call the host.
    // Polls, memory, globals, references and dialect extensions are excluded.
    if !(inst.opcode is Scalar(_)) || !(inst.results is [_]) {
      return false
    }
    for value in inst.args + inst.results {
      if !(value.ty is (I32 | I64)) || value == environment {
        return false
      }
    }
  }
  if block.terminator is Some(Return([result])) && result == environment {
    return false
  }
  true
}

///|
fn inline_scalar_calls(
  function : @milkir.Function,
  callees : Map[Int32, @milkir.Function],
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
          if scalar_template(callee) {
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
              if metadata is SourceLoc(_) {
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
            expanded += 1
          }
        }
      }
      instructions.push(inst)
    }
    block.set_instructions(instructions)
  }
  expanded > 0
}
