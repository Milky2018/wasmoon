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

///|
fn wasm_vmctx_arg_preg() -> @abi.PReg {
  current_isa().wasm_vmctx_arg_preg()
}

///|
fn wasm_user_arg_gprs() -> Array[@abi.PReg] {
  current_isa().wasm_user_arg_gprs()
}

///|
fn wasm_arg_fprs() -> Array[@abi.PReg] {
  current_isa().wasm_arg_fprs()
}

///|
fn wasm_ret_gprs() -> Array[@abi.PReg] {
  current_isa().wasm_ret_gprs()
}

///|
fn wasm_ret_fprs() -> Array[@abi.PReg] {
  current_isa().wasm_ret_fprs()
}
