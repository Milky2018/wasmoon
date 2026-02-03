///|
/// AArch64 ABI/ISA policy (AAPCS64 / Apple ARM64).
///
/// These helpers are extracted from `vcode/abi/abi.mbt` so other parts of the
/// JIT backend can depend on `vcode/isa` instead of hardcoding AArch64.

///|
pub fn aapcs64_arg_gprs() -> Array[@abi.PReg] {
  [
    { index: 0, class: @abi.Int },
    { index: 1, class: @abi.Int },
    { index: 2, class: @abi.Int },
    { index: 3, class: @abi.Int },
    { index: 4, class: @abi.Int },
    { index: 5, class: @abi.Int },
    { index: 6, class: @abi.Int },
    { index: 7, class: @abi.Int },
  ]
}

///|
pub fn aapcs64_ret_gprs() -> Array[@abi.PReg] {
  [
    { index: 0, class: @abi.Int },
    { index: 1, class: @abi.Int },
    { index: 2, class: @abi.Int },
    { index: 3, class: @abi.Int },
    { index: 4, class: @abi.Int },
    { index: 5, class: @abi.Int },
    { index: 6, class: @abi.Int },
    { index: 7, class: @abi.Int },
  ]
}

///|
pub fn aapcs64_callee_saved() -> Array[@abi.PReg] {
  [
    { index: 19, class: @abi.Int },
    { index: 20, class: @abi.Int },
    { index: 21, class: @abi.Int },
    { index: 22, class: @abi.Int },
    { index: 23, class: @abi.Int },
    { index: 24, class: @abi.Int },
    { index: 25, class: @abi.Int },
    { index: 26, class: @abi.Int },
    { index: 27, class: @abi.Int },
    { index: 28, class: @abi.Int },
    { index: 29, class: @abi.Int }, // fp
    { index: 30, class: @abi.Int },
  ] // lr
}

///|
/// Scratch registers available for allocation (caller-saved, no save/restore needed).
/// We keep X16/X17 reserved for internal emission and indirect calls.
pub fn allocatable_scratch_regs() -> Array[@abi.PReg] {
  [
    { index: 0, class: @abi.Int },
    { index: 1, class: @abi.Int },
    { index: 2, class: @abi.Int },
    { index: 3, class: @abi.Int },
    { index: 4, class: @abi.Int },
    { index: 5, class: @abi.Int },
    { index: 6, class: @abi.Int },
    { index: 7, class: @abi.Int },
    { index: 8, class: @abi.Int },
    { index: 9, class: @abi.Int },
    { index: 10, class: @abi.Int },
    { index: 11, class: @abi.Int },
    { index: 12, class: @abi.Int },
    { index: 13, class: @abi.Int },
    { index: 14, class: @abi.Int },
    { index: 15, class: @abi.Int },
  ]
}

///|
/// Allocatable callee-saved registers.
///
/// When pinned-reg mode is enabled, `@abi.REG_VMCTX` must not be allocated.
pub fn allocatable_callee_saved_regs(
  enable_pinned_reg? : Bool = true,
) -> Array[@abi.PReg] {
  let regs : Array[@abi.PReg] = []
  for r in aapcs64_callee_saved() {
    // x29/x30 are fp/lr: allocator never uses them; keep them out.
    if r.index == @abi.REG_FP || r.index == @abi.REG_LR {
      continue
    }
    if enable_pinned_reg && r.index == @abi.REG_VMCTX {
      continue
    }
    regs.push(r)
  }
  regs
}

///|
/// AAPCS64 floating-point parameter regs (V0-V7).
pub fn aapcs64_arg_fprs() -> Array[@abi.PReg] {
  [
    { index: 0, class: @abi.Float64 },
    { index: 1, class: @abi.Float64 },
    { index: 2, class: @abi.Float64 },
    { index: 3, class: @abi.Float64 },
    { index: 4, class: @abi.Float64 },
    { index: 5, class: @abi.Float64 },
    { index: 6, class: @abi.Float64 },
    { index: 7, class: @abi.Float64 },
  ]
}

///|
pub fn aapcs64_ret_fprs() -> Array[@abi.PReg] {
  [
    { index: 0, class: @abi.Float64 },
    { index: 1, class: @abi.Float64 },
    { index: 2, class: @abi.Float64 },
    { index: 3, class: @abi.Float64 },
    { index: 4, class: @abi.Float64 },
    { index: 5, class: @abi.Float64 },
    { index: 6, class: @abi.Float64 },
    { index: 7, class: @abi.Float64 },
  ]
}

///|
/// Callee-saved FPRs (V8-V15).
pub fn callee_saved_fprs() -> Array[@abi.PReg] {
  [
    { index: 8, class: @abi.Float64 },
    { index: 9, class: @abi.Float64 },
    { index: 10, class: @abi.Float64 },
    { index: 11, class: @abi.Float64 },
    { index: 12, class: @abi.Float64 },
    { index: 13, class: @abi.Float64 },
    { index: 14, class: @abi.Float64 },
    { index: 15, class: @abi.Float64 },
  ]
}

///|
/// Allocatable floating-point registers (caller-saved, no save/restore needed).
/// V16-V31 are available for allocation. (V16/V17 are reserved scratch in Wasmoon.)
pub fn allocatable_scratch_fprs() -> Array[@abi.PReg] {
  [
    { index: 16, class: @abi.Float64 },
    { index: 17, class: @abi.Float64 },
    { index: 18, class: @abi.Float64 },
    { index: 19, class: @abi.Float64 },
    { index: 20, class: @abi.Float64 },
    { index: 21, class: @abi.Float64 },
    { index: 22, class: @abi.Float64 },
    { index: 23, class: @abi.Float64 },
    { index: 24, class: @abi.Float64 },
    { index: 25, class: @abi.Float64 },
    { index: 26, class: @abi.Float64 },
    { index: 27, class: @abi.Float64 },
    { index: 28, class: @abi.Float64 },
    { index: 29, class: @abi.Float64 },
    { index: 30, class: @abi.Float64 },
    { index: 31, class: @abi.Float64 },
  ]
}

///|
/// Registers clobbered by function calls (caller-saved).
/// AArch64: X0-X17.
pub fn call_clobbered_gprs() -> Array[@abi.PReg] {
  [
    { index: 0, class: @abi.Int },
    { index: 1, class: @abi.Int },
    { index: 2, class: @abi.Int },
    { index: 3, class: @abi.Int },
    { index: 4, class: @abi.Int },
    { index: 5, class: @abi.Int },
    { index: 6, class: @abi.Int },
    { index: 7, class: @abi.Int },
    { index: 8, class: @abi.Int },
    { index: 9, class: @abi.Int },
    { index: 10, class: @abi.Int },
    { index: 11, class: @abi.Int },
    { index: 12, class: @abi.Int },
    { index: 13, class: @abi.Int },
    { index: 14, class: @abi.Int },
    { index: 15, class: @abi.Int },
    { index: 16, class: @abi.Int },
    { index: 17, class: @abi.Int },
  ]
}

///|
/// For C calls, be conservative: clobber all V0-V31.
pub fn call_clobbered_fprs() -> Array[@abi.PReg] {
  let regs : Array[@abi.PReg] = []
  for i in 0..<32 {
    regs.push({ index: i, class: @abi.Float64 })
  }
  regs
}

///|
/// For Wasm-to-Wasm calls (same ABI), treat V8-V15 as callee-saved (low 64 bits).
pub fn call_clobbered_fprs_same_abi() -> Array[@abi.PReg] {
  let regs : Array[@abi.PReg] = []
  for i in 0..<32 {
    if i >= 8 && i <= 15 {
      continue
    }
    regs.push({ index: i, class: @abi.Float64 })
  }
  regs
}
