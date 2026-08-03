// ============ Run All Optimizations ============

///|
/// Optimization level
/// - 0: No optimization
/// - 1: Inexpensive optimizations (constant folding, alias cleanup, DCE)
/// - 2: Default optimizations (adds e-graph, global GVN, and CFG transforms)
/// - 3: Aggressive optimizations (includes loop optimizations)
pub(all) enum OptLevel {
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
  if !perf_enabled() {
    return pass_fn(func)
  }
  let before = instruction_count(func)
  let tick = perf_tick_now()
  let result = pass_fn(func)
  let duration_us = perf_elapsed_us(tick)
  let after = instruction_count(func)
  perf_record_ir_pass(pass_name, before, after, result.changed, duration_us)
  result
}

///|
fn egraph_limits_for_function(func : Function) -> @egraph.SaturationLimits {
  let insts = instruction_count(func)
  if insts >= 600 {
    // An e-class starts with one node, so a limit of one would disable all
    // rewrites. Allow one match and one additional node instead.
    SaturationLimits(1, 2)
  } else if insts >= 300 {
    // Medium functions retain a little more local exploration while still
    // bounding matches and e-class growth per work item.
    SaturationLimits(2, 3)
  } else {
    @egraph.SaturationLimits::cranelift_default()
  }
}

///|
fn run_egraph_pass(func : Function) -> Bool {
  let limits = egraph_limits_for_function(func)
  // Large functions keep the compact core rewrite set for predictable
  // compile time; smaller ones run the full ruleset, whose results
  // elaboration can now materialize. The limits above additionally scale
  // the work permitted per e-class.
  let ruleset = if instruction_count(func) >= 300 {
    @egraph.get_compact_ruleset()
  } else {
    @egraph.get_global_ruleset()
  }
  if !perf_enabled() {
    return optimize_function_with_stats_with_limits_and_ruleset(
        func, limits, ruleset,
      ).changed
  }
  let before = instruction_count(func)
  let tick = perf_tick_now()
  let stats = optimize_function_with_stats_with_limits_and_ruleset(
    func, limits, ruleset,
  )
  let duration_us = perf_elapsed_us(tick)
  let after = instruction_count(func)
  perf_record_ir_pass(
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
fn gvn_work_budget_for_function(func : Function) -> Int {
  let insts = instruction_count(func)
  if insts > 300 {
    300
  } else {
    insts
  }
}

///|
fn run_gvn_pass(func : Function) -> OptResult {
  let before = instruction_count(func)
  let budget = gvn_work_budget_for_function(func)
  let perf_on = perf_enabled()
  let tick = if perf_on { perf_tick_now() } else { 0L }
  let stats = if budget == before {
    cse_gvn_global(func)
  } else {
    run_global_value_numbering_with_budget(func, budget)
  }
  if perf_on {
    perf_record_ir_pass(
      "cse_gvn_global",
      before,
      instruction_count(func),
      stats.result.changed,
      perf_elapsed_us(tick),
      work_done=Some(stats.work_done),
      budget_exhausted=Some(stats.budget_exhausted),
    )
  }
  stats.result
}

///|
fn run_backend_mandatory_cleanup(func : Function) -> OptResult {
  let result = OptResult::OptResult()
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
  result
}

///|
fn run_optimized_mandatory_pre_cleanup(func : Function) -> OptResult {
  let result = OptResult::OptResult()
  let backend_result = run_backend_mandatory_cleanup(func)
  if backend_result.changed {
    result.mark_changed()
  }
  let cf_result = run_opt_pass(func, "const_fold", fold_constants)
  if cf_result.changed {
    result.mark_changed()
  }
  let alias_result = run_opt_pass(func, "alias_canon", canonicalize_aliases)
  if alias_result.changed {
    result.mark_changed()
  }
  let cleanup_result = run_opt_pass(func, "dce", eliminate_dead_code)
  if cleanup_result.changed {
    result.mark_changed()
  }
  result
}

///|
fn run_mandatory_final_cleanup(func : Function) -> OptResult {
  let result = OptResult::OptResult()
  let alias_result = run_opt_pass(func, "alias_canon", canonicalize_aliases)
  if alias_result.changed {
    result.mark_changed()
  }
  let dce_result = run_opt_pass(func, "dce", eliminate_dead_code)
  if dce_result.changed {
    result.mark_changed()
  }
  let bs_result = run_opt_pass(func, "simplify_branches", simplify_branches)
  if bs_result.changed {
    result.mark_changed()
  }
  let uce_result = run_opt_pass(
    func, "eliminate_unreachable", eliminate_unreachable_code,
  )
  if uce_result.changed {
    result.mark_changed()
  }
  let bm_result = run_opt_pass(func, "merge_blocks", merge_blocks)
  if bm_result.changed {
    result.mark_changed()
  }
  let jt_result = run_opt_pass(func, "thread_jumps", thread_jumps)
  if jt_result.changed {
    result.mark_changed()
  }
  result
}

///|
fn optimize_o2_pipeline(func : Function) -> OptResult {
  let result = OptResult::OptResult()
  // Mandatory passes are independent of function size and run before budgets
  // are selected, so dead and aliased IR does not consume expensive work.
  let pre_cleanup = run_optimized_mandatory_pre_cleanup(func)
  if pre_cleanup.changed {
    result.mark_changed()
  }
  if run_egraph_pass(func) {
    result.mark_changed()
  }
  let gvn_result = run_gvn_pass(func)
  if gvn_result.changed {
    result.mark_changed()
  }
  // Budgeted passes may stop after a safe partial rewrite. Re-establish the
  // canonical IR form unconditionally afterward.
  let final_cleanup = run_mandatory_final_cleanup(func)
  if final_cleanup.changed {
    result.mark_changed()
  }
  result
}

///|
/// Run optimizations based on level
pub fn optimize_with_level(func : Function, level : OptLevel) -> OptResult {
  // NOTE: Even at O0 we still need a small set of IR cleanups to keep the
  // backend (lowering/regalloc) robust. These are semantics-preserving and
  // align with Cranelift's "mandatory" pre-optimization / canonicalization
  // philosophy.
  if level is O0 {
    return run_backend_mandatory_cleanup(func)
  }
  let result = match level {
    O1 => optimize_o1(func)
    O2 => optimize(func)
    O3 => optimize_o3(func)
    O0 => OptResult()
  }
  result
}

///|
/// O1: Mandatory cleanup and inexpensive simplification only.
fn optimize_o1(func : Function) -> OptResult {
  run_optimized_mandatory_pre_cleanup(func)
}

///|
/// Run default optimizations (Cranelift-aligned O2 path).
pub fn optimize(func : Function) -> OptResult {
  optimize_o2_pipeline(func)
}

///|
/// O3: Aggressive optimizations including loop optimizations
fn optimize_o3(func : Function) -> OptResult {
  let result = OptResult::OptResult()
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
  let unroll_result = run_opt_pass(func, "loop_unroll", unroll_counted_loops)
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
