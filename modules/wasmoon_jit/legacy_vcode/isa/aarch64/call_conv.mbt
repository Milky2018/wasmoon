///|
pub fn aapcs64_arg_gprs() -> Array[@abi.PReg] {
  @aarch64_target.aapcs64_arg_gprs()
}

///|
pub fn aapcs64_ret_gprs() -> Array[@abi.PReg] {
  @aarch64_target.aapcs64_ret_gprs()
}

///|
pub fn aapcs64_callee_saved() -> Array[@abi.PReg] {
  @aarch64_target.aapcs64_callee_saved()
}

///|
pub fn allocatable_scratch_regs() -> Array[@abi.PReg] {
  @aarch64_target.allocatable_scratch_regs()
}

///|
pub fn allocatable_callee_saved_regs(
  enable_pinned_reg? : Bool = true,
) -> Array[@abi.PReg] {
  @aarch64_target.allocatable_callee_saved_regs(enable_pinned_reg~)
}

///|
pub fn aapcs64_arg_fprs() -> Array[@abi.PReg] {
  @aarch64_target.aapcs64_arg_fprs()
}

///|
pub fn aapcs64_ret_fprs() -> Array[@abi.PReg] {
  @aarch64_target.aapcs64_ret_fprs()
}

///|
pub fn wasm_vmctx_arg_preg() -> @abi.PReg {
  @aarch64_target.wasm_vmctx_arg_preg()
}

///|
pub fn wasm_user_arg_gprs() -> Array[@abi.PReg] {
  @aarch64_target.wasm_user_arg_gprs()
}

///|
pub fn wasm_arg_fprs() -> Array[@abi.PReg] {
  @aarch64_target.wasm_arg_fprs()
}

///|
pub fn wasm_ret_gprs() -> Array[@abi.PReg] {
  @aarch64_target.wasm_ret_gprs()
}

///|
pub fn wasm_ret_fprs() -> Array[@abi.PReg] {
  @aarch64_target.wasm_ret_fprs()
}

///|
pub fn callee_saved_fprs() -> Array[@abi.PReg] {
  @aarch64_target.callee_saved_fprs()
}

///|
pub fn allocatable_scratch_fprs() -> Array[@abi.PReg] {
  @aarch64_target.allocatable_scratch_fprs()
}

///|
pub fn call_clobbered_gprs() -> Array[@abi.PReg] {
  @aarch64_target.call_clobbered_gprs()
}

///|
pub fn call_clobbered_fprs() -> Array[@abi.PReg] {
  @aarch64_target.call_clobbered_fprs()
}

///|
pub fn call_clobbered_fprs_same_abi() -> Array[@abi.PReg] {
  @aarch64_target.call_clobbered_fprs_same_abi()
}
