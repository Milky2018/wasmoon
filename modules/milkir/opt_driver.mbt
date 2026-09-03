// ============ Run All Optimizations ============

///|
/// Optimization level
/// - 0: No optimization
/// - 1: Inexpensive optimizations (constant folding, alias cleanup, DCE)
/// - 2: Default optimizations (adds acyclic rewrites, GVN, and CFG transforms)
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
    count = count + block.instruction_count()
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
fn gvn_work_budget_for_instruction_count(insts : Int) -> Int {
  if insts > 300 {
    300
  } else {
    insts
  }
}

///|
fn run_acyclic_optimization_pass_with_analysis(
  func : Function,
  analysis : FunctionAnalysis,
) -> (Bool, OptResult) {
  let before = instruction_count(func)
  let perf_on = perf_enabled()
  let tick = if perf_on { perf_tick_now() } else { 0L }
  let optimize_stats = run_acyclic_optimization_with_budget_and_analysis(
    func,
    gvn_work_budget_for_instruction_count(before),
    analysis,
  )
  if perf_on {
    perf_record_ir_pass(
      "acyclic_optimize",
      before,
      instruction_count(func),
      optimize_stats.result.changed,
      perf_elapsed_us(tick),
      work_done=Some(optimize_stats.work_done),
      rewrite_apps=Some(optimize_stats.rewrite_stats.applied),
      rewrite_attempts=Some(optimize_stats.rewrite_stats.attempts),
      rewrite_created_insts=Some(
        optimize_stats.rewrite_stats.created_instructions,
      ),
      budget_exhausted=Some(optimize_stats.budget_exhausted),
    )
  }
  (optimize_stats.rewrite_stats.changed, optimize_stats.result)
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
fn run_acyclic_pipeline_after_normalization(
  func : Function,
  needs_dce : Bool,
) -> OptResult {
  let result = OptResult::OptResult()
  let analysis = FunctionAnalysis::build(func)
  let (rewrite_changed, gvn_result) = run_acyclic_optimization_pass_with_analysis(
    func, analysis,
  )
  if rewrite_changed {
    result.mark_changed()
  }
  if gvn_result.changed {
    result.mark_changed()
  }
  // Budgeted passes may stop after a safe partial rewrite. Re-establish the
  // canonical IR form unconditionally afterward.
  let final_cleanup = run_mandatory_final_cleanup_with_analysis(
    func,
    analysis,
    needs_dce || rewrite_changed || gvn_result.changed,
  )
  if final_cleanup.changed {
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
  if run_acyclic_pipeline_after_normalization(func, false).changed {
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
  // Normalize once so loop transforms do not spend work on dead or aliased
  // input. The full acyclic rewrite/GVN pipeline runs only after structural
  // loop transforms have exposed their final expression graph.
  let normalization = run_optimized_mandatory_pre_cleanup(func)
  if normalization.changed {
    result.mark_changed()
  }
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
  let loop_changed = licm_result.changed ||
    unroll_result.changed ||
    sr_result.changed
  if run_acyclic_pipeline_after_normalization(func, loop_changed).changed {
    result.mark_changed()
  }
  if run_final_materialization_sink(func).changed {
    result.mark_changed()
  }
  result
}
