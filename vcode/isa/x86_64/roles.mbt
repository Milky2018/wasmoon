///|
/// x86_64 role mapping stub.
///
/// SysV AMD64 register assignment for Wasmoon's JIT backend.

///|
pub fn int_reg_index(_role : @spec.IntRegRole) -> Int {
  // We encode x86_64 GPRs using the common 0..15 numbering:
  //   0: rax  1: rcx  2: rdx  3: rbx
  //   4: rsp  5: rbp  6: rsi  7: rdi
  //   8: r8   9: r9  10: r10 11: r11
  //  12: r12 13: r13 14: r14 15: r15
  match _role {
    // Prefer callee-saved registers for pinned/cached pointers.
    Vmctx => 14 // r14
    Mem0Desc => 15 // r15
    FuncTable => 13 // r13
    ExtraResultsPtr => 12 // r12
    // Reserve two caller-saved scratch regs for lowering/emission.
    Scratch1 => 10 // r10
    Scratch2 => 11 // r11
    // Frame pointer (optional; we use rbp when enabled).
    FP => 5 // rbp
    // x86_64 has no link register; use a dummy value (rbp) to avoid
    // accidentally introducing a real allocatable register dependency.
    LR => 5
    // SysV uses RDI for sret (hidden first argument).
    SRet => 7 // rdi
  }
}
