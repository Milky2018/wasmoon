///|
fn role_to_target(role : @spec.IntRegRole) -> @aarch64_target.IntRegRole {
  match role {
    Vmctx => Vmctx
    Mem0Desc => Mem0Desc
    FuncTable => FuncTable
    ExtraResultsPtr => ExtraResultsPtr
    Scratch1 => Scratch1
    Scratch2 => Scratch2
    FP => FP
    LR => LR
    SRet => SRet
  }
}

///|
pub fn int_reg_index(role : @spec.IntRegRole) -> Int {
  @aarch64_target.int_reg_index(role_to_target(role))
}
