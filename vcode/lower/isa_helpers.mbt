///|
/// Helpers for ISA role queries used in lowering.
///
/// Keep ISA-dependent register choices out of the lowering logic. Today the JIT
/// backend targets AArch64 only (`ISA::current()`), but these helpers make it
/// straightforward to add x86_64 later.

///|
fn current_isa() -> @isa.ISA {
  @isa.ISA::current()
}

///|
fn vmctx_index() -> Int {
  current_isa().vmctx_reg_index()
}

///|
fn vmctx_preg() -> @abi.PReg {
  current_isa().vmctx_preg()
}

///|
fn scratch2_index() -> Int {
  current_isa().scratch_reg_2_index()
}
