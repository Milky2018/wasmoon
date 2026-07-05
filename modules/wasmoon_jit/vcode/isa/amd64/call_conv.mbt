///|
/// amd64 ABI/ISA policy (SysV AMD64).
///
/// Note: this file only defines the "policy" bits currently needed by the ISA
/// facade (call-clobbered sets). Lowering/emission will be added in Step 3.

///|
pub fn call_clobbered_gprs() -> Array[@abi.PReg] {
  // SysV AMD64: caller-saved GPRs.
  //
  // We use the 0..15 numbering described in `vcode/isa/amd64/roles.mbt`.
  [
    { index: 0, class: Int }, // rax
    { index: 1, class: Int }, // rcx
    { index: 2, class: Int }, // rdx
    { index: 6, class: Int }, // rsi
    { index: 7, class: Int }, // rdi
    { index: 8, class: Int }, // r8
    { index: 9, class: Int }, // r9
    { index: 10, class: Int }, // r10
    { index: 11, class: Int },
  ] // r11
}

///|
pub fn call_clobbered_fprs() -> Array[@abi.PReg] {
  // SysV AMD64: all XMM registers are caller-saved.
  let regs : Array[@abi.PReg] = []
  for i in 0..<16 {
    regs.push({ index: i, class: Float64 })
  }
  regs
}

///|
pub fn call_clobbered_fprs_same_abi() -> Array[@abi.PReg] {
  // SysV has no callee-saved XMM registers, even for internal calls.
  call_clobbered_fprs()
}

///|
/// Internal Wasm ABI (initial amd64 design): vmctx argument register.
pub fn wasm_vmctx_arg_preg() -> @abi.PReg {
  { index: 7, class: Int } // rdi
}

///|
/// Internal Wasm ABI (initial amd64 design): user integer argument registers.
///
/// Keep this aligned with SysV argument placement after vmctx in `rdi`.
/// This is required so imported C ABI functions (for example WASI hostcalls)
/// observe correct stack/register argument ordering.
pub fn wasm_user_arg_gprs() -> Array[@abi.PReg] {
  [
    { index: 6, class: Int }, // rsi
    { index: 2, class: Int }, // rdx
    { index: 1, class: Int }, // rcx
    { index: 8, class: Int }, // r8
    { index: 9, class: Int }, // r9
  ] // r9
}

///|
/// Internal Wasm ABI: float argument registers (XMM0-XMM7).
pub fn wasm_arg_fprs() -> Array[@abi.PReg] {
  let regs : Array[@abi.PReg] = []
  for i in 0..<8 {
    regs.push({ index: i, class: Float64 })
  }
  regs
}

///|
/// Internal Wasm ABI: integer return registers.
pub fn wasm_ret_gprs() -> Array[@abi.PReg] {
  // Internal multi-value return convention: allow up to 8 integer return regs.
  // Keep r11 free as a scratch register for parallel-move breaking.
  [
    { index: 0, class: Int }, // rax
    { index: 2, class: Int }, // rdx
    { index: 1, class: Int }, // rcx
    { index: 8, class: Int }, // r8
    { index: 9, class: Int }, // r9
    { index: 6, class: Int }, // rsi
    { index: 7, class: Int }, // rdi
    { index: 10, class: Int },
  ] // r10
}

///|
/// Internal Wasm ABI: float return registers.
pub fn wasm_ret_fprs() -> Array[@abi.PReg] {
  let regs : Array[@abi.PReg] = []
  for i in 0..<8 {
    regs.push({ index: i, class: Float64 })
  }
  regs
}
