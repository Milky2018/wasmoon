// IR Optimization Passes
// Implements target-independent optimizations on the high-level IR

// NOTE: This file is intentionally kept small. The implementation is split
// across:
// - opt_passes_basic.mbt
// - opt_passes_cse_gvn.mbt
// - opt_driver.mbt
// - opt_cfg.mbt
// - opt_loops.mbt
