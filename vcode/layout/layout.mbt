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
  let order = layout_blocks(func)
  reorder_blocks(func, order)
}
