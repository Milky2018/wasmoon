///|
/// Helpers for target register queries used in machine code emission.
///
/// Embedding-specific register roles are supplied through
/// `@abi.EmbeddingRegRoles`, not through this ISA helper package.

///|
pub fn scratch1_index(isa? : @isa.ISA = AArch64) -> Int {
  isa.scratch_reg_1_index()
}

///|
pub fn scratch2_index(isa? : @isa.ISA = AArch64) -> Int {
  isa.scratch_reg_2_index()
}

///|
pub fn lr_index(isa? : @isa.ISA = AArch64) -> Int {
  isa.lr_reg_index()
}

///|
pub fn sret_index(isa? : @isa.ISA = AArch64) -> Int {
  isa.sret_reg_index()
}
