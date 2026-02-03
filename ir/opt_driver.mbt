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
    let dce_result = eliminate_dead_code(func)
    if dce_result.changed {
      result.mark_changed()
    }
    let cbpe_result = eliminate_constant_block_params(func)
    if cbpe_result.changed {
      result.mark_changed()
    }
    let dbpe_result = eliminate_dead_block_params(func)
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
      let remat_result = rematerialize_across_blocks(func)
      if remat_result.changed {
        result.mark_changed()
      }
      // Cleanup: remat may leave now-unused original defs behind.
      let dce_result = eliminate_dead_code(func)
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
    if optimize_function(func) {
      changed = true
      result.mark_changed()
    }
    // Basic optimizations only
    let cf_result = fold_constants(func)
    if cf_result.changed {
      changed = true
      result.mark_changed()
    }
    let mb_result = eliminate_redundant_mem_base_loads(func)
    if mb_result.changed {
      changed = true
      result.mark_changed()
    }
    let cp_result = propagate_copies_global(func)
    if cp_result.changed {
      changed = true
      result.mark_changed()
    }
    let cse_result = eliminate_common_subexpressions_global(func)
    if cse_result.changed {
      changed = true
      result.mark_changed()
    }
    // GVN with load CSE (extends CSE to handle memory loads)
    let gvn_result = gvn_global(func)
    if gvn_result.changed {
      changed = true
      result.mark_changed()
    }
    let dce_result = eliminate_dead_code(func)
    if dce_result.changed {
      changed = true
      result.mark_changed()
    }
    let cbpe_result = eliminate_constant_block_params(func)
    if cbpe_result.changed {
      changed = true
      result.mark_changed()
    }
    // Dead block parameter elimination (crucial for unused locals)
    let dbpe_result = eliminate_dead_block_params(func)
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
    if optimize_function(func) {
      changed = true
      result.mark_changed()
    }
    // Run each optimization pass
    let cf_result = fold_constants(func)
    if cf_result.changed {
      changed = true
      result.mark_changed()
    }
    let mb_result = eliminate_redundant_mem_base_loads(func)
    if mb_result.changed {
      changed = true
      result.mark_changed()
    }
    let cp_result = propagate_copies_global(func)
    if cp_result.changed {
      changed = true
      result.mark_changed()
    }
    let cse_result = eliminate_common_subexpressions_global(func)
    if cse_result.changed {
      changed = true
      result.mark_changed()
    }
    // GVN with load CSE (extends CSE to handle memory loads)
    let gvn_result = gvn_global(func)
    if gvn_result.changed {
      changed = true
      result.mark_changed()
    }
    let dce_result = eliminate_dead_code(func)
    if dce_result.changed {
      changed = true
      result.mark_changed()
    }
    let cbpe_result = eliminate_constant_block_params(func)
    if cbpe_result.changed {
      changed = true
      result.mark_changed()
    }
    // Dead block parameter elimination (crucial for unused locals)
    let dbpe_result = eliminate_dead_block_params(func)
    if dbpe_result.changed {
      changed = true
      result.mark_changed()
    }
    // Control flow optimizations
    let bs_result = simplify_branches(func)
    if bs_result.changed {
      changed = true
      result.mark_changed()
    }
    let uce_result = eliminate_unreachable_code(func)
    if uce_result.changed {
      changed = true
      result.mark_changed()
    }
    let bm_result = merge_blocks(func)
    if bm_result.changed {
      changed = true
      result.mark_changed()
    }
    let jt_result = thread_jumps(func)
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
  let licm_result = hoist_loop_invariants(func)
  if licm_result.changed {
    result.mark_changed()
  }
  let unroll_result = unroll_loops(func, 2) // Unroll factor of 2
  if unroll_result.changed {
    result.mark_changed()
  }
  let sr_result = reduce_strength(func)
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
