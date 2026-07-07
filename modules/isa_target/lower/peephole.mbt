// Peephole optimizations and local transforms for VCode lowering

// NOTE: This file is intentionally kept small. The implementation is split
// across:
// - peephole_basic.mbt
// - peephole_licm.mbt

///|
pub fn optimize_vcode(
  func : @machv.Function,
  isa? : @isa.ISA = AArch64,
) -> Unit {
  @peephole.optimize_vcode(func, isa~, profile=Full)
}

///|
pub fn optimize_vcode_for_lowering(
  func : @machv.Function,
  isa? : @isa.ISA = AArch64,
  runtime_layout? : @abi.RuntimeContextLayout? = None,
  embedding_reg_roles? : @abi.EmbeddingRegRoles = @abi.EmbeddingRegRoles::none(),
) -> Unit {
  @peephole.optimize_vcode(
    func,
    isa~,
    profile=Lowering,
    runtime_layout~,
    embedding_reg_roles~,
  )
}
