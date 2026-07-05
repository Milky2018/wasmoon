///|
/// Mapping from ISA-independent roles to concrete AArch64 physical registers.
///
/// This isolates AArch64-specific register choices in one place.

///|
pub fn int_reg_index(role : @spec.IntRegRole) -> Int {
  match role {
    Vmctx => 21
    Mem0Desc => 20
    FuncTable => 19
    // Wasmoon uses X23 for the extra results pointer buffer.
    ExtraResultsPtr => 23
    Scratch1 => 16
    Scratch2 => 17
    FP => 29
    LR => 30
    SRet => 8
  }
}
