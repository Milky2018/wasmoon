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
fn use_egraph_for_instruction_count(insts : Int) -> Bool {
  // Large functions previously copied every admitted MilkIR expression into
  // a second graph, only to run a deliberately tiny compact ruleset. The
  // existing in-place folding and GVN passes cover that tier without the
  // representation round trip. Keep aegraph for small functions where the
  // full ruleset can justify its construction cost.
  insts < 300
}

///|
fn run_egraph_pass_with_analysis(
  func : Function,
  analysis : FunctionAnalysis,
) -> Bool {
  let before = instruction_count(func)
  if !use_egraph_for_instruction_count(before) {
    return false
  }
  let limits = @egraph.SaturationLimits::cranelift_default()
  let ruleset = @egraph.get_global_ruleset()
  if !perf_enabled() {
    return optimize_function_with_stats_with_limits_and_ruleset(
        func, limits, ruleset, analysis,
      ).changed
  }
  let tick = perf_tick_now()
  let stats = optimize_function_with_stats_with_limits_and_ruleset(
    func, limits, ruleset, analysis,
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
fn gvn_work_budget_for_instruction_count(insts : Int) -> Int {
  if insts > 300 {
    300
  } else {
    insts
  }
}

///|
fn run_gvn_pass_with_analysis(
  func : Function,
  analysis : FunctionAnalysis,
) -> OptResult {
  let before = instruction_count(func)
  let budget = gvn_work_budget_for_instruction_count(before)
  let perf_on = perf_enabled()
  let tick = if perf_on { perf_tick_now() } else { 0L }
  let stats = run_global_value_numbering_with_budget_and_analysis(
    func, budget, analysis,
  )
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
  if backend_result.changed || cf_result.changed || alias_result.changed {
    let cleanup_result = run_opt_pass(func, "dce", eliminate_dead_code)
    if cleanup_result.changed {
      result.mark_changed()
    }
  }
  result
}

///|
fn run_mandatory_final_cleanup_with_analysis(
  func : Function,
  analysis : FunctionAnalysis,
  needs_dce : Bool,
) -> OptResult {
  let result = OptResult::OptResult()
  let alias_result = run_opt_pass(func, "alias_canon", function => {
    canonicalize_aliases_with_analysis(function, analysis)
  })
  if alias_result.changed {
    result.mark_changed()
  }
  if needs_dce || alias_result.changed {
    let dce_result = run_opt_pass(func, "dce", eliminate_dead_code)
    if dce_result.changed {
      result.mark_changed()
    }
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
  let analysis = FunctionAnalysis::build(func)
  let egraph_changed = run_egraph_pass_with_analysis(func, analysis)
  if egraph_changed {
    result.mark_changed()
  }
  let gvn_result = run_gvn_pass_with_analysis(func, analysis)
  if gvn_result.changed {
    result.mark_changed()
  }
  // Budgeted passes may stop after a safe partial rewrite. Re-establish the
  // canonical IR form unconditionally afterward.
  let final_cleanup = run_mandatory_final_cleanup_with_analysis(
    func,
    analysis,
    egraph_changed || gvn_result.changed,
  )
  if final_cleanup.changed {
    result.mark_changed()
  }
  result
}

///|
fn run_final_materialization_sink(func : Function) -> OptResult {
  let result = run_opt_pass(
    func, "sink_materializations", sink_single_use_materializations,
  )
  if result.changed {
    run_opt_pass(func, "dce", eliminate_dead_code) |> ignore
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
  let result = optimize_o2_pipeline(func)
  if run_final_materialization_sink(func).changed {
    result.mark_changed()
  }
  result
}

///|
/// O3: Aggressive optimizations including loop optimizations
fn optimize_o3(func : Function) -> OptResult {
  let result = OptResult::OptResult()
  // First run O2 optimizations
  let o2_result = optimize_o2_pipeline(func)
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
  let cleanup_result = optimize_o2_pipeline(func)
  if cleanup_result.changed {
    result.mark_changed()
  }
  if run_final_materialization_sink(func).changed {
    result.mark_changed()
  }
  result
}
