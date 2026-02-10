// Block layout optimization.
// Keeps branch threading, and uses Cranelift-style CFG reverse-postorder
// ordering to prefer straight-line fallthrough on dominator-tree order.

///|
/// Compute an optimized block ordering for the function
/// Returns an array of block indices in the new order
pub fn layout_blocks(func : @regalloc.VCodeFunction) -> Array[Int] {
  let blocks = func.get_blocks()
  let n = blocks.length()
  if n <= 1 {
    let order : Array[Int] = []
    for i in 0..<n {
      order.push(i)
    }
    return order
  }

  let cfg = VCodeCFG::build(func)
  let rpo = cfg.reverse_postorder()
  let block_idx_by_id : Map[Int, Int] = {}
  for i, block in blocks {
    block_idx_by_id.set(block.id, i)
  }

  // Place reachable blocks in CFG RPO order, then append unreachable blocks
  // in stable original order.
  let placed : Array[Bool] = Array::make(n, false)
  let order : Array[Int] = []
  for block_id in rpo {
    if block_id < 0 || block_id >= n || placed[block_id] {
      continue
    }

    // Follow jump-only, single-predecessor chains to maximize fallthrough,
    // similar in effect to Cranelift's late branch-threading in MachBuffer.
    let mut current = block_id
    while !placed[current] {
      placed[current] = true
      order.push(current)
      match blocks[current].terminator {
        Some(Jump(target, _args)) =>
          match block_idx_by_id.get(target) {
            Some(next_idx) =>
              if next_idx == current ||
                placed[next_idx] ||
                cfg.preds[next_idx].length() != 1 {
                break
              } else {
                current = next_idx
                continue
              }
            None => break
          }
        _ => break
      }
    }
  }
  for i in 0..<n {
    if !placed[i] {
      placed[i] = true
      order.push(i)
    }
  }
  order
}

///|
/// Build a map from block ID to block index in the block array.
fn build_block_index_map(func : @regalloc.VCodeFunction) -> Map[Int, Int] {
  let block_idx_by_id : Map[Int, Int] = {}
  for i, block in func.get_blocks() {
    block_idx_by_id.set(block.id, i)
  }
  block_idx_by_id
}

///|
/// Substitute forwarded jump arguments through a block-parameter mapping.
///
/// Returns `None` when a forwarded virtual value is not a block parameter of
/// the forwarded block.
fn substitute_forwarded_args(
  forwarded_args : Array[@abi.Reg],
  params : Array[@abi.VReg],
  incoming_args : Array[@abi.Reg],
) -> Array[@abi.Reg]? {
  let rewritten : Array[@abi.Reg] = []
  for arg in forwarded_args {
    match arg {
      Physical(_) => rewritten.push(arg)
      Virtual(vreg) => {
        let mut mapped : @abi.Reg? = None
        for i, param in params {
          if param.id == vreg.id {
            mapped = Some(incoming_args[i])
            break
          }
        }
        match mapped {
          Some(value) => rewritten.push(value)
          None => return None
        }
      }
    }
  }
  Some(rewritten)
}

///|
/// Resolve a jump target through chains of trivial jump-only blocks.
///
/// A block is considered a trivial jump block iff:
/// - it has no instructions;
/// - its terminator is `Jump(next, next_args)`;
/// - `next_args` can be expressed as a forwarding of this block's parameters.
///
/// This mirrors Cranelift MachBuffer branch-threading for empty jump blocks.
fn resolve_threaded_jump(
  start_target : Int,
  start_args : Array[@abi.Reg],
  func : @regalloc.VCodeFunction,
  block_idx_by_id : Map[Int, Int],
) -> (Int, Array[@abi.Reg], Bool) {
  let mut current = start_target
  let mut current_args = start_args.copy()
  let visited : Map[Int, Bool] = {}
  let blocks = func.get_blocks()
  let mut changed = false
  while true {
    if visited.get(current).unwrap_or(false) {
      // Cycle in trivial-jump chain; keep original target stable.
      return (start_target, start_args, false)
    }
    visited.set(current, true)
    match block_idx_by_id.get(current) {
      Some(block_idx) => {
        let block = blocks[block_idx]
        if block.insts.length() == 0 {
          if block.terminator is Some(@instr.Jump(next, next_args)) &&
            next != current &&
            block.params.length() == current_args.length() {
            if substitute_forwarded_args(next_args, block.params, current_args)
              is Some(mapped) {
              current = next
              current_args = mapped
              changed = true
              continue
            }
          }
        }
        return (current, current_args, changed)
      }
      None => return (current, current_args, changed)
    }
  }
  // Unreachable, retained for exhaustiveness.
  (start_target, start_args, false)
}

///|
/// Resolve a branch target through trivial jump chains when no block arguments
/// are available.
fn resolve_threaded_target(
  start_target : Int,
  func : @regalloc.VCodeFunction,
  block_idx_by_id : Map[Int, Int],
) -> Int {
  let (target, _, _) = resolve_threaded_jump(
    start_target,
    [],
    func,
    block_idx_by_id,
  )
  target
}

///|
/// Rewrite one terminator by threading successors through trivial jump blocks.
fn rewrite_terminator_targets(
  term : @instr.VCodeTerminator,
  func : @regalloc.VCodeFunction,
  block_idx_by_id : Map[Int, Int],
) -> (@instr.VCodeTerminator, Bool) {
  match term {
    @instr.Jump(target, args) => {
      let (resolved_target, resolved_args, changed) = resolve_threaded_jump(
        target, args, func, block_idx_by_id,
      )
      (@instr.Jump(resolved_target, resolved_args), changed)
    }
    @instr.Branch(cond, then_b, else_b) => {
      let new_then = resolve_threaded_target(then_b, func, block_idx_by_id)
      let new_else = resolve_threaded_target(else_b, func, block_idx_by_id)
      if new_then == new_else {
        (@instr.Jump(new_then, []), true)
      } else {
        (
          @instr.Branch(cond, new_then, new_else),
          new_then != then_b || new_else != else_b,
        )
      }
    }
    @instr.BranchCmp(lhs, rhs, cond, is_64, then_b, else_b) => {
      let new_then = resolve_threaded_target(then_b, func, block_idx_by_id)
      let new_else = resolve_threaded_target(else_b, func, block_idx_by_id)
      if new_then == new_else {
        (@instr.Jump(new_then, []), true)
      } else {
        (
          @instr.BranchCmp(lhs, rhs, cond, is_64, new_then, new_else),
          new_then != then_b || new_else != else_b,
        )
      }
    }
    @instr.BranchZero(reg, is_nonzero, is_64, then_b, else_b) => {
      let new_then = resolve_threaded_target(then_b, func, block_idx_by_id)
      let new_else = resolve_threaded_target(else_b, func, block_idx_by_id)
      if new_then == new_else {
        (@instr.Jump(new_then, []), true)
      } else {
        (
          @instr.BranchZero(reg, is_nonzero, is_64, new_then, new_else),
          new_then != then_b || new_else != else_b,
        )
      }
    }
    @instr.BranchCmpImm(lhs, imm, cond, is_64, then_b, else_b) => {
      let new_then = resolve_threaded_target(then_b, func, block_idx_by_id)
      let new_else = resolve_threaded_target(else_b, func, block_idx_by_id)
      if new_then == new_else {
        (@instr.Jump(new_then, []), true)
      } else {
        (
          @instr.BranchCmpImm(lhs, imm, cond, is_64, new_then, new_else),
          new_then != then_b || new_else != else_b,
        )
      }
    }
    @instr.BrTable(index, targets, default) => {
      let new_targets : Array[Int] = []
      let mut changed = false
      for t in targets {
        let nt = resolve_threaded_target(t, func, block_idx_by_id)
        if nt != t {
          changed = true
        }
        new_targets.push(nt)
      }
      let new_default = resolve_threaded_target(default, func, block_idx_by_id)
      if new_default != default {
        changed = true
      }
      // If all targets collapse to one, this br_table is equivalent to jump.
      let mut all_same = true
      let pivot = if new_targets.length() > 0 {
        new_targets[0]
      } else {
        new_default
      }
      for t in new_targets {
        if t != pivot {
          all_same = false
          break
        }
      }
      if all_same && new_default == pivot {
        (@instr.Jump(pivot, []), true)
      } else {
        (@instr.BrTable(index, new_targets, new_default), changed)
      }
    }
    @instr.Return(_) | @instr.Trap(_) => (term, false)
  }
}

///|
/// Thread trivial jump blocks across the function terminators to reduce
/// branch-to-branch chains before final code emission.
fn thread_trivial_jumps(
  func : @regalloc.VCodeFunction,
) -> @regalloc.VCodeFunction {
  let blocks = func.get_blocks()
  if blocks.length() == 0 {
    return func
  }

  // Iterate to fixed point so newly-created jump-only blocks can be threaded too.
  for _ in 0..<blocks.length() {
    let block_idx_by_id = build_block_index_map(func)
    let mut changed = false
    for block in blocks {
      if block.terminator is Some(term) {
        let (new_term, did_change) = rewrite_terminator_targets(
          term, func, block_idx_by_id,
        )
        if did_change {
          block.set_terminator(new_term)
          changed = true
        }
      }
    }
    if !changed {
      break
    }
  }
  func
}

///|
/// Reorder blocks in a function according to the computed layout
/// Returns a new function with blocks in the specified order
pub fn reorder_blocks(
  func : @regalloc.VCodeFunction,
  order : Array[Int],
) -> @regalloc.VCodeFunction {
  let blocks = func.get_blocks()

  // Check if reordering is actually needed
  let mut needs_reorder = false
  for i, block_idx in order {
    if block_idx != i {
      needs_reorder = true
      break
    }
  }
  if !needs_reorder {
    return func
  }

  // Create new function with reordered blocks
  let new_func = func.clone_base()
  new_func.set_num_spill_slots(func.get_num_spill_slots())

  // Copy params
  for param in func.get_params() {
    new_func.push_param(param)
  }

  // Copy result types
  for rt in func.get_result_types() {
    new_func.add_result_type(rt)
  }

  // Add blocks in new order
  for block_idx in order {
    new_func.get_blocks().push(blocks[block_idx])
  }

  // Copy param pregs
  for preg in func.get_param_pregs() {
    new_func.add_param_preg(preg)
  }
  new_func
}

///|
/// Optimize block layout for a function
/// This is the main entry point for the layout optimization pass
pub fn optimize_layout(
  func : @regalloc.VCodeFunction,
) -> @regalloc.VCodeFunction {
  // First pass: simplify branch targets on the original CFG.
  let threaded = thread_trivial_jumps(func)
  // Then reorder for fall-through opportunities.
  let order = layout_blocks(threaded)
  let reordered = reorder_blocks(threaded, order)
  // Final pass: re-thread after reordering (some branches become collapsible).
  thread_trivial_jumps(reordered)
}
