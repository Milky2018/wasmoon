// ============ Constant Block Parameter Elimination ============

///|
/// Abstract value for block parameters during constant-phi analysis
priv enum PhiAbstractValue {
  None
  One(Int)
  Many
} derive(Eq)

///|
fn PhiAbstractValue::join(
  self : PhiAbstractValue,
  other : PhiAbstractValue,
) -> PhiAbstractValue {
  match (self, other) {
    (None, v) => v
    (v, None) => v
    (Many, _) => Many
    (_, Many) => Many
    (One(v1), One(v2)) => if v1 == v2 { One(v1) } else { Many }
  }
}

///|

///|
fn build_value_array(
  func : @milkir.Function,
  value_count : Int,
) -> Array[@milkir.Value?] {
  let values : Array[@milkir.Value?] = Array::make(value_count, None)
  for param in func.params {
    let (v, _) = param
    if v.id >= 0 && v.id < value_count {
      values[v.id] = Some(v)
    }
  }
  for block in func.blocks {
    for param in block.params {
      let (v, _) = param
      if v.id >= 0 && v.id < value_count {
        values[v.id] = Some(v)
      }
    }
    for inst_id in block.instruction_ids() {
      let inst = func.instruction_by_id(inst_id).unwrap()
      for result in inst.results {
        if result.id >= 0 && result.id < value_count {
          values[result.id] = Some(result)
        }
      }
    }
  }
  values
}

///|
fn build_block_index_array(func : @milkir.Function) -> Array[Int] {
  let block_count = func.next_block_id
  let block_idx : Array[Int] = Array::make(block_count, -1)
  for i, block in func.blocks {
    if block.id >= 0 && block.id < block_count {
      block_idx[block.id] = i
    }
  }
  block_idx
}

///|
fn compress_replace_array(replace_ids : Array[Int]) -> Unit {
  let count = replace_ids.length()
  for key in 0..<count {
    if replace_ids[key] < 0 {
      continue
    }
    let mut current = key
    let path : Array[Int] = []
    let mut steps = 0
    while steps < 1024 {
      path.push(current)
      if current < 0 || current >= count {
        break
      }
      let next = replace_ids[current]
      if next < 0 || next == current {
        break
      }
      current = next
      steps = steps + 1
    }
    for visited in path {
      if visited >= 0 && visited < count {
        replace_ids[visited] = current
      }
    }
  }
}

///|
fn append_block_argument_pairs(
  pairs : Array[(Int, Int)],
  target : Int,
  arguments : Array[@milkir.Value],
  func : @milkir.Function,
  block_idx : Array[Int],
) -> Unit {
  if target < 0 || target >= block_idx.length() || block_idx[target] < 0 {
    return
  }
  let target_block = func.blocks[block_idx[target]]
  let count = target_block.params.length().min(arguments.length())
  for i in 0..<count {
    pairs.push((target_block.params[i].0.id, arguments[i].id))
  }
}

///|
fn collect_block_argument_pairs(
  func : @milkir.Function,
  block_idx : Array[Int],
) -> Array[(Int, Int)] {
  let pairs : Array[(Int, Int)] = []
  for block in func.blocks {
    match block.terminator {
      Some(Jump(target, arguments)) =>
        append_block_argument_pairs(pairs, target, arguments, func, block_idx)
      Some(Branch(_, true_target, true_args, false_target, false_args)) => {
        append_block_argument_pairs(
          pairs, true_target, true_args, func, block_idx,
        )
        append_block_argument_pairs(
          pairs, false_target, false_args, func, block_idx,
        )
      }
      _ => ()
    }
  }
  pairs
}

///|
fn retained_block_arguments(
  target : Int,
  arguments : Array[@milkir.Value],
  block_idx : Array[Int],
  params_to_keep : Array[Array[Int]],
) -> Array[@milkir.Value]? {
  if target < 0 || target >= block_idx.length() {
    return None
  }
  let target_index = block_idx[target]
  if target_index < 0 || target_index >= params_to_keep.length() {
    return None
  }
  let keep = params_to_keep[target_index]
  if keep.length() == arguments.length() {
    return None
  }
  let retained : Array[@milkir.Value] = []
  for index in keep {
    if index < arguments.length() {
      retained.push(arguments[index])
    }
  }
  Some(retained)
}

///|
/// Constant Block Parameter Elimination
/// Removes block parameters that always take the same value across all incoming edges.
/// This mirrors Cranelift's constant-phi removal, but operates on IR block params.
fn eliminate_constant_block_params(func : @milkir.Function) -> OptResult {
  let result = OptResult::OptResult()
  if func.blocks.length() == 0 {
    return result
  }
  let entry_id = func.blocks[0].id
  let block_idx = build_block_index_array(func)
  let value_count = func.next_value_id
  if value_count <= 0 {
    return result
  }
  let state : Array[PhiAbstractValue?] = Array::make(value_count, None)
  let mut has_params = false
  for block in func.blocks {
    if block.id == entry_id {
      continue
    }
    for param in block.params {
      let (v, _) = param
      if v.id >= 0 && v.id < value_count {
        state[v.id] = Some(None)
        has_params = true
      }
    }
  }
  if !has_params {
    return result
  }
  // Precompute jump-argument -> target-formal propagation pairs once.
  // This mirrors Cranelift's block-summary approach and avoids repeated
  // block/edge lookup work in each solver iteration.
  let propagation_pairs : Array[(Int, Int)] = []
  for pair in collect_block_argument_pairs(func, block_idx) {
    let (formal_id, actual_id) = pair
    if formal_id >= 0 && formal_id < value_count && state[formal_id] is Some(_) {
      propagation_pairs.push((formal_id, actual_id))
    }
  }
  if propagation_pairs.length() == 0 {
    return result
  }
  // Event-driven solver:
  // - process each propagation pair once
  // - when a formal changes, only reprocess pairs that depend on it
  // This avoids repeatedly scanning all edges until fixed-point.
  let dependent_pairs : Array[Array[Int]?] = Array::make(value_count, None)
  for pair_idx, pair in propagation_pairs {
    let (_, actual_id) = pair
    if actual_id >= 0 && actual_id < value_count && state[actual_id] is Some(_) {
      let deps = dependent_pairs[actual_id].unwrap_or([])
      deps.push(pair_idx)
      dependent_pairs[actual_id] = Some(deps)
    }
  }
  let queue : Array[Int] = []
  let in_queue : Array[Bool] = Array::make(propagation_pairs.length(), false)
  for pair_idx, _ in propagation_pairs {
    queue.push(pair_idx)
    in_queue[pair_idx] = true
  }
  let mut queue_head = 0
  let mut steps = 0
  let max_steps = propagation_pairs.length() * 16 + 1024
  while queue_head < queue.length() && steps < max_steps {
    let pair_idx = queue[queue_head]
    queue_head = queue_head + 1
    in_queue[pair_idx] = false
    steps = steps + 1
    let (formal_id, actual_id) = propagation_pairs[pair_idx]
    if formal_id < 0 || formal_id >= value_count {
      continue
    }
    let old_absval = state[formal_id].unwrap_or(None)
    if old_absval is Many {
      continue
    }
    let actual_absval = if actual_id >= 0 && actual_id < value_count {
      match state[actual_id] {
        Some(absval) => absval
        None => One(actual_id)
      }
    } else {
      One(actual_id)
    }
    let new_absval = old_absval.join(actual_absval)
    if new_absval != old_absval {
      state[formal_id] = Some(new_absval)
      if dependent_pairs[formal_id] is Some(deps) {
        for dep_idx in deps {
          if dep_idx >= 0 && dep_idx < in_queue.length() && !in_queue[dep_idx] {
            queue.push(dep_idx)
            in_queue[dep_idx] = true
          }
        }
      }
    }
  }
  let params_to_keep : Array[Array[Int]] = []
  let replace_ids : Array[Int] = Array::make(value_count, -1)
  let mut will_change = false
  for block in func.blocks {
    let keep : Array[Int] = []
    for i, param in block.params {
      let (v, _) = param
      if v.id >= 0 && v.id < value_count {
        match state[v.id] {
          Some(One(replacement_id)) => {
            replace_ids[v.id] = replacement_id
            will_change = true
          }
          _ => keep.push(i)
        }
      } else {
        keep.push(i)
      }
    }
    params_to_keep.push(keep)
  }
  if !will_change {
    return result
  }
  compress_replace_array(replace_ids)
  for block in func.blocks {
    let block_i = if block.id >= 0 && block.id < block_idx.length() {
      block_idx[block.id]
    } else {
      -1
    }
    if block_i < 0 || block_i >= params_to_keep.length() {
      continue
    }
    let keep = params_to_keep[block_i]
    if keep.length() != block.params.length() {
      func.retain_block_params(block, keep)
      result.mark_changed()
    }
  }
  for block in func.blocks {
    match block.terminator {
      Some(Jump(target, arguments)) =>
        if retained_block_arguments(
            target, arguments, block_idx, params_to_keep,
          )
          is Some(retained) {
          block.set_terminator(Jump(target, retained))
          result.mark_changed()
        }
      Some(Branch(cond, true_target, true_args, false_target, false_args)) => {
        let retained_true = retained_block_arguments(
          true_target, true_args, block_idx, params_to_keep,
        )
        let retained_false = retained_block_arguments(
          false_target, false_args, block_idx, params_to_keep,
        )
        if retained_true is Some(_) || retained_false is Some(_) {
          block.set_terminator(
            Branch(
              cond,
              true_target,
              retained_true.unwrap_or(true_args),
              false_target,
              retained_false.unwrap_or(false_args),
            ),
          )
          result.mark_changed()
        }
      }
      _ => ()
    }
  }
  let replace_values : Array[@milkir.Value?] = Array::make(value_count, None)
  let values = build_value_array(func, value_count)
  for from_id, to_id in replace_ids {
    if to_id >= 0 && to_id < value_count && values[to_id] is Some(replacement) {
      replace_values[from_id] = Some(replacement)
    }
  }
  for block in func.blocks {
    for inst_id in block.instruction_ids() {
      let inst = func.instruction_by_id(inst_id).unwrap()
      let mut changed_inst = false
      for i, op in inst.operands {
        if op.id >= 0 && op.id < value_count {
          if replace_values[op.id] is Some(replacement) &&
            replacement.id != op.id {
            inst.operands[i] = replacement
            changed_inst = true
          }
        }
      }
      if changed_inst {
        result.mark_changed()
      }
    }
    if block.terminator is Some(term) {
      match term {
        Jump(target, args) => {
          let mut new_args : Array[@milkir.Value]? = None
          for i, arg in args {
            if arg.id >= 0 && arg.id < value_count {
              if replace_values[arg.id] is Some(replacement) &&
                replacement.id != arg.id {
                if new_args is None {
                  new_args = Some(args.copy())
                }
                if new_args is Some(updated_args) {
                  updated_args[i] = replacement
                }
              }
            }
          }
          if new_args is Some(updated_args) {
            block.set_terminator(Jump(target, updated_args))
            result.mark_changed()
          }
        }
        Brz(cond, then_target, else_target) =>
          if cond.id >= 0 && cond.id < value_count {
            if replace_values[cond.id] is Some(resolved) &&
              resolved.id != cond.id {
              block.set_terminator(Brz(resolved, then_target, else_target))
              result.mark_changed()
            }
          }
        Brnz(cond, then_target, else_target) =>
          if cond.id >= 0 && cond.id < value_count {
            if replace_values[cond.id] is Some(resolved) &&
              resolved.id != cond.id {
              block.set_terminator(Brnz(resolved, then_target, else_target))
              result.mark_changed()
            }
          }
        Branch(cond, true_target, true_args, false_target, false_args) => {
          let mut new_cond = cond
          let mut changed = false
          if cond.id >= 0 && cond.id < value_count {
            if replace_values[cond.id] is Some(resolved) &&
              resolved.id != cond.id {
              new_cond = resolved
              changed = true
            }
          }
          let new_true_args = true_args.copy()
          for i, arg in true_args {
            if arg.id >= 0 && arg.id < value_count {
              if replace_values[arg.id] is Some(resolved) &&
                resolved.id != arg.id {
                new_true_args[i] = resolved
                changed = true
              }
            }
          }
          let new_false_args = false_args.copy()
          for i, arg in false_args {
            if arg.id >= 0 && arg.id < value_count {
              if replace_values[arg.id] is Some(resolved) &&
                resolved.id != arg.id {
                new_false_args[i] = resolved
                changed = true
              }
            }
          }
          if changed {
            block.set_terminator(
              Branch(
                new_cond, true_target, new_true_args, false_target, new_false_args,
              ),
            )
            result.mark_changed()
          }
        }
        BrTable(index, targets, default_target) =>
          if index.id >= 0 && index.id < value_count {
            if replace_values[index.id] is Some(resolved) &&
              resolved.id != index.id {
              block.set_terminator(BrTable(resolved, targets, default_target))
              result.mark_changed()
            }
          }
        Return(values) => {
          let mut new_values : Array[@milkir.Value]? = None
          for i, value in values {
            if value.id >= 0 && value.id < value_count {
              if replace_values[value.id] is Some(replacement) &&
                replacement.id != value.id {
                if new_values is None {
                  new_values = Some(values.copy())
                }
                if new_values is Some(updated_values) {
                  updated_values[i] = replacement
                }
              }
            }
          }
          if new_values is Some(updated_values) {
            block.set_terminator(Return(updated_values))
            result.mark_changed()
          }
        }
        Trap(_) | TrapExit(_) => ()
      }
    }
  }
  result
}

// ============ Dead Block Parameter Elimination ============

///|
/// Dead Block Parameter Elimination
/// Removes block parameters that are never used
/// This is crucial for eliminating unused locals that get SSA-converted to block params
fn eliminate_dead_block_params(func : @milkir.Function) -> OptResult {
  let result = OptResult::OptResult()

  // Build use counts for values in each block
  // A block parameter is "used" if it's referenced in instructions or passed to another used param
  let block_idx = build_block_index_array(func)
  let used_params = compute_used_block_params(func, block_idx)

  // Track which parameter indices to keep for each block
  let params_to_keep : Array[Array[Int]] = []
  for block in func.blocks {
    let keep : Array[Int] = []
    for i, param in block.params {
      let (v, _) = param
      if v.id >= 0 && v.id < used_params.length() && used_params[v.id] {
        keep.push(i)
      }
    }
    params_to_keep.push(keep)
  }

  // Check if any parameters will be removed
  let mut will_change = false
  for block in func.blocks {
    let block_i = if block.id >= 0 && block.id < block_idx.length() {
      block_idx[block.id]
    } else {
      -1
    }
    if block_i < 0 || block_i >= params_to_keep.length() {
      continue
    }
    let keep = params_to_keep[block_i]
    if keep.length() != block.params.length() {
      will_change = true
      break
    }
  }
  if !will_change {
    return result
  }

  // Update block parameters - remove unused ones
  for block in func.blocks {
    let block_i = if block.id >= 0 && block.id < block_idx.length() {
      block_idx[block.id]
    } else {
      -1
    }
    if block_i < 0 || block_i >= params_to_keep.length() {
      continue
    }
    let keep = params_to_keep[block_i]
    if keep.length() != block.params.length() {
      func.retain_block_params(block, keep)
      result.mark_changed()
    }
  }

  // Update terminators - remove arguments corresponding to removed parameters
  for block in func.blocks {
    match block.terminator {
      Some(Jump(target, arguments)) =>
        if retained_block_arguments(
            target, arguments, block_idx, params_to_keep,
          )
          is Some(retained) {
          block.set_terminator(Jump(target, retained))
          result.mark_changed()
        }
      Some(Branch(cond, true_target, true_args, false_target, false_args)) => {
        let retained_true = retained_block_arguments(
          true_target, true_args, block_idx, params_to_keep,
        )
        let retained_false = retained_block_arguments(
          false_target, false_args, block_idx, params_to_keep,
        )
        if retained_true is Some(_) || retained_false is Some(_) {
          block.set_terminator(
            Branch(
              cond,
              true_target,
              retained_true.unwrap_or(true_args),
              false_target,
              retained_false.unwrap_or(false_args),
            ),
          )
          result.mark_changed()
        }
      }
      Some(Brz(_, _, _)) | Some(Brnz(_, _, _)) | Some(BrTable(_, _, _)) =>
        // These don't pass arguments, nothing to update
        ()
      _ => ()
    }
  }
  result
}

///|
/// Compute which block parameters are actually used
/// Uses iterative dataflow analysis
fn compute_used_block_params(
  func : @milkir.Function,
  block_idx : Array[Int],
) -> Array[Bool] {
  let value_count = func.next_value_id
  if value_count <= 0 {
    return []
  }
  let used = Array::make(value_count, false)
  let propagation_edges : Array[Array[Int]?] = Array::make(value_count, None)
  for pair in collect_block_argument_pairs(func, block_idx) {
    let (formal_id, actual_id) = pair
    if formal_id >= 0 && formal_id < value_count {
      match propagation_edges[formal_id] {
        Some(edges) => edges.push(actual_id)
        None => propagation_edges[formal_id] = Some([actual_id])
      }
    }
  }

  // Initialize: all function parameters are used (they come from caller)
  for param in func.params {
    let (v, _) = param
    if v.id >= 0 && v.id < value_count {
      used[v.id] = true
    }
  }

  // First pass: mark values used directly in instructions
  for block in func.blocks {
    for inst_id in block.instruction_ids() {
      let inst = func.instruction_by_id(inst_id).unwrap()
      for op in inst.operands {
        if op.id >= 0 && op.id < value_count {
          used[op.id] = true
        }
      }
    }
    // Also count uses in terminators (excluding jump args; handled by dataflow)
    if block.terminator is Some(term) {
      match term {
        Jump(_, _) => ()
        Brz(cond, _, _) | Brnz(cond, _, _) =>
          if cond.id >= 0 && cond.id < value_count {
            used[cond.id] = true
          }
        Branch(cond, _, _, _, _) =>
          if cond.id >= 0 && cond.id < value_count {
            used[cond.id] = true
          }
        // Edge arguments are propagated only when the corresponding target
        // parameter is live, just like Jump arguments.
        BrTable(index, _, _) =>
          if index.id >= 0 && index.id < value_count {
            used[index.id] = true
          }
        Return(args) =>
          for v in args {
            if v.id >= 0 && v.id < value_count {
              used[v.id] = true
            }
          }
        Trap(_) | TrapExit(_) => ()
      }
    }
  }

  // Worklist propagation: if a block parameter is used, propagate that mark to
  // incoming jump arguments for the corresponding edge position.
  let worklist : Array[Int] = []
  for value_id in 0..<value_count {
    if used[value_id] {
      worklist.push(value_id)
    }
  }
  while worklist.length() > 0 {
    let value_id = worklist.pop().unwrap()
    if value_id < 0 || value_id >= value_count {
      continue
    }
    if propagation_edges[value_id] is Some(edges) {
      for arg_id in edges {
        if arg_id >= 0 && arg_id < value_count && !used[arg_id] {
          used[arg_id] = true
          worklist.push(arg_id)
        }
      }
    }
  }
  used
}

// ============ Branch Simplification ============

///|
/// Branch Simplification
/// Simplifies conditional branches when the condition is a known constant
fn simplify_branches(func : @milkir.Function) -> OptResult {
  let result = OptResult::OptResult()
  // Build constant map from constant folding
  let constants : @hashmap.HashMap[Int, ConstValue] = HashMap([])
  for block in func.blocks {
    for inst_id in block.instruction_ids() {
      let inst = func.instruction_by_id(inst_id).unwrap()
      if inst.opcode is Scalar(IntConst(v)) && inst.first_result() is Some(r) {
        if r.ty is I32 {
          constants.set(r.id, I32(v.to_int()))
        } else {
          constants.set(r.id, I64(v))
        }
      }
    }
  }
  // Simplify branches
  for block in func.blocks {
    if block.terminator is Some(Brz(cond, then_target, else_target)) {
      if constants.get(cond.id) is Some(I32(v)) {
        // brz: branch if zero
        let target = if v == 0 { then_target } else { else_target }
        block.set_terminator(Jump(target, []))
        result.mark_changed()
      } else if constants.get(cond.id) is Some(I64(v)) {
        let target = if v == 0L { then_target } else { else_target }
        block.set_terminator(Jump(target, []))
        result.mark_changed()
      }
    } else if block.terminator is Some(Brnz(cond, then_target, else_target)) {
      if constants.get(cond.id) is Some(I32(v)) {
        // brnz: branch if not zero
        let target = if v != 0 { then_target } else { else_target }
        block.set_terminator(Jump(target, []))
        result.mark_changed()
      } else if constants.get(cond.id) is Some(I64(v)) {
        let target = if v != 0L { then_target } else { else_target }
        block.set_terminator(Jump(target, []))
        result.mark_changed()
      }
    } else if block.terminator
      is Some(Branch(cond, true_target, true_args, false_target, false_args)) {
      if constants.get(cond.id) is Some(I32(value)) {
        block.set_terminator(
          if value != 0 {
            Jump(true_target, true_args)
          } else {
            Jump(false_target, false_args)
          },
        )
        result.mark_changed()
      } else if constants.get(cond.id) is Some(I64(value)) {
        block.set_terminator(
          if value != 0L {
            Jump(true_target, true_args)
          } else {
            Jump(false_target, false_args)
          },
        )
        result.mark_changed()
      }
    } else if block.terminator is Some(BrTable(index, targets, default_target)) {
      if constants.get(index.id) is Some(I32(v)) {
        // Convert to direct jump if index is constant
        let target = if v >= 0 && v < targets.length() {
          targets[v]
        } else {
          default_target
        }
        block.set_terminator(Jump(target, []))
        result.mark_changed()
      }
    }
  }
  result
}

// ============ Unreachable Code Elimination ============

///|
/// Unreachable Code Elimination
/// Removes blocks that cannot be reached from the entry block
fn eliminate_unreachable_code(func : @milkir.Function) -> OptResult {
  let result = OptResult::OptResult()
  if func.blocks.length() == 0 {
    return result
  }
  let block_idx = build_block_index_array(func)
  let reachable = Array::make(func.next_block_id, false)
  let worklist : Array[Int] = []
  if block_idx.length() > 0 && block_idx[0] >= 0 {
    reachable[0] = true
    worklist.push(0)
  }
  while worklist.length() > 0 {
    let block_id = worklist.pop().unwrap()
    let block = func.blocks[block_idx[block_id]]
    if block.terminator is Some(term) {
      for succ in term.targets() {
        if succ >= 0 &&
          succ < block_idx.length() &&
          block_idx[succ] >= 0 &&
          !reachable[succ] {
          reachable[succ] = true
          worklist.push(succ)
        }
      }
    }
  }
  let old_block_count = func.blocks.length()
  func.retain_blocks(fn(block) {
    block.id >= 0 && block.id < reachable.length() && reachable[block.id]
  })
  if func.blocks.length() != old_block_count {
    result.mark_changed()
  }
  result
}

// ============ Basic Block Merging ============

///|
/// Basic Block Merging
/// Merges a block with its unique predecessor if the predecessor has only one successor
fn merge_blocks(func : @milkir.Function) -> OptResult {
  let result = OptResult::OptResult()
  if func.blocks.length() <= 1 {
    return result
  }
  let block_idx = build_block_index_array(func)
  let pred_count = Array::make(func.next_block_id, 0)
  for block in func.blocks {
    if block.terminator is Some(term) {
      for target in term.targets() {
        if target >= 0 && target < pred_count.length() {
          pred_count[target] = pred_count[target] + 1
        }
      }
    }
  }

  // Absorb complete straight-line chains while indices still refer to the
  // original array, then compact the array once.
  let removed = Array::make(func.next_block_id, false)
  for block in func.blocks {
    if block.id < 0 || block.id >= removed.length() || removed[block.id] {
      continue
    }
    let mut done = false
    while !done {
      match block.terminator {
        Some(Jump(target, args)) => {
          if args.length() != 0 ||
            target <= 0 ||
            target >= block_idx.length() ||
            block_idx[target] < 0 ||
            removed[target] ||
            pred_count[target] != 1 {
            done = true
            continue
          }
          let successor = func.blocks[block_idx[target]]
          if successor.id == block.id {
            done = true
            continue
          }
          for inst_id in successor.instruction_ids() {
            block.append_inst(func.instruction_by_id(inst_id).unwrap())
          }
          successor.clear_instructions_for_move()
          block.set_terminator(successor.terminator.unwrap())
          removed[target] = true
          result.mark_changed()
        }
        _ => done = true
      }
    }
  }
  if result.changed {
    func.retain_blocks(fn(block) {
      block.id < 0 || block.id >= removed.length() || !removed[block.id]
    })
  }
  result
}

// ============ Jump Threading ============

///|
fn block_arg_arrays_equal(
  lhs : Array[@milkir.Value],
  rhs : Array[@milkir.Value],
) -> Bool {
  if lhs.length() != rhs.length() {
    return false
  }
  for i in 0..<lhs.length() {
    if lhs[i].id != rhs[i].id {
      return false
    }
  }
  true
}

///|
fn rewrite_jump_args_through_block(
  block_params : Array[(@milkir.Value, @milkir.Type)],
  incoming_args : Array[@milkir.Value],
  outgoing_args : Array[@milkir.Value],
) -> Array[@milkir.Value]? {
  if block_params.length() != incoming_args.length() {
    return None
  }
  let param_to_arg : @hashmap.HashMap[Int, @milkir.Value] = HashMap([])
  for i in 0..<block_params.length() {
    let (param, _) = block_params[i]
    param_to_arg.set(param.id, incoming_args[i])
  }
  let rewritten : Array[@milkir.Value] = []
  for arg in outgoing_args {
    rewritten.push(param_to_arg.get(arg.id).unwrap_or(arg))
  }
  Some(rewritten)
}

///|
fn resolve_jump_target_with_args(
  target : Int,
  args : Array[@milkir.Value],
  func : @milkir.Function,
  block_idx : @hashmap.HashMap[Int, Int],
  empty_jump_targets : Array[Int],
  forward_only_params : Array[Bool],
) -> (Int, Array[@milkir.Value]) {
  if args.length() == 0 &&
    target >= 0 &&
    target < empty_jump_targets.length() &&
    empty_jump_targets[target] >= 0 {
    return (empty_jump_targets[target], [])
  }
  let visited : @hashmap.HashMap[Int, Bool] = HashMap([])
  let empty_path : Array[Int] = []
  let mut current_target = target
  let mut current_args = args
  let mut cacheable = args.length() == 0
  let mut cyclic = false
  let mut done = false
  while !done {
    if cacheable &&
      current_target >= 0 &&
      current_target < empty_jump_targets.length() &&
      empty_jump_targets[current_target] >= 0 {
      current_target = empty_jump_targets[current_target]
      done = true
      continue
    }
    if visited.get(current_target).unwrap_or(false) {
      cyclic = true
      break
    }
    visited.set(current_target, true)
    let block = match block_idx.get(current_target) {
      Some(idx) => func.blocks[idx]
      None => break
    }
    if block.instruction_ids().length() != 0 {
      break
    }
    if block.params.length() != 0 &&
      (
        current_target < 0 ||
        current_target >= forward_only_params.length() ||
        !forward_only_params[current_target]
      ) {
      break
    }
    match block.terminator {
      Some(Jump(next_target, next_args)) =>
        match
          rewrite_jump_args_through_block(block.params, current_args, next_args) {
          Some(rewritten_args) => {
            if cacheable &&
              block.params.length() == 0 &&
              current_args.length() == 0 &&
              next_args.length() == 0 {
              empty_path.push(current_target)
            } else {
              cacheable = false
              empty_path.clear()
            }
            current_target = next_target
            current_args = rewritten_args
          }
          None => done = true
        }
      _ => done = true
    }
  }
  if cacheable && !cyclic && current_args.length() == 0 {
    for path_target in empty_path {
      if path_target >= 0 && path_target < empty_jump_targets.length() {
        empty_jump_targets[path_target] = current_target
      }
    }
  }
  (current_target, current_args)
}

///|
/// Jump Threading
/// Bypasses blocks that only contain an unconditional jump
fn thread_jumps(func : @milkir.Function) -> OptResult {
  let result = OptResult::OptResult()
  let block_idx : @hashmap.HashMap[Int, Int] = HashMap([])
  for i, block in func.blocks {
    block_idx.set(block.id, i)
  }
  let use_counts = compute_use_counts(func)
  let forward_only_params = Array::make(func.next_block_id, false)
  for block in func.blocks {
    if block.id < 0 || block.id >= forward_only_params.length() {
      continue
    }
    if block.terminator is Some(Jump(_, outgoing_args)) {
      forward_only_params[block.id] = block.params.all(fn(param) {
        let mut outgoing_uses = 0
        for arg in outgoing_args {
          if arg.id == param.0.id {
            outgoing_uses = outgoing_uses + 1
          }
        }
        use_counts.get(param.0.id).unwrap_or(0) == outgoing_uses
      })
    }
  }
  let empty_jump_targets = Array::make(func.next_block_id, -1)
  // Update terminators to skip intermediate jump blocks
  for block in func.blocks {
    match block.terminator {
      Some(Jump(target, args)) => {
        let (final_target, final_args) = resolve_jump_target_with_args(
          target, args, func, block_idx, empty_jump_targets, forward_only_params,
        )
        if final_target != target || !block_arg_arrays_equal(final_args, args) {
          block.set_terminator(Jump(final_target, final_args))
          result.mark_changed()
        }
      }
      Some(Brz(cond, then_target, else_target)) => {
        let (resolved_then, then_args) = resolve_jump_target_with_args(
          then_target,
          [],
          func,
          block_idx,
          empty_jump_targets,
          forward_only_params,
        )
        let (resolved_else, else_args) = resolve_jump_target_with_args(
          else_target,
          [],
          func,
          block_idx,
          empty_jump_targets,
          forward_only_params,
        )
        let new_then = if then_args.length() == 0 {
          resolved_then
        } else {
          then_target
        }
        let new_else = if else_args.length() == 0 {
          resolved_else
        } else {
          else_target
        }
        if new_then != then_target || new_else != else_target {
          block.set_terminator(Brz(cond, new_then, new_else))
          result.mark_changed()
        }
      }
      Some(Brnz(cond, then_target, else_target)) => {
        let (resolved_then, then_args) = resolve_jump_target_with_args(
          then_target,
          [],
          func,
          block_idx,
          empty_jump_targets,
          forward_only_params,
        )
        let (resolved_else, else_args) = resolve_jump_target_with_args(
          else_target,
          [],
          func,
          block_idx,
          empty_jump_targets,
          forward_only_params,
        )
        let new_then = if then_args.length() == 0 {
          resolved_then
        } else {
          then_target
        }
        let new_else = if else_args.length() == 0 {
          resolved_else
        } else {
          else_target
        }
        if new_then != then_target || new_else != else_target {
          block.set_terminator(Brnz(cond, new_then, new_else))
          result.mark_changed()
        }
      }
      Some(Branch(cond, true_target, true_args, false_target, false_args)) => {
        let (resolved_true, resolved_true_args) = resolve_jump_target_with_args(
          true_target, true_args, func, block_idx, empty_jump_targets, forward_only_params,
        )
        let (resolved_false, resolved_false_args) = resolve_jump_target_with_args(
          false_target, false_args, func, block_idx, empty_jump_targets, forward_only_params,
        )
        if resolved_true != true_target ||
          !block_arg_arrays_equal(resolved_true_args, true_args) ||
          resolved_false != false_target ||
          !block_arg_arrays_equal(resolved_false_args, false_args) {
          block.set_terminator(
            Branch(
              cond, resolved_true, resolved_true_args, resolved_false, resolved_false_args,
            ),
          )
          result.mark_changed()
        }
      }
      Some(BrTable(index, targets, default_target)) => {
        let new_targets : Array[Int] = []
        let mut any_changed = false
        for t in targets {
          let (resolved_t, resolved_args) = resolve_jump_target_with_args(
            t,
            [],
            func,
            block_idx,
            empty_jump_targets,
            forward_only_params,
          )
          let new_t = if resolved_args.length() == 0 { resolved_t } else { t }
          new_targets.push(new_t)
          if new_t != t {
            any_changed = true
          }
        }
        let (resolved_default, default_args) = resolve_jump_target_with_args(
          default_target,
          [],
          func,
          block_idx,
          empty_jump_targets,
          forward_only_params,
        )
        let new_default = if default_args.length() == 0 {
          resolved_default
        } else {
          default_target
        }
        if new_default != default_target {
          any_changed = true
        }
        if any_changed {
          block.set_terminator(BrTable(index, new_targets, new_default))
          result.mark_changed()
        }
      }
      _ => ()
    }
  }
  if result.changed {
    eliminate_unreachable_code(func) |> ignore
  }
  result
}
