// Peephole optimizations and local transforms for VCode lowering

// NOTE: This file is intentionally kept small. The implementation is split
// across:
// - peephole_basic.mbt
// - peephole_licm.mbt

///|
pub fn optimize_vcode(func : @regalloc.VCodeFunction) -> Unit {
  @peephole.optimize_vcode(func, profile=Full)
}

///|
pub fn optimize_vcode_for_lowering(func : @regalloc.VCodeFunction) -> Unit {
  @peephole.optimize_vcode(func, profile=Lowering)
}
