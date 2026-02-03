///|
/// Mapping from ISA-independent roles to concrete AArch64 physical registers.
///
/// This isolates AArch64-specific register choices in one place.

///|
pub fn int_reg_index(role : @spec.IntRegRole) -> Int {
  match role {
    Vmctx => @abi.REG_VMCTX
    Mem0Desc => @abi.REG_MEM0_DESC
    FuncTable => @abi.REG_FUNC_TABLE
    // Wasmoon uses X23 for the extra results pointer buffer.
    ExtraResultsPtr => 23
    Scratch1 => @abi.SCRATCH_REG_1
    Scratch2 => @abi.SCRATCH_REG_2
    FP => @abi.REG_FP
    LR => @abi.REG_LR
    SRet => @abi.REG_SRET
  }
}
