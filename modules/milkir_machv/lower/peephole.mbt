// Peephole optimizations and local transforms for MachV lowering

// NOTE: This file is intentionally kept small. The implementation is split
// across:
// - peephole_basic.mbt
// - peephole_licm.mbt

///|
pub fn optimize_machv(
  func : @machv.Function,
  isa? : @isa.ISA = AArch64,
) -> Unit {
  @peephole.optimize_machv(func, isa~, profile=Full)
}

///|
pub fn optimize_machv_for_lowering(
  func : @machv.Function,
  isa? : @isa.ISA = AArch64,
  embedding_abi? : @abi.EmbeddingABI? = None,
) -> Unit {
  @peephole.optimize_machv(func, isa~, profile=Lowering, embedding_abi~)
}
