///|
/// x86_64 ABI/ISA policy stub.
///
/// Step 1: this backend is not implemented. These functions must compile but
/// should not be used by the current JIT pipeline (which targets AArch64 only).

///|
pub fn call_clobbered_gprs() -> Array[@abi.PReg] {
  abort("x86_64 JIT backend not implemented yet")
}

///|
pub fn call_clobbered_fprs() -> Array[@abi.PReg] {
  abort("x86_64 JIT backend not implemented yet")
}

///|
pub fn call_clobbered_fprs_same_abi() -> Array[@abi.PReg] {
  abort("x86_64 JIT backend not implemented yet")
}
