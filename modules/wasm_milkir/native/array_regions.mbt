///|
fn array_view_origins(
  function : @milkir.Function,
  plan : Map[Int32, ArrayAccess],
) -> Map[Int32, (Int32, Int32)]? {
  let origins : Map[Int32, (Int32, Int32)] = Map([])
  for _, access in plan {
    guard function.instruction_by_id(access.first) is Some(first) &&
      array_view_reference(first) is Some(reference) else {
      return None
    }
    let identity = (reference.id, access.width)
    if origins.get(access.first) is Some(other) && other != identity {
      return None
    }
    origins[access.first] = identity
  }
  Some(origins)
}

///|
fn array_view_reference(inst : @milkir.Inst) -> @milkir.Value? {
  if @wasm_milkir.decode_opcode(inst.opcode) is Some(StructGet(_, _)) &&
    inst.results is [value] &&
    value.ty is Ref {
    Some(value)
  } else {
    inst.args.get(0)
  }
}

///|
/// A successful array operation or newly produced reference supplies a view.
/// Projection is total and nontrapping, including a nullable struct field, so
/// preparation cannot add a trap to an untaken/zero-trip loop.
fn array_view_origin_matches(
  inst : @milkir.Inst,
  context : @wasm_milkir.WasmValidationContext,
  reference : Int32,
  width : Int32,
) -> Bool {
  if array_view_reference(inst).map(v => v.id) != Some(reference) {
    return false
  }
  (
    @wasm_milkir.decode_opcode(inst.opcode) is Some(StructGet(_, _)) &&
    inst.results is [value] &&
    value.ty is Ref
  ) ||
  @wasm_milkir.decode_opcode(inst.opcode) is Some(ArrayLen) ||
  scalar_array_access(inst, context).map(v => v.0) == Some(width)
}

///|
fn plan_loop_array_accesses(
  function : @milkir.Function,
  context : @wasm_milkir.WasmValidationContext,
  cfg : @milkir.CFG,
  plan : Map[Int32, ArrayAccess],
) -> Unit {
  let blocks : Map[Int32, @milkir.Block] = Map([])
  let order : Map[Int32, Int32] = Map([])
  for rank, block in function.blocks {
    blocks[block.id] = block
    order[block.id] = rank
  }
  let mut work = 0
  for loop_ in cfg.find_loops() {
    guard cfg.get_loop_preheader(loop_) is Some(preheader) &&
      loop_.blocks.all(id => order[id] > order[preheader]) else {
      continue
    }
    let instructions : Array[Int32] = []
    for id in loop_.blocks {
      for inst in function.block_instruction_ids(blocks[id]) {
        instructions.push(inst)
      }
    }
    work += instructions.length()
    if work > 100000 {
      return
    }
    if !instructions.all(id => {
        array_region_local(function.instruction_by_id(id).unwrap())
      }) {
      continue
    }
    let prefix = function.block_instruction_ids(blocks[preheader])
    for id in instructions {
      let inst = function.instruction_by_id(id).unwrap()
      guard scalar_array_access(inst, context) is Some((width, opcode)) else {
        continue
      }
      for reverse in 0..<prefix.length() {
        work += 1
        if work > 100000 {
          return
        }
        let first = function
          .instruction_by_id(prefix[prefix.length() - 1 - reverse])
          .unwrap()
        if !array_region_local(first) {
          break
        }
        if array_view_origin_matches(first, context, inst.args[0].id, width) {
          plan[id] = {
            first: first.id,
            width,
            opcode,
            loop_header: Some(loop_.header),
          }
          break
        }
      }
    }
  }
}

///|
/// Recheck a loop borrow independently of the planner. The preheader's
/// array check or reference producer dominates every use. No route around the loop
/// may collect, reenter or rebind the heap. Array writes cannot resize it.
fn verify_loop_array_access(
  function : @milkir.Function,
  context : @wasm_milkir.WasmValidationContext,
  cfg : @milkir.CFG,
  loop_ : @milkir.Loop,
  first : Int32,
  reference : Int32,
  width : Int32,
  work : Ref[Int32],
) -> Bool {
  guard cfg.get_loop_preheader(loop_) is Some(preheader) else { return false }
  let order : Map[Int32, Int32] = Map([])
  let blocks : Map[Int32, @milkir.Block] = Map([])
  for rank, block in function.blocks {
    order[block.id] = rank
    blocks[block.id] = block
  }
  if !loop_.blocks.all(id => order[id] > order[preheader]) {
    return false
  }
  for id in loop_.blocks {
    // Reject irreducible side entries, including exception/control edges.
    if cfg
      .get_predecessors(id)
      .any(pred => {
        !loop_.contains(pred) && (id != loop_.header || pred != preheader)
      }) {
      return false
    }
    work.val += function.block_instruction_ids(blocks[id]).length()
    if work.val > 100000 {
      return false
    }
    if !function
      .block_instruction_ids(blocks[id])
      .all(id => array_region_local(function.instruction_by_id(id).unwrap())) {
      return false
    }
  }
  let mut checked = false
  for id in function.block_instruction_ids(blocks[preheader]) {
    work.val += 1
    if work.val > 100000 {
      return false
    }
    let inst = function.instruction_by_id(id).unwrap()
    if !array_region_local(inst) {
      checked = false
    }
    if id == first {
      checked = array_view_origin_matches(inst, context, reference, width)
    }
  }
  checked
}

///|
/// Every physical use needs a checked origin and a no-safepoint path. Ordinary
/// regions follow forward single-predecessor edges. A loop additionally needs
/// a dominating preheader origin and a proof for its entire cycle.
/// Verification is mandatory even when callers disable generic IR validation.
fn verify_array_accesses(
  function : @milkir.Function,
  context : @wasm_milkir.WasmValidationContext,
  plan : Map[Int32, ArrayAccess],
) -> Bool {
  guard array_view_origins(function, plan) is Some(origins) else {
    return false
  }
  let cfg = @milkir.CFG::build(function)
  let loops : Map[Int32, @milkir.Loop] = Map([])
  for loop_ in cfg.find_loops() {
    loops[loop_.header] = loop_
  }
  let loop_proofs : Map[(Int32, Int32, Int32, Int32), Bool] = Map([])
  let work = Ref(0)
  let outgoing : Map[Int32, Map[Int32, (Int32, Int32)]] = Map([])
  let mut seen = 0
  for block in function.blocks {
    let live : Map[Int32, (Int32, Int32)] = Map([])
    if cfg.get_predecessors(block.id) is [previous] &&
      outgoing.get(previous) is Some(inherited) {
      for key, value in inherited {
        live[key] = value
      }
    }
    for id in function.block_instruction_ids(block) {
      let inst = function.instruction_by_id(id).unwrap()
      if !array_region_local(inst) {
        live.clear()
      }
      if origins.get(id) is Some((reference, width)) {
        if !array_view_origin_matches(inst, context, reference, width) ||
          live.length() >= 256 {
          return false
        }
        live[id] = (reference, width)
      }
      if plan.get(id) is Some(access) {
        guard scalar_array_access(inst, context) is Some((width, opcode)) &&
          width == access.width &&
          opcode == access.opcode else {
          return false
        }
        let identity = (inst.args[0].id, width)
        if access.loop_header is Some(header) {
          guard loops.get(header) is Some(loop_) && loop_.contains(block.id) else {
            return false
          }
          let key = (header, access.first, identity.0, width)
          let proof = loop_proofs.get_or_init(key, fn() {
            verify_loop_array_access(
              function,
              context,
              cfg,
              loop_,
              access.first,
              identity.0,
              width,
              work,
            )
          })
          if !proof || origins.get(access.first) != Some(identity) {
            return false
          }
        } else if live.get(access.first) != Some(identity) {
          return false
        }
        seen += 1
      }
    }
    outgoing[block.id] = live
  }
  seen == plan.length()
}
