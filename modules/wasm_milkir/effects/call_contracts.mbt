///|
priv struct ReadOnlyBody {
  polls : Int32
  layout : (Int32, Int32, Int32, Int32)?
  calls : Array[Int32]
}

///|
/// Summarize the existing bounded templates once per module. A Kahn worklist
/// excludes recursive cycles and propagates unknown callees without an
/// optimistic fixed point. Repeated call edges remain repeated poll costs.
pub fn read_only_call_contracts(
  callees : Map[Int32, @milkir.Function],
  context : @wasm_milkir.WasmValidationContext,
) -> Map[Int32, @wasm_milkir.WasmReadOnlyCallContract] {
  let bodies : Map[Int32, ReadOnlyBody] = Map([])
  let users : Map[Int32, Array[Int32]] = Map([])
  let degrees : Map[Int32, Int32] = Map([])
  let ready : Array[Int32] = []
  for index, function in callees {
    if !context.admits_function_body(index, function) ||
      function.blocks.length() != 1 ||
      !function.blocks[0].params.is_empty() ||
      !(function.blocks[0].terminator is Some(Return(_))) {
      continue
    }
    let valid = try {
      @wasm_milkir.verify_function_with_context(function, context)
      true
    } catch {
      _ => false
    }
    if !valid {
      continue
    }
    let calls : Array[Int32] = []
    let mut polls = 0
    let mut layout : (Int32, Int32, Int32, Int32)? = None
    let mut eligible = true
    for id in function.block_instruction_ids(function.blocks[0]) {
      let inst = function.instruction_by_id(id).unwrap()
      match @wasm_milkir.decode_opcode(inst.opcode) {
        Some(SafepointPoll(a, b, c, d)) => {
          let offsets = (a, b, c, d)
          if layout is Some(previous) && previous != offsets {
            eligible = false
          }
          layout = Some(offsets)
          polls = (polls + 1).min(257)
        }
        Some(WasmCall(callee)) => calls.push(callee)
        _ => {
          let effects = analyze(inst.opcode)
          if !effects.preserves_physical_addresses() || effects.write is Some(_) {
            eligible = false
          }
        }
      }
    }
    if !eligible || polls > 256 {
      continue
    }
    bodies[index] = { polls, layout, calls, }
    degrees[index] = calls.length()
    if calls.is_empty() {
      ready.push(index)
    }
    for callee in calls {
      if users.get(callee) is None {
        users[callee] = []
      }
      users[callee].push(index)
    }
  }
  let contracts : Map[Int32, @wasm_milkir.WasmReadOnlyCallContract] = Map([])
  let mut cursor = 0
  while cursor < ready.length() {
    let index = ready[cursor]
    cursor += 1
    let body = bodies[index]
    let mut polls = body.polls
    let mut layout = body.layout
    let mut eligible = true
    for callee in body.calls {
      guard contracts.get(callee) is Some(contract) else {
        eligible = false
        continue
      }
      polls = (polls + contract.polls).min(257)
      if contract.layout is Some(offsets) {
        if layout is Some(previous) && previous != offsets {
          eligible = false
        }
        layout = Some(offsets)
      }
    }
    if eligible && polls <= 256 {
      contracts[index] = { polls, layout, }
    }
    for user in users.get(index).unwrap_or([]) {
      degrees[user] = degrees[user] - 1
      if degrees[user] == 0 {
        ready.push(user)
      }
    }
  }
  contracts
}
