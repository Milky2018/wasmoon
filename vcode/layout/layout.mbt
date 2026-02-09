// Block layout optimization with loop rotation
// Reorders blocks to make back edges fall through, improving branch prediction

///|
/// Compute an optimized block ordering for the function
/// Returns an array of block indices in the new order
pub fn layout_blocks(func : @regalloc.VCodeFunction) -> Array[Int] {
  let n = func.get_blocks().length()
  if n <= 1 {
    // Nothing to optimize for 0 or 1 blocks
    let order : Array[Int] = []
    for i in 0..<n {
      order.push(i)
    }
    return order
  }
  let cfg = VCodeCFG::build(func)
  let loops = cfg.find_loops()

  // Track which blocks have been placed
  let placed : Array[Bool] = Array::make(n, false)
  let order : Array[Int] = []

  // Sort loops by header block ID (process outer loops first, then inner)
  // This ensures proper nesting in the layout
  loops.sort_by(fn(a, b) { a.header - b.header })

  // Process entry block first
  if n > 0 {
    place_block(0, placed, order)
  }

  // Process each loop with rotation
  for lp in loops {
    if !placed[lp.header] {
      place_rotated_loop(lp, cfg, placed, order)
    }
  }

  // Place any remaining unplaced blocks (in original order)
  for i in 0..<n {
    if !placed[i] {
      place_block(i, placed, order)
    }
  }
  order
}

///|
/// Place a single block if not already placed
fn place_block(
  block_id : Int,
  placed : Array[Bool],
  order : Array[Int],
) -> Unit {
  if !placed[block_id] {
    placed[block_id] = true
    order.push(block_id)
  }
}

///|
/// Place a loop with rotation to make back edge fall through
///
/// Before rotation:
///   header -> body -> ... -> latch -> header (back edge is a jump)
///
/// After rotation:
///   body -> ... -> latch -> header -> exit (back edge & exit fall through!)
///
/// The key insight: if we place latch immediately before header,
/// the back edge (latch -> header) becomes a fall through.
/// Additionally, placing exit blocks after header makes exit branch fall through.
fn place_rotated_loop(
  lp : VCodeLoop,
  cfg : VCodeCFG,
  placed : Array[Bool],
  order : Array[Int],
) -> Unit {
  // For simple loops: place body blocks, then latch, then header, then exits
  // This makes both the back edge and exit branch fall through

  // First, find blocks that are in the loop but not header or latch
  let body_blocks : Array[Int] = []
  for block_id in lp.body {
    if block_id != lp.header && block_id != lp.latch {
      body_blocks.push(block_id)
    }
  }

  // Sort body blocks to maintain some locality
  body_blocks.sort_by(fn(a, b) { a - b })

  // Place order: body blocks -> latch -> header
  // This way latch falls through to header
  for block_id in body_blocks {
    place_block(block_id, placed, order)
  }

  // Place latch (if different from header)
  if lp.latch != lp.header {
    place_block(lp.latch, placed, order)
  }

  // Place header last in the loop
  place_block(lp.header, placed, order)

  // Place exit blocks right after header so exit branch can fall through
  // Exit blocks are successors of header that are not in the loop body
  for succ in cfg.succs[lp.header] {
    let mut is_in_loop = false
    for block_id in lp.body {
      if block_id == succ {
        is_in_loop = true
        break
      }
    }
    if !is_in_loop {
      place_block(succ, placed, order)
    }
  }
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
/// Resolve a jump target through chains of trivial jump-only blocks.
///
/// A block is considered a trivial jump block iff:
/// - it has no instructions;
/// - it has no block parameters;
/// - its terminator is `Jump(next, [])`.
///
/// This mirrors Cranelift MachBuffer branch-threading for empty jump blocks.
fn resolve_threaded_target(
  start_target : Int,
  func : @regalloc.VCodeFunction,
  block_idx_by_id : Map[Int, Int],
) -> Int {
  let mut current = start_target
  let visited : Map[Int, Bool] = {}
  let blocks = func.get_blocks()
  while true {
    if visited.get(current).unwrap_or(false) {
      // Cycle in trivial-jump chain; keep original target stable.
      return start_target
    }
    visited.set(current, true)
    match block_idx_by_id.get(current) {
      Some(block_idx) => {
        let block = blocks[block_idx]
        if block.insts.length() == 0 && block.params.length() == 0 {
          if block.terminator is Some(@instr.Jump(next, args)) &&
            args.length() == 0 &&
            next != current {
            current = next
            continue
          }
        }
        return current
      }
      None => return current
    }
  }
  // Unreachable, retained for exhaustiveness.
  start_target
}

///|
/// Rewrite one terminator by threading successors through trivial jump blocks.
fn rewrite_terminator_targets(
  term : @instr.VCodeTerminator,
  func : @regalloc.VCodeFunction,
  block_idx_by_id : Map[Int, Int],
) -> (@instr.VCodeTerminator, Bool) {
  match term {
    @instr.Jump(target, args) =>
      if args.length() == 0 {
        let resolved = resolve_threaded_target(target, func, block_idx_by_id)
        (@instr.Jump(resolved, args), resolved != target)
      } else {
        (term, false)
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
