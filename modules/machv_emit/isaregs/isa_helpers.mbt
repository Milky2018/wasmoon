///|
/// Helpers for ISA role queries used in machine code emission.
///
/// Centralize ISA-dependent register choices (vmctx, scratch regs, cached pointers)
/// so emission logic can be shared across targets in the future. Callers should
/// pass the selected ISA explicitly; the default keeps older AArch64-only tests
/// working without implying host detection.

///|
pub fn vmctx_index(isa? : @isa.ISA = AArch64) -> Int {
  isa.vmctx_reg_index()
}

///|
pub fn mem0_desc_index(isa? : @isa.ISA = AArch64) -> Int {
  isa.mem0_desc_reg_index()
}

///|
pub fn func_table_index(isa? : @isa.ISA = AArch64) -> Int {
  isa.func_table_reg_index()
}

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
