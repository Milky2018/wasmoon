///|
fn reg_num(reg : @abi.Reg) -> Int {
  match reg {
    Physical(preg) => preg.index
    Virtual(_) => abort("virtual register in legacy AMD64 emission")
  }
}

///|
fn wreg_num(wreg : @abi.Writable) -> Int {
  reg_num(wreg.reg)
}
