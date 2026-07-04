///|
/// amd64 role mapping stub.
///
/// SysV AMD64 register assignment for Wasmoon's JIT backend.

///|
pub fn int_reg_index(_role : @spec.IntRegRole) -> Int {
  match _role {
    Vmctx => @x64_target.int_reg_index(Vmctx)
    Mem0Desc => @x64_target.int_reg_index(Mem0Desc)
    FuncTable => @x64_target.int_reg_index(FuncTable)
    ExtraResultsPtr => @x64_target.int_reg_index(ExtraResultsPtr)
    Scratch1 => @x64_target.int_reg_index(Scratch1)
    Scratch2 => @x64_target.int_reg_index(Scratch2)
    FP => @x64_target.int_reg_index(FP)
    LR => @x64_target.int_reg_index(LR)
    SRet => @x64_target.int_reg_index(SRet)
  }
}
