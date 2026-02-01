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
fn build_value_map(func : Function) -> @hashmap.HashMap[Int, Value] {
  let values : @hashmap.HashMap[Int, Value] = @hashmap.new()
  for param in func.params {
    let (v, _) = param
    values.set(v.id, v)
  }
  for block in func.blocks {
    for param in block.params {
      let (v, _) = param
      values.set(v.id, v)
    }
    for inst in block.instructions {
      for result in inst.results {
        values.set(result.id, result)
      }
    }
  }
  values
}

///|
fn resolve_replacement(
  v : Value,
  replace_map : @hashmap.HashMap[Int, Int],
  value_map : @hashmap.HashMap[Int, Value],
) -> Value {
  let mut current_id = v.id
  let mut steps = 0
  while steps < 1024 {
    match replace_map.get(current_id) {
      Some(next_id) => {
        if next_id == current_id {
          break
        }
        current_id = next_id
        steps = steps + 1
      }
      None => break
    }
  }
  if current_id == v.id {
    v
  } else {
    value_map.get(current_id).unwrap_or(v)
  }
}

///|
/// Constant Block Parameter Elimination
/// Removes block parameters that always take the same value across all incoming edges.
/// This mirrors Cranelift's constant-phi removal, but operates on IR block params.
pub fn eliminate_constant_block_params(func : Function) -> OptResult {
  let result = OptResult::new()
  let cfg = CFG::build(func)
  let rpo = cfg.reverse_postorder()
  if rpo.length() == 0 {
    return result
  }
  let entry_id = rpo[0]
  let block_idx : @hashmap.HashMap[Int, Int] = @hashmap.new()
  for i, block in func.blocks {
    block_idx.set(block.id, i)
  }
  let state : @hashmap.HashMap[Int, PhiAbstractValue] = @hashmap.new()
  let mut has_params = false
  for block in func.blocks {
    if block.id == entry_id {
      continue
    }
    for param in block.params {
      let (v, _) = param
      state.set(v.id, PhiAbstractValue::None)
      has_params = true
    }
  }
  if !has_params {
    return result
  }
  let mut changed = true
  let mut iterations = 0
  let max_iterations = 512
  while changed && iterations < max_iterations {
    changed = false
    iterations = iterations + 1
    for block_id in rpo {
      let block = match block_idx.get(block_id) {
        Some(idx) => func.blocks[idx]
        None => continue
      }
      match block.terminator {
        Some(Jump(target, args)) => {
          if args.length() == 0 {
            continue
          }
          let target_block = match block_idx.get(target) {
            Some(idx) => func.blocks[idx]
            None => continue
          }
          let param_count = target_block.params.length()
          let arg_count = args.length()
          let count = if param_count < arg_count {
            param_count
          } else {
            arg_count
          }
          for i in 0..<count {
            let (formal, _) = target_block.params[i]
            if state.get(formal.id) is None {
              continue
            }
            let actual = args[i]
            let actual_absval = match state.get(actual.id) {
              Some(absval) => absval
              None => PhiAbstractValue::One(actual.id)
            }
            let old_absval = state
              .get(formal.id)
              .unwrap_or(PhiAbstractValue::None)
            let new_absval = old_absval.join(actual_absval)
            if new_absval != old_absval {
              state.set(formal.id, new_absval)
              changed = true
            }
          }
        }
        _ => ()
      }
    }
  }
  let params_to_keep : @hashmap.HashMap[Int, Array[Int]] = @hashmap.new()
  let replace_map : @hashmap.HashMap[Int, Int] = @hashmap.new()
  let mut will_change = false
  for block in func.blocks {
    let keep : Array[Int] = []
    for i, param in block.params {
      let (v, _) = param
      match state.get(v.id) {
        Some(PhiAbstractValue::One(replacement_id)) => {
          replace_map.set(v.id, replacement_id)
          will_change = true
        }
        _ => keep.push(i)
      }
    }
    params_to_keep.set(block.id, keep)
  }
  if !will_change {
    return result
  }
  for block in func.blocks {
    let keep = params_to_keep.get(block.id).unwrap_or([])
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
    match block.terminator {
      Some(Jump(target, args)) => {
        let keep = params_to_keep.get(target).unwrap_or([])
        if keep.length() != args.length() {
          let new_args : Array[Value] = []
          for idx in keep {
            if idx < args.length() {
              new_args.push(args[idx])
            }
          }
          block.terminator = Some(Terminator::Jump(target, new_args))
          result.mark_changed()
        }
      }
      _ => ()
    }
  }
  let value_map = build_value_map(func)
  for block in func.blocks {
    for inst in block.instructions {
      let mut needs_update = false
      let new_operands : Array[Value] = []
      for op in inst.operands {
        let resolved = resolve_replacement(op, replace_map, value_map)
        if resolved.id != op.id {
          needs_update = true
        }
        new_operands.push(resolved)
      }
      if needs_update {
        inst.operands.clear()
        for op in new_operands {
          inst.operands.push(op)
        }
        result.mark_changed()
      }
    }
    if block.terminator is Some(term) {
      match term {
        Jump(target, args) => {
          let mut needs_update = false
          let new_args : Array[Value] = []
          for arg in args {
            let resolved = resolve_replacement(arg, replace_map, value_map)
            if resolved.id != arg.id {
              needs_update = true
            }
            new_args.push(resolved)
          }
          if needs_update {
            block.terminator = Some(Terminator::Jump(target, new_args))
            result.mark_changed()
          }
        }
        Brz(cond, then_target, else_target) => {
          let resolved = resolve_replacement(cond, replace_map, value_map)
          if resolved.id != cond.id {
            block.terminator = Some(
              Terminator::Brz(resolved, then_target, else_target),
            )
            result.mark_changed()
          }
        }
        Brnz(cond, then_target, else_target) => {
          let resolved = resolve_replacement(cond, replace_map, value_map)
          if resolved.id != cond.id {
            block.terminator = Some(
              Terminator::Brnz(resolved, then_target, else_target),
            )
            result.mark_changed()
          }
        }
        BrTable(index, targets, default_target) => {
          let resolved = resolve_replacement(index, replace_map, value_map)
          if resolved.id != index.id {
            block.terminator = Some(
              Terminator::BrTable(resolved, targets, default_target),
            )
            result.mark_changed()
          }
        }
        Return(values) => {
          let mut needs_update = false
          let new_values : Array[Value] = []
          for value in values {
            let resolved = resolve_replacement(value, replace_map, value_map)
            if resolved.id != value.id {
              needs_update = true
            }
            new_values.push(resolved)
          }
          if needs_update {
            block.terminator = Some(Terminator::Return(new_values))
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
  let used_params = compute_used_block_params(func)

  // Track which parameter indices to keep for each block
  let params_to_keep : @hashmap.HashMap[Int, Array[Int]] = @hashmap.new()
  for block in func.blocks {
    let keep : Array[Int] = []
    for i, param in block.params {
      let (v, _) = param
      if used_params.get(v.id).unwrap_or(false) {
        keep.push(i)
      }
    }
    params_to_keep.set(block.id, keep)
  }

  // Check if any parameters will be removed
  let mut will_change = false
  for block in func.blocks {
    let keep = params_to_keep.get(block.id).unwrap_or([])
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
    let keep = params_to_keep.get(block.id).unwrap_or([])
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
        let keep = params_to_keep.get(target).unwrap_or([])
        if keep.length() != args.length() {
          let new_args : Array[Value] = []
          for idx in keep {
            if idx < args.length() {
              new_args.push(args[idx])
            }
          }
          block.terminator = Some(Terminator::Jump(target, new_args))
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
fn compute_used_block_params(func : Function) -> @hashmap.HashMap[Int, Bool] {
  let used : @hashmap.HashMap[Int, Bool] = @hashmap.new()

  // Initialize: all function parameters are used (they come from caller)
  for param in func.params {
    let (v, _) = param
    used.set(v.id, true)
  }

  // First pass: mark values used directly in instructions
  for block in func.blocks {
    for inst in block.instructions {
      for op in inst.operands {
        used.set(op.id, true)
      }
    }
    // Also count uses in terminators (excluding jump args; handled by dataflow)
    if block.terminator is Some(term) {
      match term {
        Jump(_, _) => ()
        Brz(cond, _, _) | Brnz(cond, _, _) => used.set(cond.id, true)
        BrTable(index, _, _) => used.set(index.id, true)
        Return(args) =>
          for v in args {
            used.set(v.id, true)
          }
        Trap(_) => ()
      }
    }
  }

  // Iterative dataflow: propagate "used" backwards through jump arguments
  // If a block parameter is used, the corresponding jump argument is also used
  let mut changed = true
  while changed {
    changed = false
    for block in func.blocks {
      match block.terminator {
        Some(Jump(target, args)) =>
          // Find target block and its parameters
          for target_block in func.blocks {
            if target_block.id == target {
              // For each parameter-argument pair
              for i, param in target_block.params {
                let (param_v, _) = param
                if i < args.length() {
                  let arg = args[i]
                  // If target param is used, mark the argument as used
                  if used.get(param_v.id).unwrap_or(false) &&
                    !used.get(arg.id).unwrap_or(false) {
                    used.set(arg.id, true)
                    changed = true
                  }
                }
              }
              break
            }
          }
        _ => ()
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
  let constants : @hashmap.HashMap[Int, ConstValue] = @hashmap.new()
  for block in func.blocks {
    for inst in block.instructions {
      if inst.opcode is Iconst(v) && inst.first_result() is Some(r) {
        if r.ty is I32 {
          constants.set(r.id, ConstValue::I32(v.to_int()))
        } else {
          constants.set(r.id, ConstValue::I64(v))
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
        block.terminator = Some(Terminator::Jump(target, []))
        result.mark_changed()
      } else if constants.get(cond.id) is Some(I64(v)) {
        let target = if v == 0L { then_target } else { else_target }
        block.terminator = Some(Terminator::Jump(target, []))
        result.mark_changed()
      }
    } else if block.terminator is Some(Brnz(cond, then_target, else_target)) {
      if constants.get(cond.id) is Some(I32(v)) {
        // brnz: branch if not zero
        let target = if v != 0 { then_target } else { else_target }
        block.terminator = Some(Terminator::Jump(target, []))
        result.mark_changed()
      } else if constants.get(cond.id) is Some(I64(v)) {
        let target = if v != 0L { then_target } else { else_target }
        block.terminator = Some(Terminator::Jump(target, []))
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
        block.terminator = Some(Terminator::Jump(target, []))
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
  let reachable : @hashmap.HashMap[Int, Bool] = @hashmap.new()
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
  let pred_count : @hashmap.HashMap[Int, Int] = @hashmap.new()
  let succ_count : @hashmap.HashMap[Int, Int] = @hashmap.new()
  let single_pred : @hashmap.HashMap[Int, Int] = @hashmap.new() // block -> its single predecessor
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
/// Jump Threading
/// Bypasses blocks that only contain an unconditional jump
pub fn thread_jumps(func : Function) -> OptResult {
  let result = OptResult::new()
  // Find blocks that are just jumps (no instructions, just a jump terminator)
  let jump_targets : @hashmap.HashMap[Int, Int] = @hashmap.new() // block -> final target
  for block in func.blocks {
    if block.instructions.length() == 0 &&
      block.params.length() == 0 &&
      block.terminator is Some(Jump(target, args)) &&
      args.length() == 0 {
      jump_targets.set(block.id, target)
    }
  }
  // Follow jump chains to find final target
  fn resolve_target(
    block_id : Int,
    jump_targets : @hashmap.HashMap[Int, Int],
    visited : @hashmap.HashMap[Int, Bool],
  ) -> Int {
    if visited.get(block_id).unwrap_or(false) {
      return block_id // Cycle detected
    }
    match jump_targets.get(block_id) {
      Some(target) => {
        visited.set(block_id, true)
        resolve_target(target, jump_targets, visited)
      }
      None => block_id
    }
  }
  // Update terminators to skip intermediate jump blocks
  for block in func.blocks {
    match block.terminator {
      Some(Jump(target, args)) =>
        if args.length() == 0 {
          let visited : @hashmap.HashMap[Int, Bool] = @hashmap.new()
          let final_target = resolve_target(target, jump_targets, visited)
          if final_target != target {
            block.terminator = Some(Terminator::Jump(final_target, []))
            result.mark_changed()
          }
        }
      Some(Brz(cond, then_target, else_target)) => {
        let visited1 : @hashmap.HashMap[Int, Bool] = @hashmap.new()
        let visited2 : @hashmap.HashMap[Int, Bool] = @hashmap.new()
        let new_then = resolve_target(then_target, jump_targets, visited1)
        let new_else = resolve_target(else_target, jump_targets, visited2)
        if new_then != then_target || new_else != else_target {
          block.terminator = Some(Terminator::Brz(cond, new_then, new_else))
          result.mark_changed()
        }
      }
      Some(Brnz(cond, then_target, else_target)) => {
        let visited1 : @hashmap.HashMap[Int, Bool] = @hashmap.new()
        let visited2 : @hashmap.HashMap[Int, Bool] = @hashmap.new()
        let new_then = resolve_target(then_target, jump_targets, visited1)
        let new_else = resolve_target(else_target, jump_targets, visited2)
        if new_then != then_target || new_else != else_target {
          block.terminator = Some(Terminator::Brnz(cond, new_then, new_else))
          result.mark_changed()
        }
      }
      Some(BrTable(index, targets, default_target)) => {
        let new_targets : Array[Int] = []
        let mut any_changed = false
        for t in targets {
          let visited : @hashmap.HashMap[Int, Bool] = @hashmap.new()
          let new_t = resolve_target(t, jump_targets, visited)
          new_targets.push(new_t)
          if new_t != t {
            any_changed = true
          }
        }
        let visited_default : @hashmap.HashMap[Int, Bool] = @hashmap.new()
        let new_default = resolve_target(
          default_target, jump_targets, visited_default,
        )
        if new_default != default_target {
          any_changed = true
        }
        if any_changed {
          block.terminator = Some(
            Terminator::BrTable(index, new_targets, new_default),
          )
          result.mark_changed()
        }
      }
      _ => ()
    }
  }
  result
}
