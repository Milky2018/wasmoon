///|
const MAX_FULL_UNROLL_TRIP_COUNT : Int = 8

///|
const MAX_FACTOR_TWO_TRIP_COUNT : Int = 1000000

///|
const MAX_FULL_UNROLL_CLONED_INSTRUCTIONS : Int = 64

///|
const I32_SIGNED_MIN : Int64 = -2147483648L

///|
const I32_SIGNED_MAX : Int64 = 2147483647L

///|
priv struct CountedLoopPlan {
  preheader : @milkir.Block
  header : @milkir.Block
  latch : @milkir.Block
  header_params : Array[@milkir.Value]
  initial_args : Array[@milkir.Value]
  iteration_blocks : Array[@milkir.Block]
  latch_args : Array[@milkir.Value]
  trip_count : Int
}

///|
priv enum CountedLoopDecision {
  Apply(CountedLoopPlan)
  Skip(String)
}

///|
priv enum CountedDirection {
  Increasing
  Decreasing
} derive(Eq)

///|
priv enum CountedSignedness {
  Signed
  Unsigned
}

///|
fn find_unroll_block(func : @milkir.Function, block_id : Int) -> @milkir.Block? {
  for block in func.blocks {
    if block.id == block_id {
      return Some(block)
    }
  }
  None
}

///|
/// The instruction outside the loop that defines `value`, if there is one.
fn definition_outside_loop(
  func : @milkir.Function,
  loop_ : @milkir.Loop,
  value : @milkir.Value,
) -> @milkir.Inst? {
  for block in func.blocks {
    if loop_.contains(block.id) {
      continue
    }
    for inst_id in block.instruction_ids() {
      let inst = func.instruction_by_id(inst_id).unwrap()
      if inst.results.any(result => result.id == value.id) {
        return Some(inst)
      }
    }
  }
  None
}

///|
/// Resolve `value` to an integer constant defined outside the loop, following
/// copies.
///
/// Copies are followed with a loop rather than a recursive call: the length of
/// a copy chain is a property of the input function, and nothing upstream
/// bounds it (ISS-401).
fn find_integer_constant_outside_loop(
  func : @milkir.Function,
  loop_ : @milkir.Loop,
  value : @milkir.Value,
) -> Int64? {
  if value.ty != I32 && value.ty != I64 {
    return None
  }
  let visited : @hashset.HashSet[Int] = HashSet([])
  let mut current = value
  while !visited.contains(current.id) {
    visited.add(current.id)
    guard definition_outside_loop(func, loop_, current) is Some(inst) else {
      return None
    }
    match inst.opcode {
      Scalar(IntConst(constant)) => return Some(constant)
      Scalar(Copy) =>
        if inst.operands.length() == 1 && inst.operands[0].ty == current.ty {
          current = inst.operands[0]
        } else {
          return None
        }
      _ => return None
    }
  }
  None
}

///|
fn find_iteration_definition(
  func : @milkir.Function,
  iteration_blocks : Array[@milkir.Block],
  value_id : Int,
) -> @milkir.Inst? {
  for block in iteration_blocks {
    for inst_id in block.instruction_ids() {
      let inst = func.instruction_by_id(inst_id).unwrap()
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
  func : @milkir.Function,
  loop_ : @milkir.Loop,
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
    for inst_id in block.instruction_ids() {
      let inst = func.instruction_by_id(inst_id).unwrap()
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
fn counted_signedness(cc : @milkir.IntCC) -> CountedSignedness? {
  match cc {
    Slt | Sle | Sgt | Sge => Some(Signed)
    Ult | Ule | Ugt | Uge => Some(Unsigned)
    Eq | Ne => None
  }
}

///|
fn swap_counted_condition(cc : @milkir.IntCC) -> @milkir.IntCC? {
  match cc {
    Slt => Some(Sgt)
    Sle => Some(Sge)
    Sgt => Some(Slt)
    Sge => Some(Sle)
    Ult => Some(Ugt)
    Ule => Some(Uge)
    Ugt => Some(Ult)
    Uge => Some(Ule)
    Eq | Ne => None
  }
}

///|
fn invert_counted_condition(cc : @milkir.IntCC) -> @milkir.IntCC? {
  match cc {
    Slt => Some(Sge)
    Sle => Some(Sgt)
    Sgt => Some(Sle)
    Sge => Some(Slt)
    Ult => Some(Uge)
    Ule => Some(Ugt)
    Ugt => Some(Ule)
    Uge => Some(Ult)
    Eq | Ne => None
  }
}

///|
fn counted_condition_direction(cc : @milkir.IntCC) -> CountedDirection? {
  match cc {
    Slt | Sle | Ult | Ule => Some(Increasing)
    Sgt | Sge | Ugt | Uge => Some(Decreasing)
    Eq | Ne => None
  }
}

///|
fn counted_condition_is_inclusive(cc : @milkir.IntCC) -> Bool {
  match cc {
    Sle | Sge | Ule | Uge => true
    _ => false
  }
}

///|
fn integer_domain_max(ty : @milkir.Type) -> UInt64? {
  match ty {
    I32 => Some(0xFFFFFFFFUL)
    I64 => Some(0xFFFFFFFFFFFFFFFFUL)
    _ => None
  }
}

///|
fn integer_rank(
  raw : Int64,
  ty : @milkir.Type,
  signedness : CountedSignedness,
) -> UInt64? {
  match (ty, signedness) {
    (I32, Signed) =>
      if raw < I32_SIGNED_MIN || raw > I32_SIGNED_MAX {
        None
      } else {
        Some((raw - I32_SIGNED_MIN).reinterpret_as_uint64())
      }
    (I32, Unsigned) =>
      if raw < I32_SIGNED_MIN || raw > I32_SIGNED_MAX {
        None
      } else {
        Some(raw.reinterpret_as_uint64() & 0xFFFFFFFFUL)
      }
    (I64, Signed) => Some(raw.reinterpret_as_uint64() ^ 0x8000000000000000UL)
    (I64, Unsigned) => Some(raw.reinterpret_as_uint64())
    _ => None
  }
}

///|
fn counted_step(
  raw : Int64,
  ty : @milkir.Type,
  signedness : CountedSignedness,
  opcode : @milkir.Opcode,
) -> (CountedDirection, UInt64)? {
  if ty == I32 && (raw < I32_SIGNED_MIN || raw > I32_SIGNED_MAX) {
    return None
  }
  match signedness {
    Unsigned => {
      let magnitude = match integer_rank(raw, ty, Unsigned) {
        Some(value) => value
        None => return None
      }
      if magnitude == 0UL {
        return None
      }
      match opcode {
        Scalar(IntBinary(Add)) => Some((Increasing, magnitude))
        Scalar(IntBinary(Sub)) => Some((Decreasing, magnitude))
        _ => None
      }
    }
    Signed => {
      if raw == 0L {
        return None
      }
      let negative = raw < 0L
      let magnitude = if negative {
        0UL - raw.reinterpret_as_uint64()
      } else {
        raw.reinterpret_as_uint64()
      }
      match opcode {
        Scalar(IntBinary(Add)) =>
          if negative {
            Some((Decreasing, magnitude))
          } else {
            Some((Increasing, magnitude))
          }
        Scalar(IntBinary(Sub)) =>
          if negative {
            Some((Increasing, magnitude))
          } else {
            Some((Decreasing, magnitude))
          }
        _ => None
      }
    }
  }
}

///|
fn checked_trip_product(trips : UInt64, step : UInt64) -> UInt64? {
  if trips != 0UL && step > 0xFFFFFFFFFFFFFFFFUL / trips {
    None
  } else {
    Some(trips * step)
  }
}

///|
fn bounded_trip_quotient(
  distance : UInt64,
  step : UInt64,
  inclusive : Bool,
  max_trip_count : Int,
) -> UInt64? {
  let quotient = distance / step
  let remainder = distance % step
  let max_trips = max_trip_count.to_uint64()
  if inclusive {
    if quotient >= max_trips {
      return None
    }
    return Some(quotient + 1UL)
  }
  if quotient > max_trips || (quotient == max_trips && remainder != 0UL) {
    return None
  }
  let extra = if remainder == 0UL { 0UL } else { 1UL }
  Some(quotient + extra)
}

///|
fn checked_counted_trip_count(
  initial : UInt64,
  bound : UInt64,
  step : UInt64,
  direction : CountedDirection,
  condition : @milkir.IntCC,
  domain_max : UInt64,
  max_trip_count : Int,
) -> Int? {
  if counted_condition_direction(condition) != Some(direction) {
    return None
  }
  let inclusive = counted_condition_is_inclusive(condition)
  let distance = match direction {
    Increasing => {
      if (!inclusive && initial >= bound) || (inclusive && initial > bound) {
        return Some(0)
      }
      bound - initial
    }
    Decreasing => {
      if (!inclusive && initial <= bound) || (inclusive && initial < bound) {
        return Some(0)
      }
      initial - bound
    }
  }
  let trips = match
    bounded_trip_quotient(distance, step, inclusive, max_trip_count) {
    Some(value) => value
    None => return None
  }
  let product = match checked_trip_product(trips, step) {
    Some(value) => value
    None => return None
  }
  let wraps = match direction {
    Increasing => product > domain_max - initial
    Decreasing => product > initial
  }
  if wraps {
    return None
  }
  Some(trips.to_int())
}

///|
fn analyze_counted_loop(
  func : @milkir.Function,
  cfg : @milkir.CFG,
  loop_ : @milkir.Loop,
  max_trip_count : Int,
) -> CountedLoopDecision {
  if loop_.back_edges.length() != 1 {
    return Skip("loop must have one back edge")
  }
  let header = match find_unroll_block(func, loop_.header) {
    Some(block) => block
    None => return Skip("missing loop header")
  }
  if header.params.is_empty() {
    return Skip("loop header must have an induction block parameter")
  }
  let preheader_id = match cfg.get_loop_preheader(loop_) {
    Some(block_id) => block_id
    None => return Skip("loop must have one preheader")
  }
  let preheader = match find_unroll_block(func, preheader_id) {
    Some(block) => block
    None => return Skip("missing loop preheader")
  }
  let initial_args = match preheader.terminator {
    Some(Jump(target, args)) =>
      if target == header.id && args.length() == header.params.length() {
        args
      } else {
        return Skip("preheader arguments must match the loop header")
      }
    _ => return Skip("preheader must jump to the loop header")
  }
  let (
    condition,
    predicate_true_target,
    predicate_true_args,
    predicate_false_target,
    predicate_false_args,
  ) = match header.terminator {
    Some(Brnz(cond, true_target, false_target)) =>
      (cond, true_target, [], false_target, [])
    Some(Brz(cond, zero_target, nonzero_target)) =>
      (cond, nonzero_target, [], zero_target, [])
    Some(Branch(cond, true_target, true_args, false_target, false_args)) =>
      (cond, true_target, true_args, false_target, false_args)
    _ => return Skip("header must use a canonical conditional branch")
  }
  let (body_id, body_args, exit_id, exit_args, continue_on_true) = if loop_.contains(
      predicate_true_target,
    ) &&
    !loop_.contains(predicate_false_target) {
    (
      predicate_true_target, predicate_true_args, predicate_false_target, predicate_false_args,
      true,
    )
  } else if loop_.contains(predicate_false_target) &&
    !loop_.contains(predicate_true_target) {
    (
      predicate_false_target, predicate_false_args, predicate_true_target, predicate_true_args,
      false,
    )
  } else {
    return Skip("header must have one loop edge and one exit edge")
  }
  if !loop_.contains(body_id) || loop_.contains(exit_id) {
    return Skip("header must have one loop edge and one exit edge")
  }
  let exit = match find_unroll_block(func, exit_id) {
    Some(block) => block
    None => return Skip("missing loop exit")
  }
  if !body_args.is_empty() {
    return Skip("loop body branch arguments are unsupported")
  }
  if exit_args.length() != exit.params.length() {
    return Skip("exit arguments must match exit parameters")
  }
  for index, argument in exit_args {
    let (_, expected_type) = exit.params[index]
    if argument.ty != expected_type {
      return Skip("exit argument types must match exit parameters")
    }
  }
  if header.instruction_ids().length() != 1 {
    return Skip("header must contain only the induction comparison")
  }
  let comparison = func.instruction_by_id(header.instruction_ids()[0]).unwrap()
  let mut induction_index = -1
  let mut induction_operand = -1
  if comparison.operands.length() == 2 {
    for i, item in header.params {
      let (param, declared_type) = item
      if param.id == comparison.operands[0].id &&
        (param.ty == I32 || param.ty == I64) &&
        declared_type == param.ty {
        induction_index = i
        induction_operand = 0
        break
      } else if param.id == comparison.operands[1].id &&
        (param.ty == I32 || param.ty == I64) &&
        declared_type == param.ty {
        induction_index = i
        induction_operand = 1
        break
      }
    }
  }
  let original_condition = match comparison.opcode {
    Scalar(IntCompare(cc)) => cc
    _ => return Skip("loop test must be an ordered integer comparison")
  }
  let operand_normalized_condition = if induction_operand == 1 {
    match swap_counted_condition(original_condition) {
      Some(cc) => cc
      None => return Skip("loop test must use an ordered condition")
    }
  } else {
    original_condition
  }
  let normalized_condition = if continue_on_true {
    operand_normalized_condition
  } else {
    match invert_counted_condition(operand_normalized_condition) {
      Some(cc) => cc
      None => return Skip("loop test must use an ordered condition")
    }
  }
  if comparison.results.length() != 1 ||
    comparison.results[0].id != condition.id ||
    comparison.results[0].ty != I32 ||
    comparison.operands.length() != 2 ||
    induction_index < 0 ||
    comparison.operands[0].ty != comparison.operands[1].ty {
    return Skip("comparison must use the induction type")
  }
  let (induction, _) = header.params[induction_index]
  let bound_value = comparison.operands[1 - induction_operand]
  let signedness = match counted_signedness(normalized_condition) {
    Some(value) => value
    None => return Skip("loop test must use an ordered condition")
  }
  for i, item in header.params {
    let (param, declared_type) = item
    if param.ty != declared_type || initial_args[i].ty != declared_type {
      return Skip("preheader argument types must match the loop header")
    }
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
  let iteration_blocks : Array[@milkir.Block] = []
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
  }
  let header_param_ids : @hashset.HashSet[Int] = HashSet([])
  let header_params : Array[@milkir.Value] = []
  for item in header.params {
    let (param, _) = item
    header_param_ids.add(param.id)
    header_params.push(param)
  }
  let clone_available : @hashset.HashSet[Int] = HashSet([])
  for block in iteration_blocks {
    for inst_id in block.instruction_ids() {
      let inst = func.instruction_by_id(inst_id).unwrap()
      for arg in inst.args {
        if !header_param_ids.contains(arg.id) &&
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
      if target == header.id && args.length() == header.params.length() {
        args
      } else {
        return Skip("latch arguments must match the loop header")
      }
    _ => return Skip("latch must jump to the header")
  }
  for i, arg in latch_args {
    let (_, expected_type) = header.params[i]
    if arg.ty != expected_type {
      return Skip("latch argument types must match the loop header")
    }
    if !header_param_ids.contains(arg.id) &&
      is_defined_in_unroll_loop(func, loop_, arg.id) &&
      !clone_available.contains(arg.id) {
      return Skip("latch argument cannot be remapped in the preheader")
    }
  }
  let update = match
    find_iteration_definition(
      func,
      iteration_blocks,
      latch_args[induction_index].id,
    ) {
    Some(inst) => inst
    None => return Skip("latch induction update must be defined in the loop")
  }
  let update_opcode = update.opcode
  if (
      update_opcode != Scalar(IntBinary(Add)) &&
      update_opcode != Scalar(IntBinary(Sub))
    ) ||
    update.operands.length() != 2 ||
    update.results.length() != 1 {
    return Skip("induction update must be iadd or isub")
  }
  if update_opcode == Scalar(IntBinary(Sub)) &&
    update.operands[0].id != induction.id {
    return Skip("isub induction updates must subtract from the induction value")
  }
  let step_value = if update.operands[0].id == induction.id {
    update.operands[1]
  } else if update.operands[1].id == induction.id {
    update.operands[0]
  } else {
    return Skip("induction update must use a constant step")
  }
  if step_value.ty != induction.ty {
    return Skip("induction step type must match the induction value")
  }
  let initial_constant = match
    find_integer_constant_outside_loop(
      func,
      loop_,
      initial_args[induction_index],
    ) {
    Some(value) => value
    None => return Skip("initial induction value must be constant")
  }
  let bound_constant = match
    find_integer_constant_outside_loop(func, loop_, bound_value) {
    Some(value) => value
    None => return Skip("loop bound must be constant")
  }
  let step_constant = match
    find_integer_constant_outside_loop(func, loop_, step_value) {
    Some(value) => value
    None => return Skip("induction step must be constant")
  }
  let initial_rank = match
    integer_rank(initial_constant, induction.ty, signedness) {
    Some(value) => value
    None => return Skip("initial induction value is out of range")
  }
  let bound_rank = match
    integer_rank(bound_constant, induction.ty, signedness) {
    Some(value) => value
    None => return Skip("loop bound is out of range")
  }
  let (direction, step_magnitude) = match
    counted_step(step_constant, induction.ty, signedness, update_opcode) {
    Some(value) => value
    None => return Skip("induction step is zero or out of range")
  }
  let domain_max = match integer_domain_max(induction.ty) {
    Some(value) => value
    None => return Skip("induction type must be i32 or i64")
  }
  let trip_count = match
    checked_counted_trip_count(
      initial_rank, bound_rank, step_magnitude, direction, normalized_condition,
      domain_max, max_trip_count,
    ) {
    Some(value) => value
    None => return Skip("trip count is unsafe or exceeds the unroll bound")
  }
  Apply({
    preheader,
    header,
    latch,
    header_params,
    initial_args,
    iteration_blocks,
    latch_args,
    trip_count,
  })
}

///|
fn remap_unrolled_value(
  value : @milkir.Value,
  values : @hashmap.HashMap[Int, @milkir.Value],
) -> @milkir.Value {
  values.get(value.id).unwrap_or(value)
}

///|
fn clone_unrolled_instruction(
  func : @milkir.Function,
  inst : @milkir.Inst,
  values : @hashmap.HashMap[Int, @milkir.Value],
) -> @milkir.Inst {
  let args = inst.args.map(fn(value) { remap_unrolled_value(value, values) })
  let results : Array[@milkir.Value] = []
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
fn unroll_transition_instructions(
  func : @milkir.Function,
  plan : CountedLoopPlan,
) -> Array[@milkir.Inst] {
  let instructions : Array[@milkir.Inst] = []
  for block in plan.iteration_blocks {
    for inst_id in block.instruction_ids() {
      instructions.push(func.instruction_by_id(inst_id).unwrap())
    }
  }
  instructions
}

///|
fn clone_unrolled_transition(
  func : @milkir.Function,
  plan : CountedLoopPlan,
  source : Array[@milkir.Inst],
  start_args : Array[@milkir.Value],
  destination : @milkir.Block,
) -> Array[@milkir.Value] {
  let values : @hashmap.HashMap[Int, @milkir.Value] = HashMap([])
  for i, param in plan.header_params {
    values.set(param.id, start_args[i])
  }
  for inst in source {
    destination.append_inst(clone_unrolled_instruction(func, inst, values))
  }
  plan.latch_args.map(fn(value) { remap_unrolled_value(value, values) })
}

///|
fn apply_full_unroll(func : @milkir.Function, plan : CountedLoopPlan) -> Bool {
  if plan.trip_count == 0 {
    return false
  }
  let source = unroll_transition_instructions(func, plan)
  let mut current_args = plan.initial_args.copy()
  for _ in 0..<plan.trip_count {
    current_args = clone_unrolled_transition(
      func,
      plan,
      source,
      current_args,
      plan.preheader,
    )
  }
  plan.preheader.set_terminator(Jump(plan.header.id, current_args))
  true
}

///|
fn apply_factor_two_unroll(
  func : @milkir.Function,
  plan : CountedLoopPlan,
) -> Bool {
  if plan.trip_count == 0 {
    return false
  }
  let source = unroll_transition_instructions(func, plan)
  let remainder = plan.trip_count % 2
  let mut entry_args = plan.initial_args.copy()
  if remainder == 1 {
    entry_args = clone_unrolled_transition(
      func,
      plan,
      source,
      entry_args,
      plan.preheader,
    )
    plan.preheader.set_terminator(Jump(plan.header.id, entry_args))
  }
  if plan.trip_count - remainder == 0 {
    return true
  }
  let second_args = clone_unrolled_transition(
    func,
    plan,
    source,
    plan.latch_args,
    plan.latch,
  )
  plan.latch.set_terminator(Jump(plan.header.id, second_args))
  true
}

///|
fn factor_two_growth(plan : CountedLoopPlan, instructions : Int) -> Int64 {
  if plan.trip_count <= 1 {
    instructions.to_int64() * plan.trip_count.to_int64()
  } else {
    instructions.to_int64() * (1 + plan.trip_count % 2).to_int64()
  }
}

///|
fn unroll_counted_loops(func : @milkir.Function) -> OptResult {
  let result = OptResult::OptResult()
  let cfg = @milkir.CFG::build(func)
  let plans : Array[CountedLoopPlan] = []
  for loop_ in cfg.find_loops() {
    match analyze_counted_loop(func, cfg, loop_, MAX_FACTOR_TWO_TRIP_COUNT) {
      Apply(plan) => plans.push(plan)
      // Keep the reason available to white-box diagnostics while the staged
      // pass intentionally ignores unsupported loops.
      Skip(reason) => reason |> ignore
    }
  }
  for plan in plans {
    let instruction_count = unroll_transition_instructions(func, plan).length()
    let full_growth = instruction_count.to_int64() * plan.trip_count.to_int64()
    let factor_growth = factor_two_growth(plan, instruction_count)
    let changed = if plan.trip_count <= MAX_FULL_UNROLL_TRIP_COUNT &&
      full_growth <= MAX_FULL_UNROLL_CLONED_INSTRUCTIONS.to_int64() {
      apply_full_unroll(func, plan)
    } else if factor_growth <= MAX_FULL_UNROLL_CLONED_INSTRUCTIONS.to_int64() {
      apply_factor_two_unroll(func, plan)
    } else {
      false
    }
    if changed {
      result.mark_changed()
    }
  }
  result
}
