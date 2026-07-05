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
fn reg_class_tag(class : @abi.RegClass) -> Int {
  match class {
    Int => 0
    Float32 => 1
    Float64 => 2
    Vector => 3
  }
}

///|
fn reg_class_from_tag(tag : Int) -> @abi.RegClass {
  match tag {
    1 => Float32
    2 => Float64
    3 => Vector
    _ => Int
  }
}

///|
fn reg_to_thread_arg(reg : @abi.Reg) -> @core_regalloc.ThreadArg {
  match reg {
    Physical(preg) => PhysicalArg(preg.index, reg_class_tag(preg.class))
    Virtual(vreg) => VirtualArg(vreg.id, reg_class_tag(vreg.class))
  }
}

///|
fn thread_arg_to_reg(arg : @core_regalloc.ThreadArg) -> @abi.Reg {
  match arg {
    PhysicalArg(index, class_tag) =>
      Physical({ index, class: reg_class_from_tag(class_tag) })
    VirtualArg(id, class_tag) =>
      Virtual({ id, class: reg_class_from_tag(class_tag) })
  }
}

///|
fn regs_to_thread_args(
  args : Array[@abi.Reg],
) -> Array[@core_regalloc.ThreadArg] {
  let out : Array[@core_regalloc.ThreadArg] = []
  for arg in args {
    out.push(reg_to_thread_arg(arg))
  }
  out
}

///|
fn thread_args_to_regs(
  args : Array[@core_regalloc.ThreadArg],
) -> Array[@abi.Reg] {
  let out : Array[@abi.Reg] = []
  for arg in args {
    out.push(thread_arg_to_reg(arg))
  }
  out
}

///|
fn build_thread_blocks(
  func : @regalloc.VCodeFunction,
) -> Array[@core_regalloc.ThreadBlock] {
  let blocks = func.get_blocks()
  let out : Array[@core_regalloc.ThreadBlock] = []
  for block in blocks {
    let params : Array[Int] = []
    for param in block.params {
      params.push(param.id)
    }
    let mut target : Int? = None
    let target_args : Array[@core_regalloc.ThreadArg] = []
    if block.terminator is Some(Jump(next, next_args)) {
      target = Some(next)
      for arg in next_args {
        target_args.push(reg_to_thread_arg(arg))
      }
    }
    out.push({
      id: block.id,
      params,
      target,
      target_args,
      is_empty: block.insts.length() == 0,
    })
  }
  out
}

///|
fn resolve_threaded_jump(
  start_target : Int,
  start_args : Array[@abi.Reg],
  thread_blocks : Array[@core_regalloc.ThreadBlock],
) -> (Int, Array[@abi.Reg], Bool) {
  let resolved = @core_regalloc.resolve_threaded_jump(
    thread_blocks,
    start_target,
    regs_to_thread_args(start_args),
  )
  (resolved.target, thread_args_to_regs(resolved.args), resolved.changed)
}

///|
/// Resolve a branch target through trivial jump chains when no block arguments
/// are available.
fn resolve_threaded_target(
  start_target : Int,
  thread_blocks : Array[@core_regalloc.ThreadBlock],
) -> Int {
  let (target, _, _) = resolve_threaded_jump(start_target, [], thread_blocks)
  target
}

///|
/// Rewrite one terminator by threading successors through trivial jump blocks.
fn rewrite_terminator_targets(
  term : @instr.VCodeTerminator,
  thread_blocks : Array[@core_regalloc.ThreadBlock],
) -> (@instr.VCodeTerminator, Bool) {
  match term {
    Jump(target, args) => {
      let (resolved_target, resolved_args, changed) = resolve_threaded_jump(
        target, args, thread_blocks,
      )
      (Jump(resolved_target, resolved_args), changed)
    }
    Branch(cond, then_b, else_b) => {
      let new_then = resolve_threaded_target(then_b, thread_blocks)
      let new_else = resolve_threaded_target(else_b, thread_blocks)
      if new_then == new_else {
        (Jump(new_then, []), true)
      } else {
        (
          Branch(cond, new_then, new_else),
          new_then != then_b || new_else != else_b,
        )
      }
    }
    BranchCmp(lhs, rhs, cond, is_64, then_b, else_b) => {
      let new_then = resolve_threaded_target(then_b, thread_blocks)
      let new_else = resolve_threaded_target(else_b, thread_blocks)
      if new_then == new_else {
        (Jump(new_then, []), true)
      } else {
        (
          BranchCmp(lhs, rhs, cond, is_64, new_then, new_else),
          new_then != then_b || new_else != else_b,
        )
      }
    }
    BranchZero(reg, is_nonzero, is_64, then_b, else_b) => {
      let new_then = resolve_threaded_target(then_b, thread_blocks)
      let new_else = resolve_threaded_target(else_b, thread_blocks)
      if new_then == new_else {
        (Jump(new_then, []), true)
      } else {
        (
          BranchZero(reg, is_nonzero, is_64, new_then, new_else),
          new_then != then_b || new_else != else_b,
        )
      }
    }
    BranchCmpImm(lhs, imm, cond, is_64, then_b, else_b) => {
      let new_then = resolve_threaded_target(then_b, thread_blocks)
      let new_else = resolve_threaded_target(else_b, thread_blocks)
      if new_then == new_else {
        (Jump(new_then, []), true)
      } else {
        (
          BranchCmpImm(lhs, imm, cond, is_64, new_then, new_else),
          new_then != then_b || new_else != else_b,
        )
      }
    }
    BrTable(index, targets, default) => {
      let new_targets : Array[Int] = []
      let mut changed = false
      for t in targets {
        let nt = resolve_threaded_target(t, thread_blocks)
        if nt != t {
          changed = true
        }
        new_targets.push(nt)
      }
      let new_default = resolve_threaded_target(default, thread_blocks)
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
        (Jump(pivot, []), true)
      } else {
        (BrTable(index, new_targets, new_default), changed)
      }
    }
    Return(_) | Trap(_) => (term, false)
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
    let thread_blocks = build_thread_blocks(func)
    let mut changed = false
    for block in blocks {
      if block.terminator is Some(term) {
        let (new_term, did_change) = rewrite_terminator_targets(
          term, thread_blocks,
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
