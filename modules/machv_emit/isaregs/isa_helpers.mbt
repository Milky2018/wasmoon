///|
/// Helpers for ISA role queries used in machine code emission.
///
/// Centralize ISA-dependent register choices (vmctx, scratch regs, cached pointers)
/// so emission logic can be shared across targets in the future.

///|
pub fn current_isa() -> @isa.ISA {
  @isa.ISA::current()
}

///|
pub fn vmctx_index() -> Int {
  current_isa().vmctx_reg_index()
}

///|
pub fn mem0_desc_index() -> Int {
  current_isa().mem0_desc_reg_index()
}

///|
pub fn func_table_index() -> Int {
  current_isa().func_table_reg_index()
}

///|
pub fn scratch1_index() -> Int {
  current_isa().scratch_reg_1_index()
}

///|
pub fn scratch2_index() -> Int {
  current_isa().scratch_reg_2_index()
}

///|
pub fn lr_index() -> Int {
  current_isa().lr_reg_index()
}

///|
pub fn sret_index() -> Int {
  current_isa().sret_reg_index()
}
