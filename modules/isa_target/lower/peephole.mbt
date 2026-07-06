// Peephole optimizations and local transforms for VCode lowering

// NOTE: This file is intentionally kept small. The implementation is split
// across:
// - peephole_basic.mbt
// - peephole_licm.mbt

///|
pub fn optimize_vcode(func : @machv.Function) -> Unit {
  @peephole.optimize_vcode(func, profile=Full)
}

///|
pub fn optimize_vcode_for_lowering(
  func : @machv.Function,
  runtime_layout? : @abi.RuntimeContextLayout? = None,
) -> Unit {
  @peephole.optimize_vcode(func, profile=Lowering, runtime_layout~)
}
