///|
/// x86_64 ABI/ISA policy (SysV AMD64).
///
/// Note: this file only defines the "policy" bits currently needed by the ISA
/// facade (call-clobbered sets). Lowering/emission will be added in Step 3.

///|
pub fn call_clobbered_gprs() -> Array[@abi.PReg] {
  // SysV AMD64: caller-saved GPRs.
  //
  // We use the 0..15 numbering described in `vcode/isa/x86_64/roles.mbt`.
  [
    { index: 0, class: @abi.Int }, // rax
    { index: 1, class: @abi.Int }, // rcx
    { index: 2, class: @abi.Int }, // rdx
    { index: 6, class: @abi.Int }, // rsi
    { index: 7, class: @abi.Int }, // rdi
    { index: 8, class: @abi.Int }, // r8
    { index: 9, class: @abi.Int }, // r9
    { index: 10, class: @abi.Int }, // r10
    { index: 11, class: @abi.Int },
  ] // r11
}

///|
pub fn call_clobbered_fprs() -> Array[@abi.PReg] {
  // SysV AMD64: all XMM registers are caller-saved.
  let regs : Array[@abi.PReg] = []
  for i in 0..<16 {
    regs.push({ index: i, class: @abi.Float64 })
  }
  regs
}

///|
pub fn call_clobbered_fprs_same_abi() -> Array[@abi.PReg] {
  // SysV has no callee-saved XMM registers, even for internal calls.
  call_clobbered_fprs()
}
