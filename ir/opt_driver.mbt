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
fn egraph_limits_for_function(func : Function) -> @egraph.SaturationLimits {
  let insts = instruction_count(func)
  if insts >= 600 {
    @egraph.SaturationLimits::new(1, 1)
  } else if insts >= 300 {
    // Keep medium-large functions on minimal rewrite budgets to bound
    // compile-time while preserving canonical Cranelift-style egraph usage.
    @egraph.SaturationLimits::new(1, 2)
  } else {
    @egraph.SaturationLimits::cranelift_default()
  }
}

///|
fn run_egraph_pass(func : Function) -> Bool {
  let insts = instruction_count(func)
  if insts >= 300 {
    // Keep compile wall bounded on mega-functions; rely on lightweight passes.
    return false
  }
  let limits = egraph_limits_for_function(func)
  // Keep to a compact Cranelift-like core rewrite set for predictable compile
  // time on all non-mega functions.
  let ruleset = @egraph.get_compact_ruleset()
  if !@perf.enabled() {
    return optimize_function_with_stats_with_limits_and_ruleset(
        func, limits, ruleset,
      ).changed
  }
  let before = instruction_count(func)
  let tick = @perf.tick_now()
  let stats = optimize_function_with_stats_with_limits_and_ruleset(
    func, limits, ruleset,
  )
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
fn optimize_cranelift_style(
  func : Function,
  run_egraph? : Bool = true,
) -> OptResult {
  let result = OptResult::new()
  // Align with Cranelift's phase ordering by running constant-phi cleanup first.
  let cbpe_result = run_opt_pass(
    func, "const_block_param_elim", eliminate_constant_block_params,
  )
  if cbpe_result.changed {
    result.mark_changed()
  }
  // Keep dead block-param elimination in wasmoon pipeline: unlike CLIF's
  // richer alias/SSA plumbing, our IR lowering can otherwise retain dead jump
  // params that inflate regalloc pressure.
  let dbpe_result = run_opt_pass(
    func, "dead_block_param_elim", eliminate_dead_block_params,
  )
  if dbpe_result.changed {
    result.mark_changed()
  }
  // NOTE: Temporarily keep global mem-base CSE disabled due correctness
  // regression on algorithm workloads; local mem-base CSE remains enabled.
  let addr_reassoc_result = run_opt_pass(
    func, "wasm_addr_reassoc", reassociate_wasm_addresses,
  )
  if addr_reassoc_result.changed {
    result.mark_changed()
  }
  if run_egraph && run_egraph_pass(func) {
    result.mark_changed()
  }
  // Compatibility cleanups: keep small-function local rewrites that current
  // tests/codegen still rely on, but cap them to tiny functions to keep
  // compile-time bounded on larger workloads.
  if instruction_count(func) < 300 {
    let cf_result = run_opt_pass(func, "const_fold", fold_constants)
    if cf_result.changed {
      result.mark_changed()
    }
    let alias_result = run_opt_pass(func, "alias_canon", canonicalize_aliases)
    if alias_result.changed {
      result.mark_changed()
    }
    let mb_result = run_opt_pass(
      func, "mem_base_cse", eliminate_redundant_mem_base_loads,
    )
    if mb_result.changed {
      result.mark_changed()
    }
    let gvn_result = run_opt_pass(func, "cse_gvn_global", cse_gvn_global)
    if gvn_result.changed {
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
  result
}

///|
/// O1: Basic optimizations only
fn optimize_o1(func : Function) -> OptResult {
  optimize_cranelift_style(func, run_egraph=true)
}

///|
/// Run default optimizations (Cranelift-aligned O2 path).
pub fn optimize(func : Function) -> OptResult {
  optimize_cranelift_style(func, run_egraph=true)
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
