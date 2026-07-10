///|
const MAX_FULL_UNROLL_TRIP_COUNT : Int = 8

///|
const MAX_FULL_UNROLL_CLONED_INSTRUCTIONS : Int = 64

///|
const I32_SIGNED_MIN : Int64 = -2147483648L

///|
const I32_SIGNED_MAX : Int64 = 2147483647L

///|
priv struct FullUnrollPlan {
  preheader : Block
  header : Block
  induction : Value
  initial : Value
  iteration_blocks : Array[Block]
  latch_args : Array[Value]
  trip_count : Int
}

///|
priv enum FullUnrollDecision {
  Apply(FullUnrollPlan)
  Skip(String)
}

///|
fn find_unroll_block(func : Function, block_id : Int) -> Block? {
  for block in func.blocks {
    if block.id == block_id {
      return Some(block)
    }
  }
  None
}

///|
fn find_i32_constant_outside_loop(
  func : Function,
  loop_ : Loop,
  value : Value,
) -> Int64? {
  if value.ty != I32 {
    return None
  }
  for block in func.blocks {
    if loop_.contains(block.id) {
      continue
    }
    for inst in block.instructions {
      if inst.opcode is Iconst(constant) {
        for result in inst.results {
          if result.id == value.id && result.ty == I32 {
            return Some(constant)
          }
        }
      }
    }
  }
  None
}

///|
fn find_iteration_definition(
  iteration_blocks : Array[Block],
  value_id : Int,
) -> Inst? {
  for block in iteration_blocks {
    for inst in block.instructions {
      for result in inst.results {
        if result.id == value_id {
          return Some(inst)
        }
      }
    }
  }
  None
}

///|
fn is_defined_in_unroll_loop(
  func : Function,
  loop_ : Loop,
  value_id : Int,
) -> Bool {
  for block in func.blocks {
    if !loop_.contains(block.id) {
      continue
    }
    for item in block.params {
      let (param, _) = item
      if param.id == value_id {
        return true
      }
    }
    for inst in block.instructions {
      for result in inst.results {
        if result.id == value_id {
          return true
        }
      }
    }
  }
  false
}

///|
fn is_full_unroll_pure_i32(inst : Inst) -> Bool {
  for arg in inst.args {
    if arg.ty != I32 {
      return false
    }
  }
  for result in inst.results {
    if result.ty != I32 {
      return false
    }
  }
  match inst.opcode {
    Iconst(_)
    | Iadd
    | Isub
    | Imul
    | Umulh
    | Smulh
    | Band
    | Bor
    | Bxor
    | Bnot
    | Ishl
    | Sshr
    | Ushr
    | Rotl
    | Rotr
    | Clz
    | Ctz
    | Popcnt
    | Icmp(_)
    | IcmpEq
    | Select
    | Copy => true
    _ => false
  }
}

///|
fn checked_i32_full_unroll_trip_count(
  initial : Int64,
  bound : Int64,
  step : Int64,
) -> Int? {
  if initial < I32_SIGNED_MIN ||
    initial > I32_SIGNED_MAX ||
    bound < I32_SIGNED_MIN ||
    bound > I32_SIGNED_MAX ||
    step <= 0L ||
    step > I32_SIGNED_MAX {
    return None
  }
  if initial >= bound {
    return Some(0)
  }
  let distance = bound - initial
  let trips = (distance + step - 1L) / step
  if trips > MAX_FULL_UNROLL_TRIP_COUNT.to_int64() {
    return None
  }
  let final_value = initial + trips * step
  if final_value > I32_SIGNED_MAX {
    return None
  }
  Some(trips.to_int())
}

///|
fn analyze_i32_full_unroll(
  func : Function,
  cfg : CFG,
  loop_ : Loop,
) -> FullUnrollDecision {
  if loop_.back_edges.length() != 1 {
    return Skip("loop must have one back edge")
  }
  let header = match find_unroll_block(func, loop_.header) {
    Some(block) => block
    None => return Skip("missing loop header")
  }
  if header.params.length() != 1 {
    return Skip("loop must have only the induction block parameter")
  }
  let (induction, induction_type) = header.params[0]
  if induction.ty != I32 || induction_type != I32 {
    return Skip("induction variable must be i32")
  }
  let preheader_id = match cfg.get_loop_preheader(loop_) {
    Some(block_id) => block_id
    None => return Skip("loop must have one preheader")
  }
  let preheader = match find_unroll_block(func, preheader_id) {
    Some(block) => block
    None => return Skip("missing loop preheader")
  }
  let initial = match preheader.terminator {
    Some(Jump(target, args)) =>
      if target == header.id && args.length() == 1 {
        args[0]
      } else {
        return Skip("preheader must pass only the induction value")
      }
    _ => return Skip("preheader must jump to the loop header")
  }
  let (condition, body_id, exit_id) = match header.terminator {
    Some(Brnz(cond, body, exit)) => (cond, body, exit)
    _ => return Skip("header must use brnz for the canonical loop test")
  }
  if !loop_.contains(body_id) || loop_.contains(exit_id) {
    return Skip("header must have one loop edge and one exit edge")
  }
  let exit = match find_unroll_block(func, exit_id) {
    Some(block) => block
    None => return Skip("missing loop exit")
  }
  if !exit.params.is_empty() {
    return Skip("initial slice does not support exit parameters")
  }
  if header.instructions.length() != 1 {
    return Skip("header must contain only the induction comparison")
  }
  let comparison = header.instructions[0]
  if comparison.results.length() != 1 ||
    comparison.results[0].id != condition.id ||
    comparison.results[0].ty != I32 ||
    comparison.operands.length() != 2 ||
    comparison.opcode != Icmp(Slt) ||
    comparison.operands[0].id != induction.id ||
    comparison.operands[0].ty != I32 ||
    comparison.operands[1].ty != I32 {
    return Skip("comparison must be icmp_slt(induction, bound)")
  }
  let body = match find_unroll_block(func, body_id) {
    Some(block) => block
    None => return Skip("missing loop body")
  }
  let (latch_id, _) = loop_.back_edges[0]
  let latch = match find_unroll_block(func, latch_id) {
    Some(block) => block
    None => return Skip("missing loop latch")
  }
  let iteration_blocks : Array[Block] = []
  if body.id == latch.id {
    if loop_.blocks.length() != 2 {
      return Skip("loop body contains unsupported blocks")
    }
    iteration_blocks.push(body)
  } else {
    if loop_.blocks.length() != 3 {
      return Skip("loop body contains unsupported blocks")
    }
    match body.terminator {
      Some(Jump(target, args)) =>
        if target != latch.id || !args.is_empty() {
          return Skip("body must jump directly to the latch")
        }
      _ => return Skip("body must have one path to the latch")
    }
    iteration_blocks.push(body)
    iteration_blocks.push(latch)
  }
  for block_id in loop_.blocks {
    if block_id != header.id && block_id != body.id && block_id != latch.id {
      return Skip("loop body contains unsupported blocks")
    }
  }
  for block in iteration_blocks {
    if !block.params.is_empty() {
      return Skip("initial slice does not support body parameters")
    }
    for inst in block.instructions {
      if !is_full_unroll_pure_i32(inst) {
        return Skip("loop contains an unsupported or effectful instruction")
      }
    }
  }
  let clone_available : @hashset.HashSet[Int] = HashSet([])
  for block in iteration_blocks {
    for inst in block.instructions {
      for arg in inst.args {
        if arg.id != induction.id &&
          is_defined_in_unroll_loop(func, loop_, arg.id) &&
          !clone_available.contains(arg.id) {
          return Skip(
            "body depends on a loop value unavailable in the preheader",
          )
        }
      }
      for result in inst.results {
        clone_available.add(result.id)
      }
    }
  }
  let latch_args = match latch.terminator {
    Some(Jump(target, args)) =>
      if target == header.id && args.length() == 1 {
        args
      } else {
        return Skip("latch must update only the induction value")
      }
    _ => return Skip("latch must jump to the header")
  }
  let update = match
    find_iteration_definition(iteration_blocks, latch_args[0].id) {
    Some(inst) => inst
    None => return Skip("latch induction update must be defined in the loop")
  }
  if update.opcode != Iadd || update.operands.length() != 2 {
    return Skip("induction update must be iadd")
  }
  let step_value = if update.operands[0].id == induction.id {
    update.operands[1]
  } else if update.operands[1].id == induction.id {
    update.operands[0]
  } else {
    return Skip("induction update must add a constant step")
  }
  let initial_constant = match
    find_i32_constant_outside_loop(func, loop_, initial) {
    Some(value) => value
    None => return Skip("initial induction value must be constant")
  }
  let bound_constant = match
    find_i32_constant_outside_loop(func, loop_, comparison.operands[1]) {
    Some(value) => value
    None => return Skip("loop bound must be constant")
  }
  let step_constant = match
    find_i32_constant_outside_loop(func, loop_, step_value) {
    Some(value) => value
    None => return Skip("induction step must be constant")
  }
  let trip_count = match
    checked_i32_full_unroll_trip_count(
      initial_constant, bound_constant, step_constant,
    ) {
    Some(value) => value
    None => return Skip("trip count is unsafe or exceeds the unroll bound")
  }
  let mut instructions_per_iteration = 0
  for block in iteration_blocks {
    instructions_per_iteration = instructions_per_iteration +
      block.instructions.length()
  }
  if instructions_per_iteration * trip_count >
    MAX_FULL_UNROLL_CLONED_INSTRUCTIONS {
    return Skip("unrolled body exceeds the code-growth budget")
  }
  Apply({
    preheader,
    header,
    induction,
    initial,
    iteration_blocks,
    latch_args,
    trip_count,
  })
}

///|
fn remap_unrolled_value(
  value : Value,
  values : @hashmap.HashMap[Int, Value],
) -> Value {
  values.get(value.id).unwrap_or(value)
}

///|
fn clone_unrolled_instruction(
  func : Function,
  inst : Inst,
  values : @hashmap.HashMap[Int, Value],
) -> Inst {
  let args = inst.args.map(fn(value) { remap_unrolled_value(value, values) })
  let results : Array[Value] = []
  for result in inst.results {
    let fresh = func.new_value(result.ty)
    values.set(result.id, fresh)
    results.push(fresh)
  }
  let cloned = func.new_inst(inst.opcode, args, results)
  for metadata in inst.metadata {
    cloned.add_metadata(metadata)
  }
  cloned
}

///|
fn apply_i32_full_unroll(func : Function, plan : FullUnrollPlan) -> Bool {
  if plan.trip_count == 0 {
    return false
  }
  let values : @hashmap.HashMap[Int, Value] = HashMap([])
  let mut current_induction = plan.initial
  for _ in 0..<plan.trip_count {
    values.set(plan.induction.id, current_induction)
    for block in plan.iteration_blocks {
      for inst in block.instructions {
        plan.preheader.instructions.push(
          clone_unrolled_instruction(func, inst, values),
        )
      }
    }
    current_induction = remap_unrolled_value(plan.latch_args[0], values)
  }
  plan.preheader.set_terminator(Jump(plan.header.id, [current_induction]))
  true
}

///|
fn full_unroll_i32_loops(func : Function) -> OptResult {
  let result = OptResult::OptResult()
  let cfg = CFG::build(func)
  let plans : Array[FullUnrollPlan] = []
  for loop_ in cfg.find_loops() {
    match analyze_i32_full_unroll(func, cfg, loop_) {
      Apply(plan) => plans.push(plan)
      // Keep the reason available to white-box diagnostics while the staged
      // pass intentionally ignores unsupported loops.
      Skip(reason) => reason |> ignore
    }
  }
  for plan in plans {
    if apply_i32_full_unroll(func, plan) {
      result.mark_changed()
    }
  }
  result
}
