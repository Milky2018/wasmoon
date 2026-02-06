// ============ Run All Optimizations ============

///|
/// Optimization level
/// - 0: No optimization
/// - 1: Basic optimizations (constant folding, copy propagation, CSE, DCE)
/// - 2: Default optimizations (includes control flow optimizations)
/// - 3: Aggressive optimizations (includes loop optimizations)
pub enum OptLevel {
  O0 // No optimization
  O1 // Basic optimizations
  O2 // Default optimizations
  O3 // Aggressive optimizations
}

///|
/// Parse optimization level from integer
pub fn OptLevel::from_int(n : Int) -> OptLevel {
  match n {
    0 => O0
    1 => O1
    3 => O3
    _ => O2 // Default
  }
}

///|
/// Count IR instructions in a function.
pub fn instruction_count(func : Function) -> Int {
  let mut count = 0
  for block in func.blocks {
    count = count + block.instructions.length()
  }
  count
}

///|
fn run_opt_pass(
  func : Function,
  pass_name : String,
  pass_fn : (Function) -> OptResult,
) -> OptResult {
  if !@perf.enabled() {
    return pass_fn(func)
  }
  let before = instruction_count(func)
  let tick = @perf.tick_now()
  let result = pass_fn(func)
  let duration_us = @perf.elapsed_us(tick)
  let after = instruction_count(func)
  @perf.record_ir_pass(pass_name, before, after, result.changed, duration_us)
  result
}

///|
fn run_egraph_pass(func : Function) -> Bool {
  if !@perf.enabled() {
    return optimize_function(func)
  }
  let before = instruction_count(func)
  let tick = @perf.tick_now()
  let stats = optimize_function_with_stats(func)
  let duration_us = @perf.elapsed_us(tick)
  let after = instruction_count(func)
  @perf.record_ir_pass(
    "egraph",
    before,
    after,
    stats.changed,
    duration_us,
    egraph_classes=Some(stats.total_classes),
    egraph_nodes=Some(stats.total_nodes),
    egraph_rule_apps=Some(stats.total_rule_applications),
  )
  stats.changed
}

///|
/// Run optimizations based on level
pub fn optimize_with_level(func : Function, level : OptLevel) -> OptResult {
  // NOTE: Even at O0 we still need a small set of IR cleanups to keep the
  // backend (lowering/regalloc) robust. These are semantics-preserving and
  // align with Cranelift's "mandatory" pre-optimization / canonicalization
  // philosophy.
  if level is O0 {
    let result = OptResult::new()
    // Translator produces many SSA temps/block params (e.g. from WASM locals).
    // Removing trivially-dead IR avoids pathological regalloc pressure and
    // prevents backend miscompiles in very large unoptimized functions.
    let dce_result = run_opt_pass(func, "dce", eliminate_dead_code)
    if dce_result.changed {
      result.mark_changed()
    }
    let cbpe_result = run_opt_pass(
      func, "const_block_param_elim", eliminate_constant_block_params,
    )
    if cbpe_result.changed {
      result.mark_changed()
    }
    let dbpe_result = run_opt_pass(
      func, "dead_block_param_elim", eliminate_dead_block_params,
    )
    if dbpe_result.changed {
      result.mark_changed()
    }
    return result
  }
  let result = match level {
    O1 => optimize_o1(func)
    O2 => optimize(func)
    O3 => optimize_o3(func)
    O0 => OptResult::new()
  }

  // Cranelift-style rematerialization is a post-optimization, IR-level pass.
  // Run it once, after reaching a fixed point, to avoid repeated cloning.
  match level {
    O0 => ()
    _ => {
      let remat_result = run_opt_pass(
        func, "rematerialize_across_blocks", rematerialize_across_blocks,
      )
      if remat_result.changed {
        result.mark_changed()
      }
      // Cleanup: remat may leave now-unused original defs behind.
      let dce_result = run_opt_pass(func, "dce", eliminate_dead_code)
      if dce_result.changed {
        result.mark_changed()
      }
    }
  }
  result
}

///|
/// O1: Basic optimizations only
fn optimize_o1(func : Function) -> OptResult {
  let result = OptResult::new()
  let mut changed = true
  let mut iterations = 0
  let max_iterations = 100
  while changed && iterations < max_iterations {
    changed = false
    iterations = iterations + 1
    // E-graph based optimization (constant folding + algebraic simplification)
    if run_egraph_pass(func) {
      changed = true
      result.mark_changed()
    }
    // Basic optimizations only
    let cf_result = run_opt_pass(func, "const_fold", fold_constants)
    if cf_result.changed {
      changed = true
      result.mark_changed()
    }
    let mb_result = run_opt_pass(
      func, "mem_base_cse", eliminate_redundant_mem_base_loads,
    )
    if mb_result.changed {
      changed = true
      result.mark_changed()
    }
    let cp_result = run_opt_pass(
      func, "copy_prop_global", propagate_copies_global,
    )
    if cp_result.changed {
      changed = true
      result.mark_changed()
    }
    let cse_result = run_opt_pass(
      func, "cse_global", eliminate_common_subexpressions_global,
    )
    if cse_result.changed {
      changed = true
      result.mark_changed()
    }
    // GVN with load CSE (extends CSE to handle memory loads)
    let gvn_result = run_opt_pass(func, "gvn_global", gvn_global)
    if gvn_result.changed {
      changed = true
      result.mark_changed()
    }
    let dce_result = run_opt_pass(func, "dce", eliminate_dead_code)
    if dce_result.changed {
      changed = true
      result.mark_changed()
    }
    let cbpe_result = run_opt_pass(
      func, "const_block_param_elim", eliminate_constant_block_params,
    )
    if cbpe_result.changed {
      changed = true
      result.mark_changed()
    }
    // Dead block parameter elimination (crucial for unused locals)
    let dbpe_result = run_opt_pass(
      func, "dead_block_param_elim", eliminate_dead_block_params,
    )
    if dbpe_result.changed {
      changed = true
      result.mark_changed()
    }
  }
  result
}

///|
/// Run all basic optimizations until fixed point
pub fn optimize(func : Function) -> OptResult {
  let result = OptResult::new()
  let mut changed = true
  let mut iterations = 0
  let max_iterations = 100 // Prevent infinite loops
  while changed && iterations < max_iterations {
    changed = false
    iterations = iterations + 1
    // E-graph based optimization (constant folding + algebraic simplification)
    if run_egraph_pass(func) {
      changed = true
      result.mark_changed()
    }
    // Run each optimization pass
    let cf_result = run_opt_pass(func, "const_fold", fold_constants)
    if cf_result.changed {
      changed = true
      result.mark_changed()
    }
    let mb_result = run_opt_pass(
      func, "mem_base_cse", eliminate_redundant_mem_base_loads,
    )
    if mb_result.changed {
      changed = true
      result.mark_changed()
    }
    let cp_result = run_opt_pass(
      func, "copy_prop_global", propagate_copies_global,
    )
    if cp_result.changed {
      changed = true
      result.mark_changed()
    }
    let cse_result = run_opt_pass(
      func, "cse_global", eliminate_common_subexpressions_global,
    )
    if cse_result.changed {
      changed = true
      result.mark_changed()
    }
    // GVN with load CSE (extends CSE to handle memory loads)
    let gvn_result = run_opt_pass(func, "gvn_global", gvn_global)
    if gvn_result.changed {
      changed = true
      result.mark_changed()
    }
    let dce_result = run_opt_pass(func, "dce", eliminate_dead_code)
    if dce_result.changed {
      changed = true
      result.mark_changed()
    }
    let cbpe_result = run_opt_pass(
      func, "const_block_param_elim", eliminate_constant_block_params,
    )
    if cbpe_result.changed {
      changed = true
      result.mark_changed()
    }
    // Dead block parameter elimination (crucial for unused locals)
    let dbpe_result = run_opt_pass(
      func, "dead_block_param_elim", eliminate_dead_block_params,
    )
    if dbpe_result.changed {
      changed = true
      result.mark_changed()
    }
    // Control flow optimizations
    let bs_result = run_opt_pass(func, "simplify_branches", simplify_branches)
    if bs_result.changed {
      changed = true
      result.mark_changed()
    }
    let uce_result = run_opt_pass(
      func, "eliminate_unreachable", eliminate_unreachable_code,
    )
    if uce_result.changed {
      changed = true
      result.mark_changed()
    }
    let bm_result = run_opt_pass(func, "merge_blocks", merge_blocks)
    if bm_result.changed {
      changed = true
      result.mark_changed()
    }
    let jt_result = run_opt_pass(func, "thread_jumps", thread_jumps)
    if jt_result.changed {
      changed = true
      result.mark_changed()
    }
  }
  result
}

///|
/// O3: Aggressive optimizations including loop optimizations
fn optimize_o3(func : Function) -> OptResult {
  let result = OptResult::new()
  // First run O2 optimizations
  let o2_result = optimize(func)
  if o2_result.changed {
    result.mark_changed()
  }
  // Then apply loop optimizations
  let licm_result = run_opt_pass(func, "loop_licm", hoist_loop_invariants)
  if licm_result.changed {
    result.mark_changed()
  }
  let unroll_result = run_opt_pass(func, "loop_unroll", fn(func) {
    unroll_loops(func, 2)
  }) // Unroll factor of 2
  if unroll_result.changed {
    result.mark_changed()
  }
  let sr_result = run_opt_pass(func, "loop_strength_reduce", reduce_strength)
  if sr_result.changed {
    result.mark_changed()
  }
  // Run O2 again to clean up
  let cleanup_result = optimize(func)
  if cleanup_result.changed {
    result.mark_changed()
  }
  result
}
