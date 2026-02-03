///|
/// Helpers for ISA role queries used in machine code emission.
///
/// Centralize ISA-dependent register choices (vmctx, scratch regs, cached pointers)
/// so emission logic can be shared across targets in the future.

///|
fn current_isa() -> @isa.ISA {
  @isa.ISA::current()
}

///|
fn vmctx_index() -> Int {
  current_isa().vmctx_reg_index()
}

///|
fn mem0_desc_index() -> Int {
  current_isa().mem0_desc_reg_index()
}

///|
fn func_table_index() -> Int {
  current_isa().func_table_reg_index()
}

///|
fn scratch1_index() -> Int {
  current_isa().scratch_reg_1_index()
}

///|
fn scratch2_index() -> Int {
  current_isa().scratch_reg_2_index()
}

///|
fn lr_index() -> Int {
  current_isa().lr_reg_index()
}
