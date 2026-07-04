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
fn build_value_array(func : Function, value_count : Int) -> Array[Value?] {
  let values : Array[Value?] = Array::make(value_count, None)
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
    for inst in block.instructions {
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
fn build_block_index_array(func : Function) -> Array[Int] {
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
/// Constant Block Parameter Elimination
/// Removes block parameters that always take the same value across all incoming edges.
/// This mirrors Cranelift's constant-phi removal, but operates on IR block params.
pub fn eliminate_constant_block_params(func : Function) -> OptResult {
  let result = OptResult::new()
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
  for block in func.blocks {
    if block.terminator is Some(Jump(target, args)) {
      if args.length() == 0 {
        continue
      }
      if target < 0 || target >= block_idx.length() {
        continue
      }
      let target_i = block_idx[target]
      if target_i < 0 {
        continue
      }
      let target_block = func.blocks[target_i]
      let param_count = target_block.params.length()
      let arg_count = args.length()
      let count = if param_count < arg_count { param_count } else { arg_count }
      for i in 0..<count {
        let (formal, _) = target_block.params[i]
        if formal.id >= 0 &&
          formal.id < value_count &&
          state[formal.id] is Some(_) {
          propagation_pairs.push((formal.id, args[i].id))
        }
      }
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
      let old_params = block.params.copy()
      block.params.clear()
      for idx in keep {
        block.params.push(old_params[idx])
      }
      result.mark_changed()
    }
  }
  for block in func.blocks {
    if block.terminator is Some(Jump(target, args)) {
      let keep = if target >= 0 &&
        target < block_idx.length() &&
        block_idx[target] >= 0 &&
        block_idx[target] < params_to_keep.length() {
        params_to_keep[block_idx[target]]
      } else {
        []
      }
      if keep.length() != args.length() {
        let new_args : Array[Value] = []
        for idx in keep {
          if idx < args.length() {
            new_args.push(args[idx])
          }
        }
        block.terminator = Some(Jump(target, new_args))
        result.mark_changed()
      }
    }
  }
  let replace_values : Array[Value?] = Array::make(value_count, None)
  let values = build_value_array(func, value_count)
  for from_id, to_id in replace_ids {
    if to_id >= 0 && to_id < value_count && values[to_id] is Some(replacement) {
      replace_values[from_id] = Some(replacement)
    }
  }
  for block in func.blocks {
    for inst in block.instructions {
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
          let mut new_args : Array[Value]? = None
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
            block.terminator = Some(Jump(target, updated_args))
            result.mark_changed()
          }
        }
        Brz(cond, then_target, else_target) =>
          if cond.id >= 0 && cond.id < value_count {
            if replace_values[cond.id] is Some(resolved) &&
              resolved.id != cond.id {
              block.terminator = Some(Brz(resolved, then_target, else_target))
              result.mark_changed()
            }
          }
        Brnz(cond, then_target, else_target) =>
          if cond.id >= 0 && cond.id < value_count {
            if replace_values[cond.id] is Some(resolved) &&
              resolved.id != cond.id {
              block.terminator = Some(Brnz(resolved, then_target, else_target))
              result.mark_changed()
            }
          }
        BrTable(index, targets, default_target) =>
          if index.id >= 0 && index.id < value_count {
            if replace_values[index.id] is Some(resolved) &&
              resolved.id != index.id {
              block.terminator = Some(
                BrTable(resolved, targets, default_target),
              )
              result.mark_changed()
            }
          }
        Return(values) => {
          let mut new_values : Array[Value]? = None
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
            block.terminator = Some(Return(updated_values))
            result.mark_changed()
          }
        }
        Trap(_) => ()
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
pub fn eliminate_dead_block_params(func : Function) -> OptResult {
  let result = OptResult::new()

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
      let old_params = block.params.copy()
      block.params.clear()
      for idx in keep {
        block.params.push(old_params[idx])
      }
      result.mark_changed()
    }
  }

  // Update terminators - remove arguments corresponding to removed parameters
  for block in func.blocks {
    match block.terminator {
      Some(Jump(target, args)) => {
        let keep = if target >= 0 &&
          target < block_idx.length() &&
          block_idx[target] >= 0 &&
          block_idx[target] < params_to_keep.length() {
          params_to_keep[block_idx[target]]
        } else {
          []
        }
        if keep.length() != args.length() {
          let new_args : Array[Value] = []
          for idx in keep {
            if idx < args.length() {
              new_args.push(args[idx])
            }
          }
          block.terminator = Some(Jump(target, new_args))
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
  func : Function,
  block_idx : Array[Int],
) -> Array[Bool] {
  let value_count = func.next_value_id
  if value_count <= 0 {
    return []
  }
  let used = Array::make(value_count, false)
  let propagation_edges : Array[Array[Int]?] = Array::make(value_count, None)
  for block in func.blocks {
    if block.terminator is Some(Jump(target, args)) {
      if target >= 0 && target < block_idx.length() {
        let target_idx = block_idx[target]
        if target_idx < 0 {
          continue
        }
        let target_block = func.blocks[target_idx]
        let count = if target_block.params.length() < args.length() {
          target_block.params.length()
        } else {
          args.length()
        }
        for i in 0..<count {
          let (param_v, _) = target_block.params[i]
          if param_v.id < 0 || param_v.id >= value_count {
            continue
          }
          match propagation_edges[param_v.id] {
            Some(edges) => edges.push(args[i].id)
            None => propagation_edges[param_v.id] = Some([args[i].id])
          }
        }
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
    for inst in block.instructions {
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
        Trap(_) => ()
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
pub fn simplify_branches(func : Function) -> OptResult {
  let result = OptResult::new()
  // Build constant map from constant folding
  let constants : @hashmap.HashMap[Int, ConstValue] = HashMap([])
  for block in func.blocks {
    for inst in block.instructions {
      if inst.opcode is Iconst(v) && inst.first_result() is Some(r) {
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
        block.terminator = Some(Jump(target, []))
        result.mark_changed()
      } else if constants.get(cond.id) is Some(I64(v)) {
        let target = if v == 0L { then_target } else { else_target }
        block.terminator = Some(Jump(target, []))
        result.mark_changed()
      }
    } else if block.terminator is Some(Brnz(cond, then_target, else_target)) {
      if constants.get(cond.id) is Some(I32(v)) {
        // brnz: branch if not zero
        let target = if v != 0 { then_target } else { else_target }
        block.terminator = Some(Jump(target, []))
        result.mark_changed()
      } else if constants.get(cond.id) is Some(I64(v)) {
        let target = if v != 0L { then_target } else { else_target }
        block.terminator = Some(Jump(target, []))
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
        block.terminator = Some(Jump(target, []))
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
pub fn eliminate_unreachable_code(func : Function) -> OptResult {
  let result = OptResult::new()
  if func.blocks.length() == 0 {
    return result
  }
  // Mark reachable blocks using DFS from entry
  let reachable : @hashmap.HashMap[Int, Bool] = HashMap([])
  let worklist : Array[Int] = [0] // Start from entry block (block 0)
  while worklist.length() > 0 {
    let block_id = worklist.pop().unwrap()
    if reachable.get(block_id).unwrap_or(false) {
      continue
    }
    reachable.set(block_id, true)
    // Find the block and add successors to worklist
    for block in func.blocks {
      if block.id == block_id {
        if block.terminator is Some(term) {
          for succ in get_terminator_targets(term) {
            if !reachable.get(succ).unwrap_or(false) {
              worklist.push(succ)
            }
          }
        }
        break
      }
    }
  }
  // Remove unreachable blocks (iterate backwards to avoid index issues)
  let mut i = func.blocks.length() - 1
  while i >= 0 {
    let block = func.blocks[i]
    if !reachable.get(block.id).unwrap_or(false) {
      func.blocks.remove(i) |> ignore
      result.mark_changed()
    }
    i = i - 1
  }
  result
}

// ============ Basic Block Merging ============

///|
/// Basic Block Merging
/// Merges a block with its unique predecessor if the predecessor has only one successor
pub fn merge_blocks(func : Function) -> OptResult {
  let result = OptResult::new()
  if func.blocks.length() <= 1 {
    return result
  }
  // Build predecessor and successor counts
  let pred_count : @hashmap.HashMap[Int, Int] = HashMap([])
  let succ_count : @hashmap.HashMap[Int, Int] = HashMap([])
  let single_pred : @hashmap.HashMap[Int, Int] = HashMap([]) // block -> its single predecessor
  for block in func.blocks {
    pred_count.set(block.id, 0)
    succ_count.set(block.id, 0)
  }
  for block in func.blocks {
    if block.terminator is Some(term) {
      let targets = get_terminator_targets(term)
      succ_count.set(block.id, targets.length())
      for target in targets {
        let count = pred_count.get(target).unwrap_or(0)
        pred_count.set(target, count + 1)
        // Track the predecessor if this is the first one
        if count == 0 {
          single_pred.set(target, block.id)
        } else {
          // More than one predecessor, clear
          single_pred.remove(target)
        }
      }
    }
  }
  // Find mergeable pairs: pred has 1 successor, succ has 1 predecessor
  let to_merge : Array[(Int, Int)] = [] // (pred_id, succ_id)
  for block in func.blocks {
    if block.id == 0 {
      continue // Don't merge into entry block
    }
    let preds = pred_count.get(block.id).unwrap_or(0)
    if preds == 1 && single_pred.get(block.id) is Some(pred_id) {
      let succs = succ_count.get(pred_id).unwrap_or(0)
      if succs == 1 {
        // Check that the jump has no arguments (simple case)
        for pred_block in func.blocks {
          if pred_block.id == pred_id {
            if pred_block.terminator is Some(Jump(_, args)) &&
              args.length() == 0 {
              to_merge.push((pred_id, block.id))
            }
            break
          }
        }
      }
    }
  }
  // Perform merges
  for pair in to_merge {
    let (pred_id, succ_id) = pair
    let mut pred_block : Block? = None
    let mut succ_block : Block? = None
    let mut succ_idx = -1
    for i, block in func.blocks {
      if block.id == pred_id {
        pred_block = Some(block)
      }
      if block.id == succ_id {
        succ_block = Some(block)
        succ_idx = i
      }
    }
    if (pred_block, succ_block) is (Some(pred), Some(succ)) {
      // Append successor's instructions to predecessor
      for inst in succ.instructions {
        pred.instructions.push(inst)
      }
      // Take successor's terminator
      pred.terminator = succ.terminator
      // Remove successor block
      if succ_idx >= 0 {
        func.blocks.remove(succ_idx) |> ignore
        result.mark_changed()
      }
    }
  }
  result
}

// ============ Jump Threading ============

///|
fn block_arg_arrays_equal(lhs : Array[Value], rhs : Array[Value]) -> Bool {
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
  block_params : Array[(Value, Type)],
  incoming_args : Array[Value],
  outgoing_args : Array[Value],
) -> Array[Value]? {
  if block_params.length() != incoming_args.length() {
    return None
  }
  let param_to_arg : @hashmap.HashMap[Int, Value] = HashMap([])
  for i in 0..<block_params.length() {
    let (param, _) = block_params[i]
    param_to_arg.set(param.id, incoming_args[i])
  }
  let rewritten : Array[Value] = []
  for arg in outgoing_args {
    rewritten.push(param_to_arg.get(arg.id).unwrap_or(arg))
  }
  Some(rewritten)
}

///|
fn resolve_jump_target_with_args(
  target : Int,
  args : Array[Value],
  func : Function,
  block_idx : @hashmap.HashMap[Int, Int],
) -> (Int, Array[Value]) {
  let visited : @hashmap.HashMap[Int, Bool] = HashMap([])
  let mut current_target = target
  let mut current_args = args
  let mut done = false
  while !done {
    if visited.get(current_target).unwrap_or(false) {
      break
    }
    visited.set(current_target, true)
    let block = match block_idx.get(current_target) {
      Some(idx) => func.blocks[idx]
      None => break
    }
    if block.instructions.length() != 0 {
      break
    }
    match block.terminator {
      Some(Jump(next_target, next_args)) =>
        match
          rewrite_jump_args_through_block(block.params, current_args, next_args) {
          Some(rewritten_args) => {
            current_target = next_target
            current_args = rewritten_args
          }
          None => done = true
        }
      _ => done = true
    }
  }
  (current_target, current_args)
}

///|
/// Jump Threading
/// Bypasses blocks that only contain an unconditional jump
pub fn thread_jumps(func : Function) -> OptResult {
  let result = OptResult::new()
  let block_idx : @hashmap.HashMap[Int, Int] = HashMap([])
  for i, block in func.blocks {
    block_idx.set(block.id, i)
  }
  // Update terminators to skip intermediate jump blocks
  for block in func.blocks {
    match block.terminator {
      Some(Jump(target, args)) => {
        let (final_target, final_args) = resolve_jump_target_with_args(
          target, args, func, block_idx,
        )
        if final_target != target || !block_arg_arrays_equal(final_args, args) {
          block.terminator = Some(Jump(final_target, final_args))
          result.mark_changed()
        }
      }
      Some(Brz(cond, then_target, else_target)) => {
        let (resolved_then, then_args) = resolve_jump_target_with_args(
          then_target,
          [],
          func,
          block_idx,
        )
        let (resolved_else, else_args) = resolve_jump_target_with_args(
          else_target,
          [],
          func,
          block_idx,
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
          block.terminator = Some(Brz(cond, new_then, new_else))
          result.mark_changed()
        }
      }
      Some(Brnz(cond, then_target, else_target)) => {
        let (resolved_then, then_args) = resolve_jump_target_with_args(
          then_target,
          [],
          func,
          block_idx,
        )
        let (resolved_else, else_args) = resolve_jump_target_with_args(
          else_target,
          [],
          func,
          block_idx,
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
          block.terminator = Some(Brnz(cond, new_then, new_else))
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
          block.terminator = Some(BrTable(index, new_targets, new_default))
          result.mark_changed()
        }
      }
      _ => ()
    }
  }
  result
}
